#
# MAME STATE OUTPUT PROJECT (MSOP)
# MSOP OUTPUT MODEL - shared helper library (NOT a standalone runner)
# Version: 1.0.0
# Date: 2026.07.13
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
DB_GAMES   = os.path.join(BASE_DIR, "input", "database", "games")
DRIVER_LUA = os.path.join(BASE_DIR, "output", "stateoutput", "database_driver.lua")

# An output maps to a real Hooker event only if that event exists; identity except LampStart.
SUFFIX_EVENT = {
    "Ammo": "Ammo", "Life": "Life", "Recoil": "Recoil", "Reload": "Reload",
    "Damage": "Damage", "Rumble": "Rumble", "LampStart": "LED_Start",
}


# ---- game sources -----------------------------------------------------------
def load_default():
    return json.load(open(os.path.join(DB_GAMES, "_default.json"), encoding="utf-8"))


def load_game(rom):
    return json.load(open(os.path.join(DB_GAMES, rom + ".json"), encoding="utf-8"))


def supported_roms():
    for name in sorted(os.listdir(DB_GAMES)):
        if name.endswith(".json") and not name.startswith("_"):
            yield name[:-5]


def load_driver_natives():
    """{rom: [native_output_name, ...]} from database_driver.lua (raw MAME driver outputs the plugin
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
    out = {}

    def put(name, value):
        out[name] = value

    def event_value(suffix, p):
        ev = SUFFIX_EVENT.get(suffix)
        return "P{}_{}".format(p, ev) if ev else "false"

    for i in range(1, max_players + 1):
        a = active[i]
        gates = {
            "Ammo": "AMMO" in a, "AmmoAlt": "AMMO_ALT" in a, "AmmoGrenade": "AMMO_GRENADE" in a,
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
