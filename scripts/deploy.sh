#!/usr/bin/env bash
set -euo pipefail

REMOTE="devops"
REMOTE_DIR="/var/www/devops-site"
SITE_URL="https://devops.local"
CA_CERT="${HOME}/devops.crt"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

DRY_RUN=false

if [[ $# -gt 1 ]]; then
    fail "Usage: deploy.sh [--dry-run]"
fi

if [[ $# -eq 1 ]]; then
    [[ "$1" == "--dry-run" ]] || fail "Unknown argument: $1"
    DRY_RUN=true
fi

ROOT="$(git rev-parse --show-toplevel)" || fail "Not a Git repository"
LOCAL_DIR="${ROOT}/site/"

[[ -f "${LOCAL_DIR}index.html" ]] || fail "site/index.html is missing"

STATUS="$(git -C "$ROOT" status --porcelain)" || fail "Cannot check Git status"
[[ -z "$STATUS" ]] || fail "Commit changes before deployment"

COMMIT="$(git -C "$ROOT" rev-parse --short HEAD)"

OPTIONS=(-avz --delete --chmod=D755,F644)

if [[ "$DRY_RUN" == true ]]; then
    OPTIONS+=(--dry-run)
fi

rsync "${OPTIONS[@]}" \
    -e "ssh -o BatchMode=yes -o ConnectTimeout=5" \
    "$LOCAL_DIR" "${REMOTE}:${REMOTE_DIR}/" \
    || fail "File transfer failed"

if [[ "$DRY_RUN" == true ]]; then
    echo "Dry run OK: ${COMMIT}"
    exit 0
fi

curl --fail --silent --show-error \
    --connect-timeout 5 --max-time 15 \
    --cacert "$CA_CERT" \
    --output /dev/null "$SITE_URL" \
    || fail "HTTPS check failed"

echo "Deployment OK: ${COMMIT}"