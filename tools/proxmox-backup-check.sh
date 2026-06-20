#!/usr/bin/env bash
set -u

section() {
  printf '\n\n===== %s =====\n' "$1"
}

run() {
  section "$1"
  shift
  "$@" 2>&1 || true
}

run "Generated At" date -Is
run "Backup Job Config" cat /etc/pve/jobs.cfg
run "VZDump Cron" cat /etc/pve/vzdump.cron
run "Backup Storage Status" pvesm status
run "Backup Storage Filesystems" bash -lc "df -hT /mnt/proxmox-backups /var/lib/vz 2>/dev/null"
run "Backup Directory Listing" bash -lc "find /mnt/proxmox-backups -maxdepth 4 -type f -printf '%TY-%Tm-%Td %TH:%TM %s %p\n' 2>/dev/null | sort | tail -200"
run "Backup Storage Tree" bash -lc "find /mnt/proxmox-backups -maxdepth 3 -type d -print 2>/dev/null | sort"
run "Recent Proxmox Tasks" bash -lc "find /var/log/pve/tasks -type f -mtime -45 -print 2>/dev/null | sort | tail -100 | while read -r f; do echo '---' \$f; tail -80 \"\$f\"; done"
run "Recent VZDump Logs Under Var Log" bash -lc "find /var/log -maxdepth 4 -type f \\( -iname '*vzdump*' -o -iname '*backup*' \\) -mtime -90 -print 2>/dev/null | sort | while read -r f; do echo '---' \$f; tail -120 \"\$f\"; done"
run "Scheduler Journal" journalctl --no-pager -u pvescheduler --since "45 days ago"
run "PVE Daemon Backup Mentions" bash -lc "journalctl --no-pager --since '45 days ago' | grep -Ei 'vzdump|backup|backup-8170cd3e|TASK ERROR|TASK OK|failed|error' | tail -500"
run "Guest List" bash -lc "qm list; pct list"
