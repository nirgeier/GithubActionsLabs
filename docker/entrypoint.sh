#!/bin/bash
# =============================================================================
# GitHub Actions Labs – Container Entrypoint
#
# 1. Creates the 'student' user with sudo access
# 2. Copies lab content fresh into /home/student/labs/
# 3. Writes helper .bashrc / .bash_profile for the user shell
# 4. Starts the Node.js web-terminal server
# =============================================================================
set -eu

BASE=/home/student/labs
CONTENT=/app/labs

# ── 1. Create user ────────────────────────────────────────────────────────────
if ! id -u student >/dev/null 2>&1; then
  useradd -m -s /bin/bash student
fi
echo "student:student" | chpasswd

# Passwordless sudo
echo "student ALL=(ALL) NOPASSWD:ALL" >/etc/sudoers.d/student
chmod 0440 /etc/sudoers.d/student

# ── 2. Copy fresh lab content ─────────────────────────────────────────────────
rm -rf "$BASE"
cp -rp "$CONTENT" "$BASE"
chmod -R a+rX "$BASE"

# ── 3. Write .bashrc ──────────────────────────────────────────────────────────
cat > /home/student/.bashrc <<'BASHRC'
# Custom prompt
export PS1='\[\033[01;32m\]student\[\033[00m\]:\[\033[01;34m\]\w\[\033[00m\]\$ '

export HOME=/home/student
export LABS=/home/student/labs

# GitHub CLI helpers
alias gha='gh workflow'
alias ghr='gh run'
alias ghjob='gh run view --log'

# General aliases
alias ll='ls -lah'
alias la='ls -laF'
alias l='ls -lAh'
alias k='kubectl'

# Show welcome message on first interactive login
if [ -z "${GHA_LABS_WELCOMED:-}" ]; then
  export GHA_LABS_WELCOMED=1
  echo ""
  echo "  Welcome to GitHub Actions Labs!"
  echo "  ────────────────────────────────────────────"
  echo "  Labs directory : \$LABS"
  echo "  gh CLI version : \$(gh --version 2>/dev/null | head -1 || echo 'not configured')"
  echo "  act version    : \$(act --version 2>/dev/null || echo 'not configured')"
  echo ""
  echo "  Start with lab 000-setup:"
  echo "    cd \$LABS/000-setup && cat README.md"
  echo ""
fi
BASHRC

# .bash_profile sources .bashrc so login shells work correctly
cat > /home/student/.bash_profile <<'PROFILE'
[ -f ~/.bashrc ] && source ~/.bashrc
cd /home/student/labs
PROFILE

chown -R student:student /home/student

# ── 4. Start web server ───────────────────────────────────────────────────────
exec node /app/server.js
