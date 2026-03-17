function init(jam)
    notes = {}
    long_note_this_beat = nil
    last_decision_beat = -1
end

function notein(jam, n, v) 
    -- Always pass through the note immediately
    --jam.noteout(n, v)
    
    if v > 0 then
        -- Note-on: add to buffer (avoid duplicates)
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
        -- Note-off: remove from buffer
        for i, note in ipairs(notes) do
            if note == n then
                table.remove(notes, i)
                break
            end
        end
        -- Reset state when all notes released
        if #notes == 0 then
            long_note_this_beat = nil
            last_decision_beat = -1
        end
    end
end

function tick(jam)
    if #notes > 0 then
        local current_beat = math.floor(jam.tc / jam.tpb)
        
        -- Make decision once per beat
        if current_beat ~= last_decision_beat then
            last_decision_beat = current_beat
            
            if math.random() < 0.33 then
                long_note_this_beat = notes[math.random(#notes)]
            else
                long_note_this_beat = nil
            end
        end
        
        -- Play notes 1-4 with staggered 16th note offsets
        for i = 1, math.min(4, #notes) do
            local note = notes[i]
            local offset_index = (i - 1) % 4
            local offset = offset_index * 0.25
            
            if jam.every(1, offset) then
                local duration = 0.18
                if note == long_note_this_beat then
                    duration = 0.2
                end
                
                jam.noteout(note, 100, duration)
            end
        end
        
        -- Play notes 5+ at 32nd note rate (twice as fast)
        if #notes > 4 then
            for i = 5, #notes do
                local note = notes[i]
                local offset_index = (i - 5) % 4  -- Reset offset pattern
                local offset = offset_index * 0.125  -- Half the offset (32nd spacing)
                
                -- Trigger every half beat (0.5) to play 32nd notes
                if jam.every(0.5, offset) then
                    local duration = 0.3
                    if note == long_note_this_beat then
                        duration = 0.2
                    end
                    
                    jam.noteout(note, 100, duration)
                end
            end
        end
    end
end