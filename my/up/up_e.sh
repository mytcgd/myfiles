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

    ECH_SERVER="wss://${ARGO_DOMAIN}:8443/tunnel"
    UPLOAD_DATA="ech://server=${ECH_SERVER}&listen=${ECH_LISTEN}&token=${UUID}&dns=${ECH_DNS}&ech=${ECH_URL}&ip=${CF_IP}&name=${SUB_NAME}"

    if [[ "$previousargoDomain" != "$ARGO_DOMAIN" ]]; then
      upload_subscription
      export previousargoDomain="$ARGO_DOMAIN"
    fi
    sleep 100
  done
fi
