function init(jam)
    -- Initialize state
end

function tick(jam)
    -- Called every tick - generate music here
end

function notein(jam, note, velocity)
    -- Handle incoming MIDI
    jam.noteout(note,velocity)
    -- print(note)
end

