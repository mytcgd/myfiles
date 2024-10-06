#!/bin/bash

if source /root/env.yml; then
  while true
  do

  upload_url_data() {
    if [ $# -lt 3 ]; then
      return 1
    fi

    UPLOAD_URL="$1"
    URL_NAME="$2"
    URL_TO_UPLOAD="$3"

    if command -v curl &> /dev/null; then
      curl -s -o /dev/null -X POST -H "Content-Type: application/json" -d "{\"URL_NAME\": \"$URL_NAME\", \"URL\": \"$URL_TO_UPLOAD\"}" "$UPLOAD_URL"
    elif command -v wget &> /dev/null; then
      echo "{\"URL_NAME\": \"$URL_NAME\", \"URL\": \"$URL_TO_UPLOAD\"}" | wget --quiet --post-data=- --header="Content-Type: application/json" "$UPLOAD_URL" -O -
    else
      echo "Both curl and wget are not installed. Please install one of them to upload data."
    fi
  }

  [ -s ${FILE_PATH}/argo.log ] && export ARGO_DOMAIN=$(cat ${FILE_PATH}/argo.log | grep -o "info.*https://.*trycloudflare.com" | sed "s@.*https://@@g" | tail -n 1)
  # [ -s ${FILE_PATH}/argo.log ] && export ARGO_DOMAIN=$(cat ${FILE_PATH}/argo.log | grep -o "https://.*trycloudflare.com" | tail -n 1 | sed 's/https:\/\///')

  VMESS="{ \"v\": \"2\", \"ps\": \"${country_abbreviation}-${SUB_NAME}\", \"add\": \"${CF_IP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/${VMESS_WSPATH}?ed=2048\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\" }"

  # vmess_url="vmess://$(echo "$VMESS" | base64 | tr -d '\n')"
  vless_url="vless://${UUID}@${CF_IP}:${CFPORT}?host=${ARGO_DOMAIN}&path=%2F${VLESS_WSPATH}%3Fed%3D2048&type=ws&encryption=none&security=tls&sni=${ARGO_DOMAIN}#vless-${country_abbreviation}-${SUB_NAME}"
  splithttp_url="vless://${UUID}@${CF_IP}:8443?path=%2Fsplit&security=tls&encryption=none&host=${MY_DOMAIN}&type=splithttp&sni=${MY_DOMAIN}#${country_abbreviation}-${SUB_NAME}-splithttp"
  reality_url="vless://${UUID}@${MYIP}:${REAL_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${PublicKey}&type=tcp&headerType=none#${country_abbreviation}-${SUB_NAME}"

  # UPLOAD_DATA="$vmess_url\n$vless_url"
  UPLOAD_DATA="$vless_url\n$splithttp_url"

  if [ -n "$REAL_PORT" ]; then
    UPLOAD_DATA="$UPLOAD_DATA\n$reality_url"
  fi

  export UPLOAD_DATA
  # echo -e "${UPLOAD_DATA}"

  upload_url_data "${SUB_URL}" "${SUB_NAME}" "${UPLOAD_DATA}"
  # echo "upload ok!"

  sleep 100
  done
fi
