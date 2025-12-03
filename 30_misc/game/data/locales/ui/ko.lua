-- game/data/locales/ko.lua
-- Korean translations

return {
    ko = {
        -- Main Menu
        menu = {
            continue = "이어하기",
            new_game = "새 게임",
            load_game = "불러오기",
            settings = "설정",
            quit = "종료",
            quit_to_menu = "메뉴로",
        },

        -- Pause Menu
        pause = {
            title = "일시정지",
            resume = "계속하기",
            restart_here = "여기서 다시",
            load_last_save = "마지막 저장",
        },

        -- Game Over
        gameover = {
            title = "게임 오버",
        },

        -- Ending
        ending = {
            title = "축하합니다!",
        },

        -- Settings
        settings = {
            title = "설정",
            resolution = "해상도",
            fullscreen = "전체화면",
            monitor = "모니터",
            master_volume = "전체 볼륨",
            bgm_volume = "배경음악",
            sfx_volume = "효과음",
            mute = "음소거",
            vibration = "진동",
            vibration_strength = "진동 세기",
            deadzone = "데드존",
            mobile_vibration = "모바일 진동",
            language = "언어",
        },

        -- Shop UI
        shop = {
            buy = "구매",
            sell = "판매",
            ok = "확인",
            cancel = "취소",
            gold = "골드",
            stock = "재고",
            quantity = "수량",
            total = "합계",
            get = "획득",
            purchased = "%{item} %{count}개 구매",
            sold = "%{item} %{count}개 판매",
            not_enough_gold = "골드 부족",
            out_of_stock = "재고 없음",
            no_items = "아이템 없음",
            nothing_in_stock = "판매 중인 물품 없음",
            no_items_to_sell = "판매할 아이템 없음",
            hint_select = "선택",
            hint_close = "닫기",
            hint_tab = "탭",
            hint_qty = "수량",
            hint_qty_10 = "+/-10",
        },

        -- HUD
        hud = {
            level = "Lv",
            gold = "골드",
            hp = "HP",
            exp = "경험치",
            invincible = "무적",
            dodging = "회피 중",
            evading = "회피 중",
            parry_ready = "패리 준비!",
            parry_cd = "패리 대기",
            dodge = "회피",
            evade = "회피",
            dodge_evade = "회피",
            parry = "패리!",
            perfect_parry = "퍼펙트 패리!",
        },

        -- Save/Load
        save = {
            title = "저장하기",
            load_title = "불러오기",
            new_game_title = "새 게임",
            slot = "슬롯 %{num}",
            empty = "비어있음",
            saved = "저장 완료!",
            confirm_overwrite = "덮어쓰시겠습니까?",
            confirm_delete = "삭제하시겠습니까?",
            yes = "예",
            no = "아니오",
            select_slot = "저장 슬롯 선택",
            back_to_menu = "메뉴로 돌아가기",
            action_save = "저장",
            action_load = "불러오기",
            unknown = "알 수 없음",
            confirm_delete_slot = "슬롯 %{num}을 삭제하시겠습니까?",
            cannot_undo = "이 작업은 취소할 수 없습니다!",
            action_start = "시작",
            overwrite = "덮어쓰기?",
        },

        -- Inventory
        inventory = {
            title = "인벤토리",
            equipment = "장비",
            use = "사용",
            equip = "장착",
            unequip = "해제",
            drop = "버리기",
            empty_slot = "비어있음",
            press_to_close = "%{key1} 또는 %{key2} 키로 닫기",
            press = "누르기",
            twice_to_use = "두 번 눌러 사용",
            press_to_use = "%{key} 키로 사용",
            no_items = "인벤토리가 비어있습니다",
            equipment_drag = "장비 (슬롯에 드래그)",
            can_use = "사용 가능",
            cannot_use = "사용 불가 (HP 가득)",
            equipped = "장착됨",
            pos = "위치",
            size = "크기",
        },

        -- Quest Log
        quest = {
            title = "퀘스트",
            active = "진행 중",
            available = "수락 가능",
            completed = "완료",
            all = "전체",
            objectives = "목표",
            rewards = "보상",
            accept = "수락",
            decline = "거절",
            turn_in = "완료",
            complete = "퀘스트 완료",
            accepted_message = "행운을 빕니다!",
            declined_message = "마음이 바뀌면 다시 오세요.",
            thank_you = "감사합니다!",
            ready_turn_in = "보고 가능",
            more_quests = "+ %{count}개 더...",
            no_quests = "퀘스트 없음",
            select_to_view = "상세 정보를 보려면 퀘스트를 선택하세요",
            in_progress = "진행 중",
            description = "설명",
            reward_gold = "골드",
            reward_exp = "경험치",
            reward_items = "아이템",
            help_navigate = "방향키: 이동",
            help_select = "Enter: 선택",
        },

        -- Common
        common = {
            back = "뒤로",
            close = "닫기",
            confirm = "확인",
            continue = "계속",
            on = "켜짐",
            off = "꺼짐",
        },

        -- Prompts
        prompt = {
            interact = "상호작용",
            talk = "대화",
            save = "저장",
            pickup = "줍기",
        },
    }
}
