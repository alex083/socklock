#!/bin/bash

set -e

# === Настройки ===
API_URL=${API_URL:-https://api.runonflux.io/apps/location/proxypoolusa}
PORT=${PORT:-6000}
CLIENT_PASS=${CLIENT_PASS:-clientpass}
REMOTE_USER=${REMOTE_USER:-proxyuser}
REMOTE_PASS=${REMOTE_PASS:-proxypass}
REMOTE_PORT=${REMOTE_PORT:-3405}
PROXY_MODE=${PROXY_MODE:-socks5}
SERVER_IP=$(curl -s ifconfig.me)


CONFIG_FILE="/configs/3proxy.cfg"
TMP_CONFIG="/tmp/3proxy_new.cfg"
USER_MAP_FILE="/configs/user-map.txt"
PROXY_LIST="/configs/proxies.txt"

mkdir -p /configs

declare -A USER_IP_MAP
declare -A USED_IPS

# === Загрузка ранее закреплённых логинов ===
load_user_map() {
  if [[ -f "$USER_MAP_FILE" ]]; then
    while IFS=":" read -r user ip; do
      USER_IP_MAP["$user"]="$ip"
      USED_IPS["$ip"]=1
    done < "$USER_MAP_FILE"
  fi
}

save_user_map() {
  > "$USER_MAP_FILE"
  for user in "${!USER_IP_MAP[@]}"; do
    echo "$user:${USER_IP_MAP[$user]}" >> "$USER_MAP_FILE"
  done
}

check_proxy() {
  local ip=$1
  local result
  result=$(timeout 6 curl --silent --socks5-hostname "$REMOTE_USER:$REMOTE_PASS@$ip:$REMOTE_PORT" http://ip-api.com/json -m 6)
  local status=$?
  local extracted_ip=$(echo "$result" | jq -r '.query')
  if [[ $status -eq 0 && "$extracted_ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    return 0
  fi
  return 1
}

generate_config() {
  echo "[*] Генерация конфигурации..."
  load_user_map

  for user in "${!USER_IP_MAP[@]}"; do
    ip="${USER_IP_MAP[$user]}"
    if ! check_proxy "$ip"; then
      echo "[-] $ip (user $user) — нерабочий"
      unset USER_IP_MAP["$user"]
      unset USED_IPS["$ip"]
    else
      echo "[✓] $ip (user $user) — рабочий"
    fi
  done

  IP_LIST=$(curl -s "$API_URL" | jq -r '.data[].ip' | cut -d':' -f1)

  for ip in $IP_LIST; do
    [[ ${USED_IPS[$ip]} ]] && continue
    user="user$(shuf -i 1000-9999 -n 1)"
    while [[ -n "${USER_IP_MAP[$user]}" ]]; do
      user="user$(shuf -i 1000-9999 -n 1)"
    done
    if check_proxy "$ip"; then
      USER_IP_MAP["$user"]="$ip"
      USED_IPS["$ip"]=1
      echo "[+] Назначен IP $ip для $user"
    fi
  done

  echo "[*] Генерация файла конфигурации..."

  > "$TMP_CONFIG"
  echo "nserver 8.8.8.8" >> "$TMP_CONFIG"
  echo "nscache 65536" >> "$TMP_CONFIG"

  USERS_LINE=""
  > "$PROXY_LIST"

  for user in "${!USER_IP_MAP[@]}"; do
    USERS_LINE+="$user:CL:$CLIENT_PASS "
  done
  echo "users $USERS_LINE" >> "$TMP_CONFIG"
  echo "auth strong" >> "$TMP_CONFIG"

  for user in "${!USER_IP_MAP[@]}"; do
    ip="${USER_IP_MAP[$user]}"
    echo "allow $user" >> "$TMP_CONFIG"
    echo "parent 1000 socks5 $ip $REMOTE_PORT $REMOTE_USER $REMOTE_PASS" >> "$TMP_CONFIG"
    echo "${PROXY_MODE}://$user:$CLIENT_PASS@$SERVER_IP:$PORT" >> "$PROXY_LIST"
  done

  if [[ "$PROXY_MODE" == "http" ]]; then
    echo "proxy -p$PORT -a -i0.0.0.0 -n" >> "$TMP_CONFIG"
  else
    echo "socks -p$PORT -a -i0.0.0.0 -n" >> "$TMP_CONFIG"
  fi

  # Обновляем только если изменилось
  if ! cmp -s "$TMP_CONFIG" "$CONFIG_FILE"; then
    echo "[~] Конфигурация изменилась, перезапуск 3proxy..."
    cp "$TMP_CONFIG" "$CONFIG_FILE"
    pkill -f "/usr/local/3proxy/bin/3proxy $CONFIG_FILE" 2>/dev/null || true
    /usr/local/3proxy/bin/3proxy "$CONFIG_FILE" &
  else
    echo "[=] Конфигурация не изменилась, ничего не перезапускаем"
  fi

  save_user_map

  echo "[*] Конфигурация применена ✅"
  echo "[*] Список SOCKS5-прокси:"
  cat "$PROXY_LIST"
}

# === Первый запуск ===
generate_config

# === Циклический автообновление ===
while true; do
  sleep 3600
  echo "[*] Обновление конфигурации по таймеру..."
  generate_config
done
