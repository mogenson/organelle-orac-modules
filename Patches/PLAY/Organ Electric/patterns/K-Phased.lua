-- two voices cycling through chord, phasing in and out

require("utils")

function init(jam)
    notes = {}
    index1 = 1
    index2 = 1
end

function tick(jam)
    if #notes == 0 then return end

    -- Voice 1: every 16th note (1/4 beat) 
    if jam.every(1/4) then
        if index1 > #notes then index1 = 1 end
        jam.noteout(notes[index1], 100, 0.2)
        index1 = index1 + 1
    end

    -- Voice 2: every 16th + 1/128 (slightly slower, phases over time)
    if jam.every(1/4 + 1/128) then
        if index2 > #notes then index2 = 1 end
        jam.noteout(notes[index2], 80, 0.2)
        index2 = index2 + 1
    end
end

function notein(jam, n, v)
    if v > 0 then
        table.insert(notes, n)
        table.sort(notes)
    else
        for i, note in ipairs(notes) do
            if note == n then
                table.remove(notes, i)
                if index1 > #notes then index1 = 1 end
                if index2 > #notes then index2 = 1 end
                break
            end
        end
        -- Reset when all notes released
        if #notes == 0 then
            index1 = 1
            index2 = 1
        end
    end
end

function msgin(jam, ...)
end
