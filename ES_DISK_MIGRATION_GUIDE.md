# Elasticsearch 数据迁移到新磁盘指南

## 📋 目录

- [为什么需要迁移](#为什么需要迁移)
- [快速迁移（自动脚本）](#快速迁移自动脚本)
- [手动迁移步骤](#手动迁移步骤)
- [验证迁移](#验证迁移)
- [回滚方案](#回滚方案)
- [常见问题](#常见问题)

---

## 🎯 为什么需要迁移

### 当前状况
- **磁盘：** `/dev/sdc2` - 1.8TB 总空间，已使用 1.7TB（94-100%）
- **问题：** 磁盘空间不足导致 Elasticsearch 无法写入新数据
- **影响：** RAGFlow 无法解析和索引新文档

### 迁移后的好处
- ✅ 充足的磁盘空间
- ✅ 解决 ES 数据写入问题
- ✅ 支持更多知识库和文档
- ✅ 避免频繁清理旧数据

---

## ⚡ 快速迁移（自动脚本）

### 方法一：一键自动迁移（推荐）

```bash
# 1. 准备新磁盘并挂载（例如挂载到 /mnt/new_disk）
# 假设您已经有一块新磁盘，并且已经格式化和挂载

# 2. 运行自动迁移脚本
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./migrate-es-disk.sh
```

**脚本会自动完成：**
1. ✅ 环境检查
2. ✅ 停止 RAGFlow 服务
3. ✅ 备份现有数据
4. ✅ 迁移数据到新磁盘
5. ✅ 更新 Docker 配置
6. ✅ 启动服务并验证

**预计耗时：** 20-60 分钟（取决于数据量）

---

## 🔧 手动迁移步骤

如果您想更好地控制迁移过程，可以手动执行以下步骤：

### 前置准备

#### 1. 准备新磁盘

假设您有一块新的 4TB 磁盘，设备名为 `/dev/sdd`：

```bash
# 查看可用磁盘
lsblk

# 格式化新磁盘（⚠️ 注意：会清空磁盘数据！）
sudo mkfs.ext4 /dev/sdd1

# 创建挂载点
sudo mkdir -p /mnt/new_disk

# 挂载磁盘
sudo mount /dev/sdd1 /mnt/new_disk

# 设置开机自动挂载（可选）
echo '/dev/sdd1 /mnt/new_disk ext4 defaults 0 2' | sudo tee -a /etc/fstab

# 验证挂载
df -h /mnt/new_disk
```

#### 2. 检查当前 ES 数据位置

```bash
# 查看 ES 数据卷信息
docker volume inspect docker_esdata01

# 查看数据大小
docker exec ragflow-es-01 du -sh /usr/share/elasticsearch/data
```

---

### 迁移步骤

#### 步骤 1：停止 RAGFlow 服务

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
docker-compose down
```

#### 步骤 2：创建新数据目录

```bash
# 创建目录
sudo mkdir -p /mnt/new_disk/ragflow_esdata

# 设置正确的权限（ES 容器内 UID 为 1000）
sudo chown -R 1000:1000 /mnt/new_disk/ragflow_esdata
```

#### 步骤 3：备份并迁移数据

```bash
# 获取当前数据卷路径
OLD_DATA_PATH=$(docker volume inspect docker_esdata01 | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')

# 查看数据大小
sudo du -sh $OLD_DATA_PATH

# 迁移数据（保留权限和属性）
sudo rsync -av --progress "$OLD_DATA_PATH/" /mnt/new_disk/ragflow_esdata/

# 验证迁移
sudo du -sh /mnt/new_disk/ragflow_esdata
```

**⏱️ 预计时间：** 对于 1.7TB 数据，约 30-60 分钟

#### 步骤 4：修改 Docker Compose 配置

##### 方法 A：修改 docker-compose-base.yml（推荐）

编辑 `/mnt/data6t/wangxiaojing/rag_flow/docker/docker-compose-base.yml`：

```bash
# 备份原文件
cp docker-compose-base.yml docker-compose-base.yml.backup

# 编辑文件
vim docker-compose-base.yml
```

找到文件末尾的 `volumes:` 部分，修改 `esdata01`：

**原配置：**
```yaml
volumes:
  esdata01:
    driver: local
```

**修改为：**
```yaml
volumes:
  esdata01:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/new_disk/ragflow_esdata
```

##### 方法 B：直接使用命令行修改

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker

# 备份
cp docker-compose-base.yml docker-compose-base.yml.backup

# 添加配置
cat >> docker-compose-base.yml << 'EOF'

# Elasticsearch 数据目录配置（迁移到新磁盘）
  esdata01:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/new_disk/ragflow_esdata
EOF
```

#### 步骤 5：删除旧的 Docker 卷（可选）

```bash
# 删除旧卷（确保数据已成功迁移后再执行）
docker volume rm docker_esdata01
```

#### 步骤 6：启动服务

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
docker-compose up -d
```

#### 步骤 7：等待 ES 启动

```bash
# 查看日志
docker-compose logs -f es01

# 等待约 30-60 秒，直到看到 "started" 消息
# 按 Ctrl+C 退出日志查看
```

---

## ✅ 验证迁移

### 1. 检查容器状态

```bash
docker-compose ps
```

应该看到所有容器都是 `Up` 状态。

### 2. 检查 ES 数据目录

```bash
# 检查容器内挂载点
docker exec ragflow-es-01 df -h /usr/share/elasticsearch/data

# 应该看到新磁盘的挂载信息
```

### 3. 检查集群健康

```bash
# 方法 1：通过容器内部
docker exec ragflow-es-01 curl -s http://localhost:9200/_cluster/health?pretty

# 方法 2：从宿主机
curl -u elastic:infiniFlow123 "http://localhost:1201/_cluster/health?pretty"
```

**期望输出：**
```json
{
  "status" : "green" or "yellow",
  "number_of_nodes" : 1,
  ...
}
```

### 4. 检查索引

```bash
# 查看所有索引
curl -u elastic:infiniFlow123 "http://localhost:1201/_cat/indices?v"

# 确认之前的索引都还在
```

### 5. 测试 RAGFlow 功能

1. 访问 RAGFlow UI：`http://localhost:9381`
2. 检查现有知识库是否正常
3. 尝试上传新文档测试
4. 进行一次问答测试

---

## 🔄 回滚方案

如果迁移后出现问题，可以快速回滚：

### 快速回滚

```bash
# 1. 停止服务
cd /mnt/data6t/wangxiaojing/rag_flow/docker
docker-compose down

# 2. 恢复原配置文件
cp docker-compose-base.yml.backup docker-compose-base.yml

# 3. 如果还保留着旧数据卷，直接启动
docker-compose up -d

# 4. 如果已删除旧卷，从备份恢复
# (假设备份在 /tmp/ragflow_es_backup_XXXXXX)
OLD_DATA_PATH=$(docker volume inspect docker_esdata01 | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')
sudo rsync -av /tmp/ragflow_es_backup_XXXXXX/ "$OLD_DATA_PATH/"
docker-compose up -d
```

---

## ❓ 常见问题

### Q1: 迁移需要多长时间？

**A:** 取决于数据量：
- 100GB 数据：约 5-10 分钟
- 500GB 数据：约 15-30 分钟
- 1.7TB 数据：约 30-60 分钟

### Q2: 迁移过程中会丢失数据吗？

**A:** 不会。迁移使用 `rsync` 命令，会完整复制所有数据和权限。建议在迁移前先做备份。

### Q3: 新磁盘需要多大？

**A:** 建议：
- **最小：** 当前数据量的 2 倍（例如 1.7TB 数据需要 3.5TB+）
- **推荐：** 4TB 或更大
- **考虑因素：** 未来数据增长 + 20-30% 预留空间

### Q4: 可以迁移到网络存储（NFS）吗？

**A:** 可以，但**不推荐**：
- Elasticsearch 对磁盘 I/O 要求高
- 网络存储会严重影响性能
- 推荐使用本地 SSD 或高速 HDD

### Q5: 迁移失败怎么办？

**A:** 
1. 检查错误日志：`docker-compose logs es01`
2. 验证目录权限：`ls -la /mnt/new_disk/ragflow_esdata`
3. 检查磁盘空间：`df -h /mnt/new_disk`
4. 如有问题，执行[回滚方案](#回滚方案)

### Q6: 迁移后性能会提升吗？

**A:** 可能会：
- 如果新磁盘是 SSD，性能会显著提升
- 如果从慢速 HDD 迁移到快速 HDD，性能会有所改善
- 充足的磁盘空间本身也有助于性能

### Q7: 需要停机多久？

**A:** 
- **停机时间 = 数据迁移时间 + ES 启动时间**
- 例如 1.7TB 数据：约 30-60 分钟 + 5 分钟 = 35-65 分钟

### Q8: 可以在不停机的情况下迁移吗？

**A:** 技术上可行，但**不推荐**：
- 可能导致数据不一致
- 迁移过程中的写入会丢失
- 建议选择业务低峰期停机迁移

---

## 📝 迁移检查清单

### 迁移前
- [ ] 新磁盘已准备好并挂载
- [ ] 新磁盘空间充足（至少是当前数据的 2 倍）
- [ ] 已备份重要数据
- [ ] 已通知用户服务将暂时不可用
- [ ] 选择业务低峰期进行迁移

### 迁移中
- [ ] 服务已完全停止
- [ ] 数据完整复制到新位置
- [ ] 配置文件已正确修改
- [ ] 目录权限设置正确

### 迁移后
- [ ] 所有容器正常启动
- [ ] ES 集群健康状态为 green/yellow
- [ ] 所有索引都存在
- [ ] 可以上传和解析新文档
- [ ] 问答功能正常
- [ ] 新磁盘空间正常显示

---

## 🎯 推荐配置

### 理想的磁盘配置

```yaml
磁盘类型: NVMe SSD > SATA SSD > 7200RPM HDD
容量建议: 4TB+
文件系统: ext4 或 xfs
挂载选项: noatime,nodiratime（提升性能）
```

### 示例 fstab 配置

```bash
# /etc/fstab
/dev/sdd1  /mnt/new_disk  ext4  defaults,noatime,nodiratime  0  2
```

---

## 📞 获取帮助

如果在迁移过程中遇到问题：

1. **查看日志：**
   ```bash
   docker-compose logs es01
   docker-compose logs ragflow
   ```

2. **检查数据目录权限：**
   ```bash
   ls -la /mnt/new_disk/ragflow_esdata
   ```

3. **验证配置文件：**
   ```bash
   docker-compose config
   ```

4. **参考相关文档：**
   - `ES_DISK_ISSUE_FIX.md` - 磁盘问题修复
   - `DEPLOYMENT_GUIDE.md` - 部署指南

---

## 💡 最佳实践

1. **定期监控磁盘使用率**
   ```bash
   # 添加到 cron 每天检查
   0 8 * * * df -h /mnt/new_disk >> /var/log/disk-monitor.log
   ```

2. **设置磁盘空间告警**
   - 使用量 > 70%：警告
   - 使用量 > 85%：告警
   - 使用量 > 95%：紧急

3. **定期备份**
   - 建议每周备份一次 ES 索引
   - 使用 ES snapshot API
   - 或定期 rsync 到备份磁盘

4. **考虑使用 LVM**
   - 便于未来扩容
   - 可以动态调整分区大小

---

## ✨ 总结

**推荐流程：**
1. 使用自动脚本：`sudo ./migrate-es-disk.sh`
2. 按提示操作
3. 验证迁移结果
4. 确认无误后删除备份

**关键点：**
- ✅ 迁移前务必备份
- ✅ 新磁盘至少是当前数据的 2 倍
- ✅ 选择低峰期进行迁移
- ✅ 验证数据完整性
- ✅ 保留备份直到确认稳定运行

祝迁移顺利！🎉



