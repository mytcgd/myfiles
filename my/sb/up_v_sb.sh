#!/bin/bash

if source /root/.env; then
  export previousargoDomain=""
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
      if [ -n "$MY_DOMAIN" ] && [ -z "${ARGO_DOMAIN}" ]; then
        export ARGO_DOMAIN="$MY_DOMAIN"
      fi
      if [ -n "${VMESS_WSPATH}" ] && [ -z "${VLESS_WSPATH}" ]; then
        VMESS="{ \"v\": \"2\", \"ps\": \"${ISP}-${SUB_NAME}\", \"add\": \"${CF_IP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/${VMESS_WSPATH}?ed=2560\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"randomized\"}"
        vmess_url="vmess://$(echo "$VMESS" | base64 | tr -d '\n')"
        UPLOAD_DATA="$vmess_url"
      elif [ -n "${VLESS_WSPATH}" ] && [ -z "${VMESS_WSPATH}" ]; then
        vless_url="vless://${UUID}@${CF_IP}:${CFPORT}?host=${ARGO_DOMAIN}&path=%2F${VLESS_WSPATH}%3Fed%3D2560&type=ws&encryption=none&security=tls&sni=${ARGO_DOMAIN}#${ISP}-${SUB_NAME}"
        UPLOAD_DATA="$vless_url"
      fi
    fi

    if [ -n "$HY2_PORT" ]; then
      hysteria_url="hysteria2://${UUID}@${MYIP}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#${ISP}-${SUB_NAME}"
      UPLOAD_DATA="$UPLOAD_DATA\n$hysteria_url"
    fi

    if [ -n "$TUIC_PORT" ]; then
      tuic_url="tuic://${UUID}:${TUICPASS}@${MYIP}:${TUIC_PORT}?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allow_insecure=1#${ISP}-${SUB_NAME}"
      UPLOAD_DATA="$UPLOAD_DATA\n$tuic_url"
    fi

    if [ -n "$REAL_PORT" ]; then
      reality_url="vless://${UUID}@${MYIP}:${REAL_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${public_key}&type=tcp&headerType=none#${ISP}-${SUB_NAME}-realitytcp"
      UPLOAD_DATA="$UPLOAD_DATA\n$reality_url"
    fi

    if [ -n "$ANYTLS_PORT" ]; then
      anytls_url="anytls://${UUID}@${MYIP}:${ANYTLS_PORT}?insecure=1&udp=1#${ISP}-${SUB_NAME}"
      UPLOAD_DATA="$UPLOAD_DATA\n$anytls_url"
    fi

    if [[ "$previousargoDomain" != "$ARGO_DOMAIN" ]]; then
      upload_subscription
      export previousargoDomain="$ARGO_DOMAIN"
    fi
    sleep 100
  done
fi
