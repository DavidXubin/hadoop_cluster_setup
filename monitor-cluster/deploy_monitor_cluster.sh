#!/bin/bash
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

function get_local_ip() {

    local network_interface=`ifconfig -s | awk '$1 ~ /^eth/ {print $1; exit;}'`
    if [ -z $network_interface ]; then
        #please adjust your network interface
        network_interface=`ifconfig -s | awk '$1 ~ /^ens/ {print $1; exit;}'`
    fi

    local ip_addr=`ifconfig ${network_interface}| grep 'inet ' | sed 's/inet \([\.0-9]\{1,\}\).*/\1/g' | grep -v '127.0.0.1'`

    echo $ip_addr
}


function check_current_user() {

    local cur_dir=$1
    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
     if [ `whoami` != $user ]; then
        echo "Please use \"su - ${user}\"  to change account, then start/stop cluster"
        exit
    fi
}

function check_zookeeper_cluster() {

    local cur_dir=$1
    local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`

    for key in ${keys[*]}; do
        host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
        host_ip=`echo $host_ip | sed 's/\"//g'`

        if [ $local_ip = $host_ip ]; then
            ${cur_dir}/create_monitor_cluster.sh check_zookeeper $cur_dir
        else
            ssh $host_ip "source ~/.bashrc; ${cur_dir}/create_monitor_cluster.sh check_zookeeper $cur_dir"
        fi
    done
}


function start_stop_cluster() {

    local cur_dir=$1
    local action=$2
    local cluster=$3
    local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`

    for key in ${keys[*]}; do
        host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
        host_ip=`echo $host_ip | sed 's/\"//g'`

        if [ $local_ip = $host_ip ]; then
            ${cur_dir}/create_monitor_cluster.sh ${action}_${cluster} $cur_dir
        else
            ssh $host_ip "source ~/.bashrc; ${cur_dir}/create_monitor_cluster.sh ${action}_${cluster} $cur_dir"
        fi
    done
}

function install_hadoop() {

    local cur_dir=$1
    local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`

    for key in ${keys[*]}; do
        host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
        host_ip=`echo $host_ip | sed 's/\"//g'`

        if [ $local_ip = $host_ip ]; then
            ${cur_dir}/create_monitor_cluster.sh install_hadoop $cur_dir
        else
            echo $host_ip

            ssh $host_ip "source ~/.bashrc; ${cur_dir}/create_monitor_cluster.sh install_hadoop $cur_dir"
        fi
    done
}


function install_zookeeper() {

    local cur_dir=$1
    local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`

    for key in ${keys[*]}; do
        host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
        host_ip=`echo $host_ip | sed 's/\"//g'`

        if [ $local_ip = $host_ip ]; then
            ${cur_dir}/create_monitor_cluster.sh install_zookeeper $cur_dir
        else
            echo $host_ip

            ssh $host_ip "source ~/.bashrc; ${cur_dir}/create_monitor_cluster.sh install_zookeeper $cur_dir"
        fi
    done
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
    elif [ $action = "install_hadoop" ]; then
        install_cluster $cur_dir
    elif [ $action = "install_zookeeper" ]; then
        install_zookeeper $cur_dir
    else
        check_current_user $cur_dir
        if [ $action = "start" ]; then
            start_stop_cluster $cur_dir $action zookeeper
            check_zookeeper_cluster $cur_dir

            start_stop_cluster $cur_dir $action hadoop
            #start_stop_cluster $cur_dir $action hbase
            #sleep 30
            #start_stop_cluster $cur_dir $action opentsdb
        elif [ $action = "stop" ]; then
            #start_stop_cluster $cur_dir $action opentsdb
            #start_stop_cluster $cur_dir $action hbase
            start_stop_cluster $cur_dir $action hadoop
            start_stop_cluster $cur_dir $action zookeeper
        fi
    fi
}

deploy_cluster $1
