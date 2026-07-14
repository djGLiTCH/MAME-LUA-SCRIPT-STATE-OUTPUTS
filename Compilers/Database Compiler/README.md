# MAME State Output Project (MSOP)
## MSOP Database Compiler

- **Created By:** Jacob Simpson (DJ GLiTCH)
- **Copyright:** (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
- **License:** GNU General Public License GPL-v3.0
- **Repository:** https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS

---

Compiles the per-game MSOP configs into the MSOP Lua plugin's runtime database, (optionally) scrapes
a MAME source checkout for each game's native output names, and generates the per-game **Hook Of The
Reaper defaultLG** and **MAMEhooker .ini** starting templates from that same game data. Structured the
same way as the Hooker Compiler: `scripts/` = run, `input/` = edit, `output/` = generated,
`archive/` = history.

## Folder layout

Everything is split by **release channel** (`stable` / `beta`). A channel selects both the input a tool
reads (`input/<channel>/`) and the output it writes (`output/<channel>/`), so a beta database *and* its
experimental plugin code stay fully isolated from the shipped stable build.

```
Database Compiler/
├── scripts/            YOU RUN THIS
│   ├── msop_database_compiler.py         games <-> database.json, and -> database.lua
│   ├── msop_database_driver_compiler.py  MAME source -> database_driver.lua (+ scrape report)
│   ├── msop_hotr_defaultlg_generator.py  games -> output/<channel>/defaultLG/*.txt   (Hook Of The Reaper)
│   ├── msop_mamehooker_ini_generator.py  games -> output/<channel>/ini/*.ini         (MAMEhooker skeletons)
│   ├── msop_output_model.py              shared helper (init.lua-mirroring output derivation; not run directly)
│   ├── run_stable.* / run_beta.*         run the FULL pipeline for ONE channel (db -> driver -> defaultLG -> ini)
│   ├── run.bat / run.sh                  run the full pipeline for BOTH channels (stable then beta)
│   └── run_msop_*_generator.*            per-generator launchers (defaultLG only / ini only; take --channel)
│
├── input/              YOU EDIT THIS  -  split per release channel
│   ├── stable/         the STABLE source
│   │   ├── stateoutput/    plugin runtime: init.lua, plugin.json, readme.txt  (versions/dates auto-aligned on run)
│   │   └── database/       game data: games/*.json (one per ROM, + _default.json) + database.json mirror
│   └── beta/           the BETA source - a fully isolated copy (its own stateoutput/ + database/), so
│                       experimental games AND plugin code can never touch the shipped stable build
│
├── output/             GENERATED  (safe to delete; rebuilt on every run)  -  split per release channel
│   ├── stable/
│   │   ├── stateoutput/    deployable plugin: database.lua + database_driver.lua + init.lua/plugin.json/readme.txt
│   │   ├── defaultLG/      Hook Of The Reaper defaultLG/<rom>.txt templates
│   │   ├── ini/            MAMEhooker <rom>.ini skeletons ([Output] prepopulated with the game's MSOP outputs)
│   │   └── results/        mame_driver_native_output_scrape_report.json (driver audit aid)
│   └── beta/           same shape as stable/ (only present once you've built beta)
│
└── archive/            HISTORY (old script/init versions)
```

At a glance: **`scripts/` = run, `input/<channel>/` = edit, `output/<channel>/` = generated,
`archive/` = history.** Grab **`output/stable/stateoutput/`** as the finished stable plugin folder to
ship in an MSOP Plugin release (`output/beta/stateoutput/` for a beta).

## How to run

- **One channel, full pipeline (headless, no prompts):**
  - `scripts/run_stable.*` — reads `input/stable/`, runs db compile → driver → HOTR defaultLG →
    MAMEhooker ini, writing `output/stable/` with `plugin.json` stamped `channel = "stable"`.
  - `scripts/run_beta.*` — the same for `input/beta/` → `output/beta/`, stamped `"beta"`.
  - The driver step is **skipped** unless you set `MAME_SRC` at the top of the launcher to your MAME
    source checkout (the folder containing `src/mame`); the two template generators always run.
- **Both channels at once:** `scripts/run.bat` / `scripts/run.sh` — the full pipeline for stable then
  beta (a channel whose `input/<channel>/` is absent is simply skipped).
- **MSOP-only vs. driver-included:** the ini generator is **MSOP-only by default** — it lists only the
  plugin's own **MSOP state outputs** (+ each game's curated `ADDITIONAL_OUTPUT_FORWARDS`), not the
  scraped MAME native outputs. Pass **`--include-driver`** to also fold in the MAME natives from
  `database_driver.lua`. The full launchers `run_stable.*`/`run_beta.*` (and `run.*`) run the driver
  compiler and pass `--include-driver`, so their ini includes the MAME natives. The
  `run_stable_msop_only.*` / `run_beta_msop_only.*` launchers instead **skip the driver compiler** and
  drop `database_driver.lua` from the plugin folder, so the plugin *and* its ini are both driver-free.
  HOTR defaultLG is identical either way (it never uses the driver). (CI still packages a MSOP-only
  stable build — the missing driver is a warning, not a failure.)
- **Template generators on their own:** `scripts/run_msop_hotr_defaultlg_generator.*` (→
  `output/<channel>/defaultLG/`) and `scripts/run_msop_mamehooker_ini_generator.*` (→
  `output/<channel>/ini/`). Each accepts `--channel stable|beta` (default stable), `--report` (diff
  every file against the shipped references) and `--rom <name>` (one game).
- **Interactive database editing:** `python scripts/msop_database_compiler.py` with no argument opens
  the mode menu (mode 1 games→lua, mode 2 database.json→games) on the **stable** channel. The database
  and driver compilers also take an explicit `stable`|`beta` / `--channel`.

**Beta is a branch, not a stamp.** To cut a beta: copy `input/stable/` → `input/beta/`, make your
experimental edits there (new games, or an experimental `init.lua`/`plugin.json`), and run `run_beta`.
To promote it back: copy `input/beta/` → `input/stable/` (review the diff), bump versions, run
`run_stable`. Because each channel's plugin, HOTR and INI are all generated from that one channel's
database, a beta plugin can never be paired with stable-suited HOTR/INI. CI packages the STABLE zips
automatically and the BETA zips only once you commit `output/beta/`.

All scripts resolve their paths from the project root via `__file__`, so they run from any directory.

## What each does

- **`msop_database_compiler.py`** — two interactive modes (paths shown for the resolved `<channel>`):
  - **Mode 1:** `input/<channel>/database/games/*.json` → `input/<channel>/database/database.json` +
    `output/<channel>/stateoutput/database.lua`.
  - **Mode 2:** `input/<channel>/database/database.json` → `input/<channel>/database/games/*.json` +
    `output/<channel>/stateoutput/database.lua`.

  Either mode aligns the version/date across `init.lua`/`plugin.json`/`readme.txt` in
  `input/<channel>/stateoutput/` (including init.lua's `PLUGIN_VERSION_NUM`/`PLUGIN_DATE_NUM` constants)
  and copies them into `output/<channel>/stateoutput/`, so the output is a complete plugin folder. It
  needs no MAME source. A `stable`/`beta` argument selects the channel (its input+output tree) and
  stamps `plugin.json`'s `channel`, running mode 1 headlessly (see the launchers above); no argument =
  the interactive menu on **stable**. The deploy-time `relay` member (the per-install stamp the MESH app
  writes into installed copies) is always **stripped** from the source/shipped `plugin.json` if it ever
  leaks in — manual installs must self-detect.

- **`msop_database_driver_compiler.py`** — scrapes a MAME source checkout for each supported ROM's
  native output names and writes `output/<channel>/stateoutput/database_driver.lua` (the companion
  `init.lua` loads it; missing/stale just degrades to no native forwarding). Takes `--channel` (default
  stable; `--games-dir`/`--output-dir` override). With the scrape report enabled (default;
  `--no-scrape-report` to skip) it also writes
  `output/<channel>/results/mame_driver_native_output_scrape_report.json`.

- **`msop_hotr_defaultlg_generator.py`** — writes a Hook Of The Reaper `output/<channel>/defaultLG/<rom>.txt`
  for every supported game. Recoil & reload are always driven by the dedicated MSOP recoil/reload
  commands; ammo is **display only** (emitted only when the game has an active ammo output); life, damage
  and credits are always mapped; lamp-start when the game exposes it. Player count follows `MAX_PLAYERS`.

- **`msop_mamehooker_ini_generator.py`** — writes an empty MAMEhooker `output/<channel>/ini/<rom>.ini`
  skeleton for every supported game: the standard `[General]`/`[KeyStates]`/`[Output]` layout with
  `[Output]` prepopulated by every MSOP output that game emits (values left blank, ready for hardware
  commands).

- **`msop_output_model.py`** — a shared helper library (not run directly) holding the per-game output-set
  derivation that mirrors `init.lua`. Both generators import it so that logic lives in one place. **Keep
  it in sync** with the Hooker Compiler's `msop_plugin_output_generator.py`, which carries its own copy
  for the plugin JSON pipeline.
