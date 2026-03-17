-- up down arpeggio over held notes

require("utils")

function init(jam)
    notes = {}
    index = 1
    direction = 1
end

function tick(jam)
    if #notes > 0 and jam.every(1/4) then

        local pattern = {}
        for _, note in ipairs(notes) do
            table.insert(pattern, note)
        end

        jam.noteout(pattern[index], 100, 0.2)

        index = index + direction

        -- Handle single note case - just stay on it
        if #pattern == 1 then
            index = 1
        -- Bounce at ends
        elseif index > #pattern then
            index = #pattern - 1
            direction = -1
        elseif index < 1 then
            index = 2
            direction = 1
        end
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
                if index > #notes then index = math.max(1, #notes) end
                break
            end
        end
        if #notes == 0 then
            index = 1
            direction = 1
        end
    end
end

