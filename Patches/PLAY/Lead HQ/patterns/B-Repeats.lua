-- repeater-arp.lua
-- Plays all held notes as a chord on sixteenth notes with varied velocity

require("lib/utils")

function init(jam)
    held_notes = {}
end

function notein(jam, note, velocity)
    if velocity > 0 then
        held_notes[note] = true
    else
        held_notes[note] = nil
    end
end

function tick(jam)
    -- Build array of currently held notes
    local notes = {}
    for note, _ in pairs(held_notes) do
        table.insert(notes, note)
    end
    
    -- Play all held notes together on sixteenth notes
    if #notes > 0 and jam.every(1/4) then
        for _, note in ipairs(notes) do
            jam.noteout(note, choose({60, 100}), 1/5)
        end
    end
end