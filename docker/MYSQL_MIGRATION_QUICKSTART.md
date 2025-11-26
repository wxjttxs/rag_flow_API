# MySQL 迁移快速入门 🚀

## ⚡ 1 分钟快速决策

```bash
# 查看当前状态
cd /mnt/data6t/wangxiaojing/rag_flow/docker
./diagnose-disk.sh
```

### 现在是紧急情况？（服务已经挂了）
```bash
# 5分钟快速恢复
sudo ./fix-mysql-disk.sh
```

### 想彻底解决？（有10-15分钟维护时间）
```bash
# 完整迁移到大磁盘
sudo ./migrate-mysql-complete.sh
```

---

## 📋 脚本对比表

| 脚本 | 作用 | 时间 | 停机 | 永久性 |
|------|------|------|------|--------|
| **fix-mysql-disk.sh** | 清理 binlog | 5分钟 | 否 | ❌ 临时 |
| **migrate-mysql-complete.sh** | 迁移到 /mnt/data6t | 10-15分钟 | 5-10分钟 | ✅ 永久 |

---

## 🎯 推荐执行流程

### 步骤 1：立即恢复（现在）
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./fix-mysql-disk.sh
```

**效果：**
- ✅ 释放 1-1.5GB 空间
- ✅ 服务立即恢复
- ⚠️ 过几天可能还会满

---

### 步骤 2：彻底解决（本周内）
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./migrate-mysql-complete.sh
```

**效果：**
- ✅ 释放 2.3GB 空间（根分区）
- ✅ 数据迁移到 /mnt/data6t（334GB 可用）
- ✅ 永久解决磁盘问题

---

## 📊 当前问题分析

```
磁盘状态：
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
/dev/sdc2 (根分区)    1.8TB  100% 满  ❌
├─ MySQL 数据         2.3GB            ← 需要迁移
│  └─ binlog 文件     1.8GB            ← 可以清理
└─ 其他数据           ...

/dev/sda1 (/mnt/data6t) 6TB  95%  ✅
├─ ES 数据            122MB  (已迁移)
└─ 可用空间           334GB            ← 目标位置
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

---

## 🔧 详细操作指南

### 方案 A：fix-mysql-disk.sh（清理 binlog）

#### 执行前检查
```bash
# 检查当前 binlog 大小
sudo du -sh /var/lib/docker/volumes/docker_mysql_data/_data/binlog.*
```

#### 执行脚本
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./fix-mysql-disk.sh
```

#### 脚本会做什么？
1. ✅ 显示当前磁盘和 binlog 状态
2. ✅ 清理 7 天前的 binlog 文件
3. ✅ 设置自动清理策略（7天）
4. ✅ 可选：重启 RAGFlow 服务

#### 预期结果
```bash
# 磁盘空间增加
df -h | grep sdc2
# /dev/sdc2  1.8T  1.7T  1.5G  99%  /  ← 从 100% 降到 99%

# binlog 文件减少
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "SHOW BINARY LOGS;"
# 只保留最近的 2-3 个文件
```

#### 验证服务
```bash
# 访问 UI
http://localhost:9381

# 测试创建知识库
# 测试上传文档
```

---

### 方案 B：migrate-mysql-complete.sh（完整迁移）

#### 执行前准备

**1. 确认目标磁盘有空间**
```bash
df -h /mnt/data6t
# 确保至少有 5GB 可用空间
```

**2. 确认当前数据大小**
```bash
sudo du -sh /var/lib/docker/volumes/docker_mysql_data/_data
# 预计：2.3GB
```

**3. 选择维护时间窗口**
- 需要停机：10-15 分钟
- 建议低峰期或周末执行

#### 执行脚本
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./migrate-mysql-complete.sh
```

#### 脚本会做什么？

**自动化步骤：**
1. ✅ 环境检查（权限、Docker、磁盘空间）
2. ✅ 停止 RAGFlow 服务
3. ✅ 创建新目录：/mnt/data6t/ragflow_mysql
4. ✅ rsync 迁移数据（2.3GB，2-5分钟）
5. ✅ 备份配置文件
6. ✅ 修复 docker-compose-base.yml
7. ✅ 删除旧的 Docker volume
8. ✅ 启动服务
9. ✅ 验证迁移结果

**用户交互：**
- 确认开始迁移（y/n）
- 自动执行所有步骤
- 显示详细进度

#### 预期结果

**磁盘空间变化：**
```bash
# 根分区释放空间
df -h | grep sdc2
# /dev/sdc2  1.8T  1.7T  2.5G  99%  /  ← 释放 2.3GB

# 数据磁盘增加使用
df -h /mnt/data6t
# /dev/sda1  6.0T  5.4T  332G  95%  /mnt/data6t  ← 使用 2.3GB
```

**容器挂载点：**
```bash
docker inspect ragflow-mysql | grep -A 5 Mounts
# 应该显示：
# "Source": "/mnt/data6t/ragflow_mysql"
```

**MySQL 数据验证：**
```bash
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "SHOW DATABASES;"
# 应该显示所有数据库
```

#### 迁移失败怎么办？

**自动备份位置：**
```bash
ls -la /mnt/data6t/wangxiaojing/rag_flow/docker/docker-compose-base.yml.mysql_migration_backup_*
```

**回滚步骤：**
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker

# 1. 停止服务
docker-compose down

# 2. 恢复配置文件
BACKUP=$(ls -t docker-compose-base.yml.mysql_migration_backup_* | head -1)
sudo cp "$BACKUP" docker-compose-base.yml

# 3. 重新创建旧 volume（如果还在）
docker volume create docker_mysql_data

# 4. 启动服务
docker-compose up -d
```

---

## 🧪 验证迁移成功

### 检查清单

#### 1. 容器运行状态
```bash
docker ps | grep mysql
# 应该显示：Up XX minutes (healthy)
```

#### 2. 数据库连接
```bash
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "SELECT 1;"
# 应该返回：1
```

#### 3. 挂载点验证
```bash
docker inspect ragflow-mysql | grep -A 3 "ragflow_mysql"
# 应该显示：/mnt/data6t/ragflow_mysql
```

#### 4. 磁盘空间
```bash
# MySQL 容器内看到的是新磁盘
docker exec ragflow-mysql df -h /var/lib/mysql
# 应该显示：6.0T 的磁盘
```

#### 5. 功能测试
- [ ] 访问 UI: http://localhost:9381
- [ ] 登录成功
- [ ] 创建知识库
- [ ] 上传文档
- [ ] 解析文档

---

## ⚠️ 常见问题

### Q1: 清理 binlog 会丢数据吗？
**A:** 不会。Binlog 是用于复制和恢复的，对单机部署影响很小。

### Q2: 迁移过程中断电怎么办？
**A:** 旧数据仍在，可以重新执行脚本或使用备份配置回滚。

### Q3: 迁移后性能会变差吗？
**A:** 不会。/mnt/data6t 使用的是 /dev/sda1，性能应该相似或更好。

### Q4: 能否只迁移不删除旧数据？
**A:** 可以。脚本只删除 Docker volume，不删除实际文件。旧数据仍在：
```bash
/var/lib/docker/volumes/docker_mysql_data/_data
```

### Q5: 迁移失败如何回滚？
**A:** 见上面"迁移失败怎么办？"章节。

---

## 📞 执行命令速查

### 🔍 诊断
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
./diagnose-disk.sh
```

### ⚡ 快速清理
```bash
sudo ./fix-mysql-disk.sh
```

### 🎯 完整迁移
```bash
sudo ./migrate-mysql-complete.sh
```

### 🔄 重启服务
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
docker-compose restart ragflow
```

### 📊 查看日志
```bash
docker-compose logs -f mysql
docker-compose logs -f ragflow
```

### 🧪 测试数据库
```bash
docker exec ragflow-mysql mysql -uroot -pinfini_rag_flow -e "SHOW DATABASES;"
```

---

## 🎯 最终建议

### 保守方案（推荐）
```bash
# 今天：快速恢复
sudo ./fix-mysql-disk.sh

# 本周：彻底解决
sudo ./migrate-mysql-complete.sh
```

### 激进方案（有经验）
```bash
# 直接迁移
sudo ./migrate-mysql-complete.sh
```

---

## 📚 相关文档

| 文档 | 用途 |
|------|------|
| **MYSQL_DISK_ISSUE.md** | 详细的问题分析和解决方案 |
| **SCRIPTS_COMPARISON.md** | 两个脚本的详细对比 |
| **MIGRATION_COMPLETE.md** | ES 迁移案例（可参考） |

---

## ✅ 总结

**两个脚本的关系：**
- `fix-mysql-disk.sh` = **治标**（临时清理）
- `migrate-mysql-complete.sh` = **治本**（彻底迁移）

**推荐流程：**
1. 先用 `fix-mysql-disk.sh` 恢复服务
2. 测试确认正常
3. 规划维护时间
4. 执行 `migrate-mysql-complete.sh` 彻底解决

**现在就开始：**
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./fix-mysql-disk.sh  # 或 sudo ./migrate-mysql-complete.sh
```

🚀 **Let's fix this!**



