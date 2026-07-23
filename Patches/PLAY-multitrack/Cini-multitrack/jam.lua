-- organelle-mother.lua
-- Multitrack jam for Organelle PLAY patch
-- Lean architecture: 1 global live/pattern engine + 4 pure sequencer tracks

local OGUI = require("lib/ogui").OGUI
local EncoderAccel = require("lib/ogui").EncoderAccel
local Track = require("lib/organelle_track").Track
local Sequencer = require("lib/sequencer").Sequencer
local Presets = require("lib/presets").Presets
MidiExport = require("lib/midi_export").MidiExport

-- =====================================================================
-- STATE
-- =====================================================================

local ogui = nil
local encoder_accel = nil
local jam_ctx = nil
local presets = nil

local engine = nil
local seqs = {}
local selected_track_index = 1
local track_levels = {1, 1, 1, 1}
track_types = track_types or {"empty", "empty", "empty", "empty"}
knob_track_enabled = knob_track_enabled or {false, false, false, false}
local master_loop_length = 0
local history_track_index = nil

local shift_pressed = false
local aux_menu_opened = false
local aux_combo_used = false
local notes_held = 0
local dirty_knobs = {}

-- PLAY synths can be heavier than CZ. Knob changes are queued and
-- flushed at control-rate so OLED redraws and synth parameter broadcasts
-- do not steal audio time while loops are running.
-- These are intentionally global, not local: Organelle's Lua 5.1 build
-- has a hard 200-local limit in the main chunk, and jam.lua is already
-- close to that limit.
knob_output_pending = knob_output_pending or {}
knob_output_last_sent = knob_output_last_sent or {}
knob_output_next_tc = knob_output_next_tc or 0
knob_output_interval_ticks = knob_output_interval_ticks or 18
knob_ramps = knob_ramps or {}
mixer_level_dirty = mixer_level_dirty or false
mixer_dirty_channels = mixer_dirty_channels or {false, false, false, false}
local last_display_tc = 0
local last_bpm = -1
local initial_draw_needed = true

local current_view = "main" -- "main" | "mixer"
local current_aux_page = 1 -- 1=main menu, 2=tools, 3=punch FX
local punchfx_menu_latched = false
local ignore_next_shift_release = false
local confirm_action = nil
local preset_zero_selected = true

local metro_mode = 1 -- 1=off 2=Click 3=Click! 4=Beep 5=Beep! 6=3/4 7=4/4 8=5/4
local velocity_mode = 3 -- 1=pp 2=p 3=Velocity 4=f 5=ff

-- Playlist builder state. Kept global deliberately to avoid Lua 5.1
-- main-chunk local-variable limits on Organelle.
playlist_dialog_active = false
playlist_entries = {}
playlist_select_index = 1
playlist_selection_touched = false
playlist_loaded = false
playlist_loading_temp = false
playlist_ignore_next_aux_release = false
playlist_aux_down = false
playlist_aux_down_tc = 0
playlist_aux_hold_stage = 0
playlist_enc_down = false
playlist_enc_down_tc = 0
playlist_enc_hold_stage = 0
playlist_enc_button_value = nil

-- Quantized Punch-In FX. Page 3 is latched open for two-handed performance.
-- Multiple FX can run in parallel. Each table is keyed by FX id.
active_punchfx_until_tc = {}
pending_punchfx = {}
latched_punchfx = {}
local punchfx_names = {
    "Octaves",
    "Freeze",
    "Old Tape",
    "Retrigger",
    "Distortion",
    "Stutter",
    "Warp",
    "Reverse",
    "Universe",
    "PingPong 1/8"
}

-- Footswitch detection
local fs_is_down = false
local fs_down_tc = 0
local fs_press_state = nil
local fs_hold_preview = nil -- nil | "ARMED" | "OVERDUB" | "UNDO" | "REDO"

-- Generic AUX-menu hold tracking
local menu_hold = nil
local pending_bounce_target = nil
local pending_bounce_source = nil
-- menu_hold = {
--   note = n,
--   kind = "record" | "savecopy" | "click" | "trackclear",
--   start_tc = tc,
--   stage = 0 | 1 | 2,
--   track_index = optional
-- }

-- Transient modal timeout
local transient_modal_until_tc = nil

-- Shift function keys (black keys starting from C#)
local shift_keys = {61, 63, 66, 68, 70, 73, 75, 78, 80, 82}
local pattern_select_keys = {60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83}

local knob_names = {"Swell", "Tone", "Shimmer", "Space"}
local knob_configs = {
    {"%d%%", function(v) return math.floor(v * 100) end, knob_names[1]},
    {"%d%%", function(v) return math.floor(v * 100) end, knob_names[2]},
    {"%d%%", function(v) return math.floor(v * 100) end, knob_names[3]},
    {"%d%%", function(v) return math.floor(v * 100) end, knob_names[4]},
}

-- Cached UI state for low-overhead redraw
local ui_dirty_right = true
local ui_dirty_status = true
local ui_last_progress_pixels = -1
local ui_last_track_mask = -1
local ui_last_selected_track = -1
local ui_last_rec_blink_visible = nil
ui_dirty_progress = ui_dirty_progress or false

-- Right-side visual layout
local RIGHT_X = 88
local TRACK_X = 100
local TRACK_W = 12
local PROGRESS_X = 116
local PROGRESS_W = 6
local PANEL_Y = 11
local PANEL_H = 44
local MAIN_LEFT_W = RIGHT_X

local CAPTURE_USB_ROOT = "/usbdrive"
local CAPTURE_SD_ROOT = "/sdcard"
local CAPTURE_SUBDIR = "Capture"
local capture_state = "OFF"
local capture_path = nil
local capture_save_root = CAPTURE_SD_ROOT
local pending_capture_saved_root = nil

-- =====================================================================
-- HELPERS
-- =====================================================================

local function selectedSeq()
    return seqs[selected_track_index]
end

local function secondsToTicks(jam, seconds)
    return math.max(1, math.floor((jam.tpb * jam.bpm * seconds / 60) + 0.5))
end

local function getFootActionTicks(jam)
    return secondsToTicks(jam, 0.60)
end

local function getFootUndoTicks(jam)
    return secondsToTicks(jam, 1.20)
end

local function getAuxUndoTicks(jam)
    return secondsToTicks(jam, 0.70)
end

function getAuxSaveCopyTicks(jam)
    return secondsToTicks(jam, 0.85)
end

function getPlaylistHoldTicks(jam)
    return secondsToTicks(jam, 0.85)
end

function getPlaylistEncoderUndoTicks(jam)
    return secondsToTicks(jam, 0.65)
end

function getMidiExportHoldTicks(jam)
    return secondsToTicks(jam, 1.00)
end

function getPunchFxLatchHoldTicks(jam)
    return secondsToTicks(jam, 0.30)
end

local function getAuxClickOffTicks(jam)
    return secondsToTicks(jam, 0.50)
end

local function getTrackClearHoldTicks(jam)
    return secondsToTicks(jam, 1.00)
end

local function getTrack1BounceAllHoldTicks(jam)
    return secondsToTicks(jam, 1.00)
end

local function getTrack1ClearHoldTicks(jam)
    return secondsToTicks(jam, 2.00)
end

local function getTransientModalTicks(jam)
    return secondsToTicks(jam, 1.00)
end

local function clearTransientModal()
    transient_modal_until_tc = nil
end

local function displayTransientModal(jam, text)
    clearTransientModal()
    ogui:fillArea(10, 13, 108, 38, OGUI.COLOR_BLACK)
    ogui:box(10, 13, 108, 38, OGUI.COLOR_WHITE)
    ogui:println(14, 25, OGUI.SIZE_16, OGUI.COLOR_WHITE, text)
    ogui:flip()
    transient_modal_until_tc = jam.tc + getTransientModalTicks(jam)
end

local function displayTransientModalTwoLines(jam, line1, line2)
    clearTransientModal()
    ogui:fillArea(10, 13, 108, 48, OGUI.COLOR_BLACK)
    ogui:box(10, 13, 108, 48, OGUI.COLOR_WHITE)
    ogui:println(14, 19, OGUI.SIZE_16, OGUI.COLOR_WHITE, line1)
    ogui:println(14, 40, OGUI.SIZE_16, OGUI.COLOR_WHITE, line2)
    ogui:flip()
    transient_modal_until_tc = jam.tc + getTransientModalTicks(jam)
end

local function displayTimedTransientModalTwoLines(jam, line1, line2, seconds)
    clearTransientModal()
    ogui:fillArea(10, 13, 108, 48, OGUI.COLOR_BLACK)
    ogui:box(10, 13, 108, 48, OGUI.COLOR_WHITE)
    ogui:println(14, 19, OGUI.SIZE_16, OGUI.COLOR_WHITE, line1)
    ogui:println(14, 40, OGUI.SIZE_16, OGUI.COLOR_WHITE, line2)
    ogui:flip()
    transient_modal_until_tc = jam.tc + secondsToTicks(jam, seconds or 1.00)
end

local function displayModal(text)
    ogui:fillArea(10, 13, 108, 38, OGUI.COLOR_BLACK)
    ogui:box(10, 13, 108, 38, OGUI.COLOR_WHITE)
    ogui:println(14, 25, OGUI.SIZE_16, OGUI.COLOR_WHITE, text)
    ogui:flip()
end

local function displayWideModal(text)
    ogui:fillArea(2, 10, 124, 44, OGUI.COLOR_BLACK)
    ogui:box(2, 10, 124, 44, OGUI.COLOR_WHITE)
    ogui:println(6, 24, OGUI.SIZE_16, OGUI.COLOR_WHITE, text)
    ogui:flip()
end

local function displayModalTwoLines(line1, line2)
    ogui:fillArea(10, 13, 108, 48, OGUI.COLOR_BLACK)
    ogui:box(10, 13, 108, 48, OGUI.COLOR_WHITE)
    ogui:println(14, 19, OGUI.SIZE_16, OGUI.COLOR_WHITE, line1)
    ogui:println(14, 40, OGUI.SIZE_16, OGUI.COLOR_WHITE, line2)
    ogui:flip()
end

local function clearConfirmAction()
    confirm_action = nil
    pending_bounce_target = nil
    pending_bounce_source = nil
end

local function clearMenuHold()
    menu_hold = nil
end

local function metroModeName(mode)
    if mode == 1 then return "Click off" end
    if mode == 2 then return "Click" end
    if mode == 3 then return "Click!" end
    if mode == 4 then return "Beep" end
    if mode == 5 then return "Beep!" end
    if mode == 6 then return "3/4" end
    if mode == 7 then return "4/4" end
    if mode == 8 then return "5/4" end
    return "Click off"
end

function metroBeatsPerBar(mode)
    mode = mode or metro_mode
    if mode == 6 then return 3 end
    if mode == 8 then return 5 end
    return 4
end

function metroAccentFlag(jam)
    local tpb = (jam and jam.tpb) or 360
    local tc = (jam and jam.tc) or 0
    local beats = metroBeatsPerBar(metro_mode)
    local beat_index = (math.floor(tc / math.max(1, tpb)) % beats) + 1
    return beat_index == 1 and 1 or 0
end

local function velocityModeName(mode)
    if mode == 1 then return "pp" end
    if mode == 2 then return "p" end
    if mode == 3 then return "Velocity" end
    if mode == 4 then return "f" end
    if mode == 5 then return "ff" end
    return "Velocity"
end



local function punchFxName(id)
    return punchfx_names[id] or "Off"
end

local function punchFxTimingsMs()
    local bpm = (jam_ctx and jam_ctx.bpm) or 120
    if bpm <= 0 then bpm = 120 end

    local beat_ms = 60000 / bpm
    local bar_ms = beat_ms * metroBeatsPerBar(metro_mode)
    return {
        -- Octaves: one punch is one bar; audio stepping is fixed at 1/16 in punchfx~.
        lpf = math.floor(bar_ms + 0.5),
        hpf = math.floor(bar_ms + 0.5),
        oldtape = math.floor((beat_ms / 3) + 0.5),
        retrig_fast = math.floor((bar_ms / 16) + 0.5),
        stutter = math.floor((beat_ms / 8) + 0.5),
        echo_eighth = math.floor((beat_ms / 2) + 0.5),
    }
end

function punchFxBarTicks(jam)
    local tpb = (jam and jam.tpb) or 360
    return math.max(1, math.floor((tpb * metroBeatsPerBar(metro_mode)) + 0.5))
end

function punchFxTicksPerPress(id, jam)
    local bar_ticks = punchFxBarTicks(jam)
    if id == 1 then return bar_ticks end
    if id == 4 then return math.max(1, math.floor((bar_ticks / 4) + 0.5)) end
    if id == 6 then return math.max(1, math.floor((bar_ticks / 2) + 0.5)) end
    return bar_ticks
end

function punchFxNextBeatTc(jam)
    local tpb = (jam and jam.tpb) or 360
    local tc = (jam and jam.tc) or 0
    local grid_ticks = math.max(1, math.floor(tpb + 0.5))
    local remainder = tc % grid_ticks
    if remainder == 0 then return tc end
    return tc + (grid_ticks - remainder)
end

function punchFxNextBarTc(jam)
    local tpb = (jam and jam.tpb) or 360
    local tc = (jam and jam.tc) or 0
    local grid_ticks = math.max(1, math.floor((tpb * metroBeatsPerBar(metro_mode)) + 0.5))
    local remainder = tc % grid_ticks
    if remainder == 0 then return tc + grid_ticks end
    return tc + (grid_ticks - remainder)
end

function punchFxSyncedFreezeTicks(jam)
    local tc = (jam and jam.tc) or 0
    local bar_ticks = punchFxBarTicks(jam)
    local start_tc = punchFxNextBeatTc(jam)
    return math.max(1, (start_tc + bar_ticks) - tc)
end

function punchFxTicksToMs(ticks)
    local bpm = (jam_ctx and jam_ctx.bpm) or 120
    local tpb = (jam_ctx and jam_ctx.tpb) or 360
    if bpm <= 0 then bpm = 120 end
    if tpb <= 0 then tpb = 360 end
    return math.max(1, math.floor((ticks * 60000 / (bpm * tpb)) + 0.5))
end

function punchFxDurationLabelFor(id, ticks, jam)
    local bar_ticks = punchFxBarTicks(jam or jam_ctx)
    if id == 4 then
        local q = math.max(1, math.floor(((ticks * 4) / bar_ticks) + 0.5))
        if q == 4 then return "1 bar" end
        if q % 4 == 0 then return tostring(q / 4) .. " bars" end
        return tostring(q) .. "/4 bar"
    end
    if id == 6 then
        local h = math.max(1, math.floor(((ticks * 2) / bar_ticks) + 0.5))
        if h == 1 then return "0.5 bar" end
        if h % 2 == 0 then
            local b = h / 2
            if b == 1 then return "1 bar" end
            return tostring(b) .. " bars"
        end
        return string.format("%.1f bars", h / 2)
    end
    local bars = math.max(1, math.floor((ticks / bar_ticks) + 0.5))
    if bars == 1 then return "1 bar" end
    return tostring(bars) .. " bars"
end

function displayPunchFxMessage(id, ticks, jam)
    displayModalTwoLines(punchFxName(id), punchFxDurationLabelFor(id, ticks, jam))
end

function punchFxAnyActive(jam)
    local tc = (jam and jam.tc) or (jam_ctx and jam_ctx.tc) or 0
    for id = 1, #punchfx_names do
        if active_punchfx_until_tc[id] and active_punchfx_until_tc[id] > tc then
            return true
        end
    end
    return false
end

local function sendPunchFxDry(on)
    if jam_ctx then
        local t = punchFxTimingsMs()
        jam_ctx.msgout("punchfx", 0, on and 1 or 0, t.lpf, t.hpf, t.oldtape, t.retrig_fast, t.stutter, t.echo_eighth)
    end
end

local function sendPunchFx(id, on, duration_ticks)
    if jam_ctx then
        local t = punchFxTimingsMs()
        local dur = duration_ticks or punchFxBarTicks(jam_ctx)
        jam_ctx.msgout("punchfx", id or 0, on and 1 or 0, t.lpf, t.hpf, t.oldtape, t.retrig_fast, t.stutter, t.echo_eighth, punchFxTicksToMs(dur))
    end
end

function clearPendingPunchFx(note)
    if not note then
        pending_punchfx = {}
        return
    end
    for id = 1, #punchfx_names do
        if pending_punchfx[id] and pending_punchfx[id].note == note then
            pending_punchfx[id] = nil
        end
    end
end

local function clearPunchFx()
    pending_punchfx = {}
    for id = 1, #punchfx_names do
        if active_punchfx_until_tc[id] or latched_punchfx[id] then
            sendPunchFx(id, false)
            active_punchfx_until_tc[id] = nil
            latched_punchfx[id] = nil
        end
    end
    sendPunchFxDry(true)
end

function refreshPunchFxMenuIfOpen()
    if current_aux_page == 3 and displayShiftMenu then
        displayShiftMenu()
    end
end

function setLatchedPunchFx(id, on, jam)
    if on then
        latched_punchfx[id] = true
        active_punchfx_until_tc[id] = nil
        pending_punchfx[id] = nil
        sendPunchFx(id, true, punchFxTicksPerPress(id, jam or jam_ctx))
        sendPunchFxDry(false)
    else
        if latched_punchfx[id] or active_punchfx_until_tc[id] then
            sendPunchFx(id, false)
        end
        latched_punchfx[id] = nil
        active_punchfx_until_tc[id] = nil
        pending_punchfx[id] = nil
        sendPunchFxDry(not punchFxAnyActive(jam or jam_ctx))
    end
    clearTransientModal()
    refreshPunchFxMenuIfOpen()
end

function activatePunchFxNow(id, note, duration_ticks, jam)
    duration_ticks = duration_ticks or punchFxTicksPerPress(id, jam or jam_ctx)
    local tc = ((jam and jam.tc) or (jam_ctx and jam_ctx.tc) or 0)
    active_punchfx_until_tc[id] = tc + duration_ticks
    sendPunchFx(id, true, duration_ticks)
    sendPunchFxDry(false)
    displayPunchFxMessage(id, duration_ticks, jam)
end

function activatePunchFx(id, note, jam)
    if id == 2 then
        pending_punchfx[id] = nil
        local tc = (jam and jam.tc) or (jam_ctx and jam_ctx.tc) or 0
        local add_ticks = punchFxBarTicks(jam or jam_ctx)

        if active_punchfx_until_tc[id] and active_punchfx_until_tc[id] > tc then
            active_punchfx_until_tc[id] = active_punchfx_until_tc[id] + add_ticks
            sendPunchFx(id, true, active_punchfx_until_tc[id] - tc)
            sendPunchFxDry(false)
            if not silent then displayPunchFxMessage(id, active_punchfx_until_tc[id] - tc, jam) end
            return
        end

        activatePunchFxNow(id, note, punchFxSyncedFreezeTicks(jam), jam, silent)
        return
    end

    local add_ticks = punchFxTicksPerPress(id, jam)

    if active_punchfx_until_tc[id] and active_punchfx_until_tc[id] > jam.tc then
        active_punchfx_until_tc[id] = active_punchfx_until_tc[id] + add_ticks
        sendPunchFx(id, true, active_punchfx_until_tc[id] - jam.tc)
        sendPunchFxDry(false)
        displayPunchFxMessage(id, active_punchfx_until_tc[id] - jam.tc, jam)
        return
    end

    if pending_punchfx[id] then
        pending_punchfx[id].ticks = (pending_punchfx[id].ticks or 0) + add_ticks
    else
        pending_punchfx[id] = { note = note, target_tc = punchFxNextBeatTc(jam), ticks = add_ticks }
    end

    if not silent then displayPunchFxMessage(id, pending_punchfx[id].ticks or add_ticks, jam) end
end

local function velocityFixedValue(mode)
    if mode == 1 then return 15 end
    if mode == 2 then return 40 end
    if mode == 4 then return 110 end
    if mode == 5 then return 127 end
    return nil
end

local function displayVelocityStatusToken()
    if velocity_mode == 3 then return nil end
    return velocityModeName(velocity_mode)
end

local function applyLocalVelocity(value)
    if value <= 0 then return value end
    local fixed = velocityFixedValue(velocity_mode)
    if fixed then return fixed end
    return value
end

local function scaleTrackVelocity(track_index, velocity)
    if velocity <= 0 then return velocity end
    local scaled = math.floor((velocity * (track_levels[track_index] or 1)) + 0.5)
    if scaled < 0 then scaled = 0 end
    if scaled > 127 then scaled = 127 end
    return scaled
end

local function anySeq(predicate)
    for i = 1, 4 do
        if predicate(seqs[i], i) then
            return true, seqs[i], i
        end
    end
    return false, nil, nil
end

local function anySeqHasEvents()
    return anySeq(function(seq) return seq:hasEvents() end)
end

local function allSeqsEmpty()
    for i = 1, 4 do
        if seqs[i]:hasEvents() then return false end
    end
    return true
end

local function isTransportRunning()
    return anySeq(function(seq)
        return seq:isPlaying() or seq:isSyncing() or seq:isRecording() or seq:isOverdubbing()
    end)
end

local function getReferenceSeq()
    local _, seq = anySeq(function(s)
        return s.loop_length > 0 and (s:isPlaying() or s:isOverdubbing() or s:isArmed() or s:isSyncing())
    end)
    return seq or seqs[1]
end

local function getReferenceBeat()
    local seq = getReferenceSeq()
    if not seq or seq.loop_length <= 0 then return 0 end
    return seq:getCurrentLoopBeat()
end

local function updateMasterLoopLengthFromSeqs()
    if seqs[1] and seqs[1].loop_length > 0 then
        master_loop_length = seqs[1].loop_length
        return
    end
    local _, seq = anySeq(function(s) return s.loop_length > 0 or s:hasEvents() end)
    if seq then master_loop_length = seq.loop_length or master_loop_length end
    if allSeqsEmpty() then master_loop_length = 0 end
end

local function syncSeqToReference(seq, run_state)
    if master_loop_length <= 0 then return end
    local beat = getReferenceBeat()
    seq.loop_length = master_loop_length
    seq.playback_tick = math.floor(beat * seq.tpb)
    seq.sync_pending = false
    seq:rebuildEventIndex(beat)
    if run_state then
        seq.state = "PLAYING"
    else
        seq.state = "STOPPED"
    end
end

local function normalizeAllSeqLengths()
    if master_loop_length <= 0 then return end
    local running = isTransportRunning()
    for i = 1, 4 do
        local seq = seqs[i]
        seq.loop_length = master_loop_length
        if running and not seq:isRecording() and not seq:isOverdubbing() and not seq:isArmed() then
            syncSeqToReference(seq, true)
        end
    end
end

local function getGlobalSeqState()
    if anySeq(function(seq) return seq:isRecording() end) then return "RECORDING" end
    if anySeq(function(seq) return seq:isOverdubbing() end) then return "OVERDUB" end
    if selectedSeq():isArmed() then return "ARMED" end
    if anySeq(function(seq) return seq:isSyncing() end) then return "SYNCING" end
    if anySeq(function(seq) return seq:isPlaying() end) then return "PLAYING" end
    return "STOPPED"
end

local function canUndoHistory()
    if not history_track_index then return false end
    local seq = seqs[history_track_index]
    return seq and seq.undo_events ~= nil
end

local function canRedoHistory()
    if not history_track_index then return false end
    local seq = seqs[history_track_index]
    return seq and seq.redo_events ~= nil
end

local function getRecordHoldAction()
    if canRedoHistory() then return "redo" end
    if canUndoHistory() then return "undo" end
    return nil
end

local function hasLoopContext()
    if master_loop_length > 0 then return true end
    return anySeqHasEvents()
end

local function getStoppedFootHoldAction()
    if hasLoopContext() then return "overdub" end
    return "arm"
end

local function clearOtherTrackHistory(target_index)
    for i = 1, 4 do
        if i ~= target_index then
            seqs[i].undo_events = nil
            seqs[i].undo_loop_length = nil
            seqs[i].redo_events = nil
            seqs[i].redo_loop_length = nil
        end
    end
end

local function setGlobalKnobValue(knob_num, value, send_output, immediate)
    engine.knob_values[knob_num] = value
    if send_output and jam_ctx then
        if immediate then
            knob_output_pending[knob_num] = nil
            knob_output_last_sent[knob_num] = value
            jam_ctx.msgout("knobs", "knob" .. knob_num, value)
        else
            knob_output_pending[knob_num] = value
        end
    end
end

function rampGlobalKnobValue(knob_num, target, ticks)
    local current = target
    if engine and engine.knob_values and engine.knob_values[knob_num] ~= nil then
        current = engine.knob_values[knob_num]
    end
    if not jam_ctx or not ticks or ticks <= 1 or math.abs((current or 0) - (target or 0)) < 0.001 then
        knob_ramps[knob_num] = nil
        setGlobalKnobValue(knob_num, target, true, true)
        dirty_knobs[knob_num] = true
        return
    end
    knob_ramps[knob_num] = {
        start = current,
        target = target,
        start_tc = jam_ctx.tc,
        duration = ticks,
        last_tc = -999999
    }
end

function updateKnobRamps(jam)
    if not jam or not knob_ramps then return end
    for i = 1, 4 do
        local ramp = knob_ramps[i]
        if ramp then
            local elapsed = jam.tc - ramp.start_tc
            if elapsed >= ramp.duration then
                knob_ramps[i] = nil
                setGlobalKnobValue(i, ramp.target, true, true)
                dirty_knobs[i] = true
            elseif elapsed >= 0 and (jam.tc - (ramp.last_tc or -999999)) >= 3 then
                local frac = elapsed / ramp.duration
                -- Smoothstep avoids a hard start/end when automation is enabled.
                frac = (frac * frac) * (3 - (2 * frac))
                local value = ramp.start + ((ramp.target - ramp.start) * frac)
                ramp.last_tc = jam.tc
                setGlobalKnobValue(i, value, true, true)
                dirty_knobs[i] = true
            end
        end
    end
end

-- Track type / automation helpers. A track is either nil, "notes", or "knobs".
-- Knob tracks record/play synth parameter automation only. Only one knob track
-- may be enabled at a time, to avoid conflicting parameter playback.
function isKnobTrack(index)
    return track_types and track_types[index] == "knobs"
end

function isAutomationEventType(event_type)
    if not event_type then return false end
    local t = tostring(event_type)
    return t:match("^knob%d$") ~= nil or t:match("^level%d$") ~= nil
end

function seqHasKnobEvents(seq)
    for _, event in ipairs((seq and seq.events) or {}) do
        if isAutomationEventType(event.type) then return true end
    end
    return false
end

function seqHasNoteEvents(seq)
    for _, event in ipairs((seq and seq.events) or {}) do
        if event.type == "note" then return true end
    end
    return false
end

function inferTrackTypeFromSeqData(data)
    if not data or not data.events then return nil end
    local has_knobs = false
    local has_notes = false
    for _, event in ipairs(data.events or {}) do
        if event.type == "note" then has_notes = true end
        if isAutomationEventType(event.type) then has_knobs = true end
    end
    if has_knobs and not has_notes then return "knobs" end
    if has_notes then return "notes" end
    if has_knobs then return "knobs" end
    return nil
end

function copyTrackTypesForSave()
    local out = {}
    for i = 1, 4 do out[i] = track_types and track_types[i] or "empty" end
    return out
end

function copyKnobTrackEnabledForSave()
    local out = {}
    for i = 1, 4 do out[i] = knob_track_enabled and knob_track_enabled[i] or false end
    return out
end

function disableOtherKnobTracks(index)
    for i = 1, 4 do
        knob_track_enabled[i] = (i == index)
    end
end

function sanitizeKnobTrackEnabled()
    local first_enabled = nil
    for i = 1, 4 do
        if track_types[i] ~= "knobs" then
            knob_track_enabled[i] = false
        elseif knob_track_enabled[i] and not first_enabled then
            first_enabled = i
        elseif knob_track_enabled[i] then
            knob_track_enabled[i] = false
        end
    end
end

function getSeqCurrentBeat(seq)
    if not seq then return 0 end
    if seq.getCurrentLoopBeat then return seq:getCurrentLoopBeat() end
    if seq.tpb and seq.tpb > 0 then return (seq.playback_tick or 0) / seq.tpb end
    return 0
end

function getKnobValuesAtBeat(seq, beat)
    local values = {}
    local fallback = {}
    for _, event in ipairs((seq and seq.events) or {}) do
        local knob_num = event.type and tostring(event.type):match("^knob(%d)$")
        knob_num = tonumber(knob_num)
        if knob_num and knob_num >= 1 and knob_num <= 4 then
            fallback[knob_num] = event.value
            if (event.time or 0) <= beat then
                values[knob_num] = event.value
            end
        end
    end
    for i = 1, 4 do
        if values[i] == nil then values[i] = fallback[i] end
    end
    return values
end

function getLevelValuesAtBeat(seq, beat)
    local values = {}
    local fallback = {}
    for _, event in ipairs((seq and seq.events) or {}) do
        local level_num = event.type and tostring(event.type):match("^level(%d)$")
        level_num = tonumber(level_num)
        if level_num and level_num >= 1 and level_num <= 4 then
            fallback[level_num] = event.value
            if (event.time or 0) <= beat then
                values[level_num] = event.value
            end
        end
    end
    for i = 1, 4 do
        if values[i] == nil then values[i] = fallback[i] end
    end
    return values
end

function setTrackLevelValue(track_num, value, redraw_mixer)
    if not track_num or track_num < 1 or track_num > 4 then return end
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    track_levels[track_num] = value
    if redraw_mixer and current_view == "mixer" then
        mixer_level_dirty = true
        mixer_dirty_channels[track_num] = true
    end
    -- Redrawing is handled by the display tick. drawMixerChannel is local and defined later.
end

function applyKnobTrackNow(index, use_ramp)
    if not isKnobTrack(index) then return false end
    local seq = seqs[index]
    if not seq then return false end
    local beat = getSeqCurrentBeat(seq)
    local values = getKnobValuesAtBeat(seq, beat)
    local level_values = getLevelValuesAtBeat(seq, beat)
    local applied = false
    for i = 1, 4 do
        if values[i] ~= nil then
            if use_ramp then
                rampGlobalKnobValue(i, values[i], secondsToTicks(jam_ctx, 0.24))
            else
                setGlobalKnobValue(i, values[i], true, true)
                dirty_knobs[i] = true
            end
            applied = true
        end
        if level_values[i] ~= nil then
            setTrackLevelValue(i, level_values[i], false)
            applied = true
        end
    end
    return applied
end

function setKnobTrackEnabled(index, enabled)
    if not isKnobTrack(index) then return false end

    if enabled then
        local already_exclusive = knob_track_enabled[index] == true
        if already_exclusive then
            for i = 1, 4 do
                if i ~= index and knob_track_enabled[i] then
                    already_exclusive = false
                    break
                end
            end
        end
        if already_exclusive then
            return false
        end

        disableOtherKnobTracks(index)
        applyKnobTrackNow(index, true)
        return true
    end

    if not knob_track_enabled[index] then
        return false
    end
    knob_track_enabled[index] = false
    return true
end

function ensureAutomationTrackForRecording(seq, index, snapshot_kind)
    if not seq or track_types[index] == "notes" then return false end
    if track_types[index] ~= "knobs" then
        track_types[index] = "knobs"
        disableOtherKnobTracks(index)
        if snapshot_kind == "knobs" then
            for i = 1, 4 do
                seq:recordKnob(i, engine.knob_values[i] or 0)
            end
        elseif snapshot_kind == "levels" then
            for i = 1, 4 do
                seq:recordLevel(i, track_levels[i] or 1)
            end
        end
        return true
    end
    return true
end

function recordSelectedKnobAutomation(knob_num, value)
    local seq = selectedSeq()
    local index = selected_track_index
    if not seq then return false, false end
    if track_types[index] == "notes" then return false, false end

    if seq:isArmed() then
        ensureAutomationTrackForRecording(seq, index, "knobs")
        return true, true
    elseif seq:isRecording() and track_types[index] == "knobs" then
        seq:recordKnob(knob_num, value)
        return true, false
    elseif seq:isOverdubbing() and track_types[index] ~= "notes" then
        if ensureAutomationTrackForRecording(seq, index, "knobs") then
            seq:recordKnob(knob_num, value)
            return true, false
        end
    end

    return false, false
end

function recordSelectedLevelAutomation(level_num, value)
    local seq = selectedSeq()
    local index = selected_track_index
    if not seq then return false, false end
    if track_types[index] == "notes" then return false, false end

    if seq:isArmed() then
        ensureAutomationTrackForRecording(seq, index, "levels")
        return true, true
    elseif seq:isRecording() and track_types[index] == "knobs" then
        seq:recordLevel(level_num, value)
        return true, false
    elseif seq:isOverdubbing() and track_types[index] ~= "notes" then
        if ensureAutomationTrackForRecording(seq, index, "levels") then
            seq:recordLevel(level_num, value)
            return true, false
        end
    end

    return false, false
end

function mixerAutomationCaptureActive()
    if current_view ~= "mixer" then return false end
    local seq = selectedSeq and selectedSeq() or nil
    if not seq then return false end
    if track_types[selected_track_index] == "notes" then return false end
    return seq:isArmed() or seq:isRecording() or seq:isOverdubbing()
end

function flushPendingKnobOutputs(jam)
    if not jam or jam.tc < knob_output_next_tc then return end

    local sent_any = false
    for i = 1, 4 do
        local value = knob_output_pending[i]
        if value ~= nil then
            local last = knob_output_last_sent[i]
            if last == nil or math.abs(value - last) >= 0.001 then
                jam.msgout("knobs", "knob" .. i, value)
                knob_output_last_sent[i] = value
                sent_any = true
            end
            knob_output_pending[i] = nil
        end
    end

    if sent_any then
        knob_output_next_tc = jam.tc + knob_output_interval_ticks
    end
end

local function markRightVisualDirty()
    ui_dirty_right = true
end

local function markStatusDirty()
    ui_dirty_status = true
end

local function releaseLatchAndFlush()
    if engine and engine.latch then
        engine.latch:disable()
    end
    if jam_ctx then
        jam_ctx.flushnotes()
    end
    markStatusDirty()
end

local function markAllUiDirty()
    ui_dirty_right = true
    ui_dirty_status = true
    ui_last_progress_pixels = -1
    ui_last_track_mask = -1
    ui_last_selected_track = -1
    ui_dirty_progress = false
    last_bpm = -1
    for i = 1, 4 do dirty_knobs[i] = true end
end

local function currentProgressPixels()
    if master_loop_length <= 0 then return 0 end
    local beat = getReferenceBeat()
    local progress = beat / master_loop_length
    if progress < 0 then progress = 0 end
    if progress > 1 then progress = 1 end
    return math.floor(progress * (PANEL_H - 2))
end

local function getTrackMask()
    local mask = 0
    for i = 1, 4 do
        if seqs[i] and seqs[i]:hasEvents() then
            mask = mask + (2 ^ (i - 1))
        end
    end
    return mask
end

local function presetCount()
    return presets and presets:count() or 0
end

local function presetStatusString()
    local count = presetCount()
    if preset_zero_selected then
        return string.format("0/%d", count)
    end
    if count == 0 then
        return "--"
    end
    return string.format("%d/%d", presets.current_index, count)
end

local function getCurrentPatchName()
    local handle = io.popen("ps -o args= -p $(pidof pd) 2>/dev/null")
    if handle then
        local args = handle:read("*a") or ""
        handle:close()
        local path = args:match('"([^"]+/mother%.pd)"') or args:match('(%S+/mother%.pd)')
        if path then
            local name = path:match('.*/([^/]+)/mother%.pd$')
            if name and #name > 0 then
                return name
            end
        end
    end
    return "capture"
end

local function sanitizeFilenamePart(s)
    s = tostring(s or "capture")
    s = s:gsub("%s+", "_")
    s = s:gsub("[^%w%-%_]+", "")
    if s == "" then s = "capture" end
    return s
end

local function shellQuote(s)
    s = tostring(s or "")
    return "'" .. s:gsub("'", "'\\''") .. "'"
end

local function commandSucceeded(cmd)
    local result = os.execute(cmd .. " >/dev/null 2>&1")
    return result == true or result == 0
end

local function captureDirForRoot(root)
    return root .. "/" .. CAPTURE_SUBDIR
end

local function captureRootIsWritable(root)
    local dir = captureDirForRoot(root)
    if not commandSucceeded("mkdir -p " .. shellQuote(dir)) then
        return false
    end

    local test_path = dir .. "/.capture_write_test"
    if not commandSucceeded("touch " .. shellQuote(test_path)) then
        return false
    end

    os.remove(test_path)
    return true
end

local function chooseCaptureRoot()
    if captureRootIsWritable(CAPTURE_USB_ROOT) then
        return CAPTURE_USB_ROOT
    end

    captureRootIsWritable(CAPTURE_SD_ROOT)
    return CAPTURE_SD_ROOT
end

local function fileExists(path)
    local f = io.open(path, "r")
    if f then
        f:close()
        return true
    end
    return false
end

local function buildCapturePath()
    local root = chooseCaptureRoot()
    local dir = captureDirForRoot(root)
    local patch = sanitizeFilenamePart(getCurrentPatchName())

    for i = 1, 999 do
        local path = string.format("%s/%s_%03d.wav", dir, patch, i)
        if not fileExists(path) then
            capture_save_root = root
            return path
        end
    end

    capture_save_root = root
    return string.format("%s/%s_%03d.wav", dir, patch, 999)
end

function buildMidiPath()
    local root = chooseCaptureRoot()
    local dir = captureDirForRoot(root)
    local patch = sanitizeFilenamePart(getCurrentPatchName())

    for i = 1, 999 do
        local path = string.format("%s/%s_%03d.mid", dir, patch, i)
        if not fileExists(path) then
            capture_save_root = root
            return path
        end
    end

    capture_save_root = root
    return string.format("%s/%s_%03d.mid", dir, patch, 999)
end

function performMidiExport(jam)
    jam = jam or jam_ctx
    if not jam then return false end

    if getGlobalSeqState and getGlobalSeqState() == "RECORDING" then
        displayModal("Stop recording first")
        return false
    end

    if allSeqsEmpty and allSeqsEmpty() then
        displayModal("No MIDI")
        return false
    end

    local path = buildMidiPath()
    local ok, result = MidiExport.write(path, seqs, {
        bpm = jam.bpm or 120,
        beats_per_bar = metroBeatsPerBar(metro_mode),
        track_levels = track_levels,
        loop_length = master_loop_length,
        ppq = 480
    })

    if ok then
        displayTimedTransientModalTwoLines(jam, "MIDI saved", capture_save_root, 3.00)
        return true
    end

    displayTimedTransientModalTwoLines(jam, "MIDI error", tostring(result or "Write failed"), 3.00)
    return false
end

local function startCaptureIfArmed()
    if capture_state ~= "ARMED" then return false end
    capture_path = buildCapturePath()
    jam_ctx.msgout("capture", "open", capture_path)
    jam_ctx.msgout("capture", "start")
    capture_state = "RECORDING"
    markRightVisualDirty()
    return true
end

local function stopCapture(show_message)
    if capture_state == "RECORDING" then
        jam_ctx.msgout("capture", "stop")
        capture_state = "OFF"
        capture_path = nil
        markRightVisualDirty()
        if show_message then
            displayTimedTransientModalTwoLines(jam_ctx, "Saved to", capture_save_root, 3.00)
        end
        return true
    elseif capture_state == "ARMED" then
        capture_state = "OFF"
        capture_path = nil
        markRightVisualDirty()
        if show_message then
            displayModal("Capture Off")
        end
        return true
    end
    return false
end

local function enterPresetZero()
    stopCapture(false)
    if engine and engine.latch then
        engine.latch:disable()
    end
    if jam_ctx then
        jam_ctx.flushnotes()
    end
    
    for i = 1, 4 do
        seqs[i]:stop()
        seqs[i]:clear(false)
        seqs[i].loop_length = 0
        seqs[i].playback_tick = 0
    end
    jam_ctx.flushnotes()
    master_loop_length = 0
    for i = 1, 4 do
        track_types[i] = "empty"
        knob_track_enabled[i] = false
    end
    history_track_index = nil
    selected_track_index = 1
    preset_zero_selected = true
    playlist_loaded = false
    markAllUiDirty()
end

-- =====================================================================
-- DISPLAY
-- =====================================================================

local function formatMenuLine(left, right)
    left = left or ""
    right = right or ""
    return string.format("%-10s| %-7s", left, right)
end

local function trackLabel(index)
    if index == selected_track_index then
        return string.format("[Trk%d]", index)
    end
    return string.format("Track%d", index)
end

local function clearRightVisualArea()
    ogui:fillArea(RIGHT_X, PANEL_Y, 128 - RIGHT_X, PANEL_H, OGUI.COLOR_BLACK)
end

local function drawVerticalProgressBar()
    local x, y, w, h = PROGRESS_X, PANEL_Y, PROGRESS_W, PANEL_H
    ogui:box(x, y, w, h, OGUI.COLOR_WHITE)
    local fill_height = currentProgressPixels()
    if fill_height > 0 then
        ogui:fillArea(x + 1, y + 1, w - 2, fill_height, OGUI.COLOR_WHITE)
    end
end

local function isCaptureRecVisible()
    if capture_state ~= "RECORDING" or not jam_ctx then return false end
    local blink_ticks = secondsToTicks(jam_ctx, 1.00)
    return math.floor(jam_ctx.tc / blink_ticks) % 2 == 0
end

local function drawCaptureRecIndicator()
    if not isCaptureRecVisible() then return end
    local x = 89
    local y = 12
    ogui:fillArea(x - 1, y, 9, 35, OGUI.COLOR_WHITE)
    ogui:println(x, 13, OGUI.SIZE_8, OGUI.COLOR_BLACK, "R")
    ogui:println(x, 24, OGUI.SIZE_8, OGUI.COLOR_BLACK, "E")
    ogui:println(x, 35, OGUI.SIZE_8, OGUI.COLOR_BLACK, "C")
end

local function drawTrackPanel()
    local x, y, w = TRACK_X, PANEL_Y, TRACK_W
    ogui:box(x, y, w, PANEL_H, OGUI.COLOR_WHITE)

    for i = 1, 4 do
        local row_y = y + ((i - 1) * 11)
        local has_events = seqs[i]:hasEvents()
        local selected = (i == selected_track_index)
        local knob_track = isKnobTrack(i)
        -- Automation tracks are not shown as muted/crossed out in the track panel.
        -- They use two material dots instead of one.
        local muted = (not knob_track) and ((track_levels[i] or 0) <= 0.0001)

        if i < 4 then
            ogui:line(x, row_y + 11, x + w - 1, row_y + 11, OGUI.COLOR_WHITE)
        end

        if selected then
            ogui:fillArea(x + 1, row_y + 1, w - 2, 10, OGUI.COLOR_WHITE)
            ogui:println(x + 2, row_y + 2, OGUI.SIZE_8, OGUI.COLOR_BLACK, tostring(i))
            if has_events then
                if knob_track then
                    ogui:fillArea(x + w - 4, row_y + 2, 2, 2, OGUI.COLOR_BLACK)
                    ogui:fillArea(x + w - 4, row_y + 7, 2, 2, OGUI.COLOR_BLACK)
                else
                    ogui:fillArea(x + w - 4, row_y + 4, 2, 3, OGUI.COLOR_BLACK)
                end
            end
            if muted then
                ogui:line(x + 1, row_y + 9, x + w - 2, row_y + 2, OGUI.COLOR_BLACK)
                ogui:line(x + 1, row_y + 8, x + w - 2, row_y + 1, OGUI.COLOR_BLACK)
            end
        else
            ogui:println(x + 2, row_y + 2, OGUI.SIZE_8, OGUI.COLOR_WHITE, tostring(i))
            if has_events then
                if knob_track then
                    ogui:fillArea(x + w - 4, row_y + 2, 2, 2, OGUI.COLOR_WHITE)
                    ogui:fillArea(x + w - 4, row_y + 7, 2, 2, OGUI.COLOR_WHITE)
                else
                    ogui:fillArea(x + w - 4, row_y + 4, 2, 3, OGUI.COLOR_WHITE)
                end
            end
            if muted then
                ogui:line(x + 1, row_y + 9, x + w - 2, row_y + 2, OGUI.COLOR_WHITE)
                ogui:line(x + 1, row_y + 8, x + w - 2, row_y + 1, OGUI.COLOR_WHITE)
            end
        end
    end
end

function restoreKnobLabelsAfterRightRedraw()
    if not engine or not engine.knob_values then return end
    for i = 1, 4 do
        local cfg = knob_configs[i]
        local y = (i - 1) * 11 + 11
        local name_x = 11 + 37 + 4
        ogui:println(name_x, y + 1, OGUI.SIZE_8, OGUI.COLOR_WHITE, cfg[3])
    end
end

function redrawProgressVisualOnly()
    ogui:fillArea(PROGRESS_X, PANEL_Y, PROGRESS_W, PANEL_H, OGUI.COLOR_BLACK)
    drawVerticalProgressBar()
    ui_dirty_progress = false
end

local function drawKnobBar(knob_num, value)
    local cfg = knob_configs[knob_num]
    local y = (knob_num - 1) * 11 + 11
    ogui:fillArea(0, y, MAIN_LEFT_W, 11, OGUI.COLOR_BLACK)
    ogui:println(0, y + 1, OGUI.SIZE_8, OGUI.COLOR_WHITE, tostring(knob_num))

    local bar_x, bar_width, bar_height = 11, 37, 8
    ogui:box(bar_x, y + 1, bar_width, bar_height, OGUI.COLOR_WHITE)
    local fill_width = math.floor(value * (bar_width - 2))
    if fill_width > 0 then
        ogui:fillArea(bar_x + 1, y + 2, fill_width, bar_height - 2, OGUI.COLOR_WHITE)
    end

    local name_x = bar_x + bar_width + 4
    ogui:println(name_x, y + 1, OGUI.SIZE_8, OGUI.COLOR_WHITE, cfg[3])
end

local function drawStatusLine(jam)
    local bpm_str = tostring(math.floor((jam.bpm or 120) + 0.5))
    local latch_str = engine and engine:isLatchEnabled() and "L" or "-"
    local pattern_letter = "-"
    if engine and engine.current_pattern_index > 0 then
        pattern_letter = string.char(64 + engine.current_pattern_index)
    end
    local transpose_str = string.format("%+d", engine and engine.transpose or 0)
    local velocity_token = displayVelocityStatusToken()

    local status_preset = playlist_loaded and "List" or presetStatusString()
    local status = string.format("%s %s %s %s %s", status_preset, bpm_str, latch_str, pattern_letter, transpose_str)
    if velocity_token then status = status .. " " .. velocity_token end

    ogui:fillArea(0, 55, 128, 9, OGUI.COLOR_BLACK)
    ogui:println(0, 56, OGUI.SIZE_8, OGUI.COLOR_WHITE, status)
end

local function drawKnobAutomationIcon(x, y, color)
    -- Minimal Organelle-style knob icon:
    -- round knob, one simple straight pointer inside the circle,
    -- and a custom tiny "1" matching the panel typo:
    -- long vertical stroke, very short horizontal top spur, no foot.
    local cx = x + 10
    local cy = y + 13

    ogui:circle(cx, cy, 7, color)
    ogui:line(cx, cy, cx - 5, cy - 5, color)

    local one_x = cx + 9
    local one_y = cy - 13
    ogui:line(one_x, one_y, one_x, one_y + 7, color)
    ogui:line(one_x - 1, one_y, one_x, one_y, color)
end

local function drawMixerChannel(index)
    local lefts = {4, 35, 66, 97}
    local widths = {24, 24, 24, 24}
    local top = 12
    local bottom = 46
    local max_h = bottom - top
    local x = lefts[index]
    local w = widths[index]

    ogui:fillArea(x - 1, 0, w + 2, 64, OGUI.COLOR_BLACK)
    ogui:box(x, top, w, max_h + 2, OGUI.COLOR_WHITE)

    if isKnobTrack(index) then
        local enabled = knob_track_enabled[index]
        if enabled then
            ogui:fillArea(x + 1, top + 1, w - 2, max_h, OGUI.COLOR_WHITE)
            drawKnobAutomationIcon(x + 2, top + 3, OGUI.COLOR_BLACK)
            ogui:println(x + 7, 52, OGUI.SIZE_8, OGUI.COLOR_WHITE, "on")
        else
            drawKnobAutomationIcon(x + 2, top + 3, OGUI.COLOR_WHITE)
            ogui:println(x + 5, 52, OGUI.SIZE_8, OGUI.COLOR_WHITE, "off")
        end
        return
    end

    local level = track_levels[index] or 0
    local percent = math.floor(level * 100 + 0.5)
    local fill_h = math.floor(level * max_h)

    if fill_h > 0 then
        ogui:fillArea(x + 1, bottom - fill_h + 1, w - 2, fill_h, OGUI.COLOR_WHITE)
    end

    local value_str = tostring(percent)
    local char_w = 5
    local value_w = #value_str * char_w
    local value_x = x + math.floor((w - value_w) / 2)

    ogui:println(value_x, 52, OGUI.SIZE_8, OGUI.COLOR_WHITE, value_str)
end
local function drawMixerDisplay()
    ogui:clear()
    for i = 1, 4 do
        drawMixerChannel(i)
        mixer_dirty_channels[i] = false
    end
    mixer_level_dirty = false
    ogui:flip()
end

local function redrawMixerDirtyChannels()
    local any = false
    for i = 1, 4 do
        if mixer_dirty_channels[i] then
            drawMixerChannel(i)
            mixer_dirty_channels[i] = false
            any = true
        end
    end
    if not any then
        for i = 1, 4 do drawMixerChannel(i) end
    end
    mixer_level_dirty = false
    ogui:flip()
end

local function redrawRightVisuals(skip_label_restore)
    clearRightVisualArea()
    drawCaptureRecIndicator()
    drawTrackPanel()
    drawVerticalProgressBar()
    -- Long knob labels can extend a few pixels into the right panel.
    -- Restore only the label text after right-panel redraws; do not redraw/clear
    -- the full knob rows here, otherwise short loops can make parameter rows blink
    -- because the progress bar updates very frequently.
    if not skip_label_restore and capture_state ~= "RECORDING" and not isCaptureRecVisible() then
        restoreKnobLabelsAfterRightRedraw()
    end
    ui_dirty_right = false
    ui_dirty_progress = false
end

local function drawMainDisplay(force_all)
    redrawRightVisuals(force_all)
    for i = 1, 4 do
        if force_all or dirty_knobs[i] then
            drawKnobBar(i, engine.knob_values[i])
            dirty_knobs[i] = nil
        end
    end
    drawStatusLine(jam_ctx)
    ui_dirty_status = false
    ogui:flip()
end

local function drawCurrentView(force_all)
    if current_view == "mixer" then
        drawMixerDisplay()
    else
        drawMainDisplay(force_all)
    end
end

local function displayKnob(knob_num, value)
    if shift_pressed or current_view ~= "main" then return end
    dirty_knobs[knob_num] = true
end

-- =====================================================================
-- PRESET / TRANSPORT / HISTORY
-- =====================================================================

local function applyExtraPresetSettings(settings)
    metro_mode = settings.metro_mode or 1
    velocity_mode = settings.velocity_mode or 3
    track_levels = settings.track_levels or {1, 1, 1, 1}
    selected_track_index = settings.selected_track or 1
    master_loop_length = settings.master_loop_length or 0

    if selected_track_index < 1 or selected_track_index > 4 then
        selected_track_index = 1
    end

    if jam_ctx then
        jam_ctx.msgout("metro", metro_mode)
    end
end

local function buildPresetSettings()
    local sequences = {}
    for i = 1, 4 do
        sequences[i] = seqs[i]:serialize()
    end

    return {
        knob1 = engine.knob_values[1],
        knob2 = engine.knob_values[2],
        knob3 = engine.knob_values[3],
        knob4 = engine.knob_values[4],
        transpose = engine.transpose,
        pattern = engine.current_pattern_index,
        sequences = sequences,
        track_types = copyTrackTypesForSave(),
        knob_track_enabled = copyKnobTrackEnabledForSave(),
        track_levels = track_levels,
        metro_mode = metro_mode,
        velocity_mode = velocity_mode,
        master_loop_length = master_loop_length,
        selected_track = selected_track_index,
        bpm = jam_ctx and jam_ctx.bpm or nil,
    }
end

local function loadPresetSettings(settings, autoplay)
    if not settings then return nil end

    if not playlist_loading_temp then
        playlist_loaded = false
    end

    stopCapture(false)

    if engine and engine.latch then
        engine.latch:disable()
    end
    jam_ctx.flushnotes()
    
    for i = 1, 4 do seqs[i]:stop() end
    jam_ctx.flushnotes()
    history_track_index = nil
    preset_zero_selected = false

    applyExtraPresetSettings(settings)

    local saved_bpm = tonumber(settings.bpm)
    if jam_ctx then
        if saved_bpm then
            jam_ctx.bpm = saved_bpm
        else
            jam_ctx.bpm = 100
        end
        jam_ctx.msgout("bpm", jam_ctx.bpm)
        last_bpm = -1
        markStatusDirty()
    end

    local pattern_index = settings.pattern or 1
    if engine:getPatternCount() > 0 then
        engine:loadPattern(pattern_index)
    end

    engine.transpose = settings.transpose or 0

    for i = 1, 4 do
        local value = settings["knob" .. i] or 0
        setGlobalKnobValue(i, value, true, true)
        dirty_knobs[i] = true
    end

    local sequences = settings.sequences or {settings.sequence, nil, nil, nil}
    track_types = settings.track_types or {"empty", "empty", "empty", "empty"}
    knob_track_enabled = settings.knob_track_enabled or {false, false, false, false}
    for i = 1, 4 do
        if not track_types[i] or track_types[i] == "empty" then
            track_types[i] = inferTrackTypeFromSeqData(sequences[i]) or "empty"
        end
    end
    sanitizeKnobTrackEnabled()
    for i = 1, 4 do
        if sequences[i] then
            seqs[i]:deserialize(sequences[i], true)
        else
            seqs[i]:clear(master_loop_length > 0)
        end
    end

    if master_loop_length <= 0 then
        updateMasterLoopLengthFromSeqs()
    end
    if master_loop_length > 0 then
        normalizeAllSeqLengths()
    end

    if autoplay and anySeqHasEvents() then
        for i = 1, 4 do
            if seqs[i]:hasEvents() or seqs[i].loop_length > 0 then
                seqs[i]:playSync()
            end
        end
    end

    markAllUiDirty()
    return presets:getDisplayString()
end

-- =====================================================================
-- PLAYLIST BUILDER
-- =====================================================================

function playlistClearTextLayer()
    if ogui then
        ogui:simpleText("", "", "", "", "")
        for i = 1, 5 do ogui:setLine(i, "") end
    end
end

function playlistFormatIndex(index)
    local count = presetCount()
    if count <= 0 then return "--" end
    if index < 1 then index = count end
    if index > count then index = 1 end
    return string.format("%d/%d", index, count)
end

function playlistEntriesText(max_chars)
    if not playlist_entries or #playlist_entries == 0 then return "Empty" end
    local parts = {}
    for i, index in ipairs(playlist_entries) do
        parts[i] = tostring(index)
    end
    local text = table.concat(parts, "+")
    max_chars = max_chars or 21
    if #text > max_chars then
        text = ".." .. string.sub(text, #text - max_chars + 3)
    end
    return text
end

function playlistSplitEntriesText()
    local text = playlistEntriesText(999)
    local prefix = "Playlist: "
    local first_width = 11
    local second_width = 21

    if text == "Empty" then
        return prefix .. text, ""
    end

    if #text <= first_width then
        return prefix .. text, ""
    end

    local first = string.sub(text, 1, first_width)
    local rest = string.sub(text, first_width + 1)
    if #rest > second_width then
        rest = string.sub(rest, 1, second_width - 2) .. ".."
    end
    return prefix .. first, rest
end

function displayPlaylistDialog(message)
    local count = presetCount()
    local selected = playlist_selection_touched and playlistFormatIndex(playlist_select_index) or (count > 0 and ("?/" .. tostring(count)) or "--")
    local list_line_1, list_line_2 = playlistSplitEntriesText()

    -- Keep this dialog deliberately simple: pure text, no graphics inversion.
    -- Avoid clear/flip on every encoder step so preset browsing does not flicker.
    if jam_ctx then jam_ctx.msgout("osc", "/enablepatchsub", 1) end
    if ogui then
        ogui:simpleText(
            "Add Seq:  " .. selected,
            list_line_1,
            list_line_2,
            "Cis:Add   Dis:Remove",
            "Aux:Play  Hold:Save"
        )
    end
end

function playlistLoadSettings(index)
    if not presets or not presets.preset_list or not presets.preset_list[index] then return nil end
    return dofile((presets.base_path or "presets") .. "/" .. presets.preset_list[index])
end

function playlistCloneTable(value)
    if type(value) ~= "table" then return value end
    local copy = {}
    for k, v in pairs(value) do
        copy[k] = playlistCloneTable(v)
    end
    return copy
end

function playlistSegmentLength(settings)
    local length = tonumber(settings and settings.master_loop_length) or 0
    local sequences = settings and (settings.sequences or {settings.sequence, nil, nil, nil}) or {}
    if length <= 0 then
        for i = 1, 4 do
            local seq = sequences[i]
            local seq_len = tonumber(seq and seq.loop_length) or 0
            if seq_len > length then length = seq_len end
        end
    end
    return length
end

function playlistSortEvents(events)
    table.sort(events, function(a, b)
        if a.time == b.time then
            local a_off = a.type == "note" and a.velocity == 0
            local b_off = b.type == "note" and b.velocity == 0
            if a_off ~= b_off then return a_off end
            return (a.type or "") < (b.type or "")
        end
        return (a.time or 0) < (b.time or 0)
    end)
end

function buildPlaylistSettings()
    if not playlist_entries or #playlist_entries == 0 then return nil, "No list" end

    local base = playlistLoadSettings(playlist_entries[1])
    if not base then return nil, "No preset" end

    local result = playlistCloneTable(base)
    local merged = {
        {events = {}, loop_length = 0},
        {events = {}, loop_length = 0},
        {events = {}, loop_length = 0},
        {events = {}, loop_length = 0}
    }
    local offset = 0

    for _, preset_index in ipairs(playlist_entries) do
        local settings = playlistLoadSettings(preset_index)
        if not settings then return nil, "No preset" end
        local segment_length = playlistSegmentLength(settings)
        if segment_length <= 0 then return nil, "Empty seq" end
        local sequences = settings.sequences or {settings.sequence, nil, nil, nil}

        for track = 1, 4 do
            local seq = sequences[track]
            if seq and seq.events then
                for _, event in ipairs(seq.events) do
                    if event.type == "note" then
                        local copy = playlistCloneTable(event)
                        copy.time = (tonumber(copy.time) or 0) + offset
                        table.insert(merged[track].events, copy)
                    end
                end
            end
        end
        offset = offset + segment_length
    end

    for track = 1, 4 do
        merged[track].loop_length = offset
        playlistSortEvents(merged[track].events)
    end

    result.sequences = merged
    result.sequence = nil
    result.track_types = {"notes", "notes", "notes", "notes"}
    result.knob_track_enabled = {false, false, false, false}
    result.master_loop_length = offset
    return result, nil
end

function openPlaylistDialog(jam)
    clearTransientModal()
    clearConfirmAction()
    playlist_dialog_active = true
    playlist_ignore_next_aux_release = true
    playlist_aux_down = false
    playlist_enc_down = false
    playlist_enc_button_value = nil
    playlist_selection_touched = false
    if presetCount() <= 0 then
        playlist_select_index = 1
    elseif not playlist_select_index or playlist_select_index < 1 or playlist_select_index > presetCount() then
        playlist_select_index = presets.current_index > 0 and presets.current_index or 1
    end
    playlistClearTextLayer()
    shift_pressed = false
    aux_menu_opened = false
    aux_combo_used = true
    current_aux_page = 1
    displayPlaylistDialog()
    jam.msgout("osc", "/enablepatchsub", 1)
end

function closePlaylistDialog(redraw)
    playlistClearTextLayer()
    playlist_dialog_active = false
    playlist_aux_down = false
    playlist_enc_down = false
    playlist_enc_button_value = nil
    playlist_ignore_next_aux_release = false
    jam_ctx.msgout("osc", "/enablepatchsub", 0)
    if redraw then
        ogui:clear()
        drawCurrentView(true)
    end
end

function playlistAddSelected()
    if presetCount() <= 0 then
        displayPlaylistDialog("No preset")
        return
    end
    playlist_selection_touched = true
    table.insert(playlist_entries, playlist_select_index)
    displayPlaylistDialog()
end

function playlistUndoLast()
    if playlist_entries and #playlist_entries > 0 then
        table.remove(playlist_entries)
    end
    displayPlaylistDialog()
end

function playlistPlay()
    local settings, err = buildPlaylistSettings()
    if not settings then
        if err == "No list" then
            closePlaylistDialog(false)
            displayTransientModal(jam_ctx, "No list")
        else
            displayPlaylistDialog(err or "No list")
        end
        return false
    end
    playlist_loading_temp = true
    loadPresetSettings(settings, true)
    playlist_loading_temp = false
    playlist_loaded = true
    preset_zero_selected = false
    markStatusDirty()
    closePlaylistDialog(true)
    displayTransientModal(jam_ctx, "List")
    return true
end

function playlistSaveAsNew(from_dialog)
    local settings = nil
    local err = nil
    if playlist_loaded and not from_dialog then
        settings = buildPresetSettings()
    else
        settings, err = buildPlaylistSettings()
    end
    if not settings then
        if from_dialog then displayPlaylistDialog(err or "No list") else displayModal(err or "No list") end
        return false
    end
    if presets:save(settings) then
        playlist_loaded = false
        preset_zero_selected = false
        if from_dialog then
            playlist_loading_temp = false
            loadPresetSettings(settings, false)
            playlist_loaded = false
            markStatusDirty()
            closePlaylistDialog(true)
            displayTimedTransientModalTwoLines(jam_ctx, "Saved", presetStatusString(), 1.00)
        else
            markStatusDirty()
            displayModalTwoLines("Saved", presetStatusString())
        end
        return true
    end
    if from_dialog then displayPlaylistDialog("Save failed") else displayModal("Save failed") end
    return false
end

function updatePlaylistHolds(jam)
    if playlist_aux_down and playlist_aux_hold_stage < 1 and jam.tc - playlist_aux_down_tc >= getPlaylistHoldTicks(jam) then
        playlist_aux_hold_stage = 1
        playlist_aux_down = false
        -- Save immediately at the long-press threshold. The following AUX
        -- release is swallowed by the normal shift handler after the dialog
        -- closes.
        ignore_next_shift_release = true
        playlistSaveAsNew(true)
        return
    end
    if playlist_enc_down and playlist_enc_hold_stage < 1 and jam.tc - playlist_enc_down_tc >= getPlaylistEncoderUndoTicks(jam) then
        playlist_enc_hold_stage = 1
        displayPlaylistDialog()
    end
end

local function startAllPlayback()
    if not anySeqHasEvents() and master_loop_length <= 0 then return "empty" end
    if master_loop_length <= 0 then updateMasterLoopLengthFromSeqs() end
    
    if engine and engine.latch then
        engine.latch:disable()
    end
    jam_ctx.flushnotes()
    markStatusDirty()
    
    for i = 1, 4 do
        seqs[i]:stop()
        if master_loop_length > 0 then seqs[i].loop_length = master_loop_length end
        if seqs[i]:hasEvents() or seqs[i].loop_length > 0 then
            seqs[i]:playSync()
        end
    end

    for i = 1, 4 do
        if isKnobTrack(i) and knob_track_enabled[i] then applyKnobTrackNow(i) end
    end
    startCaptureIfArmed()
    markRightVisualDirty()
    return "playing"
end

local function commitActiveOverdubsBeforeStop()
    local committed = false
    for i = 1, 4 do
        if seqs[i]:isOverdubbing() then
            if seqs[i]:endOverdub() then
                committed = true
                history_track_index = i
            end
        end
    end
    return committed
end

local function stopAllPlayback()
    local saved = false
    if capture_state == "RECORDING" then
        stopCapture(false)
        saved = true
    elseif capture_state == "ARMED" then
        stopCapture(false)
    end

    commitActiveOverdubsBeforeStop()

    for i = 1, 4 do seqs[i]:stop() end
    releaseLatchAndFlush()
    markRightVisualDirty()
    if saved then return "saved" end
    return "stopped"
end

local function toggleGlobalPlayback()
    if isTransportRunning() then
        return stopAllPlayback()
    elseif selectedSeq():isArmed() then
        selectedSeq():stop()
        markRightVisualDirty()
        return "stopped"
    end
    return startAllPlayback()
end

local function syncSelectedIfRunning()
    if engine and engine.latch then
        engine.latch:disable()
    end
    jam_ctx.flushnotes()
    markStatusDirty()
    
    local seq = selectedSeq()
    if master_loop_length > 0 and isTransportRunning() then
        syncSeqToReference(seq, true)
        markRightVisualDirty()
        return "playing"
    end
    seq:stop()
    markRightVisualDirty()
    return "stopped"
end

local function armSelectedTrack()
    local seq = selectedSeq()

    if master_loop_length <= 0 and selected_track_index ~= 1 then
        return "need_master"
    end

    if seq:isArmed() then
        return syncSelectedIfRunning()
    end

    jam_ctx.flushnotes()

    if master_loop_length > 0 then
        seq:stop()
        seq.loop_length = master_loop_length
        seq.playback_tick = math.floor(getReferenceBeat() * seq.tpb)
        seq:arm(true)
        seq.playback_tick = math.floor(getReferenceBeat() * seq.tpb)
    else
        seq:stop()
        seq:arm()
    end

    markRightVisualDirty()
    return "armed"
end

local function endSelectedRecording()
    local seq = selectedSeq()
    if not seq:isRecording() then return nil end

    local was_free_initial_recording = master_loop_length <= 0

    seq:endRecording()
    releaseLatchAndFlush()

    if was_free_initial_recording then
        clearOtherTrackHistory(selected_track_index)
        history_track_index = selected_track_index
        seq.undo_events = {}
        seq.undo_loop_length = 0
        seq.redo_events = nil
        seq.redo_loop_length = nil
    end

    if master_loop_length <= 0 then
        master_loop_length = seq.loop_length
    else
        seq.loop_length = master_loop_length
    end

    normalizeAllSeqLengths()
    if anySeqHasEvents() then startAllPlayback() end

    markRightVisualDirty()
    return "playing"
end

local function startSelectedOverdub()
    local seq = selectedSeq()
    if master_loop_length <= 0 then
        updateMasterLoopLengthFromSeqs()
    end
    if master_loop_length <= 0 then return nil end

    if not isTransportRunning() then
        for i = 1, 4 do
            seqs[i]:stop()
            seqs[i].loop_length = master_loop_length
            if seqs[i]:hasEvents() or seqs[i].loop_length > 0 then
                seqs[i]:play()
            end
        end
    end

    seq = selectedSeq()
    seq.loop_length = master_loop_length

    if not seq:isPlaying() then
        syncSeqToReference(seq, true)
    end

    clearOtherTrackHistory(selected_track_index)

    local result = seq:startOverdub()
    if result then
        seq.knob_overdub_touched = {}
        history_track_index = selected_track_index
        markRightVisualDirty()
        return "overdub"
    end

    return nil
end

local function endSelectedOverdub()
    local result = selectedSeq():endOverdub()
    if result then
        releaseLatchAndFlush()
        markRightVisualDirty()
        return "playing"
    end
    return nil
end

local function undoHistory()
    if not history_track_index then return nil end
    local seq = seqs[history_track_index]
    if not seq then return nil end
    local result = seq:undoOverdub()
    if result then
        if allSeqsEmpty() then
            master_loop_length = 0
            for i = 1, 4 do
                seqs[i]:stop()
                seqs[i].loop_length = 0
                seqs[i].playback_tick = 0
                seqs[i].event_index = 1
                seqs[i].redo_events = nil
                seqs[i].redo_loop_length = nil
            end
            history_track_index = nil
            releaseLatchAndFlush()
        else
            updateMasterLoopLengthFromSeqs()
            normalizeAllSeqLengths()
        end
        markRightVisualDirty()
        return "undone"
    end
    return nil
end

local function redoHistory()
    if not history_track_index then return nil end
    local seq = seqs[history_track_index]
    if not seq then return nil end
    local result = seq:redoOverdub()
    if result then
        markRightVisualDirty()
        return "redone"
    end
    return nil
end

local function clearTrackSequence(index)
    seqs[index]:stop()
    seqs[index]:clear(master_loop_length > 0)
    if master_loop_length > 0 then
        seqs[index].loop_length = master_loop_length
    end

    track_types[index] = "empty"
    knob_track_enabled[index] = false

    if index == history_track_index then
        history_track_index = nil
    end

    if allSeqsEmpty() then
        master_loop_length = 0
        for i = 1, 4 do
            seqs[i].loop_length = 0
            seqs[i].playback_tick = 0
        end
    elseif isTransportRunning() and master_loop_length > 0 then
        syncSeqToReference(seqs[index], true)
    end

    markRightVisualDirty()
end

local function sortSequenceEvents(events)
    table.sort(events, function(a, b)
        if a.time == b.time then
            local a_is_off = a.type == "note" and a.velocity == 0
            local b_is_off = b.type == "note" and b.velocity == 0
            if a_is_off ~= b_is_off then return a_is_off end
            return (a.type or "") < (b.type or "")
        end
        return a.time < b.time
    end)
end

local function trackBounceAction(target_index, source_index)
    return "BOUNCE_" .. tostring(target_index) .. "_" .. tostring(source_index)
end

local function bounceAllAction()
    return "BOUNCE_ALL_T1"
end

local function cloneEventForBounce(event, level)
    local copy = {}
    for k, v in pairs(event) do
        copy[k] = v
    end

    if copy.type == "note" and copy.velocity and copy.velocity > 0 then
        copy.velocity = math.floor((copy.velocity * level) + 0.5)
        if copy.velocity < 1 then copy.velocity = 1 end
        if copy.velocity > 127 then copy.velocity = 127 end
    end

    return copy
end

local function doTrackBounce(target_index, source_index)
    if target_index == source_index then return false end

    if isKnobTrack(target_index) or isKnobTrack(source_index) then
        displayModalTwoLines("No knob", "bounce")
        return false
    end

    local target = seqs[target_index]
    local source = seqs[source_index]
    if not source or not target or not source:hasEvents() then
        displayModal("Track empty")
        return false
    end

    if master_loop_length <= 0 then
        updateMasterLoopLengthFromSeqs()
    end

    target.loop_length = master_loop_length > 0 and master_loop_length or source.loop_length

    local source_level = track_levels[source_index] or 1
    if source_level > 0 then
        for _, event in ipairs(source.events) do
            table.insert(target.events, cloneEventForBounce(event, source_level))
        end
        sortSequenceEvents(target.events)
    end

    if target:isPlaying() or target:isOverdubbing() or target:isSyncing() then
        target:rebuildEventIndex(target:getCurrentLoopBeat())
    end

    target.undo_events = nil
    target.undo_loop_length = nil
    target.redo_events = nil
    target.redo_loop_length = nil
    source.undo_events = nil
    source.undo_loop_length = nil
    source.redo_events = nil
    source.redo_loop_length = nil

    if history_track_index == source_index or history_track_index == target_index then
        history_track_index = nil
    end

    track_types[target_index] = "notes"
    knob_track_enabled[target_index] = false
    clearTrackSequence(source_index)
    selected_track_index = target_index
    markRightVisualDirty()
    return true
end

local function promptTrackBounce(target_index, source_index)
    if target_index == source_index then return end
    if not seqs[source_index]:hasEvents() then
        displayModal("Track empty")
        return
    end

    pending_bounce_target = target_index
    pending_bounce_source = source_index
    confirm_action = trackBounceAction(target_index, source_index)
    displayModalTwoLines("Bounce ?", "T" .. source_index .. " > T" .. target_index)
end

local function confirmPendingTrackBounce(source_index)
    if not pending_bounce_target or pending_bounce_source ~= source_index then
        return false
    end

    local target_index = pending_bounce_target
    local action = trackBounceAction(target_index, source_index)
    if confirm_action ~= action then
        return false
    end

    clearConfirmAction()
    if doTrackBounce(target_index, source_index) then
        displayModalTwoLines("Done.", "T" .. source_index .. " > T" .. target_index)
    end
    return true
end

local function doBounceAllToTrack1()
    if isKnobTrack(1) then
        displayModalTwoLines("No knob", "bounce")
        return false
    end

    local target = seqs[1]
    if not target then return false end

    local has_source_events = false
    for source_index = 2, 4 do
        if seqs[source_index] and seqs[source_index]:hasEvents() and not isKnobTrack(source_index) then
            has_source_events = true
            break
        end
    end

    if not has_source_events then
        displayModal("Track empty")
        return false
    end

    if master_loop_length <= 0 then
        updateMasterLoopLengthFromSeqs()
    end

    if master_loop_length > 0 then
        target.loop_length = master_loop_length
    end

    for source_index = 2, 4 do
        local source = seqs[source_index]
        if source and source:hasEvents() and not isKnobTrack(source_index) then
            local source_level = track_levels[source_index] or 1
            if source_level > 0 then
                for _, event in ipairs(source.events) do
                    table.insert(target.events, cloneEventForBounce(event, source_level))
                end
            end
        end
    end

    sortSequenceEvents(target.events)

    if target:isPlaying() or target:isOverdubbing() or target:isSyncing() then
        target:rebuildEventIndex(target:getCurrentLoopBeat())
    end

    for source_index = 2, 4 do
        local source = seqs[source_index]
        if source then
            source:stop()
            source:clear(master_loop_length > 0)
            if master_loop_length > 0 then
                source.loop_length = master_loop_length
            end
            source.undo_events = nil
            source.undo_loop_length = nil
            source.redo_events = nil
            source.redo_loop_length = nil
            track_types[source_index] = "empty"
            knob_track_enabled[source_index] = false
        end
    end

    target.undo_events = nil
    target.undo_loop_length = nil
    target.redo_events = nil
    target.redo_loop_length = nil
    track_types[1] = "notes"
    knob_track_enabled[1] = false
    history_track_index = nil
    selected_track_index = 1

    if master_loop_length <= 0 then
        updateMasterLoopLengthFromSeqs()
    end
    if master_loop_length > 0 then
        normalizeAllSeqLengths()
    end

    markRightVisualDirty()
    return true
end

local function confirmBounceAllToTrack1()
    if confirm_action ~= bounceAllAction() then
        return false
    end

    clearConfirmAction()
    if doBounceAllToTrack1() then
        displayModalTwoLines("Done.", "All > T1")
    end
    return true
end

-- =====================================================================
-- AUX MENU LOGIC
-- =====================================================================

local function getPlayLabel()
    if isTransportRunning() or selectedSeq():isArmed() then return "Stop/List" end
    return "Play/List"
end

local function getRecordLabel()
    local state = getGlobalSeqState()

    if state == "OVERDUB" and selectedSeq():isOverdubbing() then
        if canUndoHistory() then
            return "Play/Undo"
        end
        return "Play"
    end

    if selectedSeq():isArmed() then
        return "Stop"
    end

    if master_loop_length > 0 then
        if canRedoHistory() then
            return "Over/Redo"
        elseif canUndoHistory() then
            return "Over/Undo"
        end
        return "Over"
    end

    return "Arm"
end

local function getPageLabels(page)
    if page == 3 then
        local labels = {
            "Octaves",
            "Freeze",
            "OldTape",
            "Retrigger",
            "Dist",
            "Stutter",
            "Warp",
            "Reverse",
            "Universe",
            "PingPong"
        }
        for i = 1, #punchfx_names do
            if latched_punchfx[i] then
                labels[i] = labels[i] .. "+"
            end
        end
        return labels
    end

    if page == 2 then
        return {
            "Loop x2",
            "Loop /2",
            velocityModeName(velocity_mode),
            "Capture",
            "Delete",
            trackLabel(1),
            trackLabel(2),
            trackLabel(3),
            trackLabel(4),
            "Punch FX"
        }
    end

    return {
        getPlayLabel(),
        getRecordLabel(),
        "<",
        "Save/Copy",
        ">",
        "Oct-",
        "Oct+",
        "Latch",
        metroModeName(metro_mode),
        "Page2 >>>"
    }
end

function displayShiftMenu()
    local labels = getPageLabels(current_aux_page)

    if current_aux_page == 3 then
        -- Page 3 changes while it stays latched open. Rebuild the OLED area
        -- explicitly so latch markers appear immediately and stale modal
        -- graphics cannot cover the menu.
        ogui:clear()
        for line = 1, 5 do
            ogui:setLine(line, formatMenuLine(labels[line] or "", labels[line + 5] or ""))
        end
        return
    end

    for line = 1, 5 do
        ogui:setLine(line, formatMenuLine(labels[line] or "", labels[line + 5] or ""))
    end
end

local function closeShiftMenu(jam, suppress_redraw)
    if not shift_pressed then return end
    clearTransientModal()
    clearConfirmAction()
    clearMenuHold()
    punchfx_menu_latched = false
    shift_pressed = false
    current_aux_page = 1
    aux_menu_opened = false
    if not suppress_redraw then
        ogui:clear()
        drawCurrentView(true)
    end
    jam.msgout("osc", "/enablepatchsub", 0)

    if pending_capture_saved_root then
        local root = pending_capture_saved_root
        pending_capture_saved_root = nil
        displayTimedTransientModalTwoLines(jam, "Saved to", root, 3.00)
    end
end

local function openShiftMenu(jam)
    if shift_pressed then return end
    clearTransientModal()
    clearConfirmAction()
    clearMenuHold()
    punchfx_menu_latched = false
    current_aux_page = 1
    shift_pressed = true
    aux_menu_opened = true
    ogui:clear()
    displayShiftMenu()
    jam.msgout("osc", "/enablepatchsub", 1)
end

local function confirmOrPerform(action, callback)
    if confirm_action == action then
        confirm_action = nil
        callback()
        return true
    end
    confirm_action = action
    return false
end

local function trackClearAction(index)
    return "CLEAR_TRACK_" .. tostring(index)
end


function finishActiveOverdubsForTrackSwitch()
    local committed = false
    for i = 1, 4 do
        if seqs[i]:isOverdubbing() then
            if seqs[i]:endOverdub() then
                committed = true
                history_track_index = i
            end
        end
    end
    if committed then
        releaseLatchAndFlush()
        markRightVisualDirty()
    end
    return committed
end

local function selectTrack(index)
    if index ~= selected_track_index then
        finishActiveOverdubsForTrackSwitch()
    end
    selected_track_index = index
    markRightVisualDirty()
    if shift_pressed then
        displayShiftMenu()
    else
        drawCurrentView(true)
    end
end

local function cycleMetroMode()
    metro_mode = (metro_mode % 8) + 1
    jam_ctx.msgout("metro", metro_mode)
    displayModal(metroModeName(metro_mode))
end

local function metroOff()
    metro_mode = 1
    jam_ctx.msgout("metro", metro_mode)
    displayModal("Click off")
end

local function cycleVelocityMode()
    velocity_mode = (velocity_mode % 5) + 1
    markStatusDirty()
    displayModal(velocityModeName(velocity_mode))
end

local function performLoopDouble()
    if master_loop_length <= 0 then
        displayModal("Empty")
        return
    end

    if not confirmOrPerform("LOOP_X2", function()
        for i = 1, 4 do
            if seqs[i]:hasEvents() then seqs[i]:duplicateLoop() end
        end
        master_loop_length = master_loop_length * 2
        normalizeAllSeqLengths()
        markRightVisualDirty()
        displayModal("Loop x2")
    end) then
        displayModal("Loop x2?")
    end
end

local function performLoopHalf()
    if master_loop_length <= 0 then
        displayModal("Empty")
        return
    end

    if not confirmOrPerform("LOOP_X0.5", function()
        for i = 1, 4 do
            if seqs[i]:hasEvents() then seqs[i]:halveLoop() end
        end
        master_loop_length = master_loop_length / 2
        normalizeAllSeqLengths()
        markRightVisualDirty()
        displayModal("Loop /2")
    end) then
        displayModal("Loop /2?")
    end
end

local function performDeletePreset()
    if preset_zero_selected or presets.current_index == 0 or presetCount() == 0 then
        displayModal("No preset")
        return
    end

    if not confirmOrPerform("DELETE", function()
        if presets:delete() then
            if presetCount() == 0 then
                enterPresetZero()
                displayModal("Deleted")
            else
                local settings = presets:loadCurrent()
                if settings then
                    loadPresetSettings(settings, false)
                    displayModalTwoLines("Preset", presetStatusString())
                else
                    enterPresetZero()
                    displayModal("Deleted")
                end
            end
        end
    end) then
        displayModal("Delete?")
    end
end

local function performTrackClear(index)
    local action = trackClearAction(index)
    if not confirmOrPerform(action, function()
        selectTrack(index)
        clearTrackSequence(index)
        displayWideModal("Track " .. index .. " clear")
    end) then
        displayWideModal("Clear Track" .. index .. "?")
    end
end

local function performRecordButtonShort()
    local state = getGlobalSeqState()

    if state == "OVERDUB" and selectedSeq():isOverdubbing() then
        local result = endSelectedOverdub()
        if result == "playing" then displayModal("Playing") end
        return
    end

    if selectedSeq():isArmed() then
        local result = syncSelectedIfRunning()
        if result == "playing" then
            displayModal("Playing")
        else
            displayModal("Stopped")
        end
        return
    end

    if master_loop_length > 0 then
        local result = startSelectedOverdub()
        if result == "overdub" then displayModal("Overdub") end
    else
        local result = armSelectedTrack()
        if result == "armed" then
            displayModal("Armed")
        elseif result == "need_master" then
            displayModal("Track1 first")
        end
    end
end

function performPresetSaveConfirmed()
    if playlist_loaded then
        playlistSaveAsNew(false)
        return
    end

    local ok
    if preset_zero_selected then
        ok = presets:save(buildPresetSettings())
    else
        ok = presets:overwrite(buildPresetSettings())
    end
    if ok then
        preset_zero_selected = false
        displayModalTwoLines("Saved", presetStatusString())
        markStatusDirty()
    end
end

function performPresetCopyConfirmed()
    if playlist_loaded then
        playlistSaveAsNew(false)
        return
    end

    if presets:save(buildPresetSettings()) then
        preset_zero_selected = false
        displayModalTwoLines("Copied", presetStatusString())
        markStatusDirty()
    end
end

function confirmPresetSave()
    if getGlobalSeqState() == "RECORDING" then
        displayModal("Stop recording first")
        return
    end
    if confirm_action == "SAVE_PRESET" then
        confirm_action = nil
        performPresetSaveConfirmed()
    else
        confirm_action = "SAVE_PRESET"
        displayModal("Save?")
    end
end

function confirmPresetCopy()
    if getGlobalSeqState() == "RECORDING" then
        displayModal("Stop recording first")
        return
    end
    if confirm_action == "COPY_PRESET" then
        confirm_action = nil
        performPresetCopyConfirmed()
    else
        confirm_action = "COPY_PRESET"
        displayModal("Copy?")
    end
end

local function handlePage1ImmediateKey(index)
    local state = getGlobalSeqState()
    if index ~= 10 and index ~= 9 and index ~= 4 then clearConfirmAction() end

    if index == 1 then
        local result = toggleGlobalPlayback()
        if result == "playing" then
            displayModal("Playing")
        elseif result == "saved" then
            pending_capture_saved_root = capture_save_root
            displayTimedTransientModalTwoLines(jam_ctx, "Saved to", capture_save_root, 3.00)
        elseif result == "stopped" then
            displayModal("Stopped")
        else
            displayModal("Empty")
        end

    elseif index == 3 then
        local count = presetCount()
        if count == 0 then
            displayModal("No preset")
        elseif preset_zero_selected then
            presets.current_index = count
            local settings = presets:loadCurrent()
            if settings then
                loadPresetSettings(settings, true)
                displayModalTwoLines("Preset", presetStatusString())
            end
        elseif presets.current_index == 1 then
            enterPresetZero()
            displayModalTwoLines("Preset", presetStatusString())
        else
            local settings = presets:prev()
            if settings then
                loadPresetSettings(settings, true)
                displayModalTwoLines("Preset", presetStatusString())
            else
                displayModal("No preset")
            end
        end

    elseif index == 4 then
        -- Fallback: Save now asks for confirmation.
        confirmPresetSave()

    elseif index == 5 then
        local count = presetCount()
        if count == 0 then
            displayModal("No preset")
        elseif preset_zero_selected then
            presets.current_index = 1
            local settings = presets:loadCurrent()
            if settings then
                loadPresetSettings(settings, true)
                displayModalTwoLines("Preset", presetStatusString())
            end
        elseif presets.current_index >= count then
            enterPresetZero()
            displayModalTwoLines("Preset", presetStatusString())
        else
            local settings = presets:next()
            if settings then
                loadPresetSettings(settings, true)
                displayModalTwoLines("Preset", presetStatusString())
            else
                displayModal("No preset")
            end
        end

    elseif index == 6 then
        engine.transpose = math.max(-24, engine.transpose - 12)
        markStatusDirty()
        displayModalTwoLines("Octave", string.format("%+d", engine.transpose / 12))

    elseif index == 7 then
        engine.transpose = math.min(24, engine.transpose + 12)
        markStatusDirty()
        displayModalTwoLines("Octave", string.format("%+d", engine.transpose / 12))

    elseif index == 8 then
        local enabled = not engine:isLatchEnabled()
        if enabled then
            engine.latch:enable()
        else
            engine.latch:disable()
        end
        markStatusDirty()
        displayModalTwoLines("Latch", enabled and "On" or "Off")

    elseif index == 10 then
        clearConfirmAction()
        current_aux_page = 2
        displayShiftMenu()
    end
end

local function handlePage2ImmediateKey(index)
    if index ~= 10 and index ~= 1 and index ~= 2 and index ~= 4 and index ~= 5 then clearConfirmAction() end

    if index == 1 then
        performLoopDouble()
    elseif index == 2 then
        performLoopHalf()
    elseif index == 3 then
        cycleVelocityMode()
    elseif index == 4 then
        if capture_state == "OFF" then
            capture_state = "ARMED"
            markRightVisualDirty()
            displayModalTwoLines("Capture", "Armed")
        elseif capture_state == "ARMED" then
            stopCapture(true)
        else
            stopCapture(true)
        end
    elseif index == 5 then
        performDeletePreset()
    elseif index == 10 then
        clearConfirmAction()
        current_aux_page = 3
        punchfx_menu_latched = true
        aux_menu_opened = true
        displayShiftMenu()
    end
end

local function handlePage3ImmediateKey(index, note, jam)
    clearConfirmAction()

    if index >= 1 and index <= #punchfx_names then
        activatePunchFx(index, note, jam)
    end
end

local function updateMenuHold(jam)
    if not menu_hold then return end

    local held_ticks = jam.tc - menu_hold.start_tc

    if menu_hold.kind == "playlist" then
        if held_ticks >= getPlaylistHoldTicks(jam) and menu_hold.stage < 1 then
            menu_hold.stage = 1
            openPlaylistDialog(jam)
        end

    elseif menu_hold.kind == "record" then
        if held_ticks >= getAuxUndoTicks(jam) and menu_hold.stage < 1 then
            local action = getRecordHoldAction()
            if action == "redo" then
                menu_hold.stage = 1
                displayModal("Redo")
            elseif action == "undo" then
                menu_hold.stage = 1
                displayModal("Undo")
            end
        end

    elseif menu_hold.kind == "savecopy" then
        if held_ticks >= getAuxSaveCopyTicks(jam) and menu_hold.stage < 1 then
            menu_hold.stage = 1
            displayModal("Copy?")
        end

    elseif menu_hold.kind == "click" then
        if held_ticks >= getAuxClickOffTicks(jam) and menu_hold.stage < 1 then
            menu_hold.stage = 1
            metroOff()
        end

    elseif menu_hold.kind == "capture" then
        if menu_hold.capture_state == "OFF" and held_ticks >= getMidiExportHoldTicks(jam) and menu_hold.stage < 1 then
            menu_hold.stage = 1
            confirm_action = "MIDI_EXPORT"
            displayWideModal("Export MIDI?")
        end

    elseif menu_hold.kind == "punchfx" then
        if held_ticks >= getPunchFxLatchHoldTicks(jam) and menu_hold.stage < 1 then
            menu_hold.stage = 1
            setLatchedPunchFx(menu_hold.fx_id, true, jam)
        end

    elseif menu_hold.kind == "trackclear" then
        if menu_hold.track_index == 1 then
            if held_ticks >= getTrack1ClearHoldTicks(jam) and menu_hold.stage < 2 then
                menu_hold.stage = 2
                if not seqs[1]:hasEvents() then
                    displayModal("Track empty")
                else
                    confirm_action = trackClearAction(1)
                    displayWideModal("Clear Track1?")
                end
            elseif held_ticks >= getTrack1BounceAllHoldTicks(jam) and menu_hold.stage < 1 then
                menu_hold.stage = 1
                local has_source_events = false
                for source_index = 2, 4 do
                    if seqs[source_index]:hasEvents() then
                        has_source_events = true
                        break
                    end
                end
                if has_source_events then
                    confirm_action = bounceAllAction()
                    displayModalTwoLines("Bounce All?", "To T1")
                else
                    displayModal("Track empty")
                end
            end
        elseif held_ticks >= getTrackClearHoldTicks(jam) and menu_hold.stage < 1 then
            menu_hold.stage = 1
            if not seqs[menu_hold.track_index]:hasEvents() then
                displayModal("Track empty")
            else
                confirm_action = trackClearAction(menu_hold.track_index)
                displayWideModal("Clear Track" .. menu_hold.track_index .. "?")
            end
        end
    end
end

local function handleMenuHoldRelease(jam, note)
    if not menu_hold or menu_hold.note ~= note then return false end
    local hold = menu_hold
    clearMenuHold()

    if hold.kind == "playlist" then
        if hold.stage < 1 then
            handlePage1ImmediateKey(1)
        end
        return true

    elseif hold.kind == "record" then
        if hold.stage >= 1 then
            local action = getRecordHoldAction()
            if action == "redo" then
                local result = redoHistory()
                if result == "redone" then
                    displayTransientModal(jam, "Redo")
                else
                    displayTransientModal(jam, "No Redo")
                end
            elseif action == "undo" then
                local result = undoHistory()
                if result == "undone" then
                    displayTransientModal(jam, "Undo")
                else
                    displayTransientModal(jam, "No Undo")
                end
            else
                performRecordButtonShort()
            end
        else
            performRecordButtonShort()
        end
        return true

    elseif hold.kind == "savecopy" then
        if confirm_action == "COPY_PRESET" then
            confirmPresetCopy()
        elseif confirm_action == "SAVE_PRESET" then
            confirmPresetSave()
        elseif hold.stage >= 1 then
            confirmPresetCopy()
        else
            confirmPresetSave()
        end
        return true

    elseif hold.kind == "click" then
        if hold.stage >= 1 then
            metroOff()
        else
            cycleMetroMode()
        end
        return true

    elseif hold.kind == "capture" then
        if hold.stage >= 1 and hold.capture_state == "OFF" then
            -- MIDI export is confirmed by pressing Capture again while the Aux menu is open.
        else
            handlePage2ImmediateKey(4)
        end
        return true

    elseif hold.kind == "punchfx" then
        if hold.stage < 1 then
            activatePunchFx(hold.fx_id, hold.note, jam)
        end
        return true

    elseif hold.kind == "trackclear" then
        if hold.stage == 0 then
            selectTrack(hold.track_index)
        end
        return true

    elseif hold.kind == "bounce" then
        return true
    end

    return false
end

local function toggleView()
    current_view = (current_view == "main") and "mixer" or "main"
    ogui:clear()
    drawCurrentView(true)
end

-- =====================================================================
-- FOOTSWITCH
-- =====================================================================

local function getFootPreview(jam, press_state, held_ticks)
    local history_action = getRecordHoldAction()

    if press_state == "STOPPED" then
        if held_ticks >= getFootActionTicks(jam) then
            if getStoppedFootHoldAction() == "overdub" then
                return "OVERDUB"
            end
            return "ARMED"
        end
    elseif press_state == "PLAYING" or press_state == "SYNCING" then
        if held_ticks >= getFootUndoTicks(jam) then
            if history_action == "redo" then
                return "REDO"
            elseif history_action == "undo" then
                return "UNDO"
            end
        end
        if held_ticks >= getFootActionTicks(jam) then
            return "OVERDUB"
        end
    elseif press_state == "OVERDUB" then
        if held_ticks >= getFootUndoTicks(jam) then
            if history_action == "redo" then
                return "REDO"
            elseif history_action == "undo" then
                return "UNDO"
            end
        end
    end
    return nil
end

local function updateFootPreview(jam)
    if not fs_is_down or not fs_press_state then
        if fs_hold_preview ~= nil then fs_hold_preview = nil end
        return
    end

    local held_ticks = jam.tc - fs_down_tc
    local new_preview = getFootPreview(jam, fs_press_state, held_ticks)
    if new_preview ~= fs_hold_preview then
        fs_hold_preview = new_preview
        clearTransientModal()
        if fs_hold_preview == "ARMED" then
            displayModal("Armed")
        elseif fs_hold_preview == "OVERDUB" then
            displayModal("Overdub")
        elseif fs_hold_preview == "UNDO" then
            displayModal("Undo")
        elseif fs_hold_preview == "REDO" then
            displayModal("Redo")
        end
    end
end

local function handleFootswitchRelease(jam, held_ticks, press_state)
    if press_state == "RECORDING" then
        local result = endSelectedRecording()
        if result == "playing" then displayTransientModal(jam, "Playing") end
        return
    end

    if held_ticks >= getFootUndoTicks(jam) and (press_state == "PLAYING" or press_state == "OVERDUB" or press_state == "SYNCING") then
        local history_action = getRecordHoldAction()
        if history_action == "redo" then
            local result = redoHistory()
            if result == "redone" then
                displayTransientModal(jam, "Redo")
            else
                displayTransientModal(jam, "No Redo")
            end
            return
        elseif history_action == "undo" then
            local result = undoHistory()
            if result == "undone" then
                displayTransientModal(jam, "Undo")
            else
                displayTransientModal(jam, "No Undo")
            end
            return
        end
    end

    if held_ticks >= getFootActionTicks(jam) then
        if press_state == "STOPPED" then
            if getStoppedFootHoldAction() == "overdub" then
                local result = startSelectedOverdub()
                if result == "overdub" then
                    displayTransientModal(jam, "Overdub")
                else
                    displayTransientModal(jam, "Empty")
                end
            else
                local result = armSelectedTrack()
                if result == "armed" then
                    displayTransientModal(jam, "Armed")
                elseif result == "need_master" then
                    displayTransientModal(jam, "Track1 first")
                end
            end
            return
        elseif press_state == "PLAYING" or press_state == "SYNCING" then
            local result = startSelectedOverdub()
            if result == "overdub" then displayTransientModal(jam, "Overdub") end
            return
        end
    end

    if press_state == "ARMED" then
        local result = syncSelectedIfRunning()
        if result == "playing" then
            displayTransientModal(jam, "Playing")
        else
            displayTransientModal(jam, "Stopped")
        end
        return
    end

    if press_state == "STOPPED" then
        local result = startAllPlayback()
        if result == "playing" then
            displayTransientModal(jam, "Playing")
        else
            displayTransientModal(jam, "Empty")
        end
        return
    end

    if press_state == "PLAYING" or press_state == "SYNCING" then
        local result = stopAllPlayback()
        if result == "saved" then
            displayTimedTransientModalTwoLines(jam, "Saved to", capture_save_root, 3.00)
        else
            displayTransientModal(jam, "Stopped")
        end
        return
    end

    if press_state == "OVERDUB" then
        local result = endSelectedOverdub()
        if result == "playing" then displayTransientModal(jam, "Playing") end
        return
    end
end

-- =====================================================================
-- INIT / TICK / INPUT
-- =====================================================================

function init(jam)
    jam_ctx = jam

    collectgarbage("collect")
    collectgarbage("setpause", 110)
    collectgarbage("setstepmul", 200)

    captureRootIsWritable(CAPTURE_SD_ROOT)

    ogui = OGUI.new(function(...) jam.msgout(...) end)
    encoder_accel = EncoderAccel.new()
    presets = Presets.new("presets")

    jam.msgout("osc", "/enablepatchsub", 0)

    for i = 1, 4 do
        seqs[i] = Sequencer.new({
            tpb = jam.tpb,
            tc = jam.tc,
            output = function(type, ...)
                if type == "note" then
                    local note, velocity, duration = ...
                    jam.noteout(note, scaleTrackVelocity(i, velocity), duration)
                elseif type == "knobs" then
                    if isKnobTrack(i) and knob_track_enabled[i] then
                        local automation_type, value = ...
                        local knob_num = tonumber(tostring(automation_type):match("^knob(%d)$"))
                        local level_num = tonumber(tostring(automation_type):match("^level(%d)$"))
                        if knob_num then
                            setGlobalKnobValue(knob_num, value, true, true)
                            dirty_knobs[knob_num] = true
                        elseif level_num then
                            setTrackLevelValue(level_num, value, true)
                        end
                    end
                end
            end
        })
    end

    engine = Track.new(jam, 1, function(type, ...)
        if type == "note" then
            local note, velocity, duration = ...
            jam.noteout(note, scaleTrackVelocity(selected_track_index, velocity), duration)
        elseif type == "knobs" then
            local automation_type, value = ...
            local knob_num = tonumber(tostring(automation_type):match("^knob(%d)$"))
            local level_num = tonumber(tostring(automation_type):match("^level(%d)$"))
            if knob_num then
                setGlobalKnobValue(knob_num, value, true, true)
                dirty_knobs[knob_num] = true
            elseif level_num then
                setTrackLevelValue(level_num, value, true)
            else
                jam.msgout("knobs", automation_type, value)
            end
        elseif type == "flushnotes" then
            jam.flushnotes()
        end
    end)

    -- Replace engine recorder with selected-seq proxy
    engine.seq = {
        tick = function() end,
        recordNote = function(_, note, velocity, duration)
            local index = selected_track_index
            if track_types[index] == "knobs" then return end
            if velocity > 0 and (selectedSeq():isArmed() or selectedSeq():isOverdubbing()) and not selectedSeq():hasEvents() then
                track_types[index] = "notes"
                knob_track_enabled[index] = false
            end
            selectedSeq():recordNote(note, velocity, duration)
        end,
        recordKnob = function(_, knob_num, value)
            recordSelectedKnobAutomation(knob_num, value)
        end,
    }

    if engine:getPatternCount() > 0 then
        engine:loadPattern(1)
    end

    jam.msgout("metro", metro_mode)
    sendPunchFxDry(true)
    for i = 1, #punchfx_names do
        sendPunchFx(i, false)
    end
    ogui:led(OGUI.LED_OFF)
end

function tick(jam)
    if initial_draw_needed then
        initial_draw_needed = false
        drawCurrentView(true)
    end

    if jam.tc % 30 == 0 then
        collectgarbage("step", 8)
    end

    updateKnobRamps(jam)
    flushPendingKnobOutputs(jam)

    engine:tick()
    for i = 1, 4 do seqs[i]:tick() end

    if metro_mode > 1 then
        if jam.every(1) then
            jam.msgout("click", metro_mode, metroAccentFlag(jam))
        end
    end

    for id = 1, #punchfx_names do
        if pending_punchfx[id] and jam.tc >= pending_punchfx[id].target_tc then
            local pending = pending_punchfx[id]
            pending_punchfx[id] = nil
            activatePunchFxNow(id, pending.note, pending.ticks, jam)
        end
    end

    local punchfx_changed = false
    for id = 1, #punchfx_names do
        if (not latched_punchfx[id]) and active_punchfx_until_tc[id] and active_punchfx_until_tc[id] > 0 and jam.tc >= active_punchfx_until_tc[id] then
            sendPunchFx(id, false)
            active_punchfx_until_tc[id] = nil
            punchfx_changed = true
        end
    end
    if punchfx_changed then
        sendPunchFxDry(not punchFxAnyActive(jam))
        if punchfx_menu_latched and current_aux_page == 3 then
            displayShiftMenu()
        end
    end

    updateFootPreview(jam)
    updateMenuHold(jam)
    if playlist_dialog_active then updatePlaylistHolds(jam) end

    if transient_modal_until_tc and jam.tc >= transient_modal_until_tc then
        transient_modal_until_tc = nil
        if punchfx_menu_latched and current_aux_page == 3 then
            displayShiftMenu()
        elseif not shift_pressed and not playlist_dialog_active and fs_hold_preview == nil then
            drawCurrentView(true)
        end
    end

    local track_mask = getTrackMask()
    if track_mask ~= ui_last_track_mask or selected_track_index ~= ui_last_selected_track then
        ui_last_track_mask = track_mask
        ui_last_selected_track = selected_track_index
        ui_dirty_right = true
    end

    local progress_pixels = currentProgressPixels()
    if progress_pixels ~= ui_last_progress_pixels then
        ui_last_progress_pixels = progress_pixels
        ui_dirty_progress = true
    end

    local rec_visible = isCaptureRecVisible()
    if rec_visible ~= ui_last_rec_blink_visible then
        ui_last_rec_blink_visible = rec_visible
        ui_dirty_right = true
    end

    local current_bpm = math.floor((jam.bpm or 120) + 0.5)
    if current_bpm ~= last_bpm then
        last_bpm = current_bpm
        ui_dirty_status = true
    end

    local ticks_wait = math.max(1, math.floor(jam.tpb * jam.bpm / 1200))
    if jam.tc - last_display_tc >= ticks_wait then
        if current_view == "mixer" and not shift_pressed and not playlist_dialog_active and not transient_modal_until_tc and fs_hold_preview == nil then
            if mixer_level_dirty then
                redrawMixerDirtyChannels()
            end
        elseif current_view == "main" and not shift_pressed and not playlist_dialog_active and not transient_modal_until_tc and fs_hold_preview == nil then
            local need_flip = false
            if dirty_knobs[1] or dirty_knobs[2] or dirty_knobs[3] or dirty_knobs[4] then
                for i = 1, 4 do
                    if dirty_knobs[i] then
                        drawKnobBar(i, engine.knob_values[i])
                        dirty_knobs[i] = nil
                    end
                end
                need_flip = true
            end
            if ui_dirty_right then
                redrawRightVisuals()
                need_flip = true
            elseif ui_dirty_progress then
                redrawProgressVisualOnly()
                need_flip = true
            end
            if ui_dirty_status then
                drawStatusLine(jam)
                ui_dirty_status = false
                need_flip = true
            end
            if need_flip then ogui:flip() end
        end
        last_display_tc = jam.tc
    end

    updateLED()
end

function encoder(jam, v)
    if playlist_dialog_active then
        shift_pressed = false
        aux_menu_opened = false
        aux_combo_used = true
        current_aux_page = 1
        if jam then jam.msgout("osc", "/enablepatchsub", 1) end
        local count = presetCount()
        if count <= 0 then
            displayPlaylistDialog("No preset")
            return
        end
        local increment = encoder_accel:getIncrement()
        if v == 1 then
            playlist_select_index = playlist_select_index + increment
        else
            playlist_select_index = playlist_select_index - increment
        end
        while playlist_select_index < 1 do playlist_select_index = playlist_select_index + count end
        while playlist_select_index > count do playlist_select_index = playlist_select_index - count end
        playlist_selection_touched = true
        displayPlaylistDialog()
        return
    end

    if shift_pressed then
        aux_combo_used = true
    end

    local increment = encoder_accel:getIncrement()
    if v == 1 then
        jam.bpm = math.min(250, jam.bpm + increment)
    else
        jam.bpm = math.max(20, jam.bpm - increment)
    end
    jam.msgout("bpm", jam.bpm)
    displayTransientModalTwoLines(jam, "BPM", tostring(math.floor(jam.bpm)))
end

function encoder_button(jam, v)
    if not playlist_dialog_active then return end

    -- Different Organelle builds can report encoder-button polarity differently.
    -- Treat the first event as button-down and the matching opposite event as release.
    if not playlist_enc_down then
        playlist_enc_down = true
        playlist_enc_down_tc = jam.tc
        playlist_enc_hold_stage = 0
        playlist_enc_button_value = v
        return
    end

    if v ~= playlist_enc_button_value then
        if playlist_enc_hold_stage >= 1 or jam.tc - playlist_enc_down_tc >= getPlaylistEncoderUndoTicks(jam) then
            playlistUndoLast()
        else
            playlistAddSelected()
        end
        playlist_enc_down = false
        playlist_enc_button_value = nil
    end
end

function midinotein(jam, n, v)
    local velocity = v
    if v > 0 then velocity = applyLocalVelocity(v) end
    engine:midinotein(n, velocity)
end

function keyin(jam, n, v)
    notes_held = notes_held + (v > 0 and 1 or -1)
    notes_held = math.max(0, notes_held)

    if playlist_dialog_active then
        if v > 0 then
            if n == 61 or n == 73 then
                playlistAddSelected()
            elseif n == 63 or n == 75 then
                playlistUndoLast()
            end
        end
        return
    end

    if shift_pressed then
        local track_slot_lookup = {
            [73] = 1,
            [75] = 2,
            [78] = 3,
            [80] = 4
        }
        local held_track_index = track_slot_lookup[n]

        if current_aux_page == 3 then
            for i, key in ipairs(shift_keys) do
                if n == key then
                    aux_combo_used = true
                    if v > 0 then
                        if latched_punchfx[i] then
                            setLatchedPunchFx(i, false, jam)
                        else
                            menu_hold = {
                                note = n,
                                kind = "punchfx",
                                start_tc = jam.tc,
                                stage = 0,
                                fx_id = i
                            }
                        end
                    else
                        if handleMenuHoldRelease(jam, n) then
                            return
                        end
                    end
                    return
                end
            end

            -- Page 3 is a latched performance menu: black keys trigger FX,
            -- white keys remain playable as live notes.
            local velocity = v
            if v > 0 then
                velocity = applyLocalVelocity(v)
            end
            engine:notein(n, velocity)
            return
        end

        if v > 0 then
            aux_combo_used = true

            -- Page 1 hold buttons
            if current_aux_page == 1 and n == shift_keys[1] then
                clearConfirmAction()
                menu_hold = {
                    note = n,
                    kind = "playlist",
                    start_tc = jam.tc,
                    stage = 0
                }
                return
            end

            if current_aux_page == 1 and n == shift_keys[2] then
                clearConfirmAction()
                menu_hold = {
                    note = n,
                    kind = "record",
                    start_tc = jam.tc,
                    stage = 0
                }
                return
            end

            if current_aux_page == 1 and n == shift_keys[4] then
                menu_hold = {
                    note = n,
                    kind = "savecopy",
                    start_tc = jam.tc,
                    stage = 0
                }
                return
            end

            if current_aux_page == 1 and n == shift_keys[9] then
                clearConfirmAction()
                menu_hold = {
                    note = n,
                    kind = "click",
                    start_tc = jam.tc,
                    stage = 0
                }
                return
            end

            -- Page 2 capture button: short press arms/stops WAV capture, hold asks to export MIDI.
            if current_aux_page == 2 and n == shift_keys[4] then
                if confirm_action == "MIDI_EXPORT" then
                    clearConfirmAction()
                    performMidiExport(jam)
                    return
                end
                clearConfirmAction()
                menu_hold = {
                    note = n,
                    kind = "capture",
                    start_tc = jam.tc,
                    stage = 0,
                    capture_state = capture_state
                }
                return
            end

            -- Page 2 track buttons
            if current_aux_page == 2 and held_track_index then
                if held_track_index == 1 and confirmBounceAllToTrack1() then
                    clearMenuHold()
                    return
                end

                if confirmPendingTrackBounce(held_track_index) then
                    clearMenuHold()
                    return
                end

                if menu_hold and menu_hold.kind == "trackclear" and menu_hold.track_index ~= held_track_index and menu_hold.stage == 0 then
                    local target_index = menu_hold.track_index
                    promptTrackBounce(target_index, held_track_index)
                    menu_hold = {
                        note = n,
                        kind = "bounce",
                        start_tc = jam.tc,
                        stage = 0,
                        track_index = target_index,
                        source_index = held_track_index
                    }
                    return
                end

                local action = trackClearAction(held_track_index)
                if confirm_action == action then
                    performTrackClear(held_track_index)
                    clearMenuHold()
                else
                    clearConfirmAction()
                    menu_hold = {
                        note = n,
                        kind = "trackclear",
                        start_tc = jam.tc,
                        stage = 0,
                        track_index = held_track_index
                    }
                end
                return
            end

            -- Black-key shift functions
            for i, key in ipairs(shift_keys) do
                if n == key then
                    if current_aux_page == 2 then
                        handlePage2ImmediateKey(i)
                    else
                        handlePage1ImmediateKey(i)
                    end
                    return
                end
            end

            -- White-key pattern / arp selection
            clearConfirmAction()
            for i, key in ipairs(pattern_select_keys) do
                if n == key then
                    local pattern_name = engine:loadPattern(i)
                    if pattern_name then
                        local letter = pattern_name:match("^(%a)%-") or ""
                        local display_name = pattern_name:gsub("^%a%-", "")
                        displayModalTwoLines("Pattern " .. letter, display_name)
                        markStatusDirty()
                    else
                        displayModal("No pattern")
                    end
                    return
                end
            end

        else
            if handleMenuHoldRelease(jam, n) then
                return
            end
        end

    else
        local velocity = v
        if v > 0 then
            velocity = applyLocalVelocity(v)
        end
        engine:notein(n, velocity)
    end
end

function footswitch(jam, _value)
    if not fs_is_down then
        fs_is_down = true
        fs_down_tc = jam.tc
        fs_press_state = getGlobalSeqState()
        fs_hold_preview = nil
        return
    end

    local held_ticks = jam.tc - fs_down_tc
    local press_state = fs_press_state
    fs_is_down = false
    fs_press_state = nil
    fs_hold_preview = nil

    handleFootswitchRelease(jam, held_ticks, press_state)
end

function shift(jam, v)
    if playlist_dialog_active then
        if v == 1 then
            playlist_aux_down = true
            playlist_aux_down_tc = jam.tc
            playlist_aux_hold_stage = 0
        else
            if playlist_ignore_next_aux_release then
                playlist_ignore_next_aux_release = false
                shift_pressed = false
                aux_combo_used = false
                aux_menu_opened = false
                return
            end
            if playlist_aux_down then
                if playlist_aux_hold_stage < 1 and jam.tc - playlist_aux_down_tc < getPlaylistHoldTicks(jam) then
                    playlistPlay()
                end
            end
            playlist_aux_down = false
        end
        return
    end

    if v == 1 then
        if punchfx_menu_latched then
            ignore_next_shift_release = true
            closeShiftMenu(jam, false)
            aux_combo_used = false
            aux_menu_opened = false
            return
        end

        aux_combo_used = false
        aux_menu_opened = false

        local state = getGlobalSeqState()
        if state == "RECORDING" then
            endSelectedRecording()
            return
        end

        if notes_held == 0 then
            openShiftMenu(jam)
        end

    else
        if ignore_next_shift_release then
            ignore_next_shift_release = false
            aux_combo_used = false
            aux_menu_opened = false
            return
        end

        if punchfx_menu_latched and current_aux_page == 3 then
            -- Keep Page 3 open after AUX release, so both hands can fire FX.
            shift_pressed = true
            aux_combo_used = false
            aux_menu_opened = true
            displayShiftMenu()
            return
        end

        local did_action = aux_combo_used
        local had_menu = aux_menu_opened

        if shift_pressed then
            closeShiftMenu(jam, not did_action and had_menu)
        end

        if had_menu and not did_action then
            toggleView()
        end

        aux_combo_used = false
        aux_menu_opened = false
    end
end

local function handleKnob(jam, knob_num, v)
    if shift_pressed and not (punchfx_menu_latched and current_aux_page == 3) then
        aux_combo_used = true
        return
    end

    if punchfx_menu_latched and current_aux_page == 3 then
        setGlobalKnobValue(knob_num, v, true)
        local recorded, visual_dirty = recordSelectedKnobAutomation(knob_num, v)
        if visual_dirty then markRightVisualDirty() end
        return
    end

    if current_view == "mixer" then
        if mixerAutomationCaptureActive() then
            -- During mixer automation recording/overdub, keep the UI responsive:
            -- update the live value and record it, but let the throttled mixer
            -- redraw in tick() do the screen work. Immediate flips on every
            -- knob movement can steal audio time and cause zipper/click artifacts.
            setTrackLevelValue(knob_num, v, true)
            recordSelectedLevelAutomation(knob_num, v)
            return
        end

        if isKnobTrack(knob_num) then
            local enabled = v >= 0.5
            if setKnobTrackEnabled(knob_num, enabled) then
                for i = 1, 4 do
                    drawMixerChannel(i)
                    mixer_dirty_channels[i] = false
                end
                mixer_level_dirty = false
                ogui:flip()
                markRightVisualDirty()
            end
            return
        end
        setTrackLevelValue(knob_num, v, true)
        markRightVisualDirty()
        return
    end

    setGlobalKnobValue(knob_num, v, true)
    local recorded, visual_dirty = recordSelectedKnobAutomation(knob_num, v)
    if visual_dirty then markRightVisualDirty() end
    displayKnob(knob_num, v)
end
function knob1(jam, v) handleKnob(jam, 1, v) end
function knob2(jam, v) handleKnob(jam, 2, v) end
function knob3(jam, v) handleKnob(jam, 3, v) end
function knob4(jam, v) handleKnob(jam, 4, v) end

function displayStatusLine(jam)
    drawStatusLine(jam)
    ogui:flip()
end

function displayKnobs(jam)
    drawCurrentView(true)
end

function updateLED()
    if capture_state == "RECORDING" then
        ogui:led(OGUI.LED_CYAN)
        return
    elseif capture_state == "ARMED" then
        local blink_ticks = math.max(1, secondsToTicks(jam_ctx, 0.40))
        if math.floor(jam_ctx.tc / blink_ticks) % 2 == 0 then
            ogui:led(OGUI.LED_CYAN)
        else
            ogui:led(OGUI.LED_OFF)
        end
        return
    elseif fs_hold_preview == "REDO" then
        ogui:led(OGUI.LED_PURPLE)
        return
    elseif fs_hold_preview == "UNDO" then
        ogui:led(OGUI.LED_PURPLE)
        return
    elseif fs_hold_preview == "OVERDUB" then
        ogui:led(OGUI.LED_RED)
        return
    elseif fs_hold_preview == "ARMED" then
        ogui:led(OGUI.LED_PURPLE)
        return
    end

    local state = getGlobalSeqState()
    if state == "RECORDING" or state == "OVERDUB" then
        ogui:led(OGUI.LED_RED)
    elseif state == "PLAYING" or state == "SYNCING" then
        ogui:led(OGUI.LED_GREEN)
    elseif state == "ARMED" then
        ogui:led(OGUI.LED_PURPLE)
    else
        ogui:led(OGUI.LED_OFF)
    end
end