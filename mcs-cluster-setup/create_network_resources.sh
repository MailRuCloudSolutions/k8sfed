#!/bin/bash

set -ex

echo Creating network k8s-fed-network
export NETWORK_ID=$(openstack network create -f value -c id "k8s-fed-network-$RAND_PART")
echo Creating subnet k8s-fed-subnet
SUBNET_ID=$(openstack subnet create "k8s-fed-subnet-$RAND_PART" --network $NETWORK_ID --subnet-range $1 -f value -c id)
echo "created subnet:$SUBNET_ID"
echo Creating router k8s-fed-router
ROUTER_ID=$(openstack router create "k8s-fed-router-$RAND_PART" -f value -c id)
echo Connecting router to ext-net
openstack router set $ROUTER_ID --external-gateway ext-net
echo Connecting router to subnet
openstack router add subnet $ROUTER_ID $SUBNET_ID
echo $NETWORK_ID > $2
echo $SUBNET_ID > $3
