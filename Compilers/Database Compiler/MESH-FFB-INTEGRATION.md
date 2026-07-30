# MESH FFB Integration — Design Notes (SUPERSEDED)

> **SUPERSEDED (2026-07-30).** MESH independently built and hardware-validated its FFB engine
> on **SDL3** (`src/MESH/Hardware/Ffb/` — see `MESH\docs\FFB-MSOP-HANDOVER.md`), making this
> SDL2-era design spec historical. The authoritative, agreed vocabulary now lives in
> **`MESH\docs\FFB-MSOP-CONTRACT.md`**. Kept only for the design rationale below.

What MESH would need to convert the MSOP `ffb` channel's standardized state outputs into real
wheel/controller effects. Based on a working spike previously built and reverted (its design is
reproduced here so nothing is lost); **no MESH code is touched by the current branch**.

## 1. Where it plugs in

`MainWindow.Engines.cs → DispatchStateLine` is the single convergence point every delivery leg
passes through (relay, MAME readers, Live Tests). The FFB engine becomes a third consumer beside
the lighting and peripheral engines:

```csharp
// after the peripheral tap, matching on the MSOP_-stripped name
// (wire names: MSOP_P1_FFB_Constant, MSOP_P1_FFB_Spring, ...):
if (name.StartsWith("P1_FFB_", StringComparison.OrdinalIgnoreCase))
    _ffbEngine?.OnChannel(name[7..], value);   // "Constant", "Spring", ... , "Raw"
```

- Create the engine lazily on the first FFB line (zero cost for gun-only setups).
- `mame_start` / `mame_stop` markers must **hard-release all effects** (the classic "wheel keeps
  pulling after the game closed" failure). `OnClosed` disposes the engine (zero forces, free device).
- The existing dedup cache already suppresses cross-transport duplicates for these names.

## 2. The engine (`Hardware/Ffb/FfbEngine.cs` + `Sdl2Native.cs`)

**SDL2 via P/Invoke** is the proven route (it is the exact stack the FFB Arcade Plugin drives every
supported wheel through). ~15 imports; `SDL2.dll` (zlib licence) beside `MESH.exe`; the
`SDL_HapticEffect` C union marshalled at explicit offsets (verified layout: `type`@0, direction
type@4, dir[3]@8/12/16, `length`@20, envelope tail to @38, union size 72).

**Threading contract (matches every MESH transport):** all SDL calls confined to one background
thread; `DispatchStateLine` only enqueues into a bounded latest-wins queue (a stalled device can
never back-pressure the dispatch path).

**Channel → SDL effect mapping** (one persistent, infinite-length effect per channel, uploaded
once and updated in place — the "ConstantInf" pattern):

| MSOP output | SDL effect | Mapping |
| :--- | :--- | :--- |
| `FFB_Constant` | `SDL_HAPTIC_CONSTANT` | `level = abs(v)/100 * 32767 * maxForce%`; cartesian `dir.x = sign(v)` (+ = from right) |
| `FFB_Spring` | `SDL_HAPTIC_SPRING` (condition) | both-side `coeff = v/100 * 32767`, center 0 |
| `FFB_Friction` | `SDL_HAPTIC_FRICTION` (condition) | `coeff = v/100 * 32767` |
| `FFB_Damper` | `SDL_HAPTIC_DAMPER` (condition) | `coeff = v/100 * 32767` |
| `FFB_Sine` | `SDL_HAPTIC_SINE` (periodic) | `magnitude = v/100 * 32767`; period from config (default ~75 ms) |
| `FFB_Rumble` | `SDL_JoystickRumble` | sign picks motor: + → high-freq, − → low-freq; magnitude `abs(v)/100 * 65535` |
| `FFB_Raw` | — | diagnostics only (surface in the State Outputs tab like any output) |

**Degradation chain** so the pipeline is provable on any machine: full haptics → rumble-only
(pads; map `Constant`+`Rumble` magnitudes onto motors) → monitor-only (no SDL2.dll / no device;
log forces). Query `SDL_HapticQuery` caps per device and create only supported effects.

**Value semantics to honour:** outputs are change-only and channels **persist** until MSOP sends a
new value — the engine simply keeps each effect running at its last level; no refresh/timeout
logic is needed (but a watchdog zeroing everything if the relay connection drops is a worthwhile
safety, mirroring `mame_stop`).

## 3. Configuration (fits MESH's per-game override model)

Minimum viable (`ffb.json` in the settings folder, or folded into peripherals settings):

```json
{ "enabled": true, "deviceMatch": "", "maxForcePercent": 100, "invert": false, "sinePeriodMs": 75 }
```

- `deviceMatch` — substring to pick the wheel when several sticks exist; else first haptic device.
- `invert` — flips `Constant`/`Rumble` sign for wheels that pull the wrong way (the
  AlternativeFFB-style wheels the FFB Arcade Plugin documents).
- Per-game overrides (strength scaling per title) can ride the existing game_json profile chain
  later, exactly like lighting labels.

## 4. UI touchpoints (later, when promoted)

- Devices tab: an "FFB Wheel" device tile (status: constant-force / rumble-fallback / monitor).
- Diagnostics → Live Tests: inject `MSOP_P1_FFB_Constant = ±50` etc. — this already works today via
  the simulate-output path with zero new plumbing, and is the fastest hardware smoke test.
- Troubleshooting map: list the `FFB*` vocabulary like other outputs (the compiled-vocabulary
  chain picks the names up from the database automatically once the ffb channel merges to beta).

## 5. Effort estimate

The reverted spike was ~350 lines for constant-force + rumble + fallbacks + config; the condition
and periodic effects add roughly 100 more (same update-in-place pattern, different structs).
No new NuGet dependencies; ship `SDL2.dll` beside the exe (add to `THIRD-PARTY-NOTICES.txt`).
