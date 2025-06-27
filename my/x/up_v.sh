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

    if [ -n "$V_PORT" ]; then
      if [ -n "$MY_DOMAIN" ] && [ -z "${ARGO_DOMAIN}" ]; then
        export ARGO_DOMAIN="$MY_DOMAIN"
      fi
      if [ -n "${VLESS_WSPATH}" ] && [ -z "${XHTTP_PATH}" ]; then
        vless_url="vless://${UUID}@${CF_IP}:${CFPORT}?host=${ARGO_DOMAIN}&path=%2F${VLESS_WSPATH}%3Fed%3D2560&type=ws&encryption=none&security=tls&sni=${ARGO_DOMAIN}#${ISP}-${SUB_NAME}"
        UPLOAD_DATA="$vless_url"
      elif [ -n "${XHTTP_PATH}" ] && [ -z "${VLESS_WSPATH}" ]; then
        xhttp_url="vless://${UUID}@${CF_IP}:${CFPORT}?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=xhttp&host=${ARGO_DOMAIN}&path=%2F${XHTTP_PATH}%3Fed%3D2560&mode=packet-up#${ISP}-${SUB_NAME}-xhttp"
        UPLOAD_DATA="$xhttp_url"
      fi
    fi

    if [ -n "$REAL_PORT" ] && [ -n "$shortid" ]; then
      reality_url="vless://${UUID}@${MYIP}:${REAL_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PublicKey}&sid=${shortid}&type=tcp&headerType=none#${ISP}-${SUB_NAME}-realtcp"
      UPLOAD_DATA="$UPLOAD_DATA\n$reality_url"
    elif [ -n "$REAL_PORT" ] && [ -z "$shortid" ]; then
      reality_url="vless://${UUID}@${MYIP}:${REAL_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PublicKey}&type=tcp&headerType=none#${ISP}-${SUB_NAME}-realtcp"
      UPLOAD_DATA="$UPLOAD_DATA\n$reality_url"
    fi

    if [[ "$previousargoDomain" != "$ARGO_DOMAIN" ]]; then
      upload_subscription
      export previousargoDomain="$ARGO_DOMAIN"
    fi
    sleep 100
  done
fi
