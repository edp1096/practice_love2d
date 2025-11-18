-- game/data/quests.lua
-- Quest definitions (game-specific)
--
-- Structure:
--   quest_id = {
--     id = "quest_id",
--     title = "Quest Title",
--     description = "Quest description shown in log",
--     objectives = {
--       {
--         type = "kill|collect|talk|explore|deliver",
--         target = "enemy_type|item_type|npc_id|location_id",
--         count = 5,  -- How many needed (default: 1)
--         description = "Kill 5 slimes",  -- Shown in UI
--         npc = "npc_receiver"  -- For deliver quests only
--       }
--     },
--     giver_npc = "npc_id",        -- Who gives the quest
--     receiver_npc = "npc_id",     -- Who receives completion (default: same as giver)
--     rewards = {
--       gold = 100,
--       exp = 50,
--       items = { "small_potion", "sword" }
--     },
--     prerequisites = { "other_quest_id" }  -- Must complete these first
--   }

local quests = {}

-- ============================================================================
-- Tutorial Quests
-- ============================================================================

quests.tutorial_talk = {
    id = "tutorial_talk",
    title = "Meet the Villager",
    description = "Talk to the friendly villager to learn about the area.",
    objectives = {
        {
            type = "talk",
            target = "passerby_01",  -- Talk to this NPC
            count = 1,
            description = "Talk to the Villager"
        }
    },
    giver_npc = "passerby_01",  -- Changed to match actual NPC
    rewards = {
        gold = 10,
        exp = 5
    }
}

-- ============================================================================
-- Test Quests (Simple versions for testing each quest type)
-- ============================================================================

quests.collect_test = {
    id = "collect_test",
    title = "Item Collection Test",
    description = "Collect health potions to test the collection system.",
    objectives = {
        {
            type = "collect",
            target = "small_potion",  -- Using existing item type
            count = 2,
            description = "Collect 2 Health Potions"
        }
    },
    giver_npc = "passerby_01",
    rewards = {
        gold = 50,
        exp = 25
    },
    prerequisites = { "tutorial_talk", "slime_menace" },

    -- Dialogue information (for quest offer system)
    dialogue = {
        offer_text = "Actually, I need some slime cores for research. Could you collect 3 of them?",
        accept_text = "Great! Bring me 3 slime cores when you have them.",
        decline_response = "main_menu"  -- Node to go to on decline
    }
}

quests.explore_test = {
    id = "explore_test",
    title = "Exploration Test",
    description = "Visit the second area to test the exploration system.",
    objectives = {
        {
            type = "explore",
            target = "level1_area2",  -- Map area ID
            count = 1,
            description = "Visit Area 2"
        }
    },
    giver_npc = "passerby_01",
    rewards = {
        gold = 30,
        exp = 20
    },
    prerequisites = { "tutorial_talk", "slime_menace" },

    -- Dialogue information (for quest offer system)
    dialogue = {
        offer_text = "Have you explored the eastern area yet? I'd like to know if it's safe.",
        accept_text = "Thank you! Let me know what you find there.",
        decline_response = "main_menu"
    }
}

quests.deliver_test = {
    id = "deliver_test",
    title = "Delivery Test",
    description = "Deliver a small potion to test the delivery system.",
    objectives = {
        {
            type = "deliver",
            target = "small_potion",  -- Item to deliver
            count = 1,
            npc = "passerby_01",  -- Deliver to this NPC
            description = "Deliver Small Potion to Villager"
        }
    },
    giver_npc = "passerby_01",
    receiver_npc = "passerby_01",  -- Same NPC (for testing)
    rewards = {
        gold = 40,
        exp = 15
    },
    prerequisites = { "tutorial_talk", "slime_menace" },

    -- Dialogue information (for quest offer system)
    dialogue = {
        offer_text = "I need a small health potion delivered to someone. Can you help?",
        accept_text = "Perfect! Take this potion to the merchant when you're ready.",
        decline_response = "main_menu"
    }
}

-- ============================================================================
-- Combat Quests
-- ============================================================================

quests.slime_menace = {
    id = "slime_menace",
    title = "Slime Menace",
    description = "The village is being bothered by slimes. Help by defeating 3 of them.",
    objectives = {
        {
            type = "kill",
            target = "red_slime",  -- Changed to match actual enemy type in game
            count = 3,  -- Reduced to 3 for easier testing
            description = "Defeat 3 red slimes"
        }
    },
    giver_npc = "passerby_01",  -- Changed to match actual NPC
    receiver_npc = "passerby_01",
    rewards = {
        gold = 100,
        exp = 50,
        items = { "small_potion" }
    },
    prerequisites = { "tutorial_talk" }
}

quests.forest_cleanup = {
    id = "forest_cleanup",
    title = "Forest Cleanup",
    description = "Clear out the forest by defeating 10 slimes.",
    objectives = {
        {
            type = "kill",
            target = "slime",
            count = 10,
            description = "Defeat 10 slimes in the forest"
        }
    },
    giver_npc = "villager_main",
    rewards = {
        gold = 250,
        exp = 120,
        items = { "small_potion", "small_potion" }
    },
    prerequisites = { "slime_menace" }
}

-- ============================================================================
-- Collection Quests
-- ============================================================================

quests.herb_gathering = {
    id = "herb_gathering",
    title = "Herb Gathering",
    description = "The healer needs herbs for medicine. Collect 3 healing herbs.",
    objectives = {
        {
            type = "collect",
            target = "healing_herb",
            count = 3,
            description = "Collect 3 Healing Herbs"
        }
    },
    giver_npc = "healer",
    rewards = {
        gold = 80,
        exp = 30,
        items = { "small_potion", "small_potion" }
    }
}

quests.rare_materials = {
    id = "rare_materials",
    title = "Rare Materials",
    description = "Find rare slime gel for the alchemist's research.",
    objectives = {
        {
            type = "collect",
            target = "slime_gel",
            count = 5,
            description = "Collect 5 Slime Gels"
        }
    },
    giver_npc = "alchemist",
    rewards = {
        gold = 150,
        exp = 75
    }
}

-- ============================================================================
-- Exploration Quests
-- ============================================================================

quests.explore_forest = {
    id = "explore_forest",
    title = "Explore the Forest",
    description = "Venture into the eastern forest and discover what lies within.",
    objectives = {
        {
            type = "explore",
            target = "level1_area2",  -- Map area ID
            count = 1,
            description = "Visit the Eastern Forest"
        }
    },
    giver_npc = "villager_main",
    receiver_npc = "passerby_01",  -- TEST: Easy to turn in (same as explore_test)
    rewards = {
        gold = 50,
        exp = 40
    },

    -- Dialogue information (for quest offer system)
    dialogue = {
        offer_text = "The eastern forest is vast and mysterious. Would you explore it and report back what you find?",
        accept_text = "Excellent! The forest lies to the east. Be careful out there!",
        decline_response = "main_menu"
    }
}

quests.ancient_ruins = {
    id = "ancient_ruins",
    title = "Ancient Ruins",
    description = "Explore the mysterious ruins to the north.",
    objectives = {
        {
            type = "explore",
            target = "level2_area1",
            count = 1,
            description = "Discover the Ancient Ruins"
        }
    },
    giver_npc = "scholar",
    rewards = {
        gold = 200,
        exp = 100
    },
    prerequisites = { "explore_forest" }
}

-- ============================================================================
-- Delivery Quests
-- ============================================================================

quests.medicine_delivery = {
    id = "medicine_delivery",
    title = "Medicine Delivery",
    description = "Deliver medicine from the healer to the sick merchant.",
    objectives = {
        {
            type = "deliver",
            target = "medicine_package",
            count = 1,
            npc = "merchant",
            description = "Deliver medicine to the Merchant"
        }
    },
    giver_npc = "healer",
    receiver_npc = "merchant",
    rewards = {
        gold = 75,
        exp = 35
    }
}

quests.letter_delivery = {
    id = "letter_delivery",
    title = "Important Letter",
    description = "Deliver an important letter from the village elder to the scholar.",
    objectives = {
        {
            type = "deliver",
            target = "sealed_letter",
            count = 1,
            npc = "scholar",
            description = "Deliver the letter to the Scholar"
        }
    },
    giver_npc = "elder",
    receiver_npc = "scholar",
    rewards = {
        gold = 120,
        exp = 60
    }
}

-- ============================================================================
-- Multi-Objective Quests
-- ============================================================================

quests.village_hero = {
    id = "village_hero",
    title = "Village Hero",
    description = "Prove yourself as a hero by completing multiple tasks.",
    objectives = {
        {
            type = "kill",
            target = "slime",
            count = 15,
            description = "Defeat 15 slimes"
        },
        {
            type = "collect",
            target = "healing_herb",
            count = 5,
            description = "Collect 5 Healing Herbs"
        },
        {
            type = "talk",
            target = "elder",
            count = 1,
            description = "Report to the Elder"
        }
    },
    giver_npc = "elder",
    rewards = {
        gold = 500,
        exp = 250,
        items = { "iron_sword", "small_potion", "small_potion", "small_potion" }  -- TODO: Add hero_medal item
    },
    prerequisites = { "slime_menace", "herb_gathering" }
}

-- ============================================================================
-- Story Quests (Chain)
-- ============================================================================

quests.mysterious_stranger = {
    id = "mysterious_stranger",
    title = "The Mysterious Stranger",
    description = "A stranger has appeared in the village. Find out what they want.",
    objectives = {
        {
            type = "talk",
            target = "stranger",
            count = 1,
            description = "Talk to the Mysterious Stranger"
        }
    },
    giver_npc = "villager_main",
    rewards = {
        gold = 50,
        exp = 30
    },

    -- Dialogue information (for quest offer system)
    dialogue = {
        offer_text = "Have you noticed that mysterious stranger near the village entrance? I'm curious what they want. Could you talk to them?",
        accept_text = "Thank you! The stranger should be near the village entrance. Let me know what they say!",
        decline_response = "main_menu"
    }
}

quests.strangers_request = {
    id = "strangers_request",
    title = "Stranger's Request",
    description = "The stranger needs an ancient artifact from the ruins.",
    objectives = {
        {
            type = "explore",
            target = "level2_area1",
            count = 1,
            description = "Search the Ancient Ruins"
        },
        {
            type = "collect",
            target = "ancient_artifact",
            count = 1,
            description = "Find the Ancient Artifact"
        }
    },
    giver_npc = "stranger",
    rewards = {
        gold = 300,
        exp = 150
    },
    prerequisites = { "mysterious_stranger" }
}

return quests
