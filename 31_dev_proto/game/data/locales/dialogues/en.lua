-- game/data/locales/dialogues/en.lua
-- English dialogue translations

return {
    en = {
        dialogue = {
            -- Villager 01 (passerby_01) - Quest giver
            villager_01 = {
                greeting = "Hello traveler!",
                how_can_i_help = "How can I help you?",
                choice_village_info = "Tell me about this village",
                choice_rumors = "Any rumors?",
                choice_other_quest = "Other quest?",
                choice_goodbye = "Goodbye",

                village_info = "This is a peaceful village. We have a merchant and a blacksmith nearby.",
                choice_interesting = "Interesting. What else?",
                choice_thanks_info = "Thanks for the info",

                more_info_1 = "There's also an old forest to the east. It's been there for centuries, long before our village was founded.",
                more_info_2 = "Many travelers have explored it, but few have ventured deep inside. The trees grow thick and the paths are winding.",
                more_info_3 = "Some say slimes live there, gathering in the darker corners. They're not dangerous alone, but in groups...",
                choice_tell_slimes = "Tell me more about the slimes",
                choice_interesting_story = "Interesting story",

                slimes = "Yes, slimes! They've been bothering us lately. Maybe you could help?",
                choice_sure_help = "Sure, I'll help!",
                choice_think_about_it = "I'll think about it",
                choice_not_interested = "Not interested",

                quest_accepted = "Thank you! Please defeat 3 slimes. They're usually found in the forest to the east.",
                choice_get_on_it = "I'll get right on it",
                choice_tell_more = "Tell me more",

                rumors = "I heard the merchant has rare items for sale. You should check them out!",
                choice_good_to_know = "Good to know",

                no_more_quests = "I don't have any more tasks at the moment. Thank you for all your help!",

                farewell = "Take care, traveler!",
            },

            -- Villager 02 (passerby_02) - Casual passerby
            villager_02 = {
                greeting = "Oh, hello there!",
                nice_weather = "Nice weather we're having, isn't it?",
                choice_beautiful_day = "Yes, it's a beautiful day",
                choice_live_here = "Do you live around here?",
                choice_see_around = "See you around",

                agree = "Perfect for a stroll through town. I love days like this.",
                choice_me_too = "Me too",
                choice_know_area = "Do you know anything about this area?",

                local_info = "I'm just passing through, actually. But I've heard there's a merchant nearby with interesting goods.",
                choice_thanks_tip = "Thanks for the tip",
                choice_anything_else = "Anything else?",

                more_info = "Well, I did see some slimes in the forest earlier. Be careful if you go that way!",
                choice_keep_in_mind = "I'll keep that in mind",

                farewell = "Take care out there!",
            },

            -- Merchant
            merchant = {
                welcome = "Welcome to my shop!",
                what_brings_you = "What brings you here?",
                choice_what_sell = "What do you sell?",
                choice_just_browsing = "Just browsing",
                choice_goodbye = "Goodbye",

                shop_info = "I have potions, weapons, and rare items. Everything an adventurer needs!",
                choice_see_goods = "Let me see your goods",
                choice_maybe_later = "Maybe later",

                browsing = "Take your time! Let me know if you need anything.",
                choice_actually_sell = "Actually, what do you sell?",
                choice_thanks = "Thanks",

                open_shop = "Here's what I have in stock!",

                farewell = "Come again!",
            },

            -- Guard
            guard = {
                move_along = "Move along, citizen. Nothing to see here.",
            },

            -- Surrendered Bandit
            surrendered_bandit = {
                surrender = "Please... spare me! I surrender!",
                tell_anything = "I'll tell you anything you want to know!",
                choice_why_attack = "Why did you attack me?",
                choice_hideout = "Where is your hideout?",
                choice_let_go = "I'll let you go this time.",

                reason = "I... I was desperate! The village cut off our supplies...",
                hideout = "It's in the northern woods! But please, don't hurt my friends!",
                mercy = "Thank you! I won't forget this kindness...",
            },

            -- Deceiver
            deceiver = {
                greeting = "Well, well... what do we have here?",
                looking_valuable = "Looking for something... valuable?",
                choice_who_are_you = "Who are you?",
                choice_passing_through = "I'm just passing through.",
                choice_suspicious = "You seem suspicious.",

                identity = "Just a humble traveler... like yourself.",
                passing = "Of course, of course... Safe travels, then.",
                suspicious = "Suspicious? Me? How... perceptive of you.",
                hostile = "Perhaps TOO perceptive. I can't let you leave now!",
            },

            -- Vehicle Dealer
            vehicle_dealer = {
                greeting = "Hey there! I run the vehicle rental shop around here.",
                offer = "Need a ride? I've got a special promotion going on.",
                choice_free_scooter = "Free scooter? Sure!",
                choice_no_thanks = "No thanks.",
                give_scooter = "Here you go! Press V to summon it anytime.",
                farewell = "Come back if you change your mind!",
            },

            -- Common/Shared
            common = {
                speaker_villager = "Villager",
                speaker_passerby = "Passerby",
                speaker_merchant = "Merchant",
                speaker_guard = "Guard",
                speaker_bandit = "Bandit",
                speaker_deceiver = "Deceiver",
                speaker_dealer = "Dealer",
                speaker_unknown = "???",
            },
        }
    }
}
