-- game/data/locales/quests/ko.lua
-- Korean quest translations

return {
    ko = {
        quests = {
            -- Tutorial Quests
            tutorial_talk = {
                title = "마을 주민 만나기",
                description = "친절한 마을 주민과 대화하여 이 지역에 대해 알아보세요.",
                obj_1 = "마을 주민과 대화하기"
            },

            -- Test Quests
            collect_test = {
                title = "아이템 수집 테스트",
                description = "수집 시스템을 테스트하기 위해 체력 물약을 모으세요.",
                obj_1 = "체력 물약 2개 수집",
                dialogue_offer = "이 근처에서 물약을 구할 수 있는지 확인해보고 싶어요. 체력 물약 2개를 모아올 수 있나요?",
                dialogue_accept = "좋아요! 체력 물약 2개를 모으면 보여주세요."
            },

            explore_test = {
                title = "탐험 테스트",
                description = "탐험 시스템을 테스트하기 위해 두 번째 지역을 방문하세요.",
                obj_1 = "2구역 방문하기",
                dialogue_offer = "동쪽 지역을 탐험해 보셨나요? 그곳이 안전한지 알고 싶어요.",
                dialogue_accept = "감사합니다! 그곳에서 발견한 것을 알려주세요."
            },

            deliver_test = {
                title = "배달 테스트",
                description = "배달 시스템을 테스트하기 위해 작은 물약을 상점 주인에게 배달하세요.",
                obj_1 = "상인에게 작은 물약 배달",
                dialogue_offer = "상점 주인에게 작은 체력 물약을 배달해야 해요. 도와주실 수 있나요?",
                dialogue_accept = "완벽해요! 준비되면 물약을 상점 주인에게 가져다 주세요."
            },

            -- Combat Quests
            slime_menace = {
                title = "슬라임 소탕",
                description = "마을이 슬라임들 때문에 곤란해요. 3마리를 처치해 주세요.",
                obj_1 = "빨간 슬라임 3마리 처치"
            },

            forest_cleanup = {
                title = "숲 정화",
                description = "슬라임 10마리를 처치하여 숲을 정화하세요.",
                obj_1 = "숲에서 슬라임 10마리 처치"
            },

            -- Collection Quests
            herb_gathering = {
                title = "약초 수집",
                description = "치료사가 약을 만들기 위해 약초가 필요해요. 치유 약초 3개를 모아주세요.",
                obj_1 = "치유 약초 3개 수집"
            },

            rare_materials = {
                title = "희귀 재료",
                description = "연금술사의 연구를 위해 희귀한 슬라임 젤을 찾아주세요.",
                obj_1 = "슬라임 젤 5개 수집"
            },

            -- Exploration Quests
            explore_forest = {
                title = "숲 탐험",
                description = "동쪽 숲으로 가서 그 안에 무엇이 있는지 발견하세요.",
                obj_1 = "동쪽 숲 방문",
                dialogue_offer = "동쪽 숲은 광활하고 신비로워요. 탐험하고 발견한 것을 보고해 주시겠어요?",
                dialogue_accept = "좋아요! 숲은 동쪽에 있어요. 조심하세요!"
            },

            ancient_ruins = {
                title = "고대 유적",
                description = "북쪽의 신비로운 유적을 탐험하세요.",
                obj_1 = "고대 유적 발견"
            },

            -- Delivery Quests
            medicine_delivery = {
                title = "약 배달",
                description = "치료사로부터 아픈 상인에게 약을 배달하세요.",
                obj_1 = "상인에게 약 배달"
            },

            letter_delivery = {
                title = "중요한 편지",
                description = "마을 원로로부터 학자에게 중요한 편지를 배달하세요.",
                obj_1 = "학자에게 편지 배달"
            },

            package_delivery = {
                title = "소포 배달",
                description = "마을 주민의 소포를 다른 지역 주민에게 배달하세요.",
                obj_1 = "마을 주민에게서 소포 받기",
                obj_2 = "마을 주민에게 소포 배달",
                dialogue_offer = "저기요, 이 소포를 4구역에 있는 사람에게 배달해 주실 수 있나요? 제가 직접 가기엔 너무 멀어서요.",
                dialogue_accept = "감사합니다! 여기 소포예요. 조심히 배달해 주세요!"
            },

            -- Multi-Objective Quests
            village_hero = {
                title = "마을의 영웅",
                description = "여러 과제를 완료하여 영웅임을 증명하세요.",
                obj_1 = "슬라임 15마리 처치",
                obj_2 = "치유 약초 5개 수집",
                obj_3 = "원로에게 보고"
            },

            -- Story Quests
            mysterious_stranger = {
                title = "수상한 이방인",
                description = "마을에 이방인이 나타났어요. 그들이 원하는 것이 무엇인지 알아보세요.",
                obj_1 = "수상한 이방인과 대화",
                dialogue_offer = "마을 입구 근처에 있는 수상한 이방인을 보셨나요? 그들이 무엇을 원하는지 궁금해요. 말을 걸어봐 주시겠어요?",
                dialogue_accept = "감사합니다! 이방인은 마을 입구 근처에 있을 거예요. 그들이 뭐라고 하는지 알려주세요!"
            },

            strangers_request = {
                title = "이방인의 부탁",
                description = "이방인이 유적에서 고대 유물을 필요로 해요.",
                obj_1 = "고대 유적 수색",
                obj_2 = "고대 유물 찾기"
            }
        }
    }
}
