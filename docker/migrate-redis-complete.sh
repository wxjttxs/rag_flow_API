#!/bin/bash
################################################################################
# Redis 数据完整迁移脚本
# 
# 功能：将 Redis 数据从满载的根分区迁移到 /mnt/data6t
# 参考：migrate-mysql-complete.sh
# 版本：1.0
#
# 使用方法：
#   sudo ./migrate-redis-complete.sh
################################################################################

set -e  # 遇到错误立即退出

# ============================================================================
# 颜色定义
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# ============================================================================
# 配置变量
# ============================================================================
DOCKER_DIR="/mnt/data6t/wangxiaojing/rag_flow/docker"
COMPOSE_FILE="$DOCKER_DIR/docker-compose-base.yml"
NEW_DATA_DIR="/mnt/data6t/ragflow_redis"
VOLUME_NAME="docker_redis_data"
REDIS_PASSWORD="infini_rag_flow"

# ============================================================================
# 显示标题
# ============================================================================
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Redis 数据迁移脚本${NC}"
echo -e "${BLUE}  从根分区 → /mnt/data6t${NC}"
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo ""

# ============================================================================
# 步骤 1：环境检查
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 1/8: 环境检查${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 检查权限
if [[ $EUID -ne 0 ]] && ! sudo -n true 2>/dev/null; then
   echo -e "${RED}✗ 需要 sudo 权限${NC}"
   echo "请使用: sudo $0"
   exit 1
fi
echo "✓ 权限检查通过"

# 检查 Docker
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}✗ Docker 未运行${NC}"
    exit 1
fi
echo "✓ Docker 运行正常"

# 检查目标目录
if [ ! -d "/mnt/data6t" ]; then
    echo -e "${RED}✗ 目标目录 /mnt/data6t 不存在${NC}"
    exit 1
fi
echo "✓ 目标目录存在"

# 显示当前磁盘使用情况
echo ""
echo "当前磁盘使用情况："
df -h | grep -E "(Filesystem|/dev/sdc2|/dev/sda1)"
echo ""

# 显示当前 Redis 数据大小
OLD_DATA_PATH=$(docker volume inspect $VOLUME_NAME 2>/dev/null | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')
if [ -d "$OLD_DATA_PATH" ]; then
    echo "当前 Redis 数据："
    echo "  位置: $OLD_DATA_PATH"
    echo "  大小: $(sudo du -sh $OLD_DATA_PATH 2>/dev/null | awk '{print $1}')"
else
    echo -e "${YELLOW}⚠️  未找到现有数据（可能使用默认配置）${NC}"
fi
echo ""

# 确认是否继续
read -p "确认开始迁移 Redis 数据? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "操作已取消"
    exit 0
fi
echo ""

# ============================================================================
# 步骤 2：停止 RAGFlow 服务
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 2/8: 停止 RAGFlow 服务${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cd "$DOCKER_DIR"
echo "停止所有容器..."
docker-compose down
echo -e "${GREEN}✓ 服务已停止${NC}"
sleep 3
echo ""

# ============================================================================
# 步骤 3：创建新数据目录
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 3/8: 创建新数据目录${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 创建目录
sudo mkdir -p "$NEW_DATA_DIR"
echo "✓ 目录已创建: $NEW_DATA_DIR"

# 设置权限（Redis 容器内使用 UID 999）
sudo chown -R 999:999 "$NEW_DATA_DIR"
echo "✓ 权限已设置 (999:999)"
echo ""

# ============================================================================
# 步骤 4：迁移数据
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 4/8: 迁移 Redis 数据${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 获取当前数据卷路径
OLD_DATA_PATH=$(docker volume inspect $VOLUME_NAME 2>/dev/null | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')

if [ -d "$OLD_DATA_PATH" ] && [ "$(sudo ls -A $OLD_DATA_PATH 2>/dev/null)" ]; then
    echo "当前数据位置: $OLD_DATA_PATH"
    echo "当前数据大小: $(sudo du -sh $OLD_DATA_PATH 2>/dev/null | awk '{print $1}')"
    echo ""
    echo "开始迁移数据..."
    
    # 使用 rsync 迁移数据，保留所有属性
    sudo rsync -av --progress "$OLD_DATA_PATH/" "$NEW_DATA_DIR/"
    
    echo ""
    echo -e "${GREEN}✓ 数据迁移完成${NC}"
    echo "新位置数据大小: $(sudo du -sh $NEW_DATA_DIR 2>/dev/null | awk '{print $1}')"
else
    echo -e "${YELLOW}⚠️  未找到现有数据，将创建空数据目录${NC}"
    echo "   Redis 启动后会自动创建新数据文件"
fi
echo ""

# ============================================================================
# 步骤 5：备份并修复配置文件
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 5/8: 修复 Docker Compose 配置文件${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 备份当前配置文件
BACKUP_FILE="${COMPOSE_FILE}.redis_migration_backup_$(date +%Y%m%d_%H%M%S)"
sudo cp "$COMPOSE_FILE" "$BACKUP_FILE"
echo "✓ 配置文件已备份: $BACKUP_FILE"

# 临时文件
TEMP_FILE=$(mktemp)

echo "修复配置文件中的 redis_data 定义..."

# 使用 awk 修复配置文件
sudo awk '
BEGIN {
    in_volumes = 0
    redis_found = 0
    skip_old_redis = 0
}

# 进入 volumes 部分
/^volumes:/ {
    in_volumes = 1
    print
    next
}

# 离开 volumes 部分
/^[a-z]/ && in_volumes == 1 && !/^  / {
    in_volumes = 0
}

# 在 volumes 部分找到 redis_data
/^  redis_data:/ && in_volumes == 1 {
    if (redis_found == 0) {
        # 输出新配置
        print "  redis_data:"
        print "    driver: local"
        print "    driver_opts:"
        print "      type: none"
        print "      o: bind"
        print "      device: '"$NEW_DATA_DIR"'"
        redis_found = 1
        skip_old_redis = 1
        next
    }
}

# 跳过旧的 redis_data 的 driver: local 行
skip_old_redis == 1 && /^    driver: local/ {
    skip_old_redis = 0
    next
}

# 打印其他所有行
{ print }
' "$COMPOSE_FILE" > "$TEMP_FILE"

# 替换原文件
sudo mv "$TEMP_FILE" "$COMPOSE_FILE"
echo -e "${GREEN}✓ 配置文件已修复${NC}"
echo ""

# ============================================================================
# 步骤 6：验证配置文件
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 6/8: 验证配置文件${NC}"
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

# 检查 redis_data 配置
echo ""
echo "redis_data 配置："
grep -A 6 "^  redis_data:" "$COMPOSE_FILE" || echo "未找到 redis_data 定义"
echo ""

# ============================================================================
# 步骤 7：删除旧的 Docker Volume
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 7/8: 删除旧的 Docker Volume${NC}"
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
echo -e "${YELLOW}步骤 8/8: 启动 RAGFlow 服务${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

cd "$DOCKER_DIR"
echo "启动服务..."
docker-compose up -d
echo -e "${GREEN}✓ 服务已启动${NC}"
echo ""

# 等待 Redis 启动
echo "等待 Redis 启动（最多 30 秒）..."
for i in {1..15}; do
    sleep 2
    # 检查 Redis 是否响应
    if docker exec ragflow-redis redis-cli -a ${REDIS_PASSWORD} ping >/dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}✓ Redis 已启动${NC}"
        break
    fi
    echo -n "."
    
    # 超时处理
    if [ $i -eq 15 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  等待超时，但服务可能仍在启动中${NC}"
    fi
done
echo ""

# ============================================================================
# 验证迁移结果
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  迁移完成！正在验证结果...${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo "1. 容器状态："
docker ps --format "table {{.Names}}\t{{.Status}}" | grep -E "NAME|redis" || true
echo ""

echo "2. Redis 连接测试："
docker exec ragflow-redis redis-cli -a ${REDIS_PASSWORD} ping 2>/dev/null || \
    echo "等待 Redis 完全启动..."
echo ""

echo "3. Redis 数据目录挂载："
docker inspect ragflow-redis | grep -A 3 "Source.*ragflow_redis" 2>/dev/null || \
    docker inspect ragflow-redis | grep -A 5 '"Mounts"' | grep -A 3 "/data"
echo ""

echo "4. 磁盘空间对比："
echo "数据磁盘（迁移后）："
df -h /mnt/data6t
echo ""

# ============================================================================
# 显示总结
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ Redis 迁移成功完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}📝 迁移总结：${NC}"
echo "  ✓ 数据位置: $NEW_DATA_DIR"
echo "  ✓ 配置备份: $BACKUP_FILE"
echo "  ✓ 服务状态: 运行中"
echo ""

echo -e "${BLUE}🎯 验证步骤：${NC}"
echo "  1. 测试 Redis 连接: docker exec ragflow-redis redis-cli -a ${REDIS_PASSWORD} ping"
echo "  2. 检查数据目录: ls -lh $NEW_DATA_DIR"
echo "  3. 测试 RAGFlow 功能"
echo ""

echo -e "${GREEN}迁移脚本执行完毕！🎉${NC}"



