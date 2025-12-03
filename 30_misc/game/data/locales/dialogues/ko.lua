-- game/data/locales/dialogues/ko.lua
-- Korean dialogue translations

return {
    ko = {
        dialogue = {
            -- Villager 01 (passerby_01) - Quest giver
            villager_01 = {
                greeting = "안녕하세요, 여행자님!",
                how_can_i_help = "무엇을 도와드릴까요?",
                choice_village_info = "이 마을에 대해 알려주세요",
                choice_rumors = "소문이 있나요?",
                choice_other_quest = "다른 퀘스트가 있나요?",
                choice_goodbye = "안녕히 계세요",

                village_info = "이곳은 평화로운 마을이에요. 근처에 상인과 대장장이가 있답니다.",
                choice_interesting = "흥미롭네요. 또 뭐가 있나요?",
                choice_thanks_info = "알려주셔서 감사합니다",

                more_info_1 = "동쪽에는 오래된 숲이 있어요. 우리 마을이 세워지기 훨씬 전부터 있었던 숲이죠.",
                more_info_2 = "많은 여행자들이 탐험했지만, 깊숙이 들어간 사람은 거의 없어요. 나무가 빽빽하고 길이 꼬불꼬불하거든요.",
                more_info_3 = "어두운 구석에 슬라임들이 모여 산다는 이야기가 있어요. 혼자일 땐 위험하지 않지만, 무리를 지으면...",
                choice_tell_slimes = "슬라임에 대해 더 알려주세요",
                choice_interesting_story = "흥미로운 이야기네요",

                slimes = "네, 슬라임이요! 요즘 우리를 괴롭히고 있어요. 혹시 도와주실 수 있나요?",
                choice_sure_help = "물론이죠, 도와드릴게요!",
                choice_think_about_it = "생각해 볼게요",
                choice_not_interested = "관심 없어요",

                quest_accepted = "감사합니다! 슬라임 3마리를 처치해 주세요. 동쪽 숲에서 주로 발견돼요.",
                choice_get_on_it = "바로 처리하겠습니다",
                choice_tell_more = "더 알려주세요",

                rumors = "상인이 희귀한 물건을 팔고 있다고 들었어요. 한번 확인해 보세요!",
                choice_good_to_know = "좋은 정보네요",

                no_more_quests = "지금은 더 이상 부탁드릴 일이 없어요. 도움 주셔서 감사합니다!",

                farewell = "조심히 가세요, 여행자님!",
            },

            -- Villager 02 (passerby_02) - Casual passerby
            villager_02 = {
                greeting = "어머, 안녕하세요!",
                nice_weather = "날씨가 정말 좋죠?",
                choice_beautiful_day = "네, 아름다운 날이네요",
                choice_live_here = "이 근처에 사세요?",
                choice_see_around = "나중에 봬요",

                agree = "마을을 산책하기 딱 좋은 날이에요. 이런 날이 정말 좋아요.",
                choice_me_too = "저도요",
                choice_know_area = "이 지역에 대해 아시는 게 있나요?",

                local_info = "사실 저도 지나가는 길이에요. 근처에 흥미로운 물건을 파는 상인이 있다고 들었어요.",
                choice_thanks_tip = "알려주셔서 감사해요",
                choice_anything_else = "또 다른 건요?",

                more_info = "아, 아까 숲에서 슬라임을 봤어요. 그쪽으로 가신다면 조심하세요!",
                choice_keep_in_mind = "명심할게요",

                farewell = "조심히 다니세요!",
            },

            -- Merchant
            merchant = {
                welcome = "어서오세요!",
                what_brings_you = "무엇을 찾으시나요?",
                choice_what_sell = "뭘 파시나요?",
                choice_just_browsing = "그냥 구경이요",
                choice_goodbye = "안녕히 계세요",

                shop_info = "포션, 무기, 희귀 아이템까지! 모험가에게 필요한 건 다 있어요!",
                choice_see_goods = "물건을 보여주세요",
                choice_maybe_later = "나중에 올게요",

                browsing = "천천히 구경하세요! 필요한 게 있으면 말씀해 주세요.",
                choice_actually_sell = "그런데, 뭘 파시나요?",
                choice_thanks = "감사합니다",

                open_shop = "여기 재고가 있어요!",

                farewell = "또 오세요!",
            },

            -- Guard
            guard = {
                move_along = "지나가세요, 시민. 여긴 볼 것 없습니다.",
            },

            -- Surrendered Bandit
            surrendered_bandit = {
                surrender = "제발... 살려주세요! 항복합니다!",
                tell_anything = "뭐든 말씀드릴게요!",
                choice_why_attack = "왜 공격한 거야?",
                choice_hideout = "은신처가 어디야?",
                choice_let_go = "이번엔 봐주지.",

                reason = "저... 저도 어쩔 수 없었어요! 마을에서 보급을 끊어서...",
                hideout = "북쪽 숲에 있어요! 하지만 제발, 동료들은 해치지 마세요!",
                mercy = "감사합니다! 이 은혜 잊지 않겠습니다...",
            },

            -- Deceiver
            deceiver = {
                greeting = "이런, 이런... 누가 왔나?",
                looking_valuable = "뭔가... 귀중한 걸 찾고 있나?",
                choice_who_are_you = "당신은 누구요?",
                choice_passing_through = "그냥 지나가는 길이에요.",
                choice_suspicious = "수상해 보이는군요.",

                identity = "그저 겸손한 여행자일 뿐... 당신처럼.",
                passing = "그래, 그래... 조심히 가게.",
                suspicious = "수상하다고? 나를? 눈치가... 빠르군.",
                hostile = "너무 빠른 게 문제야. 이제 보내줄 수 없겠어!",
            },

            -- Common/Shared
            common = {
                speaker_villager = "마을 주민",
                speaker_passerby = "행인",
                speaker_merchant = "상인",
                speaker_guard = "경비병",
                speaker_bandit = "산적",
                speaker_deceiver = "사기꾼",
                speaker_unknown = "???",
            },
        }
    }
}
