#!/usr/bin/env bash
# Установка max-client из GitHub Releases: бинарник под вашу ОС/арх
# в ~/.local/bin (или MAX_INSTALL_DIR).
#
# Репозиторий приватный — скрипту нужен токен GitHub с правом «Contents: read»:
#   curl -fsSL <url>/install.sh | MAX_GH_TOKEN=github_pat_… bash
set -euo pipefail

REPO="roman-yerin/max-client-dist"
DEST="${MAX_INSTALL_DIR:-$HOME/.local/bin}"
TOKEN="${MAX_GH_TOKEN:-${GITHUB_TOKEN:-}}"
API="https://api.github.com"

die() { echo "install.sh: $*" >&2; exit 1; }

case "$(uname -s)" in
  Darwin) os=darwin ;;
  Linux) os=linux ;;
  *) die "поддерживаются macOS и Linux (ваше ядро: $(uname -s))" ;;
esac
case "$(uname -m)" in
  arm64 | aarch64) arch=arm64 ;;
  x86_64 | amd64) arch=amd64 ;;
  *) die "неизвестная архитектура: $(uname -m)" ;;
esac
asset="max-$os-$arch"

# macOS тянет bash 3.2, где пустой массив при set -u считается unbound.
curl_auth() {
  if [ -n "$TOKEN" ]; then
    curl -fsSL -H "Authorization: Bearer $TOKEN" "$@"
  else
    curl -fsSL "$@"
  fi
}

api() {
  curl_auth -H "Accept: application/vnd.github+json" "$@"
}

echo "==> ищу последний релиз ${REPO}…"
release="$(api "$API/repos/$REPO/releases/latest")" ||
  die "не удалось получить релиз. Если репозиторий приватный — передайте токен:
  curl … | MAX_GH_TOKEN=<github token> bash
(токену достаточно права «Contents: read»)"

# id ассета нужен для скачивания: у приватных репозиториев
# browser_download_url с Bearer-токеном не работает, работает только
# API-эндпоинт releases/assets/<id> с Accept: application/octet-stream.
aid="$(printf %s "$release" | awk -v want="\"$asset\"" '
  match($0, /releases\/assets\/[0-9]+/) { id = substr($0, RSTART + 16, RLENGTH - 16) }
  index($0, "\"name\": " want) { print id; exit }
')"

tmp="$(mktemp -t "$asset.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
echo "==> скачиваю ${asset}…"
if [ -n "$aid" ]; then
  # Редирект на S3 ловим вручную: curl переслал бы Authorization на чужой
  # хост, и S3 ответил бы 400 (два механизма авторизации сразу).
  loc="$(curl_auth -fsSI -H "Accept: application/octet-stream" \
    "$API/repos/$REPO/releases/assets/$aid" |
    grep -i '^location:' | tr -d '\r' | awk '{print $2}')" || true
  if [ -n "${loc:-}" ]; then
    curl -fsSL -o "$tmp" "$loc"
  else
    curl_auth -fL -H "Accept: application/octet-stream" \
      -o "$tmp" "$API/repos/$REPO/releases/assets/$aid"
  fi
else
  # Публичный репозиторий: обычная ссылка из релиза.
  url="$(printf %s "$release" | grep -o "\"browser_download_url\": *\"[^\"]*/$asset\"" |
    head -n1 | sed 's/.*"\(https[^"]*\)"/\1/')" || true
  [ -n "${url:-}" ] || die "в релизе нет ассета $asset"
  curl_auth -fL -o "$tmp" "$url"
fi

mkdir -p "$DEST"
install -m 0755 "$tmp" "$DEST/max"

case ":$PATH:" in
  *":$DEST:"*) ;;
  *) echo "==> внимание: $DEST нет в PATH — добавьте в ~/.zshrc:
  export PATH=\"\$PATH:$DEST\"" >&2 ;;
esac
echo "==> готово: $DEST/max — запускайте «max»"
