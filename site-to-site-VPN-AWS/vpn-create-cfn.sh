#!/bin/bash
set -e

ip1=$1
cidr2=$2
filename=$3
vpnconnid_path=$4
aws_region=$5
stackname="aws-mcs-kubfed-vpn"

# Fetching newly created VPC ID based on tags 
vpcid=$(aws ec2 describe-vpcs --region=$aws_region --filters Name=tag:Name,Values="cdk-py/EKSVpc" --query 'Vpcs[0].VpcId' | jq -r .)

# Fetching newly created routing tables. We will need these to update them with static route from MCS side
rtids=$(aws ec2 describe-route-tables --region=$aws_region --filters "Name=vpc-id,Values=$vpcid" "Name=tag:aws:cloudformation:stack-name, Values=cdk-py" --query 'RouteTables[].RouteTableId' | jq -r 'join(",")')

echo 'We have vpcid:$vpcid and rtids:$rtids'
echo "Input params: ip:$ip1, cidr:$cidr2, filename:$filename"

# Deploy cloudformation stack with all AWS resources: VPN Gateway, VPN Customer Gateway, VPN Site-site connection and etc
aws cloudformation deploy --region=$aws_region --template-file site-to-site-VPN-AWS/VPC-VPN-site2site.yaml --stack-name $stackname --parameter-overrides HomeIP=$ip1 ExtRouteCIDR=$cidr2 VpcId=$vpcid RouteTableIds=$rtids --tags KubeFed=True
echo 'Yaml with VPN gateway, Customer Gateway, VPN connection created'

# Fetching VPNconnectionId from cloudformation stack results
VpnConnectionID=$(aws cloudformation describe-stacks --region=$aws_region --stack-name $stackname |  jq -r '.Stacks[0].Outputs[] | select(.OutputKey == "VPNGatewayId") | .OutputValue')
echo 'We have VpnConnection ID: $VpnConnectionID'
echo $VpnConnectionID > $vpnconnid_path

# Fetching xml config for newly created VPN connection that should be providede to MCS side
aws ec2 describe-vpn-connections --region=$aws_region --vpn-connection-id $VpnConnectionID | jq -r '.VpnConnections[0].CustomerGatewayConfiguration' > $filename
echo 'File with vpn configuration created and saved'
echo 'Everything is created and prepaired on AWS side for VPN connection!'