#!/usr/bin/env bash
set -euo pipefail

CONFIG="/etc/omv-data-mirror.conf"
SCRIPT="/usr/local/sbin/omv-data-mirror-to-external.sh"
DEST_ROOT="/mnt/proxmox-backups/omv-data-mirror"

usage() {
  cat <<'EOF'
Usage:
  proxmox-install-omv-data-mirror.sh --audit
  proxmox-install-omv-data-mirror.sh --install

Purpose:
  Install a file-level mirror job from selected OMV NFS mounts to the external
  Proxmox backup SSD. This complements Proxmox vzdump, which should back up
  guest system disks only.

Installed files:
  /etc/omv-data-mirror.conf
  /usr/local/sbin/omv-data-mirror-to-external.sh

Default mirrored sources:
  /mnt/omv-dev -> /mnt/proxmox-backups/omv-data-mirror/dev
  /mnt/omv-llm -> /mnt/proxmox-backups/omv-data-mirror/llm

Time Machine and Docker are not added by default because this host does not
currently have separate NFS mounts for those paths. Add them to the config
after exporting/mounting them from OMV.
EOF
}

require_root() {
  if [[ "$(id -u)" != "0" ]]; then
    echo "ERROR: run this on the Proxmox host as root." >&2
    exit 1
  fi
}

audit() {
  require_root

  echo "===== Current Storage ====="
  pvesm status || true
  echo
  df -hT /mnt/proxmox-backups /mnt/omv-dev /mnt/omv-llm 2>/dev/null || true

  echo
  echo "===== Existing Mirror Config ====="
  if [[ -f "$CONFIG" ]]; then
    cat "$CONFIG"
  else
    echo "No $CONFIG yet."
  fi

  echo
  echo "===== Existing Mirror Script ====="
  if [[ -f "$SCRIPT" ]]; then
    ls -l "$SCRIPT"
  else
    echo "No $SCRIPT yet."
  fi
}

install_files() {
  require_root
  mkdir -p "$DEST_ROOT"

  if [[ ! -f "$CONFIG" ]]; then
    cat > "$CONFIG" <<EOF
# source|destination|label
/mnt/omv-dev|${DEST_ROOT}/dev|omv-dev
/mnt/omv-llm|${DEST_ROOT}/llm|omv-llm

# Add these after creating/mounting separate OMV exports:
# /mnt/omv-timemachine|${DEST_ROOT}/timemachine|timemachine
# /mnt/omv-docker|${DEST_ROOT}/docker|docker
EOF
  fi

  cat > "$SCRIPT" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

CONFIG="${CONFIG:-/etc/omv-data-mirror.conf}"
LOG_DIR="${LOG_DIR:-/var/log/omv-data-mirror}"
MODE="${1:---dry-run}"

if [[ "$MODE" != "--dry-run" && "$MODE" != "--apply" ]]; then
  echo "Usage: omv-data-mirror-to-external.sh [--dry-run|--apply]" >&2
  exit 1
fi

mkdir -p "$LOG_DIR"
log="${LOG_DIR}/mirror-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$log") 2>&1

echo "===== OMV Data Mirror $(date -Is) ====="
echo "Mode: $MODE"
echo "Config: $CONFIG"

if ! command -v rsync >/dev/null; then
  echo "ERROR: rsync is not installed." >&2
  exit 1
fi

while IFS='|' read -r src dst label; do
  [[ -z "${src:-}" || "${src:0:1}" == "#" ]] && continue

  echo
  echo "===== ${label:-$src} ====="
  echo "Source: $src"
  echo "Dest:   $dst"

  if [[ ! -d "$src" ]]; then
    echo "SKIP: source directory does not exist"
    continue
  fi

  mkdir -p "$dst"

  args=(
    -aHAX
    --numeric-ids
    --one-file-system
    --info=stats2,progress2
    --delete-delay
    --delete-excluded
  )

  if [[ "$MODE" == "--dry-run" ]]; then
    args+=(--dry-run)
  fi

  rsync "${args[@]}" "${src%/}/" "${dst%/}/"
done < "$CONFIG"

echo
echo "Done. Log: $log"
EOF

  chmod 0755 "$SCRIPT"

  echo "Installed:"
  echo "  $CONFIG"
  echo "  $SCRIPT"
  echo
  echo "Run a dry run first:"
  echo "  $SCRIPT --dry-run"
  echo
  echo "Run the real mirror:"
  echo "  $SCRIPT --apply"
}

case "${1:-}" in
  --audit)
    audit
    ;;
  --install)
    install_files
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
