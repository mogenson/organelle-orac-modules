-- rubato random notes with LFO-controlled timing
require("lib/utils")

function init(jam)
    notes = {}
    next_note_beat = 0
    next_note_beat2 = 0
end

function notein(jam, n, v)
    if v > 0 then
        local exists = false
        for i, note in ipairs(notes) do
            if note == n then
                exists = true
                break
            end
        end
        if not exists then
            table.insert(notes, n)
        end
    else
        for i, note in ipairs(notes) do
            if note == n then
                table.remove(notes, i)
                break
            end
        end
        -- Reset when all notes released
        if #notes == 0 then
            next_note_beat = 0
        end
    end
end

function tick(jam)
    if #notes == 0 then return end

    local current_beat = jam.tc / jam.tpb

    if current_beat >= next_note_beat then

        -- LFO cycles over 10 beats, varies interval from 0.25 to 1 beat
        local lfo = math.sin(2 * math.pi * current_beat / 10)
        local interval = 0.625 - 0.375 * lfo  -- fast (0.25) at peak, slow (1) at trough

        -- Pick a random note
        local note = notes[math.random(#notes)]
        jam.noteout(note, choose({60, 100}), interval * 0.6)
        
        next_note_beat = current_beat + interval
    end
    
    if current_beat >= next_note_beat2 then
        
        -- LFO cycles over 10 beats, varies interval from 0.25 to 1 beat
        local lfo = math.sin(2 * math.pi * current_beat / 13)
        local interval = 0.5 - 0.4 * lfo  -- fast (0.25) at peak, slow (1) at trough
        -- Pick a random note
        
        local note = notes[math.random(#notes)]
        jam.noteout(note + 12, choose({60, 100}), interval * 0.6)
        
        next_note_beat2 = current_beat + interval
    end
end
