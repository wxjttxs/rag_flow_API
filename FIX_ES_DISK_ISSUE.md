# 修复 Elasticsearch 磁盘空间问题

## 问题描述

Elasticsearch 索引因磁盘空间不足被设置为只读模式，导致无法删除数据。

错误信息：
```
disk usage exceeded flood-stage watermark, index has read-only-allow-delete block
```

## 解决步骤

### 1. 首先检查磁盘空间

```bash
# 检查主机磁盘使用情况
df -h

# 查找Docker占用空间
docker system df

# 查找大文件
sudo du -sh /var/lib/docker/volumes/* | sort -rh | head -20
```

### 2. 清理磁盘空间

```bash
# 清理未使用的Docker资源
docker system prune -a --volumes

# 清理ES日志（如果有）
docker exec ragflow-es-01 rm -rf /usr/share/elasticsearch/logs/*

# 清理旧的索引数据（谨慎操作）
# docker exec ragflow-es-01 curl -X DELETE "http://localhost:9200/old_index_name"
```

### 3. 连接到ES并解除只读限制

由于您在Docker环境中，需要通过以下方式连接：

#### 方法1：通过Docker exec执行

```bash
# 进入ES容器
docker exec -it ragflow-es-01 bash

# 在容器内执行以下命令
curl -X PUT "http://localhost:9200/ragflow_03135d329ce411f09cb50242ac170006/_settings" \
  -H "Content-Type: application/json" -d '{
    "index.blocks.read_only_allow_delete": null
  }'

# 或者一行命令执行
docker exec ragflow-es-01 curl -X PUT "http://localhost:9200/ragflow_03135d329ce411f09cb50242ac170006/_settings" \
  -H "Content-Type: application/json" -d '{
    "index.blocks.read_only_allow_delete": null
  }'
```

#### 方法2：通过映射的端口访问

根据您的docker-compose配置，ES端口映射为 ${ES_PORT}:9200，通常是1201：

```bash
# 查看实际的端口映射
docker ps | grep ragflow-es-01

# 使用实际的端口（假设是1201）
curl -X PUT "http://localhost:1201/ragflow_03135d329ce411f09cb50242ac170006/_settings" \
  -H "Content-Type: application/json" -d '{
    "index.blocks.read_only_allow_delete": null
  }'
```

### 4. 解除所有索引的只读限制

```bash
# 通过Docker执行
docker exec ragflow-es-01 curl -X PUT "http://localhost:9200/_all/_settings" \
  -H "Content-Type: application/json" -d '{
    "index.blocks.read_only_allow_delete": null
  }'
```

### 5. 调整磁盘水位线设置（可选）

```bash
docker exec ragflow-es-01 curl -X PUT "http://localhost:9200/_cluster/settings" \
  -H "Content-Type: application/json" -d '{
    "transient": {
      "cluster.routing.allocation.disk.watermark.low": "85%",
      "cluster.routing.allocation.disk.watermark.high": "90%",
      "cluster.routing.allocation.disk.watermark.flood_stage": "95%",
      "cluster.routing.allocation.disk.threshold_enabled": true
    }
  }'
```

### 6. 验证修复结果

```bash
# 检查索引设置
docker exec ragflow-es-01 curl -X GET "http://localhost:9200/ragflow_03135d329ce411f09cb50242ac170006/_settings?pretty"

# 检查集群健康状态
docker exec ragflow-es-01 curl -X GET "http://localhost:9200/_cluster/health?pretty"

# 检查磁盘使用情况
docker exec ragflow-es-01 curl -X GET "http://localhost:9200/_cat/allocation?v"
```

### 7. 测试删除操作

```bash
# 测试删除
docker exec ragflow-es-01 curl -X POST "http://localhost:9200/ragflow_03135d329ce411f09cb50242ac170006/_delete_by_query?refresh=true" \
  -H "Content-Type: application/json" -d '{
    "query": {
      "match_all": {}
    }
  }' | jq '.'
```

## 预防措施

1. **设置磁盘监控**
   - 配置磁盘空间告警
   - 定期检查磁盘使用情况

2. **配置数据生命周期**
   ```bash
   # 创建ILM策略
   docker exec ragflow-es-01 curl -X PUT "http://localhost:9200/_ilm/policy/ragflow_policy" \
     -H "Content-Type: application/json" -d '{
       "policy": {
         "phases": {
           "hot": {
             "actions": {
               "rollover": {
                 "max_size": "50GB",
                 "max_age": "30d"
               }
             }
           },
           "delete": {
             "min_age": "90d",
             "actions": {
               "delete": {}
             }
           }
         }
       }
     }'
   ```

3. **增加存储空间**
   - 扩展Docker存储卷
   - 或迁移到更大的磁盘

## 常见问题

### Q: 为什么会出现这个问题？
A: Elasticsearch为了保护数据完整性，当磁盘空间不足时会自动将索引设置为只读模式。

### Q: read-only-allow-delete是什么意思？
A: 虽然名字中有"allow-delete"，但这个模式实际上会阻止所有写操作，包括删除。这是ES的一个保护机制。

### Q: 如何永久解决？
A: 需要确保有足够的磁盘空间，建议保持至少20%的可用空间。

## 相关命令速查

```bash
# 查看ES日志
docker logs ragflow-es-01 --tail 100

# 查看索引大小
docker exec ragflow-es-01 curl -X GET "http://localhost:9200/_cat/indices?v&s=store.size:desc"

# 查看节点磁盘使用
docker exec ragflow-es-01 curl -X GET "http://localhost:9200/_cat/nodes?v&h=name,disk.avail,disk.used,disk.total,disk.used_percent"
```