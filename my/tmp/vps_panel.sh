#!/bin/bash

# ==================== 颜色函数 ====================
red() { echo -e "\e[1;91m$1\e[0m"; }
green() { echo -e "\e[1;32m$1\e[0m"; }
yellow() { echo -e "\e[1;33m$1\e[0m"; }
purple() { echo -e "\e[1;35m$1\e[0m"; }

# ==================== 参数配置 ====================
export FILE_PATH=${FILE_PATH:-'/root/panel'}
export ENABLE_ARGO=${ENABLE_ARGO:-'false'}  # true or false true为开启argo。一些网络不便的vps使用argo。一般直连就行。
export PORT=${PORT:-'8080'}
export PANEL_PASSWORD=${PANEL_PASSWORD:-'123456'}
export ARGO_DOMAIN=${ARGO_DOMAIN:-''}
export ARGO_AUTH=${ARGO_AUTH:-''}
export STATIC_IP="" # 在装有warp的vps上要自己手动设置真实ip，如hax。没有不填，留空

# 面板节点部分，不设为下面默认值。
export WS_ENABLE=${WS_ENABLE:-'false'}  # true为开启面板ws代理，订阅为/sub
export UUID=${UUID:-'7160b696-dd5e-42e3-a024-145e92cec916'}
export SUB_PATH=${SUB_PATH:-'sub'}
export CF_IP=${CF_IP:-'ip.sb'}
export SUB_NAME=${SUB_NAME:-'test'}
export MY_DOMAIN=${MY_DOMAIN:-''} # ENABLE_ARGO为false时，MY_DOMAIN有值则使用cdn cf域名
export CLIENT_TYPE=${CLIENT_TYPE:-'v2'}

# 检查是否为root下运行
if [ "$(id -u)" != 0 ]; then
  red "请在root用户下运行脚本"
  exit 1
fi

# 安全删除：路径为空时跳过，路径加引号
safe_rm() {
  local target
  for target in "$@"; do
    [ -z "$target" ] && continue
    [ -e "$target" ] && rm -rf -- "$target"
  done
}

# 建立运行目录
createfolder() {
  if [ ! -d "$FILE_PATH" ]; then
    mkdir -p "$FILE_PATH"
  fi
}

# 停止移除服务
stop_services() {
  if [ -f /etc/alpine-release ]; then
    if [ "${ENABLE_ARGO}" = "true" ]; then
      rc-service cloudflared stop
      rc-update del cloudflared default
      pkill -TERM -f "${FILE_PATH}/cloudflared" >/dev/null 2>&1 || true
      sleep 1
      pkill -KILL -f "${FILE_PATH}/cloudflared" >/dev/null 2>&1 || true
    fi
    rc-service panel stop
    rc-update del panel default
    pkill -TERM -f "${FILE_PATH}/system-panel" >/dev/null 2>&1 || true
    sleep 1
    pkill -KILL -f "${FILE_PATH}/system-panel" >/dev/null 2>&1 || true
  else
    if [ "${ENABLE_ARGO}" = "true" ]; then
      systemctl stop cloudflared 2>/dev/null
      systemctl disable cloudflared 2>/dev/null
    fi
    systemctl stop panel 2>/dev/null
    systemctl disable panel 2>/dev/null
  fi
}

# 清理文件
cleanup_files() {
  safe_rm "${FILE_PATH}"/*.log
  safe_rm "${FILE_PATH}"/tunnel.json "${FILE_PATH}"/tunnel.yml
  if [ -f /etc/alpine-release ]; then
    safe_rm /etc/init.d/panel
    if [ "${ENABLE_ARGO}" = "true" ]; then
      safe_rm /etc/init.d/cloudflared
    fi
  else
    safe_rm /etc/systemd/system/panel.service
    if [ "${ENABLE_ARGO}" = "true" ]; then
      safe_rm /etc/systemd/system/cloudflared.service
    fi
    systemctl daemon-reload 2>/dev/null || true
  fi
}

# 根据系统类型安装、卸载依赖
manage_packages() {
  if [ $# -lt 2 ]; then
    red "Unspecified package name or action"
    return 1
  fi

  action=$1
  shift

  for package in "$@"; do
    if [ "$action" == "install" ]; then
      if command -v "$package" &>/dev/null; then
        green "${package} already installed"
        continue
      fi
      yellow "正在安装 ${package}..."
      if command -v apt &>/dev/null; then
        DEBIAN_FRONTEND=noninteractive apt install -y "$package"
      elif command -v dnf &>/dev/null; then
        dnf install -y "$package"
      elif command -v yum &>/dev/null; then
        yum install -y "$package"
      elif command -v apk &>/dev/null; then
        apk update
        apk add "$package"
      else
        red "Unknown system!"
        return 1
      fi
    elif [ "$action" == "uninstall" ]; then
      if ! command -v "$package" &>/dev/null; then
        yellow "${package} is not installed"
        continue
      fi
      yellow "正在卸载 ${package}..."
      if command -v apt &>/dev/null; then
        apt remove -y "$package" && apt autoremove -y
      elif command -v dnf &>/dev/null; then
        dnf remove -y "$package" && dnf autoremove -y
      elif command -v yum &>/dev/null; then
        yum remove -y "$package" && yum autoremove -y
      elif command -v apk &>/dev/null; then
        apk del "$package"
      else
        red "Unknown system!"
        return 1
      fi
    else
      red "Unknown action: $action"
      return 1
    fi
  done

  return 0
}

# 检查并安装必要的工具
check_and_install_tools() {
  manage_packages install curl wget
}

# 设置下载
download_program() {
  local program_name="$1"
  local default_url="$2"
  local x64_url="$3"

  local download_url
  case "$(uname -m)" in
    x86_64|amd64|x64)
      download_url="${x64_url}"
      ;;
    *)
      download_url="${default_url}"
      ;;
  esac

  # 文件存在且大小大于 0
  if [ ! -s "${program_name}" ]; then
    if [ -n "${download_url}" ]; then
      echo "Downloading ${program_name}..."
      if command -v curl &> /dev/null; then
        curl -sSL "${download_url}" -o "${program_name}"
      elif command -v wget &> /dev/null; then
        wget -qO "${program_name}" "${download_url}"
      fi
      echo "Downloaded ${program_name}"
    else
      echo "Skipping download for ${program_name}"
    fi
  else
    echo "${program_name} already exists, skipping download"
  fi
  chmod +x "$program_name"
}

# 初始化下载
initialize_downloads() {
  download_program "${FILE_PATH}/system-panel" "https://github.com/kahunama/myfile/releases/download/main/system-panel-arm" "https://github.com/kahunama/myfile/releases/download/main/system-panel"

  case "$ENABLE_ARGO" in
    "true" )
      download_program "${FILE_PATH}/cloudflared" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
      ;;
    "false" )
      green "\n本次安装不使用argo隧道!"
      ;;
  esac
}

fetch_and_parse() {
    local url="$1"
    local json_key="$2"

    IP_INFO=$(curl -s "$url")

    if echo "$IP_INFO" | grep -q "\"${json_key}\""; then
        if [[ "$json_key" == "ip" ]]; then
            if [[ -z "$STATIC_IP" ]]; then
              SERVER_IP=$(echo "$IP_INFO" | sed -n 's/.*"ip": *"\([^"]*\).*/\1/p')
            else
              SERVER_IP="$STATIC_IP"
            fi
            ISP_NAME=$(echo "$IP_INFO" | sed -n 's/.*"isp": *"\([^"]*\).*/\1/p' | sed -e 's/[ ,\.]/_/g; s/__*/_/g; s/^_//; s/_$//')

            COUNTRY_CODE=$(echo "$IP_INFO" | sed -n 's/.*"country_code": *"\([^"]*\).*/\1/p')
        else
            # 针对 ip-api.com
            if [[ -z "$STATIC_IP" ]]; then
              SERVER_IP=$(echo "$IP_INFO" | sed -n 's/.*"query": *"\([^"]*\).*/\1/p')
            else
              SERVER_IP="$STATIC_IP"
            fi
            ISP_NAME=$(echo "$IP_INFO" | sed -n 's/.*"isp": *"\([^"]*\).*/\1/p' | sed -e 's/[ ,\.]/_/g; s/__*/_/g; s/^_//; s/_$//')
            COUNTRY_CODE=$(echo "$IP_INFO" | sed -n 's/.*"countryCode": *"\([^"]*\).*/\1/p')
        fi

        if [[ -n "$SERVER_IP" && -n "$ISP_NAME" && -n "$COUNTRY_CODE" ]]; then
            export SERVER_IP
            export ISP="${COUNTRY_CODE}-${ISP_NAME}"
            return 0
        fi
    fi
    return 1
}

# 获取IP及国家代码
get_ip_country_code() {
    local ip_value=""
    local api_status=1

    # 装有 warp 的 VPS 配置了 STATIC_IP：MYIP 直接取固定真实 IP，API 仅用于查询 ISP。
    if [[ -n "${STATIC_IP:-}" ]]; then
        ip_value="$STATIC_IP"
        api_status=0

        fetch_and_parse "https://api.ip.sb/geoip" "ip" || \
          fetch_and_parse "http://ip-api.com/json" "query" || \
          export ISP="UN"
    elif fetch_and_parse "https://api.ip.sb/geoip" "ip" || \
         fetch_and_parse "http://ip-api.com/json" "query" || \
         { [[ -n "${MYIP_URL:-}" ]] && fetch_and_parse "$MYIP_URL" "ip"; }; then
        ip_value="$SERVER_IP"
        api_status=0
    fi

    if [[ "$api_status" -eq 0 ]]; then
        # IPv6 地址放入 URL 时需要使用方括号。
        if [[ "$ip_value" == *:* ]]; then
            export MYIP="[$ip_value]"
            purple "本机的ipv6地址是: $ip_value"
        else
            export MYIP="$ip_value"
            purple "本机的ipv4地址是: $ip_value"
        fi
        purple "本机的ISP: ${ISP}"
        return 0
    fi

    # 保留原有非空兜底地址，避免后续面板地址为空；返回 1 表示公网查询失败。
    export MYIP="1.1.1.1"
    export ISP="UN"
    purple "本机的ip地址是: $MYIP"
    purple "本机的ISP: ${ISP}"
    return 1
}

create_services() {
  if [ "${ENABLE_ARGO}" = "true" ] && [ -e "${FILE_PATH}/cloudflared" ]; then
    ARGO_RUNS="${FILE_PATH}/cloudflared tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH}"
    if [ -f /etc/alpine-release ]; then
      cat > /etc/init.d/cloudflared << ARGO_EOF
#!/sbin/openrc-run

supervisor=supervise-daemon
name="cloudflared"
description="Cloudflare Tunnel"
command="$ARGO_RUNS"
start_pre() {
    pkill -9 -f "${FILE_PATH}/cloudflared" || true
    sleep 1
}
respawn_delay=5
respawn_max=0
supervise_daemon_args="--stdout /dev/null --stderr /dev/null"
ARGO_EOF
      chmod +x /etc/init.d/cloudflared
      rc-update add cloudflared default
    else
      cat > /etc/systemd/system/cloudflared.service << ARGO_EOF
[Unit]
Description=Cloudflare Tunnel
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=$ARGO_RUNS
Restart=on-failure
RestartSec=5s
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
ARGO_EOF
    fi
  fi

  if [ -e "${FILE_PATH}/system-panel" ]; then
    if [ -f /etc/alpine-release ]; then
      cat > /etc/init.d/panel << PANEL_EOF
#!/sbin/openrc-run

supervisor=supervise-daemon
name="panel"
description="system-panel service"
command="${FILE_PATH}/system-panel"
command_args=""
command_env="PORT=${PORT} PANEL_PASSWORD=${PANEL_PASSWORD} WS_ENABLE=${WS_ENABLE} UUID=${UUID} SUB_PATH=${SUB_PATH} CF_IP=${CF_IP} SUB_NAME=${SUB_NAME} MY_DOMAIN=${MY_DOMAIN} CLIENT_TYPE=${CLIENT_TYPE} STATIC_IP=${STATIC_IP}"
start_pre() {
    pkill -9 -f "${FILE_PATH}/system-panel" || true
    sleep 1
}
respawn_delay=5
respawn_max=0
supervise_daemon_args="--stdout /dev/null --stderr /dev/null"
PANEL_EOF
      chmod +x /etc/init.d/panel
      rc-update add panel default
    else
      cat > /etc/systemd/system/panel.service << PANEL_EOF
[Unit]
Description=System Panel Service
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
Environment=PORT=${PORT}
Environment=PANEL_PASSWORD=${PANEL_PASSWORD}
Environment=WS_ENABLE=${WS_ENABLE}
Environment=UUID=${UUID}
Environment=SUB_PATH=${SUB_PATH}
Environment=CF_IP=${CF_IP}
Environment=SUB_NAME=${SUB_NAME}
Environment=MY_DOMAIN=${MY_DOMAIN}
Environment=CLIENT_TYPE=${CLIENT_TYPE}
Environment=STATIC_IP=${STATIC_IP}
ExecStart=${FILE_PATH}/system-panel
Restart=on-failure
RestartSec=5s
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
PANEL_EOF
    fi
  fi

  if [ ! -f /etc/alpine-release ]; then
    systemctl daemon-reload 2>/dev/null || true
  fi
}

# 放行指定端口（不再清空全部防火墙规则）
open_ports() {
  local ports=()
  [ -n "${PORT}" ]        && ports+=("${PORT}")

  if command -v iptables &>/dev/null; then
    for p in "${ports[@]}"; do
      iptables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || true
      iptables -C INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || \
        iptables -I INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || true
    done
  fi
  if command -v ip6tables &>/dev/null; then
    for p in "${ports[@]}"; do
      ip6tables -C INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || \
        ip6tables -I INPUT -p tcp --dport "$p" -j ACCEPT 2>/dev/null || true
      ip6tables -C INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || \
        ip6tables -I INPUT -p udp --dport "$p" -j ACCEPT 2>/dev/null || true
    done
  fi
}

# 启动服务
run_processes() {
  # 放行所需端口（不再清空防火墙）
  open_ports

  if [ "${ENABLE_ARGO}" = "true" ] && [ -e "${FILE_PATH}/cloudflared" ]; then
    if [ -f /etc/alpine-release ]; then
      rc-service cloudflared start
    else
      systemctl enable cloudflared >/dev/null 2>&1
      systemctl start cloudflared
    fi
    green "cloudflared服务已成功启动"
  fi

  sleep 5

  # 当 WS_ENABLE 与 ENABLE_ARGO 同时开启时，订阅 /sub 内容使用 ARGO_DOMAIN 获取
  if [ "${WS_ENABLE}" = "true" ] && [ "${ENABLE_ARGO}" = "true" ] && [ -n "${ARGO_DOMAIN}" ] && [ -z "${MY_DOMAIN}" ]; then
    export MY_DOMAIN="${ARGO_DOMAIN}"
  fi

  if [ -e "${FILE_PATH}/system-panel" ]; then
    if [ -f /etc/alpine-release ]; then
      rc-service panel start
    else
      systemctl enable panel >/dev/null 2>&1
      systemctl start panel
    fi
    green "panel服务已成功启动"
  fi

  sleep 3

  if [ "${ENABLE_ARGO}" = "true" ]; then
      purple "\n面板管理地址: http://${ARGO_DOMAIN}  密码: ${PANEL_PASSWORD}"
  else
    if [ -n "${MY_DOMAIN}" ]; then
      purple "\n面板管理地址: http://${MY_DOMAIN}  密码: ${PANEL_PASSWORD}"
    else
      get_ip_country_code && sleep 3
      purple "\n面板管理地址: http://${MYIP}:${PORT}  密码: ${PANEL_PASSWORD}"
    fi
  fi

  if [ -f /etc/alpine-release ]; then
    purple "查看日志: rc-service panel status / rc-service panel tail"
  else
    purple "查看日志: systemctl status panel; journalctl -u panel -f"
  fi
}

# install_panel
install_panel() {
  stop_services
  check_and_install_tools
  createfolder
  cleanup_files
  initialize_downloads
  create_services
  run_processes
}

# remove_panel
remove_panel() {
  stop_services
  cleanup_files
  safe_rm "${FILE_PATH}"
  green "system-panel已卸载"
}

# 更新二进制文件
update_binary() {
  purple "开始更新 system-panel 二进制..."
  local panel_url
  panel_url=$(get_download_url "https://github.com/kahunama/myfile/releases/download/main/system-panel-arm" "https://github.com/kahunama/myfile/releases/download/main/system-panel")

  # 停止服务
  if [ -f /etc/alpine-release ]; then
    rc-service panel stop
  else
    systemctl stop panel
  fi

  # 备份旧文件
  if [ -f "${FILE_PATH}/system-panel" ]; then
    cp "${FILE_PATH}/system-panel" "${FILE_PATH}/system-panel.backup"
    purple "已备份旧版本到: ${FILE_PATH}/system-panel.backup"
  fi

  # 下载新文件
  local temp_file="/tmp/system-panel.download"
  if command -v curl &> /dev/null; then
    curl -L --progress-bar -o "$temp_file" "$panel_url"
  elif command -v wget &> /dev/null; then
    wget -q --show-progress -O "$temp_file" "$panel_url"
  fi

  if [ $? -eq 0 ] && [ -s "$temp_file" ]; then
    mv "$temp_file" "${FILE_PATH}/system-panel"
    chmod +x "${FILE_PATH}/system-panel"
    green "更新成功"

    # 重启服务
    if [ -f /etc/alpine-release ]; then
      rc-service panel start
    else
      systemctl start panel
    fi
    green "面板服务已重启"
  else
    red "下载失败"
    rm -f "$temp_file"
    if [ -f "${FILE_PATH}/system-panel.backup" ]; then
      mv "${FILE_PATH}/system-panel.backup" "${FILE_PATH}/system-panel"
      yellow "已恢复旧版本"
    fi
    return 1
  fi
}

# 重启面板服务
restart_service() {
  purple "正在重启面板服务..."
  if [ -f /etc/alpine-release ]; then
    rc-service panel restart
  else
    systemctl restart panel
  fi
  green "面板服务已重启"
  show_service_status
}

# 查看服务状态
show_service_status() {
  echo ""
  echo "服务状态:"
  if [ -f /etc/alpine-release ]; then
    rc-service panel status
    if [ "${ENABLE_ARGO}" = "true" ]; then
      rc-service cloudflared status
    fi
  else
    systemctl status panel --no-pager -l
    if [ "${ENABLE_ARGO}" = "true" ]; then
      systemctl status cloudflared --no-pager -l
    fi
  fi
}

# 查看日志
show_panel_logs() {
  if [ -f /etc/alpine-release ]; then
    rc-service panel tail
  else
    journalctl -u panel -f
  fi
}

menu(){
echo "========================================="
echo "   System Panel 服务安装脚本"
echo "========================================="
echo "  1) 安装面板"
echo "  2) 卸载面板"
echo "  3) 更新二进制文件"
echo "  4) 重启面板服务"
echo "  5) 查看服务状态"
echo "  6) 查看日志"
echo "  0) 退出"
echo "========================================="
read -p "请选择 [0-6]: " num
case "$num" in
    1)
    install_panel
    ;;
    2)
    remove_panel
    ;;
    3)
    update_binary
    ;;
    4)
    restart_service
    ;;
    5)
    show_service_status
    ;;
    6)
    show_panel_logs
    ;;
    0)
    exit 0
    ;;
    *)
    clear
    echo -e "${Error}:请输入正确数字 [0-6]"
    sleep 5
    menu
    ;;
esac
}

main() {
  case "$1" in
    install)
      install_panel
      ;;
    uninstall)
      remove_panel
      ;;
    update)
      update_binary
      ;;
    restart)
      restart_service
      ;;
    status)
      show_service_status
      ;;
    logs)
      show_panel_logs
      ;;
    *)
      menu
      ;;
  esac
}

# 运行主程序
main "$@"
