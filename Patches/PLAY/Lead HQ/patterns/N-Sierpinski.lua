-- Rule 90 cellular automata (Sierpinski triangle)
-- 50 cells map to notes 40-89, active cells play nearest held note
-- Creates expanding/contracting triangular patterns with natural breathing

function init(jam)
    held_notes = {}

    -- 50 cells covering notes 40-89
    cells = {}
    for i = 1, 50 do cells[i] = 0 end
    cells[25] = 1  -- seed in middle
end

function reset_cells()
    for i = 1, 50 do cells[i] = 0 end
    cells[25] = 1  -- seed in middle
end

function notein(jam, n, v)
    if v > 0 then
        local was_empty = #held_notes == 0
        local exists = false
        for i, note in ipairs(held_notes) do
            if note == n then exists = true break end
        end
        if not exists then
            table.insert(held_notes, n)
            table.sort(held_notes)
            if was_empty then reset_cells() end
        end
    else
        for i, note in ipairs(held_notes) do
            if note == n then
                table.remove(held_notes, i)
                break
            end
        end
    end
end

-- Snap a note to the nearest held note
function filter_note(note)
    if #held_notes == 0 then return note end

    local closest = held_notes[1]
    local min_dist = math.abs(note - closest)

    -- Check held notes and their octave transpositions
    for _, held in ipairs(held_notes) do
        -- Check this note across several octaves
        for oct = -2, 2 do
            local candidate = held + (oct * 12)
            local dist = math.abs(note - candidate)
            if dist < min_dist then
                min_dist = dist
                closest = candidate
            end
        end
    end

    return closest
end

function rule90(l, c, r)
    -- XOR of left and right neighbors (Sierpinski triangle)
    return (l + r) % 2
end

function evolve()
    local new_cells = {}
    for i = 1, 50 do
        local left = cells[((i - 2) % 50) + 1]
        local center = cells[i]
        local right = cells[(i % 50) + 1]
        new_cells[i] = rule90(left, center, right)
    end
    cells = new_cells

    -- Reseed if all died
    local sum = 0
    for i = 1, 50 do sum = sum + cells[i] end
    if sum == 0 then
        cells[math.random(50)] = 1
    end
end

function tick(jam)
    if #held_notes == 0 then return end

    -- Every 16th note
    if jam.every(0.25) then
        -- Collect unique notes from active cells
        local notes_to_play = {}
        for i = 1, 50 do
            if cells[i] == 1 then
                local raw_note = 39 + i  -- cells 1-50 map to notes 40-89
                local note = filter_note(raw_note)
                notes_to_play[note] = true
            end
        end

        -- Play each unique note once
        for note, _ in pairs(notes_to_play) do
            local vel = math.random() < 0.5 and 60 or 100
            jam.noteout(note, vel, 0.15)
        end

        -- Evolve for next step
        evolve()
    end
end
