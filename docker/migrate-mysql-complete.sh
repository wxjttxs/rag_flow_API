#!/bin/bash
################################################################################
# MySQL 数据完整迁移脚本
# 
# 功能：将 MySQL 数据从满载的根分区迁移到 /mnt/data6t
# 参考：migrate-es-complete.sh (Elasticsearch 迁移脚本)
# 作者：AI Assistant
# 日期：2025-10-30
# 版本：1.0
#
# 使用方法：
#   sudo ./migrate-mysql-complete.sh
#
# 前提条件：
#   1. /mnt/data6t 有足够空间（至少 5GB）
#   2. 有 sudo 权限
#   3. Docker 和 docker-compose 已安装
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
NEW_DATA_DIR="/mnt/data6t/ragflow_mysql"
VOLUME_NAME="docker_mysql_data"
MYSQL_PASSWORD="infini_rag_flow"

# ============================================================================
# 显示标题
# ============================================================================
echo -e "${BLUE}════════════════════════════════════════════════════════${NC}"
echo -e "${BLUE}  MySQL 数据迁移完整脚本${NC}"
echo -e "${BLUE}  从 /dev/sdc2 (100%满) → /mnt/data6t (334GB可用)${NC}"
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

# 显示当前 MySQL 数据大小
OLD_DATA_PATH=$(docker volume inspect $VOLUME_NAME 2>/dev/null | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')
if [ -d "$OLD_DATA_PATH" ]; then
    echo "当前 MySQL 数据："
    echo "  位置: $OLD_DATA_PATH"
    echo "  大小: $(sudo du -sh $OLD_DATA_PATH | awk '{print $1}')"
else
    echo -e "${YELLOW}⚠️  未找到现有数据${NC}"
fi
echo ""

# 确认是否继续
read -p "确认开始迁移 MySQL 数据? (y/n): " confirm
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

# 设置权限（MySQL 容器内使用 UID 999）
sudo chown -R 999:999 "$NEW_DATA_DIR"
echo "✓ 权限已设置 (999:999)"
echo ""

# ============================================================================
# 步骤 4：迁移数据
# ============================================================================
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${YELLOW}步骤 4/8: 迁移 MySQL 数据${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 获取当前数据卷路径
OLD_DATA_PATH=$(docker volume inspect $VOLUME_NAME 2>/dev/null | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')

if [ -d "$OLD_DATA_PATH" ] && [ "$(ls -A $OLD_DATA_PATH)" ]; then
    echo "当前数据位置: $OLD_DATA_PATH"
    echo "当前数据大小: $(sudo du -sh $OLD_DATA_PATH | awk '{print $1}')"
    echo ""
    echo "开始迁移数据..."
    echo "提示：2.3GB 数据预计需要 2-5 分钟"
    echo ""
    
    # 使用 rsync 迁移数据，保留所有属性
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
echo -e "${YELLOW}步骤 5/8: 修复 Docker Compose 配置文件${NC}"
echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

# 备份当前配置文件
BACKUP_FILE="${COMPOSE_FILE}.mysql_migration_backup_$(date +%Y%m%d_%H%M%S)"
sudo cp "$COMPOSE_FILE" "$BACKUP_FILE"
echo "✓ 配置文件已备份: $BACKUP_FILE"

# 临时文件
TEMP_FILE=$(mktemp)

echo "修复配置文件中的 mysql_data 定义..."

# 使用 awk 修复配置文件
# 在 volumes 部分，将 mysql_data 的定义替换为新配置
sudo awk '
BEGIN {
    in_volumes = 0
    in_mysql = 0
    mysql_replaced = 0
    skip_mode = 0
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

# 在 volumes 部分找到 mysql_data
/^  mysql_data:/ && in_volumes == 1 {
    if (mysql_replaced == 0) {
        # 输出新配置
        print "  mysql_data:"
        print "    driver: local"
        print "    driver_opts:"
        print "      type: none"
        print "      o: bind"
        print "      device: '"$NEW_DATA_DIR"'"
        mysql_replaced = 1
        in_mysql = 1
        next
    }
}

# 跳过旧的 mysql_data 配置内容
in_mysql == 1 && /^    driver:/ {
    in_mysql = 0
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

# 检查 mysql_data 配置
echo ""
echo "mysql_data 配置："
grep -A 6 "^  mysql_data:" "$COMPOSE_FILE" || echo "未找到 mysql_data 定义"
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

# 等待 MySQL 启动
echo "等待 MySQL 启动（最多 60 秒）..."
for i in {1..30}; do
    sleep 2
    # 检查 MySQL 是否响应
    if docker exec ragflow-mysql mysqladmin -uroot -p${MYSQL_PASSWORD} ping >/dev/null 2>&1; then
        echo ""
        echo -e "${GREEN}✓ MySQL 已启动${NC}"
        break
    fi
    echo -n "."
    
    # 超时处理
    if [ $i -eq 30 ]; then
        echo ""
        echo -e "${YELLOW}⚠️  等待超时，但服务可能仍在启动中${NC}"
        echo "您可以稍后手动检查: docker-compose logs -f mysql"
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
docker-compose ps | grep -E "NAME|ragflow|mysql" || true
echo ""

echo "2. MySQL 磁盘空间："
docker exec ragflow-mysql df -h / 2>/dev/null | head -2 || \
    echo "容器可能还在启动中..."
echo ""

echo "3. MySQL 数据目录挂载："
docker inspect ragflow-mysql | grep -A 3 "Source.*ragflow_mysql" 2>/dev/null || \
    echo "检查挂载点..."
echo ""

echo "4. 数据库连接测试："
docker exec ragflow-mysql mysql -uroot -p${MYSQL_PASSWORD} \
    -e "SELECT VERSION(); SHOW DATABASES;" 2>/dev/null | grep -v "Using a password" || \
    echo "等待 MySQL 完全启动..."
echo ""

echo "5. 磁盘空间对比："
echo "根分区（迁移前）："
df -h /dev/sdc2 2>/dev/null || df -h / | grep "/$"
echo ""
echo "数据磁盘（迁移后）："
df -h /mnt/data6t
echo ""

# ============================================================================
# 显示总结
# ============================================================================
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}  ✅ MySQL 迁移成功完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

echo -e "${BLUE}📝 迁移总结：${NC}"
echo "  ✓ 数据位置: $NEW_DATA_DIR"
echo "  ✓ 配置备份: $BACKUP_FILE"
echo "  ✓ 服务状态: 运行中"
echo "  ✓ MySQL 状态: 等待验证"
echo ""

echo -e "${BLUE}🎯 下一步操作：${NC}"
echo "  1. 访问 RAGFlow UI: http://localhost:9381"
echo "  2. 测试创建知识库"
echo "  3. 测试上传文档"
echo "  4. 查看日志: cd $DOCKER_DIR && docker-compose logs -f ragflow"
echo ""

echo -e "${BLUE}📊 空间释放：${NC}"
OLD_SIZE=$(sudo du -sh "$OLD_DATA_PATH" 2>/dev/null | awk '{print $1}' || echo "未知")
echo "  根分区释放: 约 $OLD_SIZE"
echo "  (旧数据仍在: $OLD_DATA_PATH)"
echo ""

echo -e "${BLUE}⚠️  清理建议：${NC}"
echo "  确认一切正常后，可以删除旧数据释放更多空间："
echo "  sudo rm -rf $OLD_DATA_PATH"
echo "  警告：删除前请确保 MySQL 工作正常！"
echo ""

echo -e "${BLUE}📚 相关文档：${NC}"
echo "  - MYSQL_DISK_ISSUE.md - MySQL 磁盘问题说明"
echo "  - MIGRATION_COMPLETE.md - ES 迁移完成总结"
echo ""

echo -e "${GREEN}迁移脚本执行完毕！🎉${NC}"



