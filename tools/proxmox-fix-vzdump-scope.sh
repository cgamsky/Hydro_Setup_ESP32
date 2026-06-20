#!/usr/bin/env bash
set -euo pipefail

VMID="${VMID:-100}"
CONF="/etc/pve/qemu-server/${VMID}.conf"
BACKUP_DIR="/root/proxmox-backup-fix"

usage() {
  cat <<'EOF'
Usage:
  proxmox-fix-vzdump-scope.sh --audit
  proxmox-fix-vzdump-scope.sh --apply

Purpose:
  Prevent Proxmox vzdump from trying to include the OMV VM's 1TB passthrough
  data disk. This keeps Proxmox guest backups focused on system disks.

What --apply changes:
  - Backs up /etc/pve/qemu-server/100.conf to /root/proxmox-backup-fix/
  - Adds backup=0 to VM 100's scsi1 line if missing

It does not delete old backups.
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

  echo "===== VM ${VMID} Config ====="
  if [[ ! -f "$CONF" ]]; then
    echo "ERROR: missing $CONF" >&2
    exit 1
  fi
  cat "$CONF"

  echo
  echo "===== Current scsi1 Line ====="
  grep '^scsi1:' "$CONF" || {
    echo "ERROR: VM ${VMID} has no scsi1 line; nothing to fix." >&2
    exit 1
  }

  echo
  echo "===== Interpretation ====="
  if grep '^scsi1:.*backup=0' "$CONF" >/dev/null; then
    echo "OK: scsi1 already has backup=0. Proxmox should not include the passthrough data disk in vzdump."
  else
    echo "NEEDS CHANGE: scsi1 does not have backup=0. Proxmox may try to back up the 1TB OMV data disk."
  fi
}

apply_fix() {
  require_root
  audit

  if grep '^scsi1:.*backup=0' "$CONF" >/dev/null; then
    echo
    echo "No change needed."
    return
  fi

  mkdir -p "$BACKUP_DIR"
  backup_file="${BACKUP_DIR}/${VMID}.conf.$(date +%Y%m%d-%H%M%S)"
  cp -a "$CONF" "$backup_file"

  python3 - "$CONF" <<'PY'
from pathlib import Path
import sys

path = Path(sys.argv[1])
lines = path.read_text().splitlines()
out = []
changed = False

for line in lines:
    if line.startswith("scsi1:") and "backup=" not in line:
        line = f"{line},backup=0"
        changed = True
    out.append(line)

if not changed:
    raise SystemExit("No scsi1 line changed")

path.write_text("\n".join(out) + "\n")
PY

  echo
  echo "Changed $CONF"
  echo "Original saved at $backup_file"
  echo
  echo "===== Updated scsi1 Line ====="
  grep '^scsi1:' "$CONF"
}

case "${1:-}" in
  --audit)
    audit
    ;;
  --apply)
    apply_fix
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    usage >&2
    exit 1
    ;;
esac
