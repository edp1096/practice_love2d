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
    start_node = "start",
    nodes = {
        start = {
            text = "Hello traveler! How can I help you?",
            speaker = "Villager",
            choices = {
                { text = "Tell me about this village", next = "village_info" },
                { text = "Any rumors?", next = "rumors" },
                { text = "Goodbye", next = "end" }
            }
        },

        village_info = {
            text = "This is a peaceful village. We have a merchant and a blacksmith nearby.",
            speaker = "Villager",
            choices = {
                { text = "Interesting. What else?", next = "more_info" },
                { text = "Thanks for the info", next = "start" }
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
                { text = "Interesting story", next = "start" }
            }
        },

        slimes = {
            text = "Yes, slimes! They've been bothering us lately. Maybe you could help?",
            speaker = "Villager",
            choices = {
                { text = "I'll think about it", next = "start" },
                { text = "Not interested", next = "end" }
            }
        },

        rumors = {
            text = "I heard the merchant has rare items for sale. You should check them out!",
            speaker = "Villager",
            choices = {
                { text = "Good to know", next = "start" }
            }
        },

        -- Special node: ends dialogue
        ["end"] = {
            text = "Take care, traveler!",
            speaker = "Villager",
            -- No choices = dialogue ends after this
        }
    }
}

-- Example: Merchant (will be expanded to shop in Phase 4)
dialogues.merchant_greeting = {
    start_node = "start",
    nodes = {
        start = {
            text = "Welcome to my shop! What brings you here?",
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
        },

        ["end"] = {
            text = "Come again!",
            speaker = "Merchant",
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
