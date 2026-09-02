#!/bin/bash

# 定义颜色函数
red() { echo -e "\e[1;91m$1\e[0m"; }
green() { echo -e "\e[1;32m$1\e[0m"; }
yellow() { echo -e "\e[1;33m$1\e[0m"; }
purple() { echo -e "\e[1;35m$1\e[0m"; }
# reading() { read -p "$(red "$1")" "$2"; }

export FILE_PATH=${FILE_PATH:-'/root/singbox'}
export CFPORT=${CFPORT:-'8443'} # https 443 2053 2083 2087 2096 8443  # http 80 8080 8880 2052 2082 2086 2095
export CF_IP=${CF_IP:-'ip.sb'}

# 其他参数
export ENABLE_ARGO=${ENABLE_ARGO:-'true'} # 默认使用argo，为 false 时禁用argo
export SERVER_IP="" # 在装有warp的vps上要自己手动设置真实ip，如hax。没有不填，留空

# 设置订阅上传地址和节点名称
export SUB_URL=${SUB_URL:-'https://jy.tcgd.nyc.mn/upload-aac316c5-a112-40e1-9319-10d25e4e8d44'} # 为空不上传
export SUB_NAME=${SUB_NAME:-'neoheberg'} # 节点名称
export MYIP_URL=${MYIP_URL:-''} # 自建ip api 一般不填

# 隧道或直连用,vless或vmess协议二选一
export VMESS_WSPATH=${VMESS_WSPATH:-''} # startvm
export VLESS_WSPATH=${VLESS_WSPATH:-'startvl'} # startvl
export SNI=${SNI:-'www.zara.com'} # reality协议用
export TUICPASS=${TUICPASS:-''} # tuic密码，不设随机

# 不是natvps如hax cf域名节点直连需caddy反代 cf中SSL/TLS加密为完全     natvps可设为no，cf中SSL/TLS加密为灵活，并rule到natpvs开放端口也就是V_PORT端口。直接使用cf域名节点直连
export USECADDY=${USECADDY:-'no'} # yes or no，只在ENABLE_ARGO为true时有效
export MY_MAIL=${MY_MAIL:-''}   # cf域名节点直连时用，填入自己的邮箱,caddy用于自动申请域名证书，不用留空
export MY_DOMAIN=${MY_DOMAIN:-''}  # cf域名节点
export PORT=${PORT:-''}   # natvps使用caddy时订阅端口，不填不使用

# export V_PORT=$(shuf -i 20001-65535 -n 1) # 直辖时随机端口示例
# 自己设置端口。留空或删除时不使用，不上传此协议
export V_PORT=${V_PORT:-'8080'} # V_PORT为空时不使用vless或vmess。当为8080时使用argo隧道代理vless,vmess，直连时为NATVPS开放端口，非NATVPS可参考V_PORT示例使用随机端口。
export HY2_PORT=$(shuf -i 20001-65535 -n 1)
export TUIC_PORT=${TUIC_PORT:-''}
export REAL_PORT=${REAL_PORT:-''}
export ANYTLS_PORT=${ANYTLS_PORT:-''}

# socks，不用可留空或删除
export SOCKS_PORT=${SOCKS_PORT:-''}
export SOCKS_USER=${SOCKS_USER:-''}
export SOCKS_PASS=${SOCKS_PASS:-''}

# 哪吒参数，NEZHA_SERVER和NEZHA_KEY不填不安装哪吒
export UUID=${UUID:-'0c1a637c-4d13-4b0f-96ef-41ac35b748f1'}  # 这个要填，节点uuid及哪吒V1uuid共用
export NEZHA_VERSION=${NEZHA_VERSION:-'V1'} # V0 OR V1
export NEZHA_SERVER=${NEZHA_SERVER:-'my.tcguangda.eu.org'}
export NEZHA_KEY=${NEZHA_KEY:-'ilovehesufeng520'}
export NEZHA_PORT=${NEZHA_PORT:-'443'}

# argo参数
export ARGO_DOMAIN=${ARGO_DOMAIN:-''}
export ARGO_AUTH=${ARGO_AUTH:-''}

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
      rc-service argo stop
      rc-update del argo default
      pkill -TERM -f "${FILE_PATH}/argo" >/dev/null 2>&1 || true
      sleep 1
      pkill -KILL -f "${FILE_PATH}/argo" >/dev/null 2>&1 || true
      rc-service uploads stop
      rc-update del uploads default
      pkill -TERM -f "${FILE_PATH}/up_s.sh" >/dev/null 2>&1 || true
      sleep 1
      pkill -KILL -f "${FILE_PATH}/up_s.sh" >/dev/null 2>&1 || true
    fi
    rc-service singbox stop
    rc-update del singbox default
    pkill -TERM -f "${FILE_PATH}/singbox" >/dev/null 2>&1 || true
    sleep 1
    pkill -KILL -f "${FILE_PATH}/singbox" >/dev/null 2>&1 || true
    if [ -n "${NEZHA_SERVER}" ] && [ -n "${NEZHA_KEY}" ]; then
      rc-service nezha-agent stop
      rc-update del nezha-agent
      pkill -TERM -f "${FILE_PATH}/nezha-agent" >/dev/null 2>&1 || true
      sleep 1
      pkill -KILL -f "${FILE_PATH}/nezha-agent" >/dev/null 2>&1 || true
    fi
  else
    if [ "${ENABLE_ARGO}" = "true" ]; then
      systemctl disable argo
      systemctl stop argo
      systemctl disable uploads
      systemctl stop uploads
    fi
    systemctl disable singbox
    systemctl stop singbox
    if [ -n "${NEZHA_SERVER}" ] && [ -n "${NEZHA_KEY}" ]; then
      systemctl disable nezha-agent
      systemctl stop nezha-agent
    fi
  fi
}

# 清理文件
cleanup_files() {
  safe_rm "${FILE_PATH}/sconf"
  safe_rm "${FILE_PATH}"/*.log "${FILE_PATH}/list.txt" "${FILE_PATH}/config.yml" \
          "${FILE_PATH}/tunnel"*.* "${FILE_PATH}/cert.pem" "${FILE_PATH}/private.key" \
          "${FILE_PATH}/cache.db"
  safe_rm /var/www/sub.txt
  if [ -f /etc/alpine-release ]; then
    safe_rm /etc/init.d/singbox
    if [ "${ENABLE_ARGO}" = "true" ]; then
      safe_rm /etc/init.d/argo /etc/init.d/uploads "${FILE_PATH}"/*.sh /root/.env
    fi
    if [ -n "${NEZHA_SERVER}" ] && [ -n "${NEZHA_KEY}" ]; then
      safe_rm /etc/init.d/nezha-agent
    fi
  else
    safe_rm /etc/systemd/system/singbox.service
    if [ "${ENABLE_ARGO}" = "true" ]; then
      safe_rm /etc/systemd/system/argo.service /etc/systemd/system/uploads.service \
              "${FILE_PATH}"/*.sh /root/.env
    fi
    if [ -n "${NEZHA_SERVER}" ] && [ -n "${NEZHA_KEY}" ]; then
      safe_rm /etc/systemd/system/nezha-agent.service
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
    if [ "$action" = "install" ]; then
      if command -v "$package" &>/dev/null; then
        green "${package} already installed"
        continue  # continue命令的作用是跳过后面的代码，并且在循环迭代中移动到下一个出现点。
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
    elif [ "$action" = "uninstall" ]; then
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

# 处理ubuntu系统中没有caddy源的问题
install_caddy () {
  if [ -f /etc/os-release ] && (grep -q "Ubuntu" /etc/os-release || grep -q "Debian GNU/Linux 11" /etc/os-release); then
    purple "安装caddy中...\n"
    apt install -y debian-keyring debian-archive-keyring apt-transport-https
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | tee /etc/apt/trusted.gpg.d/caddy-stable.asc
    curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list
    rm /etc/apt/trusted.gpg.d/caddy-stable.asc /usr/share/keyrings/caddy-archive-keyring.gpg 2>/dev/null
    curl -fsSL https://dl.cloudsmith.io/public/caddy/stable/gpg.key | gpg --dearmor -o /usr/share/keyrings/caddy-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/caddy-archive-keyring.gpg] https://dl.cloudsmith.io/public/caddy/stable/deb/debian any-version main" | tee /etc/apt/sources.list.d/caddy-stable.list
    DEBIAN_FRONTEND=noninteractive apt update -y && manage_packages install caddy
  else
    manage_packages install caddy
  fi
}

# 检查并安装必要的工具
check_and_install_tools() {
  manage_packages install curl grep openssl coreutils
  if [ "$ENABLE_ARGO" = "false" ]; then
    # reading "是否使用caddy反代vless或vmess直连(yes or no): " USECADDY
    case "$USECADDY" in
      "yes" )
        if command -v caddy >/dev/null 2>&1; then
          green "caddy already installed"
        else
          install_caddy
        fi
        ;;
      "no" )
        green "不使用caddy反代vless或vmess直连，安装继续！"
        ;;
    esac
  fi
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
  if [ -n "${NEZHA_SERVER}" ] && [ -n "${NEZHA_KEY}" ]; then
    case "$NEZHA_VERSION" in
      "V0" )
        download_program "${FILE_PATH}/nezha-agent" "https://github.com/kahunama/myfile/releases/download/main/nezha-agent_arm" "https://github.com/kahunama/myfile/releases/download/main/nezha-agent"
        ;;
      "V1" )
        download_program "${FILE_PATH}/nezha-agent" "https://github.com/mytcgd/myfiles/releases/download/main/nezha-agentv1_arm" "https://github.com/mytcgd/myfiles/releases/download/main/nezha-agentv1"
        ;;
    esac
  fi

  download_program "${FILE_PATH}/singbox" "https://github.com/mytcgd/myfiles/releases/download/main/sing-box_arm" "https://github.com/mytcgd/myfiles/releases/download/main/sing-box"

  case "$ENABLE_ARGO" in
    "true" )
      download_program "${FILE_PATH}/argo" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
      if [ -n "${SUB_URL}" ] && [ -z "${ARGO_DOMAIN}" ] && [ -z "${ARGO_AUTH}" ]; then
        download_program "${FILE_PATH}/up_s.sh" "https://raw.githubusercontent.com/mytcgd/myfiles/refs/heads/main/my/up/up_s.sh" "https://raw.githubusercontent.com/mytcgd/myfiles/refs/heads/main/my/up/up_s.sh"
      fi
      ;;
    "false" )
      green "\n本次安装不使用argo隧道!"
      ;;
  esac
}

# 生成 singbox inbound 配置
generate_config() {
  mkdir -p "${FILE_PATH}/sconf"
  if [ "$HY2_PORT" ] || [ "$TUIC_PORT" ] || [ "$ANYTLS_PORT" ]; then  # 求或
    openssl ecparam -genkey -name prime256v1 -out "${FILE_PATH}/private.key"
    openssl req -new -x509 -days 3650 -key "${FILE_PATH}/private.key" -out "${FILE_PATH}/cert.pem" -subj "/CN=bing.com"
  fi

  if [ -n "${TUIC_PORT}" ] && [ -z "${TUICPASS}" ]; then
    export TUICPASS=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 24)
  fi

  if [ -n "${REAL_PORT}" ]; then
    output=$(${FILE_PATH}/singbox generate reality-keypair)
    private_key=$(echo "${output}" | grep -E 'PrivateKey:' | cut -d: -f2- | sed 's/^\s*//' )
    export public_key=$(echo "${output}" | grep -E 'PublicKey:' | cut -d: -f2- | sed 's/^\s*//' )
  fi

  cat > ${FILE_PATH}/sconf/inbound.json << EOF
{
    "log": {
        "disabled": false,
        "level": "info",
        "timestamp": true
    },
    "dns": {
        "servers": [
            {
                "address": "https://8.8.8.8/dns-query"
            }
        ]
    }
}
EOF

  if [ -n "${V_PORT}" ]; then
    if [ -n "${VMESS_WSPATH}" ] && [ -z "${VLESS_WSPATH}" ]; then
      cat > ${FILE_PATH}/sconf/inbound_w.json << EOF
{
    "inbounds": [
        {
            "type": "vmess",
            "tag": "vmess-in",
            "listen": "::",
            "listen_port": ${V_PORT},
            "sniff": true,
            "sniff_override_destination": true,
            "users": [
                {
                    "uuid": "${UUID}"
                }
            ],
            "transport": {
                "type": "ws",
                "path": "/${VMESS_WSPATH}",
                "early_data_header_name": "Sec-WebSocket-Protocol"
            }
        }
    ]
}
EOF
    elif [ -n "${VLESS_WSPATH}" ] && [ -z "${VMESS_WSPATH}" ]; then
      cat > ${FILE_PATH}/sconf/inbound_w.json << EOF
{
    "inbounds": [
        {
            "type": "vless",
            "tag": "vless-in",
            "listen": "::",
            "listen_port": ${V_PORT},
            "sniff": true,
            "sniff_override_destination": true,
            "users": [
                {
                    "uuid": "${UUID}",
                    "flow": ""
                }
            ],
            "transport": {
                "type": "ws",
                "path": "/${VLESS_WSPATH}",
                "early_data_header_name": "Sec-WebSocket-Protocol"
            }
        }
    ]
}
EOF
    fi
  fi

  if [ -n "${HY2_PORT}" ]; then
    cat > ${FILE_PATH}/sconf/inbound_h.json << EOF
{
    "inbounds": [
        {
            "tag": "hysteria-in",
            "type": "hysteria2",
            "listen":"::",
            "listen_port": ${HY2_PORT},
            "users": [
                {
                    "password": "${UUID}"
                }
            ],
            "masquerade": "https://bing.com",
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "${FILE_PATH}/cert.pem",
                "key_path": "${FILE_PATH}/private.key"
            }
        }
    ]
}
EOF
  fi

  if [ -n "${TUIC_PORT}" ]; then
    cat > ${FILE_PATH}/sconf/inbound_t.json << EOF
{
    "inbounds": [
        {
            "tag": "tuic-in",
            "type": "tuic",
            "listen":"::",
            "listen_port": ${TUIC_PORT},
            "users": [
                {
                    "uuid": "${UUID}",
                    "password": "${TUICPASS}"
                }
            ],
            "congestion_control": "bbr",
            "tls": {
                "enabled": true,
                "alpn": [
                    "h3"
                ],
                "certificate_path": "${FILE_PATH}/cert.pem",
                "key_path": "${FILE_PATH}/private.key"
            }
        }
    ]
}
EOF
  fi

  if [ -n "${REAL_PORT}" ]; then
    cat > ${FILE_PATH}/sconf/inbound_r.json << EOF
{
    "inbounds": [
        {
            "tag": "vless-reality-in",
            "type": "vless",
            "listen": "::",
            "listen_port": ${REAL_PORT},
            "users": [
                {
                    "uuid": "${UUID}",
                    "flow": "xtls-rprx-vision"
                }
            ],
            "tls": {
                "enabled": true,
                "server_name": "${SNI}",
                "reality": {
                    "enabled": true,
                    "handshake": {
                        "server": "${SNI}",
                        "server_port": 443
                    },
                    "private_key": "${private_key}",
                    "short_id": [
                        ""
                    ]
                }
            }
        }
    ]
}
EOF
  fi

  if [ -n "${ANYTLS_PORT}" ]; then
    cat > ${FILE_PATH}/sconf/inbound_a.json << EOF
{
    "inbounds": [
        {
            "tag": "anytls-in",
            "type": "anytls",
            "listen": "::",
            "listen_port": ${ANYTLS_PORT},
            "users": [
                {
                    "password": "${UUID}"
                }
            ],
            "padding_scheme": [],
            "tls": {
                "enabled":true,
                "certificate_path": "${FILE_PATH}/cert.pem",
                "key_path": "${FILE_PATH}/private.key"
            }
        }
    ]
}
EOF
  fi

  if [ -n "${SOCKS_PORT}" ] && [ -n "${SOCKS_USER}" ] && [ -n "${SOCKS_PASS}" ]; then
    cat > ${FILE_PATH}/sconf/inbound_s.json << EOF
{
    "inbounds": [
        {
            "tag": "socks-in",
            "type": "socks",
            "listen": "::",
            "listen_port": $SOCKS_PORT,
            "users": [
                {
                    "username": "$SOCKS_USER",
                    "password": "$SOCKS_PASS"
                }
            ]
        }
    ]
}
EOF
  fi

  cat > ${FILE_PATH}/sconf/outbound.json << EOF
{
    "outbounds": [
        {
            "tag": "direct",
            "type": "direct"
        }
    ],
    "experimental": {
        "cache_file": {
            "enabled": true,
            "path": "${FILE_PATH}/cache.db"
        }
    }
}
EOF
}

# 节点及程序环境配置
my_config() {
  generate_config

  if [ "$ENABLE_ARGO" = "true" ] && [ -e "${FILE_PATH}/argo" ]; then
    argo_type() {
      if [ -z "$ARGO_AUTH" ] && [ -z "$ARGO_DOMAIN" ]; then
        purple "ARGO_AUTH和ARGO_DOMAIN为空，使用临时隧道"
        return
      fi

      if [ -n "$(echo "$ARGO_AUTH" | grep TunnelSecret)" ]; then
        echo $ARGO_AUTH > ${FILE_PATH}/tunnel.json
        cat > ${FILE_PATH}/tunnel.yml << EOF
tunnel=$(echo "$ARGO_AUTH" | cut -d\" -f12)
credentials-file: ${FILE_PATH}/tunnel.json
protocol: http2

ingress:
  - hostname: $ARGO_DOMAIN
    service: http://localhost:${V_PORT}
    originRequest:
      noTLSVerify: true
  - service: http_status:404
EOF
      else
        echo "ARGO_AUTH Mismatch TunnelSecret"
      fi
    }
    argo_type

    args() {
      if [ -n "$(echo "$ARGO_AUTH" | grep '^[A-Z0-9a-z=]\{120,250\}$')" ]; then
        args="tunnel --edge-ip-version auto --protocol http2 --no-autoupdate run --token ${ARGO_AUTH}"
      elif [ -n "$(echo "$ARGO_AUTH" | grep TunnelSecret)" ]; then
        args="tunnel --edge-ip-version auto --config ${FILE_PATH}/tunnel.yml run"
      else
        args="tunnel --edge-ip-version auto --protocol http2 --no-autoupdate --logfile ${FILE_PATH}/argo.log --url http://localhost:$V_PORT"
      fi
    }
    args

    ARGO_RUNS="${FILE_PATH}/argo $args"
    if [ -f /etc/alpine-release ]; then
      cat > /etc/init.d/argo << ABC
#!/sbin/openrc-run

supervisor=supervise-daemon
name="argo"
description="Cloudflare Tunnel"
command=${FILE_PATH}/argo
command_args="${args}"
# 新进程启动前，旧进程死透
start_pre() {
    pkill -9 -f "${FILE_PATH}/argo" || true
    sleep 1
}
# 自动重启设置
respawn_delay=5
respawn_max=0
# 静默输出
supervise_daemon_args="--stdout /dev/null --stderr /dev/null"
ABC
      chmod +x /etc/init.d/argo
      rc-update add argo default
    else
      cat > /etc/systemd/system/argo.service << ABC
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
ABC
    fi
  fi

  if [ -e "${FILE_PATH}/singbox" ]; then
    singbox_RUNS="${FILE_PATH}/singbox run -C ${FILE_PATH}/sconf"
    if [ -f /etc/alpine-release ]; then
      cat > /etc/init.d/singbox << DEF
#!/sbin/openrc-run

supervisor=supervise-daemon
name="singbox"
description="sing-box Service"
command="${FILE_PATH}/singbox"
command_args="run -C ${FILE_PATH}/sconf"
start_pre() {
    pkill -9 -f "${FILE_PATH}/singbox" || true
    sleep 1
}
respawn_delay=5
respawn_max=0
supervise_daemon_args="--stdout /dev/null --stderr /dev/null"
DEF
      chmod +x /etc/init.d/singbox
      rc-update add singbox default
    else
      cat > /etc/systemd/system/singbox.service << DEF
[Unit]
Description=sing-box Service
Documentation=https://sing-box.sagernet.org
After=network.target nss-lookup.target
Wants=network-online.target

[Service]
Type=simple
NoNewPrivileges=yes
ExecStart=$singbox_RUNS
Restart=on-failure
RestartSec=5s
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
DEF
    fi
  fi

  if [ -n "${NEZHA_SERVER}" ] && [ -n "${NEZHA_KEY}" ] && [ -e "${FILE_PATH}/nezha-agent" ]; then
    tlsPorts=("443" "8443" "2096" "2087" "2083" "2053")
    case "$NEZHA_VERSION" in
      "V0" )
        if [[ " ${tlsPorts[@]} " =~ " ${NEZHA_PORT} " ]]; then
          NEZHA_TLS="--tls"
        else
          NEZHA_TLS=""
        fi
        NEZHA_RUNS="${FILE_PATH}/nezha-agent -s ${NEZHA_SERVER}:${NEZHA_PORT} -p ${NEZHA_KEY} ${NEZHA_TLS}"
        ;;
      "V1" )
        if [[ " ${tlsPorts[@]} " =~ " ${NEZHA_PORT} " ]]; then
          NEZHA_TLS="true"
        else
          NEZHA_TLS="false"
        fi
        cat > ${FILE_PATH}/config.yml << EOF
client_secret: $NEZHA_KEY
debug: false
disable_auto_update: false
disable_command_execute: false
disable_force_update: false
disable_nat: false
disable_send_query: false
gpu: false
insecure_tls: false
ip_report_period: 1800
report_delay: 4
server: $NEZHA_SERVER:$NEZHA_PORT
skip_connection_count: false
skip_procs_count: false
temperature: false
tls: $NEZHA_TLS
use_gitee_to_upgrade: false
use_ipv6_country_code: false
uuid: $UUID
EOF
        NEZHA_RUNS="${FILE_PATH}/nezha-agent -c ${FILE_PATH}/config.yml"
        ;;
    esac

    if [ -f /etc/alpine-release ]; then
      cat > /etc/init.d/nezha-agent << GHI
#!/sbin/openrc-run

supervisor=supervise-daemon
name="nezha-agent"
description="nezha-agent"
command=${FILE_PATH}/nezha-agent
command_args="${NEZHA_RUNS#*nezha-agent }"
start_pre() {
    pkill -9 -f "${FILE_PATH}/nezha-agent" || true
    sleep 1
}
respawn_delay=5
respawn_max=0
supervise_daemon_args="--stdout /dev/null --stderr /dev/null"
GHI
      chmod +x /etc/init.d/nezha-agent
      rc-update add nezha-agent default
    else
      cat > /etc/systemd/system/nezha-agent.service << GHI
[Unit]
Description=nezha-agent
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=$NEZHA_RUNS
Restart=on-failure
RestartSec=5s
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
GHI
    fi
  fi

  if [ -n "$SUB_URL" ]; then
    if [ -n "$ARGO_DOMAIN" ] && [ -n "$ARGO_AUTH" ]; then
      purple "使用固定隧道，不使用上传服务，一次上传！"
    elif [ -z "$ARGO_DOMAIN" ] && [ -z "$ARGO_AUTH" ] && [ -e ${FILE_PATH}/up_s.sh ]; then
      if [ -f /etc/alpine-release ]; then
        cat > /etc/init.d/uploads << JKL
#!/sbin/openrc-run

supervisor=supervise-daemon
name="uploads"
description="uploadsub"
command="/bin/sh"
command_args="-c '${FILE_PATH}/up_s.sh'"
start_pre() {
    ps -ef | grep "${FILE_PATH}/up_s.sh" | grep -v "supervise-daemon" | grep -v "grep" | awk '{print $2}' | xargs kill -9 >/dev/null 2>&1 || true
    sleep 1
}
respawn_delay=5
respawn_max=0
supervise_daemon_args="--stdout /dev/null --stderr /dev/null"
JKL
        chmod +x /etc/init.d/uploads
        rc-update add uploads default
      else
        cat > /etc/systemd/system/uploads.service << JKL
[Unit]
Description=uploads
After=network.target

[Service]
Type=simple
NoNewPrivileges=yes
TimeoutStartSec=0
ExecStart=${FILE_PATH}/up_s.sh
Restart=on-failure
RestartSec=5s
StandardOutput=null
StandardError=null

[Install]
WantedBy=multi-user.target
JKL
      fi
    fi
  fi
}

# caddy反代配置
add_caddy_conf() {
  [ -f /etc/caddy/Caddyfile ] && cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak
  safe_rm /etc/caddy/Caddyfile
  password=$(< /dev/urandom tr -dc 'A-Za-z0-9' | head -c 24)

  if [ -n "${VMESS_WSPATH}" ] && [ -z "${VLESS_WSPATH}" ]; then
     MYPROXY="${VMESS_WSPATH}"
  elif [ -n "${VLESS_WSPATH}" ] && [ -z "${VMESS_WSPATH}" ]; then
     MYPROXY="${VLESS_WSPATH}"
  fi

  if [ -n "${PORT}" ]; then
    cat > /etc/caddy/Caddyfile << EOF
$MY_DOMAIN {
    tls $MY_MAIL
    encode gzip

EOF
  else
    cat > /etc/caddy/Caddyfile << EOF
$MY_DOMAIN {
    # 非NAT_VPS如hax所需，默认监听的是443端口（HTTPS），并会自动重定向80端口
    root * /var/www
    file_server browse

    tls $MY_MAIL
    encode gzip

EOF
  fi

  cat >> /etc/caddy/Caddyfile << EOF
    @mywebsocket {
        path /${MYPROXY}
        header Connection *Upgrade*
        header Upgrade websocket
    }
    reverse_proxy @mywebsocket localhost:${V_PORT}
}
EOF

  if [ -n "${PORT}" ]; then
    cat >> /etc/caddy/Caddyfile << EOF

# NAT_VPS所用，非NAT_VPS如hax,可不设PORT变量值，设了也没事，就是多占用一个端口
:$PORT {
    handle /$password {
        root * /var/www
        try_files /sub.txt
        file_server browse
        header Content-Type "text/plain; charset=utf-8"
    }

    handle {
        respond "404 Not Found" 404
    }
}
EOF
  fi

  if /usr/bin/caddy validate --config /etc/caddy/Caddyfile > /dev/null 2>&1; then
    if [ -f /etc/alpine-release ]; then
      rc-service caddy restart
    else
      systemctl daemon-reload
      systemctl restart caddy
    fi
  else
    if [ -f /etc/alpine-release ]; then
      rc-service caddy restart > /dev/null 2>&1 || red "Caddy 配置文件验证失败!"
    else
      red "Caddy 配置文件验证失败!"
    fi
  fi
}

# 启动 caddy
start_caddy() {
  if command -v caddy &>/dev/null; then    # (&>/dev/null)表示 suppression of standard output and errors，即抑制标准输出和错误
    yellow "\n正在启动caddy服务"
    if [ -f /etc/alpine-release ]; then
        rc-service caddy start
    else
        systemctl enable caddy
        systemctl daemon-reload
        systemctl start caddy
    fi
    if [ $? -eq 0 ]; then
        green "caddy服务已成功启动\n"
    else
        red "caddy启动失败\n"
    fi
  else
    yellow "caddy尚未安装！\n"
  fi
}

# 放行指定端口（不再清空全部防火墙规则）
open_ports() {
  local ports=()
  [ -n "${V_PORT}" ]      && ports+=("${V_PORT}")
  [ -n "${HY2_PORT}" ]    && ports+=("${HY2_PORT}")
  [ -n "${TUIC_PORT}" ]   && ports+=("${TUIC_PORT}")
  [ -n "${REAL_PORT}" ]   && ports+=("${REAL_PORT}")
  [ -n "${ANYTLS_PORT}" ] && ports+=("${ANYTLS_PORT}")
  [ -n "${SOCKS_PORT}" ]  && ports+=("${SOCKS_PORT}")
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

# 保持进程运行
run_processes() {
  # 放行所需端口（不再清空防火墙）
  open_ports

  if [ "$ENABLE_ARGO" = "false" ] && [ "$USECADDY" = "yes" ]; then
    add_caddy_conf && sleep 3 && start_caddy
  fi

  if [ "$ENABLE_ARGO" = "true" ] && [ -e "${FILE_PATH}/argo" ]; then
    if [ -f /etc/alpine-release ]; then
      rc-service argo start
    else
      systemctl enable argo
      systemctl start argo
    fi
    green "argo服务已成功启动\n"
  fi

  sleep 5

  if [ -e "${FILE_PATH}/singbox" ]; then
    if [ -f /etc/alpine-release ]; then
      rc-service singbox start
    else
      systemctl enable singbox
      systemctl start singbox
    fi
    green "singbox服务已成功启动\n"
  fi

  sleep 3

  if [ -n "${NEZHA_SERVER}" ] && [ -n "${NEZHA_KEY}" ] && [ -e "${FILE_PATH}/nezha-agent" ]; then
    if [ -f /etc/alpine-release ]; then
      rc-service nezha-agent start
    else
      systemctl enable nezha-agent
      systemctl start nezha-agent
    fi
    green "nezha服务已成功启动\n"
  fi

  sleep 3

  build_urls && sleep 3

  if [ -n "$SUB_URL" ]; then
    if [ -s "${FILE_PATH}/argo.log" ]; then
      if [ -e ${FILE_PATH}/up_s.sh ]; then
        dynamic_variables
        if [ -f /etc/alpine-release ]; then
          rc-service uploads start
        else
          systemctl enable uploads
          systemctl start uploads
        fi
        green "upload服务已成功启动"
      fi
    else
      upload_subscription
    fi
  fi

  purple "\nvps节点链接如下：\n"
  cat ${FILE_PATH}/list.txt

  if [ -n "${SOCKS_PORT}" ] && [ -n "${SOCKS_USER}" ] && [ -n "${SOCKS_PASS}" ]; then
    purple "\nsocks5服务如下： 代理地址：$SERVER_IP  端口：$SOCKS_PORT  用户名：$SOCKS_USER  密码：$SOCKS_PASS\n"
    purple "tg中使用: https://t.me/socks?server=$SERVER_IP&port=$SOCKS_PORT&user=$SOCKS_USER&pass=$SOCKS_PASS\n"
  fi

  if [ "$ENABLE_ARGO" = "false" ]; then
    yellow "\n温馨提醒：如果是NAT机,singbox端口需使用可用端口范围内的端口,并且要做Origin Rules，否则协议不通\n"
    if [ "$USECADDY" = "yes" ]; then
      green "VPS节点用订阅链接(非NAT_VPS)：http://$MY_DOMAIN/sub.txt\n"
      green "NAT_VPS节点用订阅链接：http://$MYIP:$PORT/$password\n\n订阅链接适用于V2rayN\n"
    fi
  fi
}

# 声明一个辅助函数，用于调用 API 并解析结果
fetch_and_parse() {
    local url="$1"
    local json_key="$2" # "ip" for (ip.sb/Worker), "query" for ip-api.com

    IP_INFO=$(curl -s --connect-timeout 10 --max-time 15 "$url")

    # 检查是否成功获取到 IP 地址的键
    if echo "$IP_INFO" | grep -q "\"${json_key}\""; then
        if [[ "$json_key" = "ip" ]]; then
            # 针对 ip.sb 和 Worker API
            if [[ -z "$SERVER_IP" ]]; then
              SERVER_IP=$(echo "$IP_INFO" | sed -n 's/.*"ip": *"\([^"]*\).*/\1/p')
            fi
            ISP_NAME=$(echo "$IP_INFO" | sed -n 's/.*"isp": *"\([^"]*\).*/\1/p' | sed -e 's/[ ,\.]/_/g; s/__*/_/g; s/^_//; s/_$//')

            # 解析 Worker 或 ip.sb 的 'country_code'
            COUNTRY_CODE=$(echo "$IP_INFO" | sed -n 's/.*"country_code": *"\([^"]*\).*/\1/p')
        else
            # 针对 ip-api.com
            if [[ -z "$SERVER_IP" ]]; then
              SERVER_IP=$(echo "$IP_INFO" | sed -n 's/.*"query": *"\([^"]*\).*/\1/p')
            fi
            ISP_NAME=$(echo "$IP_INFO" | sed -n 's/.*"isp": *"\([^"]*\).*/\1/p' | sed -e 's/[ ,\.]/_/g; s/__*/_/g; s/^_//; s/_$//')
            COUNTRY_CODE=$(echo "$IP_INFO" | sed -n 's/.*"countryCode": *"\([^"]*\).*/\1/p')
        fi

        # 检查是否成功提取了所有关键信息
        if [[ -n "$SERVER_IP" && -n "$ISP_NAME" && -n "$COUNTRY_CODE" ]]; then
            export SERVER_IP
            export ISP="${COUNTRY_CODE}-${ISP_NAME}"
            return 0 # 成功
        fi
    fi
    return 1 # 失败
}

# 获取IP及国家代码
get_ip_country_code() {
    local API_STATUS=1

    # 1. 尝试 https://api.ip.sb/geoip
    if fetch_and_parse "https://api.ip.sb/geoip" "ip"; then
        API_STATUS=0

    # 2. 如果第一个也失败，尝试 http://ip-api.com/json
    elif fetch_and_parse "http://ip-api.com/json" "query"; then
        API_STATUS=0

    # 3. 如果第二个失败，尝试您的 Worker URL
    elif [[ -n "$MYIP_URL" ]] && fetch_and_parse "${MYIP_URL}" "ip"; then
        API_STATUS=0
    fi

    # 检查是否从任何 API 成功获取数据
    if [[ "$API_STATUS" -eq 0 ]]; then
        # 处理 IPv4 或 IPv6 格式
        if [[ ! "$SERVER_IP" =~ : ]]; then
            export MYIP="$SERVER_IP"
            purple "本机的ipv4地址是: $SERVER_IP"
        else
            # 对于 IPv6 地址，使用方括号包裹
            export MYIP="[$SERVER_IP]"
            purple "本机的ipv6地址是: $SERVER_IP"
        fi
        purple "本机的ISP: ${ISP}"
        return 0
    else
        # 所有 API 都失败了
        export MYIP="1.1.1.1"
        export ISP="UN"
        purple "本机的ip地址是: $MYIP"
        purple "本机的ISP: ${ISP}"
        return 1
    fi
}

# 构建URL
build_urls() {
  if [ -s "${FILE_PATH}/argo.log" ]; then
    export ARGO_DOMAIN=$(grep -o "info.*https://.*trycloudflare.com" < "${FILE_PATH}/argo.log" | sed "s@.*https://@@g" | tail -n 1)
    # export ARGO_DOMAIN=$(cat ${FILE_PATH}/argo.log | grep -o "https://.*trycloudflare.com" | tail -n 1 | sed 's/https:\/\///')
  fi
  if [ -n "${ARGO_DOMAIN}" ]; then
    purple "ARGO隧道域名: $ARGO_DOMAIN"
  fi

  cat > ${FILE_PATH}/list.txt << EOF
***************************************************

      IP : ${SERVER_IP}     Country： ${ISP}

***************************************************

EOF
  if [ -n "${V_PORT}" ]; then
    if [ -n "$MY_DOMAIN" ] && [ -z "${ARGO_DOMAIN}" ]; then
      export ARGO_DOMAIN="$MY_DOMAIN"
      purple "节点CDN域名: $ARGO_DOMAIN"
    fi
    if [ -n "${VMESS_WSPATH}" ] && [ -z "${VLESS_WSPATH}" ]; then
      VMESS="{ \"v\": \"2\", \"ps\": \"${ISP}-${SUB_NAME}\", \"add\": \"${CF_IP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/${VMESS_WSPATH}?ed=2560\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"chrome\"}"

      vmess_url="vmess://$(echo "$VMESS" | base64 | tr -d '\n')"
      UPLOAD_DATA="$vmess_url"
    elif [ -n "${VLESS_WSPATH}" ] && [ -z "${VMESS_WSPATH}" ]; then
      UPLOAD_DATA="vless://${UUID}@${CF_IP}:${CFPORT}?host=${ARGO_DOMAIN}&path=%2F${VLESS_WSPATH}%3Fed%3D2560&type=ws&encryption=none&security=tls&sni=${ARGO_DOMAIN}#${ISP}-${SUB_NAME}"
    fi
    if [ -n "${UPLOAD_DATA}" ]; then
      echo "${UPLOAD_DATA}" >> ${FILE_PATH}/list.txt
    fi
  fi

  if [ -n "$HY2_PORT" ]; then
    export hysteria_url="hysteria2://${UUID}@${MYIP}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#${ISP}-${SUB_NAME}"
    UPLOAD_DATA="$UPLOAD_DATA\n$hysteria_url"
    echo "${hysteria_url}" >> ${FILE_PATH}/list.txt
  fi
  if [ -n "$TUIC_PORT" ]; then
    tuic_url="tuic://${UUID}:${TUICPASS}@${MYIP}:${TUIC_PORT}?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allow_insecure=1#${ISP}-${SUB_NAME}"
    UPLOAD_DATA="$UPLOAD_DATA\n$tuic_url"
    echo "${tuic_url}" >> ${FILE_PATH}/list.txt
  fi
  if [ -n "$REAL_PORT" ]; then
    export reality_url="vless://${UUID}@${MYIP}:${REAL_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${public_key}&type=tcp&headerType=none#${ISP}-${SUB_NAME}-realitytcp"
    UPLOAD_DATA="$UPLOAD_DATA\n$reality_url"
    echo "${reality_url}" >> ${FILE_PATH}/list.txt
  fi
  if [ -n "$ANYTLS_PORT" ]; then
    export anytls_url="anytls://${UUID}@${MYIP}:${ANYTLS_PORT}?insecure=1&udp=1#${ISP}-${SUB_NAME}"
    UPLOAD_DATA="$UPLOAD_DATA\n$anytls_url"
    echo "${anytls_url}" >> ${FILE_PATH}/list.txt
  fi
  if [ -n "${SOCKS_PORT}" ]; then
    BASE64_CREDENTIALS=$(echo -n "${SOCKS_USER}:${SOCKS_PASS}" | base64)
    export socks5_url="socks://${BASE64_CREDENTIALS}@${MYIP}:${SOCKS_PORT}#${ISP}-${SUB_NAME}"
    UPLOAD_DATA="${UPLOAD_DATA}\n${socks5_url}"
    echo "${socks5_url}" >> ${FILE_PATH}/list.txt
  fi
  export UPLOAD_DATA

  if [ "$ENABLE_ARGO" = "false" ] && [ "$USECADDY" = "yes" ]; then
    [ ! -d "/var/www" ] && mkdir -p /var/www
    printf '%b' "${UPLOAD_DATA}" > ${FILE_PATH}/tmp.txt
    if [ -n "${PORT}" ]; then
      base64 ${FILE_PATH}/tmp.txt | tr -d '\n' > /var/www/sub.txt
    fi
    safe_rm "${FILE_PATH}/tmp.txt"
  fi

  cat >> ${FILE_PATH}/list.txt << EOF

***************************************************
EOF
}

# 传递变量
dynamic_variables() {
  local VAR_STORAGE="/root/.env"
  cat > "$VAR_STORAGE" << EOF
#!/bin/bash
VAR_NAMES=( UUID V_PORT HY2_PORT TUIC_PORT REAL_PORT SOCKS_PORT ANYTLS_PORT VMESS_WSPATH VLESS_WSPATH ARGO_DOMAIN FILE_PATH CF_IP CFPORT ISP SUB_NAME SUB_URL hysteria_url tuic_url reality_url socks5_url anytls_url )
UUID='${UUID}'
V_PORT='${V_PORT}'
HY2_PORT='${HY2_PORT}'
TUIC_PORT='${TUIC_PORT}'
REAL_PORT='${REAL_PORT}'
SOCKS_PORT='${SOCKS_PORT}'
ANYTLS_PORT='${ANYTLS_PORT}'
VMESS_WSPATH='${VMESS_WSPATH}'
VLESS_WSPATH='${VLESS_WSPATH}'
ARGO_DOMAIN='${ARGO_DOMAIN}'
FILE_PATH='${FILE_PATH}'
CF_IP='${CF_IP}'
CFPORT='${CFPORT}'
ISP='${ISP}'
SUB_NAME='${SUB_NAME}'
SUB_URL='${SUB_URL}'
hysteria_url='${hysteria_url}'
tuic_url='${tuic_url}'
reality_url='${reality_url}'
socks5_url='${socks5_url}'
anytls_url='${anytls_url}'
EOF
}

# upload
upload_subscription() {
  local response
  if command -v curl &> /dev/null; then
    response=$(curl -s --connect-timeout 10 --max-time 30 -X POST -H "Content-Type: application/json" -d "{\"URL_NAME\":\"$SUB_NAME\",\"URL\":\"$UPLOAD_DATA\"}" "$SUB_URL" 2>&1)
  elif command -v wget &> /dev/null; then
    response=$(wget -qO- --timeout=30 --post-data="{\"URL_NAME\":\"$SUB_NAME\",\"URL\":\"$UPLOAD_DATA\"}" --header="Content-Type: application/json" "$SUB_URL" 2>&1)
  else
    red "无 curl/wget 可用，上传失败"
    return 1
  fi
  # 检查上传结果
  if [ $? -eq 0 ] && [ -n "$response" ]; then
    green "upload成功上传"
    return 0
  else
    red "upload上传失败: ${response}"
    return 1
  fi
}

# install_singbox
install_singbox() {
  stop_services
  check_and_install_tools
  createfolder
  cleanup_files
  initialize_downloads
  get_ip_country_code
  my_config
  run_processes
}

# remove_singbox
remove_singbox() {
  stop_services
  # manage_packages uninstall curl grep openssl coreutils
  if [ "$USECADDY" = "yes" ]; then
    manage_packages uninstall caddy
    safe_rm /etc/caddy
  fi
  cleanup_files
  safe_rm "${FILE_PATH}"
}

menu(){
echo "1、安装singbox节点"
echo " "
echo "2、御载singbox节点"
echo " "
echo "0、退出脚本"
echo " "
read -p " 请输入数字 [0-2]: " num
case "$num" in
    1)
    install_singbox
    ;;
    2)
    remove_singbox
    ;;
    0)
    exit 1
    ;;
    *)
    clear
    echo -e "${Error}:请输入正确数字 [1-2]"
    sleep 5
    menu
    ;;
esac
}
menu
