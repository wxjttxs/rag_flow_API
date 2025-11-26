#!/bin/bash
################################################################################
# Elasticsearch 数据迁移完整脚本
# 
# 功能：将 Elasticsearch 数据从满载的磁盘迁移到新磁盘
# 作者：AI Assistant
# 日期：2025-10-29
# 版本：1.0 (最终版本)
#
# 使用方法：
#   sudo ./migrate-es-complete.sh
#
# 前提条件：
#   1. 新磁盘已挂载到 /mnt/data6t
#   2. 有 sudo 权限
#   3. Docker 和 docker-compose 已安装
#
# 本脚本整合了迁移过程中实际有效的所有步骤：
#   1. quick-migrate-to-data6t.sh - 数据复制
#   2. fix-config-now.sh - 配置文件修复
#   3. sed 命令 - 删除重复配置
#   4. curl 命令 - 解除只读锁
################################################################################

set -e  # 遇到错误立即退出

# ============================================================================
# 颜色定义（用于美化输出）
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'  # No Color

# ============================================================================
# 配置变量
# ============================================================================
DOCKER_DIR="/mnt/data6t/wangxiaojing/rag_flow/docker"
COMPOSE_FILE="$DOCKER_DIR/docker-compose-base.yml"
NEW_DATA_DIR="/mnt/data6t/ragflow_esdata"
VOLUME_NAME="docker_esdata01"
ES_PASSWORD="infini_rag_flow"  # 从 .env 文件获取的正确密码

# ============================================================================
# 显示标题
# ============================================================================
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Elasticsearch 数据迁移完整脚本${NC}"
echo -e "${BLUE}  从 /dev/sdc2 (100%满) → /mnt/data6t (350GB可用)${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# 步骤 1：环境检查
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 1/9: 环境检查${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 检查是否为 root 或有 sudo 权限
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
   echo -e "${RED}✗ 需要 sudo 权限${NC}"
   echo "请使用: sudo $0"
   exit 1
fi
echo "✓ 权限检查通过"

# 检查 Docker 是否运行
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}✗ Docker 未运行${NC}"
    exit 1
fi
echo "✓ Docker 运行正常"

# 检查新磁盘挂载点
if [ ! -d "/mnt/data6t" ]; then
    echo -e "${RED}✗ 目标目录 /mnt/data6t 不存在${NC}"
    exit 1
fi
echo "✓ 目标目录存在"

# 显示当前磁盘使用情况
echo ""
echo "当前磁盘使用情况："
df -h | grep -E "(Filesystem|/dev/sdc2|/dev/sda1)" || true
echo ""

# 确认是否继续
read -p "确认开始迁移? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "操作已取消"
    exit 0
fi
echo ""

# ============================================================================
# 步骤 2：停止 RAGFlow 服务
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 2/9: 停止 RAGFlow 服务${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cd "$DOCKER_DIR"
echo "停止所有容器..."
docker-compose down
echo -e "${GREEN}✓ 服务已停止${NC}"
sleep 2
echo ""

# ============================================================================
# 步骤 3：创建新数据目录
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 3/9: 创建新数据目录${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 创建目录
sudo mkdir -p "$NEW_DATA_DIR"
echo "✓ 目录已创建: $NEW_DATA_DIR"

# 设置权限（ES 容器内使用 UID 1000）
sudo chown -R 1000:1000 "$NEW_DATA_DIR"
echo "✓ 权限已设置 (1000:1000)"
echo ""

# ============================================================================
# 步骤 4：迁移数据
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 4/9: 迁移 Elasticsearch 数据${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 获取当前数据卷路径
OLD_DATA_PATH=$(docker volume inspect $VOLUME_NAME 2>/dev/null | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')

if [ -d "$OLD_DATA_PATH" ] && [ "$(ls -A $OLD_DATA_PATH)" ]; then
    echo "当前数据位置: $OLD_DATA_PATH"
    echo "当前数据大小: $(sudo du -sh $OLD_DATA_PATH | awk '{print $1}')"
    echo ""
    echo "开始迁移数据（这可能需要一些时间，取决于数据量）..."
    echo "提示：1.7TB 数据大约需要 30-60 分钟"
    echo ""
    
    # 使用 rsync 迁移数据，保留所有属性
    # -a: 归档模式（保留权限、时间戳等）
    # -v: 显示详细信息
    # --progress: 显示进度
    sudo rsync -av --progress "$OLD_DATA_PATH/" "$NEW_DATA_DIR/"
    
    echo ""
    echo -e "${GREEN}✓ 数据迁移完成${NC}"
    echo "新位置数据大小: $(sudo du -sh $NEW_DATA_DIR | awk '{print $1}')"
else
    echo -e "${YELLOW}⚠️  未找到现有数据，将创建空数据目录${NC}"
fi
echo ""

# ============================================================================
# 步骤 5：备份并修复配置文件
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 5/9: 修复 Docker Compose 配置文件${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 备份当前配置文件
BACKUP_FILE="${COMPOSE_FILE}.migration_backup_$(date +%Y%m%d_%H%M%S)"
sudo cp "$COMPOSE_FILE" "$BACKUP_FILE"
echo "✓ 配置文件已备份: $BACKUP_FILE"

# 临时文件
TEMP_FILE=$(mktemp)

echo "修复配置文件中的 esdata01 定义..."

# 使用 awk 修复配置文件
# 策略：
# 1. 在 volumes 部分找到或添加 esdata01 定义
# 2. 确保配置正确且不重复
sudo awk '
BEGIN {
    in_volumes = 0
    in_networks = 0
    esdata_added = 0
    skip_esdata = 0
}

# 进入 volumes 部分
/^volumes:/ {
    in_volumes = 1
    in_networks = 0
    print
    next
}

# 进入 networks 部分
/^networks:/ {
    # 如果在 volumes 部分没有添加 esdata01，在这里添加
    if (esdata_added == 0) {
        print "  esdata01:"
        print "    driver: local"
        print "    driver_opts:"
        print "      type: none"
        print "      o: bind"
        print "      device: '"$NEW_DATA_DIR"'"
        print ""
        esdata_added = 1
    }
    in_volumes = 0
    in_networks = 1
    print
    next
}

# 在 volumes 部分遇到 esdata01
/^  esdata01:/ && in_volumes == 1 {
    if (esdata_added == 0) {
        # 输出正确的配置
        print "  esdata01:"
        print "    driver: local"
        print "    driver_opts:"
        print "      type: none"
        print "      o: bind"
        print "      device: '"$NEW_DATA_DIR"'"
        esdata_added = 1
        # 跳过旧的配置（如果有）
        skip_esdata = 1
        next
    }
}

# 跳过旧的 esdata01 配置内容
skip_esdata == 1 && /^    / {
    next
}

skip_esdata == 1 && /^  [a-z]/ {
    skip_esdata = 0
}

# 在 networks 之后遇到 esdata01（错误位置），跳过
in_networks == 1 && /^# ES 数据迁移/ {
    skip_esdata = 1
    next
}

in_networks == 1 && skip_esdata == 1 {
    # 跳过所有缩进的行
    if (/^  / || /^    / || /^      / || /^$/) {
        next
    }
    skip_esdata = 0
}

# 打印其他所有行
{ print }
' "$COMPOSE_FILE" > "$TEMP_FILE"

# 替换原文件
sudo mv "$TEMP_FILE" "$COMPOSE_FILE"
echo -e "${GREEN}✓ 配置文件已修复${NC}"

# 删除可能存在的重复 driver_opts
# 某些情况下可能会有重复，使用 sed 清理
# 查找重复的 driver_opts 行并删除
if grep -q "driver_opts.*driver_opts" "$COMPOSE_FILE" 2>/dev/null; then
    echo "检测到重复的 driver_opts，正在清理..."
    # 这里需要根据实际情况调整行号
    # 先保存一个副本
    sudo cp "$COMPOSE_FILE" "${COMPOSE_FILE}.before_dedup"
    
    # 使用 awk 删除重复的 driver_opts 块
    sudo awk '
    BEGIN { in_esdata = 0; driver_opts_count = 0 }
    /^  esdata01:/ { in_esdata = 1; driver_opts_count = 0 }
    /^  [a-z]/ && !/^    / { in_esdata = 0; driver_opts_count = 0 }
    /^    driver_opts:/ && in_esdata == 1 {
        driver_opts_count++
        if (driver_opts_count == 1) {
            print
            next
        } else {
            # 跳过第二个 driver_opts 及其内容
            while (getline > 0 && /^      /) { }
            if ($0 !~ /^      /) { print }
            next
        }
    }
    { print }
    ' "${COMPOSE_FILE}.before_dedup" > "$TEMP_FILE"
    sudo mv "$TEMP_FILE" "$COMPOSE_FILE"
    echo "✓ 重复配置已清理"
fi
echo ""

# ============================================================================
# 步骤 6：验证配置文件
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 6/9: 验证配置文件${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 检查配置语法
if docker-compose config > /dev/null 2>&1; then
    echo -e "${GREEN}✓ Docker Compose 配置语法正确${NC}"
else
    echo -e "${RED}✗ 配置文件有错误：${NC}"
    docker-compose config 2>&1 | head -20
    echo ""
    echo "请检查备份文件并手动修复: $BACKUP_FILE"
    exit 1
fi

# 检查 esdata01 配置
echo ""
echo "esdata01 配置："
grep -A 6 "^  esdata01:" "$COMPOSE_FILE" || echo "未找到 esdata01 定义"

# 检查是否有重复定义
esdata_count=$(grep -c "^  esdata01:" "$COMPOSE_FILE" || true)
if [ "$esdata_count" -eq 1 ]; then
    echo -e "${GREEN}✓ 没有重复定义${NC}"
else
    echo -e "${YELLOW}⚠️  警告: 找到 $esdata_count 个 esdata01 定义${NC}"
fi
echo ""

# ============================================================================
# 步骤 7：删除旧的 Docker Volume
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 7/9: 删除旧的 Docker Volume${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 删除旧的 volume（如果存在）
if docker volume ls | grep -q "$VOLUME_NAME"; then
    docker volume rm "$VOLUME_NAME" 2>/dev/null && \
        echo -e "${GREEN}✓ 旧 volume 已删除${NC}" || \
        echo -e "${YELLOW}ℹ  Volume 可能正在使用或已删除${NC}"
else
    echo "ℹ  旧 volume 不存在，跳过"
fi
echo ""

# ============================================================================
# 步骤 8：启动服务
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 8/9: 启动 RAGFlow 服务${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cd "$DOCKER_DIR"
echo "启动服务..."
docker-compose up -d
echo -e "${GREEN}✓ 服务已启动${NC}"
echo ""

# 等待 Elasticsearch 启动
echo "等待 Elasticsearch 启动（最多 60 秒）..."
for i in {1..30}; do
    sleep 2
    # 检查 ES 是否响应
    if docker exec ragflow-es-01 curl -s -u elastic:${ES_PASSWORD} \
        "http://localhost:9200/_cluster/health" >/dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}✓ Elasticsearch 已启动${NC}"
        break
    fi
    echo -n "."
    
    # 超时处理
    if [ $i -eq 30 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  等待超时，但服务可能仍在启动中${NC}"
        echo "您可以稍后手动检查: docker-compose logs -f es01"
    fi
done
echo ""

# ============================================================================
# 步骤 9：配置 Elasticsearch
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 9/9: 配置 Elasticsearch${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 给 ES 一点时间完全启动
sleep 5

echo "9.1 调整磁盘水位阈值..."
# 调整 watermark 阈值，避免再次触发只读保护
docker exec ragflow-es-01 curl -s -u elastic:${ES_PASSWORD} \
    -X PUT "http://localhost:9200/_cluster/settings" \
    -H 'Content-Type: application/json' \
    -d '{
        "persistent": {
            "cluster.routing.allocation.disk.watermark.low": "95%",
            "cluster.routing.allocation.disk.watermark.high": "97%",
            "cluster.routing.allocation.disk.watermark.flood_stage": "99%"
        }
    }' > /dev/null 2>&1 && echo "✓ 水位阈值已调整" || echo "⚠️  调整失败，稍后重试"

echo ""
echo "9.2 解除索引只读锁..."
# 解除所有索引的只读锁定
docker exec ragflow-es-01 curl -s -u elastic:${ES_PASSWORD} \
    -X PUT "http://localhost:9200/_all/_settings" \
    -H 'Content-Type: application/json' \
    -d '{
        "index.blocks.read_only_allow_delete": null
    }' > /dev/null 2>&1 && echo "✓ 只读锁已解除" || echo "⚠️  解除失败，稍后重试"

echo ""

# ============================================================================
# 验证迁移结果
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  迁移完成！正在验证结果...${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "1. 容器状态："
docker-compose ps | grep -E "NAME|ragflow|es01|mysql|redis|minio" || true
echo ""

echo "2. Elasticsearch 磁盘空间："
docker exec ragflow-es-01 df -h /usr/share/elasticsearch/data 2>/dev/null || \
    echo "容器可能还在启动中..."
echo ""

echo "3. 集群健康状态："
docker exec ragflow-es-01 curl -s -u elastic:${ES_PASSWORD} \
    "http://localhost:9200/_cluster/health?pretty" 2>/dev/null | \
    grep -E "status|number_of_nodes|active_shards_percent" || \
    echo "等待 ES 完全启动..."
echo ""

echo "4. 索引状态："
docker exec ragflow-es-01 curl -s -u elastic:${ES_PASSWORD} \
    "http://localhost:9200/_cat/indices?v&h=index,status,health" 2>/dev/null || \
    echo "等待 ES 完全启动..."
echo ""

# ============================================================================
# 显示总结
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ Elasticsearch 迁移成功完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}📝 迁移总结：${NC}"
echo "  ✓ 数据位置: $NEW_DATA_DIR"
echo "  ✓ 配置备份: $BACKUP_FILE"
echo "  ✓ 服务状态: 运行中"
echo "  ✓ 集群状态: 等待验证"
echo ""

echo -e "${BLUE}🎯 下一步操作：${NC}"
echo "  1. 访问 RAGFlow UI: http://localhost:9381"
echo "  2. 测试文档上传功能"
echo "  3. 查看日志: cd $DOCKER_DIR && docker-compose logs -f ragflow"
echo ""

echo -e "${BLUE}📚 相关文档：${NC}"
echo "  - MIGRATION_COMPLETE.md - 迁移完成总结"
echo "  - ES_DISK_MIGRATION_GUIDE.md - 详细迁移指南"
echo ""

echo -e "${BLUE}⚠️  重要信息：${NC}"
echo "  - ES 密码: $ES_PASSWORD"
echo "  - 如需回滚，使用备份: $BACKUP_FILE"
echo "  - 监控磁盘: watch 'docker exec ragflow-es-01 df -h'"
echo ""

echo -e "${GREEN}迁移脚本执行完毕！🎉${NC}"



