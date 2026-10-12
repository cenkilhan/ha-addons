#!/usr/bin/with-contenv bashio
# Ev Bot — HA Green eklentisi girisi. Secenekleri daemon'un bekledigi ortam dosyasina yazar ve
# daemon'u /share/ev-otomasyon icinden calistirir. Kalici veri: /data (HOME).
set -euo pipefail
export HOME=/data
mkdir -p /data/.config /data/logs /data/claude-ev /data/.local/bin
ln -sf /usr/local/bin/claude /data/.local/bin/claude

TG_BOT_TOKEN="$(bashio::config 'tg_bot_token')"
TG_CHAT_ID="$(bashio::config 'tg_chat_id')"
CLAUDE_OAUTH="$(bashio::config 'claude_oauth_token')"
REPO_DIR="$(bashio::config 'repo_dir')"

if [[ -z "$TG_BOT_TOKEN" || -z "$TG_CHAT_ID" || -z "$CLAUDE_OAUTH" ]]; then
  bashio::log.error "tg_bot_token, tg_chat_id ve claude_oauth_token secenekleri dolu olmali"; exit 1
fi
if [[ ! -f "$REPO_DIR/scripts/ev_bot_daemon.py" ]]; then
  bashio::log.error "Depo bulunamadi: $REPO_DIR (scripts/ev_bot_daemon.py yok). /share altina kopyalayin."; exit 1
fi
umask 077
cat > /data/.config/tg_ev.env <<ENV
TG_BOT_TOKEN=$TG_BOT_TOKEN
TG_CHAT_ID=$TG_CHAT_ID
CLAUDE_CODE_OAUTH_TOKEN=$CLAUDE_OAUTH
ENV

# Daemon icin yollar (ev_bot_daemon.py bunlari ortamdan okur; yoksa HOME altini kullanir)
export EV_REPO="$REPO_DIR"
export CLAUDE_BIN=/usr/local/bin/claude
export CLAUDE_CONFIG_DIR=/data/claude-ev
export DISABLE_AUTOUPDATER=1
export CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1
# HA erisimi: SUPERVISOR_TOKEN ile http://supervisor/core (ha.sh bunu tanir)
export HA_URL="http://supervisor/core"
export HA_TOKEN="${SUPERVISOR_TOKEN}"
export EV_BOT_ON_GREEN=1
export PATH="/usr/local/bin:/usr/bin:/bin:$REPO_DIR/scripts"
# Konteyner root calisir; Claude root'ta --dangerously-skip-permissions'i reddeder
# ("cannot be used with root/sudo privileges"). IS_SANDBOX=1 bu kontrolu kaldirir — eklenti
# zaten yalitilmis bir konteyner. (12.10.2026: ilk gercek mesaj bu yuzden hata dondu.)
export IS_SANDBOX=1

# Claude icin calisma alani guveni (headless -p modunda trust diyalogu askida kalmasin)
python3 - "$REPO_DIR" <<'PY'
import json,os,sys
p="/data/claude-ev/.claude.json"
try: d=json.load(open(p))
except Exception: d={}
d.setdefault("projects",{}).setdefault(sys.argv[1],{})["hasTrustDialogAccepted"]=True
d["hasCompletedOnboarding"]=True
json.dump(d,open(p,"w"))
PY

# Daemon gunlugunu eklenti gunlugune akit (ha addons logs ile izlenebilsin)
touch /data/logs/ev_bot_daemon.log; tail -n 20 -F /data/logs/ev_bot_daemon.log &

bashio::log.info "Ev Bot basliyor — depo: $REPO_DIR, claude: $(claude --version 2>/dev/null || echo ?)"
cd "$REPO_DIR"

# Baslangic oz-testi (arka planda): Claude bu konteynerde gercekten cevap verebiliyor mu?
# Sonuc eklenti gunlugune duser; Telegram'dan mesaj atmadan dogrulanabilir.
(
  cikti="$(CLAUDE_CODE_OAUTH_TOKEN="$CLAUDE_OAUTH" timeout 180 claude -p --output-format json \
            --dangerously-skip-permissions "Sadece OK yaz." </dev/null 2>&1)" || true
  sonuc="$(printf '%s' "$cikti" | python3 -c 'import sys,json
try:
    d=json.loads(sys.stdin.read()); print(("HATA " if d.get("is_error") else "OK ")+str(d.get("result"))[:120])
except Exception: print("HATA (json degil)")' 2>/dev/null || echo "HATA (ayristirilamadi)")"
  if [[ "$sonuc" == OK* ]]; then
    bashio::log.info "Claude oz-testi: $sonuc"
  else
    bashio::log.error "Claude oz-testi: $sonuc — ham: $(printf '%s' "$cikti" | tail -c 300)"
  fi
) &
exec python3 "$REPO_DIR/scripts/ev_bot_daemon.py"
