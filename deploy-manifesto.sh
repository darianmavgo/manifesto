#!/usr/bin/env bash
# deploy-manifesto.sh
# Provisions Cloudflare Pages and GitHub repository for manifesto.darianhickman.com

set -euo pipefail

# ─── CONFIG ──────────────────────────────────────────────────────────────────
ZONE_NAME="darianhickman.com"
SUBDOMAIN="manifesto"
FULL_DOMAIN="${SUBDOMAIN}.${ZONE_NAME}"
PAGES_PROJECT="manifesto-web"
REPO_NAME="manifesto"
REPO_ORG="darianmavgo"
STATE_FILE="$(pwd)/.manifesto-state"
touch "${STATE_FILE}"

# Utilities
GREEN='\033[0;32m'; RED='\033[0;31m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; NC='\033[0m'
ok()   { echo -e "${GREEN}✅ $*${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $*${NC}"; }
fail() { echo -e "${RED}❌ $*${NC}" >&2; exit 1; }
step() { echo -e "\n${YELLOW}▶ $*${NC}"; }
skip() { echo -e "${CYAN}⏭  $* (already done — skipping)${NC}"; }

# State Functions
step_done() { grep -qxF "$1" "${STATE_FILE}" 2>/dev/null; }
mark_done() { echo "$1" >> "${STATE_FILE}"; }
state_get() { grep "^${1}=" "${STATE_FILE}" 2>/dev/null | cut -d= -f2- || echo ""; }
state_set() { 
  grep -v "^${1}=" "${STATE_FILE}" > "${STATE_FILE}.tmp" 2>/dev/null || true
  echo "${1}=${2}" >> "${STATE_FILE}.tmp"
  mv "${STATE_FILE}.tmp" "${STATE_FILE}"
}

# ─── 1. DEPENDENCIES ──────────────────────────────────────────────────────────
step "Checking CLI tools..."
for cmd in wrangler gh jq curl git npm; do
  command -v "$cmd" &>/dev/null || fail "$cmd is required."
done
ok "All tools found."

# ─── 2. DNS/CF SECRETS ────────────────────────────────────────────────────────
_saved_cf=$(state_get "CF_DNS_TOKEN")
if [[ -n "${CF_DNS_TOKEN:-}" ]]; then
  ok "CF_DNS_TOKEN found in ENV."
elif [[ -n "$_saved_cf" ]]; then
  export CF_DNS_TOKEN="$_saved_cf"
  ok "CF_DNS_TOKEN loaded from state."
else
  echo -e "${YELLOW}Need Cloudflare API Token to set CNAME for ${FULL_DOMAIN}${NC}"
  read -rp "Paste CF API Token (Enter=skip DNS): " input_token </dev/tty
  export CF_DNS_TOKEN="${input_token// /}"
  state_set "CF_DNS_TOKEN" "${CF_DNS_TOKEN:-}"
fi

# Resolve Zone ID
ZONE_ID=""
if [[ -n "${CF_DNS_TOKEN:-}" ]]; then
  ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=${ZONE_NAME}" \
    -H "Authorization: Bearer ${CF_DNS_TOKEN}" \
    -H "Content-Type: application/json" | jq -r '.result[0].id // empty')
fi

# ─── 3. BUILD SITE ────────────────────────────────────────────────────────────
if step_done "site_built"; then skip "Site built"; else
  step "Building VitePress static site..."
  npm run docs:build
  mark_done "site_built"
fi

# ─── 4. DEPLOY CLOUDFLARE PAGES ───────────────────────────────────────────────
if step_done "pages_deployed"; then skip "Pages deployed"; else
  step "Deploying to Cloudflare Pages (${PAGES_PROJECT})..."
  wrangler pages project create "${PAGES_PROJECT}" --production-branch main 2>/dev/null || true
  wrangler pages deploy .vitepress/dist --project-name="${PAGES_PROJECT}" --branch=main
  ok "Pages deployed to https://${PAGES_PROJECT}.pages.dev"
  mark_done "pages_deployed"
fi

# ─── 5. DNS CNAME ─────────────────────────────────────────────────────────────
if step_done "dns_configured"; then skip "DNS configured"; else
  if [[ -n "${CF_DNS_TOKEN:-}" ]] && [[ -n "$ZONE_ID" ]]; then
    step "Adding DNS CNAME: ${SUBDOMAIN}.${ZONE_NAME} → ${PAGES_PROJECT}.pages.dev ..."
    
    EXISTING=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records?type=CNAME&name=${FULL_DOMAIN}" \
      -H "Authorization: Bearer ${CF_DNS_TOKEN}" -H "Content-Type: application/json" | jq -r '.result | length')

    if [[ "$EXISTING" == "0" ]]; then
      curl -s -X POST "https://api.cloudflare.com/client/v4/zones/${ZONE_ID}/dns_records" \
        -H "Authorization: Bearer ${CF_DNS_TOKEN}" -H "Content-Type: application/json" \
        --data "{\"type\":\"CNAME\",\"name\":\"${SUBDOMAIN}\",\"content\":\"${PAGES_PROJECT}.pages.dev\",\"proxied\":true}" > /dev/null
      ok "CNAME added."
    else
      warn "CNAME already exists."
    fi
    wrangler pages domain add "${PAGES_PROJECT}" "${FULL_DOMAIN}" 2>/dev/null || true
    mark_done "dns_configured"
  else
    warn "Skipping DNS. Add CNAME manually."
  fi
fi

# ─── 6. GITHUB SETUP ──────────────────────────────────────────────────────────
if step_done "github_pushed"; then skip "GitHub pushed"; else
  step "Setting up GitHub tracking..."
  [ ! -d ".git" ] && git init
  echo -e ".manifesto-state\n.vitepress/cache/\n.vitepress/dist/\nnode_modules/" > .gitignore
  git add .
  if ! git diff --cached --quiet; then
    git commit -m "feat: initial manifesto deployment"
  fi
  
  if ! gh repo view "${REPO_ORG}/${REPO_NAME}" &>/dev/null; then
    gh repo create "${REPO_ORG}/${REPO_NAME}" --public --source=. --remote=origin --push
    ok "Repo created and pushed."
  else
    git remote add origin "https://github.com/${REPO_ORG}/${REPO_NAME}.git" 2>/dev/null || true
    git push origin main 2>/dev/null || git push origin HEAD:main
    ok "Pushed to existing repo."
  fi
  mark_done "github_pushed"
fi

echo -e "\n${GREEN}🎉 Successfully published Manifesto to https://${FULL_DOMAIN}!${NC}"
