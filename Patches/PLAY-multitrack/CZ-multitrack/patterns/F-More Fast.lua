-- the more notes held down, the faster they play

require("utils")

function init(jam)
    notes = {}  -- held notes in order pressed
    index = 1
end

function tick(jam)
    if #notes > 0 and jam.every(1/#notes) then
        if index > #notes then index = 1 end
        jam.noteout(notes[index], 100, 1/#notes)
        index = index + 1
    end
end

function notein(jam, n, v)
    if v > 0 then
        -- Add note in order pressed
        table.insert(notes, n)
    else
        -- Remove note
        for i, note in ipairs(notes) do
            if note == n then
                table.remove(notes, i)
                if index > #notes then index = 1 end
                break
            end
        end
    end
end

function msgin(jam, ...)
end
