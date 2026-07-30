#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP OUTPUT MODEL - shared helper library (NOT a standalone runner)
# Version: 1.3.0
# Date: 2026.07.31
# Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
# License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
# Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
#
# The authoritative per-game state-output derivation, mirroring init.lua's own output logic. Imported
# by BOTH the HOTR defaultLG generator and the MAMEhooker .ini generator so the "which outputs does
# this game emit" logic lives in ONE place. KEEP IN SYNC with the Hooker Compiler's
# msop_plugin_output_generator.py, which carries its own copy for its JSON pipeline - if init.lua's
# emission rules change, update both.
#
# Paths are root-anchored via __file__ (this file lives in Database Compiler/scripts/).
#

import os
import re
import json

HERE      = os.path.dirname(os.path.abspath(__file__))
BASE_DIR  = os.path.dirname(HERE)                                 # Database Compiler/
REPO_ROOT = os.path.abspath(os.path.join(BASE_DIR, "..", ".."))   # repo root

# Release channel selects BOTH the input game-data set and the output tree, so the stable and beta
# ecosystems never cross-contaminate: everything derived from the database (this model + both
# generators) reads input/<channel>/... and output/<channel>/.... Default is "stable"; call
# set_channel("beta") - as the generators do from their --channel flag - to repoint every path below.
CHANNEL    = "stable"
DB_GAMES   = os.path.join(BASE_DIR, "input", CHANNEL, "database", "games")
DRIVER_LUA = os.path.join(BASE_DIR, "output", CHANNEL, "stateoutput", "native_outputs_by_rom.lua")


def set_channel(channel):
    """Repoint DB_GAMES + DRIVER_LUA at input/<channel>/ and output/<channel>/. Call this BEFORE any
    load_default / load_game / supported_roms / load_driver_natives so they read the right channel."""
    global CHANNEL, DB_GAMES, DRIVER_LUA
    CHANNEL    = channel
    DB_GAMES   = os.path.join(BASE_DIR, "input", channel, "database", "games")
    DRIVER_LUA = os.path.join(BASE_DIR, "output", channel, "stateoutput", "native_outputs_by_rom.lua")

# An output maps to a real Hooker event only if that event exists; identity except LampStart.
SUFFIX_EVENT = {
    "Ammo": "Ammo", "Life": "Life", "Recoil": "Recoil", "Reload": "Reload",
    "Damage": "Damage", "Rumble": "Rumble", "LampStart": "LED_Start",
}


# ---- game sources -----------------------------------------------------------
class GameDataError(Exception):
    """A game JSON file could not be read/parsed. Its str() is a single, actionable line naming the
    FULL file path plus (for a syntax error) the exact line and column - so a caller can print it as-is
    instead of dumping a raw json traceback that never names which file broke. Callers should catch
    this, print it, and exit non-zero rather than let it propagate as an unhandled traceback."""


def load_json(path):
    """Read + parse one JSON file, turning the two failure modes into a GameDataError whose message
    points straight at the problem: a missing/unreadable file, or a syntax error at a specific
    line:column. Keeps the 'where exactly is the error' detail that a bare json.load buries in a
    traceback."""
    try:
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    except FileNotFoundError:
        raise GameDataError("Missing file: {}".format(path)) from None
    except json.JSONDecodeError as e:
        raise GameDataError(
            "JSON syntax error in {}\n    line {}, column {}: {}".format(path, e.lineno, e.colno, e.msg)
        ) from None
    except OSError as e:
        raise GameDataError("Could not read {}\n    {}".format(path, e)) from None


def load_default():
    return load_json(os.path.join(DB_GAMES, "_default.json"))


def load_game(rom):
    return load_json(os.path.join(DB_GAMES, rom + ".json"))


def supported_roms():
    for name in sorted(os.listdir(DB_GAMES)):
        if name.endswith(".json") and not name.startswith("_"):
            yield name[:-5]


def load_driver_natives():
    """{rom: [native_output_name, ...]} from native_outputs_by_rom.lua (raw MAME driver outputs the plugin
    forwards verbatim). Returns {} if the driver was never compiled."""
    if not os.path.exists(DRIVER_LUA):
        return {}
    txt = open(DRIVER_LUA, encoding="utf-8").read()
    natives = {}
    for m in re.finditer(r'\["([^"]+)"\]\s*=\s*\{(.*?)\}', txt, re.S):
        natives[m.group(1)] = re.findall(r'"([^"]+)"', m.group(2))
    return natives


# ---- output-set derivation (mirrors init.lua) -------------------------------
def truthy(v):
    """A resolved config field is 'active' (drives an output) when it isn't false/None/empty."""
    if v is None or v is False:
        return False
    if isinstance(v, str) and v.strip().lower() in ("", "false"):
        return False
    return True


def resolve_players(game, default):
    """Per player index, the set of ACTIVE (output-driving) config fields - replicating init.lua's
    resolution (P1 auto-hardware survives only if its source exists; P2..MAX_PLAYERS mirror P1)."""
    def merged(pkey):
        m = dict(default.get(pkey, {}))
        m.update(game.get(pkey, {}))
        if "LAMP_START" in m and "LAMPSTART" not in m:
            m["LAMPSTART"] = m.pop("LAMP_START")
        return m

    max_players = game.get("MAX_PLAYERS", default.get("MAX_PLAYERS", 2))
    p1 = merged("P1")

    has_ammo = truthy(p1.get("AMMO")) or truthy(p1.get("AMMO_ALT")) or truthy(p1.get("AMMO_GRENADE"))
    has_life = truthy(p1.get("LIFE")) or truthy(p1.get("LIFE_ALT"))
    for key in ("RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMPSTART"):
        if p1.get(key) == "auto":
            if key in ("RECOIL", "RELOAD") and has_ammo:      pass
            elif key == "DAMAGE" and has_life:                pass
            elif key == "LAMPSTART":                          pass
            else:                                             p1[key] = False

    active = {1: {k for k, v in p1.items() if truthy(v)}}
    for i in range(2, int(max_players) + 1):
        pi = merged("P" + str(i))
        act = set()
        for k, v in pi.items():
            if v == "auto":
                if k in active[1]:
                    act.add(k)
            elif truthy(v):
                act.add(k)
        active[i] = act
    return active, int(max_players)


def build_outputs(game, default, natives=None):
    """The COMPLETE set of outputs the plugin emits for this game, as {output_name: event_or_false}."""
    active, max_players = resolve_players(game, default)
    flag = lambda k: bool(game.get(k, default.get(k, True)))
    demul = flag("DEMULSHOOTER_COMPATIBILITY")

    # GAME_TYPE (plugin v9.2.0): mirrors init.lua's genre gate. "racing" compiles only the
    # FFB vocabulary (the gun per-player set and DemulShooter aliases are skipped);
    # "lightgun" (default, incl. unknown values) compiles everything except FFB names;
    # "both" compiles all. Globals are genre-neutral and unaffected.
    game_type = str(game.get("GAME_TYPE", default.get("GAME_TYPE", "lightgun")) or "").strip().lower()
    if game_type not in ("racing", "both"):
        game_type = "lightgun"

    # P*_Clip (plugin v9.0.1) is DERIVED from the primary ammo rather than read from memory: 1 while
    # ammo > 0, 0 the moment it empties (a reload is needed). KEEP IN SYNC with init.lua's _ClipEnabled:
    # it is only emitted for a genuinely DEPLETING clip, because that is the only reading where 0
    # unambiguously means empty.
    #   * "decrease" -> a real clip counting down to 0. Emitted.
    #   * increase   -> the address is a shots-FIRED counter, so 0 means a FULL clip and the flag would
    #                   be exactly inverted. Never emitted.
    #   * "change"   -> direction unknown, so it carries the same inversion risk. Never emitted.
    ammo_dir = str(game.get("AMMO_DIRECTION", default.get("AMMO_DIRECTION", "")) or "").strip().lower()
    clip_enabled = (ammo_dir == "decrease")

    out = {}

    def put(name, value):
        out[name] = value

    def event_value(suffix, p):
        ev = SUFFIX_EVENT.get(suffix)
        return "P{}_{}".format(p, ev) if ev else "false"

    # GAME_TYPE gate: "racing" profiles skip the entire gun per-player set (mirrors
    # init.lua v9.2.0's zero-iteration player loop + vocabulary filter).
    if game_type != "racing":
        for i in range(1, max_players + 1):
            a = active[i]
            gates = {
                "Ammo": "AMMO" in a, "AmmoAlt": "AMMO_ALT" in a, "AmmoGrenade": "AMMO_GRENADE" in a,
                "Clip": ("AMMO" in a) and clip_enabled,
                "Life": "LIFE" in a, "LifeAlt": "LIFE_ALT" in a,
                "Status": "STATUS" in a, "StatusAlt": "STATUS_ALT" in a,
                "Recoil": "RECOIL" in a, "Reload": "RELOAD" in a, "Damage": "DAMAGE" in a,
                "Rumble": "RUMBLE" in a, "LampStart": "LAMPSTART" in a,
                "ShotsFiredPrimary": ("AMMO" in a) and flag("ENABLE_SHOT_COUNT"),
                "ShotsFiredAlt":     ("AMMO_ALT" in a) and flag("ENABLE_SHOT_COUNT"),
                "ShotsFiredGrenade": ("AMMO_GRENADE" in a) and flag("ENABLE_SHOT_COUNT"),
                "LifeLost":   (("LIFE" in a) or ("LIFE_ALT" in a)) and flag("ENABLE_LIFE_LOST"),
                "DamageTaken": (("LIFE" in a) or ("LIFE_ALT" in a) or ("DAMAGE" in a)) and flag("ENABLE_DAMAGE_COUNT"),
                "CreditsInserted": ("CREDITS" in a) and flag("ENABLE_CREDIT_COUNT"),
                "CreditsConsumed": ("CREDITS" in a) and flag("ENABLE_CREDIT_COUNT"),
            }
            for suffix, on in gates.items():
                if on:
                    put("MSOP_P{}_{}".format(i, suffix), event_value(suffix, i))
            if demul:
                if gates["Recoil"]:    put("P{}_CtmRecoil".format(i), "false")
                if gates["Damage"]:    put("P{}_Damaged".format(i), "false")
                if gates["LampStart"]: put("P{}_CtmLmpStart".format(i), "false")

    # FFB vocabulary (plugin v9.2.0, GAME_TYPE racing/both + FFB.ENABLED): mirrors
    # _FFB.Compute's warmup zero-flush - the six stream channels + FFB_Raw always emit
    # for an enabled profile (for its configured PLAYER index), plus one output per
    # configured EVENTS key. Suffixes match _default's OUTPUT_SUFFIXES. No hooker
    # event mapping yet (values "false"), same as the informational outputs.
    ffb = dict(default.get("FFB", {}) or {})
    ffb.update(game.get("FFB", {}) or {})
    if game_type in ("racing", "both") and ffb.get("ENABLED") is True:
        try:
            fp = int(ffb.get("PLAYER", 1))
        except (TypeError, ValueError):
            fp = 1
        if fp < 1 or fp > max_players:
            fp = 1
        for suffix in ("FFB_Constant", "FFB_Spring", "FFB_Friction", "FFB_Damper",
                       "FFB_Sine", "FFB_Rumble", "FFB_Raw"):
            put("MSOP_P{}_{}".format(fp, suffix), "false")
        ffb_event_suffix = {
            "COLLISION": "FFB_Collision", "GEARCHANGE": "FFB_GearChange",
            "SURFACERUMBLE": "FFB_SurfaceRumble", "TYRESLIP": "FFB_TyreSlip",
            "ENGINERUMBLE": "FFB_EngineRumble",
        }
        for key in (ffb.get("EVENTS") or {}):
            sfx = ffb_event_suffix.get(str(key).upper())
            if sfx:
                put("MSOP_P{}_{}".format(fp, sfx), "false")

    put("MSOP_Credits", "false")
    put("MSOP_GameStatus", "false")
    put("MSOP_AttractStatus", "false")
    put("MSOP_GlobalCreditsInserted", "false")
    put("MSOP_LuaVersion", "false")
    put("MSOP_LuaDate", "false")
    put("MSOP_LuaROMid", "false")
    put("System_AspectRatio", "AspectRatio_4_3")

    for native_name in list(natives or []) + list(game.get("ADDITIONAL_OUTPUT_FORWARDS", []) or []):
        out.setdefault(native_name, "false")
    return dict(sorted(out.items()))


# ---- shared file / diff utilities -------------------------------------------
def write_lines(path, lines, eol, trailing):
    text = eol.join(lines) + (eol if trailing else "")
    with open(path, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    return text


def read_text(path):
    with open(path, encoding="utf-8", newline="") as fh:
        return fh.read()


def diff_summary(generated, ref_path):
    """Short human summary of how generated text differs from a reference file (line-set based)."""
    if not os.path.exists(ref_path):
        return "NEW (no reference)"
    g = generated.replace("\r\n", "\n").split("\n")
    e = read_text(ref_path).replace("\r\n", "\n").split("\n")
    if g == e:
        return None
    gs, es = set(g), set(e)
    added   = sorted({l for l in g if l not in es and l.strip()})
    removed = sorted({l for l in e if l not in gs and l.strip()})
    bits = []
    if len(g) != len(e):
        bits.append(f"lines {len(e)}->{len(g)}")
    if added:
        bits.append("added: " + ", ".join(added[:5]))
    if removed:
        bits.append("removed: " + ", ".join(removed[:5]))
    return "; ".join(bits)
