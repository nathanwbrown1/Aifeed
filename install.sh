#!/usr/bin/env bash
# Miniflux RSS reader — one-shot installer
# Sets up Miniflux + Postgres in Docker, creates an admin account,
# and preloads the AI / DevOps feed list.
#
# Usage (as root, or with sudo, on a Debian/Ubuntu VM or LXC):
#   bash install.sh
#
# Optional overrides:
#   PORT=8080 ADMIN_USER=nate INSTALL_DIR=/opt/miniflux TZ_NAME=America/Denver bash install.sh
#
# Safe to re-run: existing credentials and data are kept.

set -euo pipefail

MINIFLUX_VERSION="${MINIFLUX_VERSION:-2.3.4}"
POSTGRES_VERSION="${POSTGRES_VERSION:-18}"
INSTALL_DIR="${INSTALL_DIR:-/opt/miniflux}"
PORT="${PORT:-8080}"
ADMIN_USER="${ADMIN_USER:-nate}"
TZ_NAME="${TZ_NAME:-America/Denver}"

log()  { printf '\033[1;36m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m %s\n' "$*" >&2; exit 1; }

[[ $EUID -eq 0 ]] || die "Run as root (or with sudo)."

# --- Don't install Docker onto a Proxmox host itself ----------------------
if command -v pveversion >/dev/null 2>&1 && [[ "${FORCE:-0}" != "1" ]]; then
  die "This looks like a Proxmox host. Run this inside a Debian/Ubuntu VM or LXC instead (set FORCE=1 to override)."
fi

# --- Docker ----------------------------------------------------------------
if ! command -v docker >/dev/null 2>&1; then
  log "Docker not found — installing via get.docker.com"
  command -v curl >/dev/null 2>&1 || { apt-get update -qq && apt-get install -y -qq curl; }
  curl -fsSL https://get.docker.com | sh
fi
docker compose version >/dev/null 2>&1 || die "The Docker Compose plugin is missing (docker compose)."
systemctl enable --now docker >/dev/null 2>&1 || true

# --- Directory + secrets ---------------------------------------------------
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"

rand() { tr -dc 'A-Za-z0-9' </dev/urandom | head -c "$1"; }

# Pick the address you'll browse to: Tailscale IP if present, else first LAN IP
detect_host() {
  local ip=""
  if command -v tailscale >/dev/null 2>&1; then
    ip="$(tailscale ip -4 2>/dev/null | head -n1 || true)"
  fi
  [[ -n "$ip" ]] || ip="$(hostname -I 2>/dev/null | awk '{print $1}')"
  [[ -n "$ip" ]] || ip="localhost"
  printf '%s' "$ip"
}

if [[ -f .env ]]; then
  log "Existing install found in $INSTALL_DIR — reusing credentials"
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
else
  HOST_ADDR="$(detect_host)"
  cat > .env <<EOF
MINIFLUX_VERSION=${MINIFLUX_VERSION}
POSTGRES_VERSION=${POSTGRES_VERSION}
PORT=${PORT}
BASE_URL=http://${HOST_ADDR}:${PORT}/
DB_PASSWORD=$(rand 32)
ADMIN_USERNAME=${ADMIN_USER}
ADMIN_PASSWORD=$(rand 20)
EOF
  chmod 600 .env
  set -a
  # shellcheck source=/dev/null
  source .env
  set +a
fi

# --- Compose file ----------------------------------------------------------
cat > compose.yaml <<'EOF'
services:
  miniflux:
    image: miniflux/miniflux:${MINIFLUX_VERSION}
    container_name: miniflux
    restart: unless-stopped
    ports:
      - "${PORT}:8080"
    depends_on:
      db:
        condition: service_healthy
    environment:
      DATABASE_URL: postgres://miniflux:${DB_PASSWORD}@db/miniflux?sslmode=disable
      RUN_MIGRATIONS: "1"
      CREATE_ADMIN: "1"
      ADMIN_USERNAME: ${ADMIN_USERNAME}
      ADMIN_PASSWORD: ${ADMIN_PASSWORD}
      BASE_URL: ${BASE_URL}
    healthcheck:
      test: ["CMD", "/usr/bin/miniflux", "-healthcheck", "auto"]
      interval: 30s
      start_period: 20s

  db:
    image: postgres:${POSTGRES_VERSION}
    container_name: miniflux-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: miniflux
      POSTGRES_PASSWORD: ${DB_PASSWORD}
      POSTGRES_DB: miniflux
    volumes:
      # Postgres 18+ keeps data under /var/lib/postgresql
      - miniflux-db:/var/lib/postgresql
    healthcheck:
      test: ["CMD", "pg_isready", "-U", "miniflux"]
      interval: 10s
      start_period: 30s

volumes:
  miniflux-db:
EOF

# --- Feed list -------------------------------------------------------------
cat > feeds.opml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<opml version="2.0">
  <head>
    <title>AI and DevOps feeds</title>
  </head>
  <body>
    <outline text="AI" title="AI">
      <outline type="rss" text="Latent Space" title="Latent Space" xmlUrl="https://latent.space/feed" htmlUrl="https://latent.space/"/>
      <outline type="rss" text="Simon Willison's Weblog" title="Simon Willison's Weblog" xmlUrl="https://simonwillison.net/atom/everything/" htmlUrl="https://simonwillison.net/"/>
      <outline type="rss" text="Dwarkesh Podcast" title="Dwarkesh Podcast" xmlUrl="https://www.dwarkesh.com/feed" htmlUrl="https://www.dwarkesh.com/"/>
      <outline type="rss" text="Machine Learning Street Talk" title="Machine Learning Street Talk" xmlUrl="https://anchor.fm/s/1e4a0eac/podcast/rss"/>
      <outline type="rss" text="The AI Daily Brief" title="The AI Daily Brief" xmlUrl="https://anchor.fm/s/f7cac464/podcast/rss"/>
      <outline type="rss" text="TLDR AI" title="TLDR AI" xmlUrl="https://tldr.tech/api/rss/ai" htmlUrl="https://tldr.tech/ai"/>
      <outline type="rss" text="r/LocalLLaMA (top daily)" title="r/LocalLLaMA (top daily)" xmlUrl="https://www.reddit.com/r/LocalLLaMA/top/.rss?t=day" htmlUrl="https://www.reddit.com/r/LocalLLaMA/"/>
    </outline>
    <outline text="DevOps &amp; Platform" title="DevOps &amp; Platform">
      <outline type="rss" text="Kubernetes Blog" title="Kubernetes Blog" xmlUrl="https://kubernetes.io/feed.xml" htmlUrl="https://kubernetes.io/blog/"/>
      <outline type="rss" text="LearnKube" title="LearnKube" xmlUrl="https://learnkube.com/rss.xml" htmlUrl="https://learnkube.com/"/>
      <outline type="rss" text="SRE Weekly" title="SRE Weekly" xmlUrl="https://sreweekly.com/feed/" htmlUrl="https://sreweekly.com/"/>
      <outline type="rss" text="The Pragmatic Engineer" title="The Pragmatic Engineer" xmlUrl="https://newsletter.pragmaticengineer.com/feed" htmlUrl="https://newsletter.pragmaticengineer.com/"/>
      <outline type="rss" text="CNCF (YouTube)" title="CNCF (YouTube)" xmlUrl="https://www.youtube.com/feeds/videos.xml?channel_id=UCvqbFHwN-nwalWPjPUKpvTA" htmlUrl="https://www.youtube.com/@cncf"/>
      <outline type="rss" text="Red Hat Developer" title="Red Hat Developer" xmlUrl="https://developers.redhat.com/blog/feed" htmlUrl="https://developers.redhat.com/blog"/>
      <outline type="rss" text="Red Hat OpenShift Blog" title="Red Hat OpenShift Blog" xmlUrl="https://www.redhat.com/en/rss/blog/channel/red-hat-openshift" htmlUrl="https://www.redhat.com/en/blog/channel/red-hat-openshift"/>
      <outline type="rss" text="Hacker News (150+ points)" title="Hacker News (150+ points)" xmlUrl="https://hnrss.org/frontpage?points=150" htmlUrl="https://news.ycombinator.com/"/>
    </outline>
  </body>
</opml>
EOF

# --- Start -----------------------------------------------------------------
log "Pulling images and starting Miniflux ${MINIFLUX_VERSION}"
docker compose pull -q
docker compose up -d

log "Waiting for Miniflux to come up"
API="http://127.0.0.1:${PORT}"
for _ in $(seq 1 60); do
  if curl -fsS "${API}/healthcheck" >/dev/null 2>&1; then ready=1; break; fi
  sleep 2
done
[[ "${ready:-0}" == "1" ]] || die "Miniflux didn't become healthy. Check: docker compose -f ${INSTALL_DIR}/compose.yaml logs"

AUTH=(-u "${ADMIN_USERNAME}:${ADMIN_PASSWORD}")

# --- Import feeds ----------------------------------------------------------
log "Importing feeds"
if curl -fsS "${AUTH[@]}" -X POST --data-binary @feeds.opml "${API}/v1/import" >/dev/null; then
  log "Feeds imported"
else
  warn "Feed import failed — you can import ${INSTALL_DIR}/feeds.opml from Settings → Import"
fi

# --- Set timezone (best effort) -------------------------------------------
USER_ID="$(curl -fsS "${AUTH[@]}" "${API}/v1/me" 2>/dev/null | grep -o '"id":[0-9]*' | head -n1 | cut -d: -f2 || true)"
if [[ -n "${USER_ID}" ]]; then
  curl -fsS "${AUTH[@]}" -X PUT -H 'Content-Type: application/json' \
    -d "{\"timezone\":\"${TZ_NAME}\"}" "${API}/v1/users/${USER_ID}" >/dev/null 2>&1 || true
fi

# --- Kick off the first fetch ---------------------------------------------
curl -fsS "${AUTH[@]}" -X PUT "${API}/v1/feeds/refresh" >/dev/null 2>&1 || true

cat <<EOF

  Miniflux is running.

    URL:       ${BASE_URL}
    Username:  ${ADMIN_USERNAME}
    Password:  ${ADMIN_PASSWORD}

  Credentials are saved in ${INSTALL_DIR}/.env (root only).
  Change the password under Settings once you're in.

  Manage it from ${INSTALL_DIR}:
    docker compose ps                          # status
    docker compose logs -f miniflux            # logs
    docker compose pull && docker compose up -d   # update

EOF
