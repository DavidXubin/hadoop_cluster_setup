Current support hadoop stack version:

1.hadoop-2.8.3
2.hbase-2.1.0
3.zookeeper-3.4.12
4.hive-2.3.3
5.opentsdb-2.3.1
6.spark-2.3.1

##########################################################################################################

How to build a opentsdb cluster with multiple nodes from scratch?

1. Fill the nodes information in config/cluster_settings.json including new user and group
2. In each node, use root to run  "deploy_monitor_cluster.sh account"  to create account including new user and group
3. In hadoop master node and hbase master node, use the new user to run "deploy_monitor_cluster.sh ssh"  to create ssh logon without password
4. In hadoop master node, use the new user to run "sudo deploy_monitor_cluster.sh install" to set up all the nodes in the cluster
5. In hadoop master node, use the new user to run "deploy_monitor_cluster.sh start" to start up the cluster
