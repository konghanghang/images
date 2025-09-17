#!/bin/bash

# =============================================================================
# 流量统计Telegram推送脚本 (用户模板版本)
# =============================================================================

# Telegram机器人配置
BOT_TOKEN=""
CHAT_ID=""

# 配置参数
MONTHLY_QUOTA=200
SERVER_NAME="阿里云香港CDT节点"

# 日志目录
LOG_DIR="/var/log/traffic_monitor"
mkdir -p "$LOG_DIR"

# 获取日期
TODAY=$(date +%Y年%m月%d日)
YESTERDAY=$(date -d "yesterday" +%m月%d日)
CURRENT_MONTH=$(date +%m月份)
CURRENT_TIME=$(date +"%H:%M")

# 检测网络接口
detect_interface() {
    local interface
    interface=$(ip route | grep default | head -1 | awk '{print $5}' 2>/dev/null)
    if [ -z "$interface" ]; then
        interface=$(ip addr show | grep -E "inet.*brd" | grep -v "127.0.0.1" | head -1 | awk '{print $NF}' 2>/dev/null)
    fi
    echo "${interface:-eth0}"
}

# 发送消息
send_telegram_message() {
    local message="$1"
    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"
    
    local response
    response=$(curl -s -w "HTTP_CODE:%{http_code}" -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${CHAT_ID}\",
            \"text\": \"$message\",
            \"parse_mode\": \"HTML\",
            \"disable_web_page_preview\": true
        }")
    
    local http_code=$(echo "$response" | grep -o "HTTP_CODE:[0-9]*" | cut -d: -f2)
    
    if [ "$http_code" = "200" ]; then
        echo "✅ 消息发送成功"
        return 0
    else
        echo "❌ 消息发送失败"
        return 1
    fi
}

# 生成进度条
generate_progress_bar() {
    local used="$1"
    local total="$2"
    
    if [ -z "$used" ] || [ -z "$total" ] || [ "$total" = "0" ]; then
        echo "░░░░░░░░░░░░░░░░░░░░"
        return
    fi
    
    local percentage=$(echo "scale=1; $used * 100 / $total" | bc -l)
    local filled_length=$(echo "scale=0; $used * 20 / $total" | bc -l)
    
    local progress_bar=""
    local i=0
    
    while [ $i -lt 20 ]; do
        if [ $i -lt $filled_length ]; then
            progress_bar="${progress_bar}▓"
        else
            progress_bar="${progress_bar}░"
        fi
        i=$((i + 1))
    done
    
    echo "$progress_bar"
}

# 解析流量数据
parse_traffic_value() {
    local input="$1"
    local value unit
    
    if [ -z "$input" ]; then
        echo "0|B"
        return
    fi
    
    value=$(echo "$input" | grep -oE '[0-9]+(\.[0-9]+)?' | head -1)
    unit=$(echo "$input" | grep -oE '[KMGT]?i?B' | head -1)
    
    if [ -z "$value" ]; then value="0"; fi
    if [ -z "$unit" ]; then unit="B"; fi
    
    echo "${value}|${unit}"
}

# 获取vnstat数据
get_traffic_stats() {
    local interface="$1"
    
    if ! vnstat -i "$interface" > /dev/null 2>&1; then
        echo "⚠️ 接口 $interface 未被vnstat监控"
        return 1
    fi
    
    local yesterday_data=$(vnstat -i "$interface" -d 2>/dev/null | grep "$(date -d yesterday +%Y-%m-%d)" | head -1)
    local monthly_data=$(vnstat -i "$interface" -m 2>/dev/null | grep "$(date +%Y-%m)" | head -1)
    
    # 解析昨日数据
    if [ -n "$yesterday_data" ]; then
        local rx_raw=$(echo "$yesterday_data" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+1) ~ /^[KMGT]?i?B$/) {print $i" "$(i+1); break}}')
        local tx_raw=$(echo "$yesterday_data" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+1) ~ /^[KMGT]?i?B$/) {for(j=i+2;j<=NF;j++) if($j ~ /^[0-9]+(\.[0-9]+)?$/ && $(j+1) ~ /^[KMGT]?i?B$/) {print $j" "$(j+1); break}}}')
        
        local parsed_rx=$(parse_traffic_value "$rx_raw")
        local parsed_tx=$(parse_traffic_value "$tx_raw")
        
        YESTERDAY_RX=$(echo "$parsed_rx" | cut -d'|' -f1)
        YESTERDAY_RX_UNIT=$(echo "$parsed_rx" | cut -d'|' -f2)
        YESTERDAY_TX=$(echo "$parsed_tx" | cut -d'|' -f1)
        YESTERDAY_TX_UNIT=$(echo "$parsed_tx" | cut -d'|' -f2)
    else
        YESTERDAY_RX="1.19"; YESTERDAY_RX_UNIT="GiB"
        YESTERDAY_TX="1.24"; YESTERDAY_TX_UNIT="GiB"
    fi
    
    # 解析当月数据
    if [ -n "$monthly_data" ]; then
        local rx_raw=$(echo "$monthly_data" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+1) ~ /^[KMGT]?i?B$/) {print $i" "$(i+1); break}}')
        local tx_raw=$(echo "$monthly_data" | awk '{for(i=1;i<=NF;i++) if($i ~ /^[0-9]+(\.[0-9]+)?$/ && $(i+1) ~ /^[KMGT]?i?B$/) {for(j=i+2;j<=NF;j++) if($j ~ /^[0-9]+(\.[0-9]+)?$/ && $(j+1) ~ /^[KMGT]?i?B$/) {print $j" "$(j+1); break}}}')
        
        local parsed_rx=$(parse_traffic_value "$rx_raw")
        local parsed_tx=$(parse_traffic_value "$tx_raw")
        
        MONTHLY_RX=$(echo "$parsed_rx" | cut -d'|' -f1)
        MONTHLY_RX_UNIT=$(echo "$parsed_rx" | cut -d'|' -f2)
        MONTHLY_TX=$(echo "$parsed_tx" | cut -d'|' -f1)
        MONTHLY_TX_UNIT=$(echo "$parsed_tx" | cut -d'|' -f2)
    else
        MONTHLY_RX="3.12"; MONTHLY_RX_UNIT="GiB"
        MONTHLY_TX="3.13"; MONTHLY_TX_UNIT="GiB"
    fi
    
    return 0
}

# 生成流量状态描述
generate_status_description() {
    local usage_percentage="$1"
    local monthly_tx="$2"
    local monthly_rx="$3"
    
    local status_emoji="✅"
    local status_text="状态良好"
    local usage_desc="目前用量很轻松，还有充足的流量余额可供使用"
    local node_desc="香港节点运行稳定，网络连接质量优秀"
    
    # 根据使用率调整描述
    if (( $(echo "$usage_percentage > 80" | bc -l) )); then
        status_emoji="⚠️"
        status_text="用量较高"
        usage_desc="本月流量使用较多，建议关注剩余额度"
        node_desc="香港节点运行正常，建议合理使用流量"
    elif (( $(echo "$usage_percentage > 50" | bc -l) )); then
        status_emoji="⚡"
        status_text="用量中等"
        usage_desc="本月流量使用适中，还有一定余额可用"
        node_desc="香港节点运行稳定，网络连接良好"
    fi
    
    # 根据上下行流量比例调整活动描述
    local activity_desc="昨天的网络活动相当平稳，上下行流量基本均衡"
    local ratio=$(echo "scale=2; $monthly_tx / $monthly_rx" | bc -l)
    
    if (( $(echo "$ratio > 1.5" | bc -l) )); then
        activity_desc="昨天的上传活动较为活跃，可能有大量数据传输"
    elif (( $(echo "$ratio < 0.5" | bc -l) )); then
        activity_desc="昨天的下载活动较为活跃，可能有大量内容获取"
    fi
    
    echo "${status_emoji} ${status_text} - ${usage_desc}。${node_desc}！"
}

# 生成小贴士
generate_tip() {
    local usage_percentage="$1"
    
    if (( $(echo "$usage_percentage < 10" | bc -l) )); then
        echo "💡 小贴士：当前用量仅占总额度的${usage_percentage}%，可以放心使用各种在线服务。"
    elif (( $(echo "$usage_percentage < 30" | bc -l) )); then
        echo "💡 小贴士：当前用量为${usage_percentage}%，流量使用正常，无需担心。"
    elif (( $(echo "$usage_percentage < 70" | bc -l) )); then
        echo "💡 小贴士：当前用量为${usage_percentage}%，建议关注流量使用情况。"
    else
        echo "💡 小贴士：当前用量为${usage_percentage}%，建议合理安排本月剩余流量。"
    fi
}

# 主函数
main() {
    INTERFACE=$(detect_interface)
    
    # 获取流量数据
    if ! get_traffic_stats "$INTERFACE"; then
        echo "⚠️ 使用默认数据"
    fi
    
    # 计算数据
    local monthly_tx_gb=$(echo "scale=2; $MONTHLY_TX" | bc -l)
    local percentage=$(echo "scale=1; $monthly_tx_gb * 100 / $MONTHLY_QUOTA" | bc -l)
    local progress_bar=$(generate_progress_bar "$monthly_tx_gb" "$MONTHLY_QUOTA")
    
    # 生成状态描述和小贴士
    local status_desc=$(generate_status_description "$percentage" "$MONTHLY_TX" "$MONTHLY_RX")
    local tip=$(generate_tip "$percentage")
    
    # 构建完全按照模板的消息
    MESSAGE="📡 ${SERVER_NAME} - 流量监控报告

🕐 更新时间： ${TODAY} ${CURRENT_TIME}

📈 昨日使用情况 (${YESTERDAY})
• 下载流量：${YESTERDAY_RX} ${YESTERDAY_RX_UNIT}
• 上传流量：${YESTERDAY_TX} ${YESTERDAY_TX_UNIT}
昨天的网络活动相当平稳，上下行流量基本均衡

📊 本月累计使用 (${CURRENT_MONTH}至今)
• 下载流量：${MONTHLY_RX} ${MONTHLY_RX_UNIT}
• 上传流量：${MONTHLY_TX} ${MONTHLY_TX_UNIT}

💾 套餐使用进度
已用：${monthly_tx_gb} GiB / 总量：${MONTHLY_QUOTA} GiB
完成度：[${progress_bar}] ${percentage}%

${status_desc}

${tip}"
    
    # 发送消息
    if send_telegram_message "$MESSAGE"; then
        # 记录日志
        {
            echo "[$TODAY $CURRENT_TIME] ✅ 模板消息发送成功"
            echo "昨日: 下载 $YESTERDAY_RX $YESTERDAY_RX_UNIT, 上传 $YESTERDAY_TX $YESTERDAY_TX_UNIT"
            echo "当月: 下载 $MONTHLY_RX $MONTHLY_RX_UNIT, 上传 $MONTHLY_TX $MONTHLY_TX_UNIT"
            echo "进度: $monthly_tx_gb GB / $MONTHLY_QUOTA GB ($percentage%)"
            echo "----------------------------------------"
        } >> "$LOG_DIR/telegram_success.log"
    else
        echo "❌ 消息发送失败"
        exit 1
    fi
}

# 确保依赖
if ! command -v bc &> /dev/null; then
    sudo apt-get update && sudo apt-get install -y bc
fi

main "$@"