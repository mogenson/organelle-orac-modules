-- original octave cascade from pocket piano

require("utils")

function init(jam)
    notes = {}                      -- buffer to hold active notes (up to 4 voices)
    shifter_l = 0                   -- main counter (0-3)
    shifter_count2 = 0              -- pattern counter (0-2)
    octave_shift = {0, 0, 0, 0}     -- octave shift for each voice
end

function chris_shifter(jam)
    -- Increment and wrap main counter
    shifter_l = shifter_l + 1
    shifter_l = shifter_l % 4
    
    -- Increment pattern counter
    shifter_count2 = shifter_count2 + 1
    if shifter_count2 > 2 then
        shifter_count2 = 0
    end
    
    -- Calculate octave shifts based on pattern
    if shifter_count2 == 0 then
        -- Pattern 0: each voice offset by its index
        for i = 0, 3 do
            octave_shift[i + 1] = (shifter_l + i) % 4
        end
    elseif shifter_count2 == 1 then
        -- Pattern 1: odd/even voices paired
        for i = 0, 3 do
            local offset = ((i % 2) * 2)  -- 0 for even, 2 for odd
            octave_shift[i + 1] = (shifter_l + offset) % 4
        end
    elseif shifter_count2 == 2 then
        -- Pattern 2: all voices same octave
        for i = 0, 3 do
            octave_shift[i + 1] = shifter_l
        end
    end
    
    -- Play all active voices with their octave shifts
    for i = 1, math.min(4, #notes) do
        if notes[i] then
            -- Original formula: (note + 24) - (12 * octave_shift)
            local shifted_note = (notes[i] + 24) - (12 * octave_shift[i])
            jam.noteout(shifted_note, 100, 1/4 * 0.8)
        end
    end
end

function tick(jam)
    if #notes == 0 then return end
    
    -- Trigger on sixteenth notes
    if jam.every(1/4) then
        chris_shifter(jam)
    end
end

function notein(jam, n, v)
    if v > 0 then
        -- Add note if not already present and we have room for 4 voices
        local exists = false
        for i, note in ipairs(notes) do
            if note == n then
                exists = true
                break
            end
        end
        if not exists and #notes < 4 then
            table.insert(notes, n)
        end
    else
        -- Remove note on note-off
        for i, note in ipairs(notes) do
            if note == n then
                table.remove(notes, i)
                break
            end
        end
    end
end
