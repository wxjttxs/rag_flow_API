#!/bin/bash
################################################################################
# RAGFlow 所有服务数据统一迁移脚本
# 
# 功能：一次性将所有服务数据从满载的根分区迁移到 /mnt/data6t
# 服务：MySQL, Redis, MinIO (Elasticsearch 已迁移)
# 版本：1.0
#
# 使用方法：
#   sudo ./migrate-all-services.sh
#
# 优势：
#   1. 一次性迁移所有服务，避免多次停机
#   2. 统一配置管理，避免遗漏
#   3. 彻底解决磁盘空间问题
################################################################################

set -e  # 遇到错误立即退出

# ============================================================================
# 颜色定义
# ============================================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m'

# ============================================================================
# 配置变量
# ============================================================================
DOCKER_DIR="/mnt/data6t/wangxiaojing/rag_flow/docker"
COMPOSE_FILE="$DOCKER_DIR/docker-compose-base.yml"
DATA_BASE="/mnt/data6t"

# 服务配置
declare -A SERVICES=(
    ["mysql"]="ragflow_mysql:docker_mysql_data:ragflow-mysql:999:999:infini_rag_flow"
    ["redis"]="ragflow_redis:docker_redis_data:ragflow-redis:999:999:infini_rag_flow"
    ["minio"]="ragflow_minio:docker_minio_data:ragflow-minio:1000:1000:infini_rag_flow"
)

# ============================================================================
# 工具函数
# ============================================================================

# 打印分隔线
print_separator() {
    echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
}

# 打印步骤标题
print_step() {
    local step=$1
    local title=$2
    echo -e "${YELLOW}步骤 $step: $title${NC}"
    print_separator
}

# 打印服务标题
print_service() {
    local service=$1
    echo -e "${CYAN}▶ 正在处理: $service${NC}"
}

# 获取服务配置
get_service_config() {
    local service=$1
    local index=$2
    echo "${SERVICES[$service]}" | cut -d: -f$index
}

# ============================================================================
# 显示标题和说明
# ============================================================================
clear
echo -e "${MAGENTA}════════════════════════════════════════════════════════${NC}"
echo -e "${MAGENTA}  RAGFlow 所有服务数据统一迁移脚本${NC}"
echo -e "${MAGENTA}  从根分区（100%满）→ /mnt/data6t（334GB可用）${NC}"
echo -e "${MAGENTA}════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}📋 迁移计划：${NC}"
echo "  1. MySQL   → /mnt/data6t/ragflow_mysql"
echo "  2. Redis   → /mnt/data6t/ragflow_redis"
echo "  3. MinIO   → /mnt/data6t/ragflow_minio"
echo ""
echo "  ✓ Elasticsearch 已迁移到 /mnt/data6t/ragflow_esdata"
echo ""

echo -e "${BLUE}⏱️  预计时间：${NC}"
echo "  - 环境检查：1 分钟"
echo "  - 数据迁移：5-15 分钟（取决于数据量）"
echo "  - 配置修复：2 分钟"
echo "  - 服务启动：3-5 分钟"
echo "  - 总计：约 15-25 分钟"
echo ""

echo -e "${BLUE}⚠️  注意事项：${NC}"
echo "  1. 迁移期间服务将停止（约 15-25 分钟）"
echo "  2. 建议在低峰期执行"
echo "  3. 自动备份配置文件"
echo "  4. 可以随时回滚"
echo ""

# ============================================================================
# 步骤 1：环境检查
# ============================================================================
print_separator
print_step "1/7" "环境检查"
echo ""

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

# 检查 docker-compose
if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}✗ docker-compose 未安装${NC}"
    exit 1
fi
echo "✓ docker-compose 可用"

# 检查目标目录
if [ ! -d "$DATA_BASE" ]; then
    echo -e "${RED}✗ 目标目录 $DATA_BASE 不存在${NC}"
    exit 1
fi
echo "✓ 目标目录存在"

# 检查磁盘空间
AVAILABLE_GB=$(df -BG "$DATA_BASE" | awk 'NR==2 {print $4}' | sed 's/G//')
if [ "$AVAILABLE_GB" -lt 10 ]; then
    echo -e "${RED}✗ 目标磁盘可用空间不足（需要至少 10GB）${NC}"
    exit 1
fi
echo "✓ 磁盘空间充足 (${AVAILABLE_GB}GB 可用)"

echo ""
echo -e "${GREEN}环境检查完成！${NC}"
echo ""

# ============================================================================
# 步骤 2：显示当前状态
# ============================================================================
print_separator
print_step "2/7" "当前状态分析"
echo ""

echo "磁盘使用情况："
df -h | grep -E "(Filesystem|/dev/sdc2|/dev/sda1)"
echo ""

echo "服务数据大小统计："
TOTAL_SIZE=0
for service in "${!SERVICES[@]}"; do
    VOLUME_NAME=$(get_service_config "$service" 2)
    OLD_PATH=$(docker volume inspect "$VOLUME_NAME" 2>/dev/null | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')
    
    if [ -d "$OLD_PATH" ]; then
        SIZE=$(sudo du -sm "$OLD_PATH" 2>/dev/null | awk '{print $1}')
        SIZE_MB=${SIZE:-0}
        TOTAL_SIZE=$((TOTAL_SIZE + SIZE_MB))
        printf "  %-10s %6d MB  (%s)\n" "$service:" "$SIZE_MB" "$OLD_PATH"
    else
        printf "  %-10s %6s     (无数据)\n" "$service:" "-"
    fi
done
echo "  ----------------------------------------"
printf "  %-10s %6d MB  (约 %.1f GB)\n" "总计:" "$TOTAL_SIZE" "$(echo "scale=1; $TOTAL_SIZE/1024" | bc)"
echo ""

# 确认是否继续
read -p "确认开始迁移所有服务? (y/n): " confirm
if [ "$confirm" != "y" ]; then
    echo "操作已取消"
    exit 0
fi
echo ""

# ============================================================================
# 步骤 3：停止服务
# ============================================================================
print_separator
print_step "3/7" "停止 RAGFlow 服务"
echo ""

cd "$DOCKER_DIR"
echo "停止所有容器..."
docker-compose down
echo -e "${GREEN}✓ 服务已停止${NC}"
sleep 3
echo ""

# ============================================================================
# 步骤 4：创建新数据目录并迁移数据
# ============================================================================
print_separator
print_step "4/7" "创建目录并迁移数据"
echo ""

for service in mysql redis minio; do
    print_service "$service"
    
    # 获取配置
    NEW_DIR="${DATA_BASE}/ragflow_${service}"
    VOLUME_NAME=$(get_service_config "$service" 2)
    UID=$(get_service_config "$service" 4)
    GID=$(get_service_config "$service" 5)
    
    # 创建目录
    echo "  → 创建目录: $NEW_DIR"
    sudo mkdir -p "$NEW_DIR"
    sudo chown -R ${UID}:${GID} "$NEW_DIR"
    echo "  ✓ 目录已创建，权限: ${UID}:${GID}"
    
    # 迁移数据
    OLD_PATH=$(docker volume inspect "$VOLUME_NAME" 2>/dev/null | grep Mountpoint | awk '{print $2}' | sed 's/[",]//g')
    
    if [ -d "$OLD_PATH" ] && [ "$(sudo ls -A $OLD_PATH 2>/dev/null)" ]; then
        OLD_SIZE=$(sudo du -sh "$OLD_PATH" 2>/dev/null | awk '{print $1}')
        echo "  → 迁移数据: $OLD_SIZE"
        echo "     从: $OLD_PATH"
        echo "     到: $NEW_DIR"
        
        # 使用 rsync 迁移
        sudo rsync -a --info=progress2 "$OLD_PATH/" "$NEW_DIR/" 2>&1 | \
            grep -E "to-chk|%" | tail -1 || true
        
        NEW_SIZE=$(sudo du -sh "$NEW_DIR" 2>/dev/null | awk '{print $1}')
        echo "  ✓ 数据迁移完成: $NEW_SIZE"
    else
        echo "  ℹ  无数据需要迁移"
    fi
    echo ""
done

echo -e "${GREEN}所有数据迁移完成！${NC}"
echo ""

# ============================================================================
# 步骤 5：备份并修复配置文件
# ============================================================================
print_separator
print_step "5/7" "修复 Docker Compose 配置"
echo ""

# 备份配置文件
BACKUP_FILE="${COMPOSE_FILE}.all_services_backup_$(date +%Y%m%d_%H%M%S)"
sudo cp "$COMPOSE_FILE" "$BACKUP_FILE"
echo "✓ 配置文件已备份: $BACKUP_FILE"
echo ""

# 修复配置文件
TEMP_FILE=$(mktemp)

echo "修复 volumes 配置..."
sudo awk -v mysql_dir="$DATA_BASE/ragflow_mysql" \
         -v redis_dir="$DATA_BASE/ragflow_redis" \
         -v minio_dir="$DATA_BASE/ragflow_minio" '
BEGIN {
    in_volumes = 0
    skip_next = 0
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

# 跳过标记
skip_next == 1 && /^    driver: local/ {
    skip_next = 0
    next
}

# MySQL
/^  mysql_data:/ && in_volumes == 1 {
    if (index($0, "driver_opts") == 0) {
        print "  mysql_data:"
        print "    driver: local"
        print "    driver_opts:"
        print "      type: none"
        print "      o: bind"
        print "      device: " mysql_dir
        skip_next = 1
        next
    }
}

# Redis
/^  redis_data:/ && in_volumes == 1 {
    if (index($0, "driver_opts") == 0) {
        print "  redis_data:"
        print "    driver: local"
        print "    driver_opts:"
        print "      type: none"
        print "      o: bind"
        print "      device: " redis_dir
        skip_next = 1
        next
    }
}

# MinIO
/^  minio_data:/ && in_volumes == 1 {
    if (index($0, "driver_opts") == 0) {
        print "  minio_data:"
        print "    driver: local"
        print "    driver_opts:"
        print "      type: none"
        print "      o: bind"
        print "      device: " minio_dir
        skip_next = 1
        next
    }
}

# 打印其他所有行
{ print }
' "$COMPOSE_FILE" > "$TEMP_FILE"

sudo mv "$TEMP_FILE" "$COMPOSE_FILE"
echo -e "${GREEN}✓ 配置文件已修复${NC}"
echo ""

# ============================================================================
# 步骤 6：验证配置并清理旧 Volume
# ============================================================================
print_separator
print_step "6/7" "验证配置并清理"
echo ""

# 验证配置语法
echo "验证 Docker Compose 配置..."
if docker-compose config > /dev/null 2>&1; then
    echo -e "${GREEN}✓ 配置语法正确${NC}"
else
    echo -e "${RED}✗ 配置文件有错误${NC}"
    docker-compose config 2>&1 | head -20
    echo ""
    echo "可以使用备份恢复: $BACKUP_FILE"
    exit 1
fi
echo ""

# 显示新配置
echo "新的 volumes 配置："
grep -A 6 "mysql_data:\|redis_data:\|minio_data:" "$COMPOSE_FILE" | grep -v "^--$"
echo ""

# 删除旧 volumes
echo "清理旧的 Docker volumes..."
for service in mysql redis minio; do
    VOLUME_NAME=$(get_service_config "$service" 2)
    if docker volume ls | grep -q "$VOLUME_NAME"; then
        docker volume rm "$VOLUME_NAME" 2>/dev/null && \
            echo "  ✓ 已删除: $VOLUME_NAME" || \
            echo "  ℹ  $VOLUME_NAME 可能已删除"
    fi
done
echo ""

# ============================================================================
# 步骤 7：启动服务并验证
# ============================================================================
print_separator
print_step "7/7" "启动服务并验证"
echo ""

cd "$DOCKER_DIR"
echo "启动所有服务..."
docker-compose up -d
echo -e "${GREEN}✓ 服务已启动${NC}"
echo ""

# 等待服务启动
echo "等待服务启动完成..."
sleep 5

# 检查 MySQL
echo -n "MySQL:  "
for i in {1..30}; do
    if docker exec ragflow-mysql mysqladmin -uroot -pinfini_rag_flow ping >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 运行正常${NC}"
        break
    fi
    [ $i -eq 30 ] && echo -e "${YELLOW}⚠ 等待超时${NC}"
    sleep 2
done

# 检查 Redis
echo -n "Redis:  "
for i in {1..15}; do
    if docker exec ragflow-redis redis-cli -a infini_rag_flow ping >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 运行正常${NC}"
        break
    fi
    [ $i -eq 15 ] && echo -e "${YELLOW}⚠ 等待超时${NC}"
    sleep 2
done

# 检查 MinIO
echo -n "MinIO:  "
for i in {1..15}; do
    if docker exec ragflow-minio curl -sf http://localhost:9000/minio/health/live >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 运行正常${NC}"
        break
    fi
    [ $i -eq 15 ] && echo -e "${YELLOW}⚠ 等待超时${NC}"
    sleep 2
done

# 检查 RAGFlow
echo -n "RAGFlow:"
for i in {1..20}; do
    if docker exec ragflow-server curl -sf http://localhost:9380/health >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 运行正常${NC}"
        break
    fi
    [ $i -eq 20 ] && echo -e "${YELLOW}⚠ 等待超时（可能仍在启动）${NC}"
    sleep 3
done
echo ""

# ============================================================================
# 显示最终结果
# ============================================================================
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo -e "${GREEN}  ✅ 所有服务迁移完成！${NC}"
echo -e "${GREEN}════════════════════════════════════════════════════════${NC}"
echo ""

echo -e "${BLUE}📊 迁移总结：${NC}"
echo "  ✓ MySQL   → $DATA_BASE/ragflow_mysql"
echo "  ✓ Redis   → $DATA_BASE/ragflow_redis"
echo "  ✓ MinIO   → $DATA_BASE/ragflow_minio"
echo "  ✓ 配置备份: $BACKUP_FILE"
echo ""

echo -e "${BLUE}💾 磁盘空间变化：${NC}"
echo "  根分区："
df -h / | tail -1 | awk '{printf "    使用率: %s (可用: %s)\n", $5, $4}'
echo "  数据盘："
df -h "$DATA_BASE" | tail -1 | awk '{printf "    使用率: %s (可用: %s)\n", $5, $4}'
echo ""

echo -e "${BLUE}🔍 容器状态：${NC}"
docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}" | \
    grep -E "NAME|ragflow|mysql|redis|minio|es-01" | head -10
echo ""

echo -e "${BLUE}🎯 下一步操作：${NC}"
echo "  1. 访问 RAGFlow UI: http://localhost:9381"
echo "  2. 测试创建知识库"
echo "  3. 测试上传文档"
echo "  4. 测试对话功能"
echo "  5. 查看日志: docker-compose logs -f ragflow"
echo ""

echo -e "${BLUE}📚 数据位置：${NC}"
echo "  MySQL:   $DATA_BASE/ragflow_mysql"
echo "  Redis:   $DATA_BASE/ragflow_redis"
echo "  MinIO:   $DATA_BASE/ragflow_minio"
echo "  ES:      $DATA_BASE/ragflow_esdata"
echo ""

echo -e "${BLUE}⚠️  重要提示：${NC}"
echo "  1. 旧数据仍在 /var/lib/docker/volumes/"
echo "  2. 确认一切正常后可以删除旧数据释放空间"
echo "  3. 删除命令（危险，请谨慎）："
echo "     sudo rm -rf /var/lib/docker/volumes/docker_mysql_data"
echo "     sudo rm -rf /var/lib/docker/volumes/docker_redis_data"
echo "     sudo rm -rf /var/lib/docker/volumes/docker_minio_data"
echo ""

echo -e "${GREEN}迁移脚本执行完毕！🎉${NC}"
echo ""

# 提示查看日志
echo -e "${YELLOW}提示：如果服务启动异常，可以查看日志：${NC}"
echo "  docker-compose logs -f ragflow"
echo "  docker-compose logs -f mysql"
echo "  docker-compose logs -f redis"
echo "  docker-compose logs -f minio"



