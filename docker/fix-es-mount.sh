#!/bin/bash
# 修复ES数据挂载配置

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== 修复ES数据挂载配置 ===${NC}"
echo ""

# 切换到docker目录
cd /mnt/data6t/wangxiaojing/rag_flow/docker

# 1. 停止ES服务（如果正在运行）
echo -e "${YELLOW}[1/4] 停止ES服务...${NC}"
docker-compose -f docker-compose-base.yml stop es01 2>/dev/null || true

# 2. 备份当前配置
echo -e "\n${YELLOW}[2/4] 备份配置文件...${NC}"
BACKUP_TIME=$(date +%Y%m%d_%H%M%S)
cp docker-compose-base.yml docker-compose-base.yml.fix_mount_backup_${BACKUP_TIME}
echo "配置已备份为: docker-compose-base.yml.fix_mount_backup_${BACKUP_TIME}"

# 3. 准备数据目录
echo -e "\n${YELLOW}[3/4] 准备数据目录...${NC}"

# 如果Docker volume中有数据，复制到目标位置
if [ -d "/var/lib/docker/volumes/docker_esdata01/_data" ] && [ "$(ls -A /var/lib/docker/volumes/docker_esdata01/_data 2>/dev/null)" ]; then
    echo "发现Docker volume中的ES数据，正在复制..."
    sudo mkdir -p /mnt/data6t/ragflow_esdata_new
    sudo cp -rp /var/lib/docker/volumes/docker_esdata01/_data/* /mnt/data6t/ragflow_esdata_new/
    sudo chown -R 1000:1000 /mnt/data6t/ragflow_esdata_new
    ES_DATA_PATH="/mnt/data6t/ragflow_esdata_new"
else
    # 检查是否已有ES数据在其他位置
    if [ -d "/mnt/data6t/ragflow_esdata" ] && [ "$(ls -A /mnt/data6t/ragflow_esdata 2>/dev/null)" ]; then
        echo "使用已存在的ES数据目录: /mnt/data6t/ragflow_esdata"
        ES_DATA_PATH="/mnt/data6t/ragflow_esdata"
    else
        echo "创建新的ES数据目录..."
        sudo mkdir -p /mnt/data6t/ragflow_esdata
        sudo chown -R 1000:1000 /mnt/data6t/ragflow_esdata
        ES_DATA_PATH="/mnt/data6t/ragflow_esdata"
    fi
fi

# 4. 修改配置文件
echo -e "\n${YELLOW}[4/4] 修改配置文件...${NC}"
# 使用sed修改volumes配置
sed -i "s|- esdata01:/usr/share/elasticsearch/data|- ${ES_DATA_PATH}:/usr/share/elasticsearch/data|g" docker-compose-base.yml

echo -e "${GREEN}配置修改完成！${NC}"
echo ""
echo -e "ES数据目录设置为: ${ES_DATA_PATH}"
echo ""
echo -e "${YELLOW}现在可以启动ES服务：${NC}"
echo "docker-compose -f docker-compose-base.yml up -d es01"
echo ""
echo -e "${YELLOW}启动后检查状态：${NC}"
echo "curl -X GET 'http://localhost:1201/_cluster/health?pretty' -u elastic:infini_rag_flow"