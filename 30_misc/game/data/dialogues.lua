-- game/data/dialogues.lua
-- Dialogue tree definitions (choice-based conversations)
--
-- Structure:
--   dialogue_id = {
--     nodes = {
--       node_id = {
--         text_key = "dialogue.character.key",  -- Translation key (preferred)
--         text = "Fallback text",                -- Direct text (fallback if key not found)
--         speaker_key = "dialogue.common.speaker_villager",  -- Speaker name key
--         speaker = "Fallback Name",             -- Direct speaker name (fallback)
--         choices = {  -- Optional: if present, shows choice buttons
--           { text_key = "choice_key", text = "Fallback", next = "next_node_id" },
--         },
--         pages_key = { "key1", "key2" },  -- Multi-page with keys
--         pages = { "Page 1", "Page 2" },  -- Multi-page fallback
--         next = "auto_next_node",          -- Optional: auto-advance if no choices
--         condition = { ... },              -- Optional: show only if condition met
--         action = { ... }                  -- Optional: execute action when entering node
--       }
--     },
--     start_node = "node_id"  -- Starting node (default: "start")
--   }

local dialogues = {}

-- Villager 01 (passerby_01) - Quest giver, helpful villager
dialogues.villager_01_greeting = {
    -- NOTE: npc_id is injected at runtime from actual NPC (see input.lua)
    start_node = "start",
    nodes = {
        start = {
            text_key = "dialogue.villager_01.greeting",
            speaker_key = "dialogue.common.speaker_villager",
            next = "main_menu"
        },

        main_menu = {
            text_key = "dialogue.villager_01.how_can_i_help",
            speaker_key = "dialogue.common.speaker_villager",
            choices = {
                { text_key = "dialogue.villager_01.choice_village_info", next = "village_info" },
                { text_key = "dialogue.villager_01.choice_rumors", next = "rumors" },
                {
                    text_key = "dialogue.villager_01.choice_other_quest",
                    next = "quest_list",
                    -- Show only if this NPC has available quests
                    condition = {
                        type = "has_available_quests"
                        -- npc_id automatically uses current NPC from context
                    }
                },
                { text_key = "dialogue.villager_01.choice_goodbye", next = "end" }
            }
        },

        village_info = {
            text_key = "dialogue.villager_01.village_info",
            speaker_key = "dialogue.common.speaker_villager",
            choices = {
                { text_key = "dialogue.villager_01.choice_interesting", next = "more_info" },
                { text_key = "dialogue.villager_01.choice_thanks_info", next = "main_menu" }
            }
        },

        more_info = {
            -- Multi-page dialogue with translation keys
            pages_key = {
                "dialogue.villager_01.more_info_1",
                "dialogue.villager_01.more_info_2",
                "dialogue.villager_01.more_info_3"
            },
            speaker_key = "dialogue.common.speaker_villager",
            choices = {
                {
                    text_key = "dialogue.villager_01.choice_tell_slimes",
                    next = "slimes",
                    -- Only show if quest is still available (not already accepted)
                    condition = {
                        type = "quest_state_is",
                        quest_id = "slime_menace",
                        state = "available"
                    }
                },
                { text_key = "dialogue.villager_01.choice_interesting_story", next = "main_menu" }
            }
        },

        slimes = {
            text_key = "dialogue.villager_01.slimes",
            speaker_key = "dialogue.common.speaker_villager",
            choices = {
                {
                    text_key = "dialogue.villager_01.choice_sure_help",
                    next = "quest_accepted",
                    actions = {
                        { type = "accept_quest", quest_id = "slime_menace" },
                        { type = "give_item", item_id = "staff", count = 1 }
                    },
                    -- Only show if quest is still available (not already accepted)
                    condition = {
                        type = "quest_state_is",
                        quest_id = "slime_menace",
                        state = "available"
                    }
                },
                { text_key = "dialogue.villager_01.choice_think_about_it", next = "main_menu" },
                { text_key = "dialogue.villager_01.choice_not_interested", next = "main_menu" }
            }
        },

        quest_accepted = {
            text_key = "dialogue.villager_01.quest_accepted",
            speaker_key = "dialogue.common.speaker_villager",
            choices = {
                { text_key = "dialogue.villager_01.choice_get_on_it", next = "end" },
                { text_key = "dialogue.villager_01.choice_tell_more", next = "main_menu" }
            }
        },

        rumors = {
            text_key = "dialogue.villager_01.rumors",
            speaker_key = "dialogue.common.speaker_villager",
            choices = {
                { text_key = "dialogue.villager_01.choice_good_to_know", next = "main_menu" }
            }
        },

        -- Quest offer node (Dynamic quest dialogue generation from quest data)
        quest_list = {
            type = "quest_offer",  -- Special node type
            -- npc_id automatically uses current NPC from dialogue.current_npc_id
            speaker_key = "dialogue.common.speaker_villager",
            no_quest_fallback = "no_more_quests"  -- Where to go if no quests available
        },

        -- No more quests fallback
        no_more_quests = {
            text_key = "dialogue.villager_01.no_more_quests",
            speaker_key = "dialogue.common.speaker_villager",
            choices = {
                { text_key = "dialogue.villager_01.choice_thanks_info", next = "main_menu" }
            }
        },

        -- End conversation
        ["end"] = {
            text_key = "dialogue.villager_01.farewell",
            speaker_key = "dialogue.common.speaker_villager"
            -- No choices, no next = dialogue ends completely
        }
    }
}

-- Villager 02 (passerby_02) - Casual passerby, simpler dialogue
dialogues.villager_02_greeting = {
    start_node = "start",
    nodes = {
        start = {
            text_key = "dialogue.villager_02.greeting",
            speaker_key = "dialogue.common.speaker_passerby",
            next = "main_menu"
        },

        main_menu = {
            text_key = "dialogue.villager_02.nice_weather",
            speaker_key = "dialogue.common.speaker_passerby",
            choices = {
                { text_key = "dialogue.villager_02.choice_beautiful_day", next = "agree" },
                { text_key = "dialogue.villager_02.choice_live_here", next = "local_info" },
                { text_key = "dialogue.villager_02.choice_see_around", next = "end" }
            }
        },

        agree = {
            text_key = "dialogue.villager_02.agree",
            speaker_key = "dialogue.common.speaker_passerby",
            choices = {
                { text_key = "dialogue.villager_02.choice_me_too", next = "end" },
                { text_key = "dialogue.villager_02.choice_know_area", next = "local_info" }
            }
        },

        local_info = {
            text_key = "dialogue.villager_02.local_info",
            speaker_key = "dialogue.common.speaker_passerby",
            choices = {
                { text_key = "dialogue.villager_02.choice_thanks_tip", next = "end" },
                { text_key = "dialogue.villager_02.choice_anything_else", next = "more_info" }
            }
        },

        more_info = {
            text_key = "dialogue.villager_02.more_info",
            speaker_key = "dialogue.common.speaker_passerby",
            choices = {
                { text_key = "dialogue.villager_02.choice_keep_in_mind", next = "end" }
            }
        },

        ["end"] = {
            text_key = "dialogue.villager_02.farewell",
            speaker_key = "dialogue.common.speaker_passerby"
        }
    }
}

-- Merchant (will be expanded to shop in Phase 4)
dialogues.merchant_greeting = {
    start_node = "start",
    nodes = {
        start = {
            text_key = "dialogue.merchant.welcome",
            speaker_key = "dialogue.common.speaker_merchant",
            next = "main_menu"
        },

        main_menu = {
            text_key = "dialogue.merchant.what_brings_you",
            speaker_key = "dialogue.common.speaker_merchant",
            choices = {
                { text_key = "dialogue.merchant.choice_what_sell", next = "shop_info" },
                { text_key = "dialogue.merchant.choice_just_browsing", next = "browsing" },
                { text_key = "dialogue.merchant.choice_goodbye", next = "end" }
            }
        },

        shop_info = {
            text_key = "dialogue.merchant.shop_info",
            speaker_key = "dialogue.common.speaker_merchant",
            choices = {
                { text_key = "dialogue.merchant.choice_see_goods", next = "open_shop" },
                { text_key = "dialogue.merchant.choice_maybe_later", next = "end" }
            }
        },

        browsing = {
            text_key = "dialogue.merchant.browsing",
            speaker_key = "dialogue.common.speaker_merchant",
            choices = {
                { text_key = "dialogue.merchant.choice_actually_sell", next = "shop_info" },
                { text_key = "dialogue.merchant.choice_thanks", next = "end" }
            }
        },

        open_shop = {
            text_key = "dialogue.merchant.open_shop",
            speaker_key = "dialogue.common.speaker_merchant",
            action = { type = "open_shop", shop_id = "general_store" }
        },

        ["end"] = {
            text_key = "dialogue.merchant.farewell",
            speaker_key = "dialogue.common.speaker_merchant"
            -- No choices, no next = dialogue ends completely
        }
    }
}

-- Example: Guard (simple, no choices - backwards compatible)
dialogues.guard_greeting = {
    start_node = "start",
    nodes = {
        start = {
            text_key = "dialogue.guard.move_along",
            speaker_key = "dialogue.common.speaker_guard",
        }
    }
}

-- Surrendered Bandit (Enemy → NPC transformation demo)
dialogues.surrendered_bandit = {
    start_node = "surrender",
    nodes = {
        surrender = {
            text_key = "dialogue.surrendered_bandit.surrender",
            speaker_key = "dialogue.common.speaker_bandit",
            next = "main_menu"
        },

        main_menu = {
            text_key = "dialogue.surrendered_bandit.tell_anything",
            speaker_key = "dialogue.common.speaker_bandit",
            choices = {
                { text_key = "dialogue.surrendered_bandit.choice_why_attack", next = "reason" },
                { text_key = "dialogue.surrendered_bandit.choice_hideout", next = "hideout" },
                { text_key = "dialogue.surrendered_bandit.choice_let_go", next = "mercy" },
            }
        },

        reason = {
            text_key = "dialogue.surrendered_bandit.reason",
            speaker_key = "dialogue.common.speaker_bandit",
            next = "main_menu"
        },

        hideout = {
            text_key = "dialogue.surrendered_bandit.hideout",
            speaker_key = "dialogue.common.speaker_bandit",
            next = "main_menu"
        },

        mercy = {
            text_key = "dialogue.surrendered_bandit.mercy",
            speaker_key = "dialogue.common.speaker_bandit",
        }
    }
}

-- Deceiver (NPC → Enemy transformation demo)
dialogues.deceiver_greeting = {
    start_node = "start",
    nodes = {
        start = {
            text_key = "dialogue.deceiver.greeting",
            speaker_key = "dialogue.common.speaker_unknown",
            next = "main_menu"
        },

        main_menu = {
            text_key = "dialogue.deceiver.looking_valuable",
            speaker_key = "dialogue.common.speaker_unknown",
            choices = {
                { text_key = "dialogue.deceiver.choice_who_are_you", next = "identity" },
                { text_key = "dialogue.deceiver.choice_passing_through", next = "passing" },
                { text_key = "dialogue.deceiver.choice_suspicious", next = "suspicious" },
            }
        },

        identity = {
            text_key = "dialogue.deceiver.identity",
            speaker_key = "dialogue.common.speaker_unknown",
            next = "main_menu"
        },

        passing = {
            text_key = "dialogue.deceiver.passing",
            speaker_key = "dialogue.common.speaker_unknown",
        },

        suspicious = {
            text_key = "dialogue.deceiver.suspicious",
            speaker_key = "dialogue.common.speaker_deceiver",
            next = "hostile"
        },

        hostile = {
            text_key = "dialogue.deceiver.hostile",
            speaker_key = "dialogue.common.speaker_deceiver",
            -- This choice will trigger NPC → Enemy transformation
            action = {
                type = "transform_to_enemy",
                enemy_type = "deceiver"
            }
        }
    }
}

return dialogues
