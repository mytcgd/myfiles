#!/bin/bash

if source /root/.env; then
  previousargoDomain=""
  while true; do
    upload_subscription() {
      if command -v curl &> /dev/null; then
        response=$(curl -s -X POST -H "Content-Type: application/json" -d "{\"URL_NAME\":\"$SUB_NAME\",\"URL\":\"$UPLOAD_DATA\"}" $SUB_URL)
      elif command -v wget &> /dev/null; then
        response=$(wget -qO- --post-data="{\"URL_NAME\":\"$SUB_NAME\",\"URL\":\"$UPLOAD_DATA\"}" --header="Content-Type: application/json" $SUB_URL)
      fi
    }

    if [ -s "${FILE_PATH}/argo.log" ]; then
      export ARGO_DOMAIN=$(cat ${FILE_PATH}/argo.log | grep -o "info.*https://.*trycloudflare.com" | sed "s@.*https://@@g" | tail -n 1)
      sleep 2
    fi

    UPLOAD_DATA=""
    if [ -n "${V_PORT}" ]; then
      if [ -n "${VMESS_WSPATH}" ] && [ -z "${VLESS_WSPATH}" ]; then
        VMESS="{ \"v\": \"2\", \"ps\": \"${ISP}-${SUB_NAME}\", \"add\": \"${CF_IP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/${VMESS_WSPATH}?ed=2560\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"randomized\"}"
        UPLOAD_DATA="vmess://$(echo "$VMESS" | base64 | tr -d '\n')"
      elif [ -n "${VLESS_WSPATH}" ] && [ -z "${VMESS_WSPATH}" ]; then
        UPLOAD_DATA="vless://${UUID}@${CF_IP}:${CFPORT}?host=${ARGO_DOMAIN}&path=%2F${VLESS_WSPATH}%3Fed%3D2560&type=ws&encryption=none&security=tls&sni=${ARGO_DOMAIN}#${ISP}-${SUB_NAME}"
      fi
    fi
    if [ -n "$HY2_PORT" ] && [ -n "$hysteria_url" ]; then
      UPLOAD_DATA="$UPLOAD_DATA\n$hysteria_url"
    fi
    if [ -n "$TUIC_PORT" ] && [ -n "$tuic_url" ]; then
      UPLOAD_DATA="$UPLOAD_DATA\n$tuic_url"
    fi
    if [ -n "$REAL_PORT" ] && [ -n "$reality_url" ]; then
      UPLOAD_DATA="$UPLOAD_DATA\n$reality_url"
    fi
    if [ -n "$ANYTLS_PORT" ] && [ -n "$anytls_url" ]; then
      UPLOAD_DATA="$UPLOAD_DATA\n$anytls_url"
    fi
    if [ -n "$SOCKS_PORT" ] && [ -n "$socks5_url" ]; then
      UPLOAD_DATA="$UPLOAD_DATA\n$socks5_url"
    fi

    if [[ "$previousargoDomain" != "$ARGO_DOMAIN" ]]; then
      upload_subscription
      export previousargoDomain="$ARGO_DOMAIN"
    fi
    sleep 100
  done
fi
