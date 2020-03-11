#!/bin/bash

set -e

echo $(openstack floating ip create -f value -c floating_ip_address ext-net)
