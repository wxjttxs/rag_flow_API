# MySQL 磁盘空间问题解决方案

## 🔍 问题诊断

### 错误现象
- ❌ 创建知识库失败
- ❌ 上传文件报错
- ❌ 数据库操作超时

### 错误日志
```
AttributeError: 'NoneType' object has no attribute 'settimeout'
Disk is full writing './binlog.000015' (OS errno 28 - No space left on device)
```

### 根本原因
**MySQL 所在的根分区磁盘已满（100%）！**

```
/dev/sdc2  1.8T  1.7T  0  100%  /   ← MySQL 数据在这里
```

MySQL binlog（二进制日志）文件占用大量空间：
- binlog.000014: 1.1GB
- binlog.000015: 685MB
- 总计约 1.8GB

---

## 💡 问题分析

### 为什么之前 ES 迁移后还有问题？

| 组件 | 位置 | 磁盘 | 状态 |
|------|------|------|------|
| Elasticsearch | /mnt/data6t/ragflow_esdata | /dev/sda1 (6TB, 334GB可用) | ✅ 已迁移 |
| MySQL | /var/lib/docker/volumes/docker_mysql_data | /dev/sdc2 (1.8TB, 100%满) | ❌ 未迁移 |
| Redis | /var/lib/docker/volumes/docker_redis_data | /dev/sdc2 (100%满) | ❌ 未迁移 |
| MinIO | /var/lib/docker/volumes/docker_minio_data | /dev/sdc2 (100%满) | ❌ 未迁移 |

**结论：** 只迁移了 ES，其他服务的数据仍在满载的根分区。

---

## ✅ 解决方案

### 方案 A：紧急修复（5分钟）⚡

**适用：** 快速恢复服务，临时缓解

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./fix-mysql-disk.sh
```

**操作：**
1. 清理旧的 MySQL binlog 文件
2. 配置自动清理策略（7天）
3. 释放约 1-1.5GB 空间

**优点：**
- ✅ 快速（5分钟）
- ✅ 风险低
- ✅ 立即生效

**缺点：**
- ⚠️ 只是临时方案
- ⚠️ 过几天可能还会满
- ⚠️ 根分区仍然紧张

---

### 方案 B：完整迁移（推荐）🎯

**适用：** 彻底解决问题

将所有 Docker 数据迁移到 /mnt/data6t

#### B1. 迁移 MySQL 数据

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./migrate-mysql-data.sh
```

**步骤：**
1. 停止服务
2. 复制 MySQL 数据到新位置
3. 修改 docker-compose 配置
4. 启动服务

**预计时间：** 10-15 分钟

#### B2. 迁移其他服务（可选）

```bash
# 迁移 Redis, MinIO 等
sudo ./migrate-all-volumes.sh
```

---

## 🚀 推荐执行流程

### 立即执行（紧急）

```bash
# 1. 清理 binlog 恢复服务
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./fix-mysql-disk.sh
```

### 后续规划（本周内）

```bash
# 2. 迁移 MySQL 数据（推荐）
sudo ./migrate-mysql-data.sh

# 3. 监控磁盘空间
watch -n 60 'df -h | grep sdc2'
```

---

## 📊 磁盘使用详情

### 当前状况

```
磁盘分区使用情况：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/dev/sdc2 (根分区)      1.8TB  100% 满 ❌
├── Docker volumes      ~5GB
│   ├── mysql_data      2.3GB
│   │   └── binlog     1.8GB  ← 主要问题
│   ├── redis_data      几百MB
│   ├── minio_data      几GB
│   └── 其他            ...
└── 系统文件            1.7TB

/dev/sda1 (/mnt/data6t) 6TB    95% 使用 ✅
├── ragflow_esdata      122MB  ← 已迁移
└── 可用空间            334GB  ← 可以用
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 清理后（方案 A）

```
/dev/sdc2: 1.8TB, 约 99% 使用
释放空间: 约 1-1.5GB
```

### 迁移后（方案 B）

```
/dev/sdc2: 1.8TB, 约 98% 使用
/dev/sda1: 6TB, 约 95.5% 使用
MySQL 数据迁移到 sda1，根分区释放 2.3GB
```

---

## 🔧 详细操作指南

### 方案 A：清理 binlog

#### 手动清理（如果脚本有问题）

```bash
# 1. 连接到 MySQL
docker exec -it ragflow-mysql mysql -uroot -pinfini_rag_flow

# 2. 查看当前 binlog
SHOW BINARY LOGS;

# 3. 清理 7 天前的 binlog
PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 7 DAY);

# 4. 或清理到指定文件
PURGE BINARY LOGS TO 'binlog.000014';

# 5. 设置自动清理（7天）
SET GLOBAL binlog_expire_logs_seconds = 604800;

# 6. 验证
SHOW VARIABLES LIKE 'binlog_expire_logs_seconds';

# 7. 退出
EXIT;
```

#### 验证结果

```bash
# 检查磁盘空间
df -h | grep sdc2

# 检查 binlog 大小
sudo du -sh /var/lib/docker/volumes/docker_mysql_data/_data/binlog.*

# 重启 RAGFlow
cd /mnt/data6t/wangxiaojing/rag_flow/docker
docker-compose restart ragflow
```

---

### 方案 B：迁移 MySQL（完整版）

#### 步骤详解

**1. 停止服务**
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
docker-compose down
```

**2. 创建新数据目录**
```bash
sudo mkdir -p /mnt/data6t/ragflow_mysql
sudo chown -R 999:999 /mnt/data6t/ragflow_mysql  # MySQL 容器 UID
```

**3. 复制数据**
```bash
OLD_PATH="/var/lib/docker/volumes/docker_mysql_data/_data"
NEW_PATH="/mnt/data6t/ragflow_mysql"

sudo rsync -av --progress "$OLD_PATH/" "$NEW_PATH/"
```

**4. 修改配置**

编辑 `docker-compose-base.yml`：

```yaml
volumes:
  mysql_data:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/data6t/ragflow_mysql
```

**5. 删除旧 volume**
```bash
docker volume rm docker_mysql_data
```

**6. 启动服务**
```bash
docker-compose up -d
```

**7. 验证**
```bash
# 检查挂载
docker inspect ragflow-mysql | grep -A 5 Mounts

# 检查数据库
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "SHOW DATABASES;"
```

---

## ⚠️ 常见问题

### Q1: 清理 binlog 会丢失数据吗？

**A:** 不会。Binlog 是用于复制和恢复的，对于单机部署：
- 清理旧 binlog 不影响当前数据
- 只会影响到该时间点之前的恢复能力
- 如果没有主从复制，影响很小

### Q2: 为什么 binlog 这么大？

**A:** MySQL 默认配置导致：
- `binlog_expire_logs_seconds = 2592000`（30天）
- 频繁的写入操作积累
- 建议设置为 7 天：`604800` 秒

### Q3: 清理后多久会再满？

**A:** 取决于使用量：
- 轻度使用：1-2 周
- 中度使用：3-7 天
- 重度使用：1-3 天

**建议：** 尽快执行完整迁移（方案 B）

### Q4: 能直接删除 binlog 文件吗？

**A:** ❌ 不要直接删除！会导致：
- MySQL 启动失败
- 数据不一致
- 必须通过 MySQL 命令清理

### Q5: 迁移 MySQL 会丢失数据吗？

**A:** 不会，前提是：
- ✅ 完全停止服务
- ✅ 使用 rsync 保留权限
- ✅ 验证数据完整性
- ✅ 保留备份

---

## 📈 监控和预防

### 设置磁盘监控

```bash
# 创建监控脚本
cat > /usr/local/bin/check-disk.sh << 'EOF'
#!/bin/bash
USAGE=$(df -h /dev/sdc2 | awk 'NR==2 {print $5}' | sed 's/%//')
if [ $USAGE -gt 95 ]; then
    echo "警告：根分区使用率 ${USAGE}%"
    # 可以发送邮件或通知
fi
EOF

chmod +x /usr/local/bin/check-disk.sh

# 添加到 crontab（每小时检查）
(crontab -l 2>/dev/null; echo "0 * * * * /usr/local/bin/check-disk.sh") | crontab -
```

### 定期清理

```bash
# 每周清理一次 binlog
0 2 * * 0 docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 7 DAY);"
```

---

## 🎯 最终建议

### 立即执行（今天）

1. ✅ **运行紧急修复脚本**
   ```bash
   sudo ./fix-mysql-disk.sh
   ```
   
2. ✅ **测试服务是否恢复**
   - 创建知识库
   - 上传文件
   - 检查是否正常

### 本周内完成

3. ✅ **迁移 MySQL 数据**
   ```bash
   sudo ./migrate-mysql-data.sh
   ```

4. ✅ **设置监控**
   - 磁盘使用率告警
   - Binlog 自动清理

### 长期优化

5. ✅ **考虑清理系统**
   - 找出占用空间的大文件
   - 清理不需要的数据
   - 或添加新磁盘

---

## 📞 执行命令总结

```bash
# === 紧急修复（立即执行）===
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./fix-mysql-disk.sh

# === 验证 ===
df -h | grep sdc2
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "SHOW BINARY LOGS;"

# === 重启服务 ===
docker-compose restart ragflow

# === 测试 ===
# 访问 http://localhost:9381
# 尝试创建知识库和上传文件

# === 后续迁移（推荐）===
# sudo ./migrate-mysql-data.sh
```

---

**现在立即执行紧急修复，恢复服务！** 🚀



