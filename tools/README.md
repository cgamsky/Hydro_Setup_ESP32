# Proxmox Inventory

`proxmox-inventory.sh` is a read-only collection script for the Proxmox host.

Run it on the Proxmox host as `root`:

```bash
bash /path/to/proxmox-inventory.sh > /tmp/proxmox-inventory.txt
```

Then copy `/tmp/proxmox-inventory.txt` back into this project folder so Codex can analyze the exact current setup.

From this Mac, if SSH root access is enabled, the same thing can be run remotely:

```bash
ssh root@192.168.50.10 'bash -s' < tools/proxmox-inventory.sh > proxmox-inventory.txt
```

