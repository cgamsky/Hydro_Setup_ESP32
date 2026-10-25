# Hydroponics, Measured — Control Strategy & VS Code Agent Contract

**Document ID:** HM-CTRL-001  
**Version:** 1.0 (design baseline; not deployed)  
**Date:** 2026-10-25  
**Canonical repository:** `cgamsky/Hydro_Setup_ESP32`  
**Intended repository path:** `docs/HYDRO_CONTROL_STRATEGY.md`  
**Status:** Proposed software architecture built from agreed hardware decisions; **do not treat as tested firmware, completed assembly, or permission to enable unattended dosing.**

> **Agent entry point:** Read this entire file before changing ESPHome, Home Assistant, wiring documentation, or dosing logic. Follow the [implementation gates](#implementation-roadmap-and-release-gates) and [acceptance matrix](#verification-acceptance-matrix). Keep the existing functioning controller intact until a documented cutover. If an important decision is not yet verified, implement a configurable placeholder or a disabled feature; do not fill the gap with an unreviewed assumption.

## 0. Executive control strategy

**ESP32 is the local safety/actuation controller; Home Assistant is the Wi-Fi-facing scheduler, operator interface, data historian, and eventual chemistry decision engine. MQTT remains the messaging transport, consistent with the current installation.** The ESP32 must enforce its own interlocks and bounded runtimes; HA automation is *not* the sole layer preventing a pump from running indefinitely.

**Physical process:** selected reservoir **source valve** → Kamoer KHM sampling pump → common flooded sample header (**pH**, reserved **DO**, reserved **temperature**, **EC**) → shared sample-line flow meter as installed in the actual plumbing path → selected reservoir **return valve**. Exact meter position within the sample loop must be recorded from the physical build. At a later gate, **A, B, C, and pH-down** dosing lines inject individually into the common flowing return **after the analytical probes and before the selected return valve**. The reservoir mixes; subsequent sampling evaluates the response.

**One relay selects a complete reservoir path.** Each of three relays supplies **both** the normally closed (NC) source and NC return solenoids for its reservoir in parallel. They receive the same electrical command and de-energize closed; there are **not** six separately controlled valve outputs. Only one reservoir pair may be energized at a time. A single DIGITEN meter measures **shared sample-line flow only**. There is **no extra return-flow sensor or return-flow verification requirement**.

**Commission in order:**

1. Existing reservoir: prove flow/priming, pH and EC sampling, sensor quality, Wi-Fi/MQTT readout and emergency stop. **No automated chemical addition**.
2. Three source/return pairs: one selected path, flush/settle/sample, flow timeout, cross-reservoir sequencing and route lockout. Still **no automated dosing**.
3. Shared nutrient A/B/C and pH-down: calibrated *independent* pumps, conservative per-reservoir recipe and targets, sequential injection with carrier flow/flush/mixing, anti-repeat limits, logged intervention, and gradual transition from manual to unattended operation.

The assembled electrical enclosure may provision all outputs now, but **software enablement is phase-gated**.

## 1. Provenance: what is observed, owned, ordered, or only proposed

| Category | Evidence-based status as of 2026-10-25 |
|---|---|
| Existing functioning controller | Repository `hydro-controller.yaml` describes ESPHome `esp32dev`, Wi-Fi `192.168.50.150`, MQTT broker `192.168.50.86`, Atlas pH/EC, **G1/2 circulation-flow GPIO33**, five raw pump GPIOs. Repository was inspected live on 2026-10-25. This is **legacy active-system configuration**, not the new station firmware. |
| Existing automation | `home-assistant/hydroponics-package.yaml`: 5-minute conservative control, pH up/down, three legacy Flora-named nutrient channels, volume helpers, 60-second **HA-side** runtime cutoff, 4 L/min circulation-flow email alert. Preserve it until deliberate cutover. |
| New electronics, photographed | ESP32 on HW-395 screw carrier; Diitao CW-024 16-channel 12 V low-trigger relay mounted on one board. Physical relay input characteristics/pin labels still need bench verification. |
| User confirmed on hand | KHM sampling pump, NKP dosing pumps, pH/EC sensors; fuses, heat-shrink tubing, solder; smseace ring-terminal kit purchased. Physical count/model/position of specific carrier interfaces must be confirmed on assembly. |
| Ordered, not stated delivered | WUPP six-circuit fused power block with negative bus; ULN2803A modules (3-pack); Dupont jumper wires. Distinguish future arrival from current installation. |
| Candidate wire / join method | BNTECHGO 16 AWG 252-strand tinned **copper** silicone wire selected; purchase/delivery not confirmed. Soldered insulated branches and correctly crimped ring terminals; **no WAGO connectors** owned or required. Existing 18 AWG CCA must not go into copper-only terminals. |
| Six valves | Six DIGITEN 12 V normally closed 1/4-inch quick-connect valves reported in September order. One pair per reservoir, common relay per pair. |
| Flow meter | DIGITEN **1/4-inch 0.3–10 L/min** Hall meter in new sample line; reported ordered previously and now included in system design. Actual installed location and output behavior still need verification. |
| Future sensor slots | DO and temperature positions reserved; do not assume an EZO-DO, EZO-RTD, RTD probe, or DS18B20 purchased or connected. |
| Future/conditional | Dosing injection plumbing and actual Masterblend A/B/C pump-to-bottle mapping, calibration, exact reservoir target values and mixing times still require testing; not software facts. |

**Source precedence for agents:** directly observed as-built/photo or measurements > user-confirmed current inventory and decisions > *newly inspected* source files > historical handoff and order records > product literature > working hypotheses. When two sources disagree, **record the conflict**; do not silently rewrite the old setup.

## 2. Boundaries, responsibilities, and unchanged legacy system

### 2.1 Two-layer control

**ESP32 / ESPHome or thin local component owns:** output-off initialization, single-reservoir valve selection, single active pump operation, per-run timeouts, flow-watchdog checks, freshness/ready state for measurements, abort/off, command rejection in wrong states, physical-command acknowledgments, and telemetry of state, alarms, sample IDs and operating times. The enforcement is independent of a long-running HA delay.

**Home Assistant owns:** dashboard, Wi-Fi remote controls for **high-level guarded operations**, schedules, recipe and target settings by reservoir, trend/history, manual confirmation workflow, alerts and the decision whether to request a *bounded* sample or dose. HA cannot bypass hardware interlocks or bypass calibration gates by toggling raw output switches. An HA reboot may cancel an HA script; this must not leave a pump on.

**Broker/MQTT owns only transport:** no unbounded ON/OFF retained commands. Availability and birth messages are informational, not evidence of current liquid circulation or valve actuation. Remote access should be through the existing secured HA/VPN approach, not a publicly exposed ESP32 HTTP endpoint.

### 2.2 Preserve the old controller

The currently committed `hydro-controller.yaml` is **not** a drop-in base for the new control board. It contains a **different 1–30 L/min circulation sensor**, `GPIO33`, `7.5 Hz/(L/min)` and a five-pump pH-up design. The new **sample** flow sensor has different nominal calibration and pin assignment. The existing HA low-circulation alarm (`4.0 L/min`) must **not** be copied onto the roughly `0.5 L/min` sample line.

**Recommended implementation path:** create a separate *candidate* firmware file (e.g. `hydro-sampler.yaml`) with a distinct node name, MQTT discovery IDs, and an unused Wi-Fi IP. Preserve the existing `hydro-controller.yaml`, Home Assistant package, and entity IDs until the user explicitly authorizes migrating the working system. Before first flash, determine whether the new ESP32 is physically distinct and whether Atlas probes are being moved rather than duplicated. If only one controller will remain after cutover, document its transition separately. **Do not reuse `.150` while the old node is active.**

### 2.3 Operating modes

`MONITOR_ONLY` (initial default), `MANUAL_SAMPLE`, `ROUTING_TEST`, `MANUAL_DOSE_TEST`, `AUTO_SUPERVISED`, and `AUTO_ENABLED` (last only after all release gates). Auto mode and chemical permissions **default false on every reboot**, require deliberate re-arm, and cannot be restored from nonvolatile memory to ON without a new operator decision.

## 3. One binding pin/actuator map

This is the **proposed Rev 2 wiring map**, not verified in deployed firmware. Relay numbers refer to physical Diitao **IN1–IN8** and associated **COM/NO** output contacts.

| Function | ESP32 | Intermediate / protocol | Hardware / meaning |
|---|---|---|---|
| pH | GPIO21 SDA + GPIO22 SCL | Atlas EZO pH, I²C `0x63` (99) | 3.3 V interface-side VCC/GND; isolated probe side remains isolated |
| EC | same I²C bus | Atlas EZO EC, I²C `0x64` (100) | As above; stable readings needed before any dose |
| Sample flow pulses | GPIO32 | DIGITEN 1/4 Hall meter | Proposed 3.3 V supply; verify actual wire labels, pulse-high ≤3.3 V and calibration |
| Reservoir 1 source **and** return | GPIO16 | ULN channel 1: `1B` → `1C` → Diitao `IN1` | R1 NO drives **both** 12 V NC valves in parallel |
| Reservoir 2 source **and** return | GPIO17 | ULN 2 `2B` → `2C` → `IN2` | R2 two NC valves |
| Reservoir 3 source **and** return | GPIO18 | ULN 3 `3B` → `3C` → `IN3` | R3 two NC valves |
| KHM sample pump | GPIO33 | ULN 4 `4B` → `4C` → `IN4` | R4 powers KHM 12 V |
| Nutrient A (Masterblend stock) | GPIO27 | ULN 5 `5B` → `5C` → `IN5` | R5 powers one NKP |
| Nutrient B (calcium nitrate stock) | GPIO26 | ULN 6 `6B` → `6C` → `IN6` | R6 powers one NKP |
| Nutrient C (magnesium sulfate stock) | GPIO25 | ULN 7 `7B` → `7C` → `IN7` | R7 powers one NKP |
| pH-down | GPIO14 | ULN 8 `8B` → `8C` → `IN8` | R8 powers one NKP |
| DO / optional future | shared I²C only if EZO DO selected | Default `0x61` (97) if Atlas | **Reserved, no wiring now** |
| Temperature / optional future | shared I²C only if EZO RTD selected | Default `0x66` (102) if Atlas | **Reserved, not a fixed sensor choice** |

**Electrical implementation contract:** 12 V relay power comes from an appropriately fused branch; ESP32 gets USB power. ULN logic GND joins ESP32 logic GND and 12 V supply negative at the intended **reference** connection; no motor/valve return current flows through the ESP32. ULN `COM` is unused when sinking logic inputs, **not** switching inductive relay coils directly. `GPIO HIGH` should drive ULN sink ON, then low-trigger relay ON, but **verify actual low-trigger CW-024 board behavior** on the bench. Driver outputs are not motor-power outputs. Relay COM has fused +12 V, NO feeds switched load positive; load negative goes back to the WUPP negative bus. Each of six valve coils and five pump motors has its own 1N5408 flyback diode (11 total), cathode/stripe at switched positive, anode at load negative. Confirm installed pumps/valves do not already have incompatible integrated suppressors.

**Fuse proposal (unapproved amperages):** upstream inline F0 (previous 5 A candidate); WUPP F1 relay-module supply; F2 three valve pairs via R1–R3; F3 KHM; F4 A/B/C pumps via R5–R7; F5 acid via R8; F6 spare. Verify every fuse against **total credible current/inrush, the smallest downstream wire, crimp ratings, and the 12 V/5 A supply** before energizing. Parallel valves share ONE relay contact; confirm combined valve-coil current is below that contact's rating. Unused relays R9–R16 remain unconnected and OFF.

**Startup/boot caveat:** `restore_mode: ALWAYS_OFF`, `inverted: false` with GPIO HIGH → ULN sink is a proposed logical model, not proven through ESP boot pin high impedance, carrier, or CW-024 input circuit. Bench-test reset, 12 V arriving before USB, USB arriving before 12 V, Wi-Fi loss, and OTA reboot with a voltmeter/indicator and **loads disconnected**. If an output energizes transiently, hardware pull-downs or control-power interlocking may be required; software settings alone do not fix pre-boot pin behavior.

## 4. Process states and interlocks

### 4.1 State machine (one active transaction globally)

```text
DISARMED / BOOT_SAFE
   | operator enables MONITOR_ONLY and hardware/sensors self-test passes
   v
IDLE (everything OFF)
   | valid bounded sample request for one reservoir
   v
SELECT_PATH (turn OFF all three routes, then energize requested pair)
   v
PRIME_AND_FLUSH (KHM ON; await validated sample-line pulses/flow)
   v
SETTLE_AND_READ (maintain safe circulation; acquire stable pH/EC)
   v
SAMPLE_VALID (publish reservoir-tagged reading, flow, quality, timestamps)
   | optional dosing-authorized command and remaining checks succeed
   v
SEQUENTIAL_DOSE (only ONE NKP at a time; KHM/flow maintained)
   v
POST_DOSE_FLUSH (keep same reservoir selected; carrier clears common return)
   v
STOP_AND_MIX (dosing OFF, KHM OFF, route OFF; mixing cooldown)
   v
IDLE (future sample may assess response)

ANY ACTIVE STATE --timeout, no flow, lost interlock, restart, STOP, bad input-->
FAULT / ABORT -> ALL ACTUATORS OFF -> LATCH until explicitly cleared.
```

The exact point where pumps or route close may depend on proving a flooded sample chamber and actual return-path plumbing. Time/distance values are **calibrated parameters**, not guessed hardcoded constants.

### 4.2 Invariants — must hold in firmware, regardless of HA

- **I01:** `active_valve_pairs ∈ {0, 1}`. Never energize two reservoirs together, including during switching.
- **I02:** Each reservoir pair consists of exactly one physical relay output driving **its** source and return valves together. Do not create independent software entities for each valve.
- **I03:** No KHM sample pumping unless a reservoir path is selected and transaction state explicitly permits pumping.
- **I04:** No nutrient or acid pump unless: route selected and locked, KHM carrier flowing and proven, calibration valid, sampling context current, dose permissions active, and transaction has not timed out.
- **I05:** At most **one** dosing NKP on at any instant; A, B, C and acid never overlap. pH-down must not be combined in the same immediate nutrient adjustment without a new mixing/measurement interval.
- **I06:** All output relays OFF at boot/init, on stop/abort/fault and after bounded job completion. Do not restore an unfinished dosing transaction across restart.
- **I07:** Every motor is locally time bounded; no MQTT/HA/OTA delay can keep a dosing output ON indefinitely. **The 60-second limit in the *old* HA package is not an adequate standalone local interlock.**
- **I08:** No autopilot when pH/EC is unknown, stale, not calibrated, or has ambiguous reservoir identity. Invalid measurements cannot silently become numeric zero.
- **I09:** Missing/low sample flow aborts sampling or dosing only after the separately configured **priming allowance**; flow threshold and time are derived from the *new* sensor's bench calibration.
- **I10:** A duplicate, expired, retained, reordered, or out-of-state command cannot repeat a dose. Maintain transaction IDs and bounded acknowledgments; a reboot starts DISARMED, not mid-command.
- **I11:** Any loss of required communications during **unattended chemistry addition** causes local dose outputs to stop promptly (define/test short grace); no continued chemical dosing from a stale command. Monitor-only operation may continue safely offline.
- **I12:** Sensor interface grounds and 12 V power ground share only the intentional logic reference; never connect isolated **probe-side** returns to power GND or carry motor current on sensor grounds.
- **I13:** Only the **shared sample-line** flow sensor exists. Its flow supports pump/line operation diagnostics but does **not** independently identify which physical valve opened and is **not** a return-reservoir sensor or test.
- **I14:** A remote raw-switch, dashboard test button, or HA automation must **not bypass** these invariants. Expose high-level guarded actions; keep low-level GPIO switches internal or otherwise inaccessible to routine operation.
- **I15:** A physically welded relay/solenoid that does not de-energize is **not solvable by software**. Identify residual risk during commissioning; do not claim software guarantees mechanical shutoff or liquid return.

### 4.3 Fault handling and operator recovery

**Fault sources:** boot mid-operation, local watchdog/reset, unexpectedly unavailable EZO circuit, no flow after prime, loss of flow during dose, physically unexpected flow readings, two-route software request, out-of-range sensor value, dose runtime ceiling, stale measurement, failed MQTT broker/Wi-Fi (in AUTO), invalid reservoir ID, rejected/duplicate command.

**Fault action:** turn OFF all four dosing relays, sample pump relay and all three valve-pair relays as soon as electrically possible; publish retained **fault state** but never retain action commands; persist error history through HA when online. Require human acknowledgment and new validation before re-arming. No automatic retry of acid or nutrient doses after an ambiguous interruption; if delivery quantity is uncertain, sample after mixing or inspect physically.

Do **not** add another return-flow sensor or additional route verification hardware. Test tubing orientation and valve operation as normal mechanical commissioning, not as a new continuous return measurement subsystem.

## 5. Sampling, flow, and measurement quality

### 5.1 DIGITEN 1/4-inch flow mathematics (new sampling meter)

DIGITEN lists for the selected **1/4-inch 0.3–10 L/min** unit:

- Supply `3–24 V DC`, nominal frequency `f(Hz) = 36 × Q(L/min)`, factory error approximately ±2% under stated conditions.
- At 0.5 L/min nominal KHM flow: `f ≈ 18 Hz` and `1080 pulses/min` (not a validated installed flow rate).
- ESPHome `pulse_counter` reports pulses/min. **Proposed** `flow_L_min = pulses_per_minute / (36 × 60) = x / 2160`.
- **Proposed** total volume `L = pulse_total / 2160` before field calibration.

**Contrast with the existing legacy circulation meter:** that code divides by `7.5 Hz/(L/min)` and reads `GPIO33`. Do **not** reuse those numbers for GPIO32 sample flow. The new Hall sensor is near the low end of its rated 0.3 L/min range; validate with a graduated cylinder and water, at multiple head pressures, after integration into tubing, and compare pulse-derived volume against gravimetric/time or cylinder reference. Check startup pulse noise, stopped-pump false pulses, arrow orientation and sensor supply/pulse amplitude before GPIO hookup. Datasheet frequency factor is a **starting estimate**, not calibration evidence.

### 5.2 Sampling validity

Every published pH and EC measurement must be bound to: `sample_id`, `reservoir_id`, `measurement_time`, `sensor_id`, route_state, flow diagnostics, sensor calibration/check age, settling time, and validation flags. EZO update rate of 15 seconds in legacy code is a **reference configuration**, not proof one sample has stabilized. Determine acceptable stabilization statistically on the flooded header, comparing against the existing reservoir spot readings; record repeatability and offset. No chemistry dose from a measurement taken during route changes, priming, flushing or immediately following injection.

For multi-reservoir sampling, log pre-sample rinse/flush **measured volume**, not just wall clock duration. Detect carryover empirically by sampling strongly differing known solutions in alternating order. If necessary increase flush amount; never guess cross-loop mixing is impossible.

### 5.3 Calibration/standards

- pH: reproduce manufacturer-supported 7 → 4 → optional 10 point sequence with rinse and stability; log solution lot, date, temperature (if available), observed values before and after, device/circuit identity and acceptance criterion.
- EC: dry-point and appropriate standard(s), e.g., 1413 and/or 12880 µS/cm **as justified by K=0.1 cell and intended range**; select based on Atlas probe/circuit instructions rather than blindly executing legacy buttons.
- Temperature compensation: do not report compensated EC or pH adjustment as validated until the actual temperature sensor/interface and compensation algorithm are selected/tested. Ambient room temperature is not a substitute for solution temperature.
- An EC/pH reading is *operationally valid* only if telemetry is present and fresh, probe calibration/check process accepted, sample route and flow valid, reading stable, and no known contamination or fault. Historical calibration status of `unknown` is **not proof of calibration**.

## 6. Dosing chemistry, reservoir routing and experiments

### 6.1 What the stocks mean

The old HA entity names `FloraGro`, `FloraMicro`, `FloraBloom` are legacy labels. User-reported **current stock recipes** in reused bottles are:

- A / Masterblend tomato formula: `760 g per US gal` stock preparation.
- B / calcium nitrate: `760 g per US gal` stock preparation.
- C / Epsom salt (magnesium sulfate): `378 g per US gal` stock preparation.
- D / pH-down: concentration, composition, pump mapping and tubing compatibility **to confirm**.

These are preparation records, **not measured stock assays** and **not required A:B:C dose ratios**. The previous legacy automation gave equal **volumes** from three bottles, but the new three-reservoir recipe must be explicitly selected after compatibility/target calculations. No algorithm may assume equal mL or automatic EC-based chemical composition without an approved reservoir-specific formulation.

### 6.2 Injection sequence (future stage)

**A valid dose transaction:** lock reservoir → turn ON its paired NC valves → start KHM → prove sample-line flow → optional rinse/measurement → enable one NKP for bounded calibrated delivered volume → turn it OFF → flush with KHM carrier to same selected route → only then another compatible NKP if recipe requires → flush → sample/stop as protocol specifies → close pair → allow reservoir mixing before making another chemical decision.

Inject each concentrate **after analytical probe locations and before the selected return valve**, not upstream of pH/EC. Never run two stock pumps simultaneously; keep highly concentrated calcium and phosphate/sulfate stocks separated and use carrier rinse between additions. Acid correction is a separate, supervised logic branch after nutrient mixing and a fresh pH measurement.

`pump_time_s = requested_ml / measured_pump_rate_ml_s` may be used only **within both per-pulse and cumulative ceilings** and only after test-cup pump calibration for the actual fluid/tubing/height. Prefer using elapsed on-time as an estimate of delivered mL plus a dose ledger; do not claim volumetric feedback from a motor energized event.

### 6.3 pH and EC decision policy (proposal; disabled until release gate)

1. Acquire **fresh, quality-accepted** reservoir measurement after stable sample flow. If invalid, report and do **nothing**.
2. If pH **above** target plus deadband: candidate **pH-down** correction, within per-reservoir safeguards; do not dose unless chemistry gates and no recent mixing cooldown.
3. If pH **below** target minus deadband: **alert / manual assessment only**. New eight-relay design **does not include a pH-up pump**; do not map legacy GPIO12 or pH-up automation into the new controller.
4. If EC **below** target minus deadband: evaluate nutrient recipe and reservoir working volume; request a bounded **A then B then C** plan only when user-approved ratio and recent dose ledger permit it. The target values in the old HA package (`pH=6`, `EC=1200 µS/cm`, 5 min interval) are **legacy defaults, not final targets** for all three independent loops.
5. If EC **above** target: alert/manual dilution strategy; **no nutrient dosing**.
6. After each intervention, wait for measured/validated mixing interval and repeat sampling before considering a further correction. Never stack unverified corrections based on stale pH or EC.
7. Maximum volumes, daily totals, minimum time between interventions, and crop/reservoir-specific set points remain **TBD until real reservoir volume and concentrations are measured**. Default auto-dose permission is OFF.

### 6.4 Initial user-facing UI

- Reservoir 1/2/3: `Sample now` and `Last valid sample` with pH, EC, flow, timestamp, sample quality, phase, and time since calibration.
- Controller state: `DISARMED/IDLE/.../FAULT`, active reservoir, current transaction, Wi-Fi/MQTT availability, uptime, fault reason.
- Guarded actions: `Stop all now`, `Sample selected reservoir`, `Enable manual calibration mode`, `Acknowledge fault`, later `Test pump to beaker`, `Supervised dose X mL` (confirmation required). **No raw never-expiring relay switches** in normal dashboard.
- Future after validation: reservoir-specific pH/EC targets, deadbands, concentrations/recipe reference, max one-shot dose, max daily cumulative dose, minimum sample interval, cooldown/mixing timer and auto-enable control.
- Trend/log: separate reservoir time series with `sample_id` and event log; never put readings from alternating reservoirs into one unlabeled curve.

## 7. MQTT and command contract for agents

**Design preference:** reuse ESPHome MQTT discovery and existing Mosquitto broker. The examples below are **protocol design**, not verified as natively supported ESPHome YAML. Agents must choose the simplest ESPHome-script/lambda or small local component implementing these semantics, then compile against the installed ESPHome version.

**Device identity:** distinct new node name, `hydro_samplestation` suggested; exact hostname/IP and physical ESP32 identity are open. Every command identifies intended destination and reservoir. Proposed topics (namespace may be revised before deployment):

| Direction | Topic example | Payload / behavior |
|---|---|---|
| HA → ESP | `hm/station/cmd` | `{"id":"uuid","action":"sample","reservoir":1,"issued_at":"...","expires_at":"..."}`; QoS 1 acceptable, **retain=false** |
| HA → ESP | `hm/station/cmd` | `{"id":"uuid","action":"stop"}` always accepted, nonretained; stop on local network outage requires device watchdog too |
| ESP → HA | `hm/station/ack` | `id`, `accepted`, `reason`, `active_id`, state; use idempotency/recent ID cache |
| ESP → HA | `hm/station/state` | current state, selected reservoir, active relay and pump IDs, timing, fault, online; retained STATE permitted |
| ESP → HA | `hm/station/sample` | `sample_id`, `reservoir`, pH, EC, flow, quality flags, timestamp, calibration age; never conflate with old circulation meter |
| ESP → HA | `hm/station/event` | start, stop, flow fault, sample invalid, dose request/estimated delivered mL, reset; append-only in HA history |
| ESP → HA | `hm/station/availability` | availability/birth/LWT online/offline; retained state permitted |

**Security/reliability rules:** secrets remain in `secrets.yaml` excluded from git. No hardcoded MQTT credentials. Commands validated at both HA and ESP; invalid/missing IDs and unsafe requests rejected; no retained actuator commands; expire commands; duplicate payload cannot repeat a dose; HA shouldn't conclude a dose happened from `publish` success alone. Require explicit ack and completed telemetry. On broker loss mid-chemistry request, local fail-safe stops chemistry output; exact timeout must be bench tested. Store dose ledger in HA and reconcile incomplete transactions before reboot rearm.

**Operator command boundaries:** `stop` has highest priority; a request to sample reservoir B during reservoir A sampling should be **rejected** or queued by the HA coordinator for later (single queue), never trigger open A+B. Chemistry commands while `MONITOR_ONLY` rejected. Calibration/maintenance actions temporarily suspend scheduled sampling and all automation.

## 8. Proposed firmware modules / file changes (not implemented)

Keep current `hydro-controller.yaml` untouched until authorized. New development may use these separately testable building blocks:

```text
hydro-sampler.yaml                  # proposed NEW ESPHome node entrypoint
packages/hm_gpio.yaml              # 8 internal relay GPIO outputs / interlocks
packages/hm_ezo.yaml               # pH/EC I2C and calibration reporting
packages/hm_flow.yaml              # GPIO32 DIGITEN pulse count and quality
packages/hm_runtime.yaml           # transactions, limits, fault/abort and timer
packages/hm_mqtt.yaml              # guarded MQTT command handling + availability
home-assistant/hm-station.yaml     # NEW HA package; not old hydroponics-package.yaml
home-assistant/hm-dashboard.yaml   # NEW dashboard or subview
schemas/hm-command.schema.json     # optional explicit message validation
scripts/check_hm_config.sh         # optional ESPHome + HA static checks
```

The file layout is a proposal, **not a requirement to generate all files before sensor validation**. Agents should avoid creating an elaborate plugin framework for basic phase-1 sensors. A small cohesive ESPHome YAML plus a guarded local sample script is sufficient initially; split components only when complexity warrants it.

**Suggested phase 1 implementation task order:**

1. Inventory current deployed versions, preserve backups, verify the actual new hardware and choose an unused node/IP; create feature branch.
2. Add distinct ESPHome node with Wi-Fi, MQTT, logger, safe output defaults and pH/EC EZO I²C only. Confirm no duplicate MQTT discovery names from legacy.
3. Add GPIO32 pulse counting with correct **36×** factor and qualify 3.3 V electrical interface. Log pulses and calibration.
4. Implement R1 + R4 low-risk single-reservoir sample script on water only (other relays disabled). Add guard/abort timers, off-on-reboot verification.
5. Add phase-1 quality flags, reservoir-tagged sample telemetry, HA view/history and `Stop all` UI.
6. Run the phase-1 acceptance list and capture objective evidence before enabling another reservoir or chemical pump.

### ESPHome feasibility notes

Current ESPHome documents an `ezo` sensor, `pulse_counter`, `switch.gpio` with interlocks, `script` with single/restart/queued modes, `restore_mode: ALWAYS_OFF`, and MQTT component. These are credible building blocks, **not proof** that a YAML-only implementation meets all requirements under every failure. ESPHome GPIO interlocks are a software guard, not hardware redundancy. Do **not** expose raw GPIO output switches via discovery without authorization and safety wrappers. Bench-test all on/off wiring because ULN sinks a **low-trigger** relay input when its ESP32 input goes HIGH.

## 9. Detailed normal sequences (acceptance-oriented)

### 9.1 Phase 1: reservoir 1 measurement only

- Start in `DISARMED`, all 8 relays OFF. Finish I²C scan and initial pH/EC sanity check; status `SENSOR_READY` doesn't imply calibrations accepted.
- Operator asks `sample(1)` with no chemistry authorization. Validate router idle, sensors available, no fault, and allowed phase.
- Energize R1 **one source+return pair**, wait valve-opening interval based on bench testing.
- Energize R4 (KHM); allow bounded priming window; require subsequent coherent flow pulses from GPIO32. No return-line sensor is checked.
- Carry known flush volume through sample header; then monitor pH/EC stabilization and take multiple measurements. Save raw and accepted readings, flow and metadata.
- Turn OFF R4, then R1 according to tested depressurization/hold order; output complete and no chemical change. Always land `IDLE` or `FAULT` with all outputs OFF.

### 9.2 Phase 2: alternating reservoir measurement

- Requests for R1/R2/R3 all pass through one arbiter. Reject/serialize simultaneous jobs.
- De-energize previous pair before energizing next; avoid cross-loop overlap, then prime/flush measured volume and settle.
- Track reservoir identity at every step. A sensor update arriving during switch/flush cannot be labeled as the new reservoir's valid result until quality gate passes.

### 9.3 Phase 3: supervised nutrient dose

- User/HA produces a plan with reservoir ID, three explicit stock doses in mL, calibration version, max allowable budget and transaction ID. Require expected state and operator confirmation.
- Run the select/prime/flow sequence. For A, B, C **in chosen validated formulation order**, run exactly one NKP with bounded time, flush measured carrier volume, repeat. One motor at a time; retain route lock.
- Stop pumps/route; enter `MIX_WAIT`; report **estimated** delivered volumes and uncertain/interrupted status. A new sample after mixing is required before any follow-up correction.

### 9.4 Phase 3: supervised acid adjustment

- Only if new valid post-mixing pH is above target and recipe limit allows it; run pH-down pump separately, bounded volume and carrier flush. Missing pH-up correction is surfaced as manual alert, not automatic compensation.

## 10. Timing and guardrail parameter ledger — defaults are DISABLED/TBD

| Parameter | Purpose | Initial treatment |
|---|---|---|
| `valve_open_delay_s` | After R1/R2/R3 ON before KHM ON | **TBD by valve test** |
| `prime_timeout_s` | Maximum to see first credible pulses after KHM ON | **TBD by wet test**, bounded |
| `sample_flow_min_lpm` | Minimum credible line flow for sample and dose | **TBD after installed calibration**, not legacy 4 L/min |
| `flow_debounce_s` | Prevent instant abort on occasional missed pulse | **TBD**; rate at ~0.5 L/min gives ~18 Hz nominal |
| `flush_volume_ml` | Purge previous sample/chemistry and minimize carryover | **TBD measured** for line/header volume |
| `settle_timeout_s` | Wait for stable pH/EC | **TBD using variance and timing traces** |
| `sample_max_run_s` | ESP local KHM watchdog ceiling | **TBD from measured fill+flush** (separate from chemical pump timer) |
| `dose_pulse_max_s` | Hard cap on any one NKP actuation | **TBD conservatively after test-cup calibration**, never blindly 60s |
| `dose_max_ml_per_pulse` | Max one-shot A/B/C/acid dose | **TBD after measured reservoir volumes and stock strengths** |
| `dose_max_ml_per_day` | Reservoir-/stock-specific total limit | **TBD** |
| `mix_wait_min` | Required post-dose delay prior to further chemistry | **TBD from circulation/mixing validation** |
| `sensor_max_age_s` | Fresh reading requirement | **TBD** (15s raw EZO update is not settling guarantee) |
| `mqtt_loss_abort_s` | Bound delay to halt chemistry on lost MQTT | **TBD and bench tested** |
| `auto_enable` | Permit automatic chemical addition | **OFF until gate 3 passes**, OFF after reboot |

Agents must not turn a TBD into a production constant without measured justification and a signed entry in the change/decision log. A test-only value must be labeled test-only, bounded, and excluded from auto mode.

## 11. Fault/observability decision table

| Condition | Required effect | Record/notification |
|---|---|---|
| Boot / ESPHome OTA restart | All valves and pumps OFF; auto disarmed | `BOOT_SAFE` with restart reason |
| Wrong/multiple reservoir request | Reject new request without opening second pair | Command reject + conflict |
| No flow after prime timeout | All outputs OFF, latch fault | No-flow fault; sample invalid |
| Flow stops mid-chemical dose | Stop NKP immediately, KHM and route to defined safe OFF state | `DOSE_INTERRUPTED`, actual added mL **unknown** |
| pH or EC offline/stale/failed | No auto dose, no valid sample | Sensor fault and quality reason |
| pH lower than target | No automatic pH-up (none in new design) | Alert for manual plan |
| EC higher than target | No nutrient dose | Alert/manual dilution evaluation |
| MQTT broker loss mid-dose | Stop chemistry by local deadline; do not complete stale dose command | Network fault; reconcile ledger later |
| HA reboot during active task | ESP local bounded script continues only if explicitly allowed per mode; chemistry stops if watchdog/connection policy requires | No reliance on HA timers |
| Duplicate retained/replayed MQTT command | Reject/re-ack without actuation | Same ID, duplicate flag |
| 12 V supply lost while ESP USB alive | Physical NC valves/pumps de-energize; do not claim physical flow | Sensor indicates no flow; power-status inferred, not measured |
| Welded contact or stuck valve | Software cannot guarantee physical stop | Residual mechanical risk; user alerted; require inspection |
| Pulse present with all pumps commanded OFF | Report anomaly, do not infer selected route | Flow anomaly |

## 12. Multi-perspective design reviews — checklists, not independent endorsements

These are **structured review lenses applied to the written design**, not claims that different external engineers reviewed or tested hardware.

| Reviewer perspective | Main finding | Required closure |
|---|---|---|
| Firmware / embedded systems | HA scripts alone do not bound a GPIO output during outages; live local control needs state machine/watchdog, boot defaults and idempotency. | T01, T03–T12 passed with physical pins and logger trace. |
| Electrical / reliability | Low-trigger relay via ULN and separate 12V/USB supplies are prone to startup sequencing errors; F0/F1–F5 and motor suppression unverified. | Cold/warm/OTA boot bench testing, contact/coil currents and diode orientation documented. |
| Analytical chemistry | Sample carryover, probe calibration and temperature compensation can bias dose decisions. | Stable data and calibrated spot-reference acceptance, dated calibration record. |
| Fluidics / hydroponics | Paired source/return valves move on one command but cannot prove both mechanically open; common sample-line flow is the only flow measurement. | Wet functional check before scheduling; no additional return-flow system. |
| Home Assistant / SRE | Existing G1/2 main-loop flow alarm, GPIO33, old five pump entities and `.150` conflict with new station if cloned. | New unique node/IP/discovery, HA package namespace; regression preserve legacy. |
| Cybersecurity / remote control | Bare MQTT relay entities and publicly exposed ESP web UI are unsafe for chemical dosing. | Broker auth, secrets kept outside Git, guarded commands, OTA authorization, no retained dose messages. |
| Test / quality engineering | Settings are mostly TBD; simulator/logic tests can check invariants but do not validate the actual wet system. | Acceptance records for every gate, negative tests and regression documentation. |
| Cost / maintenance | Existing ESP32, relays, valves, pumps, probes, WUPP and ring/solder supplies suffice for core design; avoid needless new interface hardware. | Inventory check before purchasing, only add device on proven test failure. |

### Executed reference-model checks (logic only)

On 2026-10-25, the separate, **non-deployable Python reference model** `tests/test_hm_control_contract.py` was run with `python -m unittest -v`. Nine tests passed, including 400 deterministic randomized sequences of 100 actions each (40,000 state transitions/commands). They exercised one active reservoir relay, at most one dosing relay, rejection of duplicate IDs, denied dosing on bad/no flow, sensor fault shutdown, reboot disarming, MQTT-loss abort during dosing, and Stop/all-off. This checks the **reference model's invariants only**; the actual ESPHome YAML does not implement the new state machine yet and no physical or wet hardware was tested. An agent must repeat equivalent tests on the implementation and bench hardware before release.

**Highest-priority unresolved risks:** (a) new vs existing ESP physical identity/HA migration, (b) actual CW-024 boot and low-trigger behavior, (c) non-volatile prevention of duplicate acid/nutrient dosing, (d) Hall signal amplitude and pulse factor, (e) measurement/flush/flow acceptance and calibration, (f) dose limits and chemistry, (g) 12V budget/fuse/crimp verification.

## 13. Implementation roadmap and release gates

### G0 — Baseline / no wet load automation

- [ ] Make local repository clone; save live deployed YAML/HA entities/config versions without credentials.
- [ ] Confirm whether new station has independent ESP32 and separate Atlas interfaces from current productive controller.
- [ ] Freeze baseline old firmware, HA package and useful pH/EC/flow trends; avoid any unreviewed change in production.
- [ ] Confirm hardware and copper wire, 12 V/5 A budget, fuse ratings, diode polarity, relay COM/NO, and GND references.
- [ ] Flash non-actuating test firmware to **correct target**, safe new node/IP; validate HA MQTT telemetry with distinct IDs.
- [ ] Test relays with loads **disconnected** under power sequencing and reboot, including Wi-Fi absent. Record evidence.

### G1 — Reliable pH/EC sample from current reservoir

- [ ] Measure flow pulses in reference volume; calibrate new 1/4 sensor near actual KHM operating point and verify pulse voltage.
- [ ] pH/EC I²C reads correctly; confirm isolated carrier I²C/pullups and calibrate/spot-check probes.
- [ ] Implement paired R1 valve + KHM R4 sampled state machine with LOCAL abort/timeout. No chemical pumps available.
- [ ] Characterize prime time, flush volume, chamber flooding/air, stabilization and repeatability; capture logs and acceptance figures.
- [ ] Wi-Fi/HA dashboard shows `sample_id/reservoir/quality`; local STOP and loss-of-network tests pass.

### G2 — Three-reservoir routing

- [ ] Add R2/R3 valve pairs in firmware, with interlock and break-before-make switching.
- [ ] Alternate different solutions; quantify carryover versus flush volume, log reservoir tags and select accuracy.
- [ ] Demonstrate single relay per paired source/return and absence of simultaneous pairs during manual/auto commands.
- [ ] Test no flow, stalled pump, 12V drop, ESP restart and repeated remote commands. No chemical dosing.

### G3 — Supervised dosing, then optional automatic dosing

- [ ] Confirm real reservoir *working volumes*, stocks, A/B/C bottle mapping, acid identity and pump/tube compatibility.
- [ ] Calibrate each of four NKP pumps separately into a graduated container; characterize repeatability and lift effects.
- [ ] Approve separate recipe/limits/targets for reservoir 1, 2, 3 and manual proof against chemistry ledger.
- [ ] Enable supervised tiny water-only then nutrient tests, single motor/time, flush, mixing, sample, logged estimated volume.
- [ ] Confirm acid-only supervised runs in controlled conditions; pH low alerts but never actuates nonexistent pH-up.
- [ ] Pass stale-sensor, duplicate MQTT, disconnect, reboot-mid-dose, lockout, interleaving, runaway and watchdog checks.
- [ ] Only then allow deliberately armed conservative HA auto-control; document operator and acceptance date.

Every gate closes with **observed data and a dated entry**; unsuccessful tests are documented rather than overwritten or rationalized.

## 14. Verification & acceptance matrix

Use these test identifiers in PRs, agent plans and sign-off notes.

| ID | Test/trigger | Pass condition | Gate |
|---|---|---|---|
| T01 | ESP boots with USB only, 12 V present, inverse sequencing | Eight output relays remain OFF until deliberately commanded; no pulse on startup | G0 |
| T02 | EZO scan/read at 0x63 and 0x64 | Distinct devices detected; values readable; isolation/power verified | G1 |
| T03 | 1/4 sample Hall meter at 0.3–1.0 L/min test flows | Hz/L relation characterized, pulses measured, GPIO amplitude ≤3.3V | G1 |
| T04 | R1 source+return on one NO relay | Both see one common switched voltage and go NC unpowered; wired per plan | G1 |
| T05 | Prime KHM with air / no water flow | Bounded no-flow fault; R1/R4 go OFF; no measurement valid | G1 |
| T06 | Sample steady reference with repeated polls | Stable pH/EC and flow; log variance, accepted timestamp, sample_id | G1 |
| T07 | Simultaneous reservoir 1 and 2 commands | Never energize two valve pairs; reject/serialize deterministically | G2 |
| T08 | Switch reservoir with dissimilar EC | Pre-flush carryover quantified; post-flush threshold passes | G2 |
| T09 | KHM on at wrong/no route | Firmware rejects or aborts operation | G2 |
| T10 | Wi-Fi/MQTT disconnect while dose active | Local NKP stops within verified deadline, route exits safely | G3 |
| T11 | Duplicate, old, retained and reordered dose command | At most one actual bounded dose per valid ID; no late replay | G3 |
| T12 | ESP reset or HA restart mid-dose | Motors OFF on reboot; transaction not automatically resumed | G3 |
| T13 | Low/high pH and low/high EC algorithm | Only permitted action with fresh reading; no pH-up output; no dose for high EC | G3 |
| T14 | Request to operate A and B at once | Reject overlap; never two dosing NKPs energized | G3 |
| T15 | Dosage cap test: requested mL/duration over limits | Locally reject without actuation | G3 |
| T16 | 12 V dropout, ESP USB survives | R1–R8 load power disappears; ESP reports fault/no valid flow | G2 |
| T17 | Calibration invalid/stale, sensor unplug | No valid sample for control and no chemical actuation | G1/G3 |
| T18 | Pump flow calibration with test cylinder | Run seconds match measured mL rate within chosen tolerance; no assumption of exact delivery | G3 |
| T19 | MQTT discovery alongside existing controller | No entity conflicts, existing circulating alarm continues unchanged | G0/G1 |
| T20 | Fault latch and manual reset | OFF remains latched; no automatic stale retry on reset | G2/G3 |
| T21 | EZO 15 s sample update during flush | Measurement marked invalid until settling condition met | G1 |
| T22 | Mechanical stuck-open/failed valve (safe simulation) | System flags limits of detection; does not claim physical closure from relay state | G2 |
| T23 | Human Stop at every state | Chem pumps off immediately and then KHM/route safely OFF; no unexpected restart | G1–G3 |
| T24 | WUPP fused branch with worst credible loads | Branch wire/contact protection and supply margins documented and met | G0 |

**Evidence record template:** `Test ID | date/time | firmware commit | HA config commit | hardware revision | fluid | starting state | stimulus | predicted | measured | result | anomalies | next action | operator`.

## 15. Agent implementation instructions and change protocol

1. **Read current files** before every coding session: `docs/HYDRO_CONTROL_STRATEGY.md` (this file), `hydro-controller.yaml`, `home-assistant/hydroponics-package.yaml`, and recent Git commits. These YAML files are **legacy baseline**, not a new-station implementation.
2. State proposed change, affected invariant IDs, acceptance test IDs, phase/gate, and whether it changes hardware wiring, HA entities or dosing chemistry.
3. Implement on a feature branch with minimal surface change; never copy the legacy circulation-flow scale, low-flow threshold, GPIO33 sensor mapping or pH-up channel into the new sampler.
4. Do not add new physical sensors, second flow meter, WAGOs, extra boards, return-flow verification, or any cloud subscription without explicit user decision.
5. Never change a TBD calibration/limit into an implicit universal constant. Label prototype values `TEST_ONLY`, keep dosing disarmed and document how they were measured.
6. All outputs and HA scripts must obey `I01`–`I15`. On safety uncertainty, deny actuation and continue read-only telemetry if possible.
7. Compile with pinned, logged ESPHome version. Run HA config validation in a safe/staged environment. Do not flash the productive controller without review and a tested rollback path.
8. Collect test evidence and update this spec (decision log, changes and unresolved issues) when actual readings or test behavior change the design; report both passes and failures.
9. Secrets stay in `.gitignore`d secrets files and are not published to GitHub, PDFs or public lab notebook.
10. Deliver each change with a short checklist: **What changed / What was tested / What remains unknown / What operation is still disabled**.

### Agent work request template

```text
READ FIRST: docs/HYDRO_CONTROL_STRATEGY.md, section 15.
TASK: <one bounded task>
GATE: G0 | G1 | G2 | G3
INVARIANTS: <I01...>
TESTS: <T01...>
ACCEPTANCE EVIDENCE: <what will be observed/measured>
DO NOT TOUCH: productive hydro-controller.yaml and existing HA automations unless authorized.
SAFETY: auto dosing OFF; never energize pumps from unvalidated YAML.
DELIVER: code change + validation logs + updated decision entry + rollback.
```

## 16. Open questions / decisions required only at the relevant gate

| Question | Why it matters | When to resolve |
|---|---|---|
| Is the photographed ESP32 separate from the existing productive ESP32? Will probes/pumps be migrated or duplicated? | Determines safe deployment, identity, IP and interim HA coexistence. | Before first flash (G0) |
| What are actual WUPP stud sizes, branch fuse ratings, true copper wire status and current loads? | Prevents wiring/connector and power budget mistakes. | Before 12 V load connection (G0) |
| Does actual CW-024 stay OFF during reset/power order with ULN sink inputs? | Avoids unscheduled valve and chemical pump actuation. | Before motor/valve connections (G0) |
| What are exact Atlas isolated carrier modules and pullup voltage? | Avoids 5 V GPIO or lost isolation. | G1 |
| What pulse high/low behavior and installed K-factor does the 1/4 meter have at KHM actual flow? | Reliable no-flow protection and volume data. | G1 |
| Does KHM produce stable flooded header and pH/EC reading at nominal ~0.5 L/min? | Valid sample threshold and flush time. | G1 |
| What is suitable washout/carryover volume for each reservoir? | Prevents comparing misassigned sample. | G1/G2 |
| How will OTA and MQTT disconnect abort be enforced locally, not HA only? | Chemistry release gate. | G1 design / G3 test |
| What are the reservoirs' measured working volumes and stock compositions/dose ratios? | Prevents applying historic 10-gal estimate or equal mL formula universally. | G3 |
| Which pump delivers which bottle and what are actual mL/s curves? | Dose volume correctness. | G3 |
| What are pH/EC targets/deadbands, max daily/per-event additions and mixing delays by reservoir? | Chemical safety. | G3 |
| Are DO/temp added later, and with which circuits? | Choose bus addresses/compensation without inventing purchases. | Optional future |

## 17. References and verification history

### Project sources inspected 2026-10-25

- GitHub repository: `https://github.com/cgamsky/Hydro_Setup_ESP32` — `README.md`, `hydro-controller.yaml`, `home-assistant/hydroponics-package.yaml`, `home-assistant/README.md`. These are **prior/active-system implementation records**, not newly flashed code.
- Provided working-system reference: `system-overview.html` prepared 2026-07-19; and inventory reconciliation `Hydroponics_Measured_Inventory_2026-09-26.md`.
- Hydroponics, Measured project handoff updated 2026-09-27.
- October 25, 2026 working wiring revision: `Hydroponics_Measured_Complete_Wiring_and_Splices_BW_2026-10-25.pdf` (proposed, not as-built).
- Direct conversation decisions Oct 23–25: paired NC valves on one relay, eight relays, one sample flow meter, no return-flow sensing, owned ring-terminal kit/solder/heat-shrink, no WAGO connectors, sequential project phases.

### Vendor/official references, checked 2026-10-25

- ESPHome EZO: https://esphome.io/components/sensor/ezo/
- ESPHome pulse_counter: https://esphome.io/components/sensor/pulse_counter/
- ESPHome GPIO switch: https://esphome.io/components/switch/gpio/
- ESPHome script: https://esphome.io/components/script/
- ESPHome MQTT: https://esphome.io/components/mqtt/
- ESPHome ESP32 pins: https://esphome.io/components/esp32/
- DIGITEN 1/4-inch 0.3–10 L/min flow sensor: https://www.digiten.shop/products/digiten-1-4-quick-connect-0-3-10l-min-water-hall-effect-flow-sensor-meter
- Atlas EZO pH/EC/DO/RTD standard addresses: https://atlas-scientific.com/files/Wi-Fi-Hydroponics-kit-setup-guide.pdf
- Home Assistant automation modes (single vs queued/restart/parallel): https://www.home-assistant.io/docs/automation/modes/
- Home Assistant MQTT: https://www.home-assistant.io/integrations/mqtt/

### Decision log (document-specific)

| Date | Decision | Status / evidence |
|---|---|---|
| 2026-07-19 | Existing MQTT-based ESP32 and HA automations documented. | Historical deployed design. |
| 2026-09-26 | New sample header to be validated on existing reservoir before routing and shared dosing. | Agreed phased design; not yet validated. |
| 2026-10-23 | Existing ESP/relay panel retained; only fuse distribution may occupy second small box. | Selected layout. |
| 2026-10-25 | R1–R3 each switch paired normally closed source+return valves, one relay per reservoir. R4 sample, R5–R8 A/B/C/acid. | User-confirmed, 8 relay channels. |
| 2026-10-25 | Only one 1/4-inch flow meter in shared sample line; no return-flow measurement or return-flow validation subsystem. | User-confirmed. |
| 2026-10-25 | Shared grounds/positive branches via owned solder, heat-shrink and ring terminals, no WAGO purchase. | User-confirmed materials; joints as-built to verify. |
| 2026-10-25 | New station should be separate firmware identity from legacy until explicit cutover; HA remains high-level control and MQTT transport. | Engineering recommendation in this spec, not yet deployed. |
| 2026-10-25 | Safe auto dosing off by default, locally enforced bounded commands, recipe/per-loop parameters TBD from measurement. | Engineering acceptance criteria, pending implementation/test. |

### Change log

- **1.0 — 2026-10-25:** Initial agent-ready control strategy; first direct GitHub source audit; legacy/new flow meter and GPIO discrepancies identified; state machine, invariants, safety/risk reviews, MQTT contract, acceptance matrix and gated roadmap documented. **No controller firmware or HA automation was modified.** A separate reference-model test suite was executed; 9/9 passed (40,000 randomized steps inside one test).

---

**Completion criterion:** a Wi-Fi-controlled **measurement and dosing station that maintains separation between reservoir chemistry, uses one guarded actuator transaction at a time, provides reproducible pH/EC samples and bounded calibrated additions, and fails electrically OFF when interrupted.** Until staged tests establish those behaviors, the artifact is a design specification, not a claim of achieved performance.