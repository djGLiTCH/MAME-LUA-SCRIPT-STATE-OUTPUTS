# MSOP Beta v9.2.0 — Force Feedback State Outputs (Testing Guide)

**Contract:** `MESH\docs\FFB-MSOP-CONTRACT.md` is the authoritative vocabulary contract agreed
with the MESH side (whose SDL3 engine is built and rumble-validated). Beta v9.2.0 implements it.
**Scope:** the FFB work now lives in the **beta channel** (`input/beta/` → `output/beta/`),
promoted from the temporary development channel. The stable channel is untouched.

## The standardized FFB vocabulary (contract-locked)

### Stream channels — continuous, persist until changed

| Output | Range | Meaning |
| :--- | :--- | :--- |
| `MSOP_P1_FFB_Constant` | −255..+255 (Signed255) | directional push force; **positive = force from the right** (wheel pushed left), 0 = release |
| `MSOP_P1_FFB_Spring` | 0..255 | self-centering spring strength |
| `MSOP_P1_FFB_Friction` | 0..255 | steering friction / clutch drag |
| `MSOP_P1_FFB_Damper` | 0..255 | velocity damping strength |
| `MSOP_P1_FFB_Sine` | 0..255 | drive-board-commanded shake strength (period = consumer tuning knob) |
| `MSOP_P1_FFB_Rumble` | 0..255 (**unsigned**) | continuous force-correlated motor level; motor routing + direction derivation are consumer-side (from `FFB_Constant`'s sign) |
| `MSOP_P1_FFB_Raw` | raw | undecoded source value (diagnostics, new-game analysis) |

`FFB_Rumble` deliberately **coexists** with the standard pulse-style `P<n>_Rumble` (lightgun/
environmental heritage) — different semantics (held level vs pulse). Single-rumble-path
consumers mix by **MAX, never sum**.

**Scale rationale (255 not 100):** lossless for every known source encoding (full-value games
= ±127 levels, Namco LUT ≈ 123); ±100 would collapse adjacent source levels at the
standardization choke point. MESH parses Signed255/Unsigned255 natively.

### Semantic events — pulse/level style, 0..255, address-sourced

`MSOP_P1_FFB_Collision` · `FFB_GearChange` · `FFB_SurfaceRumble` · `FFB_TyreSlip` ·
`FFB_EngineRumble` — optional per game, read from separate per-game **memory addresses**
(the gun games' Damage/Rumble acquisition model; address-only by contract). Configured via
the profile's `FFB.EVENTS` block:

```json
"FFB": {
    "ENABLED": true,
    "SOURCES": ["wheel"],
    "DECODE": "konami_dir4",
    "SCALE": 255,
    "PLAYER": 1,
    "EVENTS": {
        "COLLISION":     { "SOURCE": "0x00123456", "MODE": "increase", "STRENGTH": 255, "DURATION_MS": 150 },
        "SURFACERUMBLE": { "SOURCE": "0x00123458", "MODE": "nonzero",  "STRENGTH": 140 },
        "TYRESLIP":      { "SOURCE": "0x0012345A", "MODE": "value",    "MAX": 255 }
    }
}
```

Modes: `nonzero` (level: STRENGTH while the flag byte ≠ 0), `change` / `increase` (pulse
STRENGTH for `DURATION_MS` on change / on counter increase), `value` (raw scaled 0..255
against `MAX`). `WIDTH` overrides `DATA_WIDTHS.FFB` per event. Events work with empty
`SOURCES` too (events-only profiles).

**Command semantics (all outputs):** on-change emission only; decoders update only the
channels a game command addresses this frame — unlisted channels persist (drive boards
receive commands, not state snapshots); explicit 0 releases; warmup holds everything at 0;
everything zeroed at game exit.

## GAME_TYPE (new in v9.2.0)

Per-game genre gate: `"lightgun"` (default — existing profiles unaffected), `"racing"`,
`"both"`. Racing profiles **skip the per-player gun pipeline** each frame and compile **only
the FFB vocabulary** (so the warmup zero-flush and relay never carry gun output names the ROM
can never drive — and gun games never carry FFB names). Globals (`Credits`/`GameStatus`/
`AttractStatus`) apply to every type. Use `"both"` for hybrids (e.g. a racing game that also
tracks life/damage). Unknown values degrade to `lightgun`.

## Acquisition (`FFB` block per game profile)

`SOURCES` probed in order per frame until one resolves:
- **`"0x..."` hex** = emulated **memory address** (canonical MSOP path, same as gun Ammo/Life) via
  `CPU_TAGS.FFB` / `MEMORY_SPACES.FFB` / `DATA_WIDTHS.FFB`.
- **Plain string** = **native output name** — resolved through the plugin's exact `device.outputs`
  enumeration first (subdevice-capable), then a side-effect-free root probe.

## Supported racing games (145 ROMs, 11 decoder families)

Every ROM the FFB Arcade Plugin projects drive through a decodable MAME output now has a
profile. Decoding mirrors those projects' per-game readers (GPLv3); **none are hardware
validated yet**.

| Decoder | ROMs | Source output | Games |
| :--- | ---: | :--- | :--- |
| `harddrivin_serial` | 35 | `wheel` | Hard Drivin', Race Drivin', Hard Drivin's Airborne (all revisions) |
| `konami_dir4` | 34 | `wheel` family | Thrill Drive, GTI Club, Midnight Run, Winding Heat, Racing Jam 1/2 |
| `signed8` | 27 | `wheel` / `wheel_motor` | Cruis'n USA/World, San Francisco Rush + 2049 + The Rock, Off Road Challenge, California Speed, Cart Fury, Hyperdrive, Vapor TRX |
| `flag_shake` | 16 | `MA_Steering_Wheel_motor` family, `led2` | OutRunners, Turbo OutRun, Chase Bombers, Double Axle, Cisco Heat, F-1 Grand Prix Star 1/2 |
| `model2_bands` | 13 | `wheel_motor` | Daytona USA, Indianapolis 500, Sega Touring Car, Over Rev, Super GT 24h |
| `pdrift_8step` | 5 | `bank_motor_position` | Power Drift |
| `sega_rally_bands` | 4 | `wheel_motor` | Sega Rally Championship |
| `namco_lut_rr` | 4 | `wheel_motor` | Rave Racer |
| `sidebs_5bit` | 4 | `wheel_motor` | Side by Side 1/2 |
| `hng64_bands` | 2 | `wheel_motor` | Roads Edge, Xtreme Rally |
| `virtua_racing` | 1 | `digit0` | Virtua Racing |

`INVERT: true` is set on the 17 Cruis'n / San Francisco Rush ROMs, whose wheel output uses the
opposite direction convention to the otherwise identical California Speed / Cart Fury group.

**Start here:** `thrilld` (Thrill Drive) is the primary test game - a simple decoder on a
native output. `overrev` exercises the multi-channel banded path, and `harddriv` exercises the
stateful frame reassembly, so those two are the most valuable second tests.

**Per-game prerequisites** carried in the profiles: Rave Racer needs feedback enabled in its
service menu; Over Rev needs its output mode changed there; Virtua Racing must be set to
UPRIGHT cabinet; the Side by Side pair are under-clocked in MAME and are scaffolding only.

### Not yet supported (14 ROMs)

| Games | Why |
| :--- | :--- |
| Super Chase (4), Dirt Dash (3), Ace Driver + Victory Lap (4) | The plugin obtains the force by **signature-scanning host memory** - it has no MAME output to read. MSOP needs the equivalent **emulated** RAM address instead; find it with MAME's debugger and add it to `SOURCES` as a `"0x..."` string (no plugin change needed). |
| OutRun (3) | Needs **two** outputs combined (`Bank_Motor_Direction` for sign + `Bank_Motor_Speed` for magnitude). The current schema resolves a single source per profile. |

## Install & run

1. Copy the assembled beta plugin folder `output/beta/stateoutput/` into `MAME\plugins\` (it
   contains `init.lua`, `plugin.json`, `readme.txt`, `database.lua`).
2. `mame.ini`: `output none` · `plugin.ini`: `plugins 1` (normal relay install)
3. `mame thrilld -verbose`
4. Watch for `[MSOP] FFB: source resolved to native output '<name>' (enumerated)`, then observe
   `MSOP_P1_FFB_*` lines on the relay (any listener on 127.0.0.1:8000).

Rebuild after profile/decoder edits: `python scripts/msop_database_compiler.py beta`
(or the `run_beta` launcher).

## Troubleshooting

- **`FFB WARNING: no source found after 600 frames`** — none of the candidate names exist for this
  ROM on your MAME build. The plugin's enumeration log in `-verbose` shows what the machine actually
  created; add the real name to that game's `SOURCES` and recompile.
- **`FFB_Raw` moves but decoded channels look wrong** — the encoding differs from the reference;
  capture a session of `FFB_Raw` values against what the game was doing and adjust/add a decoder in
  `_FFB.decoders` (init.lua).
- **Direction inverted** — consumer-side flip (MESH `Invert`); the sign convention here is
  fixed: positive = force from the right.
