#!/bin/bash
# systemd 开机启动服务一键部署脚本
# 通过跳板机 (k8s-master01) 部署到所有中间件服务器

set -e

SSH_JUMP="sshpass -p laluna157 ssh -o StrictHostKeyChecking=no -p 2217 root@192.168.11.157"
SSH_TO() { $SSH_JUMP "sshpass -p laluna157 ssh -o StrictHostKeyChecking=no root@$1 \"$2\""; }

echo "=========================================="
echo " Mobile Claude Controller — 中间件开机启动部署"
echo "=========================================="

# ========== VM01 (192.168.2.200): MySQL + Nacos + ZK + Kafka ==========
echo ""
echo ">>> VM01 (192.168.2.200)"

SSH_TO 192.168.2.200 "cat > /etc/systemd/system/mysqld.service" << 'UNIT'
[Unit]
Description=MySQL Database Server
After=network.target
[Service]
Type=forking
ExecStart=/usr/sbin/mysqld --daemonize
ExecStop=/usr/bin/killall mysqld
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
echo "  mysqld.service done"

SSH_TO 192.168.2.200 "cat > /etc/systemd/system/nacos.service" << 'UNIT'
[Unit]
Description=Nacos Server
After=network.target
[Service]
Type=forking
ExecStart=/bin/bash /usr/local/software/nacos/bin/startup.sh -m standalone
ExecStop=/bin/bash /usr/local/software/nacos/bin/shutdown.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
echo "  nacos.service done"

SSH_TO 192.168.2.200 "cat > /etc/systemd/system/zookeeper.service" << 'UNIT'
[Unit]
Description=Apache Zookeeper
After=network.target
[Service]
Type=forking
ExecStart=/bin/bash /opt/modules/zookeeper/bin/zkServer.sh start
ExecStop=/bin/bash /opt/modules/zookeeper/bin/zkServer.sh stop
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
echo "  zookeeper.service done"

SSH_TO 192.168.2.200 "cat > /etc/systemd/system/kafka.service" << 'UNIT'
[Unit]
Description=Apache Kafka
After=network.target zookeeper.service
Requires=zookeeper.service
[Service]
Type=simple
ExecStart=/bin/bash /opt/module/kafka/bin/kafka-server-start.sh /opt/module/kafka/config/server.properties
ExecStop=/bin/bash /opt/module/kafka/bin/kafka-server-stop.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
echo "  kafka.service done"

SSH_TO 192.168.2.200 "systemctl daemon-reload && systemctl enable mysqld nacos zookeeper kafka"
echo "  VM01 enabled!"

# ========== VM02 (192.168.2.201): MySQL + Nacos + ZK + Kafka ==========
echo ""
echo ">>> VM02 (192.168.2.201)"

SSH_TO 192.168.2.201 "cat > /etc/systemd/system/mysqld.service" << 'UNIT'
[Unit]
Description=MySQL Database Server
After=network.target
[Service]
Type=forking
ExecStart=/usr/sbin/mysqld --daemonize
ExecStop=/usr/bin/killall mysqld
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

SSH_TO 192.168.2.201 "cat > /etc/systemd/system/nacos.service" << 'UNIT'
[Unit]
Description=Nacos Server
After=network.target
[Service]
Type=forking
ExecStart=/bin/bash /usr/local/software/nacos/bin/startup.sh -m standalone
ExecStop=/bin/bash /usr/local/software/nacos/bin/shutdown.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

SSH_TO 192.168.2.201 "cat > /etc/systemd/system/zookeeper.service" << 'UNIT'
[Unit]
Description=Apache Zookeeper
After=network.target
[Service]
Type=forking
ExecStart=/bin/bash /opt/modules/zookeeper/bin/zkServer.sh start
ExecStop=/bin/bash /opt/modules/zookeeper/bin/zkServer.sh stop
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

SSH_TO 192.168.2.201 "cat > /etc/systemd/system/kafka.service" << 'UNIT'
[Unit]
Description=Apache Kafka
After=network.target zookeeper.service
Requires=zookeeper.service
[Service]
Type=simple
ExecStart=/bin/bash /opt/module/kafka/bin/kafka-server-start.sh /opt/module/kafka/config/server.properties
ExecStop=/bin/bash /opt/module/kafka/bin/kafka-server-stop.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

SSH_TO 192.168.2.201 "systemctl daemon-reload && systemctl enable mysqld nacos zookeeper kafka"
echo "  VM02 enabled!"

# ========== VM03 (192.168.2.202): Nacos + ZK + Kafka ==========
echo ""
echo ">>> VM03 (192.168.2.202)"

SSH_TO 192.168.2.202 "cat > /etc/systemd/system/nacos.service" << 'UNIT'
[Unit]
Description=Nacos Server
After=network.target
[Service]
Type=forking
ExecStart=/bin/bash /usr/local/software/nacos/bin/startup.sh -m standalone
ExecStop=/bin/bash /usr/local/software/nacos/bin/shutdown.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

SSH_TO 192.168.2.202 "cat > /etc/systemd/system/zookeeper.service" << 'UNIT'
[Unit]
Description=Apache Zookeeper
After=network.target
[Service]
Type=forking
ExecStart=/bin/bash /opt/modules/zookeeper/bin/zkServer.sh start
ExecStop=/bin/bash /opt/modules/zookeeper/bin/zkServer.sh stop
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

SSH_TO 192.168.2.202 "cat > /etc/systemd/system/kafka.service" << 'UNIT'
[Unit]
Description=Apache Kafka
After=network.target zookeeper.service
Requires=zookeeper.service
[Service]
Type=simple
ExecStart=/bin/bash /opt/module/kafka/bin/kafka-server-start.sh /opt/module/kafka/config/server.properties
ExecStop=/bin/bash /opt/module/kafka/bin/kafka-server-stop.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT

SSH_TO 192.168.2.202 "systemctl daemon-reload && systemctl enable nacos zookeeper kafka"
echo "  VM03 enabled!"

# ========== kuboard1 (192.168.2.138): Redis + Elasticsearch ==========
echo ""
echo ">>> kuboard1 (192.168.2.138)"

SSH_TO 192.168.2.138 "cat > /etc/systemd/system/redis.service" << 'UNIT'
[Unit]
Description=Redis Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/redis-7.0.2/redis-server /usr/local/redis-7.0.2/redis.conf
ExecStop=/usr/local/redis-7.0.2/redis-cli -a laluna157 shutdown
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
echo "  redis.service done"

SSH_TO 192.168.2.138 "cat > /etc/systemd/system/elasticsearch.service" << 'UNIT'
[Unit]
Description=Elasticsearch
After=network.target
[Service]
Type=simple
User=elasticsearch
Group=elasticsearch
ExecStart=/opt/es7/elasticsearch-7.12.0/bin/elasticsearch
Restart=on-failure
LimitNOFILE=65536
LimitNPROC=4096
[Install]
WantedBy=multi-user.target
UNIT
echo "  elasticsearch.service done"

SSH_TO 192.168.2.138 "systemctl daemon-reload && systemctl enable redis elasticsearch"
echo "  kuboard1 enabled!"

# ========== Redis Cluster (192.168.2.203-208) ==========
echo ""
echo ">>> Redis Cluster nodes (.203-.208)"

for ip in 192.168.2.203 192.168.2.204 192.168.2.205 192.168.2.206 192.168.2.207 192.168.2.208; do
  SSH_TO $ip "cat > /etc/systemd/system/redis-cluster.service" << 'UNIT'
[Unit]
Description=Redis Cluster Node
After=network.target
[Service]
Type=simple
ExecStart=/root/software/redis-3.0.7/redis-server /root/software/redis-3.0.7/redis.conf
ExecStop=/root/software/redis-3.0.7/redis-cli -a laluna157 shutdown
Restart=on-failure
[Install]
WantedBy=multi-user.target
UNIT
  SSH_TO $ip "systemctl daemon-reload && systemctl enable redis-cluster"
  echo "  $ip redis-cluster enabled!"
done

echo ""
echo "=========================================="
echo " 全部开机启动服务部署完成！"
echo "=========================================="
