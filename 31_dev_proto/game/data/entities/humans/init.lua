-- game/data/entities/humans/init.lua
-- Human entity type registry

local bandits = require "game.data.entities.humans.bandits"
local common = require "game.data.entities.humans.common"
local erratic = require "game.data.entities.humans.erratic"

return {
    bandits = bandits,
    common = common,
    erratic = erratic,
}
