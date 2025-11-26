# Elasticsearch 磁盘空间问题解决指南

## 🔴 问题诊断

### 错误信息
```
Exception: Insert chunk error: disk usage exceeded flood-stage watermark, 
index has read-only-allow-delete block
```

### 根本原因
- **Elasticsearch 数据磁盘使用率：100%**
- 磁盘：`/dev/sdc2` - 1.8TB 总空间，已用 1.7TB，仅剩 1.7GB
- 触发了 Elasticsearch 的保护机制，索引被设为只读

---

## 🚀 快速修复（3 步解决）

### 方法 A：使用自动脚本（推荐）

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
./fix-es-disk.sh
```

脚本会自动：
1. ✅ 检查磁盘状态
2. ✅ 显示所有索引大小
3. ✅ 调整 watermark 阈值
4. ✅ 解除索引只读锁
5. ✅ 提供清理选项

---

### 方法 B：手动修复（3 个命令）

#### 步骤 1：临时调整 Watermark 阈值
```bash
curl -u elastic:infiniFlow123 -X PUT "http://localhost:1201/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "cluster.routing.allocation.disk.watermark.low": "95%",
      "cluster.routing.allocation.disk.watermark.high": "97%",
      "cluster.routing.allocation.disk.watermark.flood_stage": "99%"
    }
  }'
```

#### 步骤 2：解除所有索引的只读锁
```bash
curl -u elastic:infiniFlow123 -X PUT "http://localhost:1201/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index.blocks.read_only_allow_delete": null
  }'
```

#### 步骤 3：清理旧数据（选择一种）

**选项 A：查看并删除指定索引**
```bash
# 查看所有索引及大小
curl -u elastic:infiniFlow123 "http://localhost:1201/_cat/indices?v&h=index,docs.count,store.size&s=store.size:desc"

# 删除特定索引（替换 INDEX_NAME）
curl -u elastic:infiniFlow123 -X DELETE "http://localhost:1201/INDEX_NAME"
```

**选项 B：删除旧的 RAGFlow 索引**
```bash
# 列出所有 ragflow 相关索引
curl -u elastic:infiniFlow123 "http://localhost:1201/_cat/indices?v" | grep ragflow

# 删除旧索引（根据实际情况调整）
curl -u elastic:infiniFlow123 -X DELETE "http://localhost:1201/ragflow_*?ignore_unavailable=true"
```

**选项 C：优化现有索引（合并段，减少空间）**
```bash
curl -u elastic:infiniFlow123 -X POST "http://localhost:1201/_all/_forcemerge?max_num_segments=1"
```

---

## 📊 验证修复

### 1. 检查磁盘空间
```bash
docker exec ragflow-es-01 df -h /usr/share/elasticsearch/data
```

### 2. 检查集群健康
```bash
curl -u elastic:infiniFlow123 "http://localhost:1201/_cluster/health?pretty"
```

### 3. 验证索引可写
```bash
curl -u elastic:infiniFlow123 "http://localhost:1201/_cat/indices?v&h=index,status,health"
```

---

## 🔧 长期解决方案

### 方案 1：扩展磁盘空间（最彻底）

1. **挂载新磁盘**
2. **迁移 Elasticsearch 数据目录**

```bash
# 停止服务
cd /mnt/data6t/wangxiaojing/rag_flow/docker
docker-compose down

# 假设新磁盘挂载在 /mnt/new_disk
# 复制数据
sudo rsync -av /var/lib/docker/volumes/docker_esdata01/_data/ /mnt/new_disk/esdata/

# 修改 docker-compose-base.yml，添加新的卷路径
# volumes:
#   esdata01:
#     driver: local
#     driver_opts:
#       type: none
#       o: bind
#       device: /mnt/new_disk/esdata

# 重启服务
docker-compose up -d
```

### 方案 2：设置索引生命周期管理（ILM）

创建自动清理策略：

```bash
# 创建 ILM 策略：保留 30 天
curl -u elastic:infiniFlow123 -X PUT "http://localhost:1201/_ilm/policy/ragflow_policy" \
  -H 'Content-Type: application/json' \
  -d '{
    "policy": {
      "phases": {
        "hot": {
          "actions": {}
        },
        "delete": {
          "min_age": "30d",
          "actions": {
            "delete": {}
          }
        }
      }
    }
  }'

# 应用到索引模板
curl -u elastic:infiniFlow123 -X PUT "http://localhost:1201/_index_template/ragflow_template" \
  -H 'Content-Type: application/json' \
  -d '{
    "index_patterns": ["ragflow_*"],
    "template": {
      "settings": {
        "index.lifecycle.name": "ragflow_policy"
      }
    }
  }'
```

### 方案 3：定期清理任务

创建定时清理脚本 `/mnt/data6t/wangxiaojing/rag_flow/docker/cleanup-es-cron.sh`：

```bash
#!/bin/bash
# 每周清理 30 天前的索引

ES_HOST="localhost:1201"
ES_USER="elastic"
ES_PASS="infiniFlow123"

# 删除 30 天前的索引
date_30days_ago=$(date -d '30 days ago' +%Y.%m.%d)

curl -s -u "${ES_USER}:${ES_PASS}" -X GET "http://${ES_HOST}/_cat/indices?h=index" | while read index; do
  # 检查索引日期是否早于 30 天前
  if [[ $index =~ [0-9]{4}\.[0-9]{2}\.[0-9]{2} ]]; then
    index_date=$(echo $index | grep -oP '\d{4}\.\d{2}\.\d{2}')
    if [[ "$index_date" < "$date_30days_ago" ]]; then
      echo "Deleting old index: $index"
      curl -s -u "${ES_USER}:${ES_PASS}" -X DELETE "http://${ES_HOST}/$index"
    fi
  fi
done
```

添加到 crontab：
```bash
chmod +x /mnt/data6t/wangxiaojing/rag_flow/docker/cleanup-es-cron.sh
crontab -e
# 添加：每周日凌晨 2 点执行
0 2 * * 0 /mnt/data6t/wangxiaojing/rag_flow/docker/cleanup-es-cron.sh >> /var/log/es-cleanup.log 2>&1
```

### 方案 4：清理 Docker 系统缓存

```bash
# 清理未使用的镜像和容器
docker system prune -a --volumes

# 注意：这会删除所有未使用的资源！请谨慎操作
```

---

## ⚠️ 重要配置参考

### Elasticsearch Watermark 默认值

```yaml
cluster.routing.allocation.disk.watermark.low: 85%    # 警告阈值
cluster.routing.allocation.disk.watermark.high: 90%   # 不再分配新分片
cluster.routing.allocation.disk.watermark.flood_stage: 95%  # 索引只读
```

### 修改 docker-compose-base.yml 中的配置

```yaml
environment:
  - cluster.routing.allocation.disk.watermark.low=5gb
  - cluster.routing.allocation.disk.watermark.high=3gb
  - cluster.routing.allocation.disk.watermark.flood_stage=2gb
```

**注意：** 这些是默认配置，已经设置为使用绝对值（GB），但当前磁盘只剩 1.7GB，所以仍然触发了限制。

---

## 📈 监控建议

### 1. 设置磁盘空间监控

```bash
# 添加到监控脚本
watch -n 60 'docker exec ragflow-es-01 df -h /usr/share/elasticsearch/data'
```

### 2. 使用 Elasticsearch API 监控

```bash
# 查看集群磁盘使用情况
curl -u elastic:infiniFlow123 "http://localhost:1201/_cat/allocation?v"

# 查看节点统计
curl -u elastic:infiniFlow123 "http://localhost:1201/_nodes/stats/fs?pretty"
```

---

## 🎯 推荐操作流程

### 立即执行（紧急修复）

1. **运行修复脚本**
   ```bash
   cd /mnt/data6t/wangxiaojing/rag_flow/docker
   ./fix-es-disk.sh
   ```

2. **选择清理选项**
   - 推荐：删除 7 天前的旧索引
   - 或手动删除不需要的知识库索引

3. **验证修复**
   ```bash
   docker-compose logs -f ragflow
   ```

### 后续规划（长期维护）

1. **评估磁盘需求**
   - 当前 ES 占用：1.7TB
   - 建议扩容到 3TB+ 或定期清理

2. **实施自动清理**
   - 设置 ILM 策略（30 天自动删除）
   - 配置定时任务清理

3. **监控告警**
   - 设置磁盘使用率告警（>80%）
   - 定期检查 ES 健康状态

---

## 🆘 紧急情况处理

如果以上方法都不行，**终极方案**：

```bash
# 1. 备份重要数据
# 2. 停止服务
docker-compose down

# 3. 删除 Elasticsearch 数据卷（会丢失所有数据！）
docker volume rm docker_esdata01

# 4. 重新创建卷并启动
docker-compose up -d

# 5. 重新索引文档
# 在 RAGFlow UI 中重新解析文档
```

**⚠️ 警告：此方法会导致所有知识库需要重新解析！**

---

## 📞 问题排查清单

- [ ] 磁盘空间已释放到 < 90%
- [ ] 索引只读锁已解除
- [ ] 集群状态为 green 或 yellow
- [ ] RAGFlow 可以正常上传和解析文档
- [ ] 已设置长期清理策略

---

## 📝 总结

**当前状态：** Elasticsearch 磁盘 100% 满
**推荐方案：** 先运行 `./fix-es-disk.sh` 临时解决，然后规划磁盘扩容或定期清理策略
**预计修复时间：** 5-10 分钟



