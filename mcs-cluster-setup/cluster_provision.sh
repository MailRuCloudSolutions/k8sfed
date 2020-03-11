#!/bin/bash

set -eux

openstack_token=$(openstack token issue -c id -f value)

openstack keypair show $mcs_keypair || openstack keypair create -f value $mcs_keypair > ./k8s-fed_id_rsa

CLUSTER_NAME="mcs-cluster-$RAND_PART"

cluster_payload=$(cat << EOF
{
    "cluster_template_id": "a6b541da-c3fa-420a-9cb9-29a34b7ec2c9",
    "flavor_id": "Standard-2-4-40",
    "keypair": "$mcs_keypair",
    "master_count": 1,
    "master_flavor_id": "Standard-2-4-40",
    "name": "$CLUSTER_NAME",
    "node_groups": [{
        "name": "default",
        "node_count": 1
    }],
    "labels": {
        "cluster_node_volume_type": "dp1-ssd",
        "heapster_enabled": false,
        "influx_grafana_dashboard_enabled": false,
        "prometheus_monitoring": false,
        "fixed_network": "$2",
        "fixed_subnet": "$3"
    }
}
EOF
)

create_cluster() {
    echo $(curl -s -g -X POST -d "$cluster_payload" https://infra.mail.ru:9511/v1/clusters -H "Accept: application/json" -H "Content-Type: application/json" -H "X-Auth-Token: $1" | python -c "import sys, json; print(    json.load(sys.stdin)['uuid'])")
}

get_cluster_status() {
    echo $(curl -s -g -X GET https://infra.mail.ru:9511/v1/clusters/$2 -H "Accept: application/json" -H "Content-Type: application/json" -H "X-Auth-Token: $1" |  python -c "import sys, json; print(json.load(sys.stdin)['status'])")
}

wait_for_create() {
    i=0
    while [ $i -le 120 ]
    do
        i=$(( $i + 1 ))
        cluster_status=$(get_cluster_status $1 $2)
        if [ "$cluster_status" = "CREATE_COMPLETE" ]; then
            break
        elif [ "$cluster_status" = "CREATE_FAILED" ]; then
            echo ERROR: failed to create cluster
            exit 1
        fi
        echo Cluster status is $cluster_status
        sleep 30
    done
}

write_cluster_kubeconfig () {
    curl -s -g -X GET https://infra.mail.ru:9511/v1/clusters/$2/kube_config -H "Content-Type: application/json" -H "X-Auth-Token: $1" > $3
}

provision_cluster() {
    echo Acquiring token...
    openstack_token=$(openstack token issue -c id -f value)
    echo Creating cluster with payload $cluster_payload
    cluster_uuid=$(create_cluster $openstack_token)
    echo Created cluster with uuid $cluster_uuid
    wait_for_create $openstack_token $cluster_uuid
    echo Downloading kubeconfig file into $1
    write_cluster_kubeconfig $openstack_token $cluster_uuid $1
}

provision_cluster $1
