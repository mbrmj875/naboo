#!/usr/bin/env bash
# نشر Evolution خلف Traefik HTTPS — حل دائم (بدون فتح 8080 للعالم)
# التشغيل: من كونسول Hostinger كـ root:
#   bash /tmp/deploy-evolution-https.sh
# أو: curl -fsSL ... | bash   (إن رُفع الملف)
set -euo pipefail

EVO_DIR="${EVO_DIR:-/docker/naboo-evolution}"
EVO_HOST="${EVO_HOST:-evo-nrwn.srv1769126.hstgr.cloud}"
EVO_KEY="${EVO_KEY:-Ev0_Naboo_72aB91cD3eF4gH5iJ}"
MGR_USER="${MGR_USER:-naboo_admin}"
MGR_PASS="${MGR_PASS:-NaBoo_EvoMgr_2026!Secure}"
SSH_PUBKEY="${SSH_PUBKEY:-ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMc9vQJErhJ1cPBj9PjD69MMvBBHSK04j0FNW42G1X0z mohamed123@mohameds-MacBook-Air.local}"

echo "=== [1/8] SSH key + firewall basics ==="
mkdir -p /root/.ssh
chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys
grep -qxF "$SSH_PUBKEY" /root/.ssh/authorized_keys || echo "$SSH_PUBKEY" >> /root/.ssh/authorized_keys
ufw allow OpenSSH >/dev/null 2>&1 || true
ufw allow 22/tcp >/dev/null 2>&1 || true
ufw allow 80/tcp >/dev/null 2>&1 || true
ufw allow 443/tcp >/dev/null 2>&1 || true

echo "=== [2/8] Detect Traefik network ==="
if ! docker ps --format '{{.Names}}' | grep -qx 'traefik-traefik-1'; then
  echo "ERROR: traefik-traefik-1 not running" >&2
  exit 1
fi
TRAEFIK_NET="$(docker inspect traefik-traefik-1 --format '{{range $k,$v := .NetworkSettings.Networks}}{{println $k}}{{end}}' | awk 'NF{print; exit}')"
if [[ -z "${TRAEFIK_NET}" ]]; then
  echo "ERROR: could not detect Traefik network" >&2
  exit 1
fi
echo "Traefik network: ${TRAEFIK_NET}"

# أنشئ alias اسم ثابت إن لزم (compose يستخدم traefik_proxy كـ external name)
if [[ "${TRAEFIK_NET}" != "traefik_proxy" ]]; then
  docker network create traefik_proxy >/dev/null 2>&1 || true
  # اربط Traefik بشبكة traefik_proxy إن لم يكن عليها
  docker network connect traefik_proxy traefik-traefik-1 2>/dev/null || true
  TRAEFIK_NET_FOR_COMPOSE="traefik_proxy"
else
  TRAEFIK_NET_FOR_COMPOSE="traefik_proxy"
fi

echo "=== [3/8] Restart Traefik (إصلاح 80/443 إن علّق) ==="
docker restart traefik-traefik-1 >/dev/null
sleep 3

echo "=== [4/8] Write compose in ${EVO_DIR} ==="
mkdir -p "${EVO_DIR}"
# احتفظ بنسخة من البيانات عبر volumes الموجودة
if [[ -f "${EVO_DIR}/docker-compose.yml" ]]; then
  cp -a "${EVO_DIR}/docker-compose.yml" "${EVO_DIR}/docker-compose.yml.bak.$(date +%s)"
fi

# bcrypt hash لـ Basic Auth (مضاعفة $ لـ compose)
if command -v htpasswd >/dev/null 2>&1; then
  AUTH_USERS="$(htpasswd -nbB "${MGR_USER}" "${MGR_PASS}" | sed -e 's/\$/\$\$/g')"
else
  apt-get update -qq && apt-get install -y -qq apache2-utils >/dev/null
  AUTH_USERS="$(htpasswd -nbB "${MGR_USER}" "${MGR_PASS}" | sed -e 's/\$/\$\$/g')"
fi

cat > "${EVO_DIR}/docker-compose.yml" <<EOF
services:
  postgres:
    image: postgres:15-alpine
    container_name: naboo-evolution-db
    restart: unless-stopped
    environment:
      POSTGRES_USER: evolution
      POSTGRES_PASSWORD: "Naboo_Evo_DB_2026!Secure"
      POSTGRES_DB: evolution
    volumes:
      - postgres_data:/var/lib/postgresql/data
    networks:
      - default

  evolution-api:
    image: evoapicloud/evolution-api:v2.3.7
    container_name: naboo-evolution
    restart: unless-stopped
    depends_on:
      - postgres
    expose:
      - "8080"
    environment:
      AUTHENTICATION_API_KEY: "${EVO_KEY}"
      SERVER_URL: "https://${EVO_HOST}"
      SERVER_TYPE: "http"
      DATABASE_ENABLED: "true"
      DATABASE_PROVIDER: "postgresql"
      DATABASE_CONNECTION_URI: "postgresql://evolution:Naboo_Evo_DB_2026!Secure@postgres:5432/evolution?schema=public"
      CACHE_REDIS_ENABLED: "false"
      CACHE_LOCAL_ENABLED: "true"
      NODE_OPTIONS: "--dns-result-order=ipv4first"
    volumes:
      - evolution_data:/evolution/instances
    networks:
      - default
      - traefik_proxy
    labels:
      - traefik.enable=true
      - traefik.http.routers.evo-api.rule=Host(\`${EVO_HOST}\`) && !PathPrefix(\`/manager\`)
      - traefik.http.routers.evo-api.entrypoints=websecure
      - traefik.http.routers.evo-api.tls.certresolver=letsencrypt
      - traefik.http.routers.evo-api.service=evo-api
      - traefik.http.services.evo-api.loadbalancer.server.port=8080
      - traefik.http.routers.evo-mgr.rule=Host(\`${EVO_HOST}\`) && PathPrefix(\`/manager\`)
      - traefik.http.routers.evo-mgr.entrypoints=websecure
      - traefik.http.routers.evo-mgr.tls.certresolver=letsencrypt
      - traefik.http.routers.evo-mgr.service=evo-api
      - traefik.http.routers.evo-mgr.middlewares=evo-mgr-auth
      - traefik.http.middlewares.evo-mgr-auth.basicauth.users=${AUTH_USERS}

volumes:
  postgres_data:
  evolution_data:

networks:
  default:
    name: naboo-evolution_default
  traefik_proxy:
    external: true
    name: ${TRAEFIK_NET_FOR_COMPOSE}
EOF

echo "=== [5/8] docker compose up ==="
cd "${EVO_DIR}"
docker compose up -d
sleep 5

# تأكد أن Evolution على شبكة Traefik الحقيقية أيضاً (اكتشاف تلقائي)
docker network connect "${TRAEFIK_NET}" naboo-evolution 2>/dev/null || true
docker network connect naboo-evolution_default n8n-nrwn-n8n-1 2>/dev/null || true

echo "=== [6/8] UFW: أغلق 8080 عن العالم ==="
# احذف allows القديمة لـ 8080 ثم ارفض
while ufw status numbered | grep -q '8080/tcp'; do
  NUM="$(ufw status numbered | grep '8080/tcp' | head -1 | sed -n 's/^\[\s*\([0-9]*\)\].*/\1/p')"
  [[ -n "${NUM}" ]] || break
  yes | ufw delete "${NUM}" >/dev/null || break
done
ufw deny 8080/tcp >/dev/null 2>&1 || true
ufw --force enable >/dev/null 2>&1 || true

echo "=== [7/8] Keep n8n on internal Evolution URL ==="
if [[ -f /docker/n8n-nrwn/.env ]]; then
  sed -i 's|^EVOLUTION_BASE_URL=.*|EVOLUTION_BASE_URL=http://naboo-evolution:8080|' /docker/n8n-nrwn/.env
  grep -q '^EVOLUTION_BASE_URL=' /docker/n8n-nrwn/.env || echo 'EVOLUTION_BASE_URL=http://naboo-evolution:8080' >> /docker/n8n-nrwn/.env
  # ثبّت منفذ 5678 إن أمكن
  if [[ -f /docker/n8n-nrwn/docker-compose.yml ]]; then
    sed -i 's/- 5678/- "5678:5678"/' /docker/n8n-nrwn/docker-compose.yml 2>/dev/null || true
  fi
  cd /docker/n8n-nrwn && docker compose up -d
  docker network connect naboo-evolution_default n8n-nrwn-n8n-1 2>/dev/null || true
fi

echo "=== [8/8] Verify ==="
sleep 8
echo "--- containers ---"
docker ps --format '{{.Names}}\t{{.Status}}\t{{.Ports}}' | grep -E 'evolution|n8n|traefik' || true
echo "--- local evolution ---"
curl -sS -m 8 -o /tmp/evo_local.json -w "local_http:%{http_code}\n" \
  -H "apikey: ${EVO_KEY}" http://127.0.0.1:8080/instance/fetchInstances || echo "local_8080:unreachable(expected_if_unbound)"
# من داخل شبكة docker
docker exec n8n-nrwn-n8n-1 wget -qO- --timeout=8 \
  --header="apikey: ${EVO_KEY}" \
  http://naboo-evolution:8080/instance/fetchInstances 2>&1 | head -c 180 || true
echo
echo "--- https public ---"
curl -skS -m 20 -o /tmp/evo_https.json -w "https:%{http_code}\n" \
  -H "apikey: ${EVO_KEY}" "https://${EVO_HOST}/instance/fetchInstances" || true
head -c 200 /tmp/evo_https.json 2>/dev/null; echo
echo "--- ufw ---"
ufw status numbered | head -40
echo
echo "DONE"
echo "PUBLIC_URL=https://${EVO_HOST}"
echo "MANAGER_URL=https://${EVO_HOST}/manager"
echo "MANAGER_USER=${MGR_USER}"
echo "MANAGER_PASS=${MGR_PASS}"
echo "Set Supabase: EVOLUTION_BASE_URL=https://${EVO_HOST}"
echo "Set Supabase: EVOLUTION_API_KEY=${EVO_KEY}"
