-- lib/organelle_track.lua
-- note flow: notein -> latch -> subjam arp -> sequencer -> output
local Sequencer = require("lib/sequencer").Sequencer
local Latch = require("lib/latch").Latch
local SubJam = require("lib/subjam")

local Track = {}
Track.__index = Track

function Track.new(jam, track_id, output_callback)
    local self = setmetatable({}, Track)
    
    self.jam = jam
    self.track_id = track_id
    self.output = output_callback or function() end
    self.transpose = 0
    self.knob_values = {0, 0, 0, 0}
    self.pattern_files = {}
    self.current_pattern_index = 0
    
    -- Sequencer outputs through our callback
    self.seq = Sequencer.new({
        tpb = jam.tpb,
        tc = jam.tc,  -- sync with global tick to avoid drift on reload
        output = function(type, ...)
            self.output(type, ...)
        end
    })
    
    -- Latch routes to pattern
    self.latch = Latch.new(function(note, velocity)
        if self.pattern and self.pattern.notein then
            self.pattern.notein(note, velocity)
        end
        -- Do not bypass pattern note-offs into output/recording here.
        -- Patterns/SubJam already emit their own note-offs; duplicating them
        -- creates redundant Note Off events in recorded presets/MIDI export.
    end)
    
    self.pattern = nil
    
    -- Scan patterns
    self:scanPatterns()
    
    return self
end

function Track:tick()
    self.seq:tick()
    if self.pattern and self.pattern.tick then
        self.pattern.tick()
    end
end

function Track:notein(note, velocity)
    local transposed = note + self.transpose
    
    -- Route to latch (which routes to pattern)
    self.latch:notein(transposed, velocity)
end

-- don't transpose midi
function Track:midinotein(note, velocity)
    -- Route to latch (which routes to pattern)
    self.latch:notein(note, velocity)
end

function Track:setKnob(knob_num, value)
    self.knob_values[knob_num] = value
    
    -- Output knob change
    self.output("knobs", "knob" .. knob_num, value)

    -- Record to sequencer
    self.seq:recordKnob(knob_num, value)
end

function Track:getKnob(knob_num)
    return self.knob_values[knob_num]
end

function Track:transposeUp()
    self.transpose = math.min(24, self.transpose + 12)
    return self.transpose / 12  -- return octaves
end

function Track:transposeDown()
    self.transpose = math.max(-24, self.transpose - 12)
    return self.transpose / 12  -- return octaves
end

function Track:getTranspose()
    return self.transpose / 12  -- return octaves
end

function Track:toggleLatch()
    self.latch:toggle()
    return self.latch.enabled
end

function Track:isLatchEnabled()
    return self.latch.enabled
end

-- Sequencer controls
function Track:togglePlayback()
    if self.seq:isPlaying() or self.seq:isOverdubbing() then
        self.seq:stop()
        return "stopped"
    elseif self.seq:isStopped() then
        if self.seq:hasEvents() then
            self.latch:disable()
            self.seq:playSync()
            return "playing"
        else
            return "empty"
        end
    elseif self.seq:isArmed() then
        self.seq:stop()
        return "stopped"
    end
end

function Track:startPlayback()
    self.seq:stop()
    if self.seq:hasEvents() then
        self.latch:disable()
        self.seq:playSync()
        return "playing"
    else
        return "empty"
    end
end

function Track:stopPlayback()
    self.seq:stop()
    return "stopped"
end

function Track:toggleArm()
    if self.seq:isStopped() or self.seq:isPlaying() then
        self.seq:stop()
        self.seq:arm()
        return "armed"
    elseif self.seq:isArmed() then
        self.seq:stop()
        return "stopped"
    elseif self.seq:isOverdubbing() then
        self.seq:endOverdub()
        return "playing"
    end
end

function Track:endRecording()
    if self.seq:isRecording() then
        self.seq:endRecording()
        self.latch:disable()
        self.seq:playSync()
        return "playing"
    end
end

function Track:startOverdub()
    if self.seq:isPlaying() then
        self.latch:disable()
        if self.seq:startOverdub() then
            return "overdub"
        end
    elseif self.seq:isOverdubbing() then
        return "overdub"
    elseif self.seq:isStopped() then
        return "stopped"
    end
    return nil
end

function Track:endOverdub()
    if self.seq:isOverdubbing() then
        self.seq:endOverdub()
        self.latch:disable()
        return "playing"
    end
    return nil
end

function Track:undoOverdub()
    if self.seq:undoOverdub() then
        self.latch:disable()
        return "undone"
    end
    return nil
end

function Track:getSeqState()
    return self.seq:getState()
end

function Track:hasEvents()
    return self.seq:hasEvents()
end

-- Pattern management
function Track:scanPatterns()
    self.pattern_files = {}
    local handle = io.popen("ls -1 patterns/*.lua 2>/dev/null | sort")
    if handle then
        for line in handle:lines() do
            table.insert(self.pattern_files, line)
        end
        handle:close()
    end
end

function Track:loadPattern(index)
    if index < 1 or index > #self.pattern_files then
        return nil
    end

    -- Save latched notes before switching
    local saved_latch = nil
    if self.latch.enabled and #self.latch:get_notes() > 0 then
        saved_latch = self.latch:get_notes_with_velocity()
        self.latch:disable()
    end

    -- Flush any scheduled note-offs from previous pattern
    self.output("flushnotes")

    local filepath = self.pattern_files[index]

    -- Load pattern as SubJam with output routed through our callback
    self.pattern = SubJam.load(filepath, self.jam, function(type, ...)
        if type == "note" then
            local note, velocity, duration = ...
            -- Record to sequencer
            self.seq:recordNote(note, velocity, duration)
            -- Output
            self.output("note", note, velocity, duration)
        end
    end)

    self.current_pattern_index = index

    -- Recall latched notes so new pattern receives them
    if saved_latch then
        self.latch:recall(saved_latch)
    end

    -- Extract filename for display
    return filepath:match("([^/]+)%.lua$") or tostring(index)
end

function Track:getPatternCount()
    return #self.pattern_files
end

return { Track = Track }