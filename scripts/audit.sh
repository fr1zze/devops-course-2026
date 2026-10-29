#!/usr/bin/env bash
set -uo pipefail

PASS=0
FAIL=0

check() {
    local description="$1"
    local expected="$2"
    local actual="$3"

    if [[ "$actual" == "$expected" ]]; then
        echo "[OK] $description"
        ((PASS += 1))
    else
        echo "[FAIL] $description"
        echo "  Ожидалось: $expected; получено: $actual"
        ((FAIL += 1))
    fi
}

SSH_CONFIG=$(sudo /usr/sbin/sshd -T) || exit 2
UFW_CONFIG=$(sudo env LC_ALL=C ufw status verbose) || exit 2

echo "Аудит: $(hostname -f), $(date '+%Y-%m-%d %H:%M')"

echo "[1] Служба SSH"

check "Вход root запрещён" "no" \
    "$(awk '/^permitrootlogin /{print $2}' <<< "$SSH_CONFIG")"

check "Парольный вход отключён" "no" \
    "$(awk '/^passwordauthentication /{print $2}' <<< "$SSH_CONFIG")"

PORT=$(awk '/^port /{print $2}' <<< "$SSH_CONFIG")
PORT_OK="no"

if [[ "$PORT" =~ ^[0-9]+$ && "$PORT" != "22" ]]; then
    PORT_OK="yes"
fi

check "SSH использует нестандартный порт" "yes" "$PORT_OK"

check "MaxAuthTries равен 3" "3" \
    "$(awk '/^maxauthtries /{print $2}' <<< "$SSH_CONFIG")"

echo "[2] Межсетевой экран"

check "UFW активен" "active" \
    "$(awk '/^Status:/{print $2}' <<< "$UFW_CONFIG")"

check "Входящие соединения запрещены по умолчанию" "deny" \
    "$(awk '/^Default:/{print $2}' <<< "$UFW_CONFIG")"

echo "[3] Учётные записи"

awk -F: '$3>=1000 && $3<65534 {
    printf "  %s (uid=%s)\n", $1, $3
}' /etc/passwd

echo "[4] Веб-сервер"

check "Nginx активен" "active" \
    "$(systemctl is-active nginx)"

sudo nginx -t
check "Конфигурация Nginx корректна" "0" "$?"

CERT_CHECK_SECONDS="${CERT_CHECK_SECONDS:-2592000}"

openssl x509 -in /etc/ssl/certs/devops.crt \
    -noout -checkend "$CERT_CHECK_SECONDS"
check "Сертификат действителен на заданный срок" "0" "$?"

web_permissions_ok() {
    local writable
    local key_mode

    writable=$(find /var/www/devops-site -perm -o+w) || return 1
    key_mode=$(sudo stat -c '%a' /etc/ssl/private/devops.key) || return 1

    [[ -z "$writable" && "$key_mode" == "600" ]]
}

web_permissions_ok
check "Нет записи для всех, права закрытого ключа 600" "0" "$?"

echo "[5] Containerization"

check "Docker service is active" "active" \
    "$(systemctl is-active docker)"

check "PostgreSQL container is healthy" "healthy" \
    "$(docker inspect -f '{{.State.Health.Status}}' app-db-1)"

container_ports_ok() {
    local listeners

    listeners=$(ss -H -ltn) || return 1

    awk '
        $4 ~ /:(5000|5432)$/ {
            if ($4 != "127.0.0.1:5000" &&
                $4 != "127.0.0.1:5432") {
                bad = 1
            }
        }
        END {
            exit bad
        }
    ' <<< "$listeners"
}

container_ports_ok
check "Ports 5000 and 5432 are restricted to 127.0.0.1" "0" "$?"

check "App environment file has permissions 600" "600" \
    "$(stat -c '%a' /home/devops/app/.env)"

echo "Пройдено: $PASS, не пройдено: $FAIL"

if [[ "$FAIL" -eq 0 ]]; then
    exit 0
else
    exit 1
fi
