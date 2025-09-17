#!/bin/bash

# =============================================================================
# 实时流量异常检测脚本
# =============================================================================

set -e

# 配置参数
INTERFACE=""                    # 网络接口，空则自动检测
CHECK_INTERVAL=300             # 检测间隔（秒），默认5分钟
ALERT_THRESHOLD_MB=100         # 流量告警阈值（MB/间隔）
BURST_THRESHOLD_MB=500         # 突发流量阈值（MB/间隔）
BASELINE_MULTIPLIER=3          # 基线倍数，超过平均值的N倍触发告警
LOG_FILE="/var/log/traffic_monitor/realtime.log"
DATA_FILE="/tmp/traffic_monitor_data"

# Telegram配置
BOT_TOKEN=""
CHAT_ID=""
ENABLE_TELEGRAM=false

# 告警开关
ENABLE_THRESHOLD_ALERT=true    # 绝对阈值告警
ENABLE_BASELINE_ALERT=true     # 基线对比告警
ENABLE_BURST_ALERT=true        # 突发流量告警

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# 日志函数
log_info() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] $1"
    echo -e "${BLUE}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_warning() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [WARNING] $1"
    echo -e "${YELLOW}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_error() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ERROR] $1"
    echo -e "${RED}$msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

log_alert() {
    local msg="[$(date '+%Y-%m-%d %H:%M:%S')] [ALERT] $1"
    echo -e "${RED}🚨 $msg${NC}"
    echo "$msg" >> "$LOG_FILE"
}

# 检测网络接口
detect_interface() {
    if [ -n "$INTERFACE" ]; then
        echo "$INTERFACE"
        return
    fi

    local interface
    interface=$(ip route | grep default | head -1 | awk '{print $5}' 2>/dev/null)
    if [ -z "$interface" ]; then
        interface=$(ip addr show | grep -E "inet.*brd" | grep -v "127.0.0.1" | head -1 | awk '{print $NF}' 2>/dev/null)
    fi
    echo "${interface:-eth0}"
}

# 获取网络接口统计数据
get_interface_stats() {
    local interface="$1"
    local stats_line

    stats_line=$(grep "$interface:" /proc/net/dev | head -1)
    if [ -z "$stats_line" ]; then
        echo "0 0"
        return 1
    fi

    # 提取接收和发送字节数（第2和第10列）
    local rx_bytes=$(echo "$stats_line" | awk '{print $2}')
    local tx_bytes=$(echo "$stats_line" | awk '{print $10}')

    echo "$rx_bytes $tx_bytes"
}

# 字节转换为MB
bytes_to_mb() {
    echo "scale=2; $1 / 1048576" | bc -l
}

# 计算流量速率
calculate_rate() {
    local current_rx="$1"
    local current_tx="$2"
    local previous_rx="$3"
    local previous_tx="$4"
    local time_diff="$5"

    if [ "$time_diff" -eq 0 ]; then
        echo "0 0 0"
        return
    fi

    local rx_diff=$((current_rx - previous_rx))
    local tx_diff=$((current_tx - previous_tx))
    local total_diff=$((rx_diff + tx_diff))

    local rx_rate=$(echo "scale=2; $rx_diff / $time_diff" | bc -l)
    local tx_rate=$(echo "scale=2; $tx_diff / $time_diff" | bc -l)
    local total_rate=$(echo "scale=2; $total_diff / $time_diff" | bc -l)

    echo "$rx_rate $tx_rate $total_rate"
}

# 获取vnstat基线数据
get_vnstat_baseline() {
    local interface="$1"

    if ! command -v vnstat &> /dev/null; then
        echo "0"
        return
    fi

    # 获取最近7天的平均日流量（MB）
    local avg_daily_mb
    avg_daily_mb=$(vnstat -i "$interface" -d 7 --json 2>/dev/null | jq -r '.interfaces[0].traffic.day[] | .rx + .tx' 2>/dev/null | awk '{sum+=$1; count++} END {if(count>0) print sum/count/1024/1024; else print 0}' 2>/dev/null)

    if [ -z "$avg_daily_mb" ] || [ "$avg_daily_mb" = "0" ]; then
        echo "0"
    else
        # 转换为每分钟平均流量
        echo "scale=2; $avg_daily_mb / 1440" | bc -l
    fi
}

# 发送Telegram告警
send_telegram_alert() {
    local message="$1"

    if [ "$ENABLE_TELEGRAM" != "true" ] || [ -z "$BOT_TOKEN" ] || [ -z "$CHAT_ID" ]; then
        return 0
    fi

    local url="https://api.telegram.org/bot${BOT_TOKEN}/sendMessage"

    curl -s -X POST "$url" \
        -H "Content-Type: application/json" \
        -d "{
            \"chat_id\": \"${CHAT_ID}\",
            \"text\": \"$message\",
            \"parse_mode\": \"HTML\",
            \"disable_web_page_preview\": true
        }" > /dev/null 2>&1
}

# 检测异常流量
check_traffic_anomaly() {
    local rx_rate="$1"
    local tx_rate="$2"
    local total_rate="$3"
    local interface="$4"
    local time_interval="$5"

    local rx_mb=$(bytes_to_mb "$rx_rate")
    local tx_mb=$(bytes_to_mb "$tx_rate")
    local total_mb=$(bytes_to_mb "$total_rate")

    # 计算这个时间间隔内的总流量
    local interval_total_mb=$(echo "scale=2; $total_mb * $time_interval" | bc -l)
    local interval_rx_mb=$(echo "scale=2; $rx_mb * $time_interval" | bc -l)
    local interval_tx_mb=$(echo "scale=2; $tx_mb * $time_interval" | bc -l)

    local alert_triggered=false
    local alert_messages=()

    # 1. 绝对阈值检测
    if [ "$ENABLE_THRESHOLD_ALERT" = "true" ]; then
        if (( $(echo "$interval_total_mb > $ALERT_THRESHOLD_MB" | bc -l) )); then
            alert_triggered=true
            alert_messages+=("流量超过阈值: ${interval_total_mb}MB (阈值: ${ALERT_THRESHOLD_MB}MB)")
        fi
    fi

    # 2. 突发流量检测
    if [ "$ENABLE_BURST_ALERT" = "true" ]; then
        if (( $(echo "$interval_total_mb > $BURST_THRESHOLD_MB" | bc -l) )); then
            alert_triggered=true
            alert_messages+=("检测到突发流量: ${interval_total_mb}MB (突发阈值: ${BURST_THRESHOLD_MB}MB)")
        fi
    fi

    # 3. 基线对比检测
    if [ "$ENABLE_BASELINE_ALERT" = "true" ]; then
        local baseline_per_minute=$(get_vnstat_baseline "$interface")
        if [ "$baseline_per_minute" != "0" ]; then
            local baseline_per_interval=$(echo "scale=2; $baseline_per_minute * $time_interval / 60" | bc -l)
            local threshold=$(echo "scale=2; $baseline_per_interval * $BASELINE_MULTIPLIER" | bc -l)

            if (( $(echo "$interval_total_mb > $threshold" | bc -l) )); then
                alert_triggered=true
                alert_messages+=("流量超过基线${BASELINE_MULTIPLIER}倍: ${interval_total_mb}MB (基线: ${baseline_per_interval}MB)")
            fi
        fi
    fi

    # 发送告警
    if [ "$alert_triggered" = "true" ]; then
        local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        local alert_msg="🚨 流量异常告警

📡 服务器: $(hostname)
🌐 接口: $interface
⏰ 时间: $timestamp
⏱️ 监控间隔: ${time_interval}秒

📊 流量详情:
• 下载: ${interval_rx_mb} MB
• 上传: ${interval_tx_mb} MB
• 总计: ${interval_total_mb} MB

⚠️ 告警原因:"

        for msg in "${alert_messages[@]}"; do
            alert_msg="$alert_msg
• $msg"
        done

        log_alert "流量异常: 接口=$interface, 总流量=${interval_total_mb}MB"
        send_telegram_alert "$alert_msg"

        # 保存异常记录
        echo "$(date '+%Y-%m-%d %H:%M:%S'),$interface,$interval_total_mb,$interval_rx_mb,$interval_tx_mb,${alert_messages[0]}" >> "/var/log/traffic_monitor/alerts.log"
    fi

    # 记录正常监控数据
    log_info "接口: $interface | 总流量: ${interval_total_mb}MB | 下载: ${interval_rx_mb}MB | 上传: ${interval_tx_mb}MB"
}

# 监控循环
start_monitoring() {
    local interface=$(detect_interface)
    log_info "开始监控网络接口: $interface"
    log_info "检测间隔: ${CHECK_INTERVAL}秒"
    log_info "流量告警阈值: ${ALERT_THRESHOLD_MB}MB"
    log_info "突发流量阈值: ${BURST_THRESHOLD_MB}MB"

    # 确保日志目录存在
    mkdir -p "$(dirname "$LOG_FILE")"
    mkdir -p "/var/log/traffic_monitor"

    # 获取初始数据
    local initial_stats
    initial_stats=$(get_interface_stats "$interface")
    local prev_rx=$(echo "$initial_stats" | awk '{print $1}')
    local prev_tx=$(echo "$initial_stats" | awk '{print $2}')
    local prev_time=$(date +%s)

    log_info "初始化完成，开始监控..."

    while true; do
        sleep "$CHECK_INTERVAL"

        # 获取当前数据
        local current_stats
        current_stats=$(get_interface_stats "$interface")
        local current_rx=$(echo "$current_stats" | awk '{print $1}')
        local current_tx=$(echo "$current_stats" | awk '{print $2}')
        local current_time=$(date +%s)

        # 计算时间差
        local time_diff=$((current_time - prev_time))

        # 计算流量速率
        local rates
        rates=$(calculate_rate "$current_rx" "$current_tx" "$prev_rx" "$prev_tx" "$time_diff")
        local rx_rate=$(echo "$rates" | awk '{print $1}')
        local tx_rate=$(echo "$rates" | awk '{print $2}')
        local total_rate=$(echo "$rates" | awk '{print $3}')

        # 检测异常
        check_traffic_anomaly "$rx_rate" "$tx_rate" "$total_rate" "$interface" "$time_diff"

        # 更新前一次的数据
        prev_rx=$current_rx
        prev_tx=$current_tx
        prev_time=$current_time
    done
}

# 配置函数
configure_monitor() {
    echo -e "${YELLOW}流量监控配置${NC}"
    echo

    # 网络接口
    local detected_interface=$(detect_interface)
    read -p "网络接口 (默认: $detected_interface): " input_interface
    INTERFACE=${input_interface:-$detected_interface}

    # 检测间隔
    echo "选择监控间隔:"
    echo "1) 5分钟 (300秒)"
    echo "2) 10分钟 (600秒)"
    echo "3) 15分钟 (900秒)"
    echo "4) 自定义"
    read -p "请选择 (1-4): " interval_choice

    case $interval_choice in
        1) CHECK_INTERVAL=300 ;;
        2) CHECK_INTERVAL=600 ;;
        3) CHECK_INTERVAL=900 ;;
        4) read -p "请输入监控间隔(秒): " CHECK_INTERVAL ;;
    esac

    # 告警阈值
    read -p "流量告警阈值(MB) (默认: $ALERT_THRESHOLD_MB): " threshold
    ALERT_THRESHOLD_MB=${threshold:-$ALERT_THRESHOLD_MB}

    read -p "突发流量阈值(MB) (默认: $BURST_THRESHOLD_MB): " burst
    BURST_THRESHOLD_MB=${burst:-$BURST_THRESHOLD_MB}

    # Telegram配置
    read -p "是否启用Telegram告警? [y/N]: " enable_tg
    if [[ $enable_tg =~ ^[Yy]$ ]]; then
        ENABLE_TELEGRAM=true
        read -p "Telegram Bot Token: " BOT_TOKEN
        read -p "Telegram Chat ID: " CHAT_ID
    fi

    echo
    echo -e "${GREEN}配置完成:${NC}"
    echo "• 监控接口: $INTERFACE"
    echo "• 检测间隔: ${CHECK_INTERVAL}秒"
    echo "• 流量阈值: ${ALERT_THRESHOLD_MB}MB"
    echo "• 突发阈值: ${BURST_THRESHOLD_MB}MB"
    echo "• Telegram告警: $ENABLE_TELEGRAM"
}

# 显示状态
show_status() {
    local interface=$(detect_interface)
    echo -e "${BLUE}流量监控状态${NC}"
    echo

    # 当前流量
    local current_stats
    current_stats=$(get_interface_stats "$interface")
    local current_rx=$(echo "$current_stats" | awk '{print $1}')
    local current_tx=$(echo "$current_stats" | awk '{print $2}')

    echo "接口: $interface"
    echo "累计接收: $(bytes_to_mb "$current_rx") MB"
    echo "累计发送: $(bytes_to_mb "$current_tx") MB"
    echo

    # 最近告警
    if [ -f "/var/log/traffic_monitor/alerts.log" ]; then
        echo "最近告警:"
        tail -5 "/var/log/traffic_monitor/alerts.log" | while IFS=',' read -r timestamp interface total_mb rx_mb tx_mb reason; do
            echo "  $timestamp - 总计:${total_mb}MB - $reason"
        done
    fi

    # vnstat基线
    local baseline=$(get_vnstat_baseline "$interface")
    if [ "$baseline" != "0" ]; then
        echo
        echo "基线数据: 平均 ${baseline} MB/分钟"
    fi
}

# 主函数
main() {
    case "${1:-}" in
        "start")
            start_monitoring
            ;;
        "config")
            configure_monitor
            ;;
        "status")
            show_status
            ;;
        "test")
            local interface=$(detect_interface)
            log_info "测试模式 - 接口: $interface"
            # 模拟高流量触发告警
            ALERT_THRESHOLD_MB=1
            check_traffic_anomaly 1048576 1048576 2097152 "$interface" 60
            ;;
        *)
            echo "用法: $0 {start|config|status|test}"
            echo
            echo "命令说明:"
            echo "  start   - 开始流量监控"
            echo "  config  - 配置监控参数"
            echo "  status  - 显示当前状态"
            echo "  test    - 测试告警功能"
            echo
            echo "配置文件: 编辑脚本顶部的配置参数"
            echo "日志文件: $LOG_FILE"
            ;;
    esac
}

# 检查依赖
check_dependencies() {
    local missing_deps=()

    if ! command -v bc &> /dev/null; then
        missing_deps+=("bc")
    fi

    if ! command -v curl &> /dev/null; then
        missing_deps+=("curl")
    fi

    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${RED}缺少依赖: ${missing_deps[*]}${NC}"
        echo "请安装: apt-get install ${missing_deps[*]} 或 yum install ${missing_deps[*]}"
        exit 1
    fi
}

# 检查依赖并运行
check_dependencies
main "$@"