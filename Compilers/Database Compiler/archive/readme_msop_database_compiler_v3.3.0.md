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

```
Database Compiler/
├── scripts/            YOU RUN THIS
│   ├── msop_database_compiler.py         games <-> database.json, and -> database.lua
│   ├── msop_database_driver_compiler.py  MAME source -> database_driver.lua (+ scrape report)
│   ├── msop_hotr_defaultlg_generator.py  games -> output/defaultLG/*.txt   (Hook Of The Reaper)
│   ├── msop_mamehooker_ini_generator.py  games -> output/ini/*.ini         (MAMEhooker skeletons)
│   ├── msop_output_model.py              shared helper (init.lua-mirroring output derivation; not run directly)
│   ├── run.bat / run.sh                  runs the FULL pipeline: db -> driver -> defaultLG -> ini
│   ├── run_stable.* / run_beta.*         headless channel db-compiles (stable/beta)
│   └── run_msop_*_generator.*            per-generator launchers (defaultLG only, or ini only)
│
├── input/              YOU EDIT THIS
│   ├── stateoutput/    the human-maintained plugin source:
│   │                   init.lua, plugin.json, readme.txt, README.md  (the plugin runtime; versions/dates auto-aligned on run)
│   └── database/       the game-data source:
│       ├── games/*.json    per-game configs (one file per ROM, + _default.json)
│       └── database.json   single-file mirror, interchangeable with games/
│
├── output/             GENERATED  (safe to delete; rebuilt on every run)
│   ├── stateoutput/    the deployable plugin folder for MSOP Plugin releases:
│   │                   database.lua + database_driver.lua + copies of init.lua/plugin.json/readme.txt
│   ├── defaultLG/      Hook Of The Reaper defaultLG/<rom>.txt templates
│   ├── ini/            MAMEhooker <rom>.ini skeletons (empty; [Output] prepopulated with the game's MSOP outputs)
│   └── results/        mame_driver_native_output_scrape_report.json (driver audit aid)
│
└── archive/            HISTORY (old script/init versions)
```

At a glance: **`scripts/` = run, `input/` = edit, `output/` = generated, `archive/` = history.**
Grab **`output/stateoutput/`** as the finished plugin folder to ship in an MSOP Plugin release.

## How to run

- `scripts/run.bat` (Windows) or `scripts/run.sh` (Linux/macOS) — runs the **full pipeline**: the
  database compiler (interactive mode menu) → the driver compiler → the HOTR defaultLG generator →
  the MAMEhooker ini generator. The driver step is **skipped** unless you set `MAME_SRC` at the top of
  the launcher to your MAME source checkout (the folder that contains `src/mame`); the two template
  generators always run.
- **Template generators on their own:** `scripts/run_msop_hotr_defaultlg_generator.*` (→ `output/defaultLG/`)
  and `scripts/run_msop_mamehooker_ini_generator.*` (→ `output/ini/`). Each accepts `--report` (diff
  every file against the shipped references) and `--rom <name>` (one game).
- **Release-channel launchers (headless, no prompts):**
  - `scripts/run_stable.bat` / `scripts/run_stable.sh` — stamps `plugin.json` `channel = "stable"`,
    syncs versions/dates in `input/`, then compiles (mode 1). `output/stateoutput/` comes out tagged
    STABLE, ready to zip.
  - `scripts/run_beta.bat` / `scripts/run_beta.sh` — same, tagged BETA.
  - Equivalent direct calls: `python scripts/msop_database_compiler.py stable` (or `beta`). Any other
    argument prints usage and exits with code 2.
- Or run either script directly with no argument for the interactive menu:
  `python scripts/msop_database_compiler.py` / `python scripts/msop_database_driver_compiler.py`.

All scripts resolve their paths from the project root via `__file__`, so they run from any directory.

## What each does

- **`msop_database_compiler.py`** — two interactive modes:
  - **Mode 1:** `input/database/games/*.json` → `input/database/database.json` +
    `output/stateoutput/database.lua`.
  - **Mode 2:** `input/database/database.json` → `input/database/games/*.json` +
    `output/stateoutput/database.lua`.

  Either mode aligns the version/date across `init.lua`/`plugin.json`/`readme.txt`/`README.md` in
  `input/stateoutput/` (including init.lua's `PLUGIN_VERSION_NUM`/`PLUGIN_DATE_NUM` constants) and
  copies them into `output/stateoutput/`, so the output is a complete plugin folder. It needs no MAME
  source. With a `stable`/`beta` argument it additionally stamps `plugin.json`'s `channel` and runs
  mode 1 headlessly (see the release-channel launchers above). The deploy-time `relay` member (the
  per-install stamp the MESH app writes into installed copies) is always **stripped** from the
  source/shipped `plugin.json` if it ever leaks in — manual installs must self-detect.

- **`msop_database_driver_compiler.py`** — scrapes a MAME source checkout for each supported ROM's
  native output names and writes `output/stateoutput/database_driver.lua` (the companion `init.lua`
  loads it; missing/stale just degrades to no native forwarding). With the scrape report enabled
  (default; `--no-scrape-report` to skip) it also writes
  `output/results/mame_driver_native_output_scrape_report.json`.

- **`msop_hotr_defaultlg_generator.py`** — writes a Hook Of The Reaper `output/defaultLG/<rom>.txt` for
  every supported game. Recoil & reload are always driven by the dedicated MSOP recoil/reload commands;
  ammo is **display only** (emitted only when the game has an active ammo output); life, damage and
  credits are always mapped; lamp-start when the game exposes it. Player count follows `MAX_PLAYERS`.

- **`msop_mamehooker_ini_generator.py`** — writes an empty MAMEhooker `output/ini/<rom>.ini` skeleton for
  every supported game: the standard `[General]`/`[KeyStates]`/`[Output]` layout with `[Output]`
  prepopulated by every MSOP output that game emits (values left blank, ready for hardware commands).

- **`msop_output_model.py`** — a shared helper library (not run directly) holding the per-game output-set
  derivation that mirrors `init.lua`. Both generators import it so that logic lives in one place. **Keep
  it in sync** with the Hooker Compiler's `msop_plugin_output_generator.py`, which carries its own copy
  for the plugin JSON pipeline.
