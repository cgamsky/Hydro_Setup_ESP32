# Hydroponics Home Assistant Setup

This folder contains Home Assistant YAML for the ESPHome hydroponics controller.

## Network Context

- ESP32 hydro controller: `192.168.50.150`
- MQTT broker from ESPHome config: `192.168.50.86`
- Proxmox host: `192.168.50.10`
- Home Assistant container host: Proxmox CT `102`, IP `192.168.50.86`
- OMV NAS VM: `192.168.50.228`

## Before Adding The Dashboard

In Home Assistant, verify that MQTT discovery has created these entities:

- `sensor.hydroponics_controller_node_hydroponics_ph_level`
- `sensor.hydroponics_controller_node_hydroponics_electrical_conductivity`
- `switch.hydroponics_controller_node_peristaltic_pump_1_ph_up`
- `switch.hydroponics_controller_node_peristaltic_pump_2_ph_down`
- `switch.hydroponics_controller_node_peristaltic_pump_3_floragro`
- `switch.hydroponics_controller_node_peristaltic_pump_4_floramicro`
- `switch.hydroponics_controller_node_peristaltic_pump_5_florabloom`

If Home Assistant generated slightly different entity IDs, update both YAML files to match.

The current calibration entities discovered after the ESPHome OTA update are:

- `sensor.workshop_hydroponics_controller_node_hydroponics_ph_calibration_status`
- `sensor.workshop_hydroponics_controller_node_hydroponics_ec_calibration_status`
- `button.workshop_hydroponics_controller_node_hydroponics_calibrate_ph_4`
- `button.workshop_hydroponics_controller_node_hydroponics_calibrate_ph_7`
- `button.workshop_hydroponics_controller_node_hydroponics_calibrate_ph_10`
- `button.workshop_hydroponics_controller_node_hydroponics_get_ph_calibration`
- `button.workshop_hydroponics_controller_node_hydroponics_clear_ph_calibration`
- `button.workshop_hydroponics_controller_node_hydroponics_calibrate_ec_dry`
- `button.workshop_hydroponics_controller_node_hydroponics_calibrate_ec_1413`
- `button.workshop_hydroponics_controller_node_hydroponics_calibrate_ec_12880`
- `button.workshop_hydroponics_controller_node_hydroponics_get_ec_calibration`
- `button.workshop_hydroponics_controller_node_hydroponics_clear_ec_calibration`

## Recommended Install: Package

Enable packages in Home Assistant by adding this to `configuration.yaml`:

```yaml
homeassistant:
  packages: !include_dir_named packages
```

Then create this directory in the Home Assistant config folder:

```bash
mkdir -p packages
```

Copy `hydroponics-package.yaml` into:

```text
packages/hydroponics.yaml
```

Restart Home Assistant or reload YAML where available.

The package provides:

- pH target/deadband helpers
- EC target/deadband helpers
- Separate pH and nutrient dose duration helpers
- Pump flow calibration helpers
- Timed dosing scripts
- Stop-all-pumps script
- Failsafe automation that turns off any pump left on for 60 seconds
- Conservative auto-control automation gated by `input_boolean.hydro_auto_control_enabled`

The auto-control automation is intentionally pulse-based rather than PID-based. Dosing systems have mixing delay and nonlinear sensor response, so short pulses with a deadband are safer than continuous PID output.

For the current Proxmox-hosted Docker install, the package was deployed to:

```text
/var/lib/docker/volumes/hass_config/_data/packages/hydroponics.yaml
```

Config validation was run with:

```bash
docker exec homeassistant python3 -m homeassistant --script check_config --config /config
```

## Probe Calibration

The ESPHome device exposes calibration buttons for the Atlas Scientific EZO pH and EC circuits.

pH:

1. Turn off `input_boolean.hydro_auto_control_enabled`.
2. Rinse the pH probe.
3. Place it in pH 7.00 solution and wait for a stable reading.
4. Press `Hydroponics Calibrate pH 7`.
5. Rinse, place in pH 4.00 solution, wait, then press `Hydroponics Calibrate pH 4`.
6. Optionally rinse, place in pH 10.00 solution, wait, then press `Hydroponics Calibrate pH 10`.
7. Press `Hydroponics Get pH Calibration`.

EC:

1. Turn off `input_boolean.hydro_auto_control_enabled`.
2. Rinse and dry the EC probe.
3. Press `Hydroponics Calibrate EC Dry`.
4. Place the probe in the EC calibration solution and wait for a stable reading.
5. Press either `Hydroponics Calibrate EC 1413` or `Hydroponics Calibrate EC 12880`, matching the solution.
6. Press `Hydroponics Get EC Calibration`.

## Pump Flow Calibration

For each pump:

1. Set `Hydro Pump Calibration Run`, usually 60 seconds.
2. Put the pump output into a graduated cylinder.
3. Run the matching calibration script.
4. Enter the measured output volume in that pump's `measured mL` helper.
5. Press `Hydro - Save Pump Flow Calibration`.

The dosing scripts use:

```text
run seconds = desired mL / calibrated mL per second
```

The nutrient dosing script adds equal target volumes from FloraGro, FloraMicro, and FloraBloom. If the pumps have different flow rates, each pump will run for a different duration.

## Daily Email Summary

Home Assistant's SMTP integration can send daily email reports. The package includes a daily 08:00 automation that calls:

```text
notify.hydro_email
```

Add an SMTP notifier to `configuration.yaml`:

```yaml
notify:
  - name: hydro_email
    platform: smtp
    server: smtp.gmail.com
    port: 587
    timeout: 15
    sender: !secret hydro_email_sender
    encryption: starttls
    username: !secret hydro_email_username
    password: !secret hydro_email_password
    recipient:
      - !secret hydro_email_recipient
    sender_name: Hydroponics Controller
```

Add matching values to `secrets.yaml`:

```yaml
hydro_email_sender: your_email@gmail.com
hydro_email_username: your_email@gmail.com
hydro_email_password: your_app_password
hydro_email_recipient: your_email@gmail.com
```

For Gmail, use an app password rather than your normal Google password. Home Assistant documents SMTP notification setup here: https://www.home-assistant.io/integrations/smtp/

## Alternative Install: Scripts Only

If you do not want to use packages, copy the contents of `hydroponics-scripts.yaml` into Home Assistant's `scripts.yaml`. The scripts-only option does not include the duration helper or failsafe automation.

## Add The Dashboard

In Home Assistant:

1. Open Settings > Dashboards.
2. Add a new dashboard, or open an existing dashboard.
3. Use Raw configuration editor.
4. Paste the contents of `hydroponics-dashboard.yaml`.

The dashboard intentionally puts timed dosing scripts above the raw pump switches. Raw pump switches are useful for testing, but timed scripts are safer for normal use.

## ESPHome OTA

After changing `hydro-controller.yaml`, upload to the controller with:

```bash
esphome run hydro-controller.yaml --device 192.168.50.150
```

The latest OTA added pH/EC probe calibration buttons and status sensors.
