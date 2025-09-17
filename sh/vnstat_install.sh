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
SCRIPT_URL="https://raw.githubusercontent.com/konghanghang/images/refs/heads/master/sh/vnstat_notice.sh"
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

# 安装vnstat
install_vnstat() {
    log_info "开始安装vnstat..."

    case $OS in
        ubuntu|debian)
            apt-get update
            apt-get install -y vnstat bc curl
            ;;
        centos|rhel|rocky|almalinux)
            if command -v dnf &> /dev/null; then
                dnf install -y epel-release
                dnf install -y vnstat bc curl
            else
                yum install -y epel-release
                yum install -y vnstat bc curl
            fi
            ;;
        *)
            log_error "不支持的系统类型: $OS"
            exit 1
            ;;
    esac

    # 启动vnstat服务
    systemctl enable vnstat
    systemctl start vnstat

    # 等待vnstat初始化
    log_info "等待vnstat初始化网络接口..."
    sleep 5

    # 检查vnstat状态
    if systemctl is-active --quiet vnstat; then
        log_success "vnstat安装并启动成功"
    else
        log_error "vnstat启动失败"
        exit 1
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

    # 如果是本地文件，直接复制
    if [[ -f "./sh/$SCRIPT_NAME" ]]; then
        log_info "使用本地脚本文件"
        cp "./sh/$SCRIPT_NAME" "$INSTALL_DIR/$SCRIPT_NAME"
    else
        # 从GitHub下载
        log_info "从GitHub下载脚本: $SCRIPT_URL"
        if ! curl -fsSL "$SCRIPT_URL" -o "$INSTALL_DIR/$SCRIPT_NAME"; then
            log_error "脚本下载失败"
            log_info "请检查URL是否正确或网络连接"
            exit 1
        fi
    fi

    chmod +x "$INSTALL_DIR/$SCRIPT_NAME"
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

    log_success "脚本配置完成"
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

    # 添加定时任务
    CRON_COMMAND="$CRON_SCHEDULE root $INSTALL_DIR/$SCRIPT_NAME >> $LOG_DIR/cron.log 2>&1"

    # 检查是否已存在
    if ! grep -q "$SCRIPT_NAME" /etc/crontab; then
        echo "$CRON_COMMAND" >> /etc/crontab
        log_success "定时任务添加成功: $CRON_SCHEDULE"
    else
        log_warning "定时任务已存在，跳过添加"
    fi

    # 重启cron服务
    systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null || true
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
    echo "  手动运行: $INSTALL_DIR/$SCRIPT_NAME"
    echo "  查看日志: tail -f $LOG_DIR/telegram_success.log"
    echo "  查看定时任务: crontab -l"
    echo "  vnstat状态: systemctl status vnstat"
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

# 主函数
main() {
    trap cleanup EXIT

    echo -e "${BLUE}"
    echo "========================================"
    echo "    服务器流量监控自动安装脚本"
    echo "========================================"
    echo -e "${NC}"

    check_root
    detect_system
    install_vnstat
    create_directories
    download_script
    configure_script
    setup_crontab
    test_script
    show_info

    log_success "安装完成!"
}

# 帮助信息
show_help() {
    echo "用法: $0 [选项]"
    echo
    echo "选项:"
    echo "  -h, --help     显示帮助信息"
    echo "  -u, --url URL  指定脚本下载URL"
    echo "  --uninstall    卸载流量监控系统"
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
    -u|--url)
        SCRIPT_URL="$2"
        main
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