-- game/data/items/init.lua
-- Item type registry for game
-- All specific item types are defined here and injected into engine

local items = {}

-- Consumables
items.apple = require "game.data.items.consumables.apple"
items.orange = require "game.data.items.consumables.orange"
items.strawberry = require "game.data.items.consumables.strawberry"
items.small_potion = require "game.data.items.consumables.small_potion"
items.large_potion = require "game.data.items.consumables.large_potion"

-- Weapons
items.iron_sword = require "game.data.items.weapons.iron_sword"
items.iron_axe = require "game.data.items.weapons.iron_axe"
items.club = require "game.data.items.weapons.club"
items.staff = require "game.data.items.weapons.staff"

return items
