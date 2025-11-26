# Elasticsearch 数据迁移到 /mnt/data6t 方案

## 目标
将Elasticsearch数据从Docker volume迁移到 `/mnt/data6t/ragflow_esdata`，以获得更多存储空间（60GB可用）。

## 迁移步骤

### 1. 准备工作

首先检查当前状态：

```bash
# 检查ES健康状态
curl -X GET "http://localhost:1201/_cluster/health?pretty" -u elastic:infini_rag_flow

# 检查当前数据大小
docker exec ragflow-es-01 du -sh /usr/share/elasticsearch/data
```

### 2. 停止服务

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker

# 停止RAGFlow服务
docker-compose -f docker-compose.yml stop ragflow

# 停止ES服务
docker-compose -f docker-compose-base.yml stop es01
```

### 3. 备份和准备目标目录

```bash
# 如果已存在旧数据，先备份
if [ -d "/mnt/data6t/ragflow_esdata" ]; then
    sudo mv /mnt/data6t/ragflow_esdata /mnt/data6t/ragflow_esdata_backup_$(date +%Y%m%d_%H%M%S)
fi

# 创建新目录
sudo mkdir -p /mnt/data6t/ragflow_esdata
```

### 4. 复制数据

```bash
# 复制ES数据
sudo cp -rp /var/lib/docker/volumes/docker_esdata01/_data/* /mnt/data6t/ragflow_esdata/

# 设置正确的权限（ES运行用户是UID 1000）
sudo chown -R 1000:1000 /mnt/data6t/ragflow_esdata
sudo chmod -R 755 /mnt/data6t/ragflow_esdata
```

### 5. 修改Docker Compose配置

编辑 `/mnt/data6t/wangxiaojing/rag_flow/docker/docker-compose-base.yml`:

```yaml
# 找到 es01 服务的配置
services:
  es01:
    container_name: ragflow-es-01
    profiles:
      - elasticsearch
    image: elasticsearch:${STACK_VERSION}
    volumes:
      # 修改这一行
      # - esdata01:/usr/share/elasticsearch/data
      - /mnt/data6t/ragflow_esdata:/usr/share/elasticsearch/data
    ports:
      - ${ES_PORT}:9200
    # ... 其余配置保持不变
```

### 6. 启动服务

```bash
# 启动ES服务
docker-compose -f docker-compose-base.yml up -d es01

# 等待ES启动完成（约30秒）
sleep 30

# 检查ES状态
curl -X GET "http://localhost:1201/_cluster/health?pretty" -u elastic:infini_rag_flow

# 如果ES健康，启动RAGFlow
docker-compose -f docker-compose.yml up -d ragflow
```

### 7. 验证迁移

```bash
# 检查索引是否正常
curl -X GET "http://localhost:1201/_cat/indices?v" -u elastic:infini_rag_flow

# 测试搜索功能
curl -X GET "http://localhost:1201/ragflow_03135d329ce411f09cb50242ac170006/_count" -u elastic:infini_rag_flow
```

### 8. 清理旧数据（确认一切正常后）

```bash
# 删除旧的Docker volume（可选，建议先保留一段时间）
# docker volume rm docker_esdata01
```

## 注意事项

1. **备份重要数据**：在迁移前确保有完整备份
2. **检查权限**：ES需要对数据目录有完全的读写权限
3. **监控日志**：迁移后密切关注ES日志
   ```bash
   docker logs -f ragflow-es-01
   ```

4. **磁盘空间监控**：设置定期检查磁盘空间的脚本

## 回滚方案

如果出现问题，可以快速回滚：

```bash
# 停止服务
docker-compose -f docker-compose.yml stop ragflow
docker-compose -f docker-compose-base.yml stop es01

# 恢复原配置
# 将 docker-compose-base.yml 中的 volume 配置改回：
# - esdata01:/usr/share/elasticsearch/data

# 重启服务
docker-compose -f docker-compose-base.yml up -d es01
docker-compose -f docker-compose.yml up -d ragflow
```

## 长期建议

1. **定期清理**：
   - 设置索引生命周期管理（ILM）
   - 定期删除旧的索引数据

2. **监控告警**：
   - 当磁盘使用率达到80%时发出告警
   - 自动清理日志文件

3. **数据归档**：
   - 将旧数据归档到冷存储
   - 只保留最近N天的热数据