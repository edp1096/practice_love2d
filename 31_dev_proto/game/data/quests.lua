-- game/data/quests.lua
-- Quest definitions (game-specific)
--
-- Structure:
--   quest_id = {
--     id = "quest_id",
--     title_key = "quests.quest_id.title",        -- Translation key (preferred)
--     title = "Fallback Title",                   -- Direct text (fallback)
--     description_key = "quests.quest_id.description",
--     description = "Fallback description",
--     objectives = {
--       {
--         type = "kill|collect|talk|explore|deliver",
--         target = "enemy_type|item_type|npc_id|location_id",
--         count = 5,
--         description_key = "quests.quest_id.obj_1",  -- Translation key
--         description = "Fallback objective text",
--         npc = "npc_receiver"  -- For deliver quests only
--       }
--     },
--     giver_npc = "npc_id",
--     receiver_npc = "npc_id",
--     rewards = { gold = 100, exp = 50, items = { "small_potion" } },
--     prerequisites = { "other_quest_id" },
--     dialogue = {
--       offer_text_key = "quests.quest_id.dialogue_offer",
--       accept_text_key = "quests.quest_id.dialogue_accept",
--       decline_response = "main_menu"
--     }
--   }

local quests = {}

-- ============================================================================
-- Tutorial Quests
-- ============================================================================

quests.tutorial_talk = {
    id = "tutorial_talk",
    title_key = "quests.tutorial_talk.title",
    description_key = "quests.tutorial_talk.description",
    objectives = {
        {
            type = "talk",
            target = "passerby_01",
            count = 1,
            description_key = "quests.tutorial_talk.obj_1"
        }
    },
    giver_npc = "passerby_01",
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
    title_key = "quests.collect_test.title",
    description_key = "quests.collect_test.description",
    objectives = {
        {
            type = "collect",
            target = "small_potion",
            count = 2,
            description_key = "quests.collect_test.obj_1"
        }
    },
    giver_npc = "passerby_01",
    rewards = {
        gold = 50,
        exp = 25
    },
    prerequisites = { "tutorial_talk", "slime_menace" },
    dialogue = {
        offer_text_key = "quests.collect_test.dialogue_offer",
        accept_text_key = "quests.collect_test.dialogue_accept",
        decline_response = "main_menu"
    }
}

quests.explore_test = {
    id = "explore_test",
    title_key = "quests.explore_test.title",
    description_key = "quests.explore_test.description",
    objectives = {
        {
            type = "explore",
            target = "level1_area2",
            count = 1,
            description_key = "quests.explore_test.obj_1"
        }
    },
    giver_npc = "passerby_01",
    rewards = {
        gold = 30,
        exp = 20
    },
    prerequisites = { "tutorial_talk", "slime_menace" },
    dialogue = {
        offer_text_key = "quests.explore_test.dialogue_offer",
        accept_text_key = "quests.explore_test.dialogue_accept",
        decline_response = "main_menu"
    }
}

quests.deliver_test = {
    id = "deliver_test",
    title_key = "quests.deliver_test.title",
    description_key = "quests.deliver_test.description",
    objectives = {
        {
            type = "deliver",
            target = "small_potion",
            count = 1,
            npc = "merchant_01",  -- Shop NPC (shop1)
            description_key = "quests.deliver_test.obj_1"
        }
    },
    giver_npc = "passerby_01",
    receiver_npc = "merchant_01",  -- Reward from merchant
    rewards = {
        gold = 40,
        exp = 15
    },
    prerequisites = { "tutorial_talk", "slime_menace" },
    dialogue = {
        offer_text_key = "quests.deliver_test.dialogue_offer",
        accept_text_key = "quests.deliver_test.dialogue_accept",
        decline_response = "main_menu"
    }
}

-- ============================================================================
-- Combat Quests
-- ============================================================================

quests.slime_menace = {
    id = "slime_menace",
    title_key = "quests.slime_menace.title",
    description_key = "quests.slime_menace.description",
    objectives = {
        {
            type = "kill",
            target = "red_slime",
            count = 3,
            description_key = "quests.slime_menace.obj_1"
        }
    },
    giver_npc = "passerby_01",
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
    title_key = "quests.forest_cleanup.title",
    description_key = "quests.forest_cleanup.description",
    objectives = {
        {
            type = "kill",
            target = "slime",
            count = 10,
            description_key = "quests.forest_cleanup.obj_1"
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
    title_key = "quests.herb_gathering.title",
    description_key = "quests.herb_gathering.description",
    objectives = {
        {
            type = "collect",
            target = "healing_herb",
            count = 3,
            description_key = "quests.herb_gathering.obj_1"
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
    title_key = "quests.rare_materials.title",
    description_key = "quests.rare_materials.description",
    objectives = {
        {
            type = "collect",
            target = "slime_gel",
            count = 5,
            description_key = "quests.rare_materials.obj_1"
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
    title_key = "quests.explore_forest.title",
    description_key = "quests.explore_forest.description",
    objectives = {
        {
            type = "explore",
            target = "level1_area2",
            count = 1,
            description_key = "quests.explore_forest.obj_1"
        }
    },
    giver_npc = "villager_main",
    receiver_npc = "passerby_01",
    rewards = {
        gold = 50,
        exp = 40
    },
    dialogue = {
        offer_text_key = "quests.explore_forest.dialogue_offer",
        accept_text_key = "quests.explore_forest.dialogue_accept",
        decline_response = "main_menu"
    }
}

quests.ancient_ruins = {
    id = "ancient_ruins",
    title_key = "quests.ancient_ruins.title",
    description_key = "quests.ancient_ruins.description",
    objectives = {
        {
            type = "explore",
            target = "level2_area1",
            count = 1,
            description_key = "quests.ancient_ruins.obj_1"
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
    title_key = "quests.medicine_delivery.title",
    description_key = "quests.medicine_delivery.description",
    objectives = {
        {
            type = "deliver",
            target = "medicine_package",
            count = 1,
            npc = "merchant",
            description_key = "quests.medicine_delivery.obj_1"
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
    title_key = "quests.letter_delivery.title",
    description_key = "quests.letter_delivery.description",
    objectives = {
        {
            type = "deliver",
            target = "sealed_letter",
            count = 1,
            npc = "scholar",
            description_key = "quests.letter_delivery.obj_1"
        }
    },
    giver_npc = "elder",
    receiver_npc = "scholar",
    rewards = {
        gold = 120,
        exp = 60
    }
}

-- A->B Delivery Quest (pickup from NPC A, deliver to NPC B)
quests.package_delivery = {
    id = "package_delivery",
    title_key = "quests.package_delivery.title",
    description_key = "quests.package_delivery.description",
    objectives = {
        {
            type = "pickup",
            target = "delivery_package",
            count = 1,
            npc = "passerby_01",  -- NPC A (area1)
            description_key = "quests.package_delivery.obj_1"
        },
        {
            type = "deliver",
            target = "delivery_package",
            count = 1,
            npc = "townsperson_01",  -- NPC B (area4)
            description_key = "quests.package_delivery.obj_2"
        }
    },
    giver_npc = "passerby_01",      -- Quest giver (area1)
    receiver_npc = "townsperson_01", -- Reward giver (area4)
    rewards = {
        gold = 80,
        exp = 40
    },
    prerequisites = { "slime_menace" },  -- Available after slime_menace completed
    dialogue = {
        offer_text_key = "quests.package_delivery.dialogue_offer",
        accept_text_key = "quests.package_delivery.dialogue_accept",
        decline_response = "main_menu"
    }
}

-- ============================================================================
-- Multi-Objective Quests
-- ============================================================================

quests.village_hero = {
    id = "village_hero",
    title_key = "quests.village_hero.title",
    description_key = "quests.village_hero.description",
    objectives = {
        {
            type = "kill",
            target = "slime",
            count = 15,
            description_key = "quests.village_hero.obj_1"
        },
        {
            type = "collect",
            target = "healing_herb",
            count = 5,
            description_key = "quests.village_hero.obj_2"
        },
        {
            type = "talk",
            target = "elder",
            count = 1,
            description_key = "quests.village_hero.obj_3"
        }
    },
    giver_npc = "elder",
    rewards = {
        gold = 500,
        exp = 250,
        items = { "iron_sword", "small_potion", "small_potion", "small_potion" }
    },
    prerequisites = { "slime_menace", "herb_gathering" }
}

-- ============================================================================
-- Story Quests (Chain)
-- ============================================================================

quests.mysterious_stranger = {
    id = "mysterious_stranger",
    title_key = "quests.mysterious_stranger.title",
    description_key = "quests.mysterious_stranger.description",
    objectives = {
        {
            type = "talk",
            target = "stranger",
            count = 1,
            description_key = "quests.mysterious_stranger.obj_1"
        }
    },
    giver_npc = "villager_main",
    rewards = {
        gold = 50,
        exp = 30
    },
    dialogue = {
        offer_text_key = "quests.mysterious_stranger.dialogue_offer",
        accept_text_key = "quests.mysterious_stranger.dialogue_accept",
        decline_response = "main_menu"
    }
}

quests.strangers_request = {
    id = "strangers_request",
    title_key = "quests.strangers_request.title",
    description_key = "quests.strangers_request.description",
    objectives = {
        {
            type = "explore",
            target = "level2_area1",
            count = 1,
            description_key = "quests.strangers_request.obj_1"
        },
        {
            type = "collect",
            target = "ancient_artifact",
            count = 1,
            description_key = "quests.strangers_request.obj_2"
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
