#!/bin/bash

set -ex

# CONSTANTS
IMAGE="CentOS-7.7-201910"
FLAVOR="Basic-1-2-20"

# PARAMETERS
FIP_ADDRESS=$1
NETWORK_ID=$2
SUBNET_ID=$3
PATH_TO_VPN_XML=$4
MCS_CIDR=$5
AWS_CIDR=$6
KEYPAIR_NAME=$7
KEYPAIR_PATH=$8

# KEYPAIR
echo Checking-creating keypair...
openstack keypair show $KEYPAIR_NAME || openstack keypair create -f value $KEYPAIR_NAME > $KEYPAIR_PATH

# SEC GROUP
SGROUP_ID=$(openstack security group create -f value -c id "vpnserver-sg-$RAND_PART")

openstack security group rule create -f shell -c created_at --remote-ip 0.0.0.0/0 --protocol tcp --dst-port 22 $SGROUP_ID
openstack security group rule create -f shell -c created_at --remote-ip 0.0.0.0/0 --protocol tcp --dst-port 4500 $SGROUP_ID
openstack security group rule create -f shell -c created_at --remote-ip 0.0.0.0/0 --protocol tcp --dst-port 500 $SGROUP_ID
openstack security group rule create -f shell -c created_at --remote-ip 0.0.0.0/0 --protocol icmp $SGROUP_ID

# PREPARE USERDATA
IPSEC_CONF=$(python - << EOF
import sys
import xml.etree.ElementTree as ET

tree = ET.parse('$PATH_TO_VPN_XML')
tunnels = tree.findall('ipsec_tunnel')
ipsec_conf = "config setup\n\n"
for i, t in enumerate(tunnels):
    ipsec_conf += "conn Tunnel%s\n" % i
    ipsec_conf += "    auto=start\n"
    ipsec_conf += "    left=%defaultroute\n"
    ipsec_conf += "    leftid=%s\n" % "$FIP_ADDRESS"
    ipsec_conf += "    right=%s\n" % t.find('vpn_gateway').find('tunnel_outside_address').find('ip_address').text
    ipsec_conf += "    type=tunnel\n"
    ipsec_conf += "    leftauth=psk\n"
    ipsec_conf += "    rightauth=psk\n"
    ipsec_conf += "    keyexchange=ikev1\n"
    ipsec_conf += "    ike=aes128-sha1-modp1024\n"
    ipsec_conf += "    ikelifetime=%s\n" % t.find('ike').find('lifetime').text
    ipsec_conf += "    esp=aes128-sha1-modp1024\n"
    ipsec_conf += "    lifetime=1h\n"
    ipsec_conf += "    keyingtries=%forever\n"
    ipsec_conf += "    leftsubnet=${MCS_CIDR}\n"
    ipsec_conf += "    rightsubnet=${AWS_CIDR}\n"
    ipsec_conf += "    dpddelay=10s\n"
    ipsec_conf += "    dpdtimeout=30s\n"
    ipsec_conf += "    dpdaction=restart\n"
    ipsec_conf += "\n"
    # for now we create only 1 tunnel
    break

sys.stdout.write(ipsec_conf)
EOF
)

IPSEC_SECRETS=$(python - << EOF
import sys
import xml.etree.ElementTree as ET

tree = ET.parse('$PATH_TO_VPN_XML')
tunnels = tree.findall('ipsec_tunnel')
ipsec_secrets = "# ipsec.secrets\n\n"
for t in tunnels:
    ipsec_secrets += "{} {} : PSK \"{}\"\n".format(
        "$FIP_ADDRESS",
        t.find('vpn_gateway').find('tunnel_outside_address').find('ip_address').text,
        t.find('ike').find('pre_shared_key').text
    )

sys.stdout.write(ipsec_secrets)
EOF
)

cat <<EOF > /tmp/user-data.txt
#!/bin/bash -x

# enable ip routing and disable icmp redirects
echo -e "\nnet.ipv4.ip_forward = 1\n" >> /usr/lib/sysctl.d/50-default.conf
echo -e "net.ipv4.conf.all.send_redirects = 0\n" >> /usr/lib/sysctl.d/50-default.conf
sysctl --system

# install packages
yum install -y epel-release yum-utils
yum -q makecache -y

# strongswan
yum install -y strongswan

cat <<EOT > /etc/strongswan/ipsec.conf
$IPSEC_CONF
EOT

cat <<EOT > /etc/strongswan/ipsec.secrets
$IPSEC_SECRETS
EOT

systemctl enable strongswan.service
systemctl start strongswan.service
EOF

# CREATE SERVER
SERVER_ID=$(openstack server create -f value -c id --key-name $KEYPAIR_NAME --image $IMAGE --nic "net-id=$NETWORK_ID" --flavor $FLAVOR --security-group $SGROUP_ID --user-data /tmp/user-data.txt "vpnserver-$RAND_PART")
until [ $(openstack server show -f value -c status $SERVER_ID) = "ACTIVE" ]
do
    sleep 2
done

# GET PRIVATE IP
vpnserver_private_ip=$(openstack server show -f json $SERVER_ID | python -c "import sys,json; print(json.load(sys.stdin)['addresses'].split('=')[1])")

# ATTACH IP
openstack server add floating ip $SERVER_ID $FIP_ADDRESS

# CREATE ROUTES ON DHCP
openstack subnet set --host-route "destination=${AWS_CIDR},gateway=${vpnserver_private_ip}" $SUBNET_ID

# ADD PORT PERMISSIONS
port_id=$(openstack port list -f value -c ID --server $SERVER_ID)
openstack port set --allowed-address "ip-address=${AWS_CIDR}" $port_id
