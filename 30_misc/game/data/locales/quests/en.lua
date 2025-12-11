-- game/data/locales/quests/en.lua
-- English quest translations

return {
    en = {
        quests = {
            -- Tutorial Quests
            tutorial_talk = {
                title = "Meet the Villager",
                description = "Talk to the friendly villager to learn about the area.",
                obj_1 = "Talk to the Villager"
            },

            -- Test Quests
            collect_test = {
                title = "Item Collection Test",
                description = "Collect health potions to test the collection system.",
                obj_1 = "Collect 2 Health Potions",
                dialogue_offer = "I want to check if you can find potions around here. Can you collect 2 health potions?",
                dialogue_accept = "Great! Show me when you have 2 health potions."
            },

            explore_test = {
                title = "Exploration Test",
                description = "Visit the second area to test the exploration system.",
                obj_1 = "Visit Area 2",
                dialogue_offer = "Have you explored the eastern area yet? I'd like to know if it's safe.",
                dialogue_accept = "Thank you! Let me know what you find there."
            },

            deliver_test = {
                title = "Delivery Test",
                description = "Deliver a small potion to the merchant to test the delivery system.",
                obj_1 = "Deliver Small Potion to Merchant",
                dialogue_offer = "I need a small health potion delivered to the merchant. Can you help?",
                dialogue_accept = "Perfect! Take the potion to the merchant at the shop when you're ready."
            },

            -- Combat Quests
            slime_menace = {
                title = "Slime Menace",
                description = "The village is being bothered by slimes. Help by defeating 3 of them.",
                obj_1 = "Defeat 3 red slimes"
            },

            forest_cleanup = {
                title = "Forest Cleanup",
                description = "Clear out the forest by defeating 10 slimes.",
                obj_1 = "Defeat 10 slimes in the forest"
            },

            -- Collection Quests
            herb_gathering = {
                title = "Herb Gathering",
                description = "The healer needs herbs for medicine. Collect 3 healing herbs.",
                obj_1 = "Collect 3 Healing Herbs"
            },

            rare_materials = {
                title = "Rare Materials",
                description = "Find rare slime gel for the alchemist's research.",
                obj_1 = "Collect 5 Slime Gels"
            },

            -- Exploration Quests
            explore_forest = {
                title = "Explore the Forest",
                description = "Venture into the eastern forest and discover what lies within.",
                obj_1 = "Visit the Eastern Forest",
                dialogue_offer = "The eastern forest is vast and mysterious. Would you explore it and report back what you find?",
                dialogue_accept = "Excellent! The forest lies to the east. Be careful out there!"
            },

            ancient_ruins = {
                title = "Ancient Ruins",
                description = "Explore the mysterious ruins to the north.",
                obj_1 = "Discover the Ancient Ruins"
            },

            -- Delivery Quests
            medicine_delivery = {
                title = "Medicine Delivery",
                description = "Deliver medicine from the healer to the sick merchant.",
                obj_1 = "Deliver medicine to the Merchant"
            },

            letter_delivery = {
                title = "Important Letter",
                description = "Deliver an important letter from the village elder to the scholar.",
                obj_1 = "Deliver the letter to the Scholar"
            },

            package_delivery = {
                title = "Package Delivery",
                description = "Deliver a villager's package to someone in another area.",
                obj_1 = "Pick up the package from the Villager",
                obj_2 = "Deliver the package to the Townsperson",
                dialogue_offer = "Hey, could you deliver this package to someone in Area 4? It's too far for me to go myself.",
                dialogue_accept = "Thank you! Here's the package. Please deliver it safely!"
            },

            -- Multi-Objective Quests
            village_hero = {
                title = "Village Hero",
                description = "Prove yourself as a hero by completing multiple tasks.",
                obj_1 = "Defeat 15 slimes",
                obj_2 = "Collect 5 Healing Herbs",
                obj_3 = "Report to the Elder"
            },

            -- Story Quests
            mysterious_stranger = {
                title = "The Mysterious Stranger",
                description = "A stranger has appeared in the village. Find out what they want.",
                obj_1 = "Talk to the Mysterious Stranger",
                dialogue_offer = "Have you noticed that mysterious stranger near the village entrance? I'm curious what they want. Could you talk to them?",
                dialogue_accept = "Thank you! The stranger should be near the village entrance. Let me know what they say!"
            },

            strangers_request = {
                title = "Stranger's Request",
                description = "The stranger needs an ancient artifact from the ruins.",
                obj_1 = "Search the Ancient Ruins",
                obj_2 = "Find the Ancient Artifact"
            }
        }
    }
}
