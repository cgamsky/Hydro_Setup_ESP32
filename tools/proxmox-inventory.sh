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
run "Hostname" hostnamectl
run "Kernel" uname -a
run "Proxmox Version" pveversion -v
run "CPU" lscpu
run "Memory" free -h
run "Block Devices" lsblk -o NAME,SIZE,TYPE,FSTYPE,FSVER,LABEL,UUID,MOUNTPOINTS,MODEL,SERIAL
run "Filesystems" df -hT
run "Mount Tree" findmnt
run "FSTAB" cat /etc/fstab
run "Network Addresses" ip -brief addr
run "Network Routes" ip route
run "Bridge/VLAN Details" bridge link
run "Proxmox Storage Status" pvesm status
run "Proxmox Storage Config" cat /etc/pve/storage.cfg
run "VM List" qm list
run "Container List" pct list

section "VM Configs"
for id in $(qm list 2>/dev/null | awk 'NR > 1 {print $1}'); do
  printf '\n--- VM %s ---\n' "$id"
  qm config "$id" 2>&1 || true
done

section "Container Configs"
for id in $(pct list 2>/dev/null | awk 'NR > 1 {print $1}'); do
  printf '\n--- CT %s ---\n' "$id"
  pct config "$id" 2>&1 || true
done

run "NFS Mounts" bash -lc "findmnt -t nfs,nfs4; mount | grep -Ei 'nfs|omv|workspace|llm'"
run "Exports Visible From PVE" bash -lc "command -v showmount >/dev/null && showmount -e 192.168.50.228 || true"
run "USB Devices" bash -lc "command -v lsusb >/dev/null && lsusb || true"
run "Backup Jobs" cat /etc/pve/jobs.cfg
run "Recent VZDump Logs" bash -lc "find /var/log -maxdepth 2 -type f -iname '*vzdump*' -print | sort | tail -20"
run "Running Services" systemctl --no-pager --type=service --state=running
run "Listening Ports" ss -tulpn
run "Important PVE Files" bash -lc "ls -la /etc/pve; ls -la /etc/pve/nodes/$(hostname)"
