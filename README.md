##########################################################################################################

How to setup a hadoop and zookeeper cluster with multiple nodes from scratch?

################################################################################
1. Fill the nodes information in config/cluster_settings.json including the cluster nodes, user and group;
2. In each node, use root to run  "deploy_monitor_cluster.sh account"  to create account including new user and group;
3. In hadoop master node and hbase master node, use the new user to run "deploy_monitor_cluster.sh ssh"  to create ssh logon without password among all nodes;
4. In hadoop master node, use the new user to run "sudo deploy_monitor_cluster.sh install_hadoop" to set up hadoop cluster;
5. In hadoop master node, use the new user to run "sudo deploy_monitor_cluster.sh install_zookeeper" to set up zookeeper cluster
5. In hadoop master node, use the new user to run "deploy_monitor_cluster.sh start" to start up the hadoop and zookeeper cluster;
6. If you want to stop the clusters, use the new user to run "deploy_monitor_cluster.sh stop" to stop the hadoop and zookeeper cluster;
