#!/bin/bash

function get_local_ip() {

    local network_interface=`ifconfig -s | awk '$1 ~ /^eth/ {print $1; exit;}'`
    if [ -z $network_interface ]; then
        network_interface=`ifconfig -s | awk '$1 ~ /^ens/ {print $1; exit;}'`
    fi

    local ip_addr=`ifconfig ${network_interface}| grep 'inet addr' | sed 's/inet addr:\([\.0-9]\{1,\}\).*/\1/g'`

    echo $ip_addr
}

function deploy_cluster() {

    local cur_dir=$(pwd)
    local local_ip=`get_local_ip`
    local action=$1

    if [ $# = 0 ];then
        ${cur_dir}/create_monitor_cluster.sh
        exit
    fi

    if [ $action = "account" ] || [ $action = "ssh" ] || [ $action = "help" ]; then
        ${cur_dir}/create_monitor_cluster.sh $action $cur_dir
    else
        local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`

        for key in ${keys[*]}; do
            host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
            host_ip=`echo $host_ip | sed 's/\"//g'`

            if [ $local_ip = $host_ip ]; then
                ${cur_dir}/create_monitor_cluster.sh $action $cur_dir
            else
                ssh $host_ip "${cur_dir}/create_monitor_cluster.sh $action $cur_dir"
            fi
        done
    fi
}

deploy_cluster $1
