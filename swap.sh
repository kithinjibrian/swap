#!/usr/bin/env bash
# create-swap.sh
# Usage: sudo ./create-swap.sh 2G
# Default size if not provided: 1G

set -euo pipefail

# --- Configuration ---
SWAPSIZE="${1:-1G}"          # first arg or default 1G
SWAPFILE="/swapfile"        # swap file path
SWAPPINESS="60"             # recommended default (0-100)
# ----------------------

# Helper: print and run
run() { echo "+ $*"; "$@"; }

# Must be root
if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR: This script must be run as root (use sudo)." >&2
  exit 2
fi

# Check if there's already swap active (skip if so)
if grep -q "swap" /proc/swaps || swapon --show=NAME | grep -q '\S'; then
  echo "A swap device or file is already active. Current swap:"
  swapon --show
  echo "If you want to add more swap, either turn off existing swap with 'sudo swapoff -a' and re-run,"
  echo "or adjust this script to use a different file path."
  exit 0
fi

# Ensure enough free space available (basic check)
avail_kb=$(df --output=avail / | tail -n1)
# convert requested size to KB for rough check
size_suffix="${SWAPSIZE: -1}"
size_num="${SWAPSIZE%${size_suffix}}"
case "$size_suffix" in
  G|g) req_kb=$((size_num * 1024 * 1024));;
  M|m) req_kb=$((size_num * 1024));;
  K|k) req_kb=$((size_num));;
  *) echo "Unrecognized size suffix. Use e.g. 512M or 2G."; exit 1;;
esac

if [ "$req_kb" -gt "$avail_kb" ]; then
  echo "WARNING: Not enough free space on root filesystem to create ${SWAPSIZE} swapfile."
  echo "Available (KB): $avail_kb, requested (KB): $req_kb"
  exit 1
fi

# Create the swap file
if command -v fallocate >/dev/null 2>&1; then
  run fallocate -l "$SWAPSIZE" "$SWAPFILE"
  # Some filesystems (e.g. older btrfs) create sparse allocated files; verify size
  actual_size=$(stat -c%s "$SWAPFILE")
  if [ "$actual_size" -eq 0 ]; then
    echo "fallocate created file of size 0; falling back to dd."
    rm -f "$SWAPFILE"
    dd bs=1M if=/dev/zero of="$SWAPFILE" count=$(( ${size_num} * ( [ "${size_suffix,,}" = "g" ] && echo 1024 || echo 1 ) )) status=progress
  fi
else
  # fallback to dd if fallocate not present
  bytes_per_block=1048576 # 1M
  if [ "${size_suffix,,}" = "g" ]; then
    count=$(( size_num * 1024 ))
  elif [ "${size_suffix,,}" = "m" ]; then
    count=$(( size_num ))
  else
    echo "Unsupported size format for dd fallback. Use M or G."
    exit 1
  fi
  run dd if=/dev/zero of="$SWAPFILE" bs=$bytes_per_block count=$count status=progress
fi

# Set permissions
run chmod 600 "$SWAPFILE"

# Make swap signature
run mkswap "$SWAPFILE"

# Enable swap now
run swapon "$SWAPFILE"

echo "Swap enabled:"
swapon --show

# Persist in /etc/fstab if not already present
fstab_entry="$SWAPFILE none swap sw 0 0"
if ! grep -Fqs "$SWAPFILE" /etc/fstab; then
  echo "$fstab_entry" >> /etc/fstab
  echo "Added to /etc/fstab: $fstab_entry"
else
  echo "/etc/fstab already contains an entry for $SWAPFILE"
fi

# Tune vm.swappiness
# Save current value for note
current_swappiness=$(sysctl -n vm.swappiness || echo "unknown")
echo "Current vm.swappiness: $current_swappiness"
run sysctl -w vm.swappiness="$SWAPPINESS"

# Persist swappiness in /etc/sysctl.conf if not already set
if grep -Eq '^\s*vm\.swappiness' /etc/sysctl.conf; then
  run sed -ri "s/^\s*vm\.swappiness\s*=.*/vm.swappiness = $SWAPPINESS/" /etc/sysctl.conf
else
  echo "vm.swappiness = $SWAPPINESS" >> /etc/sysctl.conf
fi

echo
echo "Done. Summary:"
swapon --show
echo "vm.swappiness now set to $(sysctl -n vm.swappiness)"
echo
echo "To remove this swapfile later:"
echo "  sudo swapoff $SWAPFILE"
echo "  sudo rm -f $SWAPFILE"
echo "  sudo sed -i '\\#$SWAPFILE#d' /etc/fstab"
