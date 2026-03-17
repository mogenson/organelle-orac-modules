-- notes fire at fixed polyrhythmic rates based on order pressed
-- 1st: 1 beat, 2nd: 3/4, 3rd: 2/3, 4th: 1/2, then cycles

function init(jam)
    notes = {}
    note_index = 0  -- tracks order of notes pressed
    rates = {1, 0.75, 2/3, 0.5}
end

function notein(jam, n, v)
    if v > 0 then
        local exists = false
        for i, note_data in ipairs(notes) do
            if note_data.note == n then
                exists = true
                break
            end
        end
        if not exists then
            -- Assign rate based on order pressed (cycles through 1-4)
            local rate = rates[(note_index % 4) + 1]
            note_index = note_index + 1

            table.insert(notes, {
                note = n,
                rate = rate
            })
        end
    else
        for i, note_data in ipairs(notes) do
            if note_data.note == n then
                table.remove(notes, i)
                break
            end
        end
        -- Reset index when all notes released
        if #notes == 0 then
            note_index = 0
        end
    end
end

function tick(jam)
    for _, note_data in ipairs(notes) do
        if jam.every(note_data.rate) then
            local vel = 70 + math.random(-15, 25)
            jam.noteout(note_data.note, vel, note_data.rate * 0.6)
        end
    end
end
