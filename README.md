# Hydro Setup ESP32

ESPHome and Home Assistant configuration for an ESP32 hydroponics controller.

The controller monitors pH and electrical conductivity through Atlas Scientific
EZO circuits and controls five peristaltic pumps:

- pH Up
- pH Down
- FloraGro
- FloraMicro
- FloraBloom

Home Assistant provides the operator dashboard, calibration controls, timed
dosing scripts, pump flow calibration, daily email summaries, and conservative
pulse-based pH/EC automation.

## Files

- `hydro-controller.yaml` - ESPHome firmware for the ESP32 controller.
- `home-assistant/hydroponics-dashboard.yaml` - Lovelace dashboard YAML.
- `home-assistant/hydroponics-package.yaml` - Home Assistant package with
  helpers, scripts, automations, and email summary.
- `home-assistant/README.md` - Home Assistant install and calibration notes.
- `tools/` - Proxmox inventory and backup helper scripts used for the local
  server setup.

## Network

Current local deployment:

- ESP32 hydroponics controller: `192.168.50.150`
- Home Assistant / MQTT host: `192.168.50.86`
- Proxmox host: `192.168.50.10`
- OMV NAS VM: `192.168.50.228`

Adjust these values before using the project on another network.

## Proxmox Server

The controller stack runs on a Dell OptiPlex 3060 Proxmox host (`pve`,
`192.168.50.10`). Guests:

- VM `100` - OMV-NAS (OpenMediaVault), serves NFS at `192.168.50.228`
- CT `101` - dev-agent, mounts NFS shares at `/workspace` and `/llm`
- CT `102` - homeassistant, IP `192.168.50.86`

### Safe shutdown (e.g. before moving the machine)

Shut guests down first, then the host. On the Proxmox host:

```bash
pct shutdown 102          # homeassistant
pct shutdown 101          # dev-agent
qm shutdown 100           # OMV-NAS (ignore the "QEMU Guest Agent" warning)
# wait until all report stopped, then:
shutdown -h now
```

Guest start/stop order is configured so this also happens automatically on
reboot: VM `100` starts first with a 90s grace period for NFS, then CT `101`,
then CT `102`. Shutdown reverses the order.

### NFS storage and automounts

The host mounts four NFS shares from the OMV NAS (`192.168.50.228`). These use
systemd automounts (`x-systemd.automount` in `/etc/fstab`) so they mount
on-demand and self-heal even if the NAS boots after the host:

- `/mnt/omv-dev` (bound into CT 101 as `/workspace`)
- `/mnt/omv-llm` (bound into CT 101 as `/llm`)
- `/mnt/omv-docker`
- `/mnt/omv-timemachine`

If a share ever looks empty after a power event, trigger it by accessing it
(`ls /mnt/omv-dev`) and, if a container shows the local disk instead of the
share, restart it (`pct stop 101 && sleep 3 && pct start 101`).

### UPS

The host is on an APC BE425M UPS for outage ride-through and surge protection.
Note: this model has no data USB port, so Proxmox cannot auto-shutdown on a
prolonged outage. Shut down manually if an outage may outlast the battery.

### Inventory

Regenerate a full read-only host inventory at any time:

```bash
ssh root@192.168.50.10 'bash -s' < tools/proxmox-inventory.sh > proxmox-inventory.txt
```

`proxmox-inventory.txt` is git-ignored.

## Home Assistant

Install the Home Assistant package at:

```text
packages/hydroponics.yaml
```

Then paste `home-assistant/hydroponics-dashboard.yaml` into a Lovelace raw
dashboard editor.

See `home-assistant/README.md` for the full install, calibration, and daily
email setup.

## Safety

The automation is intentionally conservative. It uses short dosing pulses,
deadbands, and a 60-second pump failsafe instead of continuous PID-style output.
Keep auto-control disabled until probes and pump flow rates have been calibrated.

Do not commit Home Assistant `secrets.yaml`, ESPHome secrets, app passwords,
SSH keys (`key`, `vskey`, `*.pem`), or local inventory files. These are all
covered by `.gitignore`.
