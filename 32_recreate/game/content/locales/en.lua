return {
    schema_version = 1,
    kind = "locale",
    id = "locale.en",
    name = "English",
    code = "en",
    strings = {
        ["ui.currency"] = "Currency",
        ["ui.stat.attack"] = "ATK",
        ["ui.stat.defense"] = "DEF",
        ["ui.stat.move"] = "MOVE",
        ["ui.shop.buy"] = "BUY",
        ["ui.shop.sell"] = "SELL",
        ["ui.shop.owned"] = "owned %d",
        ["ui.shop.purchased"] = "Purchased.",
        ["ui.shop.sold"] = "Sold.",
        ["ui.input.move"] = "Move: WASD/arrows/stick",
        ["ui.input.jump"] = "Jump: W/Up/A",
        ["ui.input.attack"] = "Attack: Space/X",
        ["ui.input.special"] = "Ranged: F/Y",
        ["ui.input.technique"] = "Whirlwind: Q/RB",
        ["ui.input.dodge"] = "Dodge: Shift/B",
        ["ui.input.parry"] = "Parry: C/LB",
        ["ui.input.interact"] = "Interact: E/X",
        ["ui.input.restart"] = "Restart: R/Back",
        ["ui.input.debug"] = "Debug: F1",
        ["ui.slot.weapon"] = "Weapon",
        ["ui.slot.armor"] = "Armor",
        ["ui.slot.accessory"] = "Accessory",
        ["ui.quest_status.active"] = "Active",
        ["ui.quest_status.completed"] = "Completed",
        ["ui.quest_status.failed"] = "Failed",
        ["ui.cutscene.continue"] = "Enter/Space/A Continue",
        ["ui.cutscene.skip"] = "Esc/B Skip",
        ["notice.intro"] =
            "Talk to the village guide and learn what threatens the grove.",
        ["cutscene.village_arrival.threat"] =
            "A strange unrest has spread from the Quiet Grove to the village.",
        ["cutscene.village_arrival.call"] =
            "Traveler, please speak with me. We need your help.",
        ["notice.quest.accepted"] =
            "Quest started · Training Sword equipped · 25G received",
        ["notice.field.tutorial"] =
            "Space/X Attack · C/LB Parry · Shift/B Dodge · F/Y Ranged",
        ["notice.field_potion.collected"] =
            "You found one potion in the roadside jar.",
        ["notice.field_potion.empty"] = "The jar is already empty.",
        ["notice.field.hazard"] = "The toxic mire drains your health.",
        ["notice.home.rest"] =
            "You rested at home and recovered 30 health.",
        ["notice.grove.warning"] =
            "A powerful presence waits ahead. Parry the guardian's attack.",
        ["notice.quest.completed"] =
            "Quest complete · Potion received · 75G reward",
        ["interaction.talk"] = "Talk",
        ["interaction.shop"] = "Shop",
        ["interaction.collect"] = "Collect",
        ["interaction.inspect"] = "Inspect",
        ["interaction.quest"] = "Ask about work",
        ["interaction.report"] = "Report progress",
        ["interaction.thanks"] = "Talk",
        ["flow.title.heading"] = "Guardian of the Quiet Grove",
        ["flow.title.message"] =
            "Defeat the guardian threatening the village.",
        ["flow.game_over.heading"] = "You Have Fallen",
        ["flow.game_over.message"] =
            "Try again or continue from your last save.",
        ["flow.ending.heading"] = "Peace Returns to the Grove",
        ["flow.ending.message"] =
            "You completed this small but complete adventure. Thank you.",
        ["flow.pause.heading"] = "Paused",
        ["flow.menu.new_game"] = "New Game",
        ["flow.menu.continue"] = "Continue",
        ["flow.menu.quit"] = "Quit",
        ["flow.menu.resume"] = "Resume",
        ["flow.menu.save"] = "Save",
        ["flow.menu.accessibility"] = "Accessibility",
        ["flow.menu.back"] = "Back",
        ["flow.menu.title"] = "Return to Title",
        ["flow.menu.retry"] = "Retry",
        ["flow.controls"] =
            "↑/↓·D-pad Select    Enter/A Confirm    Esc/B Back",
        ["accessibility.heading"] = "Accessibility",
        ["accessibility.message"] =
            "Adjust visual feedback and message duration.",
        ["accessibility.motion"] = "Camera motion",
        ["accessibility.motion.full"] = "Full",
        ["accessibility.motion.reduced"] = "Reduced",
        ["accessibility.motion.off"] = "Off",
        ["accessibility.hit_flash"] = "Hit flash",
        ["accessibility.notice_duration"] = "Message duration",
        ["accessibility.notice_duration.normal"] = "Normal",
        ["accessibility.notice_duration.long"] = "Long",
        ["accessibility.value.on"] = "On",
        ["accessibility.value.off"] = "Off",

        ["stage.village.name"] = "Willow Village",
        ["stage.village_home.name"] = "Village Home",
        ["stage.village_shop.name"] = "Willow General Store",
        ["stage.world_hub.name"] = "East Forest Road",
        ["stage.world_grove.name"] = "Quiet Grove",

        ["npc.guide.name"] = "Guild Guide",
        ["npc.village_guide.name"] = "Village Guide",
        ["npc.merchant.name"] = "Merchant",

        ["dialogue.guide.name"] = "A Small Request",
        ["dialogue.guide.greeting"] =
            "Two slimes are blocking the road. Can you help?",
        ["dialogue.guide.accept"] = "I will handle them.",
        ["dialogue.guide.progress"] = "I am still working on it.",
        ["dialogue.guide.completed"] = "The road is safe now.",
        ["dialogue.guide.leave"] = "Maybe later.",
        ["dialogue.guide.accepted"] =
            "Take this training sword. Come back safely.",
        ["dialogue.guide.reminder"] =
            "Defeat the two slimes near the east road.",
        ["dialogue.guide.thanks"] =
            "Excellent work. The reward is already yours.",

        ["quest.slime_patrol.name"] = "East Road Patrol",
        ["quest.slime_patrol.description"] =
            "Defeat two slimes blocking the east road.",

        ["dialogue.village_guide.name"] = "The Grove in Danger",
        ["dialogue.village_guide.greeting"] =
            "Slimes and the grove guardian are threatening our village.",
        ["dialogue.village_guide.accept"] = "I will stop them.",
        ["dialogue.village_guide.progress"] = "Report my progress.",
        ["dialogue.village_guide.completed"] = "The guardian is defeated.",
        ["dialogue.village_guide.leave"] = "I will return after preparing.",
        ["dialogue.village_guide.accepted"] =
            "Take this training sword. Be careful deep in the grove.",
        ["dialogue.village_guide.reminder"] =
            "Defeat two slimes, then stop the guardian deep in the grove.",
        ["dialogue.village_guide.thanks"] =
            "Excellent work. The grove and village are peaceful again.",

        ["quest.grove_guardian.name"] = "Guardian of the Quiet Grove",
        ["quest.grove_guardian.description"] =
            "Defeat two road slimes and the grove guardian.",

        ["item.training_sword.name"] = "Training Sword",
        ["item.training_sword.description"] =
            "A balanced sword that adds 5 attack.",
        ["item.potion.name"] = "Potion",
        ["item.potion.description"] = "Restores 25 HP.",
        ["item.leather_vest.name"] = "Leather Vest",
        ["item.leather_vest.description"] =
            "Light armor that adds 3 defense.",
        ["item.traveler_boots.name"] = "Traveler Boots",
        ["item.traveler_boots.description"] =
            "An accessory that increases movement speed by 25%.",
        ["shop.village.name"] = "Village Supplies",
    },
}
