#!/bin/bash

general_upload_data() {
  VMESS="{ \"v\": \"2\", \"ps\": \"${country_abbreviation}-${SUB_NAME}\", \"add\": \"${CF_IP}\", \"port\": \"${CFPORT}\", \"id\": \"${UUID}\", \"aid\": \"0\", \"scy\": \"none\", \"net\": \"ws\", \"type\": \"none\", \"host\": \"${ARGO_DOMAIN}\", \"path\": \"/${VMESS_WSPATH}?ed=2048\", \"tls\": \"tls\", \"sni\": \"${ARGO_DOMAIN}\", \"alpn\": \"\", \"fp\": \"randomized\"}"
  vmess_url="vmess://$(echo "$VMESS" | base64 | tr -d '\n')"
  vless_url="vless://${UUID}@${CF_IP}:${CFPORT}?host=${ARGO_DOMAIN}&path=%2F${VLESS_WSPATH}%3Fed%3D2048&type=ws&encryption=none&security=tls&sni=${ARGO_DOMAIN}#${country_abbreviation}-${SUB_NAME}"
  if [ -n "$MY_DOMAIN" ]; then
    hysteria_url="hysteria2://${UUID}@${MY_DOMAIN}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#${country_abbreviation}-${SUB_NAME}"
    tuic_url="tuic://${UUID}:${tuicpass}@${MY_DOMAIN}:${TUIC_PORT}?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allow_insecure=1#${country_abbreviation}-${SUB_NAME}"
    reality_url="vless://${UUID}@${MY_DOMAIN}:${REAL_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${public_key}&type=tcp&headerType=none#${country_abbreviation}-${SUB_NAME}-realitytcp"
    anytls_url="anytls://${UUID}@${MY_DOMAIN}:${ANYTLS_PORT}?insecure=1&udp=1#${country_abbreviation}-${SUB_NAME}"
  else
    hysteria_url="hysteria2://${UUID}@${MYIP}:${HY2_PORT}/?sni=www.bing.com&alpn=h3&insecure=1#${country_abbreviation}-${SUB_NAME}"
    tuic_url="tuic://${UUID}:${tuicpass}@${MYIP}:${TUIC_PORT}?sni=www.bing.com&congestion_control=bbr&udp_relay_mode=native&alpn=h3&allow_insecure=1#${country_abbreviation}-${SUB_NAME}"
    reality_url="vless://${UUID}@${MYIP}:${REAL_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${SNI}&fp=chrome&pbk=${public_key}&type=tcp&headerType=none#${country_abbreviation}-${SUB_NAME}-realitytcp"
    anytls_url="anytls://${UUID}@${MYIP}:${ANYTLS_PORT}?insecure=1&udp=1#${country_abbreviation}-${SUB_NAME}"
  fi

  if [ -n "${VMESS_WSPATH}" ] && [ -z "${VLESS_WSPATH}" ]; then
    UPLOAD_DATA="$vmess_url"
  fi

  if [ -n "${VLESS_WSPATH}" ] && [ -z "${VMESS_WSPATH}" ]; then
    UPLOAD_DATA="$vless_url"
  fi

  if [ -n "$HY2_PORT" ]; then
    UPLOAD_DATA="$UPLOAD_DATA\n$hysteria_url"
  fi

  if [ -n "$TUIC_PORT" ]; then
    UPLOAD_DATA="$UPLOAD_DATA\n$tuic_url"
  fi

  if [ -n "$REAL_PORT" ]; then
    UPLOAD_DATA="$UPLOAD_DATA\n$reality_url"
  fi

  if [ -n "$ANYTLS_PORT" ]; then
    UPLOAD_DATA="$UPLOAD_DATA\n$anytls_url"
  fi

  export UPLOAD_DATA
  # echo -e "${UPLOAD_DATA}"
}

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

if [ ! -s "${FILE_PATH}/boot.log" ]; then
  general_upload_data
  upload_url_data "${SUB_URL}" "${SUB_NAME}" "${UPLOAD_DATA}"
else
  while true
  do

  if [ -s "${FILE_PATH}/boot.log" ]; then
    export ARGO_DOMAIN=$(cat ${FILE_PATH}/boot.log | grep -o "info.*https://.*trycloudflare.com" | sed "s@.*https://@@g" | tail -n 1)
    # export ARGO_DOMAIN=$(cat ${FILE_PATH}/boot.log | grep -o "https://.*trycloudflare.com" | tail -n 1 | sed 's/https:\/\///')
  fi

  general_upload_data
  upload_url_data "${SUB_URL}" "${SUB_NAME}" "${UPLOAD_DATA}"

  sleep 100
  done
  fi
fi

# echo "upload ok!"
