-- organelle-mother.lua
-- Mother jam using organelle_track module

local OGUI = require("lib/ogui").OGUI
local EncoderAccel = require("lib/ogui").EncoderAccel
local Track = require("lib/organelle_track").Track

-- State
local ogui = nil
local encoder_accel = nil
local track = nil
local shift_pressed = false
local notes_held = 0
local delete_armed = false
local metro_enabled = false
local dirty_knobs = {}  -- stores pending knob values (nil = not dirty)
local last_display_tc = 0
local last_bpm = 0
local initial_draw_needed = true

-- Shift function keys (black keys starting from C#)
local shift_keys = {61, 63, 66, 68, 70, 73, 75, 78, 80, 82}
local pattern_select_keys = {60, 62, 64, 65, 67, 69, 71, 72, 74, 76, 77, 79, 81, 83}

-- Shift function labels
local shift_labels = {
    "Play", "Arm", "<", "Save", ">",
    "Oct-", "Oct+", "Latch", "Click", "Delete"
}

-- Knob names (single line for easy replacement by deploy script)
local knob_names = {"Decay", "Brightness", "Drive", "Chorus"}

-- Knob display configs: {format_string, value_transform_function, label}
local knob_configs = {
    {"%d%%", function(v) return math.floor(v * 100) end, knob_names[1]},
    {"%d%%", function(v) return math.floor(v * 100) end, knob_names[2]},
    {"%d%%", function(v) return math.floor(v * 100) end, knob_names[3]},
    {"%d%%", function(v) return math.floor(v * 100) end, knob_names[4]},
}

local function drawKnobBar(knob_num, value)
    local cfg = knob_configs[knob_num]
    local y = (knob_num - 1) * 11 + 11

    ogui:fillArea(0, y, 128, 11, OGUI.COLOR_BLACK)

    -- 1. Knob number
    local num_str = string.format("%d", knob_num)
    ogui:println(0, y + 1, OGUI.SIZE_8, OGUI.COLOR_WHITE, num_str)

    -- 2. Bar graph (2px after knob number)
    local num_width = 8  -- approximate pixel width of "1:" in SIZE_8
    local bar_x = num_width + 3
    local bar_width = 37
    local bar_height = 8

    ogui:box(bar_x, y + 1, bar_width, bar_height, OGUI.COLOR_WHITE)

    local fill_width = math.floor(value * (bar_width - 2))
    if fill_width > 0 then
        ogui:fillArea(bar_x + 1, y + 2, fill_width, bar_height - 2, OGUI.COLOR_WHITE)
    end

    -- 3. Knob name (4px after bar graph)
    local name_x = bar_x + bar_width + 4
    ogui:println(name_x, y + 1, OGUI.SIZE_8, OGUI.COLOR_WHITE, cfg[3])
end

-- Draw status line without flip (for batch updates)
local function drawStatusLine(jam)
    local preset_str = track:getPresetCount() > 0
        and string.format("%d/%d", track:getCurrentPresetIndex(), track:getPresetCount())
        or "--"
    local bpm_str = tostring(math.floor((jam.bpm or 120) + 0.5))
    local latch_str = track:isLatchEnabled() and "L" or "-"
    local pattern_letter = "-"
    if track.current_pattern_index > 0 then
        pattern_letter = string.char(64 + track.current_pattern_index)
    end
    local transpose_str = string.format("%+d", track.transpose)

    local y = 55  -- Line 5: after 10px header + 4 lines of 11px each
    ogui:fillArea(0, y, 128, 9, OGUI.COLOR_BLACK)
    ogui:println(0, y + 1, OGUI.SIZE_8, OGUI.COLOR_WHITE,
        string.format("%s %s %s %s %s", preset_str, bpm_str, latch_str, pattern_letter, transpose_str))
end

local function displayKnob(knob_num, value)
    if shift_pressed then return end
    dirty_knobs[knob_num] = value
end

function init(jam)
    -- Create Organelle UI
    ogui = OGUI.new(function(...)
        jam.msgout(...)
    end)
    
    -- helper for encoder BPM selection
    encoder_accel = EncoderAccel.new()
    
    -- take over encoder
    jam.msgout("osc", "/enablepatchsub", 0)
    
    -- Create track with output callback
    track = Track.new(jam, 1, function(type, ...)
        if type == "note" then
            local note, velocity, duration = ...
            jam.noteout(note, velocity, duration)
        elseif type == "knobs" then
            local knob_type, value = ...
            local knob_num = tonumber(knob_type:match("%d"))
            jam.msgout("knobs", knob_type, value)
            displayKnob(knob_num, value)
        elseif type == "flushnotes" then
            jam.flushnotes()
        end
    end)
    
    -- Load initial pattern if available
    if track:getPatternCount() > 0 then
        track:loadPattern(1)
    end
    
    ogui:led(OGUI.LED_OFF)
end

function tick(jam)
    if initial_draw_needed then
        initial_draw_needed = false
        displayKnobs(jam)
    end
    track:tick()
    if metro_enabled then
        if jam.every(1) then jam.msgout("click") end
    end

    -- Redraw display (rate-limited to ~50ms)
    local ticks_wait = math.max(1, math.floor(jam.tpb * jam.bpm / 1200))
    if jam.tc - last_display_tc >= ticks_wait then
        local needs_flip = false
        -- Redraw dirty knobs
        for i = 1, 4 do
            if dirty_knobs[i] then
                drawKnobBar(i, dirty_knobs[i])
                dirty_knobs[i] = nil
                needs_flip = true
            end
        end
        -- Check for BPM change (skip during shift menu to avoid flicker)
        if not shift_pressed then
            local current_bpm = math.floor(jam.bpm + 0.5)
            if current_bpm ~= last_bpm then
                last_bpm = current_bpm
                drawStatusLine(jam)
                needs_flip = true
            end
        end
        if needs_flip then
            ogui:flip()
        end
        last_display_tc = jam.tc
    end

    -- keep LED up to date with seq state
    updateLED()
end

-- Input handlers
function encoder(jam, v)
    local increment = encoder_accel:getIncrement()
    
    if v == 1 then
        -- increase bpm
        jam.bpm = math.min(250, jam.bpm + increment)
    else 
        -- decrease bpm
        jam.bpm = math.max(20, jam.bpm - increment)
    end
    jam.msgout("bpm", jam.bpm)
    
    -- Show speed indicator if accelerating for debugging
    local speed_indicator = ""--increment > 1 and (" (x" .. increment .. ")") or ""
    displayModalTwoLines("BPM" .. speed_indicator, tostring(math.floor(jam.bpm)))
end

function encoder_button(jam, v)
    
end

function midinotein(jam, n, v)
    -- midi notes always go through
    track:midinotein(n, v)
    
    -- keep led up to date
    updateLED()
end

function keyin(jam, n, v)
    -- Track note on/off for shift mode blocking
    notes_held = notes_held + (v > 0 and 1 or -1)
    notes_held = math.max(0, notes_held)
    
    if shift_pressed then
        -- Shift mode: handle shift menu
        if v > 0 then
            handleShiftMenu(n)
        end
    else
        -- Normal mode: route to track
        track:notein(n, v)
        
        -- keep led up to date
        updateLED()
    end
end

function handleShiftMenu(note)
    -- Check shift function keys
    for i, key in ipairs(shift_keys) do
        if note == key then
            if i ~= 10 then
                delete_armed = false
            end
            shiftFunctions[i]()
            return
        end
    end
    
    -- Check pattern selection keys
    for i, key in ipairs(pattern_select_keys) do
        if note == key then
            local pattern_name = track:loadPattern(i)
            if pattern_name then
                local letter = pattern_name:match("^(%a)%-") or ""
                local display_name = pattern_name:gsub("^%a%-", "")  -- strip "A-" prefix
                displayModalTwoLines("Pattern " .. letter, display_name)
            else
                displayModal("No pattern")
            end
            return
        end
    end
end

-- Shift button handler
function shift(jam, v)
    if v == 1 then
        -- Shift pressed: end recording if active, otherwise enter menu
        local state = track:getSeqState()
        if state == "RECORDING" then
            track:endRecording()
            return
        end
        
        -- Only enter shift mode if no notes held
        if notes_held == 0 then
            shift_pressed = true
            ogui:clear()
            displayShiftMenu()
            jam.msgout("osc", "/enablepatchsub", 1) -- take over encoder for tempo selection
        end
    else
        -- Shift released
        if shift_pressed then
            shift_pressed = false
            delete_armed = false
            ogui:clear()
            displayKnobs(jam)
        end
        jam.msgout("osc", "/enablepatchsub", 0) -- restore encoder
    end
end

-- Knob handlers
local function handleKnob(jam, knob_num, v)
    track:setKnob(knob_num, v)
    displayKnob(knob_num, v)
end

function knob1(jam, v) handleKnob(jam, 1, v) end
function knob2(jam, v) handleKnob(jam, 2, v) end
function knob3(jam, v) handleKnob(jam, 3, v) end
function knob4(jam, v) handleKnob(jam, 4, v) end

-- Shift Functions
shiftFunctions = {
    -- Function 1: Start/Stop playback
    function()
        local result = track:togglePlayback()
        if result == "playing" then
            displayModal("Playing")
        elseif result == "stopped" then
            displayModal("Stopped")
        elseif result == "empty" then
            displayModal("Empty")
        end
    end,
    
    -- Function 2: Arm recording
    function()
        local result = track:toggleArm()
        if result == "armed" then
            displayModal("Armed")
        elseif result == "stopped" then
            displayModal("Stopped")
        end
    end,
    
    -- Function 3: Previous preset
    function()
        local display = track:prevPreset()
        if display then
            if track:hasEvents() then
                track:startPlayback()  -- Start playing
            end
            displayModalTwoLines("Preset", display)
        else
            displayModal("No preset")
        end
    end,
    
    -- Function 4: Save preset
    function()
        if track:getSeqState() == "RECORDING" then
            displayModal("Stop recording first")
            return
        end
        
        if track:savePreset() then
            displayModalTwoLines("Saved", track:getPresetDisplay())
        end
    end,
    
    -- Function 5: Next preset
    function()
        local display = track:nextPreset()
        if display then
            if track:hasEvents() then
                track:startPlayback()  -- Start playing
            end
            displayModalTwoLines("Preset", display)
        else
            displayModal("No preset")
        end
    end,
    
    -- Function 6: Transpose down by octave
    function()
        local octaves = track:transposeDown()
        displayModalTwoLines("Octave", string.format("%+d", octaves))
    end,
    
    -- Function 7: Transpose up by octave
    function()
        local octaves = track:transposeUp()
        displayModalTwoLines("Octave", string.format("%+d", octaves))
    end,
    
    -- Function 8: Latch toggle
    function()
        local enabled = track:toggleLatch()
        displayModalTwoLines("Latch", enabled and "On" or "Off")
    end,
    
    -- Function 9: Placeholder
    function() 
        if metro_enabled then metro_enabled = false 
        else metro_enabled = true end
    end,
    
    -- Function 10: Delete preset (requires two taps)
    function()
        if track:getCurrentPresetIndex() == 0 or track:getPresetCount() == 0 then
            displayModal("No preset")
            return
        end
        
        if not delete_armed then
            delete_armed = true
            displayModalTwoLines("Delete", track:getPresetDisplay() .. "?")
        else
            if track:deletePreset() then
                delete_armed = false
                displayModalTwoLines("Deleted", " ")
                -- Load current preset (index was adjusted by delete)
                local display = track:loadCurrentPreset()
                track:stopPlayback()
                if display then
                    displayModalTwoLines("Preset", display)
                end
            end
        end
    end
}

function displayStatusLine(jam)
    drawStatusLine(jam)
    ogui:flip()
end

function displayKnobs(jam)
    for i = 1, 4 do
        drawKnobBar(i, track:getKnob(i))
    end
    drawStatusLine(jam)
    ogui:flip()
end

function displayShiftMenu()
    for line = 1, 5 do
        local left_label = shift_labels[line]
        if line == 1 then
            local state = track:getSeqState()
            left_label = (state == "PLAYING") and "Stop" or "Play"
        end
        ogui:setLine(line, string.format("%-8s | %-8s", left_label, shift_labels[line + 5]))
    end
end

function displayModal(text)
    ogui:fillArea(10, 13, 108, 38, OGUI.COLOR_BLACK)
    ogui:box(10, 13, 108, 38, OGUI.COLOR_WHITE)
    ogui:println(20, 25, OGUI.SIZE_16, OGUI.COLOR_WHITE, text)
    ogui:flip()
end

function displayModalTwoLines(line1, line2)
    ogui:fillArea(10, 13, 108, 48, OGUI.COLOR_BLACK)
    ogui:box(10, 13, 108, 48, OGUI.COLOR_WHITE)
    ogui:println(20, 19, OGUI.SIZE_16, OGUI.COLOR_WHITE, line1)
    ogui:println(20, 40, OGUI.SIZE_16, OGUI.COLOR_WHITE, line2)
    ogui:flip()
end

function updateLED()
    local state = track:getSeqState()
    if state == "RECORDING" then
        ogui:led(OGUI.LED_RED)
    elseif state == "PLAYING" then
        ogui:led(OGUI.LED_GREEN)
    elseif state == "ARMED" then
        ogui:led(OGUI.LED_PURPLE)
    else
        ogui:led(OGUI.LED_OFF)
    end
end
