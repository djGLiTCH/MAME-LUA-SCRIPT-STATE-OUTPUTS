-- =========================================================================================
-- MAME STATE OUTPUT PROJECT (MSOP)
-- MSOP PLUGIN
-- Plugin Version: 9.4.2
-- Plugin Date: 2026.10.20
-- Project: https://github.com/djGLiTCH/MAME-LUA-SCRIPT-STATE-OUTPUTS
-- License: GNU GENERAL PUBLIC LICENSE GPL-v3.0
-- Copyright (c) 2026 Jacob Simpson (DJ GLiTCH). All Rights Reserved.
-- =========================================================================================
--
-- SPECIAL THANKS:
-- The racing force feedback support in this plugin stands on protocol research from the
-- FFB Arcade Plugin family of projects by Boomslangnz, and its MAME racing fork
-- FFBPluginRacerMAME by Endprodukt (both GPL v3.0):
--   https://github.com/Boomslangnz/FFBArcadePlugin
--   https://github.com/Endprodukt/FFBPluginRacerMAME
-- Those projects did the hardware-level detective work: which output ports each arcade
-- drive board listens on, what its command bytes mean (band edges, bit masks, sign
-- conventions), and which games speak which protocol. MSOP's _FFB decoders re-implement
-- that decoding knowledge in Lua, mapped onto MSOP's own architecture: in-process
-- per-frame sampling, the standardised FFB_* output vocabulary with persist-until-
-- changed semantics, the TCP relay transport, JSON game profiles, and memory-address
-- force sourcing - none of which exist in those projects. Without their published
-- findings, supporting 146 racing games would have required redoing years of
-- per-cabinet reverse engineering. Thank you.
--
-- =========================================================================================
--
-- ARCHITECTURE OVERVIEW:
-- A native MAME plugin, loaded once when MAME starts. A machine's output table is fixed, so
-- MSOP's own outputs are delivered over the TCP relay (see RELAY TRANSPORT LAYER) and MAME's
-- native outputs are only read (see Enumerate_Native_Outputs). Two hooks run per machine
-- session and must stay separate:
--
--   1. emu.add_machine_reset_notifier -> on_start()
--      Runs on every reset of the current machine, including a soft reset. Loads the ROM's
--      profile, resolves the memory addresses and starts the per-frame loop.
--
--   2. emu.add_machine_post_load_notifier -> on_post_load()
--      Realigns the baselines and pulse timers after a state load. Never reloads the profile.
--
-- =========================================================================================

local exports = {
    name = "stateoutput",
    version = "9.4.2",
    description = "MAME State Output Project (MSOP)",
    license = "GNU GPL-v3.0",
    author = "Jacob Simpson (DJ GLiTCH)",

    -- MAME stops calling a notifier once its subscription object is garbage collected. Each
    -- subscription is stored in this table so that it stays alive for the whole MAME session.

    subscriptions = {}
}

local stateoutput = exports

-- =========================================================================
-- GENERAL USER SETTINGS
-- =========================================================================
local ENABLE_OSD = false -- shows "[MSOP]" messages on screen; console messages always print

-- =========================================================================
-- CORE PLUGIN ENGINE
-- =========================================================================
function stateoutput.startplugin()

    -- -------------------------------------------------------------------------
    -- SAFE MODULE LOADING
    -- database.lua is loaded through pcall. A missing file or a syntax error leaves db as an empty
    -- table instead of raising an error.
    -- -------------------------------------------------------------------------
    local success, db = pcall(require, "stateoutput/database")
    if not success then
        success, db = pcall(require, "database") -- fallback for flat directories
        if not success then db = {} end
    end

    -- native_outputs_by_rom.lua is optional. msop_native_outputs_compiler.py generates it from a
    -- MAME source checkout, and it lists each ROM's native outputs (the driver's own outputs, such
    -- as "lamp0"). It is read only when the build cannot enumerate outputs. Without it, forwarding
    -- falls back to the profile's ADDITIONAL_OUTPUT_FORWARDS.
    local success_driver, driver_db = pcall(require, "stateoutput/native_outputs_by_rom")
    if not success_driver then
        success_driver, driver_db = pcall(require, "native_outputs_by_rom")
        if not success_driver then driver_db = {} end
    end

    -- native_outputs_by_driver.lua is the optional driver-keyed companion. MAME declares its
    -- output_finder<> fields once per driver source file and every ROM built from that file shares
    -- them, so one entry covers every ROM in the driver. Pass-through mode reads it when a ROM has
    -- no entry of its own.
    local success_mame_driver, mame_driver_db = pcall(require, "stateoutput/native_outputs_by_driver")
    if not success_mame_driver then
        success_mame_driver, mame_driver_db = pcall(require, "native_outputs_by_driver")
        if not success_mame_driver then mame_driver_db = {} end
    end

    -- ---------------------------------------------------------------------
    -- relay mode (per-instance, stamped by the MSOP Configurator)
    -- ---------------------------------------------------------------------
    -- _UseRelay is true when MSOP outputs go through the MESH relay on port _RelayPort, and false
    -- (the default) when MAME's own output module delivers them. resolve_relay_mode sets it on the
    -- first on_start; Probe_Legacy_Set_Value forces it to true when the build cannot create
    -- outputs. The "relay" member MESH stamps into plugin.json is read only when detection fails:
    --   relay = true  when this build cannot deliver MSOP outputs itself:
    --       * MAME 0.289 and later (Lua cannot create outputs at all), or
    --       * MAME 0.288 and earlier with -output none / console (outputs are created
    --         but MAME never broadcasts them to hooker programs).
    --   relay = false when MAME broadcasts them itself and no socket is needed:
    --       * MAME 0.288 and earlier with -output network (MAME's own server delivers
    --         everything on port 8000), or
    --       * -output windows (MAME's Windows-message broadcast).
    local _UseRelay = false
    local _RelayModeResolved = false   -- guards the one-time runtime resolution

    -- The active game's merged profile, or nil when the ROM has no enabled profile.
    local CFG = nil

    -- The native output forward records for this ROM, resolved once per ROM load in on_start. See
    -- Forward_Native_Outputs for the record fields.
    local _NativeForwards = {}

    -- While true, Get_Output_Proxy and Forward_Native_Outputs do not cache a missing output and
    -- retry it on a later frame. Pass-through mode sets it, because a driver output can be created
    -- after on_start runs (a device that starts late, or an output created on its first write).
    local _RetryMissingProxies = false

    -- Whether this build has the read-only device.outputs property (a container of live output
    -- proxies keyed by name). nil means not yet probed; Enumerate_Native_Outputs probes once per
    -- session. Stock MAME 0.290 and later has it. MAME 0.289 and earlier does not, and native
    -- output discovery then falls back to the scraped database files.
    local _EnumerateOutputsSupported = nil

    -- _LegacyCreateWorks says whether the deprecated output.set_value() can still create an output
    -- (true on MAME 0.288 and earlier, false on stock MAME 0.289 and later). Probe_Legacy_Set_Value
    -- fills both in. They are declared here because resolve_relay_mode reads them and needs them in
    -- scope.
    local _LegacyCreateProbed = false
    local _LegacyCreateWorks = true

    -- The TCP port the relay dials: the MESH ingest listener, default 8004. plugin.json's
    -- "relayport" member overrides it (see resolve_relay_mode). The plugin never binds or dials
    -- port 8000, which belongs to MAME's own -output network server.
    local _RelayPort = 8004
    -- True when MAME's -output mode is "network", so MAME's own output server is broadcasting every
    -- native output on port 8000. resolve_relay_mode sets it once. Native output forwarding stands
    -- down while it is true.
    local _MameServesNetwork = false
    -- True when the relay is required and MAME's -output mode is "network", which only
    -- delivers MSOP's outputs on MAME 0.288 and earlier. Drives the one-shot "INCORRECT
    -- OUTPUT MODE" notice in on_start. "windows" and "auto" never set it.
    local _MisconfiguredOutputMode = false
    -- True when the relay is required and MAME's -output mode is "windows". MAME sends
    -- the native outputs as Windows messages and MSOP's outputs go over the relay. A
    -- program that only reads Windows messages receives the native outputs only, which
    -- the one-shot note in on_start says.
    local _WindowsOutputWithRelay = false

    -- The plugin identity published as the MSOP_Plugin_Version and MSOP_Plugin_Date outputs. Keep
    -- both in step with the file header and exports.version (the version digits without the dots).
    -- CFG.LUA_VERSION and CFG.LUA_DATE describe the database release and are not used here.
    local PLUGIN_VERSION_NUM = 942
    local PLUGIN_DATE_NUM    = 20261020

    -- -------------------------------------------------------------------------
    -- ENGINE STATE VARIABLES
    -- These variables persist between frames and hold the previous state that each frame's triggers
    -- are compared against.
    -- -------------------------------------------------------------------------
    local _HasCoinedUp = false
    local _IsShuttingDown = false
    -- _FrameHookActive is true while Compute_Outputs should run. _LegacyFrameHooked records that
    -- emu.register_frame_done has been called: that registration cannot be removed, so it is made
    -- once per MAME session and gated by _FrameHookActive.
    local _FrameHookActive = false
    local _LegacyFrameHooked = false
    local _GameActiveTick
    -- True once the game's status debounce has elapsed, so that the elapsed time is not computed
    -- again in every active frame. Each player has the same latch in Debounced.
    local _GameDebounced = false
    -- Counts of failed frames, by routine. The first failure is logged, then every 600th, so that
    -- a persistent error does not print in every frame. on_start clears them.
    local _ErrorCounts = { frame = 0, native = 0 }
    local _GameInactiveTick
    local _LastGlobalCredits = 0
    local _GlobalCreditsInserted = 0
    local _PendingGlobalCreditDrops = 0
    local _RomIdNum = 0 -- numeric ROM identity for MSOP_ROM_ID (see on_start)

    -- Memory bindings. Each data type's CPU tag and memory space are resolved once per ROM load,
    -- and the bound handles are kept here so that no frame searches MAME's device tree.
    local _MemConfig = {}
    local _MemHandles = {}
    local _HardwareBound = false

    local _PlayerCFG = {}
    local _OutputNames = {}
    -- The output keys every player shares with player 1 under alternating play, or false.
    local _SharedOutputs = false
    local _GlobalOutputs = {}

    -- True when AMMO_DIRECTION is "decrease", the only case in which the derived P*_Clip output is
    -- published. Resolve_Addresses_And_Strings sets it once per ROM load.
    local _ClipEnabled = false

    -- Pulse durations and intervals as attotime values, set once per ROM load in on_start.
    local _RecoilDuration, _RecoilAltDuration, _RecoilGrenadeDuration, _MinRecoilInterval
    local _RecoilHoldInterval, _ReloadDuration, _DamageDuration, _RumbleDuration
    local _StartupTime, _StartupDelay, _ZeroTime
    -- Per-ROM attotime constants, set once in on_start so that Frame_Logic allocates no attotime
    -- objects.
    local _StatusDebounce, _CreditsClearTimeout

    local _Player = {}
    local _GlobalLastOutputs = {}
    local _WarmupFlushed = false

    -- =========================================================================
    -- MSOP RELAY TRANSPORT LAYER
    -- =========================================================================
    -- Sends MSOP output changes, forwarded native outputs and MAME lifecycle events to MESH over a
    -- plain TCP socket, so that hooker programs receive them without a patched MAME. On stock MAME
    -- 0.289 and later this is the only delivery path for MSOP's outputs. msop_out does nothing
    -- while disconnected; Resync_Relay_State resends the tracked values on each connect.
    --
    -- Stages for an output value, in call order:
    --   1. msop_out()               - per-output change filter -> payload_buffer. Called from
    --                                 Set_Output_Safe, Resync_Relay_State and
    --                                 Forward_Native_Outputs.
    --   2. (Frame_Logic and Forward_Native_Outputs run, calling msop_out for each value)
    --   3. flush_payload_to_relay() - one write() of the whole frame's changes
    -- Lifecycle events, outside the buffered path:
    --   mame_start        - held in _ActiveMameStart and written on every connect.
    --   mame_stop, pause  - written at once by broadcast_native_event().
    -- =========================================================================
    local sock = nil
    local connected = false

    -- The running game's mame_start line ("mame_start = <rom>\r\n"), set in on_start and cleared at
    -- mame_stop. connect_socket writes it on every connect, so a listener that attaches after the
    -- ROM started still learns which game is running.
    local _ActiveMameStart = nil

    -- RETRY POLICY --------------------------------------------------------------
    -- A failed dial blocks the emulation thread: emu.file's open is a blocking connect() with no
    -- timeout, and takes about 2 seconds where security software drops loopback SYNs. The number of
    -- attempts is therefore bounded:
    --   COLD (MESH has never answered this session):
    --     dial 1  at ROM start (stall hidden in loading)  - silent
    --     dial 2  RETRY_COLD_SECOND later                 - fail -> "MESH IS NOT
    --             RUNNING" announces one final attempt
    --     dial 3  RETRY_FINAL_GAP after that              - fail -> "MESH NOT FOUND"
    --             and dialling stops
    --   WARM (a live connection dropped):
    --     "MESH DISCONNECTED" at the drop, one reconnect RETRY_FINAL_GAP later
    --     - fail -> "MESH RECONNECT FAILED" and dialling stops
    --
    -- Cold or warm is decided per MAME session (ever_connected), not per ROM. After dialling stops
    -- it resumes only on a re-arm cue:
    --   ROM start / soft reset  - a fresh cold sequence, or the single warm dial once MESH has
    --                             ever connected
    --   unpause                 - exactly one dial
    local RETRY_COLD_SECOND = 10.0 -- silent retry after the ROM-start dial fails, so a
                                   -- MESH launched alongside MAME gets a moment
    local RETRY_FINAL_GAP   = 30.0 -- the announced final attempt, cold and warm alike
    local next_retry_at   = 0      -- monotonic deadline; 0 = free to dial right now
    local ever_connected  = false  -- true once MESH has answered this MAME session; never reset
                                   -- by a ROM change: once true, every later failure
                                   -- takes the WARM path
    local cold_fail_count = 0      -- consecutive failed dials while never connected
    local relay_given_up  = false  -- no further dials until a re-arm cue

    -- CONNECTION STATUS MESSAGES ------------------------------------------------
    -- On-screen and console messages for connection problems, separate from the dbg_osd
    -- diagnostics. The console line always prints. The on-screen message is shown unless
    -- ENABLE_OSD_CONNECTION_STATUS is false in the database's _default block. Each key fires at
    -- most once per session.
    local osd_status_shown = {}
    local function osd_connection_status(key, console_msg, osd_msg)
        if osd_status_shown[key] then return end
        osd_status_shown[key] = true
        print("[MSOP] " .. console_msg)
        local osd_enabled = true
        pcall(function()
            if db and db._default and db._default.ENABLE_OSD_CONNECTION_STATUS == false then
                osd_enabled = false
            end
        end)
        if osd_enabled then
            pcall(function() manager.machine:popmessage(osd_msg) end)
        end
    end

    -- Prints a one-shot console banner stating that MESH must be running, once the relay is
    -- confirmed as the delivery path. It is console only: the on-screen notices belong to the
    -- connection status messages, which fire only on a problem.
    local relay_required_announced = false
    local function announce_relay_required()
        if relay_required_announced then return end
        relay_required_announced = true
        print("[MSOP] ----------------------------------------------------------------")
        print("[MSOP] MESH REQUIRED: MSOP is sending this session's state outputs to the")
        print("[MSOP] MSOP relay on 127.0.0.1:" .. _RelayPort .. ". MESH must be running there to")
        print("[MSOP] receive and forward them (recoil / rumble / lamps / LEDs) to your")
        print("[MSOP] hardware and hooker programs - with nothing listening on that port,")
        print("[MSOP] these outputs are not delivered anywhere.")
        print("[MSOP] ----------------------------------------------------------------")
    end

    -- Returns monotonic wall-clock seconds from emu.osd_ticks, which reads the same on Windows,
    -- Linux and macOS. os.clock() must not be used: it returns wall time on Windows but consumed
    -- CPU time on Linux and macOS. os.time() is the fallback when the binding is missing, at
    -- one-second granularity.
    local _TickRate = 0
    local function monotonic_seconds()
        if _TickRate == 0 then
            local ok, rate = pcall(emu.osd_ticks_per_second)
            _TickRate = (ok and type(rate) == "number" and rate > 0) and rate or -1
        end
        if _TickRate > 0 then
            local ok, ticks = pcall(emu.osd_ticks)
            if ok and type(ticks) == "number" then return ticks / _TickRate end
            _TickRate = -1 -- binding present but unusable; fall through for good
        end
        return os.time()
    end

    -- Arms the next dial for `gap` seconds from now. A successful connect, a ROM start and an
    -- unpause clear the deadline.
    local function arm_relay_retry(gap)
        next_retry_at = monotonic_seconds() + gap
    end

    -- True when the retry policy allows a dial. Every path that opens the socket checks this first.
    -- Once relay_given_up is set, no path dials until a re-arm cue (ROM start, soft reset or
    -- unpause) clears it.
    local function relay_retry_due()
        return (not relay_given_up) and (monotonic_seconds() >= next_retry_at)
    end

    local last_state = {}
    -- Pending "name = value\r\n" lines, joined with table.concat at flush time. Keep it an array:
    -- appending to a string would copy the whole buffer on every line.
    local payload_buffer = {}
    local changes_detected = false

    -- Forward declaration. The function is defined after msop_out, which it calls, and
    -- connect_socket calls it on every successful connect.
    local Resync_Relay_State

    -- Writes data to the relay socket. Returns true only when every byte was written: a short write
    -- is followed by the rest, and a write of no bytes or an error is a failure. Every write site
    -- uses it, so that all of them apply the same failure test.
    local function relay_write(data)
        local sent, len = 0, #data
        while sent < len do
            local ok, written = pcall(sock.write, sock, sent == 0 and data or string.sub(data, sent + 1))
            if not (ok and type(written) == "number" and written > 0) then return false end
            sent = sent + written
        end
        return len > 0
    end

    -- Opens the relay connection. emu.file's "socket.<host>:<port>" URI is MAME's stock Lua TCP
    -- client. A successful connect clears last_state, writes _ActiveMameStart and calls
    -- Resync_Relay_State, because MESH keeps nothing from before a disconnect. A failed connect
    -- follows the retry policy.
    local function connect_socket()
        -- The relay is off when MAME delivers the outputs itself, and no socket is opened.
        if not _UseRelay then return end
        sock = emu.file("w")
        local err = sock:open("socket.127.0.0.1:" .. _RelayPort)

        if not err then
            connected = true
            -- The retry state resets on success. ever_connected stays true for the rest of the
            -- session, so every later drop takes the WARM path.
            next_retry_at = 0
            ever_connected = true
            cold_fail_count = 0
            relay_given_up = false
            print("[MSOP] Connected to the MSOP relay (MESH) on port " .. _RelayPort
                  .. " - state outputs are now being delivered.")
            -- If a connection problem was announced this session, confirm that delivery has
            -- resumed. Otherwise show nothing on screen.
            if osd_status_shown.cold_first or osd_status_shown.cold_final
               or osd_status_shown.warm_first or osd_status_shown.warm_final then
                osd_connection_status("connected",
                    "MESH CONNECTED - state outputs are now being delivered.",
                    "MSOP: MESH CONNECTED\n"
                    .. "State outputs are now being delivered from MAME via MSOP Plugin"
                    .. " to MESH.")
            end
            last_state = {}

            -- Announce the running game to the new listener before the resync, so that the profile
            -- is in place when the values arrive. teardown_connection is not in scope yet, so a
            -- failed write is handled inline: the socket is closed and a retry is armed.
            if _ActiveMameStart then
                if not relay_write(_ActiveMameStart) then
                    if sock then sock:close() end
                    sock = nil
                    connected = false
                    arm_relay_retry(RETRY_FINAL_GAP)
                    return
                end
            end

            -- Before a ROM has warmed up Resync_Relay_State sends the global outputs only, the
            -- identity outputs among them; the warmup flush sends the rest. The resync is skipped
            -- when no game is announced, because a listener could not attribute the values to a
            -- ROM.
            if _ActiveMameStart then Resync_Relay_State() end
        else
            if sock then sock:close() end
            sock = nil
            connected = false

            if not ever_connected then
                -- COLD: the three-dial sequence (see RETRY POLICY). The first failure is silent,
                -- because the ROM-start dial happens while the game is loading and MESH may still
                -- be starting.
                cold_fail_count = cold_fail_count + 1
                if cold_fail_count == 1 then
                    arm_relay_retry(RETRY_COLD_SECOND)
                elseif cold_fail_count == 2 then
                    osd_connection_status("cold_first",
                        "MESH IS NOT RUNNING - nothing is listening on relay port "
                        .. _RelayPort .. ", so MSOP's state outputs for MAME are not being"
                        .. " delivered. One more connection attempt will be made in 30"
                        .. " seconds. Please open MESH before then, or disable the MSOP"
                        .. " Plugin in MAME.",
                        "MSOP: MESH IS NOT RUNNING\n"
                        .. "Nothing is listening on relay port " .. _RelayPort .. ", so"
                        .. " MSOP's state outputs for MAME are not being delivered. One"
                        .. " more connection attempt will be made in 30 seconds. Please"
                        .. " open MESH before then, or disable the MSOP Plugin in MAME.")
                    arm_relay_retry(RETRY_FINAL_GAP)
                else
                    -- The announced final attempt failed. Dialling stops until a re-arm cue
                    -- (unpause, soft reset or the next ROM start).
                    osd_connection_status("cold_final",
                        "MESH NOT FOUND - STATE OUTPUTS PAUSED. Check that MESH is"
                        .. " running in the background whenever the MSOP Plugin is"
                        .. " enabled in MAME and output is set to \"none\" or \"console\""
                        .. " (required on MAME 0.289 and above, since all of MSOP's"
                        .. " outputs must be delivered through MESH). After starting"
                        .. " MESH, pause and unpause the game to reconnect, or restart"
                        .. " MAME.",
                        "MSOP: MESH NOT FOUND - STATE OUTPUTS PAUSED\n"
                        .. "Check that MESH is running in the background whenever the"
                        .. " MSOP Plugin is enabled in MAME and output is set to \"none\""
                        .. " or \"console\" (required on MAME 0.289 and above, since all"
                        .. " of MSOP's outputs must be delivered through MESH). After"
                        .. " starting MESH, pause and unpause the game to reconnect, or"
                        .. " restart MAME.")
                    relay_given_up = true
                end
            else
                -- WARM: ever_connected stays true for the whole MAME session, so every failure
                -- after a successful connect lands here. The single warm dial has failed, so
                -- dialling stops until a re-arm cue. Each cue grants one warm dial, not a new cold
                -- sequence.
                osd_connection_status("warm_final",
                    "MESH RECONNECT FAILED - STATE OUTPUTS PAUSED. Make sure MESH is"
                    .. " running in the background, then pause and unpause the game to"
                    .. " reconnect, or restart MAME.",
                    "MSOP: MESH RECONNECT FAILED - STATE OUTPUTS PAUSED\n"
                    .. "Make sure MESH is running in the background, then pause and"
                    .. " unpause the game to reconnect, or restart MAME.")
                relay_given_up = true
            end
        end
    end

    -- Closes the connection after a failed or zero-byte write. Every write path calls it, and any
    -- write failure is treated as a lost connection. connected must never stay true on a closed
    -- socket: connect_socket is attempted only while connected is false, so a missed teardown would
    -- block every later reconnect.
    local function teardown_connection()
        print("[MSOP] Connection dropped by Relay")
        connected = false
        -- Announce the drop and schedule the single reconnect attempt that the message promises
        -- (see RETRY POLICY).
        osd_connection_status("warm_first",
            "MESH DISCONNECTED - the connection to MESH was lost; state outputs are"
            .. " paused. The MSOP Plugin will try to reconnect to MESH in 30 seconds."
            .. " Please check MESH is running before then.",
            "MSOP: MESH DISCONNECTED\n"
            .. "The connection to MESH was lost - state outputs are paused. The MSOP"
            .. " Plugin will try to reconnect to MESH in 30 seconds. Please check MESH"
            .. " is running before then.")
        arm_relay_retry(RETRY_FINAL_GAP)
        if sock then sock:close() end
        sock = nil
        -- Discard the unsent changes. After a reconnect, Resync_Relay_State sends every tracked
        -- output at its current value.
        payload_buffer = {}
        changes_detected = false
    end

    -- Writes a lifecycle event (mame_stop or pause) to the relay at once, bypassing payload_buffer,
    -- because the next flush may never run. It opens the connection first if the retry policy
    -- allows. mame_start is not sent here: it is held in _ActiveMameStart and written on every
    -- connect (see connect_socket). A failed write tears the connection down.
    local function broadcast_native_event(event_string)
        if not _UseRelay then return end -- native-delivery install: MAME emits lifecycle itself
        -- The open goes through the retry gate: pause and unpause can fire at will, and each failed
        -- dial stalls the emulation thread.
        if not connected and relay_retry_due() then
            connect_socket()
        end

        if connected and sock then
            if not relay_write(event_string) then teardown_connection() end
        end
    end

    -- Converts a value to the integer an output carries. MAME stores s32 and the relay wire format
    -- is "%d", which raises an error for a number with no integer form. Every value is limited
    -- to the s32 range. A float (the float32 and float32be widths) is rounded, and a NaN becomes
    -- 0.
    local function To_Output_Int(value)
        if math.type(value) == "integer" then
            if value > 2147483647 then return 2147483647 end
            if value < -2147483648 then return -2147483648 end
            return value
        end
        if value ~= value then return 0 end
        if value >= 2147483647 then return 2147483647 end
        if value <= -2147483648 then return -2147483648 end
        return math.floor(value + 0.5)
    end

    -- Queues one output value for the relay. Called from Set_Output_Safe, Resync_Relay_State and
    -- Forward_Native_Outputs. Only a value that differs from last_state is appended to
    -- payload_buffer, which makes this the relay's single change filter. It does nothing while
    -- disconnected, so payload_buffer cannot grow while the relay is down.
    local function msop_out(out_name, val)
        if not _UseRelay or not connected then return end
        if val ~= last_state[out_name] then
            payload_buffer[#payload_buffer + 1] = string.format("%s = %d\r\n", out_name, val)
            last_state[out_name] = val
            changes_detected = true
        end
    end

    -- -------------------------------------------------------------------------
    -- Resync_Relay_State()
    -- Sends every MSOP output that has been written, at its current value, through msop_out.
    -- connect_socket calls it after clearing last_state, because Set_Output and Set_Global_Output
    -- reach msop_out only when a value differs from their own caches, which a reconnect does not
    -- clear. Before a ROM has completed warmup it sends the global outputs only, which on_start
    -- has cleared and Send_Identity_Outputs has written for the running game; the player caches
    -- may still describe the previous game until then.
    -- -------------------------------------------------------------------------
    Resync_Relay_State = function()
        if not CFG then return end

        -- An output with no cached value has never been written, and is skipped.
        for key, name in pairs(_GlobalOutputs) do
            local value = _GlobalLastOutputs[key]
            if value ~= nil then msop_out(name, To_Output_Int(value)) end
        end

        if not _WarmupFlushed then return end

        for i = 1, CFG.MAX_PLAYERS do
            local p = _Player[i]
            local names = _OutputNames[i]
            if p and names then
                for key, name in pairs(names) do
                    local value = p.LastOutputs[key]
                    if value ~= nil then msop_out(name, To_Output_Int(value)) end
                end
            end
        end
    end

    -- Sends one frame's accumulated changes in one relay_write, at the end of Compute_Outputs.
    -- While disconnected it only dials, when the retry policy allows. A failed or zero-byte write
    -- tears the connection down.
    local function flush_payload_to_relay()
        if not _UseRelay then return end -- native-delivery install: nothing to flush over TCP
        if not connected then
            if relay_retry_due() then connect_socket() end
            return
        end

        if changes_detected then
            -- One join and one relay_write. The buffer is emptied in place and reused, so that a
            -- flushing frame allocates no new table. A failed write discards it in
            -- teardown_connection.
            if relay_write(table.concat(payload_buffer)) then
                for i = #payload_buffer, 1, -1 do payload_buffer[i] = nil end
            else
                teardown_connection()
            end
            changes_detected = false
        end
    end

    -- -------------------------------------------------------------------------
    -- LOGGING HELPERS
    -- -------------------------------------------------------------------------
    local function dbg_print(msg)
        -- Always prints to the console.
        print("[MSOP] " .. tostring(msg))
    end

    local function dbg_osd(msg, profile_osd)
        -- Shown on screen only when ENABLE_OSD is set in this file or in the profile. on_start
        -- passes the profile's switch as profile_osd, because CFG is not set when it reports.
        local use_osd = ENABLE_OSD or profile_osd
        if use_osd and manager and manager.machine then
            manager.machine:popmessage("[MSOP] " .. tostring(msg))
        end
    end

    -- -------------------------------------------------------------------------
    -- read_plugin_manifest()
    -- Returns the text of the plugin's plugin.json, or nil when it cannot be found. MESH writes the
    -- optional "relayport" and "relay" members into that file. Every pluginspath entry is searched;
    -- entries are separated by ';' and may be relative, as MAME resolves them.
    -- -------------------------------------------------------------------------
    local function read_plugin_manifest()
        local ok_pp, plugin_paths = pcall(function()
            return manager.machine.options.entries["pluginspath"]:value()
        end)
        if not ok_pp or type(plugin_paths) ~= "string" then return nil end
        for raw_dir in plugin_paths:gmatch("[^;]+") do
            local dir = raw_dir
            local ok_sub, expanded = pcall(function() return emu.subst_env(raw_dir) end)
            if ok_sub and type(expanded) == "string" and #expanded > 0 then dir = expanded end
            local f = io.open(dir .. "/stateoutput/plugin.json", "r")
            if f then
                local text = f:read("*a") or ""
                f:close()
                return text -- the first manifest found is the one used
            end
        end
        return nil
    end

    -- Sets _UseRelay from MAME itself, once, from on_start and before any relay use. It reads
    -- emu.app_version() and the resolved -output option (core_options.entries[name]:value()). Where
    -- neither gives an answer it uses the plugin.json "relay" stamp, then the default.
    -- Probe_Legacy_Set_Value can later change false to true, never the reverse.
    --   * output creation probe failed -> MAME cannot hold MSOP's outputs -> relay required.
    --   * emu.app_version() >= 0.289  -> Lua cannot create outputs at all -> relay required.
    --   * -output none / console      -> outputs are created but MAME never broadcasts them ->
    --                                    relay required. "auto" is treated as "none".
    --   * -output network / windows   -> MAME delivers the outputs itself -> relay off (no socket
    --                                    is opened at all).
    local function resolve_relay_mode()
        if _RelayModeResolved then return end
        _RelayModeResolved = true

        -- The port is settled first. It does not depend on the mode decision below. A "relayport"
        -- member in plugin.json sets it; an absent or invalid value leaves the default (8004).
        local ok_manifest, manifest = pcall(read_plugin_manifest)
        if not ok_manifest then manifest = nil end
        if manifest then
            local port = tonumber(manifest:match('"relayport"%s*:%s*(%d+)'))
            if port and port > 0 and port < 65536 then
                _RelayPort = port
                dbg_print("Relay port: " .. port .. " (plugin.json relayport stamp)")
            end
        end

        -- Read the resolved -output mode. The network flag below and the capability and version
        -- gates use it.
        local out_mode
        do
            local ok_out, m = pcall(function()
                return manager.machine.options.entries["output"]:value()
            end)
            if ok_out and type(m) == "string" then out_mode = m:lower() end
        end

        -- Record whether MAME's own network output server is running this session (it binds port
        -- 8000). Native output forwarding stands down when it is, because forwarding would deliver
        -- each output twice to a program reading both ports.
        _MameServesNetwork = (out_mode == "network")

        -- The relay port is never derived from the -output mode. The gates below decide only
        -- whether the relay is used.

        -- Capability gate, which outranks the two gates below. If the probe found that
        -- output.set_value() cannot create an output, MAME cannot broadcast MSOP's outputs in any
        -- -output mode and the relay is required. Testing the capability also covers a build that
        -- reports 0.288 but behaves as 0.289. This gate only turns the relay on.
        if _LegacyCreateProbed and not _LegacyCreateWorks then
            _UseRelay = true
            _MisconfiguredOutputMode = (out_mode == "network")
            _WindowsOutputWithRelay = (out_mode == "windows")
            dbg_print("Relay mode: ENABLED (this build cannot create custom outputs - "
                      .. "MAME has nothing of ours to broadcast in any -output mode)")
            return
        end

        -- Version gate: MAME 0.289 and later requires the relay in every -output mode.
        local ok_ver, ver = pcall(function() return emu.app_version() end)
        if ok_ver and type(ver) == "string" then
            local maj, min = ver:match("(%d+)%.(%d+)")
            if maj then
                if tonumber(maj) > 0 or tonumber(min) >= 289 then
                    _UseRelay = true
                    _MisconfiguredOutputMode = (out_mode == "network")
                    _WindowsOutputWithRelay = (out_mode == "windows")
                    dbg_print("Relay mode: ENABLED (MAME " .. ver .. " >= 0.289 - no native output creation)")
                    return
                end
            end
        end

        -- Output mode gate for MAME 0.288 and earlier. MAME resolves "-output auto" (the default)
        -- to the "none" module, so it is treated as "none" and delivered through the relay.
        local mode = (out_mode == "auto") and "none" or out_mode
        if mode == "none" or mode == "console" then
            _UseRelay = true
            dbg_print("Relay mode: ENABLED (-output " .. mode .. " - created but not broadcast)")
            return
        elseif mode == "network" or mode == "windows" then
            _UseRelay = false
            dbg_print("Relay mode: disabled (-output " .. mode .. " - MAME self-delivers)")
            return
        end

        -- Undetermined: the option is not exposed on this build, or its value is none of the modes
        -- above. Fall back to the "relay" member (true or false) that MESH stamps into plugin.json.
        -- A missing file or member keeps the default (false).
        local flag = manifest and manifest:match('"relay"%s*:%s*(%a+)')
        if flag == "true" then
            _UseRelay = true
            dbg_print("Relay mode: ENABLED (plugin.json relay stamp - runtime auto-detect unavailable)")
            return
        elseif flag == "false" then
            _UseRelay = false
            dbg_print("Relay mode: disabled (plugin.json relay stamp - runtime auto-detect unavailable)")
            return
        end
        dbg_print("Relay mode: " .. (_UseRelay and "ENABLED" or "disabled") ..
                  " (default - runtime auto-detect unavailable and no plugin.json relay stamp)")
    end

    -- -------------------------------------------------------------------------
    -- fnv1a_31(s)
    -- Returns the 31-bit FNV-1a hash of a string. It gives the MSOP_ROM_ID output a stable,
    -- positive s32 ROM ID when the profile has no LUA_ROM_ID. The hash depends only on the ROM's
    -- short name, so it does not change between plugin or database releases.
    -- -------------------------------------------------------------------------
    local function fnv1a_31(s)
        local h = 2166136261
        for idx = 1, #s do
            h = h ~ string.byte(s, idx)
            h = (h * 16777619) & 0xFFFFFFFF
        end
        return h & 0x7FFFFFFF
    end

    -- -------------------------------------------------------------------------
    -- deep_merge(default_cfg, game_cfg)
    -- Returns a copy of the '_default' template with a ROM's values layered over it, so that CFG
    -- carries every default key even when the ROM's profile is sparse.
    -- -------------------------------------------------------------------------
    local function deep_merge(default_cfg, game_cfg)
        local result = {}
        for k, v in pairs(default_cfg) do
            if type(v) == "table" then result[k] = deep_merge(v, {}) else result[k] = v end
        end
        for k, v in pairs(game_cfg) do
            if type(v) == "table" and type(result[k]) == "table" then result[k] = deep_merge(result[k], v)
            else result[k] = v end
        end
        return result
    end

    -- -------------------------------------------------------------------------
    -- normalize_variables(config)
    -- Limits MAX_PLAYERS, rounds the time settings, and moves the legacy LAMP_START setting name to
    -- LAMPSTART, the name the engine reads, in each player block and each per-setting table. The
    -- legacy key is removed: two keys with one output suffix would compile to the same output
    -- name, and a resync would send both.
    -- -------------------------------------------------------------------------
    local function normalize_variables(config)
        -- The engine holds state for four players. MAX_PLAYERS is limited to 1 to 4 here, so that
        -- a profile value outside that range cannot index a player that does not exist.
        local max_players = math.floor(tonumber(config.MAX_PLAYERS) or 1)
        if max_players < 1 then max_players = 1 elseif max_players > 4 then max_players = 4 end
        config.MAX_PLAYERS = max_players
        local function move_legacy_key(t)
            if type(t) ~= "table" or t.LAMP_START == nil then return end
            if t.LAMPSTART == nil then t.LAMPSTART = t.LAMP_START end
            t.LAMP_START = nil
        end
        for i = 1, config.MAX_PLAYERS do
            move_legacy_key(config["P"..i])
        end
        move_legacy_key(config.DATA_WIDTHS)
        move_legacy_key(config.OUTPUT_SUFFIXES)
        move_legacy_key(config.CPU_TAGS)
        move_legacy_key(config.MEMORY_SPACES)

        -- MAME's attotime constructors take whole numbers, so a time setting with a fraction is
        -- rounded.
        for key, value in pairs(config) do
            if math.type(value) == "float" and (string.match(key, "_MS$") or string.match(key, "_SEC$")) then
                config[key] = math.floor(value + 0.5)
            end
        end
        return config
    end

    -- -------------------------------------------------------------------------
    -- convert_hex_strings_to_numbers(t)
    -- Recursively converts JSON hex strings ("0x00FF") to numbers. JSON cannot store hexadecimal
    -- numbers, and MAME's memory reads take numbers.
    -- -------------------------------------------------------------------------
    local function convert_hex_strings_to_numbers(t)
        for k, v in pairs(t) do
            if type(v) == "table" then convert_hex_strings_to_numbers(v)
            elseif type(v) == "string" and string.match(v, "^0x%x+$") then
                local num = tonumber(v)
                if num then t[k] = num end
            end
        end
    end

    -- -------------------------------------------------------------------------
    -- Resolve_Addresses_And_Strings()
    -- Runs once per ROM load. Lowercases the settings that are compared as strings, builds the
    -- memory binding table and the output names, and derives the P2 to P4 values marked "auto" from
    -- the P1 value and the player memory offset.
    -- -------------------------------------------------------------------------
    local function Resolve_Addresses_And_Strings()
        -- Lowercase the settings that are compared as strings.
        CFG.AMMO_DIRECTION             = string.lower(tostring(CFG.AMMO_DIRECTION or ""))
        CFG.AMMO_ALT_DIRECTION         = string.lower(tostring(CFG.AMMO_ALT_DIRECTION or ""))
        CFG.AMMO_GRENADE_DIRECTION     = string.lower(tostring(CFG.AMMO_GRENADE_DIRECTION or ""))

        -- P*_Clip is a derived flag: 1 while ammo is above 0, 0 when it reaches 0 (a reload is
        -- needed). It is published only when AMMO_DIRECTION is "decrease", the only reading in
        -- which 0 means empty:
        --   * "decrease" -> a clip counting down to 0. Published.
        --   * increase   -> the address is a shots-fired counter, so 0 means a full clip and the
        --                   flag would be inverted. Never published.
        --   * "change"   -> the direction is unknown, so it carries the same inversion risk.
        --                   Never published.
        _ClipEnabled = (CFG.AMMO_DIRECTION == "decrease")
        CFG.LIFE_DIRECTION             = string.lower(tostring(CFG.LIFE_DIRECTION or ""))
        CFG.LIFE_ALT_DIRECTION         = string.lower(tostring(CFG.LIFE_ALT_DIRECTION or ""))
        CFG.SHOTS_FIRED_METHOD         = string.lower(tostring(CFG.SHOTS_FIRED_METHOD or "trigger"))
        CFG.SHOTS_FIRED_ALT_METHOD     = string.lower(tostring(CFG.SHOTS_FIRED_ALT_METHOD or "trigger"))
        CFG.SHOTS_FIRED_GRENADE_METHOD = string.lower(tostring(CFG.SHOTS_FIRED_GRENADE_METHOD or "trigger"))
        CFG.FORCE_FEEDBACK_ENABLER     = string.lower(tostring(CFG.FORCE_FEEDBACK_ENABLER or "both"))
        CFG.RECOIL_METHOD              = string.lower(tostring(CFG.RECOIL_METHOD or "pulse"))
        CFG.RECOIL_PRIORITY            = string.lower(tostring(CFG.RECOIL_PRIORITY or "ammo"))

        -- GAME_TYPE selects the pipelines and output names a profile uses. An unknown value is
        -- treated as "lightgun".
        --   "lightgun" (default) - runs the per-player gun pipeline and compiles the gun output
        --                          names.
        --   "racing"             - skips the gun pipeline and compiles only the FFB_* output names.
        --   "both"               - does both, for a hybrid such as a racing game with life and
        --                          damage tracking.
        CFG.GAME_TYPE = string.lower(tostring(CFG.GAME_TYPE or "lightgun"))
        if CFG.GAME_TYPE ~= "racing" and CFG.GAME_TYPE ~= "both" then CFG.GAME_TYPE = "lightgun" end

        if CFG.DATA_WIDTHS then
            for k, v in pairs(CFG.DATA_WIDTHS) do
                if type(v) == "string" then CFG.DATA_WIDTHS[k] = string.lower(v) end
            end
        end

        local data_types = {
            "SCREEN_FLASH", "GLOBAL_ATTRACT_STATUS", "GLOBAL_CREDITS", "GLOBAL_GAME_STATUS",
            "CREDITS", "STATUS", "STATUS_ALT", "AMMO", "AMMO_ALT", "AMMO_GRENADE", "LIFE", "LIFE_ALT",
            "RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMPSTART",
            "SHOTS_FIRED_PRIMARY", "SHOTS_FIRED_ALT", "SHOTS_FIRED_GRENADE", "LIFE_LOST", "DAMAGE_TAKEN",
            "FFB" -- FFB memory sources bind through CPU_TAGS.FFB / MEMORY_SPACES.FFB
        }

        local function Resolve_Mem_Path(val, global_val)
            if val == nil or val == false or val == "" or string.lower(tostring(val)) == "auto" then return global_val end
            return tostring(val)
        end

        -- -------------------------------------------------------------------------
        -- MAP CPU TAGS AND MEMORY SPACES
        -- Each data type binds to a CPU tag and a memory space. The defaults are CFG.CPU_TAG
        -- (":maincpu") and CFG.MEMORY_SPACE ("program"); CPU_TAGS and MEMORY_SPACES override them
        -- per data type.
        -- Memory space values:
        --   an address space name - the CPU's logical address space ("program" by default).
        --   "region"              - the MAME memory region named by the tag
        --                           (manager.machine.memory.regions), bypassing the CPU's address
        --                           map. Use it only to write to ROM, such as a screen flash
        --                           patch: MAME blocks writes to ROM through a CPU address space.
        -- -------------------------------------------------------------------------
        for _, key in ipairs(data_types) do
            local t = Resolve_Mem_Path(CFG.CPU_TAGS and CFG.CPU_TAGS[key], CFG.CPU_TAG or ":maincpu")
            local s = Resolve_Mem_Path(CFG.MEMORY_SPACES and CFG.MEMORY_SPACES[key], CFG.MEMORY_SPACE or "program")
            _MemConfig[key] = { tag = t, space = s }
        end

        -- P*_Clip is derived, so a database may carry no OUTPUT_SUFFIXES entry for it. A default is
        -- added here, after the merge and before the names are compiled. A profile's own CLIP
        -- suffix is kept.
        CFG.OUTPUT_SUFFIXES = CFG.OUTPUT_SUFFIXES or {}
        if CFG.OUTPUT_SUFFIXES.CLIP == nil then CFG.OUTPUT_SUFFIXES.CLIP = "Clip" end
        -- A database compiled before MSOP_Database_Date existed has no entry for it either.
        if CFG.OUTPUT_SUFFIXES.GLOBAL_DATABASE_DATE == nil then
            CFG.OUTPUT_SUFFIXES.GLOBAL_DATABASE_DATE = "Database_Date"
        end

        -- Compiles only the output names the GAME_TYPE can drive: "racing" keeps FFB_* only,
        -- "lightgun" keeps everything except FFB_*, and "both" keeps all. Global outputs are not
        -- filtered. Set_Output skips a key that has no compiled name.
        local function Type_Allows(key)
            local is_ffb = string.match(key, "^FFB_") ~= nil
            if CFG.GAME_TYPE == "racing" then return is_ffb end
            if CFG.GAME_TYPE == "lightgun" then return not is_ffb end
            return true -- "both"
        end

        -- Compile the per-player output names (for example "MSOP_P1_Ammo").
        for i = 1, CFG.MAX_PLAYERS do
            _OutputNames[i] = {}
            for key, suffix in pairs(CFG.OUTPUT_SUFFIXES) do
                if not string.match(key, "^GLOBAL_") and Type_Allows(key) then
                    local target_p = i
                    if not CFG.SIMULTANEOUS_PLAY and (key == "RECOIL" or key == "RELOAD" or key == "DAMAGE" or key == "RUMBLE" or key == "LAMPSTART") then target_p = 1 end

                    -- Per-player outputs carry the MSOP_ prefix.
                    _OutputNames[i][key] = "MSOP_P" .. target_p .. "_" .. tostring(suffix)
                end
            end
            local target_p_ctm = (not CFG.SIMULTANEOUS_PLAY) and 1 or i

            -- The DemulShooter aliases have no MSOP_ prefix, so that DemulShooter reads them under
            -- the names it expects (P<n>_CtmRecoil, P<n>_Damaged and P<n>_CtmLmpStart). They are
            -- not compiled for "racing" profiles.
            if CFG.GAME_TYPE ~= "racing" then
                _OutputNames[i]["CtmRecoil"]   = "P" .. target_p_ctm .. "_CtmRecoil"
                _OutputNames[i]["Damaged"]     = "P" .. target_p_ctm .. "_Damaged"
                _OutputNames[i]["CtmLmpStart"] = "P" .. target_p_ctm .. "_CtmLmpStart"
            end
        end

        -- With alternating play every player's pulse and start lamp outputs go out under player
        -- 1's names, so they share player 1's cache as well (see Set_Output). Player 1 alone
        -- drives the start lamp.
        _SharedOutputs = (not CFG.SIMULTANEOUS_PLAY) and
            { RECOIL = true, RELOAD = true, DAMAGE = true, RUMBLE = true, CtmRecoil = true, Damaged = true,
              LAMPSTART = true, CtmLmpStart = true } or false

        for key, suffix in pairs(CFG.OUTPUT_SUFFIXES) do
            -- Global outputs carry the MSOP_ prefix.
            if string.match(key, "^GLOBAL_") then _GlobalOutputs[key] = "MSOP_" .. tostring(suffix) end
        end

        -- Normalise every spelling of "auto" to lowercase.
        local all_players = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }
        for _, p_cfg in ipairs(all_players) do
            for k, val in pairs(p_cfg) do
                if type(val) == "string" and string.lower(val) == "auto" then p_cfg[k] = "auto" end
            end
        end

        -- A P1 ammo or life setting has no source to derive from, so "auto" there is unset. This
        -- runs first, because the hardware settings below depend on it.
        for _, key in ipairs({ "AMMO", "AMMO_ALT", "AMMO_GRENADE", "LIFE", "LIFE_ALT" }) do
            if CFG.P1[key] == "auto" then CFG.P1[key] = false end
        end
        -- A P1 hardware setting left as "auto" is set to false when no ammo or life address exists
        -- to derive it from. RUMBLE and LAMPSTART have no derived source and are always set to
        -- false.
        local p1_hardware = { "RECOIL", "RELOAD", "DAMAGE", "RUMBLE", "LAMPSTART", "STATUS", "STATUS_ALT" }
        for _, key in ipairs(p1_hardware) do
            if CFG.P1[key] == "auto" then
                if key == "STATUS" or key == "STATUS_ALT" then -- leave as auto
                elseif key == "RECOIL" and (CFG.P1.AMMO or CFG.P1.AMMO_ALT or CFG.P1.AMMO_GRENADE) then
                elseif key == "RELOAD" and (CFG.P1.AMMO or CFG.P1.AMMO_ALT or CFG.P1.AMMO_GRENADE) then
                elseif key == "DAMAGE" and (CFG.P1.LIFE or CFG.P1.LIFE_ALT) then
                else CFG.P1[key] = false end
            end
        end

        -- Derive each P2 to P4 value marked "auto" from the P1 value plus the offset multiplied by
        -- the player's position after P1.
        local standard_offset = tonumber(CFG.PLAYER_MEMORY_OFFSET) or 0
        local credit_offset = tonumber(CFG.PLAYER_CREDIT_MEMORY_OFFSET) or standard_offset
        local player_tables = { CFG.P2, CFG.P3, CFG.P4 }

        for i, p_cfg in ipairs(player_tables) do
            local multiplier = i
            for key, val in pairs(p_cfg) do
                if val == "auto" then
                    local p1_val = CFG.P1[key]
                    local offset_to_use = (key == "CREDITS") and credit_offset or standard_offset
                    if type(p1_val) == "number" then
                        p_cfg[key] = p1_val + (offset_to_use * multiplier)
                    elseif type(p1_val) == "string" and string.match(p1_val, "^0x") then
                        local p1_num = tonumber(p1_val)
                        if p1_num then p_cfg[key] = string.format("0x%08X", p1_num + (offset_to_use * multiplier)) end
                    elseif p1_val == "auto" then p_cfg[key] = "auto"
                    else p_cfg[key] = false end
                end
            end
        end
        _PlayerCFG = { CFG.P1, CFG.P2, CFG.P3, CFG.P4 }

        -- True when any player has a credit address of its own. Their total then stands for the
        -- global credits, and the global credit address is not tracked. A "racing" profile does not
        -- run the per-player pipeline, so it is always false there.
        CFG.PLAYER_CREDITS_TRACKED = false
        if CFG.GAME_TYPE ~= "racing" then
            for i = 1, CFG.MAX_PLAYERS do
                if type(_PlayerCFG[i].CREDITS) == "number" then CFG.PLAYER_CREDITS_TRACKED = true end
            end
        end
    end

    -- -------------------------------------------------------------------------
    -- Value_Is_Active(val, active_spec)
    -- Tests a polled memory value against a configured "active" specification. It is a named
    -- function so that the frame loop allocates no closure.
    -- active_spec:
    --   table       - active when val equals any entry.
    --   number      - active when val equals it.
    --   nil / false - active when val is above 0.
    -- -------------------------------------------------------------------------
    local function Value_Is_Active(val, active_spec)
        if type(active_spec) == "table" then
            for _, v in ipairs(active_spec) do
                if val == v then return true end
            end
            return false
        elseif type(active_spec) == "number" then
            return val == active_spec
        else
            -- nil or false means any positive value is active. Any other type, such as an
            -- unresolved "auto" string, is never active.
            return (not active_spec) and (val > 0)
        end
    end

    -- -------------------------------------------------------------------------
    -- Shot_Delta(direction, curr, last, threshold)
    -- Returns the number of rounds an ammo change stands for, or 0 when the change is not a shot.
    -- direction:
    --   "decrease" - a fall counts, when the previous value was at or below the threshold.
    --   "change"   - any change counts, by its size.
    --   other      - a rise counts ("increase").
    -- -------------------------------------------------------------------------
    local function Shot_Delta(direction, curr, last, threshold)
        if direction == "decrease" then
            return (curr < last and last <= threshold) and (last - curr) or 0
        elseif direction == "change" then
            return math.abs(curr - last)
        end
        return (curr > last) and (curr - last) or 0
    end

    -- -------------------------------------------------------------------------
    -- OUTPUT PROXY CACHE & SAFE SETTER
    -- Writes an output through its cached proxy where one exists, and through the deprecated
    -- set_value on a build that can still create outputs (MAME 0.288 and earlier).
    -- -------------------------------------------------------------------------
    local _ProxyCache = {}

    -- A named function for the pcalls in Get_Output_Proxy and _FFB.Probe_Output. The miss path can
    -- retry every frame, and a closure per attempt would allocate on every frame.
    local function Resolve_Root_Output(dev, name)
        return dev:output(name)
    end

    -- Tests once per session whether the deprecated output.set_value() can create an output or only
    -- resolves existing ones. The probe writes the plugin version to MSOP_Plugin_Version, the value
    -- that output carries anyway, and reads it back through get_value. Zero cannot be used: it is
    -- get_value's default. device:output() does not reliably show a set_value write.
    local function Probe_Legacy_Set_Value(out_handle)
        if _LegacyCreateProbed then return end
        if not out_handle or not out_handle.set_value or not out_handle.get_value then return end

        _LegacyCreateProbed = true
        local PROBE_NAME = "MSOP_Plugin_Version"
        local PROBE_VALUE = PLUGIN_VERSION_NUM

        -- The test write makes MAME 0.289 and later print its own error on the next console line.
        -- The message below says so in advance.
        dbg_print("COMPATIBILITY TEST: probing whether this MAME build can create state outputs "
                  .. "(via the deprecated output.set_value). If a MAME error/warning appears on "
                  .. "the NEXT line, that is EXPECTED on MAME 0.289+ (output creation was removed) "
                  .. "- it is harmless and MSOP falls back to the relay automatically.")

        pcall(function() out_handle:set_value(PROBE_NAME, PROBE_VALUE) end)
        local ok, got = pcall(function() return out_handle:get_value(PROBE_NAME) end)
        _LegacyCreateWorks = ok and got == PROBE_VALUE

        if _LegacyCreateWorks then
            dbg_print("COMPATIBILITY TEST passed: this MAME build CAN create state outputs "
                      .. "(MAME 0.288 or earlier behaviour) - no error above was expected.")
        else
            dbg_print("COMPATIBILITY TEST result: this MAME build CANNOT create state outputs (expected on MAME 0.289+ - any output error above was the test, not a fault). No further attempts will be made this session; the relay is delivering everything.")
            -- set_value is the only route by which MAME could hold an MSOP output. With creation
            -- confirmed impossible, the relay is the only delivery path, so it is forced on even
            -- when it was left off. This is reached only after a failed probe, so it cannot turn
            -- the relay on for a build that delivers the outputs itself.
            if not _UseRelay then
                _UseRelay = true
                dbg_print("Relay auto-enabled (native output creation is impossible on this build).")
                -- _ActiveMameStart already holds the running game, and connect_socket sends it on
                -- the next connect, which the frame flush triggers.
            end
        end
    end

    -- Calls the deprecated set_value only while it can create outputs. The probe runs on the first
    -- call, so nothing more is written on a build where creation is impossible.
    local function Try_Legacy_Set_Value(out_handle, name, value)
        if not out_handle or not out_handle.set_value then return end
        Probe_Legacy_Set_Value(out_handle) -- no-op after the first call
        if not _LegacyCreateWorks then return end

        out_handle:set_value(name, value)
    end

    local function Get_Output_Proxy(name, out_handle)
        if _ProxyCache[name] ~= nil then return _ProxyCache[name] end

        local proxy = false

        if manager and manager.machine and manager.machine.devices then
            local root_dev = manager.machine.devices[":"]
            if root_dev and root_dev.output then
                local s2, p = pcall(Resolve_Root_Output, root_dev, name)

                -- Accept the proxy only if the output exists.
                if s2 and p and p:exists() then
                    proxy = p
                else
                    proxy = false
                end
            end
        end

        if not proxy then
            Try_Legacy_Set_Value(out_handle, name, 0)
            -- In pass-through mode a missing output may appear once its device has started, so the
            -- miss is not cached.
            if _RetryMissingProxies then return false end
        end

        _ProxyCache[name] = proxy
        return proxy
    end

    local function Set_Output_Safe(out_handle, name, value)
        -- The value is converted once here, for both the relay and the native write.
        value = To_Output_Int(value)

        -- Queue the value for the relay, the only delivery path on stock MAME 0.289 and later.
        msop_out(name, value)

        -- Also write MAME's own output table where the output exists or can still be created (see
        -- Try_Legacy_Set_Value), for clients that read MAME's output system.
        local proxy = Get_Output_Proxy(name, out_handle)
        if proxy then
            proxy:set(value)
        else
            Try_Legacy_Set_Value(out_handle, name, value)
        end
    end

    -- -------------------------------------------------------------------------
    -- Read_Data_Safe(mem_handle, source, width)
    -- Reads one value from memory or from an existing output. Returns 0 when the source or the
    -- handle is missing.
    -- width:
    --    8, 16, 32, 64 -> reads an unsigned integer of that width (any other number reads 8 bits)
    --    "float32"     -> reads a 32-bit little-endian float (modern 3D games)
    --    "float32be"   -> reads a 32-bit big-endian float (Sega Model 2/3)
    --    "output"      -> reads an existing MAME output by name instead of RAM
    -- -------------------------------------------------------------------------
    local function Read_Data_Safe(mem_handle, source, width)
        if not source then return 0 end

        if type(width) == "string" then
            if width == "output" then
                -- Look the output up through the proxy cache.
                local proxy = Get_Output_Proxy(source, nil)

                if proxy then
                    -- MAME 0.289 and later: read through the proxy.
                    return proxy:get()
                elseif _LegacyCreateWorks and manager.machine.output and manager.machine.output.get_value then
                    -- MAME 0.288 and earlier: look the value up by name. Later builds are excluded,
                    -- because get_value is deprecated there and logs a warning on every call.
                    local native_val = manager.machine.output:get_value(source)
                    return type(native_val) == "number" and native_val or (native_val and 1 or 0)
                end
                return 0

            elseif width == "float32" and mem_handle then
                local val = mem_handle:read_u32(source)
                return string.unpack("f", string.pack("I4", val))

            elseif width == "float32be" and mem_handle then
                local val = mem_handle:read_u32(source)
                val = ((val & 0xFF) << 24) | ((val & 0xFF00) << 8) | ((val & 0xFF0000) >> 8) | ((val & 0xFF000000) >> 24)
                return string.unpack("f", string.pack("I4", val))
            end
            return 0
        end

        if not mem_handle then return 0 end
        if width == 16 then return mem_handle:read_u16(source) end
        if width == 32 then return mem_handle:read_u32(source) end
        if width == 64 then return mem_handle:read_u64(source) end
        return mem_handle:read_u8(source)
    end

    -- Reads an ammo or life value: the memory value plus the setting's offset, or 0 when it is
    -- above the setting's maximum. key is the setting name ("AMMO", "LIFE_ALT" and so on).
    -- Frame_Logic and Seed_Frame_Baselines both read through it, so their values always agree.
    local function Read_Counter(key, source, offset, max)
        local value = Read_Data_Safe(_MemHandles[key], source, CFG.DATA_WIDTHS[key]) + (offset or 0)
        if max and value > max then value = 0 end
        return value
    end

    -- -------------------------------------------------------------------------
    -- Write_Data_Safe(mem_handle, source, width, value)
    -- Writes one value to memory at the given width. It is used to hold an address at a fixed
    -- value, for example to disable a screen flash. A string width (an output or a float) is not
    -- written.
    -- -------------------------------------------------------------------------
    local function Write_Data_Safe(mem_handle, source, width, value)
        if not source or not mem_handle or not value then return end
        if type(width) == "string" then return end -- outputs and floats are not patched
        if width == 16 then mem_handle:write_u16(source, value)
        elseif width == 32 then mem_handle:write_u32(source, value)
        elseif width == 64 then mem_handle:write_u64(source, value)
        else mem_handle:write_u8(source, value) end
    end

    -- -------------------------------------------------------------------------
    -- Send_Identity_Outputs(out_handle)
    -- Writes the identity outputs with their values: the plugin version and date, the date of the
    -- loaded database and the ROM ID. on_start calls it as soon as the profile is resolved, ahead
    -- of the startup delay, so that a listener learns from the first lines of a session that this
    -- ROM's MSOP profile is running. Register_Outputs_Safe calls it again at warmup. The plugin
    -- version and date are never 0. The database date is 0 when the database has no LUA_DATE.
    -- -------------------------------------------------------------------------
    local function Send_Identity_Outputs(out_handle)
        if not out_handle or not CFG then return end

        local function Sync_Global(key, value)
            if _GlobalOutputs[key] then
                Set_Output_Safe(out_handle, _GlobalOutputs[key], value)
                _GlobalLastOutputs[key] = value
            end
        end

        -- The plugin identity comes from this file's constants. CFG.LUA_DATE is the date of the
        -- database release; CFG.LUA_VERSION is not sent.
        Sync_Global("GLOBAL_LUA_VERSION", PLUGIN_VERSION_NUM)
        Sync_Global("GLOBAL_LUA_DATE", PLUGIN_DATE_NUM)
        Sync_Global("GLOBAL_DATABASE_DATE", tonumber(CFG.LUA_DATE) or 0)
        Sync_Global("GLOBAL_LUA_ROM_ID", _RomIdNum)
    end

    -- -------------------------------------------------------------------------
    -- Register_Outputs_Safe(out_handle)
    -- Writes 0 to every configured output when warmup completes and sets the LastOutputs caches to
    -- match, so that hardware left on by a previous game is switched off. The identity outputs are
    -- written with their values.
    -- -------------------------------------------------------------------------
    local function Register_Outputs_Safe(out_handle)
        if not out_handle then return end

        local function Sync_Global(key, value)
            if _GlobalOutputs[key] then
                Set_Output_Safe(out_handle, _GlobalOutputs[key], value)
                _GlobalLastOutputs[key] = value
            end
        end

        Sync_Global("GLOBAL_GAME_STATUS", 0)
        Sync_Global("GLOBAL_ATTRACT_STATUS", 0)
        Send_Identity_Outputs(out_handle)

        if CFG.CREDITS then
            Sync_Global("GLOBAL_CREDITS", 0)
            if CFG.ENABLE_CREDIT_COUNT then Sync_Global("GLOBAL_CREDITS_INSERTED", 0) end
        end

        for i = 1, CFG.MAX_PLAYERS do
            local p_cfg = _PlayerCFG[i]

            -- An output shared with player 1 is written once, by player 1.
            local shared = _SharedOutputs
            local function Sync_Output(cfg_key, out_key)
                if i > 1 and shared and shared[out_key] then return end
                if p_cfg[cfg_key] and _OutputNames[i][out_key] then
                    Set_Output_Safe(out_handle, _OutputNames[i][out_key], 0)
                    _Player[i].LastOutputs[out_key] = 0
                end
            end

            local function Sync_Force(out_key)
                if i > 1 and shared and shared[out_key] then return end
                if _OutputNames[i][out_key] then
                    Set_Output_Safe(out_handle, _OutputNames[i][out_key], 0)
                    _Player[i].LastOutputs[out_key] = 0
                end
            end

            Sync_Output("STATUS", "STATUS")
            Sync_Output("STATUS_ALT", "STATUS_ALT")

            if p_cfg.CREDITS then
                Sync_Output("CREDITS", "CREDITS")
                if CFG.ENABLE_CREDIT_COUNT then
                    Sync_Output("CREDITS", "CREDITS_INSERTED")
                    Sync_Output("CREDITS", "CREDITS_CONSUMED")
                end
            end

            local keys = {"AMMO", "AMMO_ALT", "AMMO_GRENADE", "LIFE", "LIFE_ALT", "DAMAGE", "RECOIL", "RELOAD", "RUMBLE", "LAMPSTART"}
            for _, k in ipairs(keys) do
                Sync_Output(k, k)
            end

            -- P*_Clip is derived from AMMO and has no setting of its own, so its reset is gated on
            -- AMMO.
            if _ClipEnabled then Sync_Output("AMMO", "CLIP") end

            -- The DemulShooter aliases are reset for every player, whether or not RECOIL or DAMAGE
            -- is configured.
            if CFG.DEMULSHOOTER_COMPATIBILITY then
                Sync_Force("CtmRecoil")
                Sync_Force("Damaged")
            end

            if CFG.ENABLE_DAMAGE_COUNT and p_cfg.DAMAGE_TAKEN then Sync_Output("DAMAGE_TAKEN", "DAMAGE_TAKEN") end
            if CFG.ENABLE_SHOT_COUNT then
                Sync_Force("SHOTS_FIRED")
                if p_cfg.SHOTS_FIRED_PRIMARY then Sync_Output("SHOTS_FIRED_PRIMARY", "SHOTS_FIRED_PRIMARY") end
                if p_cfg.SHOTS_FIRED_ALT then Sync_Output("SHOTS_FIRED_ALT", "SHOTS_FIRED_ALT") end
                if p_cfg.SHOTS_FIRED_GRENADE then Sync_Output("SHOTS_FIRED_GRENADE", "SHOTS_FIRED_GRENADE") end
            end
            if CFG.ENABLE_LIFE_LOST and p_cfg.LIFE_LOST then Sync_Output("LIFE_LOST", "LIFE_LOST") end
        end
    end

    -- -------------------------------------------------------------------------
    -- OUTPUT SPAM WRAPPERS:
    -- Write an output only when its value differs from the cached last value. They are defined at
    -- plugin scope and take `out` as a parameter, so that Frame_Logic allocates no closure for
    -- them.
    -- -------------------------------------------------------------------------
    local function Set_Output(out, p_idx, key, value)
        local p = (_SharedOutputs and _SharedOutputs[key]) and _Player[1] or _Player[p_idx]
        if p.LastOutputs[key] ~= value and _OutputNames[p_idx][key] then
            Set_Output_Safe(out, _OutputNames[p_idx][key], value)
            p.LastOutputs[key] = value
        end
    end

    -- Writes 0 to every player's pulse outputs. It is used where the timers that would end a pulse
    -- are about to be discarded: after a state load and at a reset. An output that has never
    -- been written is left alone.
    local function End_Pulses(out)
        for i = 1, CFG.MAX_PLAYERS do
            local sent = _Player[i].LastOutputs
            if sent.RECOIL then Set_Output(out, i, "RECOIL", 0) end
            if sent.RELOAD then Set_Output(out, i, "RELOAD", 0) end
            if sent.DAMAGE then Set_Output(out, i, "DAMAGE", 0) end
            if sent.RUMBLE then Set_Output(out, i, "RUMBLE", 0) end
            if sent.CtmRecoil then Set_Output(out, i, "CtmRecoil", 0) end
            if sent.Damaged then Set_Output(out, i, "Damaged", 0) end
        end
    end

    -- Starts a reload pulse for player p_idx. With alternating play, player 1 owns the shared
    -- output, so its timer is started as well.
    local function Start_Reload(out, p_idx, p, current_time)
        Set_Output(out, p_idx, "RELOAD", 1)
        p.ReloadTick = current_time
        p.IsReloadActive = true
        if not CFG.SIMULTANEOUS_PLAY and p_idx > 1 then
            _Player[1].ReloadTick = current_time
            _Player[1].IsReloadActive = true
        end
    end

    -- Compares a player's credits with the last frame's. A rise is counted as credits inserted, and
    -- a fall is held as a pending drop until a spawn consumes it.
    local function Track_Player_Credits(out, p_idx, p, credits)
        if credits > p.LastCredits then
            p.CreditsInserted = p.CreditsInserted + (credits - p.LastCredits)
            if CFG.ENABLE_CREDIT_COUNT then Set_Output(out, p_idx, "CREDITS_INSERTED", p.CreditsInserted) end
        elseif credits < p.LastCredits then
            p.PendingCreditDrops = p.PendingCreditDrops + (p.LastCredits - credits)
        end
        p.LastCredits = credits
    end

    local function Set_Global_Output(out, key, value)
        -- The name is checked as in Set_Output: a profile that overrides OUTPUT_SUFFIXES and omits
        -- a GLOBAL_ key would otherwise pass nil to Set_Output_Safe.
        if _GlobalLastOutputs[key] ~= value and _GlobalOutputs[key] then
            Set_Output_Safe(out, _GlobalOutputs[key], value)
            _GlobalLastOutputs[key] = value
        end
    end

    -- -------------------------------------------------------------------------
    -- Seed_Frame_Baselines()
    -- Sets every Last* baseline from the live values when warmup completes and after a save state
    -- loads. Without it the baselines start at 0, and values that already exist, such as credits
    -- held in NVRAM, are counted as new changes on the first tracked frame. The credit reads must
    -- match Frame_Logic's divisor; the ammo and life reads share Read_Counter with it.
    -- -------------------------------------------------------------------------
    local function Seed_Frame_Baselines()
        if not CFG then return end
        local divisor = CFG.COINS_PER_CREDIT or 1
        if divisor < 1 then divisor = 1 end

        if CFG.CREDITS and type(CFG.CREDITS) == "number" and not CFG.PLAYER_CREDITS_TRACKED then
            local raw = Read_Data_Safe(_MemHandles["GLOBAL_CREDITS"], CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS)
            _LastGlobalCredits = math.floor(raw / divisor)
            if _LastGlobalCredits > 0 then _HasCoinedUp = true end
        end

        -- With per-player credit addresses, Frame_Logic tracks their total as the global credits,
        -- so the global baseline is seeded from the same total.
        local player_credit_total = 0

        for i = 1, CFG.MAX_PLAYERS do
            local cfg = _PlayerCFG[i]
            local p = _Player[i]
            if cfg then
                if cfg.CREDITS and type(cfg.CREDITS) == "number" then
                    local raw = Read_Data_Safe(_MemHandles["CREDITS"], cfg.CREDITS, CFG.DATA_WIDTHS.CREDITS)
                    p.LastCredits = math.floor(raw / divisor)
                    player_credit_total = player_credit_total + p.LastCredits
                elseif cfg.CREDITS == "auto" and type(CFG.CREDITS) == "number" then
                    local raw = Read_Data_Safe(_MemHandles["GLOBAL_CREDITS"], CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS)
                    p.LastCredits = math.floor(raw / divisor)
                end
                if cfg.AMMO then p.LastAmmo = Read_Counter("AMMO", cfg.AMMO, CFG.AMMO_OFFSET, CFG.AMMO_MAX) end
                if cfg.AMMO_ALT then p.LastAmmoAlt = Read_Counter("AMMO_ALT", cfg.AMMO_ALT, CFG.AMMO_ALT_OFFSET, CFG.AMMO_ALT_MAX) end
                if cfg.AMMO_GRENADE then p.LastAmmoGrenade = Read_Counter("AMMO_GRENADE", cfg.AMMO_GRENADE, CFG.AMMO_GRENADE_OFFSET, CFG.AMMO_GRENADE_MAX) end
                if cfg.LIFE then p.LastLife = Read_Counter("LIFE", cfg.LIFE, CFG.LIFE_OFFSET, CFG.LIFE_MAX) end
                if cfg.LIFE_ALT then p.LastLifeAlt = Read_Counter("LIFE_ALT", cfg.LIFE_ALT, CFG.LIFE_ALT_OFFSET, CFG.LIFE_ALT_MAX) end
                if type(cfg.DAMAGE_TAKEN) == "number" then
                    p.LastDmgMem = Read_Data_Safe(_MemHandles["DAMAGE_TAKEN"], cfg.DAMAGE_TAKEN, CFG.DATA_WIDTHS.DAMAGE_TAKEN)
                end
                if cfg.DAMAGE and type(cfg.DAMAGE) == "number" then
                    p.LastDamageVal = Read_Data_Safe(_MemHandles["DAMAGE"], cfg.DAMAGE, CFG.DATA_WIDTHS.DAMAGE)
                end
                if cfg.RUMBLE and type(cfg.RUMBLE) == "number" then
                    p.LastRumbleEventVal = Read_Data_Safe(_MemHandles["RUMBLE"], cfg.RUMBLE, CFG.DATA_WIDTHS.RUMBLE)
                end
                if cfg.RELOAD and type(cfg.RELOAD) == "number" then
                    p.LastReloadVal = Read_Data_Safe(_MemHandles["RELOAD"], cfg.RELOAD, CFG.DATA_WIDTHS.RELOAD)
                end
                if cfg.RECOIL and type(cfg.RECOIL) == "number" then
                    p.LastRecoilVal = Read_Data_Safe(_MemHandles["RECOIL"], cfg.RECOIL, CFG.DATA_WIDTHS.RECOIL)
                end
            end
        end

        if CFG.PLAYER_CREDITS_TRACKED then
            _LastGlobalCredits = player_credit_total
            if player_credit_total > 0 then _HasCoinedUp = true end
        end
    end

    -- =========================================================================
    -- FORCE FEEDBACK state outputs (racing genre)  --  see CFG.FFB in the database
    -- Reads the game's raw force-feedback command (a native output or a memory address), decodes it
    -- and writes a standard set of effect channels. All state lives in the _FFB table, because
    -- startplugin is close to Lua's limit of 200 locals. The resolution and compute functions are
    -- attached in the "FORCE FEEDBACK RESOLUTION + COMPUTE" section.
    --
    -- Output channels (SCALE defaults to 255, which is lossless for every known source encoding):
    --   MSOP_P<n>_FFB_Constant  signed -SCALE..+SCALE  directional push force.
    --                          positive = force from the right (wheel pushed
    --                          left), negative = from the left, 0 = release.
    --   MSOP_P<n>_FFB_Spring    0..SCALE  self-centring spring strength.
    --   MSOP_P<n>_FFB_Friction  0..SCALE  steering friction / clutch drag.
    --   MSOP_P<n>_FFB_Damper    0..SCALE  velocity damping strength.
    --   MSOP_P<n>_FFB_Sine      0..SCALE  vibration/shake strength (the effect
    --                          period is a consumer-side tuning knob).
    --   MSOP_P<n>_FFB_Rumble    0..SCALE  continuous force-correlated motor
    --                          rumble level. Unsigned by contract: motor
    --                          routing lives in the consumer's config, and
    --                          direction is derivable from FFB_Constant's
    --                          sign. Coexists with the standard pulse-style
    --                          P<n>_Rumble output - a single-rumble-path
    --                          consumer should mix the two (max), never sum.
    --   MSOP_P<n>_FFB_Raw       the undecoded source value (diagnostics and
    --                          new-game analysis).
    --
    -- Semantic events (contract 2.2):
    --   MSOP_P<n>_FFB_Collision / FFB_GearChange / FFB_SurfaceRumble /
    --   FFB_TyreSlip / FFB_EngineRumble. Pulse/level strengths 0..SCALE read
    --   from separate per-game memory addresses via CFG.FFB.EVENTS (address-only
    --   by contract). Optional per game - a profile emits only what it can source.
    --
    -- Decoders (_FFB.decoders):
    --   parameters - (raw, scale)
    --   returns    - a partial {CHANNEL = value} table holding only the channels the game's
    --                command addresses this frame, or nil for "no change". A channel that is not
    --                returned keeps its last value until it is commanded again; an explicit 0
    --                releases it.
    --   state      - every decoder is a pure function of the command byte except harddrivin_serial,
    --                which assembles a frame.
    -- =========================================================================
    local _FFB = {
        proxy = false,       -- output mode: the output's proxy; legacy mode: the output manager
        source = false,      -- resolved source (name string or numeric address)
        mode = false,        -- "output" | "legacy" | "mem"
        probe_frames = 0,    -- frames spent probing, for the one-shot warning
        events_rt = {},      -- per-event runtime state (last value, pulse tick)
        hd = { s0=0, s1=0, s2=0, s3=0, frame=0, v0=0, v1=0, v2=0, v3=0 },
        enum = false,        -- cached native-output enumeration for this ROM...
        enum_done = false,   -- ...nil is a real answer, so this says it was fetched
        exhausted = false,   -- probing gave up: no configured SOURCE exists here
        channels = { "CONSTANT", "SPRING", "FRICTION", "DAMPER", "SINE", "RUMBLE" },

        -- Namco Super System 22 wheel lookup table (Rave Racer): maps the MCU's scrambled force
        -- byte to a linear force index 1..123, with -1 for a code that is never sent. Index it with
        -- (raw & 0xFF) + 1. The scramble has no closed form. Each of 1..123 appears exactly once,
        -- at an even byte value, and every odd byte is a code the MCU never sends.
        rr_map = {
            -1,-1,62,-1,30,-1,94,-1,  46,-1,78,-1,14,-1,110,-1,
            54,-1,70,-1,22,-1,102,-1, 38,-1,86,-1,6,-1,118,-1,
            59,-1,65,-1,27,-1,97,-1,  43,-1,81,-1,11,-1,113,-1,
            50,-1,74,-1,18,-1,106,-1, 34,-1,90,-1,2,-1,122,-1,
            60,-1,64,-1,28,-1,96,-1,  44,-1,80,-1,12,-1,112,-1,
            52,-1,72,-1,20,-1,104,-1, 36,-1,88,-1,4,-1,120,-1,
            56,-1,68,-1,24,-1,100,-1, 40,-1,84,-1,8,-1,116,-1,
            48,-1,76,-1,16,-1,108,-1, 32,-1,92,-1,1,-1,123,-1,
            61,-1,63,-1,29,-1,95,-1,  45,-1,79,-1,13,-1,111,-1,
            53,-1,71,-1,21,-1,103,-1, 37,-1,87,-1,5,-1,119,-1,
            57,-1,67,-1,25,-1,99,-1,  41,-1,83,-1,9,-1,115,-1,
            49,-1,75,-1,17,-1,107,-1, 33,-1,91,-1,-1,-1,-1,-1,
            58,-1,66,-1,26,-1,98,-1,  42,-1,82,-1,10,-1,114,-1,
            51,-1,73,-1,19,-1,105,-1, 35,-1,89,-1,3,-1,121,-1,
            55,-1,69,-1,23,-1,101,-1, 39,-1,85,-1,7,-1,117,-1,
            47,-1,77,-1,15,-1,109,-1, 31,-1,93,-1,-1,-1,-1,-1,
        },
    }

    -- Maps raw in (base, base + span] linearly onto 0..scale, clamped. The banded decoders share
    -- it.
    function _FFB.Band(raw, base, span, scale)
        local p = (raw - base) / span
        if p < 0 then p = 0 elseif p > 1 then p = 1 end
        return math.floor(p * scale + 0.5)
    end

    _FFB.decoders = {
        -- Passes the raw value to the Constant channel, for analysis of a new game. Compute limits
        -- it to the scale; FFB_Raw carries the value as read.
        passthrough = function(raw, scale) return { CONSTANT = raw } end,

        -- Two's-complement byte to signed Constant, for cabinets that send a full-range signed
        -- wheel force. 0x80..0xFF is 128 negative steps and 0x01..0x7F is 127 positive steps, so
        -- each side divides by its own span and reaches exactly +/-scale; 0x00 is neutral. Rounding
        -- is half away from zero. A cabinet wired the other way round sets FFB.INVERT.
        signed8 = function(raw, scale)
            local v = raw & 0xFF
            if v > 127 then
                local scaled = -((256 - v) * scale / 128)
                return { CONSTANT = math.ceil(scaled - 0.5) }
            end
            local scaled = v * scale / 127
            return { CONSTANT = math.floor(scaled + 0.5) }
        end,

        -- Konami racers (Thrill Drive, GTI Club, Midnight Run, Winding Heat,
        -- Racing Jam): bits 0-3 = force level 0-15, bit 4 = direction
        -- (set = force from the left). Level 0 releases regardless of bit 4.
        konami_dir4 = function(raw, scale)
            local level = raw & 0x0F
            if level == 0 then return { CONSTANT = 0, RUMBLE = 0 } end
            local force = math.floor((level * scale / 15) + 0.5)
            -- RUMBLE carries the unsigned magnitude; only CONSTANT is signed.
            if (raw & 0x10) ~= 0 then return { CONSTANT = -force, RUMBLE = force } end
            return { CONSTANT = force, RUMBLE = force }
        end,

        -- Sega Model 2 banded drive-board protocol (Over Rev, and the family
        -- Daytona/Sega Rally/Indy 500 belong to): one command byte per frame
        -- selects one effect band; every other channel keeps its last value.
        model2_bands = function(raw, scale)
            if raw == 0x00 then return { CONSTANT = 0, RUMBLE = 0 } end
            if raw > 0x09 and raw < 0x18 then return { SPRING   = _FFB.Band(raw, 0x0F, 8, scale) } end
            if raw > 0x1F and raw < 0x28 then return { FRICTION = _FFB.Band(raw, 0x1F, 8, scale) } end
            if raw > 0x2F and raw < 0x3D then return { SPRING   = _FFB.Band(raw, 0x2F, 13, scale) } end
            if raw > 0x3F and raw < 0x48 then return { SINE     = _FFB.Band(raw, 0x3F, 8, scale) } end
            if raw > 0x4F and raw < 0x58 then
                local f = _FFB.Band(raw, 0x4F, 8, scale)
                return { CONSTANT = f, RUMBLE = f }    -- roll: force from the right
            end
            if raw > 0x5F and raw < 0x68 then
                local f = _FFB.Band(raw, 0x5F, 8, scale)
                return { CONSTANT = -f, RUMBLE = f }   -- roll: force from the left
            end
            return { CONSTANT = 0 }                    -- neutral / unknown band
        end,

        -- Sega Rally (srallyc family): two 32-step bands on the drive-board byte.
        -- 0xC0-0xDF = force from the right, 0x80-0x9F = force from the left.
        sega_rally_bands = function(raw, scale)
            if raw == 0x00 then return { CONSTANT = 0, RUMBLE = 0 } end
            if raw >= 0xC0 and raw <= 0xDF then
                local f = math.floor(((raw - 0xC0) * scale / 31) + 0.5)
                return { CONSTANT = f, RUMBLE = f }
            elseif raw >= 0x80 and raw <= 0x9F then
                local f = math.floor(((raw - 0x80) * scale / 31) + 0.5)
                return { CONSTANT = -f, RUMBLE = f }
            end
            return nil -- outside both bands: leave the last force in place
        end,

        -- Hyper Neo Geo 64 racers (Roads Edge, Xtreme Rally): two 63-step bands.
        -- 193-255 = force from the left, 129-191 = force from the right.
        hng64_bands = function(raw, scale)
            if raw == 0 then return { CONSTANT = 0, RUMBLE = 0 } end
            if raw >= 193 and raw <= 255 then
                local f = math.floor(((raw - 193) * scale / 62) + 0.5)
                if f > scale then f = scale end
                return { CONSTANT = -f, RUMBLE = f }
            elseif raw >= 129 and raw <= 191 then
                local f = math.floor(((raw - 129) * scale / 62) + 0.5)
                if f > scale then f = scale end
                return { CONSTANT = f, RUMBLE = f }
            end
            return { CONSTANT = 0, RUMBLE = 0 }
        end,

        -- Side by Side 1/2 (Taito): low 5 bits carry the command. 0x00/0x1E/0x1F
        -- release; otherwise odd = force from the right, even = from the left, and
        -- the step count is inverted (a low command byte means a high force).
        sidebs_5bit = function(raw, scale)
            local v = raw & 0x1F
            if v == 0 or v == 0x1E or v == 0x1F then return { CONSTANT = 0, RUMBLE = 0 } end
            local steps = (v + 1) // 2
            if steps > 15 then steps = 15 end
            local f = math.floor((((16 - steps) * scale) / 15) + 0.5)
            if f > scale then f = scale end
            if (v & 1) == 1 then return { CONSTANT = f, RUMBLE = f } end
            return { CONSTANT = -f, RUMBLE = f }
        end,

        -- Virtua Racing (Sega Model 1): the digit0 command byte selects one effect
        -- band per frame, like the Model 2 protocol but with a different layout.
        virtua_racing = function(raw, scale)
            if raw == 0x03 or raw == 0x07 or raw == 0x09 or raw == 0x10 then
                return { SPRING = math.floor(scale * 0.8 + 0.5), CONSTANT = 0 }
            end
            if raw == 0x20 or raw == 0x28 then
                return { FRICTION = math.floor(scale * 0.4 + 0.5), CONSTANT = 0 }
            end
            if raw > 0x2F and raw < 0x40 then
                return { SPRING = _FFB.Band(raw, 0x2F, 11, scale), CONSTANT = 0 }
            end
            if raw == 0x40 or raw == 0x46 or raw == 0x4A then
                local f = math.floor(scale * 0.4 + 0.5)
                return { SINE = f, RUMBLE = f, CONSTANT = 0 }
            end
            if raw == 0x50 or raw == 0x5F then
                local f = math.floor(scale * 0.5 + 0.5)
                return { CONSTANT = f, RUMBLE = f }   -- roll: force from the right
            end
            if raw == 0x60 or raw == 0x6F then
                local f = math.floor(scale * 0.5 + 0.5)
                return { CONSTANT = -f, RUMBLE = f }  -- roll: force from the left
            end
            return { CONSTANT = 0 }
        end,

        -- Power Drift (Sega Y-board): the bank-motor position byte doubles as the
        -- steering command - 0x01-0x03 = from the left, 0x05-0x07 = from the right.
        pdrift_8step = function(raw, scale)
            if raw > 0x00 and raw < 0x04 then
                local f = math.floor((((4 - raw) * scale) / 3) + 0.5)
                return { CONSTANT = -f, RUMBLE = f }
            elseif raw > 0x04 and raw < 0x08 then
                local f = math.floor((((raw - 4) * scale) / 3) + 0.5)
                return { CONSTANT = f, RUMBLE = f }
            end
            return { CONSTANT = 0, RUMBLE = 0 }
        end,

        -- Cabinets whose only feedback line is an on/off shaker (Outrunners, Turbo
        -- OutRun, Chase Bombers, Double Axle, Cisco Heat, F-1 GP Star): any non-zero
        -- command means "vibrate", so the strength is a consumer-side tuning choice.
        flag_shake = function(raw, scale)
            if raw ~= 0 then return { SINE = scale, RUMBLE = scale } end
            return { SINE = 0, RUMBLE = 0 }
        end,

        -- Hard Drivin' / Race Drivin' (Atari): the driver writes the wheel force as a 4-byte frame
        -- through one output, so this decoder keeps state in _FFB.hd (cleared by _FFB.Reset).
        -- Compute's change gate feeds it value transitions, not every write. It returns nil on
        -- every intermediate write, which holds the last force in place.
        --   * an alternating 0xE0/0x00 run is the idle/sync pattern - it resets the
        --     frame cursor and is never treated as data;
        --   * v0 must stay < 200 and v1 > 200; anything else means the cursor has
        --     slipped out of phase with the frame, so collection restarts;
        --   * on the 5th write the frame decodes to a signed force:
        --       f = (v0 & 15) + ((v3 & 7) << 5), |0x10 when v1's high nibble is F,
        --       negated when v2's high nibble is F, clamped to +/-100 and rescaled.
        --     A positive frame value drives the wheel from the left, so the sign is
        --     inverted into MSOP's convention.
        harddrivin_serial = function(raw, scale)
            local h = _FFB.hd
            h.s3, h.s2, h.s1, h.s0 = h.s2, h.s1, h.s0, raw

            local sync = (raw == 0xE0 and h.s1 == 0x00 and h.s2 == 0xE0 and h.s3 == 0x00)
                      or (raw == 0x00 and h.s1 == 0xE0 and h.s2 == 0x00 and h.s3 == 0xE0)
            if sync then h.frame = 0; return nil end

            if h.frame > 4 then h.frame = 0 end
            if h.frame > 2 and (h.v0 > 200 or (h.v1 < 200 and h.v1 ~= 0)) then
                h.frame = 0; h.v1 = 0; h.v2 = 0; h.v3 = 0
            end

            if h.frame == 0 then h.v0 = raw
            elseif h.frame == 1 then h.v1 = raw
            elseif h.frame == 2 then h.v2 = raw
            elseif h.frame == 3 then h.v3 = raw end
            h.frame = h.frame + 1

            if h.frame ~= 5 then return nil end   -- frame still assembling
            h.frame = 0

            local f = (h.v0 & 15) + ((h.v3 & 7) << 5)
            if (h.v1 & 0xF0) == 0xF0 then f = f | 0x10 end
            if (h.v2 & 0xF0) == 0xF0 then f = -f end
            if f > 100 then f = 100 elseif f < -100 then f = -100 end

            local mag = math.floor(((f < 0 and -f or f) * scale / 100) + 0.5)
            -- A frame value of 0 or above is a force from the left, so the sign is inverted.
            if f >= 0 then return { CONSTANT = -mag, RUMBLE = mag } end
            return { CONSTANT = mag, RUMBLE = mag }
        end,

        -- Rave Racer (Namco): rr_map descrambles the MCU byte to 1..123, then
        -- <=0x3D = force from the right, >0x3D = from the left. -1 = ignore.
        namco_lut_rr = function(raw, scale)
            local v = _FFB.rr_map[(raw & 0xFF) + 1]
            if not v or v < 0 then return nil end
            if v > 0x3D and v < 0x7C then
                -- The left band has one more code than the right, so its strongest code is limited.
                local f = math.floor(((124 - v) * scale / 61) + 0.5)
                if f > scale then f = scale end
                return { CONSTANT = -f, RUMBLE = f }
            elseif v > 0x00 and v < 0x3E then
                local f = math.floor((v * scale / 61) + 0.5)
                return { CONSTANT = f, RUMBLE = f }
            end
            return { CONSTANT = 0, RUMBLE = 0 }
        end,
    }

    -- =========================================================================
    -- THE FRAME LOOP ENGINE (Frame_Logic)
    -- Runs once per frame and evaluates the profile's memory conditions. It is a named function so
    -- that Compute_Outputs can pass it to pcall without allocating a closure.
    -- =========================================================================
    local function Frame_Logic()
        local machine = manager.machine
        if not machine then _IsShuttingDown = true; return end

        local out = machine.output
        local current_time = machine.time
        if not out then return end

        -- -------------------------------------------------------------------------
        -- PERFORMANCE OPTIMISATION: One-Time Bus Binding Cache
        -- Binds each data type's address space or memory region on the first frame and keeps the
        -- handle. A memory space of "region" binds the memory region named by the tag instead of a
        -- CPU address space.
        -- -------------------------------------------------------------------------
        if not _HardwareBound then
            for key, conf in pairs(_MemConfig) do
                if string.lower(conf.space) == "region" then
                    local reg = machine.memory.regions[conf.tag]
                    if reg then _MemHandles[key] = reg end
                else
                    local dev = machine.devices[conf.tag]
                    if dev and dev.spaces[conf.space] then _MemHandles[key] = dev.spaces[conf.space] end
                end
            end
            _HardwareBound = true
        end

        -- -------------------------------------------------------------------------
        -- PHASE 0: WARMUP & INITIALISATION FLUSH
        -- Holds the outputs until the startup delay expires, then writes the zero state and seeds
        -- the baselines on that frame.
        -- -------------------------------------------------------------------------
        local warmup_ok = current_time > _StartupTime

        if warmup_ok and not _WarmupFlushed then
            Register_Outputs_Safe(out)
            Seed_Frame_Baselines() -- set the Last* baselines from live values
            _WarmupFlushed = true
            -- A relay that connected during the startup delay missed the outputs written in the
            -- frames before it. The resync sends them; the change filter drops the rest.
            Resync_Relay_State()
            return -- this frame delivers the zero state only
        end

        local divisor = CFG.COINS_PER_CREDIT or 1
        if divisor < 1 then divisor = 1 end

        -- -------------------------------------------------------------------------
        -- PHASE 1: GLOBAL STATUS & ATTRACT MODE
        -- -------------------------------------------------------------------------
        local is_attract_mode = false
        if CFG.ATTRACT_STATUS and type(CFG.ATTRACT_STATUS) == "number" then
            local val = Read_Data_Safe(_MemHandles["GLOBAL_ATTRACT_STATUS"], CFG.ATTRACT_STATUS, CFG.DATA_WIDTHS.GLOBAL_ATTRACT_STATUS or 8)
            local active = CFG.ATTRACT_STATUS_ACTIVE_VALUE
            is_attract_mode = Value_Is_Active(val, active)
            Set_Global_Output(out, "GLOBAL_ATTRACT_STATUS", warmup_ok and (is_attract_mode and 1 or 0) or 0)
            if is_attract_mode then _PendingGlobalCreditDrops = 0 end
        end

        -- The global credit address is not tracked when a player has a credit address of its own:
        -- the per-player total then stands for the global credits (see the end of Phase 2), and
        -- tracking both against one baseline would count every difference between them.
        if CFG.CREDITS and type(CFG.CREDITS) == "number" and not CFG.PLAYER_CREDITS_TRACKED then
            local raw = Read_Data_Safe(_MemHandles["GLOBAL_CREDITS"], CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS)
            local current_credits = math.floor(raw / divisor)
            Set_Global_Output(out, "GLOBAL_CREDITS", warmup_ok and current_credits or 0)
            if warmup_ok then
                if current_credits > _LastGlobalCredits then
                    _GlobalCreditsInserted = _GlobalCreditsInserted + (current_credits - _LastGlobalCredits)
                    if CFG.ENABLE_CREDIT_COUNT then Set_Global_Output(out, "GLOBAL_CREDITS_INSERTED", _GlobalCreditsInserted) end
                elseif current_credits < _LastGlobalCredits then
                    _PendingGlobalCreditDrops = _PendingGlobalCreditDrops + (_LastGlobalCredits - current_credits)
                end
                _LastGlobalCredits = current_credits
            end
            if current_credits > 0 and warmup_ok then _HasCoinedUp = true end
        end

        local is_game_active = false
        local global_exists = false

        if CFG.GAME_STATUS and type(CFG.GAME_STATUS) == "number" then
            global_exists = true
            if not is_attract_mode then
                local val = Read_Data_Safe(_MemHandles["GLOBAL_GAME_STATUS"], CFG.GAME_STATUS, CFG.DATA_WIDTHS.GLOBAL_GAME_STATUS)
                local active = CFG.GAME_STATUS_ACTIVE_VALUE
                is_game_active = Value_Is_Active(val, active)
                -- GAME_STATUS_ALT (optional) is a second address for a game that tracks
                -- activity in a different place per mode. Active when either address reads
                -- active. It shares the main address's CPU, memory space and data width, and
                -- GAME_STATUS_ALT_ACTIVE_VALUE defaults to GAME_STATUS_ACTIVE_VALUE.
                if not is_game_active and type(CFG.GAME_STATUS_ALT) == "number" then
                    local alt_val = Read_Data_Safe(_MemHandles["GLOBAL_GAME_STATUS"], CFG.GAME_STATUS_ALT, CFG.DATA_WIDTHS.GLOBAL_GAME_STATUS)
                    is_game_active = Value_Is_Active(alt_val, CFG.GAME_STATUS_ALT_ACTIVE_VALUE or active)
                end
            end
        elseif CFG.GAME_STATUS == "always" then
            -- GAME_STATUS "always": no game status address is known, and the profile declares the
            -- game active whenever it is running and not in address-backed attract mode. This lets
            -- a profile with no per-player activity signal raise GLOBAL_GAME_STATUS. The debounce
            -- below still applies. With false or "auto" the game status follows the players.
            global_exists = true
            is_game_active = not is_attract_mode
        end

        if is_game_active then
            if _GameActiveTick == _ZeroTime then _GameActiveTick = current_time; _GameDebounced = false end
            if not _GameDebounced then
                if (current_time - _GameActiveTick) <= _StatusDebounce then is_game_active = false else _GameDebounced = true end
            end
        else
            _GameActiveTick = _ZeroTime; is_game_active = false
        end


        -- -------------------------------------------------------------------------
        -- PHASE 2: CORE PLAYER ITERATION
        -- Processes each player in turn.
        -- -------------------------------------------------------------------------
        local any_player_active = false
        local aggregated_credits = 0
        local using_individual_credits = false
        local t_ammo = CFG.AMMO_THRESHOLD or 254
        local t_alt = CFG.AMMO_ALT_THRESHOLD or 254
        local t_grenade = CFG.AMMO_GRENADE_THRESHOLD or 254
        -- A "racing" profile skips the per-player gun pipeline: the loop runs zero times and the
        -- logic after it uses the defaults set above. "both" runs the gun pipeline as well.
        local player_loop_max = (CFG.GAME_TYPE == "racing") and 0 or CFG.MAX_PLAYERS
        for i = 1, player_loop_max do
            local cfg = _PlayerCFG[i]
            local p = _Player[i]

            if is_attract_mode then p.PendingCreditDrops = 0 end

            -- Read the ammo and life values.
            local curr_ammo, curr_ammo_alt, curr_ammo_grenade, curr_life, curr_life_alt = 0, 0, 0, 0, 0

            if cfg.AMMO then
                curr_ammo = Read_Counter("AMMO", cfg.AMMO, CFG.AMMO_OFFSET, CFG.AMMO_MAX)
            end
            if cfg.AMMO_ALT then
                curr_ammo_alt = Read_Counter("AMMO_ALT", cfg.AMMO_ALT, CFG.AMMO_ALT_OFFSET, CFG.AMMO_ALT_MAX)
            end
            if cfg.AMMO_GRENADE then
                curr_ammo_grenade = Read_Counter("AMMO_GRENADE", cfg.AMMO_GRENADE, CFG.AMMO_GRENADE_OFFSET, CFG.AMMO_GRENADE_MAX)
            end
            if cfg.LIFE then
                curr_life = Read_Counter("LIFE", cfg.LIFE, CFG.LIFE_OFFSET, CFG.LIFE_MAX)
            end
            if cfg.LIFE_ALT then
                curr_life_alt = Read_Counter("LIFE_ALT", cfg.LIFE_ALT, CFG.LIFE_ALT_OFFSET, CFG.LIFE_ALT_MAX)
            end

            -- Read and track the per-player credits.
            local p_credits = 0
            local p_credits_known = false
            if cfg.CREDITS then
                if type(cfg.CREDITS) == "number" then
                    local raw = Read_Data_Safe(_MemHandles["CREDITS"], cfg.CREDITS, CFG.DATA_WIDTHS.CREDITS)
                    p_credits = math.floor(raw / divisor)
                    p_credits_known = true
                    Set_Output(out, i, "CREDITS", warmup_ok and p_credits or 0)

                    -- Sum the per-player credits. The total replaces the global credits after the
                    -- loop.
                    aggregated_credits = aggregated_credits + p_credits
                    using_individual_credits = true

                    if warmup_ok then Track_Player_Credits(out, i, p, p_credits) end
                elseif cfg.CREDITS == "auto" and CFG.CREDITS then
                    p_credits = math.floor(Read_Data_Safe(_MemHandles["GLOBAL_CREDITS"], CFG.CREDITS, CFG.DATA_WIDTHS.GLOBAL_CREDITS) / divisor)
                    p_credits_known = true
                    Set_Output(out, i, "CREDITS", warmup_ok and p_credits or 0)

                    if warmup_ok then Track_Player_Credits(out, i, p, p_credits) end
                end
            end

            if cfg.LAMPSTART and (i == 1 or not _SharedOutputs) then
                local lampstart_val = warmup_ok and Read_Data_Safe(_MemHandles["LAMPSTART"], cfg.LAMPSTART, CFG.DATA_WIDTHS.LAMPSTART) or 0
                Set_Output(out, i, "LAMPSTART", lampstart_val)
                if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(out, i, "CtmLmpStart", lampstart_val) end
            end

            local is_player_active = false
            local out_status_val = 0
            local out_status_alt_val = 0

            -- Player activity, in priority order: the player's own STATUS addresses, then the
            -- global game status with life, then credits with life.
            if not is_attract_mode then
                if (cfg.STATUS and cfg.STATUS ~= "auto") or (cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto") then
                    local p_stat_active = false
                    local p_stat_alt_active = false
                    if cfg.STATUS and cfg.STATUS ~= "auto" then
                        local val = Read_Data_Safe(_MemHandles["STATUS"], cfg.STATUS, CFG.DATA_WIDTHS.STATUS)
                        local act = cfg.STATUS_ACTIVE_VALUE or CFG.STATUS_ACTIVE_VALUE
                        p_stat_active = Value_Is_Active(val, act)
                    end
                    if cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto" then
                        local val = Read_Data_Safe(_MemHandles["STATUS_ALT"], cfg.STATUS_ALT, CFG.DATA_WIDTHS.STATUS_ALT)
                        local act = cfg.STATUS_ALT_ACTIVE_VALUE or CFG.STATUS_ALT_ACTIVE_VALUE
                        p_stat_alt_active = Value_Is_Active(val, act)
                    end
                    if global_exists then
                        if is_game_active and p_stat_active then out_status_val = 1 end
                        if is_game_active and p_stat_alt_active then out_status_alt_val = 1 end
                    else
                        if p_stat_active then out_status_val = 1 end
                        if p_stat_alt_active then out_status_alt_val = 1 end
                    end
                    if out_status_val == 1 or out_status_alt_val == 1 then is_player_active = true end
                elseif global_exists then
                    if is_game_active and (curr_life > 0 or curr_life_alt > 0) then is_player_active = true; out_status_val = 1; out_status_alt_val = 1 end
                else
                    if _HasCoinedUp and (curr_life > 0 or curr_life_alt > 0) and ((not p_credits_known) or p_credits > 0) then is_player_active = true; out_status_val = 1; out_status_alt_val = 1 end
                end
            end

            if not warmup_ok then is_player_active = false; out_status_val = 0; out_status_alt_val = 0 end

            if is_player_active then
                if p.ActiveTick == _ZeroTime then p.ActiveTick = current_time; p.Debounced = false end
                if not p.Debounced then
                    if (current_time - p.ActiveTick) <= _StatusDebounce then is_player_active = false; out_status_val = 0; out_status_alt_val = 0 else p.Debounced = true end
                end
            else p.ActiveTick = _ZeroTime; out_status_val = 0; out_status_alt_val = 0 end

            p.IsActive = is_player_active
            if is_player_active then any_player_active = true end
            p.IsFFBAllowed = (CFG.FORCE_FEEDBACK_ENABLER == "status") and (out_status_val == 1 or out_status_alt_val == 1) or (CFG.FORCE_FEEDBACK_ENABLER == "life") and (curr_life > 0 or curr_life_alt > 0) or (CFG.FORCE_FEEDBACK_ENABLER == "gamestatus") and is_game_active or is_player_active
            -- Nothing is allowed before the startup delay ends, whatever boot memory reads.
            if not warmup_ok then p.IsFFBAllowed = false end

            if cfg.STATUS then Set_Output(out, i, "STATUS", out_status_val) end
            if cfg.STATUS_ALT then Set_Output(out, i, "STATUS_ALT", out_status_alt_val) end

            if CFG.ENABLE_CREDIT_COUNT and warmup_ok then
                local spawned = false

                -- Check 1: the player changed from inactive to active.
                if is_player_active and not p.WasActive then
                    spawned = true

                -- Check 2: life was refilled while the player stayed active (a continue). The
                -- p.WasActive guard stops an idle player whose life address changes from claiming
                -- another player's pending credit drop.
                elseif cfg.LIFE and p.WasActive then
                    if CFG.LIFE_DIRECTION == "decrease" and curr_life > p.LastLife and p.LastLife == 0 then spawned = true
                    elseif CFG.LIFE_DIRECTION == "increase" and curr_life < p.LastLife and curr_life == 0 then spawned = true end
                end

                if spawned then p.SpawnsAwaitingCredit = p.SpawnsAwaitingCredit + 1 end

                if p.SpawnsAwaitingCredit > 0 then
                    if p.PendingCreditDrops > 0 then
                        p.CreditsConsumed = p.CreditsConsumed + 1
                        p.PendingCreditDrops = p.PendingCreditDrops - 1
                        p.SpawnsAwaitingCredit = p.SpawnsAwaitingCredit - 1
                        Set_Output(out, i, "CREDITS_CONSUMED", p.CreditsConsumed)
                    elseif _PendingGlobalCreditDrops > 0 then
                        p.CreditsConsumed = p.CreditsConsumed + 1
                        _PendingGlobalCreditDrops = _PendingGlobalCreditDrops - 1
                        p.SpawnsAwaitingCredit = p.SpawnsAwaitingCredit - 1
                        Set_Output(out, i, "CREDITS_CONSUMED", p.CreditsConsumed)
                    end
                end
            end

            local just_died = (not is_player_active and p.WasActive)
            local primary_active = (out_status_val == 1)
            -- A player with a STATUS_ALT address of its own follows it for the alternate weapon and
            -- life, and each ammo count then triggers recoil and reload only while its own status
            -- is active. The two flags are fields of p and not locals: Frame_Logic's stack frame
            -- is large, and more locals make Lua regrow the stack on every frame.
            local alternate_active = primary_active
            p.PrimaryFires, p.AlternateFires = true, true
            if cfg.STATUS_ALT and cfg.STATUS_ALT ~= "auto" then
                alternate_active = (out_status_alt_val == 1)
                p.PrimaryFires, p.AlternateFires = primary_active, alternate_active
            end

            -- -------------------------------------------------------------------------
            -- PHASE 3: HARDWARE TRIGGERS (Recoil & Reload)
            -- -------------------------------------------------------------------------
            local auto_recoil_triggered_this_frame = false

            if p.IsFFBAllowed then
                  local trigger = 0
                  if CFG.ENABLE_RECOIL_AMMO ~= false and cfg.AMMO and p.PrimaryFires then
                      if CFG.AMMO_DIRECTION == "decrease" then if curr_ammo < p.LastAmmo and p.LastAmmo <= t_ammo then trigger = 1 end
                      elseif CFG.AMMO_DIRECTION == "change" then if curr_ammo ~= p.LastAmmo then trigger = 1 end
                      elseif curr_ammo > p.LastAmmo then trigger = 1 end
                  end
                  if CFG.ENABLE_RECOIL_AMMO_ALT ~= false and cfg.AMMO_ALT and p.AlternateFires then
                      if CFG.AMMO_ALT_DIRECTION == "decrease" then if curr_ammo_alt < p.LastAmmoAlt and p.LastAmmoAlt <= t_alt then trigger = 2 end
                      elseif CFG.AMMO_ALT_DIRECTION == "change" then if curr_ammo_alt ~= p.LastAmmoAlt then trigger = 2 end
                      elseif curr_ammo_alt > p.LastAmmoAlt then trigger = 2 end
                  end
                  if CFG.ENABLE_RECOIL_AMMO_GRENADE ~= false and cfg.AMMO_GRENADE and p.AlternateFires then
                      if CFG.AMMO_GRENADE_DIRECTION == "decrease" then if curr_ammo_grenade < p.LastAmmoGrenade and p.LastAmmoGrenade <= t_grenade then trigger = 3 end
                      elseif CFG.AMMO_GRENADE_DIRECTION == "change" then if curr_ammo_grenade ~= p.LastAmmoGrenade then trigger = 3 end
                      elseif curr_ammo_grenade > p.LastAmmoGrenade then trigger = 3 end
                  end

                  -- Start a recoil pulse from an ammo change.
                  if trigger > 0 and (cfg.RECOIL == "auto" or (type(cfg.RECOIL) == "number" and CFG.RECOIL_PRIORITY == "ammo")) then
                      if current_time - p.RecoilTick > _MinRecoilInterval then
                          if trigger == 1 then p.CurrentRecoilDuration = _RecoilDuration
                          elseif trigger == 2 then p.CurrentRecoilDuration = _RecoilAltDuration
                          elseif trigger == 3 then p.CurrentRecoilDuration = _RecoilGrenadeDuration end

                          Set_Output(out, i, "RECOIL", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(out, i, "CtmRecoil", 1) end
                          p.RecoilTick = current_time; p.IsRecoilActive = true; auto_recoil_triggered_this_frame = true
                          if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].RecoilTick = current_time; _Player[1].IsRecoilActive = true; _Player[1].CurrentRecoilDuration = p.CurrentRecoilDuration end
                      end
                  end

                  -- Start a reload pulse from an ammo change.
                  if CFG.ENABLE_RELOAD_AMMO ~= false and cfg.AMMO and p.PrimaryFires then
                      if (CFG.AMMO_DIRECTION == "decrease" and curr_ammo > p.LastAmmo) or (CFG.AMMO_DIRECTION == "increase" and curr_ammo < p.LastAmmo) then
                          if cfg.RELOAD then Start_Reload(out, i, p, current_time) end
                      end
                  end
                  if CFG.ENABLE_RELOAD_AMMO_ALT ~= false and cfg.AMMO_ALT and p.AlternateFires then
                      if (CFG.AMMO_ALT_DIRECTION == "decrease" and curr_ammo_alt > p.LastAmmoAlt) or (CFG.AMMO_ALT_DIRECTION == "increase" and curr_ammo_alt < p.LastAmmoAlt) then
                          if cfg.RELOAD then Start_Reload(out, i, p, current_time) end
                      end
                  end
                  if CFG.ENABLE_RELOAD_AMMO_GRENADE ~= false and cfg.AMMO_GRENADE and p.AlternateFires then
                      if (CFG.AMMO_GRENADE_DIRECTION == "decrease" and curr_ammo_grenade > p.LastAmmoGrenade) or (CFG.AMMO_GRENADE_DIRECTION == "increase" and curr_ammo_grenade < p.LastAmmoGrenade) then
                          if cfg.RELOAD then Start_Reload(out, i, p, current_time) end
                      end
                  end

                  -- Start a reload pulse from the RELOAD memory address.
                  if cfg.RELOAD and type(cfg.RELOAD) == "number" then
                      local val = Read_Data_Safe(_MemHandles["RELOAD"], cfg.RELOAD, CFG.DATA_WIDTHS.RELOAD)
                      local manual_trigger = false

                      if type(CFG.RELOAD_MEM_ADD_VALUE) == "table" then
                          local found_match = false
                          for _, v in ipairs(CFG.RELOAD_MEM_ADD_VALUE) do
                              if val == v then found_match = true; break end
                          end

                          local last_was_match = false
                          for _, v in ipairs(CFG.RELOAD_MEM_ADD_VALUE) do
                              if p.LastReloadVal == v then last_was_match = true; break end
                          end

                          manual_trigger = (found_match and not last_was_match)

                      elseif type(CFG.RELOAD_MEM_ADD_VALUE) == "number" then
                          manual_trigger = (val == CFG.RELOAD_MEM_ADD_VALUE and p.LastReloadVal ~= CFG.RELOAD_MEM_ADD_VALUE)

                      elseif type(CFG.RELOAD_MEM_MIN_VALUE) == "number" then
                          -- The value rose and is at or above the minimum.
                          manual_trigger = (val > p.LastReloadVal and val >= CFG.RELOAD_MEM_MIN_VALUE)

                      else
                          manual_trigger = (val > p.LastReloadVal)
                      end

                      if manual_trigger then
                          Start_Reload(out, i, p, current_time)
                      end
                      p.LastReloadVal = val
                  end

                  -- Start a recoil pulse from the RECOIL memory address.
                  if not auto_recoil_triggered_this_frame then
                      if cfg.RECOIL and type(cfg.RECOIL) == "number" then
                          local val = Read_Data_Safe(_MemHandles["RECOIL"], cfg.RECOIL, CFG.DATA_WIDTHS.RECOIL)
                          if (CFG.RECOIL_PRIORITY ~= "ammo" or curr_ammo == 0) then
                              local manual_trigger = false
                              if type(CFG.RECOIL_MEM_ADD_VALUE) == "number" then
                                  if CFG.RECOIL_METHOD == "hold" then manual_trigger = (val == CFG.RECOIL_MEM_ADD_VALUE) else manual_trigger = (val == CFG.RECOIL_MEM_ADD_VALUE and p.LastRecoilVal ~= CFG.RECOIL_MEM_ADD_VALUE) end
                              else
                                  -- RECOIL_MEM_MIN_VALUE (optional) is the lowest value that
                                  -- counts as an active recoil read. Unset, any value above zero
                                  -- is active.
                                  local is_active
                                  if type(CFG.RECOIL_MEM_MIN_VALUE) == "number" then is_active = (val >= CFG.RECOIL_MEM_MIN_VALUE) else is_active = (val > 0) end
                                  local method = CFG.RECOIL_METHOD
                                  if method == "hold" then manual_trigger = is_active
                                  elseif method == "change" then manual_trigger = (is_active and val ~= p.LastRecoilVal)
                                  elseif method == "latch" then manual_trigger = (is_active and p.LastRecoilVal == 0)
                                  else manual_trigger = (is_active and val > p.LastRecoilVal) end
                              end

                              local active_interval = (CFG.RECOIL_METHOD == "hold") and _RecoilHoldInterval or _MinRecoilInterval
                              if manual_trigger and (current_time - p.RecoilTick > active_interval) then
                                  p.CurrentRecoilDuration = _RecoilDuration; Set_Output(out, i, "RECOIL", 1)
                                  if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(out, i, "CtmRecoil", 1) end

                                  -- Count the shot here when no ammo address is configured, when
                                  -- RECOIL_PRIORITY makes this address the shot source, or when the
                                  -- primary ammo is empty.
                                  if CFG.ENABLE_SHOT_COUNT and warmup_ok and (not cfg.AMMO or CFG.RECOIL_PRIORITY ~= "ammo" or curr_ammo == 0) then
                                      p.ShotCountPrimary = p.ShotCountPrimary + 1
                                      Set_Output(out, i, "SHOTS_FIRED_PRIMARY", p.ShotCountPrimary)
                                  end
                                  p.RecoilTick = current_time; p.IsRecoilActive = true
                                  if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].RecoilTick = current_time; _Player[1].IsRecoilActive = true; _Player[1].CurrentRecoilDuration = p.CurrentRecoilDuration end
                              end
                          end
                          p.LastRecoilVal = val
                      end
                  end
            else
                -- Keep the memory baselines current while the gate is closed, so that a value that
                -- rose in the meantime is not read as a new event when the gate opens.
                if type(cfg.RELOAD) == "number" then p.LastReloadVal = Read_Data_Safe(_MemHandles["RELOAD"], cfg.RELOAD, CFG.DATA_WIDTHS.RELOAD) end
                if type(cfg.RECOIL) == "number" then p.LastRecoilVal = Read_Data_Safe(_MemHandles["RECOIL"], cfg.RECOIL, CFG.DATA_WIDTHS.RECOIL) end
            end

            -- -------------------------------------------------------------------------
            -- PHASE 4: STATISTICAL BROADCASTS & HIT DAMAGE
            -- Writes the live ammo and life values and the shot, damage and life counters.
            -- -------------------------------------------------------------------------
            if is_player_active or just_died then
                if primary_active then
                    if cfg.AMMO then
                        Set_Output(out, i, "AMMO", warmup_ok and curr_ammo or 0)
                        -- P*_Clip is 1 while rounds remain and 0 when the clip is empty (a reload
                        -- is needed).
                        if _ClipEnabled then Set_Output(out, i, "CLIP", (warmup_ok and curr_ammo > 0) and 1 or 0) end
                    end
                    if cfg.LIFE then Set_Output(out, i, "LIFE", warmup_ok and curr_life or 0) end

                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_PRIMARY and warmup_ok then
                        if type(cfg.SHOTS_FIRED_PRIMARY) == "number" then
                             local val = Read_Data_Safe(_MemHandles["SHOTS_FIRED_PRIMARY"], cfg.SHOTS_FIRED_PRIMARY, CFG.DATA_WIDTHS.SHOTS_FIRED_PRIMARY)
                             Set_Output(out, i, "SHOTS_FIRED_PRIMARY", val); p.ShotCountPrimary = val
                        -- An ammo drop counts shots unless a RECOIL address with RECOIL_PRIORITY
                        -- recoil is the shot source, so that a shot is not counted twice.
                        elseif cfg.SHOTS_FIRED_PRIMARY == "auto" and cfg.AMMO and p.WasActive
                            and not (type(cfg.RECOIL) == "number" and CFG.RECOIL_PRIORITY ~= "ammo") then
                            local diff = Shot_Delta(CFG.AMMO_DIRECTION, curr_ammo, p.LastAmmo, t_ammo)
                            if diff > 0 then
                                p.ShotCountPrimary = p.ShotCountPrimary + (CFG.SHOTS_FIRED_METHOD == "bullets" and diff or 1)
                                Set_Output(out, i, "SHOTS_FIRED_PRIMARY", p.ShotCountPrimary)
                            end
                        end
                    end
                else
                    if cfg.AMMO then
                        Set_Output(out, i, "AMMO", 0)
                        if _ClipEnabled then Set_Output(out, i, "CLIP", 0) end
                    end
                    if cfg.LIFE then Set_Output(out, i, "LIFE", 0) end
                end

                if alternate_active then
                    if cfg.AMMO_ALT then Set_Output(out, i, "AMMO_ALT", warmup_ok and curr_ammo_alt or 0) end
                    if cfg.LIFE_ALT then Set_Output(out, i, "LIFE_ALT", warmup_ok and curr_life_alt or 0) end

                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_ALT and warmup_ok then
                        if type(cfg.SHOTS_FIRED_ALT) == "number" then
                            local val = Read_Data_Safe(_MemHandles["SHOTS_FIRED_ALT"], cfg.SHOTS_FIRED_ALT, CFG.DATA_WIDTHS.SHOTS_FIRED_ALT)
                            Set_Output(out, i, "SHOTS_FIRED_ALT", val); p.ShotCountAlt = val
                        elseif cfg.SHOTS_FIRED_ALT == "auto" and cfg.AMMO_ALT and p.WasActive then
                            local diff = Shot_Delta(CFG.AMMO_ALT_DIRECTION, curr_ammo_alt, p.LastAmmoAlt, t_alt)
                            if diff > 0 then
                                p.ShotCountAlt = p.ShotCountAlt + (CFG.SHOTS_FIRED_ALT_METHOD == "bullets" and diff or 1)
                                Set_Output(out, i, "SHOTS_FIRED_ALT", p.ShotCountAlt)
                            end
                        end
                    end

                    if cfg.AMMO_GRENADE then Set_Output(out, i, "AMMO_GRENADE", warmup_ok and curr_ammo_grenade or 0) end
                    if CFG.ENABLE_SHOT_COUNT and cfg.SHOTS_FIRED_GRENADE and warmup_ok then
                        if type(cfg.SHOTS_FIRED_GRENADE) == "number" then
                            local val = Read_Data_Safe(_MemHandles["SHOTS_FIRED_GRENADE"], cfg.SHOTS_FIRED_GRENADE, CFG.DATA_WIDTHS.SHOTS_FIRED_GRENADE)
                            Set_Output(out, i, "SHOTS_FIRED_GRENADE", val); p.ShotCountGrenade = val
                        elseif cfg.SHOTS_FIRED_GRENADE == "auto" and cfg.AMMO_GRENADE and p.WasActive then
                            local diff = Shot_Delta(CFG.AMMO_GRENADE_DIRECTION, curr_ammo_grenade, p.LastAmmoGrenade, t_grenade)
                            if diff > 0 then
                                p.ShotCountGrenade = p.ShotCountGrenade + (CFG.SHOTS_FIRED_GRENADE_METHOD == "bullets" and diff or 1)
                                Set_Output(out, i, "SHOTS_FIRED_GRENADE", p.ShotCountGrenade)
                            end
                        end
                    end
                else
                    if cfg.AMMO_ALT then Set_Output(out, i, "AMMO_ALT", 0) end
                    if cfg.LIFE_ALT then Set_Output(out, i, "LIFE_ALT", 0) end
                    if cfg.AMMO_GRENADE then Set_Output(out, i, "AMMO_GRENADE", 0) end
                end
            else
                if cfg.AMMO then
                    Set_Output(out, i, "AMMO", 0)
                    if _ClipEnabled then Set_Output(out, i, "CLIP", 0) end
                end
                if cfg.LIFE then Set_Output(out, i, "LIFE", 0) end
                if cfg.AMMO_ALT then Set_Output(out, i, "AMMO_ALT", 0) end
                if cfg.LIFE_ALT then Set_Output(out, i, "LIFE_ALT", 0) end
                if cfg.AMMO_GRENADE then Set_Output(out, i, "AMMO_GRENADE", 0) end
            end

            if CFG.ENABLE_SHOT_COUNT and warmup_ok then
                local total_shots = p.ShotCountPrimary + p.ShotCountAlt + p.ShotCountGrenade
                Set_Output(out, i, "SHOTS_FIRED", total_shots)
            end

            -- Process damage, rumble and lives lost.
            if is_player_active or just_died then
                local hit_triggered = false

                -- Count the damage taken.
                if type(cfg.DAMAGE_TAKEN) == "number" then
                    local val = Read_Data_Safe(_MemHandles["DAMAGE_TAKEN"], cfg.DAMAGE_TAKEN, CFG.DATA_WIDTHS.DAMAGE_TAKEN)
                    if val > p.LastDmgMem and warmup_ok then
                        if CFG.ENABLE_DAMAGE_COUNT then p.DamageCount = p.DamageCount + 1; Set_Output(out, i, "DAMAGE_TAKEN", p.DamageCount) end
                        hit_triggered = true
                    end
                    p.LastDmgMem = val
                elseif cfg.DAMAGE_TAKEN == "auto" and (cfg.LIFE or cfg.LIFE_ALT) and p.WasActive then
                    local hit = (cfg.LIFE and ((CFG.LIFE_DIRECTION == "decrease" and curr_life < p.LastLife) or (CFG.LIFE_DIRECTION == "increase" and curr_life > p.LastLife))) or (cfg.LIFE_ALT and ((CFG.LIFE_ALT_DIRECTION == "decrease" and curr_life_alt < p.LastLifeAlt) or (CFG.LIFE_ALT_DIRECTION == "increase" and curr_life_alt > p.LastLifeAlt)))
                    if hit and warmup_ok then
                        if CFG.ENABLE_DAMAGE_COUNT then p.DamageCount = p.DamageCount + 1; Set_Output(out, i, "DAMAGE_TAKEN", p.DamageCount) end
                        hit_triggered = true
                    end
                end

                local ffb_now = p.IsFFBAllowed or (just_died and p.WasFFBAllowed)

                -- Start a damage pulse.
                if cfg.DAMAGE and ffb_now then
                    if type(cfg.DAMAGE) == "number" then
                        local val = Read_Data_Safe(_MemHandles["DAMAGE"], cfg.DAMAGE, CFG.DATA_WIDTHS.DAMAGE)
                        if val > p.LastDamageVal then
                            Set_Output(out, i, "DAMAGE", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(out, i, "Damaged", 1) end
                            p.DamageTick = current_time; p.IsDamageActive = true
                            if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].DamageTick = current_time; _Player[1].IsDamageActive = true end
                        end
                        p.LastDamageVal = val
                    elseif cfg.DAMAGE == "auto" and hit_triggered then
                        Set_Output(out, i, "DAMAGE", 1); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(out, i, "Damaged", 1) end
                        p.DamageTick = current_time; p.IsDamageActive = true
                        if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].DamageTick = current_time; _Player[1].IsDamageActive = true end
                    end
                end

                -- Start a rumble pulse.
                if cfg.RUMBLE and ffb_now then
                    if type(cfg.RUMBLE) == "number" then
                        local val = Read_Data_Safe(_MemHandles["RUMBLE"], cfg.RUMBLE, CFG.DATA_WIDTHS.RUMBLE)
                        if val > p.LastRumbleEventVal then
                            Set_Output(out, i, "RUMBLE", 1)
                            p.RumbleTick = current_time; p.IsRumbleActive = true
                            if not CFG.SIMULTANEOUS_PLAY and i > 1 then _Player[1].RumbleTick = current_time; _Player[1].IsRumbleActive = true end
                        end
                        p.LastRumbleEventVal = val
                    end
                end

                -- Count the lives lost: the total fall in life across the session.
                if CFG.ENABLE_LIFE_LOST then
                    if cfg.LIFE_LOST == "auto" and (cfg.LIFE or cfg.LIFE_ALT) and warmup_ok and p.WasActive then
                         local lost = false
                         local diff = 0
                         if cfg.LIFE then
                             if CFG.LIFE_DIRECTION == "decrease" then
                                 if curr_life < p.LastLife then lost = true; diff = p.LastLife - curr_life end
                             else
                                 if curr_life > p.LastLife then lost = true; diff = curr_life - p.LastLife end
                             end
                         end
                         if cfg.LIFE_ALT then
                             if CFG.LIFE_ALT_DIRECTION == "decrease" then
                                 if curr_life_alt < p.LastLifeAlt then lost = true; diff = diff + p.LastLifeAlt - curr_life_alt end
                             else
                                 if curr_life_alt > p.LastLifeAlt then lost = true; diff = diff + curr_life_alt - p.LastLifeAlt end
                             end
                         end
                         if lost then
                             p.LifeLostCount = p.LifeLostCount + diff
                             Set_Output(out, i, "LIFE_LOST", p.LifeLostCount)
                         end
                    elseif type(cfg.LIFE_LOST) == "number" then
                         local val = Read_Data_Safe(_MemHandles["LIFE_LOST"], cfg.LIFE_LOST, CFG.DATA_WIDTHS.LIFE_LOST)
                         Set_Output(out, i, "LIFE_LOST", val)
                    end
                end
            end

            -- The damage and rumble baselines are kept current while their gate is closed, for the
            -- same reason as the recoil and reload baselines in Phase 3.
            local player_tracked = is_player_active or just_died
            if not (player_tracked and (p.IsFFBAllowed or (just_died and p.WasFFBAllowed))) then
                if type(cfg.DAMAGE) == "number" then p.LastDamageVal = Read_Data_Safe(_MemHandles["DAMAGE"], cfg.DAMAGE, CFG.DATA_WIDTHS.DAMAGE) end
                if type(cfg.RUMBLE) == "number" then p.LastRumbleEventVal = Read_Data_Safe(_MemHandles["RUMBLE"], cfg.RUMBLE, CFG.DATA_WIDTHS.RUMBLE) end
            end
            if not player_tracked and type(cfg.DAMAGE_TAKEN) == "number" then
                p.LastDmgMem = Read_Data_Safe(_MemHandles["DAMAGE_TAKEN"], cfg.DAMAGE_TAKEN, CFG.DATA_WIDTHS.DAMAGE_TAKEN)
            end

            -- Store this frame's values as the baselines for the next frame.
            p.LastAmmo = curr_ammo; p.LastAmmoAlt = curr_ammo_alt; p.LastAmmoGrenade = curr_ammo_grenade
            p.LastLife = curr_life; p.LastLifeAlt = curr_life_alt; p.WasActive = p.IsActive; p.WasFFBAllowed = p.IsFFBAllowed

            -- End each pulse when its duration has elapsed.
            if CFG.SIMULTANEOUS_PLAY or i == 1 then
                if p.IsRecoilActive and (current_time - p.RecoilTick > p.CurrentRecoilDuration) then Set_Output(out, i, "RECOIL", 0); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(out, i, "CtmRecoil", 0) end; p.IsRecoilActive = false end
                if p.IsReloadActive and (current_time - p.ReloadTick > _ReloadDuration) then Set_Output(out, i, "RELOAD", 0); p.IsReloadActive = false end
                if p.IsDamageActive and (current_time - p.DamageTick > _DamageDuration) then Set_Output(out, i, "DAMAGE", 0); if CFG.DEMULSHOOTER_COMPATIBILITY then Set_Output(out, i, "Damaged", 0) end; p.IsDamageActive = false end
                if p.IsRumbleActive and (current_time - p.RumbleTick > _RumbleDuration) then Set_Output(out, i, "RUMBLE", 0); p.IsRumbleActive = false end
            end
        end

        -- When per-player credits are configured, their total replaces the global credits.
        if using_individual_credits then
            Set_Global_Output(out, "GLOBAL_CREDITS", warmup_ok and aggregated_credits or 0)
            if warmup_ok then
                if aggregated_credits > _LastGlobalCredits then
                    _GlobalCreditsInserted = _GlobalCreditsInserted + (aggregated_credits - _LastGlobalCredits)
                    if CFG.ENABLE_CREDIT_COUNT then Set_Global_Output(out, "GLOBAL_CREDITS_INSERTED", _GlobalCreditsInserted) end
                elseif aggregated_credits < _LastGlobalCredits then
                    _PendingGlobalCreditDrops = _PendingGlobalCreditDrops + (_LastGlobalCredits - aggregated_credits)
                end
                _LastGlobalCredits = aggregated_credits
            end
            if aggregated_credits > 0 and warmup_ok then _HasCoinedUp = true end
        end

        local final_game_active = ((global_exists and is_game_active) or (not global_exists and any_player_active))
        Set_Global_Output(out, "GLOBAL_GAME_STATUS", warmup_ok and final_game_active and 1 or 0)

        -- Derived attract mode: with no attract address, attract is reported when warmup is
        -- complete, no game is active and no player is active. It is an output only. Unlike the
        -- address-backed detection in Phase 1, it must never gate memory reads or clear pending
        -- credit accounting.
        if not (CFG.ATTRACT_STATUS and type(CFG.ATTRACT_STATUS) == "number") then
            Set_Global_Output(out, "GLOBAL_ATTRACT_STATUS", (warmup_ok and not final_game_active and not any_player_active) and 1 or 0)
        end

        -- Clear the pending credit accounting after CREDITS_CLEAR_TIMEOUT_SEC of inactivity.
        if not final_game_active then
            if _GameInactiveTick == _ZeroTime then
                _GameInactiveTick = current_time
            elseif _CreditsClearTimeout and (current_time - _GameInactiveTick > _CreditsClearTimeout) then
                _PendingGlobalCreditDrops = 0
                for i = 1, CFG.MAX_PLAYERS do
                    _Player[i].PendingCreditDrops = 0
                    _Player[i].SpawnsAwaitingCredit = 0
                end
            end
        else
            _GameInactiveTick = _ZeroTime
        end

        -- -------------------------------------------------------------------------
        -- PHASE 5: MEMORY PATCHING
        -- Writes the screen flash disable values to memory on every frame.
        -- -------------------------------------------------------------------------
        if warmup_ok and CFG.SCREEN_FLASH then
            -- 1. The global patch, if configured.
            if CFG.SCREEN_FLASH_MEMORY_ADDRESS and CFG.SCREEN_FLASH_DISABLE_VALUE then
                Write_Data_Safe(_MemHandles["SCREEN_FLASH"], CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.DATA_WIDTHS.SCREEN_FLASH or 8, CFG.SCREEN_FLASH_DISABLE_VALUE)
            end

            -- 2. The per-player patches.
            for i = 1, CFG.MAX_PLAYERS do
                local p_cfg = _PlayerCFG[i]
                if p_cfg.SCREEN_FLASH_MEMORY_ADDRESS and p_cfg.SCREEN_FLASH_DISABLE_VALUE then
                    Write_Data_Safe(_MemHandles["SCREEN_FLASH"], p_cfg.SCREEN_FLASH_MEMORY_ADDRESS, CFG.DATA_WIDTHS.SCREEN_FLASH or 8, p_cfg.SCREEN_FLASH_DISABLE_VALUE)
                end
            end
        end

        -- -------------------------------------------------------------------------
        -- PHASE 6: FORCE FEEDBACK STATE OUTPUTS (racing genre)
        -- Reads and decodes the game's force command. It does nothing unless the profile has
        -- FFB.ENABLED = true. _FFB.Compute is defined in the "FORCE FEEDBACK RESOLUTION + COMPUTE"
        -- section and is looked up at call time.
        -- -------------------------------------------------------------------------
        _FFB.Compute(out, warmup_ok, current_time)
    end

    -- -------------------------------------------------------------------------
    -- Driver_Source_Key()
    -- Returns the running machine's driver source file as a lowercase basename with no directory
    -- and no extension: ".../src/mame/namco/namcos12.cpp" -> "namcos12".
    -- native_outputs_by_driver.lua is keyed this way. The path can use either slash, depending on
    -- the build host. Returns nil if the field is unavailable.
    -- -------------------------------------------------------------------------
    local function Driver_Source_Key()
        local ok, src = pcall(function() return manager.machine.system.source_file end)
        if not ok or type(src) ~= "string" or src == "" then return nil end
        local base = src:match("([^/\\]+)$") or src
        base = base:gsub("%.[Cc][Pp][Pp]$", "")
        return base ~= "" and base:lower() or nil
    end

    -- -------------------------------------------------------------------------
    -- Probe_Enumerate_Outputs() / Enumerate_Native_Outputs()
    -- Lists the outputs the running machine has created, through MAME's read-only device.outputs
    -- property. Nothing is created. It replaces the scraped database files, which are keyed by
    -- driver source file: they name outputs a given machine never creates and miss drivers that
    -- were never scraped.
    -- Returns:
    --   nil         - this build cannot enumerate; the caller falls back to the scraped files.
    --   empty table - a real answer: this machine created no outputs.
    --   records     - one per output: { dev, name, wire, proxy } (see Forward_Native_Outputs).
    -- -------------------------------------------------------------------------

    -- Recognises MSOP's own output names, so that enumeration never treats one as a native output:
    -- the MSOP_* names and the three unprefixed per-player names (P<n>_CtmRecoil, P<n>_CtmLmpStart,
    -- P<n>_Damaged). On MAME 0.288 and earlier those names exist in the machine's output table, and
    -- Set_Output_Safe already sends them over the relay.
    local function Is_MSOP_Output_Name(name)
        return (name:match("^MSOP_") or name:match("^P%d+_Ctm") or name:match("^P%d+_Damaged$")) ~= nil
    end

    local function Probe_Enumerate_Outputs()
        if _EnumerateOutputsSupported ~= nil then return _EnumerateOutputsSupported end

        local ok, val = pcall(function()
            local root = manager.machine.devices[":"]
            return root and root.outputs or nil
        end)
        -- device.outputs (stock MAME 0.290 and later) is a userdata container of live output
        -- proxies keyed by name, not a Lua table, so its type is not tested. The test is that
        -- pairs() can iterate it. A build without the property returns nil.
        local usable = false
        if ok and val ~= nil then
            usable = pcall(function() for _ in pairs(val) do break end end)
        end
        _EnumerateOutputsSupported = usable and true or false

        if _EnumerateOutputsSupported then
            dbg_print("Native output discovery: ENUMERATED from the running machine "
                      .. "(device.outputs) - scraped databases not consulted")
        else
            dbg_print("Native output discovery: device.outputs unavailable on this build - "
                      .. "falling back to the scraped databases")
        end
        return _EnumerateOutputsSupported
    end

    local function Enumerate_Native_Outputs()
        if not Probe_Enumerate_Outputs() then return nil end

        local records = {}
        local ok = pcall(function()
            for _, dev in pairs(manager.machine.devices) do
                local list = dev.outputs
                if list ~= nil then
                    local is_root = not dev.owner
                    -- device.outputs iterates as (name, live output proxy); the proxy is kept on
                    -- the record. The wire name is MAME's qualified output name, as the -output
                    -- modules send it: plain for a root-device output, else the device tag without
                    -- its leading colon, then ':', then the name (osd::output_item's constructor).
                    for name, proxy in pairs(list) do
                        if type(name) == "string" and not Is_MSOP_Output_Name(name) then
                            records[#records + 1] = {
                                dev   = dev,
                                name  = name,
                                wire  = is_root and name or (dev.tag:sub(2) .. ":" .. name),
                                proxy = proxy,
                            }
                        end
                    end
                end
            end
        end)
        if not ok then
            -- The walk raised an error. Enumeration is treated as unsupported for the rest of the
            -- session.
            _EnumerateOutputsSupported = false
            dbg_print("Native output enumeration failed mid-walk - reverting to scraped databases")
            return nil
        end
        return records
    end

    -- A named function for the pcalls in Forward_Native_Outputs and _FFB.Resolve. Both can retry
    -- every frame, and a closure per attempt would allocate on every frame.
    local function Resolve_Device_Output(fwd)
        return fwd.dev:output(fwd.name)
    end

    -- Native output reads for MAME 0.288 and earlier, which have no output proxies.
    -- name_to_id returns 0 for a name the machine never created and creates nothing;
    -- get_value reads the current value. Call them only when _LegacyCreateWorks is true:
    -- MAME 0.289 and later have no name_to_id and print a warning on every get_value.
    local function Legacy_Output_Id(name)
        return manager.machine.output:name_to_id(name)
    end

    local function Legacy_Output_Value(out, name)
        return out:get_value(name)
    end

    -- -------------------------------------------------------------------------
    -- Forward_Native_Outputs()
    -- Sends the native outputs in _NativeForwards (the driver's own outputs, such as "lamp0") over
    -- the relay, because MAME does not broadcast them with -output none or console. It only reads:
    -- nothing is written back. The names in CFG.ADDITIONAL_OUTPUT_FORWARDS are always included.
    -- on_start and on_machine_stop replace the table, so it never outlives its machine.
    --
    -- _NativeForwards is an array of records, not bare names:
    --     { dev = <device or nil>, name = "lamp0", wire = "lamp0", proxy = ... }
    --   * dev   - the device that owns the output, when it was discovered by
    --             enumeration. nil for a name that came from a database or from
    --             ADDITIONAL_OUTPUT_FORWARDS, which resolves against the root
    --             device.
    --   * name  - the output's name on its owning device.
    --   * wire  - the name put on the relay. This is MAME's own qualified name,
    --             so an output owned by a subdevice goes out as "sub:lamp0",
    --             matching what MAME's -output network module would broadcast.
    --             For a root-device output (every arcade driver in practice)
    --             the qualified name is the relative name, so payloads are
    --             byte-identical to the scraped-fallback path's.
    --   * proxy - resolved lazily on first use and cached in the record; false
    --             once a miss is known to be permanent. See _RetryMissingProxies.
    --   * legacy - true once the name is confirmed to exist on a build without
    --             output proxies (MAME 0.288 and earlier); read through
    --             Legacy_Output_Value from then on.
    --   * misses - frames in which a retried lookup failed. At 600 the miss is
    --             made permanent, or on a build without proxies the lookup slows.
    --   * wait  - frames left before the next slow lookup on a build without
    --             proxies.
    --   * legacy_out - a field of the table itself: the machine's output manager, fetched once
    --             for the legacy reads.
    -- -------------------------------------------------------------------------
    local function Forward_Native_Outputs()
        -- msop_out drops every write while the relay is down or unused, so the records are not
        -- walked then. A connect clears last_state, so the first connected frame sends every
        -- current value.
        if not (_UseRelay and connected) then return end
        for _, fwd in ipairs(_NativeForwards) do
            local proxy = fwd.proxy
            if proxy == nil and not fwd.legacy and (fwd.wait or 0) > 0 then
                fwd.wait = fwd.wait - 1
            elseif proxy == nil and not fwd.legacy then
                if fwd.dev then
                    -- Enumerated: resolve against the device that owns the output. Get_Output_Proxy
                    -- looks only at the root device, so this is the only path that reaches a
                    -- subdevice's outputs.
                    local ok, p = pcall(Resolve_Device_Output, fwd)
                    proxy = (ok and p and p:exists()) and p or false
                elseif _LegacyCreateProbed and _LegacyCreateWorks then
                    -- A build without proxies: only the output manager can find the name.
                    proxy = false
                    local ok, id = pcall(Legacy_Output_Id, fwd.name)
                    if ok and type(id) == "number" and id ~= 0 then fwd.legacy = true end
                else
                    proxy = Get_Output_Proxy(fwd.name, nil) or false
                end
                -- A miss is not cached at once while _RetryMissingProxies is set, because an output
                -- whose device started late may appear a few frames in. After 600 frames it is.
                -- A build without proxies never caches it, as an output there can be created by its
                -- first write at any time: after 600 frames it looks once every 60 frames.
                local legacy_build = _LegacyCreateProbed and _LegacyCreateWorks
                if proxy or not (_RetryMissingProxies or legacy_build) then
                    fwd.proxy = proxy
                elseif not fwd.legacy then
                    fwd.misses = (fwd.misses or 0) + 1
                    if fwd.misses >= 600 then
                        if legacy_build then fwd.wait = 59 else fwd.proxy = false end
                    end
                end
            end
            if proxy then
                msop_out(fwd.wire, proxy:get())
            elseif fwd.legacy then
                local legacy_out = _NativeForwards.legacy_out
                if not legacy_out then
                    legacy_out = manager.machine.output
                    _NativeForwards.legacy_out = legacy_out
                end
                local ok, val = pcall(Legacy_Output_Value, legacy_out, fwd.name)
                if ok and type(val) == "number" then msop_out(fwd.wire, val) end
            end
        end
    end

    -- =========================================================================
    -- FORCE FEEDBACK RESOLUTION + COMPUTE
    -- The state table and decoders are declared before Frame_Logic. These functions are defined
    -- here because resolution needs Enumerate_Native_Outputs in scope. Frame_Logic's PHASE 6 looks
    -- _FFB.Compute up at call time.
    -- =========================================================================

    -- Looks one output name up on the root device without writing anything. Get_Output_Proxy is not
    -- used, because its miss path writes a legacy 0 and a driver's own output must never be
    -- written. It is the fallback when the build cannot enumerate.
    function _FFB.Probe_Output(name)
        if not (manager and manager.machine and manager.machine.devices) then return false end
        local root = manager.machine.devices[":"]
        if not (root and root.output) then return false end
        local ok, p = pcall(Resolve_Root_Output, root, name)
        if ok and p and p:exists() then return p end
        return false
    end

    function _FFB.Reset()
        _FFB.proxy = false
        _FFB.source = false
        _FFB.mode = false
        _FFB.probe_frames = 0
        _FFB.exhausted = false
        -- The next machine has its own output table, so the cached enumeration
        -- from the last one must not be reused.
        _FFB.enum = false
        _FFB.enum_done = false
        _FFB.events_rt = {}
        -- Per-ROM decode caches: the resolved decoder/scale (they cannot change
        -- mid-ROM) and the last decoded command value (Compute's change gate).
        _FFB.decoder = nil
        _FFB.scale = nil
        _FFB.last_raw = nil
        _FFB.hd = { s0=0, s1=0, s2=0, s3=0, frame=0, v0=0, v1=0, v2=0, v3=0 }
    end

    -- Realigns the FFB state after a state load. An event's timer and last value belong to the
    -- timeline before the load: the timer could hold its output on for minutes and the last value
    -- could fire a false event. A pulsing event output is ended, and the stream is decoded afresh.
    function _FFB.Post_Load(out)
        local cfgF = CFG.FFB
        if not (cfgF and cfgF.ENABLED == true) then return end
        local p_idx = tonumber(cfgF.PLAYER) or 1
        if p_idx < 1 or p_idx > CFG.MAX_PLAYERS then p_idx = 1 end
        for _, rt in pairs(_FFB.events_rt) do
            -- A pulsing event is ended. Any other event output keeps its cached value.
            if rt.tick then Set_Output(out, p_idx, rt.out_key, 0) end
            rt.last = false
            rt.tick = false
        end
        _FFB.last_raw = nil
        _FFB.hd = { s0=0, s1=0, s2=0, s3=0, frame=0, v0=0, v1=0, v2=0, v3=0 }
    end

    -- Walks CFG.FFB.SOURCES in order and takes the first source that resolves. A number is a memory
    -- address, read through _MemHandles["FFB"]. A string is a native output name, resolved through
    -- enumeration first and then the root-device probe. It is retried every frame until a source
    -- resolves, because driver outputs may not exist on the first frame.
    function _FFB.Resolve()
        local cfgF = CFG.FFB
        for _, src in ipairs(cfgF.SOURCES) do
            if type(src) == "number" then
                if _MemHandles["FFB"] then
                    _FFB.source = src
                    _FFB.mode = "mem"
                    dbg_print(string.format("FFB: source resolved to memory address 0x%08X", src))
                    return true
                end
            elseif type(src) == "string" then
                -- The enumeration is cached for the ROM session (cleared by _FFB.Reset), because
                -- this function retries every frame and a machine's output table does not change.
                -- It is fetched on first need, so a profile whose address source resolves never
                -- enumerates.
                if not _FFB.enum_done then
                    _FFB.enum = Enumerate_Native_Outputs()
                    _FFB.enum_done = true
                end
                local enumerated = _FFB.enum
                if enumerated then
                    for _, rec in ipairs(enumerated) do
                        if rec.name == src or rec.wire == src then
                            local ok, p = pcall(Resolve_Device_Output, rec)
                            if ok and p and p:exists() then
                                _FFB.proxy = p
                                _FFB.source = src
                                _FFB.mode = "output"
                                dbg_print("FFB: source resolved to native output '" .. rec.wire .. "' (enumerated)")
                                return true
                            end
                        end
                    end
                else
                    local p = _FFB.Probe_Output(src)
                    if p then
                        _FFB.proxy = p
                        _FFB.source = src
                        _FFB.mode = "output"
                        dbg_print("FFB: source resolved to native output '" .. src .. "' (root probe)")
                        return true
                    end
                    -- MAME 0.288 and earlier have no output proxies. The name is looked up and
                    -- read through the output manager, which _FFB.proxy then holds.
                    if _LegacyCreateWorks then
                        local ok, id = pcall(Legacy_Output_Id, src)
                        if ok and type(id) == "number" and id ~= 0 then
                            _FFB.proxy = manager.machine.output
                            _FFB.source = src
                            _FFB.mode = "legacy"
                            dbg_print("FFB: source resolved to native output '" .. src .. "' (output manager)")
                            return true
                        end
                    end
                end
            end
        end
        _FFB.probe_frames = _FFB.probe_frames + 1
        if _FFB.probe_frames == 600 then
            -- Stop probing for the rest of the ROM session. After 600 frames of misses the output
            -- table will not gain the source.
            _FFB.exhausted = true
            dbg_print("FFB WARNING: no source found after 600 frames - none of the configured SOURCES exist for this ROM; probing stopped")
        end
        return false
    end

    -- Semantic events (contract 2.2). Each configured event reads its own per-game memory address
    -- (address-only by contract) through the shared FFB memory binding (CPU_TAGS.FFB /
    -- MEMORY_SPACES.FFB) and writes a pulse or level strength 0..SCALE.
    -- Event settings (CFG.FFB.EVENTS[<KEY>], where <KEY> is COLLISION / GEARCHANGE / SURFACERUMBLE
    -- / TYRESLIP / ENGINERUMBLE):
    --   SOURCE      "0x..." memory address (required; hex string -> number at load)
    --   MODE        "nonzero"  level: STRENGTH while raw ~= 0, else 0 (default)
    --               "change"   pulse STRENGTH for DURATION_MS when raw changes
    --               "increase" pulse when raw increases (event counters)
    --               "value"    raw scaled 0..SCALE against MAX
    --   STRENGTH    pulse/level strength (default SCALE)
    --   DURATION_MS pulse length for change/increase (default 150)
    --   MAX         full-scale raw value for "value" mode (default SCALE)
    --   WIDTH       read width override (default DATA_WIDTHS.FFB)
    -- Unknown keys emit nothing (Set_Output's name guard skips them).
    function _FFB.Compute_Events(out, p_idx, current_time)
        local events = CFG.FFB.EVENTS
        if type(events) ~= "table" then return end
        local mem = _MemHandles["FFB"]
        if not mem then return end
        local def_width = CFG.DATA_WIDTHS.FFB or 8
        local scale = tonumber(CFG.FFB.SCALE) or 255

        for key, ev in pairs(events) do
            if type(ev) == "table" and type(ev.SOURCE) == "number" then
                local rt = _FFB.events_rt[key]
                if not rt then
                    -- The event settings do not change during the ROM session (events_rt is cleared
                    -- by _FFB.Reset), so they are normalised once here.
                    local max = tonumber(ev.MAX) or scale
                    if max < 1 then max = 1 end
                    rt = { last = false, tick = false,
                           dur = emu.attotime.from_msec(math.floor((tonumber(ev.DURATION_MS) or 150) + 0.5)),
                           mode = string.lower(tostring(ev.MODE or "nonzero")),
                           strength = tonumber(ev.STRENGTH) or scale,
                           max = max,
                           width = ev.WIDTH or def_width,
                           out_key = "FFB_" .. key }
                    _FFB.events_rt[key] = rt
                end
                local raw = Read_Data_Safe(mem, ev.SOURCE, rt.width)
                local mode = rt.mode
                local out_key = rt.out_key

                if mode == "value" then
                    local v = math.floor(raw * scale / rt.max + 0.5)
                    if v < 0 then v = 0 elseif v > scale then v = scale end
                    Set_Output(out, p_idx, out_key, v)
                elseif mode == "change" or mode == "increase" then
                    local fire = false
                    if rt.last ~= false then
                        if mode == "increase" then fire = raw > rt.last
                        else fire = raw ~= rt.last end
                    end
                    if fire then
                        rt.tick = current_time
                        Set_Output(out, p_idx, out_key, rt.strength)
                    elseif rt.tick and (current_time - rt.tick) > rt.dur then
                        rt.tick = false
                        Set_Output(out, p_idx, out_key, 0)
                    end
                else -- "nonzero" (default): level-style flag held by the game
                    Set_Output(out, p_idx, out_key, (raw ~= 0) and rt.strength or 0)
                end

                rt.last = raw
            end
        end
    end

    -- Called once per frame from Frame_Logic's PHASE 6. Holds every FFB output at 0 during warmup,
    -- then reads, decodes and writes through Set_Output. The stream channels need a source in
    -- SOURCES to resolve. Semantic events are separate reads, so a profile with events only also
    -- works. Only the channels a decoder returns are updated.
    function _FFB.Compute(out, warmup_ok, current_time)
        local cfgF = CFG.FFB
        if not (cfgF and cfgF.ENABLED == true) then return end

        local p_idx = tonumber(cfgF.PLAYER) or 1
        if p_idx < 1 or p_idx > CFG.MAX_PLAYERS then p_idx = 1 end

        if not warmup_ok then
            for _, ch in ipairs(_FFB.channels) do
                Set_Output(out, p_idx, "FFB_" .. ch, 0)
            end
            Set_Output(out, p_idx, "FFB_RAW", 0)
            if type(cfgF.EVENTS) == "table" then
                for key in pairs(cfgF.EVENTS) do
                    Set_Output(out, p_idx, "FFB_" .. key, 0)
                end
            end
            -- Forget the last decoded command while zero-flushed, so the first
            -- post-warmup command always decodes even if its value matches.
            _FFB.last_raw = nil
            return
        end

        -- Stream channels (skipped when no SOURCES are configured).
        if type(cfgF.SOURCES) == "table" and #cfgF.SOURCES > 0
           and (_FFB.mode ~= false or (not _FFB.exhausted and _FFB.Resolve())) then
            local raw
            if _FFB.mode == "output" then
                raw = _FFB.proxy:get()
            elseif _FFB.mode == "legacy" then
                raw = Legacy_Output_Value(_FFB.proxy, _FFB.source)
            else
                raw = Read_Data_Safe(_MemHandles["FFB"], _FFB.source, CFG.DATA_WIDTHS.FFB or 8)
            end
            if type(raw) == "number" then
                Set_Output(out, p_idx, "FFB_RAW", raw)

                -- The decoder and scale cannot change during a ROM session, so they are resolved
                -- once (cleared by _FFB.Reset).
                if _FFB.decoder == nil then
                    _FFB.decoder = _FFB.decoders[string.lower(tostring(cfgF.DECODE or "passthrough"))] or _FFB.decoders.passthrough
                    _FFB.scale = tonumber(cfgF.SCALE) or 255
                end

                -- Decode only when the command value changed: an identical raw value decodes to
                -- identical channel values, which Set_Output would drop.
                if raw ~= _FFB.last_raw then
                    _FFB.last_raw = raw
                    local scale = _FFB.scale
                    local set = _FFB.decoder(raw, scale)
                    if type(set) == "table" then
                        -- INVERT (per profile): some cabinets encode steering direction
                        -- the opposite way round to the family norm. Only the signed
                        -- CONSTANT channel flips; magnitudes stay positive.
                        if cfgF.INVERT == true and set.CONSTANT then
                            set.CONSTANT = -set.CONSTANT
                        end
                        for ch, val in pairs(set) do
                            if val > scale then val = scale elseif val < -scale then val = -scale end
                            Set_Output(out, p_idx, "FFB_" .. ch, val)
                        end
                    end
                end
            end
        end

        -- Semantic events (independent of the stream source).
        _FFB.Compute_Events(out, p_idx, current_time)
    end

    -- -------------------------------------------------------------------------
    -- Compute_Outputs()
    -- The frame notifier. Runs Frame_Logic and Forward_Native_Outputs under pcall, then flushes the
    -- relay payload.
    -- -------------------------------------------------------------------------
    local function Compute_Outputs()
        -- Stop as soon as shutdown has started or the hook has been released. Unhook_Frame may not
        -- have detached this notifier before the next frame, and cannot detach a legacy hook.
        if _IsShuttingDown or not _FrameHookActive then return end

        -- Frame_Logic needs CFG. A ROM with no profile has CFG == nil but may run in pass-through
        -- mode, so the engine is skipped and the forward and flush below still run.
        if CFG then
            -- pcall catches an error in Frame_Logic, so that a failing frame is logged and the
            -- notifier keeps running.
            local ok, err = pcall(Frame_Logic)
            if not ok then
                _ErrorCounts.frame = _ErrorCounts.frame + 1
                if _ErrorCounts.frame == 1 or _ErrorCounts.frame % 600 == 0 then
                    dbg_print("FRAME ERROR (" .. _ErrorCounts.frame .. " so far): " .. tostring(err))
                end
            end
        end

        -- Forward this ROM's native outputs (nothing happens when none are listed).
        local ok2, err2 = pcall(Forward_Native_Outputs)
        if not ok2 then
            _ErrorCounts.native = _ErrorCounts.native + 1
            if _ErrorCounts.native == 1 or _ErrorCounts.native % 600 == 0 then
                dbg_print("NATIVE FORWARD ERROR (" .. _ErrorCounts.native .. " so far): " .. tostring(err2))
            end
        end

        -- Send this frame's changes over the relay.
        flush_payload_to_relay()
    end

    -- -------------------------------------------------------------------------
    -- Unhook_Frame()
    -- Detaches the frame notifier. on_start fires on every reset, and replacing the subscription
    -- without unsubscribing would leave the old one firing until it is garbage collected, running
    -- the engine twice per frame. A legacy hook stays registered and is switched off by
    -- _FrameHookActive.
    -- -------------------------------------------------------------------------
    local function Unhook_Frame()
        _FrameHookActive = false
        local sub = exports.subscriptions.frame
        if sub then
            if type(sub) == "userdata" and sub.unsubscribe then
                pcall(function() sub:unsubscribe() end)
            end
            exports.subscriptions.frame = nil
        end
    end

    -- -------------------------------------------------------------------------
    -- Hook_Frame()
    -- Attaches Compute_Outputs as the frame notifier. Callers run Unhook_Frame first. On a build
    -- without emu.add_machine_frame_notifier, emu.register_frame_done is called once only, because
    -- each call adds another hook that cannot be removed.
    -- -------------------------------------------------------------------------
    local function Hook_Frame()
        _FrameHookActive = true
        if emu.add_machine_frame_notifier then
            exports.subscriptions.frame = emu.add_machine_frame_notifier(Compute_Outputs)
        elseif not _LegacyFrameHooked then
            emu.register_frame_done(Compute_Outputs, "frame")
            _LegacyFrameHooked = true
        end
    end

    -- -------------------------------------------------------------------------
    -- on_post_load()
    -- Save-state alignment. A loaded state restores RAM and the outputs the machine had at start,
    -- but not this engine's baselines and attotime anchors, so the first frames after a load would
    -- report false changes (an ammo jump as recoil, a credit jump as "inserted"). MSOP's outputs
    -- are not part of a state, so the session counters carry on from their values before the load.
    -- Steps:
    --   1. Re-seed the memory baselines from the restored RAM.
    --   2. Carry the game and player activity over from the last values sent, so that a load
    --      neither drops the status outputs to 0 nor counts a spawn.
    --   3. End the pulses in flight. Their attotime anchors belong to the timeline before the load
    --      and can block the timer comparisons for minutes.
    -- -------------------------------------------------------------------------
    local function on_post_load()
        -- A loaded state carries its own machine time, so a deadline measured from the last reset
        -- no longer applies to it. Once warmup has completed, or when the state is older than that
        -- reset, the deadline falls back to the delay measured from zero: only a state saved while
        -- its own game was starting is held.
        if CFG and _StartupDelay and (_WarmupFlushed or manager.machine.time < _StartupTime - _StartupDelay) then
            _StartupTime = _StartupDelay
        end
        if _IsShuttingDown or not CFG or not _WarmupFlushed then
            -- A state loaded before warmup completes is not tracked yet. The warmup flush handles
            -- it.
            return
        end
        local ok, err = pcall(function()
            Seed_Frame_Baselines()

            _PendingGlobalCreditDrops = 0

            local now = manager.machine.time
            local debounce_age = emu.attotime.from_msec((CFG.STATUS_DEBOUNCE_MS or 34) + 20)
            -- The last status values sent are carried over. Starting from 0 would drop the game
            -- and every player to inactive on each load.
            local game_restored = (_GlobalLastOutputs["GLOBAL_GAME_STATUS"] or 0) == 1
            _GameActiveTick = game_restored and (now - debounce_age) or _ZeroTime
            _GameDebounced = false
            _GameInactiveTick = _ZeroTime

            -- The output caches are kept. A load does not change MSOP's own outputs, so the
            -- cached values are still the values MAME and MESH hold.
            local out = manager.machine and manager.machine.output

            for i = 1, CFG.MAX_PLAYERS do
                local p = _Player[i]

                -- Carry the activity over so that Check 1 does not count a spawn for a player
                -- already in a session. The pre-aged ActiveTick carries an active player's Status
                -- output through the debounce window without a drop to 0. The player's own flag
                -- is used, because a profile may have no STATUS output to consult.
                local was_active = p.IsActive
                p.IsActive, p.WasActive = was_active, was_active
                p.ActiveTick = was_active and (now - debounce_age) or _ZeroTime
                p.Debounced = false
                p.IsFFBAllowed, p.WasFFBAllowed = was_active, was_active

                p.RecoilTick, p.ReloadTick, p.DamageTick, p.RumbleTick = _ZeroTime, _ZeroTime, _ZeroTime, _ZeroTime
                p.IsRecoilActive, p.IsReloadActive, p.IsDamageActive, p.IsRumbleActive = false, false, false, false
                p.PendingCreditDrops, p.SpawnsAwaitingCredit = 0, 0
            end

            -- The pulse timers were reset above, so nothing would end a pulse that was in flight.
            -- Every pulse is forced to 0.
            if out then
                End_Pulses(out)
                _FFB.Post_Load(out)
            end
            dbg_print("Save state loaded - baselines re-seeded")
        end)
        if not ok then dbg_print("POST-LOAD RESYNC ERROR: " .. tostring(err)) end
    end

    -- -------------------------------------------------------------------------
    -- on_machine_stop()
    -- The machine stop hook. Stops the engine, sends mame_stop, restores the patched memory and
    -- detaches the frame notifier.
    -- -------------------------------------------------------------------------
    local function on_machine_stop()
        _IsShuttingDown = true

        -- Drop the native forward records. Each can hold a device handle and an output proxy that
        -- belong to the machine being torn down. on_start rebuilds the list for every ROM.
        _NativeForwards = {}

        -- Send mame_stop while _ActiveMameStart still holds the game. A listener whose first
        -- connection is opened by this broadcast then receives mame_start before mame_stop.
        broadcast_native_event("mame_stop = 1\r\n")

        -- No game is running from here on. Clear it so that a later connect does not announce a
        -- stale ROM.
        _ActiveMameStart = nil

        -- A connect made by that broadcast queues this game's values, and no later frame flushes
        -- them. Discard them, and require a new warmup before any resync, so that nothing of this
        -- game is sent under the next game's mame_start.
        payload_buffer = {}
        changes_detected = false
        _WarmupFlushed = false

        -- Restore the patched memory values before shutdown.
        if CFG and CFG.SCREEN_FLASH then
            local conf = _MemConfig["SCREEN_FLASH"]
            if conf and manager and manager.machine then

                -- Resolve the memory handle for the patch.
                local mem_handle = nil
                if string.lower(conf.space) == "region" then
                    mem_handle = manager.machine.memory.regions[conf.tag]
                elseif manager.machine.devices[conf.tag] then
                    local dev = manager.machine.devices[conf.tag]
                    if dev.spaces[conf.space] then
                        mem_handle = dev.spaces[conf.space]
                    end
                end

                if mem_handle then
                    -- 1. Restore the global patch.
                    if CFG.SCREEN_FLASH_MEMORY_ADDRESS and CFG.SCREEN_FLASH_RESTORE_VALUE then
                        Write_Data_Safe(mem_handle, CFG.SCREEN_FLASH_MEMORY_ADDRESS, CFG.DATA_WIDTHS.SCREEN_FLASH or 8, CFG.SCREEN_FLASH_RESTORE_VALUE)
                    end

                    -- 2. Restore the per-player patches.
                    for i = 1, CFG.MAX_PLAYERS do
                        local p_cfg = _PlayerCFG[i]
                        if p_cfg and p_cfg.SCREEN_FLASH_MEMORY_ADDRESS and p_cfg.SCREEN_FLASH_RESTORE_VALUE then
                            Write_Data_Safe(mem_handle, p_cfg.SCREEN_FLASH_MEMORY_ADDRESS, CFG.DATA_WIDTHS.SCREEN_FLASH or 8, p_cfg.SCREEN_FLASH_RESTORE_VALUE)
                        end
                    end
                end
            end
        end

        Unhook_Frame()
    end

    -- =========================================================================
    -- the BOOT HOOK (on_start)
    -- Fires on every reset of the machine, soft resets included. Settles the relay mode, loads the
    -- ROM's profile, resets the engine state and attaches the frame notifier. A ROM with no profile
    -- can run in pass-through mode.
    -- =========================================================================
    local function on_start()
        if not manager or not manager.machine then return end
        dbg_print("on_start triggered. Current MAME Phase: " .. tostring(manager.machine.phase))

        -- A new machine is starting, so the previous machine's shutdown is over. The flag is
        -- cleared here for every ROM, with or without a profile: Compute_Outputs returns at once
        -- while it is set.
        _IsShuttingDown = false

        -- Probe the create capability first: resolve_relay_mode's capability gate needs the answer,
        -- and the first real write would give it too late. resolve_relay_mode then settles the
        -- relay decision once; later resets do nothing.
        pcall(function() Probe_Legacy_Set_Value(manager.machine.output) end)
        resolve_relay_mode()

        -- With the relay decision final, state once per session that MESH must be running. It is
        -- printed here so that it appears whichever gate turned the relay on.
        if _UseRelay then
            announce_relay_required()
            -- One-shot notice: the relay is required on this build, but -output network suggests
            -- the user expects MAME to broadcast MSOP's outputs.
            if _MisconfiguredOutputMode then
                osd_connection_status("misconfig",
                    "INCORRECT OUTPUT MODE DETECTED - this MAME version cannot broadcast"
                    .. " MSOP's state outputs on its own (MAME 0.289 and above), so they"
                    .. " need to be delivered through MESH. Set MAME output to \"none\" in"
                    .. " mame.ini for the recommended setup. Using \"network\" in MAME"
                    .. " 0.289+ means external hooker programs may not receive MSOP's"
                    .. " state outputs (this output mode only delivers MSOP's outputs"
                    .. " natively in MAME 0.200 - 0.288).",
                    "MSOP: INCORRECT OUTPUT MODE DETECTED\n"
                    .. "This MAME version cannot broadcast MSOP's state outputs on its"
                    .. " own (MAME 0.289 and above), so they need to be delivered through"
                    .. " MESH. Set MAME output to \"none\" in mame.ini for the recommended"
                    .. " setup. Using \"network\" in MAME 0.289+ means external hooker"
                    .. " programs may not receive MSOP's state outputs (this output mode"
                    .. " only delivers MSOP's outputs natively in MAME 0.200 - 0.288).")
            elseif _WindowsOutputWithRelay then
                osd_connection_status("windows_output",
                    "MAME output is set to \"windows\" on a MAME version that cannot"
                    .. " broadcast MSOP's state outputs on its own (MAME 0.289 and above)."
                    .. " This works with MESH: MSOP's outputs are delivered through MESH"
                    .. " and the game's native outputs are sent by MAME. Programs that"
                    .. " only read MAME's Windows messages, such as MAMEhooker, receive"
                    .. " the native outputs only. To send them MSOP's outputs as well,"
                    .. " set MAME output to \"none\" in mame.ini and enable \"Serve Windows"
                    .. " Output\" in MESH.",
                    "MSOP: MAME OUTPUT IS SET TO WINDOWS\n"
                    .. "This works with MESH. Programs that only read MAME's Windows"
                    .. " messages, such as MAMEhooker, receive the game's native outputs"
                    .. " only. To send them MSOP's outputs as well, set MAME output to"
                    .. " \"none\" in mame.ini and enable \"Serve Windows Output\" in MESH.")
            end
        end

        local rom_name = manager.machine.system.name

        -- Warmup runs again for each ROM load and each reset. It is cleared before the dial below,
        -- because connect_socket resyncs whatever is marked as warmed up and the caches still
        -- describe the previous game; the global output cache is cleared with it. A reset discards
        -- the pulse timers, so a pulse in flight is ended first.
        if CFG and _WarmupFlushed and manager.machine.output then
            pcall(End_Pulses, manager.machine.output)
        end
        _WarmupFlushed = false
        _GlobalLastOutputs = {}
        _ErrorCounts.frame, _ErrorCounts.native = 0, 0

        -- Re-arm the retry state at every ROM start, when a dial's stall is hidden by loading.
        -- ever_connected is not reset: once MESH has connected this session, a failure here takes
        -- the single warm dial and not a new cold sequence (see RETRY POLICY).
        next_retry_at = 0
        relay_given_up = false
        cold_fail_count = 0

        -- Remember the running game so that connect_socket can announce it on every connect, then
        -- send it now. Opening the relay here is the ROM-start dial. With _UseRelay false MAME
        -- sends mame_start itself, so nothing is dialled.
        _ActiveMameStart = "mame_start = " .. rom_name .. "\r\n"
        if _UseRelay then
            if connected and sock then
                -- Already connected (for example after a ROM switch): announce the new game now.
                -- The change filter is cleared with it, so that every value of the new game is sent
                -- after its mame_start, including one equal to the previous game's last value.
                if not relay_write(_ActiveMameStart) then teardown_connection() end
                last_state = {}
            elseif relay_retry_due() then
                connect_socket()  -- on success, connect_socket sends _ActiveMameStart itself
            end
        end

        -- The profile's on-screen switch, read from the database because CFG is set further
        -- down: the ROM's own value, or the '_default' value when the ROM does not set one.
        local profile_osd = nil
        if type(db) == "table" then
            if type(db[rom_name]) == "table" then profile_osd = db[rom_name].ENABLE_OSD end
            if profile_osd == nil and type(db["_default"]) == "table" then profile_osd = db["_default"].ENABLE_OSD end
        end
        profile_osd = (profile_osd == true)

        dbg_print("Checking ROM [" .. rom_name .. "] against database")
        dbg_osd("Checking ROM [" .. rom_name .. "] against database", profile_osd)

        -- Every profile is layered over the '_default' template. A database without one cannot
        -- run a profile, so the ROM is then handled as a game without a profile.
        local has_profile = db and type(db) == "table" and db[rom_name]
        if has_profile and type(db["_default"]) ~= "table" then
            dbg_print("DATABASE ERROR - database.lua has no '_default' profile; ROM [" .. rom_name
                      .. "] is handled as a game without a profile")
            has_profile = false
        end

        if has_profile then

            -- Layer the ROM's profile over the '_default' template.
            local merged = deep_merge(db["_default"], db[rom_name])

            -- A profile with ENABLE_ROM = false is not run.
            if merged.ENABLE_ROM == false then
                dbg_print("DISABLED - ROM [" .. rom_name .. "] disabled via ENABLE_ROM flag")
                dbg_osd("DISABLED - ROM " .. rom_name .. " disabled by user", profile_osd)
                CFG = nil

                Unhook_Frame()
                return
            end

            dbg_print("ENABLED - ROM [" .. rom_name .. "] found in database")
            dbg_osd("ENABLED - ROM [" .. rom_name .. "]", profile_osd)

            CFG = normalize_variables(merged)

            -- Convert the JSON hex strings to numbers.
            convert_hex_strings_to_numbers(CFG)

            -- The numeric ROM ID for the MSOP_ROM_ID output: the profile's LUA_ROM_ID if present,
            -- otherwise the FNV-1a hash of the ROM short name.
            _RomIdNum = tonumber(CFG.LUA_ROM_ID) or fnv1a_31(rom_name)

            -- Reset the engine state.
            _HasCoinedUp = not CFG.CREDITS

            _LastGlobalCredits = 0
            _GlobalCreditsInserted = 0
            _PendingGlobalCreditDrops = 0

            -- Reset the memory bindings and the output names.
            _MemConfig = {}
            _MemHandles = {}
            _HardwareBound = false
            _OutputNames = {}
            _SharedOutputs = false
            _GlobalOutputs = {}

            -- Reset the output proxy cache on every on_start. Each cached proxy belongs to the
            -- machine that was running when it was resolved, and a new ROM destroys that machine.
            -- Output names are reused across games, so a stale entry would be hit again.
            _ProxyCache = {}
            _FFB.Reset() -- same staleness rule: the FFB source/proxy belongs to the old machine

            -- Pass-through mode sets this to true. It is cleared here so that a ROM with a profile
            -- caches a missing proxy at once on a build that has output proxies.
            _RetryMissingProxies = false

            -- Resolve this ROM's native output forward list. With device.outputs the running
            -- machine supplies it. Otherwise native_outputs_by_rom.lua's entry for this ROM is used
            -- (a generated file; never edit it by hand). ADDITIONAL_OUTPUT_FORWARDS is added in
            -- both cases, and entries are deduplicated by wire name.
            _NativeForwards = {}
            -- Stand down while MAME's own -output network server is running: it already broadcasts
            -- every output in MAME's output system on port 8000, and forwarding would deliver each
            -- one twice to a program reading both ports. MSOP's own outputs still go over the
            -- relay.
            if _MameServesNetwork then
                dbg_print("Native forwards skipped - MAME's own -output network server on "
                          .. "8000 is already broadcasting this ROM's native outputs")
            else
                local seen = {}
                local function add_name(name)
                    if type(name) == "string" and not seen[name] then
                        seen[name] = true
                        _NativeForwards[#_NativeForwards + 1] = { name = name, wire = name }
                    end
                end

                local enumerated = Enumerate_Native_Outputs()
                if enumerated then
                    for _, rec in ipairs(enumerated) do
                        if not seen[rec.wire] then
                            seen[rec.wire] = true
                            _NativeForwards[#_NativeForwards + 1] = rec
                        end
                    end
                else
                    for _, name in ipairs(driver_db[rom_name] or {}) do add_name(name) end
                end

                for _, name in ipairs(CFG.ADDITIONAL_OUTPUT_FORWARDS or {}) do add_name(name) end
            end

            -- Convert the profile's durations and intervals to attotime values.
            _RecoilDuration = emu.attotime.from_msec(CFG.RECOIL_DURATION_MS or 40)
            _RecoilAltDuration = emu.attotime.from_msec(CFG.RECOIL_ALT_DURATION_MS or 40)
            _RecoilGrenadeDuration = emu.attotime.from_msec(CFG.RECOIL_GRENADE_DURATION_MS or 80)
            _MinRecoilInterval = emu.attotime.from_msec(CFG.MIN_RECOIL_INTERVAL_MS or 100)
            _RecoilHoldInterval = CFG.RECOIL_HOLD_MS and emu.attotime.from_msec(CFG.RECOIL_HOLD_MS) or _MinRecoilInterval
            -- An interval at or below the recoil duration is raised to the duration plus 20 ms.
            if _MinRecoilInterval <= _RecoilDuration then _MinRecoilInterval = emu.attotime.from_msec((CFG.RECOIL_DURATION_MS or 40) + 20) end
            if _RecoilHoldInterval <= _RecoilDuration then _RecoilHoldInterval = emu.attotime.from_msec((CFG.RECOIL_DURATION_MS or 40) + 20) end
            -- Optional recoil safety delay (off by default, absent = off): widens the pulse
            -- interval (MIN_RECOIL_INTERVAL_MS) and the hold interval (RECOIL_HOLD_MS) to at least
            -- RECOIL_SAFETY_DELAY_MS. Pulse lengths (RECOIL_*_DURATION_MS) are never changed.
            if CFG.ENABLE_RECOIL_SAFETY_DELAY == true then
                local safety_delay = emu.attotime.from_msec(tonumber(CFG.RECOIL_SAFETY_DELAY_MS) or 100)
                if _MinRecoilInterval < safety_delay then _MinRecoilInterval = safety_delay end
                if _RecoilHoldInterval < safety_delay then _RecoilHoldInterval = safety_delay end
            end
            _ReloadDuration = emu.attotime.from_msec(CFG.RELOAD_DURATION_MS or 40)
            _DamageDuration = emu.attotime.from_msec(CFG.DAMAGE_DURATION_MS or 250)
            _RumbleDuration = emu.attotime.from_msec(CFG.RUMBLE_DURATION_MS or CFG.DAMAGE_DURATION_MS or 250)
            -- The startup delay runs from this start or reset. Machine time is not reset by a soft
            -- reset, so a deadline measured from zero would already have passed.
            _StartupDelay = emu.attotime.from_msec(CFG.STARTUP_DELAY_MS or 5000)
            _StartupTime = manager.machine.time + _StartupDelay
            _ZeroTime = emu.attotime.from_seconds(0)
            -- CREDITS_CLEAR_TIMEOUT_SEC is optional. Its constant stays nil when unset, and
            -- Frame_Logic then skips the check.
            _StatusDebounce = emu.attotime.from_msec(CFG.STATUS_DEBOUNCE_MS or 34)
            _CreditsClearTimeout = CFG.CREDITS_CLEAR_TIMEOUT_SEC and emu.attotime.from_seconds(CFG.CREDITS_CLEAR_TIMEOUT_SEC) or nil

            _GameActiveTick = _ZeroTime
            _GameInactiveTick = _ZeroTime

            -- Reset every player's state so that nothing carries over from the previous game.
            for i = 1, 4 do
                _Player[i] = {
                    LastOutputs={}, LastAmmo=0, LastAmmoAlt=0, LastAmmoGrenade=0, LastLife=0, LastLifeAlt=0, LastDmgMem=0, LastCredits=0, LastReloadVal=0,
                    RecoilTick=_ZeroTime, ReloadTick=_ZeroTime, DamageTick=_ZeroTime, RumbleTick=_ZeroTime,
                    CurrentRecoilDuration=_RecoilDuration, LastRecoilVal=0, LastDamageVal=0, LastRumbleEventVal=0,
                    ShotCountPrimary=0, ShotCountAlt=0, ShotCountGrenade=0, DamageCount=0, LifeLostCount=0, CreditsInserted=0, CreditsConsumed=0, PendingCreditDrops=0, SpawnsAwaitingCredit=0,
                    IsActive=false, WasActive=false, ActiveTick=_ZeroTime, Debounced=false, PrimaryFires=true, AlternateFires=true,
                    IsRecoilActive=false, IsReloadActive=false, IsDamageActive=false, IsRumbleActive=false,
                    IsFFBAllowed=false, WasFFBAllowed=false
                }
            end

            Resolve_Addresses_And_Strings()

            -- Send the identity outputs now, ahead of the startup delay. Over the relay they are
            -- queued behind this game's mame_start and leave with the first frame; a relay that
            -- connects later receives them from Resync_Relay_State.
            pcall(Send_Identity_Outputs, manager.machine.output)

            -- Attach the frame notifier. The previous subscription is detached first, because
            -- on_start fires on every reset and a second notifier would run the engine twice per
            -- frame.
            Unhook_Frame()
            Hook_Frame()
        else
            CFG = nil

            -- Pass-through mode. The ROM has no profile, but its native outputs exist, and with
            -- -output none or console MAME does not broadcast them, so they are forwarded over the
            -- relay. With device.outputs the machine's real outputs are used. Without it the
            -- scraped files below are used, and a ROM with no entry forwards nothing.
            _ProxyCache = {}
            _FFB.Reset() -- an unsupported ROM never computes FFB, but its predecessor's proxy is stale
            _RetryMissingProxies = true
            _NativeForwards = {}
            do
                local seen = {}
                local via

                local enumerated = Enumerate_Native_Outputs()
                if enumerated then
                    for _, rec in ipairs(enumerated) do
                        if not seen[rec.wire] then
                            seen[rec.wire] = true
                            _NativeForwards[#_NativeForwards + 1] = rec
                        end
                    end
                    via = "enumerated from the running machine"
                else
                    -- The ROM's own scraped entry is used first; it can carry layout-derived names
                    -- the driver source does not declare. When the ROM has no entry, the driver's
                    -- entry is used, keyed by source file basename.
                    local list = driver_db[rom_name]
                    via = "rom"
                    if not list or #list == 0 then
                        local src = Driver_Source_Key()
                        if src then
                            list = mame_driver_db[src]
                            via = "driver:" .. src
                        end
                    end
                    for _, name in ipairs(list or {}) do
                        if type(name) == "string" and not seen[name] then
                            seen[name] = true
                            _NativeForwards[#_NativeForwards + 1] = { name = name, wire = name }
                        end
                    end
                end

                if #_NativeForwards > 0 then
                    dbg_print("Pass-through source: " .. via)
                end
            end

            -- Stand down when MAME's own network output server is running (-output network): it
            -- already broadcasts every native output on port 8000, and forwarding would deliver
            -- each one twice to a program reading both ports. The test is the -output mode, not the
            -- relay port.
            if _MameServesNetwork then
                _NativeForwards = {}
                dbg_print("PASS-THROUGH skipped - MAME's own -output network server on 8000 is "
                          .. "already broadcasting this ROM's native outputs")
            end

            Unhook_Frame()
            if _UseRelay and #_NativeForwards > 0 then
                dbg_print("PASS-THROUGH - ROM [" .. rom_name .. "] not in database; forwarding "
                          .. #_NativeForwards .. " native output(s) over the relay")
                dbg_osd("MSOP pass-through: " .. #_NativeForwards .. " native outputs", profile_osd)
                Hook_Frame()
            else
                dbg_print("DISABLED - ROM [" .. rom_name .. "] not supported in database"
                          .. (_UseRelay and " (no scraped native outputs to forward)" or ""))
                dbg_osd("DISABLED - ROM " .. rom_name .. " not supported", profile_osd)
                -- Nothing to deliver. The ROM-start dial above already gave a running MESH its
                -- mame_start. If it did not connect, retries stop for this ROM, because no payload
                -- justifies another stall. The usual cues re-arm dialling: the next ROM start, a
                -- soft reset or an unpause.
                if not connected then
                    relay_given_up = true
                    dbg_print("Relay: no MSOP payload exists for this ROM - no further dials this session")
                end
            end
        end
    end

    -- =========================================================================
    -- COMPATIBILITY API REGISTRATION
    -- =========================================================================

    -- The hooks are bound once per MAME session.
    if not stateoutput.api_hooks_bound then
        dbg_print("Binding API Hooks...")

        -- 1. Pause and resume notifiers, for every game.
        if emu.add_machine_pause_notifier then
            exports.subscriptions.pause = emu.add_machine_pause_notifier(function()
                broadcast_native_event("pause = 1\r\n")
            end)
        end

        if emu.add_machine_resume_notifier then
            exports.subscriptions.resume = emu.add_machine_resume_notifier(function()
                -- Re-arm cue: an unpause grants one immediate dial, through the broadcast below.
                -- The cold counter is capped at its final stage and not reset, so a dial that fails
                -- after dialling had stopped stops it again without repeating the warnings. Nothing
                -- changes while connected.
                if not connected then
                    relay_given_up = false
                    next_retry_at = 0
                    if cold_fail_count > 2 then cold_fail_count = 2 end
                end
                broadcast_native_event("pause = 0\r\n")
            end)
        end

        -- 2. Reset notifier: load the ROM's profile and attach the frame notifier.
        if emu.add_machine_reset_notifier then
            dbg_print("Hooked on_start to machine_reset (RESET)")
            exports.subscriptions.reset = emu.add_machine_reset_notifier(on_start)
        else
            emu.register_start(on_start)
        end

        -- 3. Stop notifier: clean up when the machine stops.
        if emu.add_machine_stop_notifier then
            exports.subscriptions.stop = emu.add_machine_stop_notifier(on_machine_stop)
        elseif emu.register_stop then
            emu.register_stop(on_machine_stop)
        end

        -- 4. Post-load notifier: realign the Lua-side state with a loaded save state.
        if emu.add_machine_post_load_notifier then
            dbg_print("Hooked on_post_load to post_load notifier (save-state resync)")
            exports.subscriptions.post_load = emu.add_machine_post_load_notifier(on_post_load)
        elseif emu.register_postload then
            dbg_print("Hooked on_post_load to register_postload (save-state resync, legacy)")
            emu.register_postload(on_post_load)
        end

        stateoutput.api_hooks_bound = true
    end
end

return exports