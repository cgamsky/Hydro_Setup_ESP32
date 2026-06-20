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

Do not commit Home Assistant `secrets.yaml`, ESPHome secrets, app passwords, or
local inventory files.
