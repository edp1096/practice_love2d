local sfxr = require "vendor.sfxr"

local pcm = {}

local myPreset = {
    envelope = { sustain = 0.0978, decay = 0.19266, },
    highpass = { cutoff = 0.08938, },
    lowpass = { cutoff = 0.66173, },
    waveform = sfxr.WAVEFORM.SINE,     -- WAVEFORM.SQUARE = 0, WAVEFORM.SAW = 1, WAVEFORM.SINE = 2, WAVEFORM.NOISE = 3
    frequency = { slide = 0.25515, start = 0.37235, },
}

local function deepMerge(target, source)
    for k, v in pairs(source) do
        if type(v) == "table" then
            if type(target[k]) == "table" then
                deepMerge(target[k], v)
            else
                target[k] = v
            end
        else
            target[k] = v
        end
    end

    return target
end

function pcm:PlaySound()
    local sound = sfxr.newSound()
    sound:resetParameters()
    sound = deepMerge(sound, myPreset)
    sound:sanitizeParameters()

    local sounddata = sound:generateSoundData()
    local source = love.audio.newSource(sounddata)
    source:play()
end

return pcm
