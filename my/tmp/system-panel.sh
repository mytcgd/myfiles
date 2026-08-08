#!/bin/bash

# ==================== 优雅退出：Ctrl+C 时清理所有子进程 ====================
_CLEANUP_DONE=false
cleanup() {
    $_CLEANUP_DONE && exit 0
    _CLEANUP_DONE=true
    echo ""
    echo "正在停止所有服务..."
    # 杀掉当前 shell 的所有直接子进程
    local child_pids=$(pgrep -P $$ 2>/dev/null)
    [ -n "$child_pids" ] && kill $child_pids 2>/dev/null
    # 只杀 cloudflared（用 -x 精确匹配进程名，避免误杀自身）
    pkill -x "cloudflared" 2>/dev/null
    # 等待子进程结束
    sleep 1
    echo "所有服务已停止"
    exit 0
}
trap cleanup SIGINT SIGTERM SIGHUP

export FILE_PATH=${FILE_PATH:-'./.tmp'}
export ENABLE_ARGO=${ENABLE_ARGO:-'true'}  # true or false true为开启argo。
export KEEPALIVE=${KEEPALIVE:-'true'}
export PORT=${PORT:-'8080'}
export PANEL_PASSWORD=${PANEL_PASSWORD:-'123456'}
export ARGO_DOMAIN=${ARGO_DOMAIN:-''}
export ARGO_AUTH=${ARGO_AUTH:-''}

if [ ! -d "$FILE_PATH" ]; then
  mkdir -p "$FILE_PATH"
fi

# Download Dependency Files
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

initialize_downloads() {
  if argo_enabled; then
    download_program "${FILE_PATH}/cloudflared" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64" "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64"
  fi

  download_program "${FILE_PATH}/system-panel" "https://github.com/kahunama/myfile/releases/download/main/system-panel-arm" "https://github.com/kahunama/myfile/releases/download/main/system-panel"
}

# run
run_panel() {
  ${FILE_PATH}/system-panel >/dev/null 2>&1 &
}

run_cloudflared() {
  if [ -n "${ARGO_AUTH}" ]; then
    ${FILE_PATH}/cloudflared tunnel --edge-ip-version auto --no-autoupdate --protocol http2 run --token ${ARGO_AUTH} >/dev/null 2>&1 &
  else
    ${FILE_PATH}/cloudflared tunnel --edge-ip-version auto --no-autoupdate --protocol http2 --logfile ${FILE_PATH}/argo.log --url http://localhost:${PORT} >/dev/null 2>&1 &
  fi
}

Detect_process() {
  local process_name="$1"
  local pids=""
  if command -v pidof &> /dev/null; then
    pids=$(pidof "$process_name" 2>/dev/null)
  elif command -v pgrep &> /dev/null; then
    pids=$(pgrep -x "$process_name" 2>/dev/null)
  elif command -v ps &> /dev/null; then
    pids=$(ps -eo pid,comm | awk -v name="$process_name" '$2 == name {print $1}')
  fi
  [ -n "$pids" ] && echo "$pids"
}

keep_alive() {
  while true; do
    if [ -e "${FILE_PATH}/cloudflared" ] && argo_enabled && [ -z "$(Detect_process "cloudflared")" ]; then
      run_cloudflared
      sleep 5
    fi
    if [ -e "${FILE_PATH}/system-panel" ] && [ -z "$(Detect_process "system-panel")" ]; then
      run_panel
    fi
    sleep 55
  done
}

fetch_and_parse() {
    local url="$1"
    local json_key="$2"

    IP_INFO=$(curl -s "$url")
    if echo "$IP_INFO" | grep -q "\"${json_key}\""; then
        if [[ "$json_key" == "ip" ]]; then
            SERVER_IP=$(echo "$IP_INFO" | sed -n 's/.*"ip": *"\([^"]*\).*/\1/p')
        else
            SERVER_IP=$(echo "$IP_INFO" | sed -n 's/.*"query": *"\([^"]*\).*/\1/p')
        fi
        if [[ -n "$SERVER_IP" ]]; then
            export SERVER_IP
            return 0
        fi
    fi
    return 1
}

# get IP
get_ip_code() {
    local API_STATUS=1

    if fetch_and_parse "https://api.ip.sb/geoip" "ip"; then
        API_STATUS=0
    elif fetch_and_parse "http://ip-api.com/json" "query"; then
        API_STATUS=0
    elif [[ -n "$MYIP_URL" ]] && fetch_and_parse "${MYIP_URL}" "ip"; then
        API_STATUS=0
    fi

    if [[ "$API_STATUS" -eq 0 ]]; then
        if [[ ! "$SERVER_IP" =~ : ]]; then
            export MYIP="$SERVER_IP"
        else
            export MYIP="[$SERVER_IP]"
        fi
        return 0
    else
        export MYIP="1.1.1.1"
        return 1
    fi
}

# ==================== argo辅助函数 ====================
# ARGO_AUTH非空使用token固定隧道，ARGO_DOMAIN为空使用临时隧道
argo_enabled() {
  [ "${ENABLE_ARGO}" = "true" ] && { [ -n "${ARGO_AUTH}" ] || [ -z "${ARGO_DOMAIN}" ]; }
}

# 从argo.log获取临时隧道域名（存入ARGO_TEMP_DOMAIN，不覆盖用户配置的ARGO_DOMAIN）
get_argo_domain() {
  ARGO_TEMP_DOMAIN=""
  if [ -s "${FILE_PATH}/argo.log" ]; then
    export ARGO_TEMP_DOMAIN=$(grep -io "https://[^[:space:]]*trycloudflare\.com" "${FILE_PATH}/argo.log" | sed "s@https://@@g" | tail -n 1)
  fi
}

run_processes() {
  if argo_enabled && [ -e "${FILE_PATH}/system-panel" ]; then
    run_cloudflared
    sleep 5
  fi

  if [ -e "${FILE_PATH}/system-panel" ]; then
    run_panel
  fi

  if argo_enabled; then
    if [ -z "${ARGO_TEMP_DOMAIN}" ]; then
      get_argo_domain
    fi
    if [ -n "${ARGO_DOMAIN}" ]; then
      echo "ARGO隧道域名: ${ARGO_DOMAIN}"
      echo "Panel started successfully: http://${ARGO_DOMAIN}"
    elif [ -n "${ARGO_TEMP_DOMAIN}" ]; then
      echo "ARGO临时隧道域名: ${ARGO_TEMP_DOMAIN}"
      echo "Panel started successfully: http://${ARGO_TEMP_DOMAIN}"
    else
      get_ip_code && sleep 5
      echo "Panel started successfully: http://${MYIP}:${PORT}"
    fi
  else
    get_ip_code && sleep 5
    echo "Panel started successfully: http://${MYIP}:${PORT}"
  fi

  if [ -n "${KEEPALIVE}" ] && [ "${KEEPALIVE}" = "true" ]; then
    keep_alive 2>&1 &
  fi
}

# main
main() {
  initialize_downloads
  run_processes
  # 等待所有后台进程，而不是 tail -f /dev/null
  wait
}
main
