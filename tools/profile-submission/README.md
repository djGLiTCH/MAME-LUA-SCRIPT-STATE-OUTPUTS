# MAME State Output Project (MSOP)
## MSOP Apply Profile

- **Created By:** Jacob Simpson (DJ GLiTCH)
- **Copyright:** (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
- **License:** GNU General Public License GPL-v3.0
- **Repository:** https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS

---

A maintainer tool for the **Game Profile Submission** issue form. It checks a submitted game profile
and places it in the beta game database. It is not part of the MSOP Database Compiler download.

## Use

1. Download the `<rom>.json` attached to the issue. If the person pasted the file's contents
   instead, save them as `<rom>.json`.
2. Check it:

   ```
   python msop_apply_profile.py <rom>.json
   ```

3. If it passes, write it to `tools/database-compiler/input/beta/database/games/<GAME_TYPE>/`:

   ```
   python msop_apply_profile.py <rom>.json --apply
   ```

`--rom <name>` gives the ROM name when the downloaded file was renamed. The script needs Python 3 and
nothing else.

## The Checks

| Check | Fails when |
|---|---|
| JSON | the file is not one JSON object, or a key is repeated |
| ROM name | the name is not a MAME short name (lower-case letters, digits and underscores, 16 at most) |
| `ENABLE_ROM` | it is not `true` |
| `LUA_GAME` | it is missing or empty |
| `GAME_TYPE` | it is given and is not `lightgun`, `racing` or `both` |
| Player addresses | a `lightgun` or `both` profile has no `STATUS` or `LIFE` address for any player |
| `FFB` | a `racing` profile has no `FFB` block with `ENABLED` set to `true` |
| Stable | the ROM is already in the stable database: a change to it is a correction |
| Beta | the ROM is already in the beta database under another `GAME_TYPE` folder |

A setting that `_default.json` does not have is reported as a warning. The profile is then listed as
new, changed (with the settings that differ) or the same as the beta profile.

Exit codes: `0` the profile passes, `1` a check failed, `2` the file was not found.

## After `--apply`

These steps stay with the maintainer, and the script lists them each time:

1. Add the ROM's row to `updates/msop-games.json`.
2. Add a line for the ROM to the database record in `updates/msop-changelog.json`, with the credit
   from the issue.
3. Rebuild the beta channel with `run_beta.bat` or `run_beta.sh` in
   `tools/database-compiler/scripts/`.
4. Move the profile to stable once it has been played on Beta.
