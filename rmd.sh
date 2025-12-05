#!/usr/bin/env bash
# Uninstalls Docker Engine from Ubuntu
# Includes options to remove data and configurations
set -euo pipefail

echo "=== Docker Uninstall Script ==="
echo

# Must be root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run with root privileges (use sudo)." >&2
  exit 1
fi

# Determine the user who ran sudo
REAL_USER="${SUDO_USER:-$(whoami)}"

# Ask about data removal
echo "This script will uninstall Docker Engine."
echo
read -p "Do you also want to DELETE all Docker data (images, containers, volumes)? [y/N]: " -n 1 -r
echo
DELETE_DATA=false
if [[ $REPLY =~ ^[Yy]$ ]]; then
  DELETE_DATA=true
  echo "⚠️  WARNING: All Docker images, containers, volumes, and networks will be deleted!"
  read -p "Are you absolutely sure? Type 'yes' to confirm: " CONFIRM
  if [ "$CONFIRM" != "yes" ]; then
    echo "Aborting data deletion. Will only uninstall packages."
    DELETE_DATA=false
  fi
fi

echo
echo "[1/5] Stopping Docker services..."
systemctl stop docker.socket 2>/dev/null || true
systemctl stop docker 2>/dev/null || true
systemctl stop containerd 2>/dev/null || true

echo "[2/5] Removing Docker packages..."
apt-get purge -y \
  docker-ce \
  docker-ce-cli \
  containerd.io \
  docker-buildx-plugin \
  docker-compose-plugin \
  docker-ce-rootless-extras \
  2>/dev/null || true

# Remove any other Docker-related packages
apt-get purge -y docker docker-engine docker.io runc 2>/dev/null || true

echo "[3/5] Removing Docker repository and GPG key..."
rm -f /etc/apt/sources.list.d/docker.list
rm -f /etc/apt/keyrings/docker.gpg
rm -f /usr/share/keyrings/docker-archive-keyring.gpg

echo "[4/5] Cleaning up unused packages..."
apt-get autoremove -y
apt-get autoclean -y

if [ "$DELETE_DATA" = true ]; then
  echo "[5/5] Deleting Docker data directories..."
  
  # Stop any remaining processes
  pkill -9 docker 2>/dev/null || true
  pkill -9 containerd 2>/dev/null || true
  
  # Remove data directories
  echo "  - Removing /var/lib/docker..."
  rm -rf /var/lib/docker
  
  echo "  - Removing /var/lib/containerd..."
  rm -rf /var/lib/containerd
  
  echo "  - Removing /var/run/docker..."
  rm -rf /var/run/docker
  
  echo "  - Removing /var/run/docker.sock..."
  rm -f /var/run/docker.sock
  
  echo "  - Removing /etc/docker..."
  rm -rf /etc/docker
  
  echo "  - Removing user Docker config..."
  rm -rf /home/$REAL_USER/.docker 2>/dev/null || true
  
  # Remove AppArmor profiles
  echo "  - Removing AppArmor profiles..."
  rm -f /etc/apparmor.d/docker* 2>/dev/null || true
  
  echo "✓ All Docker data has been deleted."
else
  echo "[5/5] Skipping data deletion..."
  echo
  echo "ℹ️  Docker data directories preserved:"
  echo "   - /var/lib/docker"
  echo "   - /var/lib/containerd"
  echo "   - /etc/docker"
  echo
  echo "   To manually remove them later, run:"
  echo "   sudo rm -rf /var/lib/docker /var/lib/containerd /etc/docker"
fi

# Optionally remove user from docker group
echo
read -p "Remove user '$REAL_USER' from docker group? [y/N]: " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
  if getent group docker >/dev/null 2>&1; then
    gpasswd -d "$REAL_USER" docker 2>/dev/null || true
    echo "✓ User removed from docker group"
    echo "  (You may need to log out and back in)"
  fi
fi

echo
echo "=== Uninstall Complete ==="
echo
echo "Docker has been uninstalled from your system."
if [ "$DELETE_DATA" = false ]; then
  echo "Docker data was preserved and can be restored if you reinstall."
fi
echo
echo "Done!"