-- game/data/locales/en.lua
-- English translations

return {
    en = {
        -- Main Menu
        menu = {
            continue = "Continue",
            new_game = "New Game",
            load_game = "Load Game",
            settings = "Settings",
            quit = "Quit",
            quit_to_menu = "Quit to Menu",
        },

        -- Pause Menu
        pause = {
            title = "PAUSED",
            resume = "Resume",
            restart_here = "Restart from Here",
            load_last_save = "Load Last Save",
        },

        -- Game Over
        gameover = {
            title = "GAME OVER",
        },

        -- Ending
        ending = {
            title = "CONGRATULATIONS!",
        },

        -- Settings
        settings = {
            title = "Settings",
            resolution = "Resolution",
            fullscreen = "Fullscreen",
            monitor = "Monitor",
            master_volume = "Master Volume",
            bgm_volume = "BGM Volume",
            sfx_volume = "SFX Volume",
            mute = "Mute",
            vibration = "Vibration",
            vibration_strength = "Vibration Strength",
            deadzone = "Deadzone",
            mobile_vibration = "Mobile Vibration",
            language = "Language",
        },

        -- Shop UI
        shop = {
            buy = "Buy",
            sell = "Sell",
            ok = "OK",
            cancel = "Cancel",
            gold = "Gold",
            stock = "Stock",
            quantity = "Qty",
            total = "Total",
            get = "Get",
            purchased = "Purchased %{count}x %{item}",
            sold = "Sold %{count}x %{item}",
            not_enough_gold = "Not enough gold",
            out_of_stock = "Out of stock",
            no_items = "No items",
            nothing_in_stock = "Nothing in stock",
            no_items_to_sell = "No items to sell",
            hint_select = "Select",
            hint_close = "Close",
            hint_tab = "Tab",
            hint_qty = "Qty",
            hint_qty_10 = "+/-10",
        },

        -- HUD
        hud = {
            level = "Lv",
            gold = "Gold",
            hp = "HP",
            exp = "EXP",
            invincible = "INVINCIBLE",
            dodging = "DODGING",
            evading = "EVADING",
            parry_ready = "PARRY READY!",
            parry_cd = "Parry CD",
            dodge = "Dodge",
            evade = "Evade",
            dodge_evade = "Dodge/Evade",
            parry = "PARRY!",
            perfect_parry = "PERFECT PARRY!",
        },

        -- Save/Load
        save = {
            title = "Save Game",
            load_title = "Load Game",
            new_game_title = "New Game",
            slot = "Slot %{num}",
            empty = "Empty",
            saved = "Game Saved!",
            confirm_overwrite = "Overwrite save?",
            confirm_delete = "Delete save?",
            yes = "Yes",
            no = "No",
            select_slot = "Select Save Slot",
            back_to_menu = "Back to Menu",
            action_save = "Save",
            action_load = "Load",
            unknown = "Unknown",
            confirm_delete_slot = "Delete Slot %{num}?",
            cannot_undo = "This action cannot be undone!",
            action_start = "Start",
            overwrite = "Overwrite?",
        },

        -- Inventory
        inventory = {
            title = "INVENTORY",
            equipment = "Equipment",
            use = "Use",
            equip = "Equip",
            unequip = "Unequip",
            drop = "Drop",
            empty_slot = "Empty",
            press_to_close = "Press %{key1} or %{key2} to close",
            press = "Press",
            twice_to_use = "twice to use",
            press_to_use = "Press %{key} to use",
            no_items = "No items in inventory",
            equipment_drag = "Equipment (drag to slot)",
            can_use = "Can use",
            cannot_use = "Cannot use (HP full)",
            equipped = "Equipped",
            pos = "Pos",
            size = "Size",
            -- Error messages
            err_item_not_found = "Item not found",
            err_not_equippable = "Item is not equippable",
            err_wrong_slot = "Wrong slot type",
            err_equip_failed = "Failed to equip weapon",
            err_slot_empty = "Slot is empty",
            err_item_data_not_found = "Item data not found",
            err_no_space = "No space in inventory",
            err_invalid_quickslot = "Invalid quickslot index",
            err_equipment_quickslot = "Equipment cannot be assigned to quickslots",
            err_consumable_only = "Only consumable items can be assigned to quickslots",
            err_quickslot_empty = "Quickslot is empty",
            err_item_gone = "Item no longer exists",
            err_cannot_use = "Cannot use item",
            err_use_failed = "Item use failed",
            err_unequip_failed = "Cannot unequip existing item",
        },

        -- Quest Log
        quest = {
            title = "Quests",
            active = "Active",
            available = "Available",
            completed = "Completed",
            all = "All",
            objectives = "Objectives",
            rewards = "Rewards",
            accept = "Accept",
            decline = "Decline",
            turn_in = "Turn In",
            complete = "Quest Complete",
            accepted_message = "Good luck on your quest!",
            declined_message = "Come back if you change your mind.",
            thank_you = "Thank you!",
            ready_turn_in = "Ready to turn in",
            more_quests = "+ %{count} more...",
            no_quests = "No quests",
            select_to_view = "Select a quest to view details",
            in_progress = "In Progress",
            description = "Description",
            reward_gold = "Gold",
            reward_exp = "EXP",
            reward_items = "Items",
            help_navigate = "Arrow Keys: Navigate",
            help_select = "Enter: Select",
        },

        -- Common
        common = {
            back = "Back",
            close = "Close",
            confirm = "Confirm",
            continue = "Continue",
            on = "ON",
            off = "OFF",
        },

        -- Prompts
        prompt = {
            interact = "Interact",
            talk = "Talk",
            save = "Save",
            pickup = "Pick up",
        },
    }
}
