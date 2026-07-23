-- lib/midi_export.lua
-- Minimal Standard MIDI File writer for PLAY-multitrack.
-- Exports the four sequencer tracks as a Type 1 MIDI file.

local MidiExport = {}
MidiExport.__index = MidiExport

local function b(n)
    n = math.floor(n or 0) % 256
    return string.char(n)
end

local function u16be(n)
    n = math.floor(n or 0)
    return b(math.floor(n / 256)) .. b(n)
end

local function u32be(n)
    n = math.floor(n or 0)
    return b(math.floor(n / 16777216)) .. b(math.floor(n / 65536)) .. b(math.floor(n / 256)) .. b(n)
end

local function varlen(value)
    value = math.max(0, math.floor(value or 0))
    local bytes = { value % 128 }
    value = math.floor(value / 128)
    while value > 0 do
        table.insert(bytes, 1, (value % 128) + 128)
        value = math.floor(value / 128)
    end

    local out = {}
    for i = 1, #bytes do out[i] = b(bytes[i]) end
    return table.concat(out)
end

local function meta(delta, typ, data)
    return varlen(delta) .. b(0xFF) .. b(typ) .. varlen(#data) .. data
end

local function midi_event(delta, status, data1, data2)
    return varlen(delta) .. b(status) .. b(data1) .. b(data2)
end

local function clamp(n, lo, hi)
    n = math.floor((n or 0) + 0.5)
    if n < lo then return lo end
    if n > hi then return hi end
    return n
end

local function beat_to_tick(beat, ppq)
    return math.max(0, math.floor(((beat or 0) * ppq) + 0.5))
end

local function active_level_automation_seq(seqs, opts)
    opts = opts or {}
    if opts.level_automation_seq then return opts.level_automation_seq end

    local types = opts.track_types or _G.track_types
    local enabled = opts.knob_track_enabled or _G.knob_track_enabled
    if not types or not enabled then return nil end

    for i = 1, 4 do
        if enabled[i] and types[i] == "knobs" and seqs and seqs[i] then
            return seqs[i]
        end
    end
    return nil
end

local function level_value_at(seq, level_num, beat, fallback)
    local value = nil
    local wrap_value = nil

    for _, event in ipairs((seq and seq.events) or {}) do
        if tostring(event.type or "") == ("level" .. tostring(level_num)) then
            wrap_value = tonumber(event.value) or wrap_value
            if (event.time or 0) <= beat then
                value = tonumber(event.value) or value
            end
        end
    end

    if value == nil then value = wrap_value end
    if value == nil then value = fallback end
    value = tonumber(value) or 1
    if value < 0 then value = 0 end
    if value > 1 then value = 1 end
    return value
end

local function write_track(chunks)
    local data = table.concat(chunks)
    return "MTrk" .. u32be(#data) .. data
end

local function track_name_event(name)
    return meta(0, 0x03, tostring(name or "Track"))
end

local function build_tempo_track(opts)
    local bpm = tonumber(opts.bpm) or 120
    if bpm <= 0 then bpm = 120 end
    local mpqn = math.floor((60000000 / bpm) + 0.5)
    local beats_per_bar = clamp(opts.beats_per_bar or 4, 1, 32)

    local chunks = {}
    table.insert(chunks, track_name_event("PLAY-multitrack"))
    table.insert(chunks, meta(0, 0x51, b(math.floor(mpqn / 65536)) .. b(math.floor(mpqn / 256)) .. b(mpqn)))
    -- Time signature: numerator, denominator-as-power-of-two, MIDI clocks/metronome click, 32nd notes per quarter.
    table.insert(chunks, meta(0, 0x58, b(beats_per_bar) .. b(2) .. b(24) .. b(8)))
    table.insert(chunks, meta(0, 0x2F, ""))
    return write_track(chunks)
end

local function append_note_event(events, tick, order, status, note, velocity)
    table.insert(events, {
        tick = math.max(0, tick),
        order = order or 0,
        status = status,
        note = clamp(note, 0, 127),
        velocity = clamp(velocity, 0, 127)
    })
end

local function collect_track_events(seq, track_index, opts)
    local events = {}
    local ppq = opts.ppq or 480

    local base_level = 1
    if opts.track_levels and opts.track_levels[track_index] ~= nil then
        base_level = tonumber(opts.track_levels[track_index]) or 1
    end

    local automation_seq = active_level_automation_seq(opts.seqs or _G.seqs, opts)

    local loop_length = tonumber(seq and seq.loop_length) or 0
    if loop_length <= 0 then loop_length = tonumber(opts.loop_length) or 0 end

    for _, event in ipairs((seq and seq.events) or {}) do
        if event.type == "note" then
            local event_time = event.time or 0
            local tick = beat_to_tick(event_time, ppq)
            local note = event.note or 60
            local velocity = event.velocity or 0
            if velocity > 0 then
                local level = level_value_at(automation_seq, track_index, event_time, base_level)
                local scaled_velocity = clamp(velocity * level, 1, 127)
                append_note_event(events, tick, 1, 0x90, note, scaled_velocity)

                if event.duration and event.duration > 0 then
                    local off_beat = event_time + event.duration
                    if loop_length > 0 and off_beat > loop_length then off_beat = loop_length end
                    append_note_event(events, beat_to_tick(off_beat, ppq), 0, 0x80, note, 0)
                end
            else
                append_note_event(events, tick, 0, 0x80, note, 0)
            end
        end
    end

    if loop_length > 0 then
        local end_tick = beat_to_tick(loop_length, ppq)
        table.insert(events, {tick = end_tick, order = 9, end_marker = true})
    end

    table.sort(events, function(a, b)
        if a.tick == b.tick then
            return (a.order or 0) < (b.order or 0)
        end
        return a.tick < b.tick
    end)

    return events
end

local function build_note_track(seq, track_index, opts)
    local channel = 0 -- Keep exports compatible with the live MIDI-out behavior.
    local events = collect_track_events(seq, track_index, opts)
    local chunks = {}
    table.insert(chunks, track_name_event("Track " .. tostring(track_index)))

    local last_tick = 0
    local wrote_end_of_track = false
    for _, event in ipairs(events) do
        local delta = math.max(0, event.tick - last_tick)
        if event.end_marker then
            -- End Of Track is a real MIDI event; its delta-time must be attached
            -- directly to the FF 2F 00 meta event. Do not write a standalone
            -- delta byte sequence before it, because that creates an invalid SMF.
            table.insert(chunks, meta(delta, 0x2F, ""))
            last_tick = event.tick
            wrote_end_of_track = true
            break
        else
            table.insert(chunks, midi_event(delta, event.status + channel, event.note, event.velocity))
            last_tick = event.tick
        end
    end

    if not wrote_end_of_track then
        table.insert(chunks, meta(0, 0x2F, ""))
    end
    return write_track(chunks)
end

local function has_note_events(seqs)
    for _, seq in ipairs(seqs or {}) do
        for _, event in ipairs((seq and seq.events) or {}) do
            if event.type == "note" then return true end
        end
    end
    return false
end

function MidiExport.write(path, seqs, opts)
    opts = opts or {}
    opts.seqs = seqs
    if not path or path == "" then return false, "No path" end
    if not has_note_events(seqs) then return false, "No notes" end

    local tracks = {}
    table.insert(tracks, build_tempo_track(opts))
    for i = 1, 4 do
        table.insert(tracks, build_note_track(seqs[i], i, opts))
    end

    local header = "MThd" .. u32be(6) .. u16be(1) .. u16be(#tracks) .. u16be(opts.ppq or 480)
    local file, err = io.open(path, "wb")
    if not file then return false, err or "Open failed" end
    file:write(header)
    for _, track in ipairs(tracks) do file:write(track) end
    file:close()
    return true, path
end

return { MidiExport = MidiExport }
