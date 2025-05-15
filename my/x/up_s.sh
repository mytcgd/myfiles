#!/bin/bash

general_upload_data() {
  if [ -n "${V_PORT}" ]; then
    if [ -n "${VLESS_WSPATH}" ] && [ -z "${XHTTP_PATH}" ]; then
      export vless_url="vless://${UUID}@${CF_IP}:${CFPORT}?host=${ARGO_DOMAIN}&path=%2F${VLESS_WSPATH}%3Fed%3D2048&type=ws&encryption=none&security=tls&sni=${ARGO_DOMAIN}#${country_abbreviation}-${SUB_NAME}"
      UPLOAD_DATA="$vless_url"
    fi
    if [ -n "${XHTTP_PATH}" ] && [ -z "${VLESS_WSPATH}" ]; then
      export xhttp_url="vless://${UUID}@${CF_IP}:${CFPORT}?encryption=none&security=tls&sni=${ARGO_DOMAIN}&type=xhttp&host=${ARGO_DOMAIN}&path=%2F${XHTTP_PATH}%3Fed%3D2048&mode=packet-up#${country_abbreviation}-${SUB_NAME}-xhttp"
      UPLOAD_DATA="$xhttp_url"
    fi
  fi
  if [ -n "$REAL_PORT" ]; then
    UPLOAD_DATA="$UPLOAD_DATA\n$reality_url"
  fi
  if [ -n "$SOCKS_PORT" ]; then
    UPLOAD_DATA="$UPLOAD_DATA\n$socks5_url"
  fi
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

# echo "upload ok!"
