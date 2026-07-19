# Proxmox Backup Strategy

Goal:

- Internal SSD: Proxmox OS and VM/LXC root disks.
- Internal 1TB HDD: primary OMV data storage.
- External 1TB SSD: Proxmox guest backups plus file-level mirror of important OMV data.

## Stage 1: Fix Proxmox vzdump Scope

Audit:

```bash
cd /Users/christophergamsky/Documents/Python_Code/esphome
ssh root@192.168.50.10 'bash -s -- --audit' < tools/proxmox-fix-vzdump-scope.sh
```

Apply:

```bash
ssh root@192.168.50.10 'bash -s -- --apply' < tools/proxmox-fix-vzdump-scope.sh
```

This adds `backup=0` to VM 100's `scsi1` passthrough disk, so Proxmox backs up the OMV system disk but not the 1TB data disk.

## Stage 2: Install OMV Data Mirror

Install the mirror helper on Proxmox:

```bash
ssh root@192.168.50.10 'bash -s -- --install' < tools/proxmox-install-omv-data-mirror.sh
```

Dry run:

```bash
ssh root@192.168.50.10 '/usr/local/sbin/omv-data-mirror-to-external.sh --dry-run'
```

Apply:

```bash
ssh root@192.168.50.10 '/usr/local/sbin/omv-data-mirror-to-external.sh --apply'
```

Default mirrored paths are:

- `/mnt/omv-dev` -> `/mnt/proxmox-backups/omv-data-mirror/dev`
- `/mnt/omv-llm` -> `/mnt/proxmox-backups/omv-data-mirror/llm`

Time Machine and Docker are now separately exported from OMV and mounted on
Proxmox as `/mnt/omv-timemachine` and `/mnt/omv-docker`. All four NFS shares use
systemd automounts (`x-systemd.automount` in `/etc/fstab`) so they mount
on-demand and survive the NAS booting after the host. Add the two new paths to
the mirror once you want them included in the external backup.

## Stage 3: Verify Next Proxmox Backup

After the next scheduled backup, rerun:

```bash
ssh root@192.168.50.10 'bash -s' < tools/proxmox-backup-check.sh > proxmox-backup-check.txt
```

Expected result:

- VM 100 system disk succeeds.
- CT 101 succeeds.
- CT 102 succeeds.
- Overall job no longer ends with `TASK ERROR`.

## Not Yet Automated

Do not delete the old 580GB OMV backup until a successful post-fix backup exists and the OMV data mirror is verified.
