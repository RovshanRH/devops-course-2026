#!/usr/bin/env bash
# Доставка статического ресурса на devops-vm
# Использование: scripts/deploy.sh [--dry-run]
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"
LOCAL_DIR="$(git rev-parse --show-toplevel)/site/"

# --- 1. Разбор аргумента --dry-run ---
DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
elif [[ -n "${1:-}" ]]; then
    echo "Использование: $0 [--dry-run]" >&2
    exit 1
fi

# --- 2. Проверки ---
# Требование 4: должен существовать site/index.html
if [[ ! -f "${LOCAL_DIR}index.html" ]]; then
    echo "Ошибка: файл site/index.html отсутствует" >&2
    exit 1
fi

# Требование 5: не должно быть незафиксированных изменений
if ! git -C "$(git rev-parse --show-toplevel)" diff --quiet || \
   ! git -C "$(git rev-parse --show-toplevel)" diff --cached --quiet; then
    echo "Ошибка: в репозитории есть незафиксированные изменения" >&2
    exit 1
fi

# --- 3. Синхронизация ---
RSYNC_OPTS=(-avz --delete --chmod=D755,F644)
RSYNC_SSH=(-e "ssh -o BatchMode=yes -o ConnectTimeout=5")

if [[ $DRY_RUN -eq 1 ]]; then
    echo "=== Режим dry-run ==="
    rsync "${RSYNC_OPTS[@]}" --dry-run "${RSYNC_SSH[@]}" \
        "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"
    echo "Dry-run завершён успешно"
    exit 0
fi

echo "Доставка site/ → ${REMOTE}:${REMOTE_DIR}"
rsync "${RSYNC_OPTS[@]}" "${RSYNC_SSH[@]}" \
    "${LOCAL_DIR}" "${REMOTE}:${REMOTE_DIR}/"

# --- 4. Проверка доступности ---
if ! curl -fsS --cacert "${CA_CERT}" -o /dev/null "${SITE_URL}/"; then
    echo "Ошибка: ресурс ${SITE_URL} недоступен после деплоя" >&2
    exit 1
fi

# --- 5. Успешное завершение ---
COMMIT_HASH=$(git -C "$(git rev-parse --show-toplevel)" rev-parse --short HEAD)
echo "Деплой успешен. Коммит: ${COMMIT_HASH}"
exit 0