#!/bin/bash
# 调整ES磁盘阈值到更合理的值

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${YELLOW}=== 调整ES磁盘阈值配置 ===${NC}"
echo ""
echo "当前磁盘状态："
df -h /mnt/data6t | grep -E "Filesystem|/mnt/data6t"
echo ""

# 1. 解除只读状态
echo -e "${YELLOW}[1/4] 解除索引只读限制...${NC}"
curl -s -X PUT "http://localhost:1201/_all/_settings" \
  -H "Content-Type: application/json" \
  -u elastic:infini_rag_flow \
  -d '{"index.blocks.read_only_allow_delete": null}' && echo " ✓"

# 2. 调整磁盘水位线到更高的阈值
echo -e "\n${YELLOW}[2/4] 调整磁盘水位线阈值...${NC}"
echo "设置为: low=98%, high=99%, flood=99.5%"
curl -s -X PUT "http://localhost:1201/_cluster/settings" \
  -H "Content-Type: application/json" \
  -u elastic:infini_rag_flow \
  -d '{
    "persistent": {
      "cluster.routing.allocation.disk.watermark.low": "98%",
      "cluster.routing.allocation.disk.watermark.high": "99%",
      "cluster.routing.allocation.disk.watermark.flood_stage": "99.5%",
      "cluster.routing.allocation.disk.threshold_enabled": true
    }
  }' | jq '.acknowledged' && echo " ✓"

# 3. 设置最小可用空间（更实用）
echo -e "\n${YELLOW}[3/4] 设置最小可用空间阈值...${NC}"
echo "设置为: low=10gb, high=5gb, flood=2gb"
curl -s -X PUT "http://localhost:1201/_cluster/settings" \
  -H "Content-Type: application/json" \
  -u elastic:infini_rag_flow \
  -d '{
    "persistent": {
      "cluster.routing.allocation.disk.watermark.low": "10gb",
      "cluster.routing.allocation.disk.watermark.high": "5gb",
      "cluster.routing.allocation.disk.watermark.flood_stage": "2gb"
    }
  }' | jq '.acknowledged' && echo " ✓"

# 4. 验证设置
echo -e "\n${YELLOW}[4/4] 验证当前设置...${NC}"
echo "当前集群设置："
curl -s -X GET "http://localhost:1201/_cluster/settings?flat_settings=true&pretty" -u elastic:infini_rag_flow | grep -E "(watermark|threshold_enabled)" | grep -v "default"

echo -e "\n${GREEN}=== 配置完成 ===${NC}"
echo ""
echo -e "${YELLOW}说明：${NC}"
echo "1. ES现在会在剩余空间少于10GB时开始警告"
echo "2. 剩余空间少于2GB时才会将索引设为只读"
echo "3. 您有56.8GB可用空间，足够使用"
echo ""
echo -e "${YELLOW}建议：${NC}"
echo "定期清理不需要的数据，保持至少20GB可用空间"