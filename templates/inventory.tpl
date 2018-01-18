[tidb_servers]
${list_tidb}

[tikv_servers]
${list_tikv}

[pd_servers]
${list_pd}

[spark_master]
[spark_slaves]

[monitoring_servers]
${list_monitor}

[grafana_servers]
${list_monitor}

[monitored_servers:children]
tidb_servers
tikv_servers
pd_servers
spark_master
spark_slaves

## Binlog Part
[pump_servers:children]
tidb_servers

[drainer_servers]

[pd_servers:vars]
# location_labels = ["zone","rack","host"]

## Global variables
[all:vars]
deploy_dir = /home/tidb/deploy

## Connection
# ssh via root:
# ansible_user = root
# ansible_become = true
# ansible_become_user = tidb

# ssh via normal user
ansible_user = tidb

cluster_name = test-cluster

tidb_version = latest

# deployment methods, [binary, docker]
deployment_method = binary

# process supervision, [systemd, supervise]
process_supervision = systemd

# timezone of deployment region
timezone = Asia/Shanghai
set_timezone = True

# misc
enable_firewalld = False
# check NTP service
enable_ntpd = True
set_hostname = False

# binlog trigger
enable_binlog = False
# zookeeper address of kafka cluster, example:
# zookeeper_addrs = "192.168.0.11:2181,192.168.0.12:2181,192.168.0.13:2181"
zookeeper_addrs = ""
# store slow query log into seperate file
enable_slow_query_log = False

# KV mode
deploy_without_tidb = False