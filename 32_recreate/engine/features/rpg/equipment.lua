local util = require "engine.core.util"
local Schema = require "engine.runtime.session_schema"

local feature = {
    id = "rpg.equipment",
    requires = {
        "engine.features.rpg.inventory",
        "engine.features.rpg.stats",
    },
}

local function componentOf(entity)
    return entity and entity.components and
        entity.components["rpg.equipment"] or nil
end

function feature:register(host)
    local inventory = host.services.inventory
    local stats = host.services.stats
    local session = host.services.session
    local state = session:registerSection("rpg.equipment", {
        version = 1,
        defaults = {owners = {}},
        validate = function(value)
            local valid, value_error = Schema.object(
                value,
                "rpg.equipment",
                {"owners"},
                {"owners"}
            )
            if not valid then return nil, value_error end
            return Schema.map(
                value.owners,
                "rpg.equipment.owners",
                function(owner, path)
                    return Schema.map(
                        owner,
                        path,
                        function(item_id, item_path)
                            return Schema.string(item_id, item_path)
                        end
                    )
                end
            )
        end,
    })
    local equipment = {}

    inventory:registerItemSection("equipment", {
        validate = function(config, validator, path)
            if not validator:table(config, path, true) then return end
            validator:keys(config, {"slot", "modifiers"}, path)
            validator:string(
                config.slot,
                path .. ".slot",
                true
            )
            stats:validateModifiers(
                config.modifiers,
                validator,
                path .. ".modifiers"
            )
        end,
    })

    local function ownerState(component)
        local owner = state.owners[component.loadout]
        if not owner then
            owner = {}
            state.owners[component.loadout] = owner
        end
        return owner
    end

    function equipment:equipped(entity, slot)
        local component = componentOf(entity)
        if not component then return nil end
        return ownerState(component)[slot]
    end

    function equipment:equip(world, entity, item_id)
        local component = componentOf(entity)
        if not component then
            return nil, "target has no rpg.equipment component"
        end
        local item = host.catalog:get(item_id)
        local config = item and item.kind == "item" and
            item.equipment or nil
        if not config then
            return nil, "item '" .. tostring(item_id) ..
                "' is not equipment"
        end
        if not component.slot_set[config.slot] then
            return nil, string.format(
                "loadout '%s' has no slot '%s'",
                component.loadout,
                config.slot
            )
        end
        if inventory:count(item_id) < 1 then
            return nil, "item '" .. item_id .. "' is not in inventory"
        end
        local owner = ownerState(component)
        local previous = owner[config.slot]
        if previous == item_id then
            return {
                applied = false,
                item_id = item_id,
                slot = config.slot,
                previous = previous,
            }
        end
        owner[config.slot] = item_id
        world.events:emit("equipment.changed", {
            entity_id = entity.id,
            loadout = component.loadout,
            slot = config.slot,
            item_id = item_id,
            previous = previous,
        })
        return {
            applied = true,
            item_id = item_id,
            slot = config.slot,
            previous = previous,
        }
    end

    function equipment:unequip(world, entity, slot)
        local component = componentOf(entity)
        if not component then
            return nil, "target has no rpg.equipment component"
        end
        if not component.slot_set[slot] then
            return nil, string.format(
                "loadout '%s' has no slot '%s'",
                component.loadout,
                tostring(slot)
            )
        end
        local owner = ownerState(component)
        local previous = owner[slot]
        owner[slot] = nil
        if previous then
            world.events:emit("equipment.changed", {
                entity_id = entity.id,
                loadout = component.loadout,
                slot = slot,
                previous = previous,
            })
        end
        return {
            applied = previous ~= nil,
            slot = slot,
            previous = previous,
        }
    end

    stats:registerProvider("rpg.equipment", function(_, entity, stat)
        local component = componentOf(entity)
        if not component then return 0 end
        local result = 0
        local owner = ownerState(component)
        for _, slot in ipairs(component.slots) do
            local item_id = owner[slot]
            local item = item_id and host.catalog:get(item_id)
            local modifiers = item and item.equipment and
                item.equipment.modifiers
            result = result +
                (modifiers and modifiers[stat] or 0)
        end
        return result
    end)

    inventory:registerRemovalGuard(
        "rpg.equipment",
        function(item_id, amount, previous)
            local equipped_count = 0
            for _, owner in pairs(state.owners) do
                for _, equipped_id in pairs(owner) do
                    if equipped_id == item_id then
                        equipped_count = equipped_count + 1
                    end
                end
            end
            if previous - amount < equipped_count then
                return false, "cannot remove equipped item '" ..
                    item_id .. "'"
            end
            return true
        end
    )

    host:registerComponent("rpg.equipment", {
        requires = {"rpg.stats"},
        validate = function(config, validator, path)
            if not validator:table(config, path, true) then return end
            validator:keys(config, {"loadout", "slots"}, path)
            validator:string(
                config.loadout,
                path .. ".loadout",
                true
            )
            local slots = validator:array(
                config.slots,
                path .. ".slots",
                true
            )
            if slots and #slots == 0 then
                validator:error(
                    path .. ".slots",
                    "must contain at least one slot"
                )
            end
            local seen = {}
            for index, slot in ipairs(slots or {}) do
                local slot_path = string.format(
                    "%s.slots[%d]",
                    path,
                    index
                )
                slot = validator:string(slot, slot_path, true)
                if slot and seen[slot] then
                    validator:error(
                        slot_path,
                        "duplicates another equipment slot"
                    )
                elseif slot then
                    seen[slot] = true
                end
            end
        end,
        create = function(config)
            local slots = util.deepCopy(config.slots)
            local slot_set = {}
            for _, slot in ipairs(slots) do slot_set[slot] = true end
            return {
                loadout = config.loadout,
                slots = slots,
                slot_set = slot_set,
            }
        end,
    })

    host.rules:registerAction("equip_item", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "item"}, path)
            local item = validator:reference(
                action.item,
                "item",
                path .. ".item"
            )
            if item and not item.equipment then
                validator:error(
                    path .. ".item",
                    "references an item without equipment data"
                )
            end
        end,
        execute = function(action, context)
            local target = context.target or
                context.world:findByTag("player")[1]
            return equipment:equip(
                context.world,
                target,
                action.item
            )
        end,
    })
    host.rules:registerAction("unequip_slot", {
        validate = function(action, validator, path)
            validator:keys(action, {"type", "slot"}, path)
            validator:string(action.slot, path .. ".slot", true)
        end,
        execute = function(action, context)
            local target = context.target or
                context.world:findByTag("player")[1]
            return equipment:unequip(
                context.world,
                target,
                action.slot
            )
        end,
    })
    host.rules:registerCondition("item_equipped", {
        validate = function(condition, validator, path)
            validator:keys(
                condition,
                {"type", "item", "slot"},
                path
            )
            validator:reference(
                condition.item,
                "item",
                path .. ".item"
            )
            validator:string(
                condition.slot,
                path .. ".slot",
                false
            )
        end,
        evaluate = function(condition, context)
            local target = context.target
            local component = componentOf(target)
            if not component then return false end
            local owner = ownerState(component)
            if condition.slot then
                return owner[condition.slot] == condition.item
            end
            for _, item_id in pairs(owner) do
                if item_id == condition.item then return true end
            end
            return false
        end,
    })

    host:registerBootValidator("rpg.equipment.session", function()
        for _, owner in pairs(state.owners) do
            for slot, item_id in pairs(owner) do
                local item = host.catalog:get(item_id)
                if not item or item.kind ~= "item" or
                   not item.equipment then
                    return nil, "equipment save references missing " ..
                        "equipment item '" .. item_id .. "'"
                end
                if item.equipment.slot ~= slot then
                    return nil, string.format(
                        "equipment save puts '%s' in incompatible slot '%s'",
                        item_id,
                        slot
                    )
                end
                if inventory:count(item_id) < 1 then
                    return nil, "equipment save references item '" ..
                        item_id .. "' not present in inventory"
                end
            end
        end
        return true
    end)

    host:registerService("equipment", equipment)
    host:registerEntityInspector("rpg.equipment", function(entity)
        local component = componentOf(entity)
        if not component then return end
        local entries = {}
        local owner = ownerState(component)
        for _, slot in ipairs(component.slots) do
            entries[#entries + 1] = {
                slot = slot,
                item_id = owner[slot],
            }
        end
        return {
            equipment_loadout = component.loadout,
            equipment = entries,
        }
    end)
end

return feature
