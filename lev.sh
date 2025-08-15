#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

# ============================
# Levanter Termux Installer
# - Removes sqlite3 from package.json to avoid native build failures
# - Installs minimal packages
# - Creates safe autorun helper
# ============================

info(){ printf "\e[1;32m[INFO]\e[0m %s\n" "$*"; }
warn(){ printf "\e[1;33m[WARN]\e[0m %s\n" "$*"; }
err(){ printf "\e[1;31m[ERROR]\e[0m %s\n" "$*"; }

echo "========================================="
echo "🚀 Levanter Termux Installer (sqlite3 removed)"
echo "========================================="
echo "Grant storage permission when prompted."
sleep 1

# Ask for Termux storage permission if available
if command -v termux-setup-storage >/dev/null 2>&1; then
  read -rp "Grant Termux storage permission now? (y/N): " resp
  if [[ "${resp,,}" == "y" ]]; then
    termux-setup-storage || warn "termux-setup-storage failed or was denied."
  fi
fi

# Acquire wake lock while installing
if command -v termux-wake-lock >/dev/null 2>&1; then
  termux-wake-lock || warn "termux-wake-lock failed or not allowed."
fi

# -------------------------
# Update & install packages
# -------------------------
info "Updating package lists..."
pkg update -y || warn "pkg update failed; continuing."

PKGS=( git nodejs-lts python make clang pkg-config ffmpeg wget unzip tar )
info "Installing packages: ${PKGS[*]}"
for p in "${PKGS[@]}"; do
  if pkg list-installed "$p" >/dev/null 2>&1; then
    info "$p already installed"
  else
    if ! pkg install -y "$p"; then
      warn "Failed to install $p. You may need to install it manually later."
    fi
  fi
done

# Ensure npm exists
if ! command -v npm >/dev/null 2>&1; then
  warn "npm not found. nodejs-lts should provide npm; install nodejs or nodejs-lts if missing."
fi

# Install yarn if not present
if ! command -v yarn >/dev/null 2>&1; then
  if command -v npm >/dev/null 2>&1; then
    info "Installing yarn globally via npm..."
    npm install -g yarn --no-audit --no-fund || warn "Global yarn install failed; you can 'pkg install yarn' later."
  else
    warn "npm missing; cannot install yarn automatically."
  fi
else
  info "yarn already installed"
fi

# -------------------------
# Clone or update Levanter
# -------------------------
LEV_DIR="$HOME/levanter"

if [[ -d "$LEV_DIR" ]]; then
  BACKUP="${LEV_DIR}.backup.$(date +%s)"
  info "Existing $LEV_DIR found — backing up to $BACKUP"
  mv "$LEV_DIR" "$BACKUP" || { err "Failed to back up existing folder"; exit 1; }
fi

info "Cloning Levanter repository..."
if ! git clone https://github.com/lyfe00011/levanter.git "$LEV_DIR"; then
  err "Git clone failed. Check network or git settings."
  exit 2
fi

cd "$LEV_DIR" || { err "Cannot cd to $LEV_DIR"; exit 3; }

# -------------------------
# Remove sqlite3 from package.json (if present)
# -------------------------
if [[ -f package.json ]]; then
  info "Modifying package.json to remove sqlite3 dependency (if present)..."
  # Use node to safely edit JSON
  node - <<'NODE_EOF' || { warn "node JSON edit failed"; }
const fs = require('fs');
const path = 'package.json';
if(!fs.existsSync(path)){ process.exit(0); }
let p = JSON.parse(fs.readFileSync(path,'utf8'));
['dependencies','devDependencies','optionalDependencies','peerDependencies'].forEach(k=>{
  if(p[k] && p[k]['sqlite3']){
    delete p[k]['sqlite3'];
  }
});
fs.writeFileSync(path, JSON.stringify(p, null, 2));
console.log('package.json sanitized (sqlite3 removed if it existed).');
NODE_EOF
else
  warn "No package.json found in repo root; skipping removal step."
fi

# Remove any existing node_modules to avoid stale compiled modules
if [[ -d node_modules ]]; then
  info "Removing existing node_modules to ensure clean install..."
  rm -rf node_modules
fi

# Remove pm2-docker file that previously caused EEXIST
PM2_DOCKER_PATH="/data/data/com.termux/files/usr/bin/pm2-docker"
if [[ -f "$PM2_DOCKER_PATH" ]]; then
  warn "Found existing pm2-docker - removing to avoid install conflicts."
  rm -f "$PM2_DOCKER_PATH" || warn "Could not remove $PM2_DOCKER_PATH"
fi

# -------------------------
# Install node dependencies (ignore scripts to avoid native builds)
# -------------------------
info "Installing node dependencies (ignoring lifecycle scripts to avoid native builds)..."
export npm_config_loglevel=warn

if command -v yarn >/dev/null 2>&1; then
  if ! yarn install --ignore-scripts --network-concurrency 1; then
    warn "yarn install (ignore-scripts) failed; trying npm install (ignore-scripts) fallback..."
    if ! npm install --no-audit --no-fund --ignore-scripts; then
      err "Both yarn and npm installs failed. Inspect errors and add missing system libs if needed."
      # continue without exiting to allow user to fix later
    fi
  fi
else
  warn "yarn not found; running npm install (ignore-scripts)..."
  if ! npm install --no-audit --no-fund --ignore-scripts; then
    err "npm install failed. You must debug dependency errors manually."
  fi
fi

# -------------------------
# Prepare config.env
# -------------------------
CONFIG_EXAMPLE="config.env.example"
CONFIG_OUT="config.env"
if [[ -f "$CONFIG_EXAMPLE" ]]; then
  info "Copying config.env.example to config.env and prompting for values..."
  cp "$CONFIG_EXAMPLE" "$CONFIG_OUT"
  # Extract keys and prompt for each key
  mapfile -t keys < <(grep -E "^[[:space:]]*(export[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*=" "$CONFIG_EXAMPLE" | sed -E 's/^[[:space:]]*(export[[:space:]]+)?//g' | sed -E 's/=.*//g' | tr -d ' ' | uniq)
  for k in "${keys[@]}"; do
    # Get default value from example
    default_val="$(grep -E "^[[:space:]]*(export[[:space:]]+)?${k}=" "$CONFIG_EXAMPLE" | sed -E 's/^[^=]*=//g' | sed -E 's/^["'\'' ]+|["'\'' ]+$//g' | head -n1 || true)"
    read -rp "Enter value for ${k} (leave empty to keep default: ${default_val}): " input
    if [[ -z "$input" && -n "$default_val" ]]; then
      value="$default_val"
    else
      value="$input"
    fi
    if grep -qE "^${k}=" "$CONFIG_OUT" 2>/dev/null; then
      sed -i "s%^${k}=.*%${k}=${value}%g" "$CONFIG_OUT"
    else
      echo "${k}=${value}" >> "$CONFIG_OUT"
    fi
  done
else
  info "No config.env.example found. Creating minimal config.env and prompting for common keys."
  : > "$CONFIG_OUT"
  read -rp "Enter SESSION_ID (can be empty): " session_id
  read -rp "Enter BOT_TOKEN (can be empty): " bot_token
  [[ -n "$session_id" ]] && echo "SESSION_ID=$session_id" >> "$CONFIG_OUT"
  [[ -n "$bot_token" ]] && echo "BOT_TOKEN=$bot_token" >> "$CONFIG_OUT"
fi

info "config.env prepared at $LEV_DIR/$CONFIG_OUT"

# -------------------------
# Create autorun helper
# -------------------------
AUTORUN_SCRIPT="$LEV_DIR/autorun_levanter.sh"
info "Creating autorun helper at $AUTORUN_SCRIPT"

cat > "$AUTORUN_SCRIPT" <<'AUTORUN_EOF'
#!/usr/bin/env bash
# autorun helper for Levanter - safe: avoids duplicate launches
cd "$HOME/levanter" || exit 0

# If node process for levanter already running, exit
if pgrep -f "node .*levanter" >/dev/null 2>&1; then
  exit 0
fi

# Prefer pm2 if available
if command -v pm2 >/dev/null 2>&1; then
  # Try to resurrect saved pm2 processes; if none, start the bot via pm2
  pm2 resurrect >/dev/null 2>&1 || pm2 start npm --name levanter -- start >/dev/null 2>&1 || true
  pm2 save >/dev/null 2>&1 || true
else
  # Start in background via nohup to avoid blocking shell
  nohup npm start >/dev/null 2>&1 &
fi
AUTORUN_EOF

chmod +x "$AUTORUN_SCRIPT"

# Add autorun call to ~/.bashrc if not already present
BASHRC="$HOME/.bashrc"
AUTORUN_MARKER="# levanter autorun (added by lev.sh)"
if ! grep -Fxq "$AUTORUN_MARKER" "$BASHRC" 2>/dev/null; then
  info "Adding autorun launcher to $BASHRC"
  {
    echo ""
    echo "$AUTORUN_MARKER"
    echo "bash \"$AUTORUN_SCRIPT\" >/dev/null 2>&1 &"
  } >> "$BASHRC"
else
  info "Autorun already present in $BASHRC"
fi

# -------------------------
# Optional: prompt to install pm2
# -------------------------
read -rp "Do you want to install pm2 globally to manage the bot in background? (y/N): " want_pm2
if [[ "${want_pm2,,}" == "y" ]]; then
  if command -v npm >/dev/null 2>&1; then
    info "Installing pm2 globally..."
    npm install -g pm2 --no-audit --no-fund || warn "pm2 install failed. You can still start the bot manually with 'npm start'."
    info "If you install pm2, use: pm2 start npm --name levanter -- start ; pm2 save"
  else
    warn "npm not available; cannot install pm2."
  fi
fi

# -------------------------
# Final message
# -------------------------
info "Installation finished (or reached point requiring manual fix)."
echo
echo "Next steps:"
echo "  1) Review the config file: $LEV_DIR/$CONFIG_OUT"
echo "  2) Start the bot manually the first time to ensure it runs: cd $LEV_DIR && npm start"
echo "  3) Termux will auto-run the autorun helper on shell start (app open). It will use pm2 if installed, otherwise it starts npm in background."
echo
info "If yarn/npm install failed due to other native modules, paste the yarn/npm error output and I will help add minimal libs or alternatives."

# Release wake lock if available
if command -v termux-wake-unlock >/dev/null 2>&1; then
  termux-wake-unlock || true
fi

exit 0
