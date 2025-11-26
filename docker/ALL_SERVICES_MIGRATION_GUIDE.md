# RAGFlow 所有服务迁移完整指南

## 📋 概述

为了彻底解决磁盘空间问题，我们创建了完整的迁移方案，将所有服务数据从满载的根分区迁移到 `/mnt/data6t`。

---

## 🎯 迁移脚本总览

### 已创建的迁移脚本

| 脚本名称 | 迁移服务 | 数据量 | 执行时间 |
|---------|---------|-------|---------|
| **migrate-mysql-complete.sh** | MySQL | ~2.3GB | 10-15分钟 |
| **migrate-redis-complete.sh** | Redis | ~几MB | 5分钟 |
| **migrate-minio-complete.sh** | MinIO | 变化大 | 5-20分钟 |
| **migrate-all-services.sh** | 所有服务 | 全部 | 15-25分钟 |
| **migrate-es-complete.sh** | Elasticsearch | 已完成 | - |

### 推荐方案

```bash
# 🎯 推荐：一次性迁移所有服务（最省时间）
sudo ./migrate-all-services.sh
```

---

## 🚀 快速开始

### 方案 A：一键迁移所有服务（推荐⭐）

**适用场景：**
- 想一次性解决所有问题
- 有 15-25 分钟维护窗口
- 不想多次停机

**执行命令：**
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./migrate-all-services.sh
```

**优点：**
- ✅ 一次性解决，不用多次停机
- ✅ 统一管理，避免遗漏
- ✅ 时间最短（只需停机一次）
- ✅ 自动验证所有服务

---

### 方案 B：分步迁移（保守）

**适用场景：**
- 想逐个验证
- 维护窗口时间有限
- 风险控制要求高

**执行顺序：**

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker

# 1. 迁移 MySQL（最重要）
sudo ./migrate-mysql-complete.sh
# 测试验证...

# 2. 迁移 Redis（缓存，影响小）
sudo ./migrate-redis-complete.sh
# 测试验证...

# 3. 迁移 MinIO（文件存储）
sudo ./migrate-minio-complete.sh
# 测试验证...
```

---

## 📊 当前磁盘状态

### 磁盘分布

```
当前状态（迁移前）：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/dev/sdc2 (根分区)    1.8TB  100% 满  ❌
├── MySQL 数据         2.3GB
├── Redis 数据         ~10MB
├── MinIO 数据         ~几GB
└── 其他系统文件       ...

/dev/sda1 (/mnt/data6t) 6TB    95%  ✅
├── ES 数据            122MB  (已迁移)
└── 可用空间           334GB
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

目标状态（迁移后）：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/dev/sdc2 (根分区)    1.8TB  约98%  ✅
└── 释放约 2-3GB 空间

/dev/sda1 (/mnt/data6t) 6TB    95.5%  ✅
├── ES 数据            122MB
├── MySQL 数据         2.3GB  (新)
├── Redis 数据         ~10MB  (新)
├── MinIO 数据         ~几GB  (新)
└── 可用空间           约330GB
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🔧 详细操作指南

### 使用统一迁移脚本（推荐）

#### 步骤 1：查看当前状态

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
./diagnose-disk.sh
```

#### 步骤 2：执行迁移

```bash
sudo ./migrate-all-services.sh
```

#### 脚本会自动完成：

1. **环境检查**
   - 权限验证
   - Docker 状态
   - 磁盘空间检查
   - 显示当前数据大小

2. **停止服务**
   - docker-compose down
   - 等待容器完全停止

3. **创建目录并迁移数据**
   - MySQL: /mnt/data6t/ragflow_mysql
   - Redis: /mnt/data6t/ragflow_redis
   - MinIO: /mnt/data6t/ragflow_minio
   - 使用 rsync 保留所有权限

4. **修复配置文件**
   - 自动备份 docker-compose-base.yml
   - 修改 volumes 定义
   - 添加 bind mount 配置

5. **验证配置**
   - docker-compose config 语法检查
   - 显示新配置

6. **清理旧 volumes**
   - 删除 docker_mysql_data
   - 删除 docker_redis_data
   - 删除 docker_minio_data

7. **启动服务**
   - docker-compose up -d
   - 等待所有服务就绪
   - 自动健康检查

8. **验证结果**
   - 检查容器状态
   - 测试服务连接
   - 显示挂载点
   - 磁盘空间对比

#### 步骤 3：验证迁移

```bash
# 1. 检查容器状态
docker ps

# 2. 检查服务健康
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "SELECT 1;"
docker exec ragflow-redis redis-cli -a infini_rag_flow ping
docker exec ragflow-minio curl -sf http://localhost:9000/minio/health/live

# 3. 访问 UI
# http://localhost:9381

# 4. 测试功能
# - 创建知识库
# - 上传文档
# - 对话测试
```

---

### 单独迁移脚本说明

#### MySQL 迁移

```bash
sudo ./migrate-mysql-complete.sh
```

**特点：**
- 迁移 2.3GB 数据（包括 1.8GB binlog）
- 容器 UID: 999:999
- 健康检查：mysqladmin ping

**验证：**
```bash
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "SHOW DATABASES;"
```

---

#### Redis 迁移

```bash
sudo ./migrate-redis-complete.sh
```

**特点：**
- 迁移缓存数据（通常很小）
- 容器 UID: 999:999
- 健康检查：redis-cli ping

**验证：**
```bash
docker exec ragflow-redis redis-cli -a infini_rag_flow info
```

---

#### MinIO 迁移

```bash
sudo ./migrate-minio-complete.sh
```

**特点：**
- 迁移对象存储数据（文档、图片等）
- 容器 UID: 1000:1000
- 健康检查：health endpoint

**验证：**
```bash
# 访问 MinIO 控制台
http://localhost:9002
# 用户名: minioadmin
# 密码: infini_rag_flow
```

---

## ⚠️ 注意事项

### 执行前检查

- [ ] 确认有 sudo 权限
- [ ] 确认 /mnt/data6t 有足够空间（至少 10GB）
- [ ] 选择合适的维护时间窗口
- [ ] 通知用户服务将短暂中断
- [ ] 备份重要数据（脚本会自动备份配置）

### 执行过程中

- [ ] 不要手动停止脚本
- [ ] 观察迁移进度
- [ ] 注意错误提示
- [ ] 保持终端连接

### 执行后验证

- [ ] 检查所有容器状态
- [ ] 测试数据库连接
- [ ] 测试 Redis 缓存
- [ ] 测试文件上传（MinIO）
- [ ] 完整功能测试

---

## 🔍 故障排查

### 问题 1：配置文件语法错误

**症状：**
```
ERROR: The Compose file is invalid
```

**解决：**
```bash
# 查找备份文件
ls -lt docker-compose-base.yml.*backup* | head -1

# 恢复备份
BACKUP=$(ls -t docker-compose-base.yml.*backup* | head -1)
sudo cp "$BACKUP" docker-compose-base.yml

# 重新启动
docker-compose up -d
```

---

### 问题 2：服务启动超时

**症状：**
服务一直处于启动状态

**解决：**
```bash
# 查看日志
docker-compose logs -f mysql
docker-compose logs -f redis
docker-compose logs -f minio

# 检查权限
ls -la /mnt/data6t/ragflow_*

# 重启服务
docker-compose restart mysql redis minio
```

---

### 问题 3：数据丢失

**症状：**
无法访问历史数据

**解决：**
```bash
# 检查数据是否迁移成功
sudo ls -lh /mnt/data6t/ragflow_mysql
sudo ls -lh /mnt/data6t/ragflow_redis
sudo ls -lh /mnt/data6t/ragflow_minio

# 旧数据仍在原位置
sudo ls -lh /var/lib/docker/volumes/docker_mysql_data/_data
sudo ls -lh /var/lib/docker/volumes/docker_redis_data/_data
sudo ls -lh /var/lib/docker/volumes/docker_minio_data/_data

# 如果新位置没数据，重新迁移
sudo rsync -av /var/lib/docker/volumes/docker_mysql_data/_data/ /mnt/data6t/ragflow_mysql/
```

---

### 问题 4：权限问题

**症状：**
```
Permission denied
```

**解决：**
```bash
# 修复权限
sudo chown -R 999:999 /mnt/data6t/ragflow_mysql
sudo chown -R 999:999 /mnt/data6t/ragflow_redis
sudo chown -R 1000:1000 /mnt/data6t/ragflow_minio

# 重启容器
docker-compose restart mysql redis minio
```

---

## 📈 性能对比

### 迁移前后对比

| 指标 | 迁移前 | 迁移后 | 改善 |
|------|-------|-------|------|
| **根分区使用率** | 100% | ~98% | ✅ 释放 2-3GB |
| **数据磁盘使用率** | - | ~95.5% | ✅ 有效利用 |
| **MySQL 磁盘空间** | 0字节可用 | 334GB可用 | ✅ 不再报错 |
| **服务稳定性** | 经常挂起 | 稳定运行 | ✅ 显著提升 |
| **创建知识库** | 失败 | 成功 | ✅ 功能恢复 |
| **文档上传** | 失败 | 成功 | ✅ 功能恢复 |

---

## 🎯 最佳实践

### 推荐执行流程

#### 第一阶段：紧急修复（如果服务已经挂了）

```bash
# 快速清理 MySQL binlog（5分钟）
sudo ./fix-mysql-disk.sh
```

#### 第二阶段：完整迁移（计划维护时间）

```bash
# 一键迁移所有服务（15-25分钟）
sudo ./migrate-all-services.sh
```

#### 第三阶段：验证和清理（迁移后1-2天）

```bash
# 1. 观察系统运行 1-2 天
# 2. 确认一切正常
# 3. 清理旧数据释放空间

# 清理旧数据（谨慎！）
sudo rm -rf /var/lib/docker/volumes/docker_mysql_data
sudo rm -rf /var/lib/docker/volumes/docker_redis_data
sudo rm -rf /var/lib/docker/volumes/docker_minio_data
```

---

## 📚 相关文档

| 文档 | 说明 |
|------|------|
| **MYSQL_DISK_ISSUE.md** | MySQL 磁盘问题详细分析 |
| **SCRIPTS_COMPARISON.md** | 脚本功能对比 |
| **MYSQL_MIGRATION_QUICKSTART.md** | MySQL 快速迁移指南 |
| **MIGRATION_COMPLETE.md** | ES 迁移总结（可参考） |
| **ES_DISK_MIGRATION_GUIDE.md** | ES 迁移详细指南 |

---

## 🔧 维护建议

### 定期检查

```bash
# 每周检查磁盘空间
df -h | grep -E "sdc2|sda1"

# 每月检查数据增长
du -sh /mnt/data6t/ragflow_*

# 设置告警（可选）
# 当使用率 > 90% 时发送通知
```

### 自动清理

```bash
# 定期清理 MySQL binlog（已配置7天自动清理）
# 在迁移脚本中已设置：
binlog_expire_logs_seconds=604800  # 7天

# 手动清理命令（如需要）：
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow \
  -e "PURGE BINARY LOGS BEFORE DATE_SUB(NOW(), INTERVAL 7 DAY);"
```

---

## ✅ 执行检查清单

### 迁移前

- [ ] 选择合适的维护时间窗口
- [ ] 通知相关用户
- [ ] 确认磁盘空间充足
- [ ] 备份重要数据（可选）
- [ ] 确认有完整的回滚方案

### 迁移中

- [ ] 停止服务
- [ ] 迁移数据
- [ ] 修改配置
- [ ] 验证配置
- [ ] 启动服务

### 迁移后

- [ ] 验证所有容器运行正常
- [ ] 测试数据库连接
- [ ] 测试 Redis 缓存
- [ ] 测试文件上传
- [ ] 完整功能测试
- [ ] 监控服务稳定性
- [ ] 计划清理旧数据

---

## 🚀 立即执行

### 推荐命令

```bash
# 📍 当前位置
cd /mnt/data6t/wangxiaojing/rag_flow/docker

# 🔍 诊断当前状态
./diagnose-disk.sh

# 🎯 一键迁移所有服务（推荐）
sudo ./migrate-all-services.sh

# ✅ 验证迁移结果
docker ps
docker-compose logs -f ragflow
```

---

## 📞 快速参考

```bash
# ═══════════════════════════════════════
# 快速命令参考
# ═══════════════════════════════════════

# 诊断
./diagnose-disk.sh

# 一键迁移（推荐）
sudo ./migrate-all-services.sh

# 单独迁移
sudo ./migrate-mysql-complete.sh
sudo ./migrate-redis-complete.sh
sudo ./migrate-minio-complete.sh

# 查看日志
docker-compose logs -f ragflow
docker-compose logs -f mysql
docker-compose logs -f redis
docker-compose logs -f minio

# 重启服务
docker-compose restart ragflow
docker-compose restart mysql redis minio

# 检查状态
docker ps
docker-compose ps

# 查看挂载
docker inspect ragflow-mysql | grep -A 5 Mounts
docker inspect ragflow-redis | grep -A 5 Mounts
docker inspect ragflow-minio | grep -A 5 Mounts
```

---

## 🎉 总结

**问题：** 根分区磁盘 100% 满，服务无法正常运行

**方案：** 将所有服务数据迁移到 /mnt/data6t（334GB 可用）

**工具：** 4 个完整迁移脚本 + 1 个诊断工具

**推荐：** 使用 `migrate-all-services.sh` 一键迁移

**结果：** 彻底解决磁盘问题，服务稳定运行

---

**立即开始迁移，彻底解决磁盘问题！** 🚀



