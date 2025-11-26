# Docker 环境代码更新指南

## 快速重启（推荐）

由于代码是通过 volumes 挂载到容器中的，修改后只需要重启容器即可生效：

```bash
# 进入 docker 目录
cd docker

# 重启 ragflow 服务（只重启 ragflow 容器，不影响其他服务）
docker-compose restart ragflow

# 或者使用容器名
docker restart ragflow-server
```

## 查看日志确认

重启后查看日志，确认代码已生效：

```bash
# 查看 ragflow 容器日志
docker logs -f ragflow-server

# 或者使用 docker-compose
cd docker
docker-compose logs -f ragflow
```

## 验证修改是否生效

### 1. 检查缓存清理功能

在日志中查找以下信息，确认清理任务已启动：
- `Starting retrieval cache cleanup task (delayed)`
- `Starting retrieval cache cleanup. Found X cache keys`

### 2. 检查缓存配置

可以通过日志确认配置参数：
- 缓存过期时间：6个月（180天）
- 最大缓存大小：10GB
- 最大缓存年龄：3个月（90天）

### 3. 测试缓存功能

发送一个检索请求，然后再次发送相同的请求，应该看到：
- 第一次：`Performing retrieval for key: ...`
- 第二次：`Retrieval cache hit for key: ...`

## 完整重启（如果需要）

如果需要完全重新加载所有配置：

```bash
cd docker

# 停止服务
docker-compose stop ragflow

# 启动服务
docker-compose start ragflow

# 或者停止并启动
docker-compose down ragflow
docker-compose up -d ragflow
```

## 强制重新加载（如果重启无效）

如果重启后代码仍未生效，可能需要：

```bash
cd docker

# 停止并删除容器（不会删除数据卷）
docker-compose stop ragflow
docker-compose rm -f ragflow

# 重新创建并启动容器
docker-compose up -d ragflow
```

## 检查代码挂载

确认代码已正确挂载：

```bash
# 进入容器检查文件
docker exec -it ragflow-server bash

# 在容器内检查文件是否存在
ls -la /ragflow/api/apps/api_app.py
ls -la /ragflow/rag/utils/redis_conn.py

# 检查文件内容（确认修改已生效）
grep "RETRIEVAL_CACHE_MAX_SIZE" /ragflow/api/apps/api_app.py
grep "cleanup_retrieval_cache" /ragflow/api/apps/api_app.py
```

## 常见问题

### 1. 修改后没有生效

**原因**：Python 可能缓存了模块
**解决**：
```bash
# 完全重启容器
docker-compose restart ragflow

# 如果还不行，强制重新创建
docker-compose up -d --force-recreate ragflow
```

### 2. 清理任务没有启动

**检查**：
- 查看日志是否有错误
- 确认 Redis 连接正常
- 确认容器已完全启动

### 3. 缓存清理不工作

**检查**：
```bash
# 检查 Redis 连接
docker exec -it ragflow-server python -c "from rag.utils.redis_conn import REDIS_CONN; print(REDIS_CONN.is_alive())"

# 手动触发清理（在容器内）
docker exec -it ragflow-server python -c "from api.apps.api_app import cleanup_retrieval_cache; cleanup_retrieval_cache()"
```

## 修改的文件清单

本次修改涉及以下文件，都已通过 volumes 挂载：

1. ✅ `api/apps/api_app.py` - 缓存配置和清理函数
2. ✅ `rag/utils/redis_conn.py` - Redis 工具方法
3. ✅ `api/ragflow_server.py` - 定期清理任务

这些文件都在挂载的目录中，修改后重启容器即可生效。

