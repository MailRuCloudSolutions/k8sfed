#!/bin/bash

# Copyright 2020 Amazon.com, Inc. and its affiliates. All Rights Reserved.

# Licensed under the Amazon Software License (the "License").
# You may not use this file except in compliance with the License.
# A copy of the License is located at

#   http://aws.amazon.com/asl/

# or in the "license" file accompanying this file. This file is distributed
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either
# express or implied. See the License for the specific language governing
# permissions and limitations under the License.

set -ex

# Path to xaml file with aws configuration it will be autogenereated later in that script
vpn_cfg_path=/var/tmp/vpn_cfg_conn.xml

# Path to mcs_k8s config files
mcs_k8s_cfg_path=/var/tmp/mcs_k8s_cfg
mcs_netwid_path=/var/tmp/mcs_netwid_cfg
mcs_subnetid_path=/var/tmp/mcs_subnetid_cfg
mcs_keypair_path=/var/tmp/k8s-fed_id_rsa

aws_vpnconnid_path=/var/tmp/vpnconnid
aws_region=$(aws configure get region)

# CIDR Ip block on MCS side that should be added as static route on AWS side after VPN connection
# Thats CIDR block would be reserved in newly created subnet on MCS side and could be changed to anything
mcs_cidr="192.168.10.0/24"
aws_cidr="10.2.0.0/16"

# Install EKS via CDK
# All cluster init configuration located /CDK_py/cdk_py/cdk_py_stack.py
# Requirements location in requirements.txt
# @TODO: need to pass $aws_region into CDK
cd CDK_py
rm -rf .env
python3 -m venv .env
source .env/bin/activate
pip install -r requirements.txt
cdk bootstrap
cdk synth
cdk deploy --require-approval never
deactivate
cd ..

echo 'EKS created and we need to wait until it will fully provisioned for 30 sec '
sleep 30 #30 secs

# check that kubectl get nodes works and current context = awsfedclusterctx
# create .kube/config: get command from CF Output.
rm -rf ~/.kube/config #delete if already exists
runforEKSkubeconfig=$(aws cloudformation describe-stacks --stack-name cdk-py  --region=$aws_region | jq -c '.Stacks[].Outputs[] | select (.OutputKey | contains("fedclusterConfigCommand")) | .OutputValue' | jq -r .)
$runforEKSkubeconfig

# Provisining Kubefed, Tiller into AWS EKS newly created cluster
./eks-cluster-setup/eks-cluster-warmup.script

# OpenStack auto for MCS cloud (hardcoded params @TODO)
source ./openrc

# Shared variables
export RAND_PART=$(cat /dev/urandom | tr -dc 'a-z0-9' | fold -w 4 | head -n 1)

mcs_keypair="k8s-fed-$RAND_PART"

# Creating External Ip adress on MCS side that would be paired with AWS VPN Gateway
extip=$(./mcs-cluster-setup/create_extip.sh)
echo "External IP from MCS side created: $extip"
echo $extip > /var/tmp/extip

# MCS: script for extIP, subnet, k8s cluster
./mcs-cluster-setup/create_network_resources.sh $mcs_cidr $mcs_netwid_path $mcs_subnetid_path
mcs_netw_id=$(cat $mcs_netwid_path)
mcs_subid_id=$(cat $mcs_subnetid_path)

# Install AWS VPN resources (VPN Gateway, Customer Gateway and etc) to establish VPN connections
# Params:   extip - newly created on MCS side ip for VPN pairing
#           mcs_cidr - MCS CIDR IP block that is static variable for routing on AWS side
#           vpn_cfg_path - path to file that would be generated after execution for MCS side
./site-to-site-VPN-AWS/vpn-create-cfn.sh $extip $mcs_cidr $vpn_cfg_path $aws_vpnconnid_path $aws_region

#Creating virtual machine on MCS side with strongswan Ipsec VPN server and establishing connetion to AWS
./mcs-cluster-setup/vpnserver.sh $extip $mcs_netw_id $mcs_subid_id $vpn_cfg_path $mcs_cidr $aws_cidr $mcs_keypair $mcs_keypair_path

# Wait func for S2S VPN Connection is UP (AWS+MCS)
wait_for_create_vpn() {
    i=0
    while [ $i -le 30 ]
    do
        i=$(( $i + 1 ))
        VPN_conn_status=$(aws ec2 describe-vpn-connections --region=$aws_region --filters Name=vpn-connection-id,Values=$1 --query 'VpnConnections[].VgwTelemetry[].Status' | jq -r 'join(",")' )
        echo "$i: $1 VPN_conn_status: $VPN_conn_status"
        if [ -n "$(echo "$VPN_conn_status" | grep "UP")" ]
        then
            echo "VPN Conn $1 have something UP"
            break
        else
            echo "VPN Conn $1 is still DOWN"
        fi
        sleep 10
    done
}

# Checking whether VPN connection got UP eventually
vpnconnid=$(cat $aws_vpnconnid_path)
wait_for_create_vpn $vpnconnid

# Creating MCS k8s
./mcs-cluster-setup/cluster_provision.sh $mcs_k8s_cfg_path $mcs_netw_id $mcs_subid_id $mcs_keypair

# Federation
./eks-cluster-setup/eks-cluster-join-fed.script

# Configuring federation from VPN server
./exec-kubefed.py --host $extip --user centos --private-key $mcs_keypair_path --remote-path '/home/centos'

# Configuring federated resources
kubectl apply -f fed-app-example/namespace.yaml # create test NS
kubectl apply -f k8s-fed-yml-setup/federated-namespace.yaml # create Federated NS
kubectl apply -f fed-app-example/federated-nginx.yaml # federated Nginx Deployment

kubectl -n kube-federation-system get kubefedclusters

echo "Federation is up and running. Quit."
