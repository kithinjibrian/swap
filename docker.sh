#!/usr/bin/env bash
# Usage: sudo ./install-docker.sh [VERSION]
# Example: sudo ./install-docker.sh 24.0.7
set -euo pipefail

DOCKER_VERSION="${1:-latest}"

echo "=== Docker Install + Non-root Configuration Script ==="
echo "Target version: $DOCKER_VERSION"

# Must be root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run with root privileges (use sudo)." >&2
  exit 1
fi

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

apt-get update -y

echo "[6/7] Installing Docker Engine..."

if [ "$DOCKER_VERSION" = "latest" ]; then
  # Install latest version
  apt-get install -y docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin
else
  # Find the full version string
  echo "Available versions:"
  apt-cache madison docker-ce | grep "$DOCKER_VERSION" | head -5
  
  # Build version string (format: 5:VERSION~ubuntu.RELEASE~CODENAME)
  VERSION_STRING=$(apt-cache madison docker-ce | grep "$DOCKER_VERSION" | head -1 | awk '{print $3}')
  
  if [ -z "$VERSION_STRING" ]; then
    echo "ERROR: Version $DOCKER_VERSION not found!" >&2
    echo "Available versions:" >&2
    apt-cache madison docker-ce | head -10 >&2
    exit 1
  fi
  
  echo "Installing Docker CE version: $VERSION_STRING"
  apt-get install -y \
    docker-ce=$VERSION_STRING \
    docker-ce-cli=$VERSION_STRING \
    containerd.io \
    docker-buildx-plugin \
    docker-compose-plugin
fi

echo "[7/7] Enabling Docker services..."
systemctl enable docker
systemctl start docker

echo "Configuring Docker for non-root usage..."
if ! getent group docker >/dev/null 2>&1; then
  groupadd docker
fi
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