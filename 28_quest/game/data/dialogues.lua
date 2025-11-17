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
    npc_id = "villager_main",  -- NPC ID for quest lookups
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
                    -- Show only if slime quest has been accepted
                    condition = function(ctx)
                        local quest_state = ctx.quest_system:getState("slime_menace")
                        if not quest_state then return false end
                        -- Show if quest is ACTIVE, COMPLETED, or TURNED_IN
                        return quest_state.state ~= ctx.quest_system.STATE.AVAILABLE
                    end
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

        -- Quest list router - dynamically determines next quest to offer
        quest_list = {
            text = "",  -- Will be set dynamically
            speaker = "Villager",
            choices = {},  -- Will be set dynamically
            -- This is a special node that uses dynamic routing
            on_enter = function(ctx)
                -- Priority order of quests to offer
                local quest_order = {
                    { id = "collect_test", flag = "offered_collect_test", node = "offer_collect" },
                    { id = "explore_test", flag = "offered_explore_test", node = "offer_explore" },
                    { id = "deliver_test", flag = "offered_deliver_test", node = "offer_deliver" },
                    { id = "mysterious_stranger", flag = "offered_mysterious_stranger", node = "offer_stranger" },
                    { id = "explore_forest", flag = "offered_explore_forest", node = "offer_explore_forest" },
                }

                -- Find next quest to offer
                for _, quest_info in ipairs(quest_order) do
                    local offered = ctx.dialogue_system:getFlag(ctx.dialogue_id, quest_info.flag, false)
                    -- Check if quest is still available (not already accepted/completed)
                    local quest_state = ctx.quest_system:getState(quest_info.id)
                    local is_available = quest_state and quest_state.state == ctx.quest_system.STATE.AVAILABLE

                    if not offered and is_available then
                        -- Offer this quest (only if not offered before AND still available)
                        return quest_info.node
                    end
                end

                -- All quests offered
                return "no_more_quests"
            end
        },

        -- Collect quest offer
        offer_collect = {
            text = "Actually, I need some slime cores for research. Could you collect 3 of them?",
            speaker = "Villager",
            choices = {
                {
                    text = "Accept Quest",
                    next = "collect_accepted",
                    action = {
                        type = "accept_quest",
                        quest_id = "collect_test",
                        set_flag = { flag = "offered_collect_test", value = true }
                    }
                },
                {
                    text = "Decline",
                    next = "main_menu",
                    action = {
                        type = "set_flag",
                        flag = "offered_collect_test",
                        value = true
                    }
                }
            }
        },

        collect_accepted = {
            text = "Great! Bring me 3 slime cores when you have them.",
            speaker = "Villager",
            choices = {
                { text = "I'll get them", next = "end" },
                { text = "Tell me more", next = "main_menu" }
            }
        },

        -- Explore quest offer
        offer_explore = {
            text = "Have you explored the eastern area yet? I'd like to know if it's safe.",
            speaker = "Villager",
            choices = {
                {
                    text = "Accept Quest",
                    next = "explore_accepted",
                    action = {
                        type = "accept_quest",
                        quest_id = "explore_test",
                        set_flag = { flag = "offered_explore_test", value = true }
                    }
                },
                {
                    text = "Decline",
                    next = "main_menu",
                    action = {
                        type = "set_flag",
                        flag = "offered_explore_test",
                        value = true
                    }
                }
            }
        },

        explore_accepted = {
            text = "Thank you! Let me know what you find there.",
            speaker = "Villager",
            choices = {
                { text = "I'll check it out", next = "end" },
                { text = "Anything else?", next = "main_menu" }
            }
        },

        -- Deliver quest offer
        offer_deliver = {
            text = "I need a small health potion delivered to someone. Can you help?",
            speaker = "Villager",
            choices = {
                {
                    text = "Accept Quest",
                    next = "deliver_accepted",
                    action = {
                        type = "accept_quest",
                        quest_id = "deliver_test",
                        set_flag = { flag = "offered_deliver_test", value = true }
                    }
                },
                {
                    text = "Decline",
                    next = "main_menu",
                    action = {
                        type = "set_flag",
                        flag = "offered_deliver_test",
                        value = true
                    }
                }
            }
        },

        deliver_accepted = {
            text = "Perfect! Take this potion to the merchant when you're ready.",
            speaker = "Villager",
            choices = {
                { text = "I'll deliver it", next = "end" },
                { text = "Anything else?", next = "main_menu" }
            }
        },

        -- Mysterious Stranger quest offer
        offer_stranger = {
            text = "Have you noticed that mysterious stranger near the village entrance? I'm curious what they want. Could you talk to them?",
            speaker = "Villager",
            choices = {
                {
                    text = "Accept Quest",
                    next = "stranger_accepted",
                    action = {
                        type = "accept_quest",
                        quest_id = "mysterious_stranger",
                        set_flag = { flag = "offered_mysterious_stranger", value = true }
                    }
                },
                {
                    text = "Decline",
                    next = "main_menu",
                    action = {
                        type = "set_flag",
                        flag = "offered_mysterious_stranger",
                        value = true
                    }
                }
            }
        },

        stranger_accepted = {
            text = "Thank you! The stranger should be near the village entrance. Let me know what they say!",
            speaker = "Villager",
            choices = {
                { text = "I'll talk to them", next = "end" },
                { text = "Anything else?", next = "main_menu" }
            }
        },

        -- Explore Forest quest offer
        offer_explore_forest = {
            text = "The eastern forest is vast and mysterious. Would you explore it and report back what you find?",
            speaker = "Villager",
            choices = {
                {
                    text = "Accept Quest",
                    next = "explore_forest_accepted",
                    action = {
                        type = "accept_quest",
                        quest_id = "explore_forest",
                        set_flag = { flag = "offered_explore_forest", value = true }
                    }
                },
                {
                    text = "Decline",
                    next = "main_menu",
                    action = {
                        type = "set_flag",
                        flag = "offered_explore_forest",
                        value = true
                    }
                }
            }
        },

        explore_forest_accepted = {
            text = "Excellent! The forest lies to the east. Be careful out there!",
            speaker = "Villager",
            choices = {
                { text = "I'll explore it", next = "end" },
                { text = "Anything else?", next = "main_menu" }
            }
        },

        -- No more quests
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
