#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local desc="$1" expected="$2" actual="$3"
    if [[ "$actual" == "$expected" ]]; then
        echo " [OK]    $desc"
        ((PASS++)) || true
    else
        echo " [FAIL]  $desc (ожидалось: '$expected', получено: '$actual')"
        ((FAIL++)) || true
    fi
}

echo "Аудит конфигурации: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"
echo

# ===================== [1] Служба SSH =====================
echo "[1] Служба SSH"
check "Вход от имени root запрещён" \
    "no" "$(sudo sshd -T 2>/dev/null | awk '/^permitrootlogin/{print $2}')"

check "Парольная аутентификация отключена" \
    "no" "$(sudo sshd -T 2>/dev/null | awk '/^passwordauthentication/{print $2}')"

PORT=$(sudo sshd -T 2>/dev/null | awk '/^port /{print $2}')
if [[ "$PORT" != "22" ]]; then
    check "Порт SSH изменён (не 22)" "$PORT" "$PORT"
else
    check "Порт SSH изменён (не 22)" "не 22" "$PORT"
fi

check "MaxAuthTries равен 3" \
    "3" "$(sudo sshd -T 2>/dev/null | awk '/^maxauthtries/{print $2}')"

echo

# ===================== [2] Межсетевой экран =====================
echo "[2] Межсетевой экран"
check "Межсетевой экран активен" \
    "active" "$(sudo ufw status 2>/dev/null | awk '/^Status:/{print $2}')"

DEFAULT_IN=$(sudo ufw status verbose 2>/dev/null | grep -i "Default:" | head -1 | awk '{print $2}')
check "Политика входящего трафика deny" "deny" "$DEFAULT_IN"

echo

# ===================== [3] Учётные записи =====================
echo "[3] Учётные записи"
awk -F: '$3>=1000 && $3<65534 {printf "              %s (uid=%s)\n",$1,$3}' /etc/passwd
echo

# ===================== [4] Веб-сервер =====================
echo "[4] Веб-сервер"

# а) служба nginx активна
check "Служба nginx активна" \
    "active" "$(systemctl is-active nginx 2>/dev/null || echo inactive)"

# б) конфигурация синтаксически корректна
if sudo nginx -t &>/dev/null; then
    check "Конфигурация nginx корректна" "0" "0"
else
    check "Конфигурация nginx корректна" "0" "1"
fi

# в) сертификат истекает не ранее чем через 30 дней
if sudo openssl x509 -in /etc/ssl/certs/devops.crt -checkend $((30*24*3600)) &>/dev/null; then
    check "Сертификат действителен ≥ 30 дней" "0" "0"
else
    check "Сертификат действителен ≥ 30 дней" "0" "1"
fi

# г) нет файлов с правом записи для остальных + права ключа = 600
WRITABLE=$(find /var/www/devops-site -perm -o+w 2>/dev/null | wc -l)
KEY_PERM=$(sudo stat -c '%a' /etc/ssl/private/devops.key 2>/dev/null || echo "000")

if [[ "$WRITABLE" -eq 0 && "$KEY_PERM" == "600" ]]; then
    check "Права на ресурс и ключ корректны" "ok" "ok"
else
    check "Права на ресурс и ключ корректны" "ok" "writable=$WRITABLE key=$KEY_PERM"
fi

echo
echo "Пройдено: $PASS, не пройдено: $FAIL"
[[ $FAIL -eq 0 ]] && exit 0 || exit 1