#!/usr/bin/env bash
# Installs Docker Engine on Ubuntu
# Also configures Docker to run WITHOUT sudo

set -euo pipefail

echo "=== Docker Install + Non-root Configuration Script ==="

# Must be root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run with root privileges (use sudo)." >&2
  exit 1
fi

# Determine the user who ran sudo
REAL_USER="${SUDO_USER:-$(whoami)}"

echo "[1/7] Updating package index..."
apt-get update -y

echo "[2/7] Removing old Docker versions (if any)..."
apt-get remove -y docker docker-engine docker.io containerd runc 2>/dev/null || true

echo "[3/7] Installing prerequisites..."
apt-get install -y ca-certificates curl gnupg lsb-release

echo "[4/7] Adding Docker GPG key..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
    gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo "[5/7] Adding Docker repository..."
ARCH="$(dpkg --print-architecture)"
RELEASE="$(lsb_release -cs)"

echo \
"deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${RELEASE} stable" \
| tee /etc/apt/sources.list.d/docker.list > /dev/null

echo "[6/7] Installing Docker Engine..."
apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "[7/7] Enabling Docker services..."
systemctl enable docker
systemctl start docker

echo "Configuring Docker for non-root usage…"

# Create docker group if missing
if ! getent group docker >/dev/null 2>&1; then
  groupadd docker
fi

# Add your real user
usermod -aG docker "$REAL_USER"

echo
echo "=== Installation Complete ==="
echo "Docker version: $(docker --version)"
echo "Compose version: $(docker compose version)"
echo
echo "User '$REAL_USER' has been added to the 'docker' group."
echo
echo "➡ IMPORTANT: Log out and back in to apply the group change."
echo "   After that, you can run docker commands *without sudo*."
echo
echo "Done!"
