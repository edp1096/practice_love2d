-- game/data/dialogues.lua
-- Dialogue tree definitions (choice-based conversations)
--
-- Structure:
--   dialogue_id = {
--     nodes = {
--       node_id = {
--         text = "Message to display",
--         speaker = "NPC Name" (optional),
--         choices = {  -- Optional: if present, shows choice buttons
--           { text = "Choice text", next = "next_node_id" },
--           { text = "Another choice", next = "another_node" }
--         },
--         next = "auto_next_node",  -- Optional: auto-advance if no choices
--         condition = { ... },       -- Optional: show this node only if condition met (Phase 2)
--         action = { ... }           -- Optional: execute action when entering node (Phase 3)
--       }
--     },
--     start_node = "node_id"  -- Starting node (default: "start")
--   }

local dialogues = {}

-- Example: Simple greeting with choices
dialogues.villager_greeting = {
    -- NOTE: npc_id is injected at runtime from actual NPC (see input.lua)
    start_node = "start",
    nodes = {
        start = {
            text = "Hello traveler!",
            speaker = "Villager",
            next = "main_menu"
        },

        main_menu = {
            text = "How can I help you?",
            speaker = "Villager",
            choices = {
                { text = "Tell me about this village", next = "village_info" },
                { text = "Any rumors?", next = "rumors" },
                {
                    text = "Other quest?",
                    next = "quest_list",
                    -- Show only if this NPC has available quests
                    condition = {
                        type = "has_available_quests"
                        -- npc_id automatically uses current NPC from context
                    }
                },
                { text = "Goodbye", next = "end" }
            }
        },

        village_info = {
            text = "This is a peaceful village. We have a merchant and a blacksmith nearby.",
            speaker = "Villager",
            choices = {
                { text = "Interesting. What else?", next = "more_info" },
                { text = "Thanks for the info", next = "main_menu" }
            }
        },

        more_info = {
            -- NEW: Multi-page dialogue (test Visual Novel style)
            pages = {
                "There's also an old forest to the east. It's been there for centuries, long before our village was founded.",
                "Many travelers have explored it, but few have ventured deep inside. The trees grow thick and the paths are winding.",
                "Some say slimes live there, gathering in the darker corners. They're not dangerous alone, but in groups..."
            },
            speaker = "Villager",
            choices = {
                { text = "Tell me more about the slimes", next = "slimes" },
                { text = "Interesting story", next = "main_menu" }
            }
        },

        slimes = {
            text = "Yes, slimes! They've been bothering us lately. Maybe you could help?",
            speaker = "Villager",
            choices = {
                {
                    text = "Sure, I'll help!",
                    next = "quest_accepted",
                    action = { type = "accept_quest", quest_id = "slime_menace" }
                },
                { text = "I'll think about it", next = "main_menu" },
                { text = "Not interested", next = "main_menu" }
            }
        },

        quest_accepted = {
            text = "Thank you! Please defeat 3 slimes. They're usually found in the forest to the east.",
            speaker = "Villager",
            choices = {
                { text = "I'll get right on it", next = "end" },
                { text = "Tell me more", next = "main_menu" }
            }
        },

        rumors = {
            text = "I heard the merchant has rare items for sale. You should check them out!",
            speaker = "Villager",
            choices = {
                { text = "Good to know", next = "main_menu" }
            }
        },

        -- Quest offer node (NEW: Dynamic quest dialogue generation from quest data)
        quest_list = {
            type = "quest_offer",  -- Special node type
            -- npc_id automatically uses current NPC from dialogue.current_npc_id
            speaker = "Villager",
            no_quest_fallback = "no_more_quests"  -- Where to go if no quests available
        },

        -- No more quests fallback
        no_more_quests = {
            text = "I don't have any more tasks at the moment. Thank you for all your help!",
            speaker = "Villager",
            choices = {
                { text = "Thanks for the info", next = "main_menu" }
            }
        },

        -- End conversation
        ["end"] = {
            text = "Take care, traveler!",
            speaker = "Villager"
            -- No choices, no next = dialogue ends completely
        }
    }
}

-- Example: Merchant (will be expanded to shop in Phase 4)
dialogues.merchant_greeting = {
    start_node = "start",
    nodes = {
        start = {
            text = "Welcome to my shop!",
            speaker = "Merchant",
            next = "main_menu"
        },

        main_menu = {
            text = "What brings you here?",
            speaker = "Merchant",
            choices = {
                { text = "What do you sell?", next = "shop_info" },
                { text = "Just browsing", next = "browsing" },
                { text = "Goodbye", next = "end" }
            }
        },

        shop_info = {
            text = "I have potions, weapons, and rare items. Everything an adventurer needs!",
            speaker = "Merchant",
            choices = {
                { text = "Let me see your goods", next = "open_shop" },  -- Phase 4: open shop UI
                { text = "Maybe later", next = "end" }
            }
        },

        browsing = {
            text = "Take your time! Let me know if you need anything.",
            speaker = "Merchant",
            choices = {
                { text = "Actually, what do you sell?", next = "shop_info" },
                { text = "Thanks", next = "end" }
            }
        },

        open_shop = {
            text = "Here's what I have in stock!",
            speaker = "Merchant",
            -- Phase 4: This will trigger shop UI opening
            -- action = { type = "open_shop", shop_id = "general_store" }
            next = "main_menu"  -- Loop back until shop UI is implemented
        },

        ["end"] = {
            text = "Come again!",
            speaker = "Merchant"
            -- No choices, no next = dialogue ends completely
        }
    }
}

-- Example: Guard (simple, no choices - backwards compatible)
dialogues.guard_greeting = {
    start_node = "start",
    nodes = {
        start = {
            text = "Move along, citizen. Nothing to see here.",
            speaker = "Guard",
        }
    }
}

return dialogues
