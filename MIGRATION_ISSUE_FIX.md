# Elasticsearch 迁移问题修复

## 🔍 问题诊断

### 发现的问题

虽然您已经执行了 `quick-migrate-to-data6t.sh`，但 Elasticsearch 仍然报磁盘满的错误。

**原因分析：**

1. **配置文件有重复定义**
   - `docker-compose-base.yml` 中有**两个** `esdata01` 定义
   - 第一个（旧的）：在 volumes 部分，使用默认 Docker volume
   - 第二个（新的）：在文件末尾，指向 `/mnt/data6t/ragflow_esdata`
   - ⚠️ Docker 使用了第一个定义，忽略了第二个

2. **容器仍挂载旧位置**
   ```bash
   # 实际情况
   容器内看到: /dev/sdc2 (1.8T, 100% 满)
   挂载点: /var/lib/docker/volumes/docker_esdata01/_data
   
   # 期望情况
   容器内应看到: /dev/sda1 (6T, 94%)
   挂载点应该是: /mnt/data6t/ragflow_esdata
   ```

3. **索引仍处于只读状态**
   - 即使迁移了，之前触发的只读锁还在
   - 需要手动解除

---

## ✅ 解决方案

### 方法一：一键修复脚本（推荐）

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./fix-migration.sh
```

**脚本会自动完成：**
1. ✅ 停止服务
2. ✅ 修复配置文件（删除重复的 esdata01 定义）
3. ✅ 删除旧的 Docker volume
4. ✅ 启动服务（使用新的数据目录）
5. ✅ 解除索引只读锁
6. ✅ 验证迁移结果

**预计时间：** 2-3 分钟

---

### 方法二：手动修复

如果您想手动操作，按以下步骤：

#### 步骤 1：停止服务
```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
docker-compose down
```

#### 步骤 2：修复配置文件

编辑 `docker-compose-base.yml`：

**找到这部分（大约在 210-220 行）：**
```yaml
volumes:
  esdata01:
    driver: local      # ← 删除这两行！
  osdata01:
    driver: local
  infinity_data:
    driver: local
  mysql_data:
    driver: local
  minio_data:
    driver: local
  redis_data:
    driver: local
```

**修改为（删除 esdata01 的旧定义）：**
```yaml
volumes:
  osdata01:
    driver: local
  infinity_data:
    driver: local
  mysql_data:
    driver: local
  minio_data:
    driver: local
  redis_data:
    driver: local
```

**保留文件末尾的新定义（应该已经在那里）：**
```yaml
# ES 数据迁移到 /mnt/data6t
  esdata01:
    driver: local
    driver_opts:
      type: none
      o: bind
      device: /mnt/data6t/ragflow_esdata
```

#### 步骤 3：删除旧的 Docker volume
```bash
docker volume rm docker_esdata01
```

#### 步骤 4：启动服务
```bash
docker-compose up -d
```

#### 步骤 5：等待 ES 启动（约 30 秒）
```bash
docker-compose logs -f es01
# 看到 "started" 消息后按 Ctrl+C 退出
```

#### 步骤 6：解除索引只读锁
```bash
# 调整 watermark 阈值
curl -u elastic:infiniFlow123 -X PUT "http://localhost:1201/_cluster/settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "persistent": {
      "cluster.routing.allocation.disk.watermark.low": "95%",
      "cluster.routing.allocation.disk.watermark.high": "97%",
      "cluster.routing.allocation.disk.watermark.flood_stage": "99%"
    }
  }'

# 解除只读锁
curl -u elastic:infiniFlow123 -X PUT "http://localhost:1201/_all/_settings" \
  -H 'Content-Type: application/json' \
  -d '{
    "index.blocks.read_only_allow_delete": null
  }'
```

---

## 🔍 验证修复

### 1. 检查容器挂载
```bash
docker inspect ragflow-es-01 | grep -A 10 Mounts
```

**期望输出：**
```json
"Source": "/mnt/data6t/ragflow_esdata",
"Destination": "/usr/share/elasticsearch/data",
```

### 2. 检查磁盘空间
```bash
docker exec ragflow-es-01 df -h /usr/share/elasticsearch/data
```

**期望输出：**
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/sda1       6.0T  5.4T  350G  94% /usr/share/elasticsearch/data
```

**✅ 应该看到 /dev/sda1（不是 /dev/sdc2）且有 350GB 可用空间**

### 3. 检查集群健康
```bash
curl -u elastic:infiniFlow123 "http://localhost:1201/_cluster/health?pretty"
```

**期望输出：**
```json
{
  "status" : "green" or "yellow",
  ...
}
```

### 4. 测试文档上传
- 访问 RAGFlow UI
- 尝试上传新文档
- 应该不再报磁盘错误

---

## ❓ 常见问题

### Q: 为什么会有两个 esdata01 定义？
**A:** `quick-migrate-to-data6t.sh` 脚本在文件末尾追加了新配置，但没有删除原来的定义。YAML 中同名 key 出现两次，Docker 使用第一个。

### Q: 数据会丢失吗？
**A:** 不会。数据已经在 `/mnt/data6t/ragflow_esdata/`，只是容器还没使用它。

### Q: 为什么要删除旧 volume？
**A:** 如果不删除，Docker 会继续使用旧的 volume 定义。删除后，Docker 会使用新配置创建挂载。

### Q: 修复后还是报错怎么办？
**A:** 
1. 检查容器日志：`docker-compose logs es01`
2. 确认挂载点：`docker inspect ragflow-es-01 | grep Source`
3. 如果还是旧路径，尝试：
   ```bash
   docker-compose down -v  # 强制删除所有 volume
   docker-compose up -d
   ```

---

## 📝 完整检查清单

修复前检查：
- [x] 数据已复制到 `/mnt/data6t/ragflow_esdata/`
- [x] 配置文件有两个 esdata01 定义（问题原因）
- [x] 容器挂载旧位置（/dev/sdc2）

修复后验证：
- [ ] 配置文件只有一个 esdata01 定义（在文件末尾）
- [ ] 容器挂载新位置（/mnt/data6t/ragflow_esdata）
- [ ] 容器内看到 /dev/sda1，有 350GB+ 可用空间
- [ ] 索引只读锁已解除
- [ ] 集群状态为 green/yellow
- [ ] 可以上传新文档

---

## 🚀 快速执行

**推荐：使用自动修复脚本**

```bash
cd /mnt/data6t/wangxiaojing/rag_flow/docker
sudo ./fix-migration.sh
```

**预计 2-3 分钟完成，无需手动操作。**

---

## 📞 如果还有问题

1. 查看容器日志：
   ```bash
   docker-compose logs -f ragflow
   docker-compose logs -f es01
   ```

2. 验证配置：
   ```bash
   docker-compose config | grep -A 10 esdata01
   ```

3. 检查文件结构：
   ```bash
   ls -la /mnt/data6t/ragflow_esdata/
   ```

---

## 💡 总结

**问题核心：** 配置文件中重复定义导致使用了旧配置

**解决方法：** 删除旧定义 + 删除旧 volume + 重启服务

**一行命令：** `sudo ./fix-migration.sh`

✨ 修复后，Elasticsearch 将使用新磁盘，不再报磁盘满错误！



