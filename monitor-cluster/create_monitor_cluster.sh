#!/bin/bash
if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi
export PATH=$PATH:/usr/local/jdk1.8.0_211/bin 

function add_account() {
    local cur_dir=$1
    echo $cur_dir

    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local group=`jq '.account.group' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    echo "user is $user"
    echo "group is $group"

    #add group
    grep "${group}:" /etc/group >& /dev/null
    if [ $? -ne 0 ]; then
        groupadd $group
    else
        echo "$group exist!"
    fi

    #add group into sudoer
    egrep "%${group}" /etc/sudoers >& /dev/null
    if [ $? -ne 0 ]; then
        echo "%${group} ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers
    fi

    #add user into sudo and the new group
    grep "${user}:" /etc/passwd >& /dev/null
    if [ $? = 0 ]; then
        echo "${user} exist!"
        usermod -a -G $group $user
        #usermod -a -G sudo $user
    else
        #adduser --shell /bin/bash --ingroup $group $user
        adduser --shell /bin/bash -g $group $user
        #usermod -a -G sudo $user

        echo "$user created!"
    fi

    egrep "#path for sbin" /home/${user}/.bashrc >& /dev/null
    if [ $? -ne 0 ]; then
        echo "#path for sbin" >> /home/${user}/.bashrc
        echo "export PATH=\$PATH:/sbin:/usr/sbin" >> /home/${user}/.bashrc
    fi
}


function install_java() {

    local cur_dir=$1
    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

    egrep "JAVA_HOME" /home/${user}/.bashrc >& /dev/null
    if [ $? -ne 0 ]
    then
        echo "#Java Variables" >> /home/${user}/.bashrc
        local javac_path=`which javac`
        local jvm_path=`readlink -f $javac_path`
        echo "export JAVA_HOME=${jvm_path%/bin/javac}" >> /home/${user}/.bashrc
        echo "export CLASSPATH=.:$JAVA_HOME/lib/dt.jar:$JAVA_HOME/lib/tools.jar" >> /home/${user}/.bashrc
    fi
}

function set_hostname() {
    local cur_dir=$1

    egrep "monitor backend" /etc/hosts >& /dev/null
    if [ $? -ne 0 ]; then
        jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json | while read key; do
            host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
            host_name=$(jq ".hosts[$key].name" ${cur_dir}/config/cluster_settings.json)

            host_ip=`echo $host_ip | sed 's/\"//g'`
            host_name=`echo $host_name | sed 's/\"//g'`
            #according to https://wiki.apache.org/hadoop/UnknownHost, FQDN must include a trailing dot.
            sed -i "1i\\${host_ip}  ${host_name} ${host_name}." /etc/hosts
        done

        sed -i "1i\### monitor backend servers ###" /etc/hosts
    fi
}

function get_local_ip() {

    local network_interface=`ifconfig -s | awk '$1 ~ /^eth/ {print $1; exit;}'`
    if [ -z $network_interface ]; then
        #please adjust your network interface
        network_interface=`ifconfig -s | awk '$1 ~ /^ens/ {print $1; exit;}'`
    fi

    local ip_addr=`ifconfig ${network_interface}| grep 'inet ' | sed 's/inet \([\.0-9]\{1,\}\).*/\1/g' | grep -v '127.0.0.1'`

    echo $ip_addr
}

function get_java_name() {

    local javac_path=`which javac`
    local jvm_path=`readlink -f $javac_path`

    local trim_left_path=${jvm_path#/usr/lib/jvm/}

    echo ${trim_left_path%/bin/javac}
}


function get_local_hostname() {

    local ip_addr=`get_local_ip`
    local cur_dir=$1

    local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`
    for key in ${keys[*]}; do
        host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
        host_ip=`echo $host_ip | sed 's/\"//g'`

        if [ $ip_addr = $host_ip ]; then
            host_name=$(jq ".hosts[$key].name" ${cur_dir}/config/cluster_settings.json)
            host_name=`echo $host_name | sed 's/\"//g'`
            break
        fi
    done

    echo $host_name
}

function get_host_ip() {

    local host_ip=""
    local cur_dir=$1

    local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`

    for key in ${keys[*]}; do
        hostname=$(jq ".hosts[$key].name" ${cur_dir}/config/cluster_settings.json)
        hostname=`echo $hostname | sed 's/\"//g'`

        if [ $hostname = $2 ]; then
            host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
            host_ip=`echo $host_ip | sed 's/\"//g'`
            break
        fi
    done

    echo $host_ip
}


function is_master() {

    local ip_addr=`get_local_ip`
    local cur_dir=$1
    #the function parameter is cluster type, e.g., ntp_cluster, hadoop_cluster, hbase_cluster and spark_cluster
    local cluster_type=$2

    local master_name=`jq ".${cluster_type}.master" ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`

    for key in ${keys[*]}; do
        host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
        host_ip=`echo $host_ip | sed 's/\"//g'`

        if [ $ip_addr = $host_ip ]; then
            host_name=$(jq ".hosts[$key].name" ${cur_dir}/config/cluster_settings.json)
            host_name=`echo $host_name | sed 's/\"//g'`

            if [ $host_name = $master_name ]; then
                return 1
            fi
        fi
    done

    return 0
}


function is_node_of_cluster() {

    local cur_dir=$1
    local host_name=`get_local_hostname $cur_dir`
    #the function parameter is cluster type, e.g., ntp_cluster, hadoop_cluster, hbase_cluster and zookeeper_cluster
    local cluster_type=$2

    if [ $cluster_type = "zookeeper_cluster" ]; then
        local keys=`jq -r ".zookeeper_cluster|keys[]" ${cur_dir}/config/cluster_settings.json`

        for key in ${keys[*]}; do
            host=$(jq ".zookeeper_cluster[$key].host" ${cur_dir}/config/cluster_settings.json)
            host=`echo $host | sed 's/\"//g'`

            if [ $host_name = $host ]; then
                return 1
            fi
        done
    elif [ $cluster_type = "opentsdb_cluster" ]; then
        local keys=`jq -r ".opentsdb_cluster|keys[]" ${cur_dir}/config/cluster_settings.json`

        for key in ${keys[*]}; do
            host=$(jq ".opentsdb_cluster[$key]" ${cur_dir}/config/cluster_settings.json)
            host=`echo $host | sed 's/\"//g'`

            if [ $host_name = $host ]; then
                return 1
            fi
        done
    else
        local master_name=`jq ".${cluster_type}.master" ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
        if [ $host_name = $master_name ]; then
            return 1
        fi

        local keys=`jq -r ".${cluster_type}.slaves|keys[]" ${cur_dir}/config/cluster_settings.json`

        for key in ${keys[*]}; do
            host=$(jq ".${cluster_type}.slaves[$key]" ${cur_dir}/config/cluster_settings.json)
            host=`echo $host | sed 's/\"//g'`

            if [ $host_name = $host ]; then
                return 1
            fi
        done
    fi

    return 0
}


function set_ssh_logon() {

    local ip_addr=`get_local_ip`
    local cur_dir=$1

    local hosts=()
    local index=0
    local host_ip host_name local_hostname
    local keys=`jq -r '.hosts|keys[]' ${cur_dir}/config/cluster_settings.json`

    for key in ${keys[*]}; do
        host_ip=$(jq ".hosts[$key].ip" ${cur_dir}/config/cluster_settings.json)
        host_name=$(jq ".hosts[$key].name" ${cur_dir}/config/cluster_settings.json)

        host_ip=`echo $host_ip | sed 's/\"//g'`
        host_name=`echo $host_name | sed 's/\"//g'`

        echo $ip_addr
        echo $host_ip

        if [ $ip_addr != $host_ip ]; then
            hosts[$index]=$host_name
            index=$(($index + 1))
        else
            local_hostname=$host_name
        fi
    done

    if [ $index = ${#keys[*]} ]; then
        echo "The local ip is $ip_addr,  cannot find matched host in the config"
        exit 1
    fi

    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    ssh-keygen -t rsa -P ''


    for host in ${hosts[*]}; do
        ssh-copy-id -i /home/${user}/.ssh/id_rsa.pub ${user}@${host}
    done

    ssh-copy-id -i /home/${user}/.ssh/id_rsa.pub ${user}@${local_hostname}
}


function check_account() {

    local cur_dir=$1
    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local group=`jq '.account.group' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

    if [ ! `grep "${group}:" /etc/group` ] && [ ! `grep "${user}:" /etc/passwd` ];then
        echo "Please run create_monitor_cluser.sh -a  to create account firstly"
        exit 1
    fi
}


function set_ntp_cluster() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir ntp_cluster
    if [ $? = 0 ]; then
        return
    fi

    local timezone=`jq '.ntp_cluster.timezone' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    if [ $timezone ]; then
        cp $timezone /etc/localtime
    fi
    apt-get install ntp
    apt-get install ntpdate

    is_master $cur_dir ntp_cluster
    if [ $? = 1 ] ;then
        egrep "#ntp cluster for monitoring" /etc/ntp.conf >& /dev/null
        if [ $? -ne 0 ]; then
            sed -i '/pool [0-9]\{1,\}\.ubuntu.pool.ntp.org/s/^/#&/' /etc/ntp.conf
            sed -i '/pool ntp.ubuntu.com/i\#ntp cluster for monitoring' /etc/ntp.conf
            sed -i '/pool ntp.ubuntu.com/s/^/#&/' /etc/ntp.conf
            sed -i '/#pool ntp.ubuntu.com/a\server 0.cn.pool.ntp.org' /etc/ntp.conf
            sed -i '/server 0.cn.pool.ntp.org/a\server 1.cn.pool.ntp.org' /etc/ntp.conf
            sed -i '/server 1.cn.pool.ntp.org/a\server 127.127.1.0 minpoll 4 maxpoll 5' /etc/ntp.conf
            sed -i '/server 127.127.1.0 minpoll 4 maxpoll 5/a\fudge 127.127.1.0 stratum 2' /etc/ntp.conf
        fi
        /etc/init.d/ntp restart

        updated=1

        while [ $updated -ne 0 ]; do
            sleep 5
            ntpdate -q 127.0.0.1 | egrep "adjust time server 127.0.0.1" >& /dev/null
            updated=$?
            echo "updated is $updated"
	    done
    else
        /etc/init.d/ntp stop
        local ntp_master=`jq '.ntp_cluster.master' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

        updated=1

        while [ $updated -ne 0 ]; do
            sleep 5
            ntpdate $ntp_master | egrep "adjust time server" >& /dev/null
            updated=$?
            echo "updated is $updated"
        done

        cp ${cur_dir}/config/ntp/ntp-updater /etc/cron.d/
        sed -i "s/<.*>/${ntp_master}/" /etc/cron.d/ntp-updater
    fi
}

function set_hadoop() {

    local cur_dir=$1
    echo $cur_dir

    is_node_of_cluster $cur_dir hadoop_cluster
    if [ $? = 0 ]; then
        return
    fi

    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local install_path_for_sed=${install_path//\//\\\/}
    local hadoop_master=`jq '.hadoop_cluster.master' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local resource_manager=`jq '.hadoop_cluster.resource_manager' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

    local java_home=`get_java_name`
    echo $java_home
    java_home=${java_home//\//\\\/}

    cp ${cur_dir}/config/hadoop/hadoop-env.sh ${install_path}/hadoop/etc/hadoop/hadoop-env.sh

    echo "$java_home"
    sed -i "s/\%java_home\%/${java_home}/" ${install_path}/hadoop/etc/hadoop/hadoop-env.sh


    cp ${cur_dir}/config/hadoop/core-site.xml ${install_path}/hadoop/etc/hadoop/
    sed -i "s/\%hadoop_master\%/${hadoop_master}/" ${install_path}/hadoop/etc/hadoop/core-site.xml
    sed -i "s/\%install_path\%/${install_path_for_sed}/" ${install_path}/hadoop/etc/hadoop/core-site.xml

    cp ${cur_dir}/config/hadoop/hdfs-site.xml ${install_path}/hadoop/etc/hadoop/
    sed -i "s/\%install_path\%/${install_path_for_sed}/" ${install_path}/hadoop/etc/hadoop/hdfs-site.xml
    local slaves=`jq -r '.hadoop_cluster.slaves|keys[]' ${cur_dir}/config/cluster_settings.json`

    slave_num=`jq '.hadoop_cluster.replicate_num' ${cur_dir}/config/cluster_settings.json`
    if [ $slave_num = null ]; then
       slave_num=0
       for i in ${slaves[*]}; do
          slave_num=$(($slave_num + 1))
       done
    fi

    sed -i "s/\%replication_number\%/${slave_num}/" ${install_path}/hadoop/etc/hadoop/hdfs-site.xml
    sed -i "s/\%hadoop_master\%/${hadoop_master}/" ${install_path}/hadoop/etc/hadoop/hdfs-site.xml

    cp ${cur_dir}/config/hadoop/mapred-site.xml ${install_path}/hadoop/etc/hadoop/
    sed -i "s/\%hadoop_master\%/${hadoop_master}/" ${install_path}/hadoop/etc/hadoop/mapred-site.xml

    cp ${cur_dir}/config/hadoop/yarn-site.xml ${install_path}/hadoop/etc/hadoop/
    sed -i "s/\%hadoop_master\%/${hadoop_master}/" ${install_path}/hadoop/etc/hadoop/yarn-site.xml
    sed -i "s/\%resource_manager\%/${resource_manager}/" ${install_path}/hadoop/etc/hadoop/yarn-site.xml

    if [ -f "${cur_dir}/config/hadoop/slaves" ]; then
        rm -f ${cur_dir}/config/hadoop/slaves
    fi

    for i in ${slaves[*]}; do
        slave=$(jq ".hadoop_cluster.slaves[$i]" ${cur_dir}/config/cluster_settings.json)
        slave=`echo $slave | sed 's/\"//g'`
        echo -e "${slave}" >> ${cur_dir}/config/hadoop/slaves
    done

    cp ${cur_dir}/config/hadoop/slaves ${install_path}/hadoop/etc/hadoop/workers

    is_master $cur_dir hadoop_cluster
    if [ $? = 1 ]; then
        if [ -d "${install_path}/hadoop/hadoop_data/hdfs/namenode" ]; then
            rm -rf ${install_path}/hadoop/hadoop_data/hdfs/namenode
        fi
        mkdir -p ${install_path}/hadoop/hadoop_data/hdfs/namenode
    fi

    if [ -d "${install_path}/hadoop/hadoop_data/hdfs/datanode" ]; then
        rm -rf ${install_path}/hadoop/hadoop_data/hdfs/datanode
    fi
    mkdir -p ${install_path}/hadoop/hadoop_data/hdfs/datanode

    if [ -f "${install_path}/hadoop/etc/hadoop/masters" ]; then
        rm -f ${install_path}/hadoop/etc/hadoop/masters
    fi
    local secondary_master=`jq '.hadoop_cluster.secondary_master' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    if [ $secondary_master ]; then
        sed -i "s/\%secondary_namenode\%/${secondary_master}/" ${install_path}/hadoop/etc/hadoop/hdfs-site.xml
        #echo -e "$secondary_master" > ${install_path}/hadoop/etc/hadoop/masters
    fi

    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

    egrep "#hadoop config" /home/${user}/.bashrc >& /dev/null
    if [ $? -ne 0 ]; then
        echo "#hadoop config" >> /home/${user}/.bashrc
        local HADOOP_HOME=${install_path}/hadoop

        echo "export HADOOP_HOME=${install_path}/hadoop" >> /home/${user}/.bashrc
        echo "export PATH=\$PATH:\$HADOOP_HOME/bin" >> /home/${user}/.bashrc
        echo "export PATH=\$PATH:\$HADOOP_HOME/sbin" >> /home/${user}/.bashrc
        echo "export HADOOP_MAPRED_HOME=\$HADOOP_HOME" >> /home/${user}/.bashrc
        echo "export HADOOP_COMMON_HOME=\$HADOOP_HOME" >> /home/${user}/.bashrc
        echo "export HADOOP_HDFS_HOME=\$HADOOP_HOME" >> /home/${user}/.bashrc
        echo "export HADOOP_YARN_HOME=\$HADOOP_HOME" >> /home/${user}/.bashrc
		echo "export HADOOP_CONF_DIR=\$HADOOP_HOME/etc/hadoop" >> /home/${user}/.bashrc
        echo "export HADOOP_COMMON_LIB_NATIVE_DIR=\$HADOOP_HOME/lib/native" >> /home/${user}/.bashrc
        echo "export HADOOP_OPTS=\"-Djava.library.path=$HADOOP_HOME/lib\"" >> /home/${user}/.bashrc
    fi
}


function set_zookeeper() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir zookeeper_cluster
    if [ $? = 0 ]; then
        return
    fi

    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local group=`jq '.account.group' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local install_path_for_sed=${install_path//\//\\\/}
    local local_hostname=`get_local_hostname ${cur_dir}`

    cp ${cur_dir}/config/zookeeper/zoo.cfg ${install_path}/zookeeper/conf/
    sed -i "s/\%user\%/${user}/" ${install_path}/zookeeper/conf/zoo.cfg

    local data_path=`grep '^[[:space:]]*dataDir' ${install_path}/zookeeper/conf/zoo.cfg | sed -e 's/.*=//'`
    if [ -d $data_path ]; then
        rm -rf $data_path
    fi
    mkdir -p $data_path
    chown -R ${user}:${group} $data_path

    cp ${cur_dir}/config/zookeeper/zkEnv.sh ${install_path}/zookeeper/bin/
    sed -i "s/\%install_path\%/${install_path_for_sed}/" ${install_path}/zookeeper/bin/zkEnv.sh

    local keys=`jq -r '.zookeeper_cluster|keys[]' ${cur_dir}/config/cluster_settings.json`

    for key in ${keys[*]}; do
        local host=$(jq ".zookeeper_cluster[$key].host" ${cur_dir}/config/cluster_settings.json)
        host=`echo $host | sed 's/\"//g'`
        id=$(jq ".zookeeper_cluster[$key].id" ${cur_dir}/config/cluster_settings.json)

        local host_ip=`get_host_ip $cur_dir $host`

        echo "server.${id}=${host_ip}:2888:3888" >> ${install_path}/zookeeper/conf/zoo.cfg

        if [ $local_hostname = $host ]; then
            echo $id >> ${data_path}/myid
        fi
    done
}

function set_hbase() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir hbase_cluster
    if [ $? = 0 ]; then
        return
    fi

    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local install_path_for_sed=${install_path//\//\\\/}

    local hadoop_master=`jq '.hadoop_cluster.master' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

    local java_home=`get_java_name`
    cp ${cur_dir}/config/hbase/hbase-env.sh  ${install_path}/hbase/conf/
    sed -i "s/\%install_path\%/${install_path_for_sed}/" ${install_path}/hbase/conf/hbase-env.sh
    sed -i "s/\%java_home\%/${java_home}/" ${install_path}/hbase/conf/hbase-env.sh

    cp ${cur_dir}/config/hbase/hbase-site.xml ${install_path}/hbase/conf/
    sed -i "s/\%hadoop_master\%/${hadoop_master}/" ${install_path}/hbase/conf/hbase-site.xml

    local keys=`jq -r '.zookeeper_cluster|keys[]' ${cur_dir}/config/cluster_settings.json`
    local zookeeper_nodes=""
    for key in ${keys[*]}; do
        host=$(jq ".zookeeper_cluster[$key].host" ${cur_dir}/config/cluster_settings.json)
        host=`echo $host | sed 's/\"//g'`
        if [ $key = 0 ]; then
            zookeeper_nodes=${host}
        else
            zookeeper_nodes="${zookeeper_nodes},${host}"
        fi
    done

    sed -i "s/\%zookeeper_cluster\%/${zookeeper_nodes}/" ${install_path}/hbase/conf/hbase-site.xml
    sed -i "s/\%user\%/${user}/" ${install_path}/hbase/conf/hbase-site.xml

    if [ -f "${cur_dir}/config/hbase/regionservers" ]; then
        rm -f ${cur_dir}/config/hbase/regionservers
    fi

    local slaves=`jq -r '.hbase_cluster.slaves|keys[]' ${cur_dir}/config/cluster_settings.json`
    for i in ${slaves[*]}; do
        slave=$(jq ".hbase_cluster.slaves[$i]" ${cur_dir}/config/cluster_settings.json)
        slave=`echo $slave | sed 's/\"//g'`
        echo -e "${slave}" >> ${cur_dir}/config/hbase/regionservers
    done

    cp ${cur_dir}/config/hbase/regionservers ${install_path}/hbase/conf

    find ${install_path}/hadoop/share/hadoop/ -name "hadoop*jar" | xargs -i cp {} ${install_path}/hbase/lib/
    cp ${install_path}/hadoop/share/hadoop/tools/lib/aws-java-sdk-*.jar ${install_path}/hbase/lib/

    local secondary_master=`jq -r '.hbase_cluster.secondary_master' ${cur_dir}/config/cluster_settings.json`
    secondary_master=`echo $secondary_master | sed 's/\"//g' | sed 's/^ *\| *$//g'`
    if [ -f "${install_path}/hbase/conf/backup-masters" ]; then
        rm -f ${install_path}/hbase/conf/backup-masters
    fi

    if [ ! -z $secondary_master ]; then
        echo -e $secondary_master >> ${install_path}/hbase/conf/backup-masters
    fi

    egrep "#hbase config" /home/${user}/.bashrc >& /dev/null
    if [ $? -ne 0 ]; then
        echo "#hbase config" >> /home/${user}/.bashrc
        echo "export HBASE_HOME=${install_path}/hbase" >> /home/${user}/.bashrc
        echo "export PATH=\$PATH:\$HBASE_HOME/bin" >> /home/${user}/.bashrc
    fi
}


function set_opentsdb() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir opentsdb_cluster
    if [ $? = 0 ]; then
        return
    fi

    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local group=`jq '.account.group' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local install_path_for_sed=${install_path//\//\\\/}

    cp ${cur_dir}/config/opentsdb/opentsdb.conf ${install_path}/opentsdb/etc/opentsdb/
    sed -i "s/\%install_path\%/${install_path_for_sed}/" ${install_path}/opentsdb/etc/opentsdb/opentsdb.conf

    local keys=`jq -r '.zookeeper_cluster|keys[]' ${cur_dir}/config/cluster_settings.json`
    local zookeeper_nodes=""

    for key in ${keys[*]}; do
        host=$(jq ".zookeeper_cluster[$key].host" ${cur_dir}/config/cluster_settings.json)
        host=`echo $host | sed 's/\"//g'`
        if [ $key = 0 ]; then
            zookeeper_nodes=${host}
        else
            zookeeper_nodes="${zookeeper_nodes},${host}"
        fi
    done

    sed -i "s/\%zookeeper_cluster\%/${zookeeper_nodes}/" ${install_path}/opentsdb/etc/opentsdb/opentsdb.conf

    cp ${cur_dir}/config/opentsdb/tsdb ${install_path}/opentsdb/bin/
    sed -i "s/\%install_path\%/${install_path_for_sed}/" ${install_path}/opentsdb/bin/tsdb

    if [ -d "/var/log/opentsdb" ]; then
        rm -rf /var/log/opentsdb
    fi
    mkdir /var/log/opentsdb
    chown -R ${user}:${group} /var/log/opentsdb

    cache_file=`grep tsd.http.cachedir ${install_path}/opentsdb/etc/opentsdb/opentsdb.conf | sed 's/.*=\(.*\)/\1/'`
    if [ -d $cache_file ]; then
        rm -rf $cache_file
    fi
    mkdir -p $cache_file
    chown -R ${user}:${group} $cache_file

    egrep "#opentsdb config" /home/${user}/.bashrc >& /dev/null
    if [ $? -ne 0 ]; then
        echo "#opentsdb config" >> /home/${user}/.bashrc
        echo "export OPENTSDB_HOME=${install_path}/opentsdb" >> /home/${user}/.bashrc
        echo "export PATH=\$PATH:\$OPENTSDB_HOME/bin" >> /home/${user}/.bashrc
    fi
}

function set_install_path_permission() {

    local cur_dir=$1
    local user=`jq '.account.user' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local group=`jq '.account.group' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    chown -R ${user}:${group} $install_path
}


function start_hadoop() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir hadoop_cluster
    if [ $? = 0 ]; then
        return
    fi

    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

    local java_home=`get_java_name`
    echo $java_home

    #java_home=${java_home//\//\\\/}

	local resource_manager=`jq '.hadoop_cluster.resource_manager' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

    is_master $cur_dir hadoop_cluster

    if [ $? = 1 ]; then
        ${java_home}/bin/jps | grep NameNode
        if [ $? -ne 0 ]; then
            local num=`ls ${install_path}/hadoop/hadoop_data/hdfs/namenode/ | wc -l`
            if [ $num = 0 ]; then
                ${install_path}/hadoop/bin/hadoop namenode -format
            fi
            ${install_path}/hadoop/sbin/start-dfs.sh
			ssh $resource_manager "${install_path}/hadoop/sbin/start-yarn.sh"
            #${install_path}/hadoop/sbin/start-yarn.sh
        fi
    fi

    ${java_home}/bin/jps | grep JobHistoryServer
    if [ $? -ne 0 ]; then
		${install_path}/hadoop/sbin/mr-jobhistory-daemon.sh start historyserver
    fi
}

function stop_hadoop() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir hadoop_cluster
    if [ $? = 0 ]; then
        return
    fi

    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
	
	local resource_manager=`jq '.hadoop_cluster.resource_manager' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`

    local java_home=`get_java_name`
    echo $java_home

    is_master $cur_dir hadoop_cluster

    if [ $? = 1 ]; then
        ${java_home}/bin/jps | grep NameNode
        if [ $? = 0 ]; then
            ##${install_path}/hadoop/sbin/stop-yarn.sh
			ssh $resource_manager "${install_path}/hadoop/sbin/stop-yarn.sh"
            ${install_path}/hadoop/sbin/stop-dfs.sh
			
        fi
    fi

    ${java_home}/bin/jps | grep JobHistoryServer
    if [ $? = 0 ]; then
		${install_path}/hadoop/sbin/mr-jobhistory-daemon.sh stop historyserver
    fi
}


function start_zookeeper() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir zookeeper_cluster
    if [ $? = 0 ]; then
        return
    fi

    jps | grep QuorumPeerMain

    if [ $? -ne 0 ]; then
        local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
        ${install_path}/zookeeper/bin/zkServer.sh start
    fi
}

function check_zookeeper() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir zookeeper_cluster
    if [ $? = 0 ]; then
        return
    fi

    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    mode=`${install_path}/zookeeper/bin/zkServer.sh status | grep Mode | sed 's/Mode: \(.*\)/\1/g'`

    while [ ! $mode ] || [ $mode != "follower" -a $mode != "leader" ]; do
        sleep 1
        mode=`${install_path}/zookeeper/bin/zkServer.sh status | grep Mode | sed 's/Mode: \(.*\)/\1/g'`
    done
}

function stop_zookeeper() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir zookeeper_cluster
    if [ $? = 0 ]; then
        return
    fi

    jps | grep QuorumPeerMain

    if [ $? = 0 ]; then
        local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
        ${install_path}/zookeeper/bin/zkServer.sh stop
    fi
}

function start_hbase() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir hbase_cluster
    if [ $? = 0 ]; then
        return
    fi

    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    is_master $1 hbase_cluster

    if [ $? = 1 ]; then
        jps | grep HMaster
        if [ $? -ne 0 ]; then
            ${install_path}/hbase/bin/start-hbase.sh
        fi
    fi
}

function stop_hbase() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir hbase_cluster
    if [ $? = 0 ]; then
        return
    fi

    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    is_master $cur_dir hbase_cluster

    if [ $? = 1 ]; then
        jps | grep HMaster
        if [ $? = 0 ]; then
            ${install_path}/hbase/bin/stop-hbase.sh
        fi
    fi
}

function start_opentsdb() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir opentsdb_cluster
    if [ $? = 0 ]; then
        return
    fi

    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local local_hostname=`get_local_hostname ${cur_dir}`

    local keys=`jq -r '.opentsdb_cluster|keys[]' ${cur_dir}/config/cluster_settings.json`
    for key in ${keys[*]}; do
        local host=$(jq ".opentsdb_cluster[$key]" ${cur_dir}/config/cluster_settings.json)
        host=`echo $host | sed 's/\"//g'`

        if [ $host = $local_hostname ]; then

            echo "list" | ${install_path}/hbase/bin/hbase shell | grep tsdb
            if [ $? -ne 0 ]; then
                env COMPRESSION=NONE HBASE_HOME=${install_path}/hbase ${install_path}/opentsdb/tools/create_table.sh
            fi

            jps | grep TSDMain
            if [ $? -ne 0 ]; then
                (nohup ${install_path}/opentsdb/bin/tsdb tsd --config=${install_path}/opentsdb/etc/opentsdb/opentsdb.conf) >/dev/null 2>& 1 &
            fi
            break
        fi
    done
}

function stop_opentsdb() {

    local cur_dir=$1
    is_node_of_cluster $cur_dir opentsdb_cluster
    if [ $? = 0 ]; then
        return
    fi

    local install_path=`jq '.install_path' ${cur_dir}/config/cluster_settings.json | sed 's/\"//g'`
    local local_hostname=`get_local_hostname ${cur_dir}`

    local keys=`jq -r '.opentsdb_cluster|keys[]' ${cur_dir}/config/cluster_settings.json`
    for key in ${keys[*]}; do
        local host=$(jq ".opentsdb_cluster[$key]" ${cur_dir}/config/cluster_settings.json)
        host=`echo $host | sed 's/\"//g'`

        if [ $host = $local_hostname ]; then
            jps | grep TSDMain
            if [ $? = 0 ]; then
                local pid=`jps | grep TSDMain | awk '{print $1}'`
                kill -9 $pid
            fi
            break
        fi
    done
}


if [ $# = 0 ]; then
    echo "1st. on each node, run \"deploy_monitor_cluster.sh account\" to create account"
    echo "2nd. on hadoop master and hbase master node, run \"deploy_monitor_cluster.sh ssh\" to create ssh logon without password"
    echo "3rd. on hadoop master, run \"sudo deploy_monitor_cluster.sh install\" to install hadoop, zookeeper, hbase and opentsdb"
    echo "4th. on hadoop master, run \"deploy_monitor_cluster.sh start\" to start up hadoop, zookeeper, hbase and opentsdb"
    echo "also, on hadoop master, run \"deploy_monitor_cluster.sh stop\" to stop hadoop, zookeeper, hbase and opentsdb"
    exit
fi

# $1 is the action and $2 is the script path
case $1 in
    account)
        echo "create account"
        add_account $2
        set_hostname $2
        ulimit -n 65535
        user=`jq '.account.user' $2/config/cluster_settings.json | sed 's/\"//g'`
        su - $user
        ;;
    ssh)
        set_ssh_logon $2
        ;;
    install_hadoop)
        echo "install hadoop"
        check_account $2
        #install_java  $2
        #set_ntp_cluster $2
        set_hadoop $2
        #set_zookeeper $2
        #set_hbase $2
        #set_opentsdb $2
        set_install_path_permission $2
        ;;
	install_zookeeper)
		echo "install zookeeper"
		set_zookeeper $2
		;;
    start_zookeeper)
        echo "start zookeeper"
        start_zookeeper $2
        ;;
    check_zookeeper)
        echo "check zookeeper status"
        check_zookeeper $2
        ;;
    stop_zookeeper)
        echo "stop zookeeper"
        stop_zookeeper $2
        ;;
    start_hadoop)
        echo "start hadoop"
        start_hadoop $2
        ;;
    stop_hadoop)
        echo "stop hadoop"
        stop_hadoop $2
        ;;
    start_hbase)
        echo "start hbase"
        start_hbase $2
        ;;
    stop_hbase)
        echo "stop hbase"
        stop_hbase $2
        ;;
    start_opentsdb)
        start_opentsdb $2
        ;;
    stop_opentsdb)
        stop_opentsdb $2
        ;;
    *)
        echo "1st. on each node, run \"deploy_monitor_cluster.sh account\" to create account"
        echo "2nd. on hadoop master and hbase master node, run \"deploy_monitor_cluster.sh ssh\" to create ssh logon without password"
        echo "2nd. on hadoop master, run \"sudo deploy_monitor_cluster.sh install\" to install hadoop, zookeeper, hbase and opentsdb"
        echo "3rd. on hadoop master, run \"deploy_monitor_cluster.sh start\" to start up hadoop, hbase and opentsdb"
        echo "also, on hadoop master, run \"deploy_monitor_cluster.sh stop\" to stop hadoop, zookeeper, hbase and opentsdb"
        ;;
esac



