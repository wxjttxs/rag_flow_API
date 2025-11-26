# ES迁移脚本说明文档

## 当前目录中的ES相关脚本

### ✅ 实际使用的脚本

#### 1. **fix-es-mount.sh** （最终使用的脚本）
- **创建时间**: 11月 25 16:24
- **用途**: 修复ES数据挂载配置，将Docker volume改为bind mount
- **状态**: ✅ **这是实际起作用的脚本**
- **功能**:
  - 将ES数据挂载从Docker volume改为直接挂载到 `/mnt/data6t/ragflow_esdata`
  - 自动备份配置文件
  - 处理已有数据的迁移

### ❌ 未使用的脚本（仅供参考）

#### 2. **migrate-es-quick.sh**
- **创建时间**: 11月 25 16:20
- **用途**: 快速迁移ES数据
- **状态**: ❌ 未使用（因为您之前已经迁移过）
- **问题**: 尝试从不存在的Docker volume复制数据

#### 3. **migrate-es-data.sh**
- **创建时间**: 11月 25 16:19
- **用途**: ES数据迁移的详细脚本
- **状态**: ❌ 未使用（只是一个模板）

#### 4. **migrate-es-complete.sh**
- **创建时间**: 10月 31 15:25
- **用途**: 完整的ES迁移脚本（可能是之前某次迁移使用的）
- **状态**: ⚠️ 可能是之前的迁移脚本

---

## 当前ES配置状态

### 数据位置
```
ES数据目录: /mnt/data6t/ragflow_esdata
```

### Docker Compose配置
```yaml
# docker-compose-base.yml
services:
  es01:
    volumes:
      - /mnt/data6t/ragflow_esdata:/usr/share/elasticsearch/data
```

### 磁盘水位线设置
```json
{
  "cluster.routing.allocation.disk.watermark.low": "95%",
  "cluster.routing.allocation.disk.watermark.high": "97%",
  "cluster.routing.allocation.disk.watermark.flood_stage": "99%"
}
```

---

## 如果需要重新配置

如果将来需要调整ES配置，使用以下命令：

```bash
# 1. 查看当前配置
grep -A2 "volumes:" /mnt/data6t/wangxiaojing/rag_flow/docker/docker-compose-base.yml | grep -A1 "es01:"

# 2. 检查ES数据位置
docker inspect ragflow-es-01 | grep -A5 "Mounts"

# 3. 查看磁盘使用情况
df -h /mnt/data6t

# 4. 检查ES健康状态
curl -X GET "http://localhost:1201/_cluster/health?pretty" -u elastic:infini_rag_flow
```

---

## 注意事项

1. **不要重复执行迁移脚本**，当前配置已经正确
2. 如需修改配置，先备份 `docker-compose-base.yml`
3. 定期检查磁盘空间，避免再次触发只读模式

---

## 备份文件

当前目录下有多个配置文件备份：
- `docker-compose-base.yml.fix_mount_backup_20251125_162519` - 最新的备份
- 其他 `.backup_*` 文件是历史备份，可以保留作为参考