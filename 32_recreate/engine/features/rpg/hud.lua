local feature = {
    id = "rpg.hud",
    requires = {
        "engine.features.rpg.equipment",
        "engine.features.rpg.quest",
        "engine.features.rpg.economy",
        "engine.features.rpg.locale",
    },
}

local hud_system = {
    id = "rpg.hud.draw",
    draw_order = 160,
    draw_space = "screen",
}

local function localizedItemName(world, locale, item_id)
    local item = world.host.catalog:get(item_id)
    if not item then return item_id end
    return item.name_key and
        locale:text(item.name_key, item.name) or item.name or item.id
end

function hud_system:draw(world)
    local snapshot = world:snapshot()
    local locale = world:service("locale")
    local view = world:view()
    local width = 286
    local x = view.width - width - 12
    local y = 12
    local lines = {}
    lines[#lines + 1] = string.format(
        "%s: %d",
        locale:text("ui.currency", "Currency"),
        snapshot.currency.balance
    )

    local player
    for _, entity in ipairs(snapshot.entities) do
        for _, tag in ipairs(entity.tags) do
            if tag == "player" then player = entity end
        end
    end
    if player and player.stats then
        lines[#lines + 1] = string.format(
            "ATK %g   DEF %g   MOVE %.2f",
            player.stats.attack,
            player.stats.defense,
            player.stats.move_speed
        )
    end
    for _, entry in ipairs(player and player.equipment or {}) do
        if entry.item_id then
            lines[#lines + 1] = string.format(
                "%s: %s",
                locale:text(
                    "ui.slot." .. entry.slot,
                    entry.slot
                ),
                localizedItemName(world, locale, entry.item_id)
            )
        end
    end
    for _, quest in ipairs(snapshot.quests or {}) do
        local progress = {}
        for _, objective in ipairs(quest.objectives) do
            progress[#progress + 1] = string.format(
                "%d/%d",
                objective.count,
                objective.goal
            )
        end
        lines[#lines + 1] = string.format(
            "%s [%s] %s",
            quest.name or quest.id,
            locale:text(
                "ui.quest_status." .. quest.status,
                quest.status
            ),
            table.concat(progress, ", ")
        )
    end
    for _, item in ipairs(snapshot.inventory or {}) do
        lines[#lines + 1] = string.format(
            "%s x%d",
            item.name or item.item_id,
            item.count
        )
    end

    local height = 18 + #lines * 19
    love.graphics.setColor(0.02, 0.025, 0.04, 0.82)
    love.graphics.rectangle("fill", x, y, width, height, 8, 8)
    love.graphics.setColor(0.72, 0.9, 1, 1)
    for index, line in ipairs(lines) do
        love.graphics.print(line, x + 12, y + 8 + (index - 1) * 19)
    end
end

function feature:register(host)
    host:registerSystem(hud_system)
end

return feature
