require("utils")

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
            local current_beat = jam.tc / jam.tpb
            
            -- Play first bounce immediately
            jam.noteout(n, 100, 0.1)
            
            table.insert(notes, {
                note = n,
                start_beat = current_beat,
                bounce_interval = 0.5 + randf(.1),
                next_bounce = current_beat + 0.5,
                min_bounce_count = 0,
                direction = "decreasing",
                velocity = 100
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
    local current_beat = jam.tc / jam.tpb
    
    -- Play octave up every beat for all held notes
    if jam.every(1) then
        for _, note_data in ipairs(notes) do
          -- jam.noteout(note_data.note + 12, 50, 0.33)
        end
    end
    
    for _, note_data in ipairs(notes) do
        -- Check if it's time for a bounce
        if current_beat >= note_data.next_bounce then
            -- Play the bounce with current velocity
            local vel = math.floor(note_data.velocity + 0.5)
            jam.noteout(note_data.note, vel, .1)
            
            -- Update bounce interval and velocity based on direction
            if note_data.direction == "decreasing" then
                note_data.bounce_interval = note_data.bounce_interval * 0.8
                note_data.velocity = note_data.velocity * 0.85
                
                -- Check if we hit minimum interval
                if note_data.bounce_interval < 0.1 then
                    note_data.bounce_interval = 0.1
                    note_data.min_bounce_count = note_data.min_bounce_count + 1
                    
                    -- After 12 bounces at minimum, start increasing
                    if note_data.min_bounce_count >= 12 then
                        note_data.direction = "increasing"
                        note_data.min_bounce_count = 0
                    end
                end
                
                -- Clamp velocity
                note_data.velocity = math.max(10, note_data.velocity)
                
            else  -- increasing
                note_data.bounce_interval = note_data.bounce_interval * 1.33
                note_data.velocity = note_data.velocity * 1.15
                
                -- Check if we hit maximum (0.5 beat)
                if note_data.bounce_interval >= 0.5 then
                    note_data.bounce_interval = 0.5
                    note_data.velocity = 100
                    note_data.direction = "decreasing"
                end
                
                -- Clamp velocity
                note_data.velocity = math.min(100, note_data.velocity)
            end
            
            note_data.next_bounce = current_beat + note_data.bounce_interval
        end
    end
end
