#!/bin/bash

# =============================================================================
# 服务器流量监控自动安装脚本
# =============================================================================

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 脚本配置
SCRIPT_NAME="vnstat_notice.sh"
MONITOR_SCRIPT_NAME="traffic_monitor.sh"
SCRIPT_URL="https://raw.githubusercontent.com/konghanghang/images/refs/heads/master/sh/vnstat_notice.sh"
MONITOR_SCRIPT_URL="https://raw.githubusercontent.com/konghanghang/images/refs/heads/master/sh/traffic_monitor.sh"
INSTALL_DIR="/opt/traffic_monitor"
LOG_DIR="/var/log/traffic_monitor"

# 输出函数
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# 检查是否为root用户
check_root() {
    if [[ $EUID -ne 0 ]]; then
        log_error "此脚本需要root权限运行"
        log_info "请使用: sudo $0"
        exit 1
    fi
}

# 检测系统类型
detect_system() {
    if [[ -f /etc/os-release ]]; then
        source /etc/os-release
        OS=$ID
        VER=$VERSION_ID
    else
        log_error "无法检测系统类型"
        exit 1
    fi

    log_info "检测到系统: $OS $VER"
}

# 检查和安装vnstat
install_vnstat() {
    log_info "检查vnstat安装状态..."

    # 检查vnstat是否已安装
    if command -v vnstat &> /dev/null; then
        log_info "发现vnstat已安装，检查运行状态..."

        # 检查服务状态
        if systemctl is-active --quiet vnstat; then
            log_success "vnstat已安装且运行正常"

            # 检查是否有数据库文件
            if [ -d "/var/lib/vnstat" ] && [ "$(ls -A /var/lib/vnstat 2>/dev/null)" ]; then
                log_success "vnstat数据库已初始化"
            else
                log_warning "vnstat数据库未初始化，等待数据收集..."
            fi
            return 0
        else
            log_warning "vnstat已安装但未运行，尝试启动..."
            if systemctl enable vnstat && systemctl start vnstat; then
                log_success "vnstat服务启动成功"
                return 0
            else
                log_error "vnstat服务启动失败"
            fi
        fi
    else
        log_info "vnstat未安装，开始安装..."

        # 安装必要的依赖包
        case $OS in
            ubuntu|debian)
                apt-get update
                apt-get install -y vnstat bc curl jq
                ;;
            centos|rhel|rocky|almalinux)
                if command -v dnf &> /dev/null; then
                    dnf install -y epel-release
                    dnf install -y vnstat bc curl jq
                else
                    yum install -y epel-release
                    yum install -y vnstat bc curl jq
                fi
                ;;
            *)
                log_error "不支持的系统类型: $OS"
                exit 1
                ;;
        esac

        # 启动vnstat服务
        if systemctl enable vnstat && systemctl start vnstat; then
            log_success "vnstat安装并启动成功"

            # 等待vnstat初始化
            log_info "等待vnstat初始化网络接口..."
            sleep 5

            # 检查服务状态
            if systemctl is-active --quiet vnstat; then
                log_success "vnstat服务运行正常"
            else
                log_error "vnstat服务状态异常"
                systemctl status vnstat
                exit 1
            fi
        else
            log_error "vnstat启动失败"
            exit 1
        fi
    fi

    # 显示vnstat状态信息
    log_info "当前vnstat状态:"
    vnstat --version 2>/dev/null || log_warning "无法获取vnstat版本信息"

    # 检查监控的网络接口
    local interfaces=$(vnstat --iflist 2>/dev/null | grep -E "Available interfaces|可用接口" -A 10 | grep -v "Available\|可用" | head -5)
    if [ -n "$interfaces" ]; then
        log_info "监控的网络接口: $interfaces"
    else
        log_warning "暂无可用的网络接口数据"
    fi
}

# 创建安装目录
create_directories() {
    log_info "创建安装目录..."

    mkdir -p "$INSTALL_DIR"
    mkdir -p "$LOG_DIR"

    log_success "目录创建完成"
}

# 下载流量监控脚本
download_script() {
    log_info "下载流量监控脚本..."

    # 下载vnstat通知脚本
    if [[ -f "./sh/$SCRIPT_NAME" ]]; then
        log_info "使用本地vnstat通知脚本"
        cp "./sh/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
    else
        log_info "从GitHub下载vnstat通知脚本: $SCRIPT_URL"
        if ! curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"; then
            log_error "vnstat通知脚本下载失败"
            log_info "请检查URL是否正确或网络连接"
            exit 1
        fi
    fi
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

    # 询问是否需要实时流量监控
    echo
    read -p "是否需要实时流量异常监控功能? [y/N]: " install_monitor
    if [[ $install_monitor =~ ^[Yy]$ ]]; then
        if [[ -f "./sh/$MONITOR_SCRIPT_NAME" ]]; then
            log_info "使用本地实时监控脚本"
            cp "./sh/$MONITOR_SCRIPT_NAME" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
        else
            log_info "从GitHub下载实时监控脚本: $MONITOR_SCRIPT_URL"
            if ! curl -fsSL "$MONITOR_SCRIPT_URL" -o "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"; then
                log_warning "实时监控脚本下载失败，跳过此功能"
            fi
        fi

        if [[ -f "$INSTALL_DIR/$MONITOR_SCRIPT_NAME" ]]; then
            chmod +x "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
            log_success "实时监控脚本安装完成"
        fi
    fi

    log_success "脚本下载完成"
}

# 配置用户参数
configure_script() {
    log_info "配置脚本参数..."

    echo
    echo -e "${YELLOW}请输入以下配置信息:${NC}"

    # Telegram配置
    read -p "请输入Telegram Bot Token: " BOT_TOKEN
    read -p "请输入Telegram Chat ID: " CHAT_ID

    # 服务器配置
    read -p "请输入服务器名称 (默认: 服务器): " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-"服务器"}

    read -p "请输入月流量配额(GB) (默认: 200): " MONTHLY_QUOTA
    MONTHLY_QUOTA=${MONTHLY_QUOTA:-200}

    # 更新脚本配置
    sed -i "s/BOT_TOKEN=\"\"/BOT_TOKEN=\"$BOT_TOKEN\"/" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s/CHAT_ID=\"\"/CHAT_ID=\"$CHAT_ID\"/" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s/SERVER_NAME=\".*\"/SERVER_NAME=\"$SERVER_NAME\"/" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s/MONTHLY_QUOTA=.*/MONTHLY_QUOTA=$MONTHLY_QUOTA/" "$INSTALL_DIR/$SCRIPT_NAME"

    log_success "vnstat通知脚本配置完成"

    # 如果安装了实时监控脚本，进行配置
    if [[ -f "$INSTALL_DIR/$MONITOR_SCRIPT_NAME" ]]; then
        configure_traffic_monitor_in_complete
    fi
}

# 配置流量统计通知（独立安装时使用）
configure_traffic_report() {
    log_info "配置流量统计通知参数..."

    echo
    echo -e "${YELLOW}请输入以下配置信息:${NC}"

    # Telegram配置
    read -p "请输入Telegram Bot Token: " BOT_TOKEN
    read -p "请输入Telegram Chat ID: " CHAT_ID

    # 服务器配置
    read -p "请输入服务器名称 (默认: 服务器): " SERVER_NAME
    SERVER_NAME=${SERVER_NAME:-"服务器"}

    read -p "请输入月流量配额(GB) (默认: 200): " MONTHLY_QUOTA
    MONTHLY_QUOTA=${MONTHLY_QUOTA:-200}

    # 更新脚本配置
    sed -i "s/BOT_TOKEN=\"\"/BOT_TOKEN=\"$BOT_TOKEN\"/" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s/CHAT_ID=\"\"/CHAT_ID=\"$CHAT_ID\"/" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s/SERVER_NAME=\".*\"/SERVER_NAME=\"$SERVER_NAME\"/" "$INSTALL_DIR/$SCRIPT_NAME"
    sed -i "s/MONTHLY_QUOTA=.*/MONTHLY_QUOTA=$MONTHLY_QUOTA/" "$INSTALL_DIR/$SCRIPT_NAME"

    log_success "流量统计通知配置完成"
}

# 配置实时流量监控（独立安装时使用）
configure_traffic_monitor() {
    log_info "配置实时流量监控参数..."

    echo
    echo -e "${YELLOW}请输入以下配置信息:${NC}"

    # 监控参数
    read -p "流量异常告警阈值(MB/5分钟) (默认: 100): " alert_threshold
    alert_threshold=${alert_threshold:-100}

    read -p "突发流量阈值(MB/5分钟) (默认: 500): " burst_threshold
    burst_threshold=${burst_threshold:-500}

    # Telegram配置
    read -p "是否启用Telegram告警? [y/N]: " enable_tg
    if [[ $enable_tg =~ ^[Yy]$ ]]; then
        read -p "Telegram Bot Token: " BOT_TOKEN
        read -p "Telegram Chat ID: " CHAT_ID

        sed -i "s/BOT_TOKEN=\"\"/BOT_TOKEN=\"$BOT_TOKEN\"/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
        sed -i "s/CHAT_ID=\"\"/CHAT_ID=\"$CHAT_ID\"/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
        sed -i "s/ENABLE_TELEGRAM=false/ENABLE_TELEGRAM=true/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
    fi

    # 更新阈值配置
    sed -i "s/ALERT_THRESHOLD_MB=100/ALERT_THRESHOLD_MB=$alert_threshold/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
    sed -i "s/BURST_THRESHOLD_MB=500/BURST_THRESHOLD_MB=$burst_threshold/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"

    log_success "实时流量监控配置完成"
}

# 在完整安装中配置实时监控（复用已有Telegram配置）
configure_traffic_monitor_in_complete() {
    echo
    log_info "配置实时流量监控..."

    read -p "流量异常告警阈值(MB/5分钟) (默认: 100): " alert_threshold
    alert_threshold=${alert_threshold:-100}

    read -p "是否启用实时监控的Telegram告警? [y/N]: " enable_realtime_tg
    if [[ $enable_realtime_tg =~ ^[Yy]$ ]]; then
        # 使用已配置的Telegram信息
        sed -i "s/BOT_TOKEN=\"\"/BOT_TOKEN=\"$BOT_TOKEN\"/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
        sed -i "s/CHAT_ID=\"\"/CHAT_ID=\"$CHAT_ID\"/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
        sed -i "s/ENABLE_TELEGRAM=false/ENABLE_TELEGRAM=true/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
    fi

    sed -i "s/ALERT_THRESHOLD_MB=100/ALERT_THRESHOLD_MB=$alert_threshold/" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"

    log_success "实时监控脚本配置完成"
}

# 添加定时任务
setup_crontab() {
    log_info "配置定时任务..."

    echo
    echo -e "${YELLOW}请选择执行频率:${NC}"
    echo "1) 每天 09:00 执行"
    echo "2) 每天 09:00 和 21:00 执行"
    echo "3) 每6小时执行一次"
    echo "4) 自定义时间"

    read -p "请选择 (1-4): " choice

    case $choice in
        1)
            CRON_SCHEDULE="0 9 * * *"
            ;;
        2)
            CRON_SCHEDULE="0 9,21 * * *"
            ;;
        3)
            CRON_SCHEDULE="0 */6 * * *"
            ;;
        4)
            read -p "请输入cron表达式 (如: 0 9 * * *): " CRON_SCHEDULE
            ;;
        *)
            log_warning "无效选择，使用默认设置: 每天09:00执行"
            CRON_SCHEDULE="0 9 * * *"
            ;;
    esac

    echo
    echo -e "${YELLOW}请选择定时任务类型:${NC}"
    echo "1) 系统级定时任务 (/etc/crontab) - 推荐"
    echo "2) Root用户定时任务 (root crontab)"

    read -p "请选择 (1-2，默认1): " cron_type
    cron_type=${cron_type:-1}

    if [ "$cron_type" = "2" ]; then
        # Root用户crontab
        CRON_COMMAND="$CRON_SCHEDULE $INSTALL_DIR/$SCRIPT_NAME >> $LOG_DIR/cron.log 2>&1"

        # 检查root用户crontab是否已存在该任务
        if ! crontab -l 2>/dev/null | grep -q "$SCRIPT_NAME"; then
            # 备份现有crontab
            crontab -l 2>/dev/null > /tmp/current_crontab || echo "" > /tmp/current_crontab

            # 添加新任务
            echo "$CRON_COMMAND" >> /tmp/current_crontab

            # 安装新的crontab
            crontab /tmp/current_crontab

            # 清理临时文件
            rm -f /tmp/current_crontab

            log_success "定时任务添加到root用户crontab: $CRON_SCHEDULE"
            log_info "可使用 'crontab -l' 查看"
        else
            log_warning "root用户crontab中已存在该任务，跳过添加"
        fi
    else
        # 系统级crontab
        CRON_COMMAND="$CRON_SCHEDULE root $INSTALL_DIR/$SCRIPT_NAME >> $LOG_DIR/cron.log 2>&1"

        # 检查系统crontab是否已存在该任务
        if ! grep -q "$SCRIPT_NAME" /etc/crontab 2>/dev/null; then
            echo "$CRON_COMMAND" >> /etc/crontab
            log_success "定时任务添加到系统crontab: $CRON_SCHEDULE"
            log_info "可查看 /etc/crontab 文件"
        else
            log_warning "系统crontab中已存在该任务，跳过添加"
        fi
    fi

    # 重启cron服务
    systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true

    # 显示当前定时任务状态
    echo
    log_info "当前定时任务状态："
    if [ "$cron_type" = "2" ]; then
        echo "Root用户定时任务:"
        crontab -l 2>/dev/null | grep "$SCRIPT_NAME" || log_warning "未找到相关任务"
    else
        echo "系统级定时任务:"
        grep "$SCRIPT_NAME" /etc/crontab 2>/dev/null || log_warning "未找到相关任务"
    fi

    # 设置实时监控后台服务
    if [[ -f "$INSTALL_DIR/$MONITOR_SCRIPT_NAME" ]]; then
        echo
        read -p "是否启动实时流量监控后台服务? [y/N]: " start_monitor
        if [[ $start_monitor =~ ^[Yy]$ ]]; then
            setup_monitor_service
        else
            log_info "可以稍后手动启动: $INSTALL_DIR/$MONITOR_SCRIPT_NAME start &"
        fi
    fi
}

# 为流量统计通知设置定时任务
setup_report_crontab() {
    log_info "配置流量统计通知定时任务..."

    echo
    echo -e "${YELLOW}请选择执行频率:${NC}"
    echo "1) 每天 09:00 执行"
    echo "2) 每天 09:00 和 21:00 执行"
    echo "3) 每6小时执行一次"
    echo "4) 自定义时间"

    read -p "请选择 (1-4): " choice

    case $choice in
        1)
            CRON_SCHEDULE="0 9 * * *"
            ;;
        2)
            CRON_SCHEDULE="0 9,21 * * *"
            ;;
        3)
            CRON_SCHEDULE="0 */6 * * *"
            ;;
        4)
            read -p "请输入cron表达式 (如: 0 9 * * *): " CRON_SCHEDULE
            ;;
        *)
            log_warning "无效选择，使用默认设置: 每天09:00执行"
            CRON_SCHEDULE="0 9 * * *"
            ;;
    esac

    # 添加到系统crontab
    CRON_COMMAND="$CRON_SCHEDULE root $INSTALL_DIR/$SCRIPT_NAME >> $LOG_DIR/cron.log 2>&1"

    if ! grep -q "$SCRIPT_NAME" /etc/crontab 2>/dev/null; then
        echo "$CRON_COMMAND" >> /etc/crontab
        log_success "定时任务添加成功: $CRON_SCHEDULE"
    else
        log_warning "定时任务已存在"
    fi

    systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
}

# 设置实时监控服务
setup_monitor_service() {
    log_info "设置实时流量监控后台服务..."

    # 创建systemd服务文件
    cat > "/etc/systemd/system/traffic-monitor.service" << EOF
[Unit]
Description=Real-time Traffic Monitor
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=$INSTALL_DIR
ExecStart=$INSTALL_DIR/$MONITOR_SCRIPT_NAME start
Restart=always
RestartSec=10
StandardOutput=append:$LOG_DIR/monitor.log
StandardError=append:$LOG_DIR/monitor.log

[Install]
WantedBy=multi-user.target
EOF

    # 重新加载systemd配置
    systemctl daemon-reload

    # 启用并启动服务
    if systemctl enable traffic-monitor && systemctl start traffic-monitor; then
        log_success "实时监控服务启动成功"
        log_info "服务状态: systemctl status traffic-monitor"
        log_info "查看日志: journalctl -u traffic-monitor -f"
    else
        log_error "实时监控服务启动失败"
        log_info "可以手动启动: $INSTALL_DIR/$MONITOR_SCRIPT_NAME start &"
    fi
}

# 测试脚本
test_script() {
    log_info "测试脚本运行..."

    if "$INSTALL_DIR/$SCRIPT_NAME"; then
        log_success "脚本测试成功"
    else
        log_error "脚本测试失败，请检查配置"
        log_info "可以手动运行以下命令测试:"
        log_info "$INSTALL_DIR/$SCRIPT_NAME"
    fi
}

# 显示安装信息
show_info() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    流量监控系统安装完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}安装位置:${NC} $INSTALL_DIR/$SCRIPT_NAME"
    echo -e "${BLUE}日志位置:${NC} $LOG_DIR/"
    echo -e "${BLUE}定时任务:${NC} $CRON_SCHEDULE"
    echo
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  手动运行统计: $INSTALL_DIR/$SCRIPT_NAME"
    echo "  查看统计日志: tail -f $LOG_DIR/telegram_success.log"
    echo "  查看定时日志: tail -f $LOG_DIR/cron.log"
    echo "  查看系统定时任务: cat /etc/crontab | grep vnstat"
    echo "  查看用户定时任务: crontab -l"
    echo "  vnstat状态: systemctl status vnstat"

    if [[ -f "$INSTALL_DIR/$MONITOR_SCRIPT_NAME" ]]; then
        echo
        echo "  实时监控服务: systemctl status traffic-monitor"
        echo "  监控日志: tail -f $LOG_DIR/monitor.log"
        echo "  异常告警记录: tail -f $LOG_DIR/alerts.log"
        echo "  手动启动监控: $INSTALL_DIR/$MONITOR_SCRIPT_NAME start &"
        echo "  监控配置: $INSTALL_DIR/$MONITOR_SCRIPT_NAME config"
    fi
    echo
    echo -e "${YELLOW}注意事项:${NC}"
    echo "• vnstat需要运行一段时间才能收集到准确数据"
    echo "• 首次运行可能使用默认示例数据"
    echo "• 可以编辑 $INSTALL_DIR/$SCRIPT_NAME 调整配置"
    echo
}

# 清理函数
cleanup() {
    if [[ $? -ne 0 ]]; then
        log_error "安装过程中出现错误"
        log_info "清理临时文件..."
        # 这里可以添加清理逻辑
    fi
}

# 显示安装菜单
show_menu() {
    echo -e "${BLUE}"
    echo "========================================"
    echo "    服务器流量监控自动安装脚本"
    echo "========================================"
    echo -e "${NC}"
    echo
    echo -e "${YELLOW}请选择要安装的功能:${NC}"
    echo
    echo "1) 流量统计通知 - 定期发送vnstat流量统计报告"
    echo "   • 基于vnstat历史数据"
    echo "   • 支持日报/周报/月报"
    echo "   • Telegram推送"
    echo
    echo "2) 实时流量监控 - 检测异常流量并告警"
    echo "   • 5-15分钟间隔检测"
    echo "   • 异常流量实时告警"
    echo "   • 后台服务运行"
    echo
    echo "3) 完整安装 - 同时安装上述两个功能"
    echo
    echo "4) 卸载功能"
    echo
    echo "0) 退出"
    echo
}

# 流量统计通知安装
install_traffic_report() {
    log_info "安装流量统计通知功能..."

    check_root
    detect_system
    install_vnstat
    create_directories

    # 只下载vnstat通知脚本
    if [[ -f "./sh/$SCRIPT_NAME" ]]; then
        log_info "使用本地vnstat通知脚本"
        cp "./sh/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
    else
        log_info "从GitHub下载vnstat通知脚本: $SCRIPT_URL"
        if ! curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"; then
            log_error "vnstat通知脚本下载失败"
            exit 1
        fi
    fi
    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"

    # 配置vnstat通知
    configure_traffic_report
    setup_report_crontab
    test_script
    show_report_info

    log_success "流量统计通知安装完成!"
}

# 实时流量监控安装
install_traffic_monitor() {
    log_info "安装实时流量监控功能..."

    check_root
    detect_system
    create_directories

    # 只下载实时监控脚本
    if [[ -f "./sh/$MONITOR_SCRIPT_NAME" ]]; then
        log_info "使用本地实时监控脚本"
        cp "./sh/$MONITOR_SCRIPT_NAME" "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"
    else
        log_info "从GitHub下载实时监控脚本: $MONITOR_SCRIPT_URL"
        if ! curl -fsSL "$MONITOR_SCRIPT_URL" -o "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"; then
            log_error "实时监控脚本下载失败"
            exit 1
        fi
    fi
    chmod +x "$INSTALL_DIR/$MONITOR_SCRIPT_NAME"

    # 配置实时监控
    configure_traffic_monitor
    setup_monitor_service
    show_monitor_info

    log_success "实时流量监控安装完成!"
}

# 完整安装
install_complete() {
    log_info "开始完整安装..."

    check_root
    detect_system
    install_vnstat
    create_directories

    # 下载两个脚本
    download_script
    configure_script
    setup_crontab
    test_script
    show_info

    log_success "完整安装完成!"
}

# 主函数
main() {
    trap cleanup EXIT

    show_menu

    read -p "请选择 (0-4): " choice

    case $choice in
        1)
            install_traffic_report
            ;;
        2)
            install_traffic_monitor
            ;;
        3)
            install_complete
            ;;
        4)
            detect_system
            uninstall
            ;;
        0)
            log_info "退出安装"
            exit 0
            ;;
        *)
            log_error "无效选择: $choice"
            exit 1
            ;;
    esac
}

# 显示流量统计通知安装信息
show_report_info() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    流量统计通知安装完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}安装位置:${NC} $INSTALL_DIR/$SCRIPT_NAME"
    echo -e "${BLUE}日志位置:${NC} $LOG_DIR/"
    echo -e "${BLUE}定时任务:${NC} $CRON_SCHEDULE"
    echo
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  手动运行: $INSTALL_DIR/$SCRIPT_NAME"
    echo "  查看日志: tail -f $LOG_DIR/telegram_success.log"
    echo "  查看定时日志: tail -f $LOG_DIR/cron.log"
    echo "  查看定时任务: cat /etc/crontab | grep vnstat"
    echo "  vnstat状态: systemctl status vnstat"
    echo
    echo -e "${YELLOW}注意事项:${NC}"
    echo "• vnstat需要运行一段时间才能收集到准确数据"
    echo "• 首次运行可能使用默认示例数据"
    echo
}

# 显示实时监控安装信息
show_monitor_info() {
    echo
    echo -e "${GREEN}========================================${NC}"
    echo -e "${GREEN}    实时流量监控安装完成!${NC}"
    echo -e "${GREEN}========================================${NC}"
    echo
    echo -e "${BLUE}安装位置:${NC} $INSTALL_DIR/$MONITOR_SCRIPT_NAME"
    echo -e "${BLUE}日志位置:${NC} $LOG_DIR/"
    echo -e "${BLUE}服务状态:${NC} systemctl status traffic-monitor"
    echo
    echo -e "${YELLOW}常用命令:${NC}"
    echo "  查看服务状态: systemctl status traffic-monitor"
    echo "  重启监控服务: systemctl restart traffic-monitor"
    echo "  查看实时日志: journalctl -u traffic-monitor -f"
    echo "  查看监控日志: tail -f $LOG_DIR/monitor.log"
    echo "  查看异常记录: tail -f $LOG_DIR/alerts.log"
    echo "  手动配置: $INSTALL_DIR/$MONITOR_SCRIPT_NAME config"
    echo
    echo -e "${YELLOW}注意事项:${NC}"
    echo "• 监控服务在后台持续运行"
    echo "• 检测到异常流量会立即发送告警"
    echo "• 可根据需要调整告警阈值"
    echo
}

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo
    echo "交互式安装 (推荐):"
    echo "  $0              显示安装菜单"
    echo
    echo "选项:"
    echo "  -h, --help      显示帮助信息"
    echo "  --report        直接安装流量统计通知功能"
    echo "  --monitor       直接安装实时流量监控功能"
    echo "  --complete      直接安装完整功能"
    echo "  --uninstall     卸载已安装的功能"
    echo
    echo "功能说明:"
    echo "  流量统计通知   - 基于vnstat的定期流量报告 (定时任务)"
    echo "  实时流量监控   - 异常流量检测和告警 (后台服务)"
    echo "  完整安装       - 同时安装上述两个功能"
    echo
    echo "示例:"
    echo "  $0 --report     只安装流量统计通知"
    echo "  $0 --monitor    只安装实时流量监控"
    echo "  $0 --complete   安装完整功能"
    echo
}

# 卸载函数
uninstall() {
    log_info "开始卸载流量监控系统..."

    # 删除定时任务
    sed -i "/$SCRIPT_NAME/d" /etc/crontab

    # 删除文件
    rm -rf "$INSTALL_DIR"

    # 询问是否删除日志
    read -p "是否删除日志文件? [y/N]: " remove_logs
    if [[ $remove_logs =~ ^[Yy]$ ]]; then
        rm -rf "$LOG_DIR"
    fi

    # 询问是否卸载vnstat
    read -p "是否卸载vnstat? [y/N]: " remove_vnstat
    if [[ $remove_vnstat =~ ^[Yy]$ ]]; then
        case $OS in
            ubuntu|debian)
                apt-get remove -y vnstat
                ;;
            centos|rhel|rocky|almalinux)
                if command -v dnf &> /dev/null; then
                    dnf remove -y vnstat
                else
                    yum remove -y vnstat
                fi
                ;;
        esac
    fi

    log_success "卸载完成"
}

# 参数处理
case "$1" in
    -h|--help)
        show_help
        exit 0
        ;;
    --report)
        install_traffic_report
        ;;
    --monitor)
        install_traffic_monitor
        ;;
    --complete)
        install_complete
        ;;
    --uninstall)
        detect_system
        uninstall
        ;;
    "")
        main
        ;;
    *)
        echo "未知参数: $1"
        show_help
        exit 1
        ;;
esac