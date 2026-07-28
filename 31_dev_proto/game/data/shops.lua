-- game/data/shops.lua
-- Shop data definitions (items, prices, stock)

local shops = {}

-- General store (shop1 merchant)
shops.general_store = {
    name = "General Store",
    name_key = "shops.general_store.name",

    -- Items for sale
    items = {
        -- Consumables
        { type = "small_potion", price = 30, stock = 10 },
        { type = "large_potion", price = 80, stock = 5 },
        { type = "apple", price = 15, stock = 20 },
        { type = "orange", price = 15, stock = 20 },
        { type = "strawberry", price = 20, stock = 15 },

        -- Weapons
        { type = "club", price = 50, stock = 3 },
        { type = "staff", price = 100, stock = 2 },
        { type = "iron_sword", price = 200, stock = 2 },
        { type = "iron_axe", price = 250, stock = 1 },
    },

    -- Sell rate (player gets this % of buy price when selling)
    sell_rate = 0.5,
}

-- Can add more shops later:
-- shops.blacksmith = { ... }
-- shops.potion_shop = { ... }

return shops
