-- lib/sequencer.lua
local Sequencer = {}
Sequencer.__index = Sequencer

function Sequencer.new(config)
    local self = setmetatable({}, Sequencer)
    config = config or {}

    self.tpb = config.tpb or 180
    self.output = config.output or function() end

    self.state = "STOPPED"
    self.events = {}
    self.recording_start_tick = 0
    self.playback_tick = 0
    self.loop_length = 0
    self.event_index = 1
    self.recording_held_notes = {}
    self.playback_held_notes = {}
    self.internal_tick = config.tc or 0
    self.sync_pending = false
    self.loop_synced_recording = false

    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.knob_overdub_touched = {}
    self.automation_record_last = {}
    self.undo_events = nil
    self.undo_loop_length = nil
    self.redo_events = nil
    self.redo_loop_length = nil

    self.pending_events = nil
    self.pending_loop_length = nil
    self.transition_pending = false

    return self
end

local function deepCopyEvents(events)
    local copy = {}
    for i, event in ipairs(events or {}) do
        local ev = {}
        for k, v in pairs(event) do
            ev[k] = v
        end
        copy[i] = ev
    end
    return copy
end

local function sortEvents(events)
    table.sort(events, function(a, b)
        if a.time == b.time then
            local a_is_off = a.type == "note" and a.velocity == 0
            local b_is_off = b.type == "note" and b.velocity == 0
            if a_is_off ~= b_is_off then
                return a_is_off
            end
            return (a.type or "") < (b.type or "")
        end
        return a.time < b.time
    end)
end

local function isAutomationEventType(event_type)
    if not event_type then return false end
    local t = tostring(event_type)
    return t:match("^knob%d$") ~= nil or t:match("^level%d$") ~= nil
end

function Sequencer:getCurrentLoopBeat()
    if self.loop_length <= 0 then return 0 end
    return (self.playback_tick / self.tpb) % self.loop_length
end

function Sequencer:getCurrentRecordBeat()
    if self.loop_synced_recording then
        return self.playback_tick / self.tpb
    end
    if self.state == "OVERDUB" then
        return self:getCurrentLoopBeat()
    end
    return math.max(0, (self.internal_tick - self.recording_start_tick) / self.tpb)
end

function Sequencer:releasePlaybackHeldNotes()
    for note, count in pairs(self.playback_held_notes) do
        for _ = 1, count do
            self.output("note", note, 0)
        end
    end
    self.playback_held_notes = {}
end

function Sequencer:rebuildEventIndex(current_beat)
    self.event_index = 1
    while self.event_index <= #self.events and self.events[self.event_index].time <= current_beat do
        self.event_index = self.event_index + 1
    end
end

function Sequencer:clearRedo()
    self.redo_events = nil
    self.redo_loop_length = nil
end

function Sequencer:commitOverdubEvents()
    local touched = self.knob_overdub_touched or {}
    local has_touched_automation = false
    for _, active in pairs(touched) do
        if active then
            has_touched_automation = true
            break
        end
    end

    if #self.overdub_events == 0 and not has_touched_automation then return false end

    if has_touched_automation then
        local filtered = {}
        for _, event in ipairs(self.events or {}) do
            if not (event.type and touched[tostring(event.type)]) then
                table.insert(filtered, event)
            end
        end
        self.events = filtered
    end

    for _, event in ipairs(self.overdub_events) do
        table.insert(self.events, event)
    end
    sortEvents(self.events)
    self.overdub_events = {}
    self.knob_overdub_touched = {}
    return true
end

function Sequencer:duplicateLoop()
    if self.loop_length <= 0 then return false end

    local original_length = self.loop_length
    if #self.events > 0 then
        local copies = {}
        for _, event in ipairs(self.events) do
            local copy = {}
            for k, v in pairs(event) do copy[k] = v end
            copy.time = copy.time + original_length
            table.insert(copies, copy)
        end
        for _, event in ipairs(copies) do
            table.insert(self.events, event)
        end
        sortEvents(self.events)
    end

    self.loop_length = original_length * 2
    self:clearRedo()

    if self.state == "PLAYING" or self.state == "OVERDUB" or self.state == "ARMED" then
        self:rebuildEventIndex(self:getCurrentLoopBeat())
    end
    return true
end

function Sequencer:halveLoop()
    if self.loop_length <= 0 then return false end

    local old_loop_length = self.loop_length
    local new_loop_length = old_loop_length / 2
    if new_loop_length <= 0 then return false end

    local current_beat = self:getCurrentLoopBeat()
    local wrapped_beat = current_beat % new_loop_length
    local new_events = {}
    local held_counts = {}

    sortEvents(self.events)

    for _, event in ipairs(self.events) do
        if event.time < new_loop_length or (event.time == new_loop_length and event.type == "note" and event.velocity == 0) then
            local copy = {}
            for k, v in pairs(event) do copy[k] = v end
            table.insert(new_events, copy)

            if event.type == "note" and not event.duration then
                if event.velocity > 0 then
                    held_counts[event.note] = (held_counts[event.note] or 0) + 1
                elseif event.velocity == 0 then
                    local count = held_counts[event.note] or 0
                    if count > 1 then
                        held_counts[event.note] = count - 1
                    else
                        held_counts[event.note] = nil
                    end
                end
            end
        end
    end

    for note, count in pairs(held_counts) do
        for _ = 1, count do
            table.insert(new_events, {
                time = new_loop_length,
                type = "note",
                note = note,
                velocity = 0
            })
        end
    end

    self:releasePlaybackHeldNotes()

    self.events = new_events
    self.loop_length = new_loop_length
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self:clearRedo()

    sortEvents(self.events)

    if self.state == "PLAYING" or self.state == "OVERDUB" or self.state == "ARMED" then
        self.playback_tick = math.floor(wrapped_beat * self.tpb)
        self:rebuildEventIndex(wrapped_beat)
    else
        self.playback_tick = 0
        self.event_index = 1
    end

    return true
end

function Sequencer:arm(preserve_loop_length)
    self:clear(preserve_loop_length)
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.loop_synced_recording = preserve_loop_length and self.loop_length > 0 or false
    self.state = "ARMED"
    return true
end

function Sequencer:startRecording()
    self.state = "RECORDING"
    self:clearRedo()

    if self.loop_synced_recording and self.loop_length > 0 then
        self.recording_start_tick = self.internal_tick
    else
        local ticks_into_beat = self.internal_tick % self.tpb
        local position_in_beat = ticks_into_beat / self.tpb

        if position_in_beat >= 0.9 then
            self.recording_start_tick = (math.floor(self.internal_tick / self.tpb) + 1) * self.tpb
        else
            self.recording_start_tick = math.floor(self.internal_tick / self.tpb) * self.tpb
        end
    end

    self.events = {}
    self.recording_held_notes = {}
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.automation_record_last = {}
end

function Sequencer:startOverdub()
    if self.state ~= "PLAYING" then return false end
    if self.loop_length <= 0 then return false end

    self.undo_events = deepCopyEvents(self.events)
    self.undo_loop_length = self.loop_length
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.knob_overdub_touched = {}
    self.automation_record_last = {}
    self:clearRedo()
    self.state = "OVERDUB"
    return true
end

function Sequencer:endOverdub()
    if self.state ~= "OVERDUB" then return false end

    local end_time = self:getCurrentLoopBeat()
    for note, _ in pairs(self.overdub_held_notes) do
        table.insert(self.overdub_events, {
            time = end_time,
            type = "note",
            note = note,
            velocity = 0
        })
    end
    self.overdub_held_notes = {}

    self:commitOverdubEvents()
    self.state = "PLAYING"
    return true
end

function Sequencer:undoOverdub()
    if not self.undo_events then return false end

    self.redo_events = deepCopyEvents(self.events)
    self.redo_loop_length = self.loop_length

    self.events = deepCopyEvents(self.undo_events)
    self.loop_length = self.undo_loop_length or self.loop_length
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.knob_overdub_touched = {}
    self.loop_synced_recording = false

    if self.state == "OVERDUB" then
        self.state = "PLAYING"
    end

    self:rebuildEventIndex(self:getCurrentLoopBeat())
    return true
end

function Sequencer:redoOverdub()
    if not self.redo_events then return false end

    self.undo_events = deepCopyEvents(self.events)
    self.undo_loop_length = self.loop_length

    self.events = deepCopyEvents(self.redo_events)
    self.loop_length = self.redo_loop_length or self.loop_length
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.loop_synced_recording = false
    self.redo_events = nil
    self.redo_loop_length = nil

    if self.state == "OVERDUB" then
        self.state = "PLAYING"
    end

    self:rebuildEventIndex(self:getCurrentLoopBeat())
    return true
end

function Sequencer:endRecording()
    if self.state ~= "RECORDING" then return end

    local current_beat = (self.internal_tick - self.recording_start_tick) / self.tpb
    if not self.loop_synced_recording then
        self.loop_length = math.floor(current_beat + 0.5)
        if self.loop_length == 0 then self.loop_length = 1 end
    end

    local noteoff_time
    if self.loop_synced_recording then
        noteoff_time = math.min(self.playback_tick / self.tpb, self.loop_length)
    else
        noteoff_time = self.loop_length
    end

    for note, _ in pairs(self.recording_held_notes) do
        table.insert(self.events, {
            time = noteoff_time,
            type = "note",
            note = note,
            velocity = 0
        })
    end
    self.recording_held_notes = {}

    if not self.loop_synced_recording then
        for i = #self.events, 1, -1 do
            if self.events[i].time > self.loop_length then
                self.events[i].time = self.loop_length
            else
                break
            end
        end
    else
        for _, event in ipairs(self.events) do
            if event.time > self.loop_length then
                event.time = event.time % self.loop_length
            end
        end
        sortEvents(self.events)
    end

    self.loop_synced_recording = false
    self:stop()
end

function Sequencer:play()
    if #self.events == 0 and self.loop_length <= 0 then return false end
    self.state = "PLAYING"
    self.playback_tick = 0
    self.event_index = 1
    self.playback_held_notes = {}
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.knob_overdub_touched = {}
    self.sync_pending = false
    return true
end

function Sequencer:playSync()
    if #self.events == 0 and self.loop_length <= 0 then return false end
    self.sync_pending = true
    return true
end

function Sequencer:stop()
    self:releasePlaybackHeldNotes()
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.knob_overdub_touched = {}
    self.automation_record_last = {}
    self.state = "STOPPED"
    self.sync_pending = false
    self.loop_synced_recording = false
end

function Sequencer:recordEvent(event)
    if self.state == "RECORDING" or self.state == "OVERDUB" then
        event.time = self:getCurrentRecordBeat()
        if self.loop_length > 0 then
            event.time = event.time % self.loop_length
        end

        if self.state == "OVERDUB" then
            table.insert(self.overdub_events, event)
        else
            table.insert(self.events, event)
        end
        return true
    end
    return false
end

function Sequencer:recordNote(note, velocity, duration)
    if self.state == "ARMED" and velocity > 0 then
        self:startRecording()
    end

    local recorded = self:recordEvent({
        type = "note",
        note = note,
        velocity = velocity,
        duration = duration
    })

    if recorded then
        local held_notes = (self.state == "OVERDUB") and self.overdub_held_notes or self.recording_held_notes
        if velocity > 0 and not duration then
            held_notes[note] = true
        elseif velocity == 0 then
            held_notes[note] = nil
        end
    end
end

function Sequencer:markAutomationTouched(event_type, value)
    if self.state ~= "OVERDUB" then return false end
    if not isAutomationEventType(event_type) then return false end

    self.knob_overdub_touched = self.knob_overdub_touched or {}
    local key = tostring(event_type)
    if self.knob_overdub_touched[key] then return false end

    self.knob_overdub_touched[key] = true
    table.insert(self.overdub_events, {
        time = 0,
        type = key,
        value = value
    })
    return true
end

function Sequencer:automationQuantize(event_type, value)
    local v = tonumber(value) or 0
    if v < 0 then v = 0 end
    if v > 1 then v = 1 end

    local key = tostring(event_type or "")
    local step = 1 / 1024
    if key:match("^level%d$") then
        -- Mixer levels do not need sub-1024 precision; this also keeps
        -- MIDI-export velocity automation compact.
        step = 1 / 256
    end

    return math.floor((v / step) + 0.5) * step
end

function Sequencer:shouldRecordAutomation(event_type, value, beat, force)
    if force then
        self.automation_record_last = self.automation_record_last or {}
        self.automation_record_last[tostring(event_type)] = {beat = beat or 0, value = tonumber(value) or 0, delta = 0}
        return true
    end

    self.automation_record_last = self.automation_record_last or {}
    local key = tostring(event_type)
    local v = tonumber(value) or 0
    local b = tonumber(beat) or 0
    local last = self.automation_record_last[key]

    if not last then
        self.automation_record_last[key] = {beat = b, value = v, delta = 0}
        return true
    end

    local delta = v - (last.value or 0)
    local abs_delta = math.abs(delta)
    local beat_delta = math.abs(b - (last.beat or 0))
    local last_delta = last.delta or 0
    local direction_changed = (delta > 0 and last_delta < 0) or (delta < 0 and last_delta > 0)

    local is_level = key:match("^level%d$") ~= nil

    -- Conservative for synth parameters, stronger for mixer levels.
    -- Large changes are written immediately; only tiny dense movement is reduced.
    local large_delta = is_level and 0.020 or 0.012
    local small_delta = is_level and 0.006 or 0.003
    local min_beat_gap = is_level and 0.060 or 0.025

    if abs_delta >= large_delta or (direction_changed and abs_delta >= small_delta) or (beat_delta >= min_beat_gap and abs_delta >= small_delta) then
        self.automation_record_last[key] = {beat = b, value = v, delta = delta}
        return true
    end

    return false
end

function Sequencer:recordAutomationEvent(event_type, value, beat)
    local target = (self.state == "OVERDUB") and self.overdub_events or self.events
    if not target then return false end

    local key = tostring(event_type)
    local t = tonumber(beat) or 0
    local v = value

    -- Coalesce repeated writes for the same automation lane in the same tick.
    -- This keeps only the last value of a burst without altering timing.
    for i = #target, 1, -1 do
        local event = target[i]
        if not event then break end
        if event.type == key and math.abs((event.time or 0) - t) < 0.000001 then
            event.value = v
            return true
        end
        if math.abs((event.time or 0) - t) > 0.000001 then
            break
        end
    end

    table.insert(target, {
        time = t,
        type = key,
        value = v
    })
    return true
end

function Sequencer:recordAutomation(event_type, value)
    if self.state == "ARMED" then
        self:startRecording()
    end

    local current_beat = self:getCurrentRecordBeat()
    local key = tostring(event_type)
    local stored_value = self:automationQuantize(key, value)

    local first_touch = false
    if self.state == "OVERDUB" and isAutomationEventType(key) then
        first_touch = self:markAutomationTouched(key, stored_value)
    end

    if first_touch then
        self:shouldRecordAutomation(key, stored_value, current_beat, true)
        if current_beat <= 0.001 then
            return true
        end
    elseif isAutomationEventType(key) then
        if not self:shouldRecordAutomation(key, stored_value, current_beat, false) then
            return false
        end
    end

    return self:recordAutomationEvent(key, stored_value, current_beat)
end

function Sequencer:recordKnob(knob_num, value)
    return self:recordAutomation("knob" .. knob_num, value)
end

function Sequencer:recordLevel(level_num, value)
    return self:recordAutomation("level" .. level_num, value)
end

local function is_beat_boundary(tick, tpb)
    return tick % tpb == 0
end

function Sequencer:playEvent(event)
    if event.type == "note" then
        self.output("note", event.note, event.velocity, event.duration)
        if event.velocity > 0 and not event.duration then
            self.playback_held_notes[event.note] = (self.playback_held_notes[event.note] or 0) + 1
        elseif event.velocity == 0 then
            local count = self.playback_held_notes[event.note] or 0
            if count > 1 then
                self.playback_held_notes[event.note] = count - 1
            else
                self.playback_held_notes[event.note] = nil
            end
        end
    elseif isAutomationEventType(event.type) then
        local key = tostring(event.type)
        if not (self.state == "OVERDUB" and self.knob_overdub_touched and self.knob_overdub_touched[key]) then
            self.output("knobs", event.type, event.value)
        end
    end
end

function Sequencer:tick()
    self.internal_tick = self.internal_tick + 1

    if self.sync_pending then
        if is_beat_boundary(self.internal_tick, self.tpb) then
            self.state = "PLAYING"
            self.playback_tick = 0
            self.event_index = 1
            self.playback_held_notes = {}
            self.sync_pending = false
        end
        return
    end

    if self.state ~= "PLAYING" and self.state ~= "OVERDUB" then return end

    local current_beat = self.playback_tick / self.tpb
    while self.event_index <= #self.events do
        local event = self.events[self.event_index]
        if event.time <= current_beat then
            self:playEvent(event)
            self.event_index = self.event_index + 1
        else
            break
        end
    end

    self.playback_tick = self.playback_tick + 1

    local next_beat = self.playback_tick / self.tpb
    if self.loop_length > 0 and next_beat >= self.loop_length then
        while self.event_index <= #self.events do
            self:playEvent(self.events[self.event_index])
            self.event_index = self.event_index + 1
        end

        self:releasePlaybackHeldNotes()

        if self.transition_pending then
            self.events = self.pending_events
            self.loop_length = self.pending_loop_length
            self.pending_events = nil
            self.pending_loop_length = nil
            self.transition_pending = false
        end

        if self.state == "OVERDUB" then
            self:commitOverdubEvents()
        end

        self.playback_tick = 0
        self.event_index = 1
    end
end

function Sequencer:isRecording() return self.state == "RECORDING" end
function Sequencer:isOverdubbing() return self.state == "OVERDUB" end
function Sequencer:isPlaying() return self.state == "PLAYING" end
function Sequencer:isArmed() return self.state == "ARMED" end
function Sequencer:isStopped() return self.state == "STOPPED" end
function Sequencer:isSyncing() return self.sync_pending end
function Sequencer:hasEvents() return #self.events > 0 end
function Sequencer:getState() if self.sync_pending then return "SYNCING" end return self.state end

function Sequencer:clear(preserve_loop_length)
    self.events = {}
    if not preserve_loop_length then
        self.loop_length = 0
        self.playback_tick = 0
    end
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.knob_overdub_touched = {}
    self.automation_record_last = {}
    self.undo_events = nil
    self.undo_loop_length = nil
    self.redo_events = nil
    self.redo_loop_length = nil
    self.loop_synced_recording = false
end

function Sequencer:serialize()
    if #self.events == 0 then return nil end
    return {
        events = self.events,
        loop_length = self.loop_length
    }
end

function Sequencer:deserialize(data, immediate)
    if not data then
        self:clear()
        return
    end

    if self.state == "PLAYING" and not immediate then
        self.pending_events = data.events or {}
        self.pending_loop_length = data.loop_length or 0
        self.transition_pending = true
        return
    end

    self.events = data.events or {}
    self.loop_length = data.loop_length or 0
    self.playback_tick = 0
    self.event_index = 1
    self.state = "STOPPED"
    self.sync_pending = false
    self.transition_pending = false
    self.overdub_events = {}
    self.overdub_held_notes = {}
    self.knob_overdub_touched = {}
    self.automation_record_last = {}
    self.undo_events = nil
    self.undo_loop_length = nil
    self.redo_events = nil
    self.redo_loop_length = nil
    self.loop_synced_recording = false
end

return {
    Sequencer = Sequencer
}