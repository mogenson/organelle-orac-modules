
-- Constant 16th notes at 0.25 beat intervals
-- Each note has its own independent oscillation rate (3-24 sixteenth notes for a complete cycle)
-- Random starting velocity between 10-100
-- Random starting direction (some start climbing, others descending)

function init(jam)
    notes = {}
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
            table.insert(notes, {
                note = n,
                oscillation_rate = math.random(3, 24),  -- Changed from 9-19 to 3-24
                current_velocity = math.random(10, 100),  -- Changed from 40-100 to 10-100
                velocity_direction = (math.random() < 0.5) and 1 or -1,
                step_count = 0
            })
        end
    else
        jam.noteout(n, v)
        
        for i, note_data in ipairs(notes) do
            if note_data.note == n then
                table.remove(notes, i)
                break
            end
        end
    end
end

function tick(jam)
    if #notes > 0 then
        local num = 0
        for _, note_data in ipairs(notes) do
            num = num + 1
            if jam.every(.25 * (1+ num * .01)) then
                -- Round velocity to nearest integer
                local velocity = math.floor(note_data.current_velocity + 0.5)
                
                jam.noteout(note_data.note, velocity, 0.2)
                
                local velocity_range = 90  -- Changed from 60 to 90 (100 - 10)
                local velocity_step = velocity_range / (note_data.oscillation_rate / 2)
                
                note_data.current_velocity = note_data.current_velocity + (velocity_step * note_data.velocity_direction)
                
                if note_data.current_velocity >= 100 then
                    note_data.current_velocity = 100
                    note_data.velocity_direction = -1
                elseif note_data.current_velocity <= 10 then  -- Changed from 40 to 10
                    note_data.current_velocity = 10
                    note_data.velocity_direction = 1
                end
                
                note_data.step_count = note_data.step_count + 1
            end
        end
    end
end
