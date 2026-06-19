#!/usr/bin/env python3
"""一键部署 systemd 开机启动到所有中间件服务器"""
import subprocess

PASS = "laluna157"
JUMP = "root@192.168.11.157"
JUMP_PORT = 2217

def ssh(host, cmd):
    remote = f"sshpass -p '{PASS}' ssh -o StrictHostKeyChecking=no root@{host} '{cmd}'"
    jump = f"sshpass -p '{PASS}' ssh -o StrictHostKeyChecking=no -p {JUMP_PORT} {JUMP} '{remote}'"
    r = subprocess.run(jump, shell=True, capture_output=True, text=True, timeout=30)
    return r.returncode == 0, r.stderr.strip()[:100]

def deploy(host, name, unit):
    escaped = unit.replace("'", "'\\''")
    cmd = f"echo '{escaped}' > /etc/systemd/system/{name}.service && systemctl daemon-reload && systemctl enable {name} && echo OK"
    ok, err = ssh(host, cmd)
    if ok: print(f"  OK {name}.service")
    else:  print(f"  FAIL {name}.service: {err}")
    return ok

# ===== 服务定义 =====
MYSQLD = '''[Unit]
Description=MySQL Database Server
After=network.target
[Service]
Type=forking
ExecStart=/usr/sbin/mysqld --daemonize
ExecStop=/usr/bin/killall mysqld
Restart=on-failure
[Install]
WantedBy=multi-user.target'''

NACOS = '''[Unit]
Description=Nacos Server
After=network.target
[Service]
Type=forking
ExecStart=/bin/bash /usr/local/software/nacos/bin/startup.sh -m standalone
ExecStop=/bin/bash /usr/local/software/nacos/bin/shutdown.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target'''

ZOOKEEPER = '''[Unit]
Description=Apache Zookeeper
After=network.target
[Service]
Type=forking
ExecStart=/bin/bash /opt/modules/zookeeper/bin/zkServer.sh start
ExecStop=/bin/bash /opt/modules/zookeeper/bin/zkServer.sh stop
Restart=on-failure
[Install]
WantedBy=multi-user.target'''

KAFKA = '''[Unit]
Description=Apache Kafka
After=network.target zookeeper.service
Requires=zookeeper.service
[Service]
Type=simple
ExecStart=/bin/bash /opt/module/kafka/bin/kafka-server-start.sh /opt/module/kafka/config/server.properties
ExecStop=/bin/bash /opt/module/kafka/bin/kafka-server-stop.sh
Restart=on-failure
[Install]
WantedBy=multi-user.target'''

REDIS = '''[Unit]
Description=Redis Server
After=network.target
[Service]
Type=simple
ExecStart=/usr/local/redis-7.0.2/redis-server /usr/local/redis-7.0.2/redis.conf
ExecStop=/usr/local/redis-7.0.2/redis-cli -a laluna157 shutdown
Restart=on-failure
[Install]
WantedBy=multi-user.target'''

ELASTICSEARCH = '''[Unit]
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
WantedBy=multi-user.target'''

REDIS_CLUSTER = '''[Unit]
Description=Redis Cluster Node
After=network.target
[Service]
Type=simple
ExecStart=/root/software/redis-3.0.7/redis-server /root/software/redis-3.0.7/redis.conf
ExecStop=/root/software/redis-3.0.7/redis-cli -a laluna157 shutdown
Restart=on-failure
[Install]
WantedBy=multi-user.target'''

print("=" * 50)
print("systemd 开机启动部署")
print("=" * 50)

servers = [
    ("VM01 192.168.2.200", "192.168.2.200",
     [("mysqld", MYSQLD), ("nacos", NACOS), ("zookeeper", ZOOKEEPER), ("kafka", KAFKA)]),
    ("VM02 192.168.2.201", "192.168.2.201",
     [("mysqld", MYSQLD), ("nacos", NACOS), ("zookeeper", ZOOKEEPER), ("kafka", KAFKA)]),
    ("VM03 192.168.2.202", "192.168.2.202",
     [("nacos", NACOS), ("zookeeper", ZOOKEEPER), ("kafka", KAFKA)]),
    ("kuboard1 192.168.2.138", "192.168.2.138",
     [("redis", REDIS), ("elasticsearch", ELASTICSEARCH)]),
]

for label, ip, services in servers:
    print(f"\n>>> {label}")
    for name, unit in services:
        deploy(ip, name, unit)

print("\n>>> Redis Cluster (.203-.208)")
for ip in [f"192.168.2.{i}" for i in range(203, 209)]:
    deploy(ip, "redis-cluster", REDIS_CLUSTER)

print("\n" + "=" * 50)
print("Done! All services enabled for auto-start.")
print("=" * 50)
