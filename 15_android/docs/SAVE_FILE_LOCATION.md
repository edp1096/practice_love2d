# 세이브 파일 저장 위치

## 기본 정보

LÖVE2D는 각 운영체제의 표준 저장 위치를 사용합니다.

---

## 운영체제별 저장 위치

### Windows
```
%APPDATA%\LOVE\{게임이름}\saves\
```

**실제 경로 예시:**
```
C:\Users\사용자이름\AppData\Roaming\LOVE\Hello Love2D\saves\
├── save_1.json
├── save_2.json
├── save_3.json
└── recent_slot.txt
```

**빠른 접근:**
1. `Win + R` 키 누르기
2. `%APPDATA%\LOVE` 입력
3. 게임 폴더 찾기

---

### Linux
```
~/.local/share/love/{게임이름}/saves/
```

**실제 경로 예시:**
```
/home/사용자이름/.local/share/love/Hello Love2D/saves/
├── save_1.json
├── save_2.json
├── save_3.json
└── recent_slot.txt
```

**터미널에서 접근:**
```bash
cd ~/.local/share/love/
ls
cd "Hello Love2D"
cd saves
```

---

### macOS
```
~/Library/Application Support/LOVE/{게임이름}/saves/
```

**실제 경로 예시:**
```
/Users/사용자이름/Library/Application Support/LOVE/Hello Love2D/saves/
├── save_1.json
├── save_2.json
├── save_3.json
└── recent_slot.txt
```

**Finder에서 접근:**
1. Finder 열기
2. `Cmd + Shift + G`
3. `~/Library/Application Support/LOVE/` 입력

---

## 게임 이름 (Identity) 설정

### conf.lua 설정
```lua
function love.conf(t)
    t.identity = "HelloLove2D"  -- 이 이름이 폴더명이 됨
    t.title = "Hello Love2D"
    -- ...
end
```

### 기본값
identity가 설정되지 않으면 게임 폴더명이 사용됩니다.

---

## 저장 경로 확인 방법

### 1. 코드로 확인
```lua
local save_dir = love.filesystem.getSaveDirectory()
print("Save directory: " .. save_dir)
```

**출력 예시:**
```
Windows: C:\Users\Username\AppData\Roaming\LOVE\HelloLove2D
Linux:   /home/username/.local/share/love/HelloLove2D
macOS:   /Users/username/Library/Application Support/LOVE/HelloLove2D
```

### 2. 게임 내에서 확인
Save 시스템 초기화 시 콘솔에 출력:
```lua
function save:init()
    local success = love.filesystem.createDirectory(self.SAVE_DIRECTORY)
    if success then
        print("Save system initialized: " .. love.filesystem.getSaveDirectory())
    end
end
```

### 3. 폴더 바로 열기 기능 추가
```lua
-- 운영체제별로 폴더 열기
function save:openSaveFolder()
    local save_dir = love.filesystem.getSaveDirectory()
    
    if love.system.getOS() == "Windows" then
        os.execute('explorer "' .. save_dir .. '"')
    elseif love.system.getOS() == "Linux" then
        os.execute('xdg-open "' .. save_dir .. '"')
    elseif love.system.getOS() == "OS X" then
        os.execute('open "' .. save_dir .. '"')
    end
end
```

---

## 파일 구조

```
{게임이름}/
├── saves/                     ← save:SAVE_DIRECTORY
│   ├── save_1.json           ← 슬롯 1
│   ├── save_2.json           ← 슬롯 2
│   ├── save_3.json           ← 슬롯 3
│   └── recent_slot.txt       ← 최근 플레이 슬롯
├── config.ini                ← 게임 설정
└── (기타 데이터 파일)
```

---

## 세이브 파일 내용

### save_1.json 예시
```json
{
  "hp": 80,
  "max_hp": 100,
  "map": "assets/maps/level2/area3.lua",
  "x": 450.5,
  "y": 300.2,
  "timestamp": 1705312345,
  "slot": 1
}
```

### recent_slot.txt 예시
```
2
```

---

## 보안 및 주의사항

### 1. 사용자 데이터 보호
- 민감한 정보 저장 금지
- 암호화 없음 (JSON 평문)
- 누구나 읽고 수정 가능

### 2. 파일 크기
- 최소화 권장
- 큰 데이터는 압축 고려

### 3. 백업
- 자동 백업 기능 없음
- 사용자가 수동으로 백업해야 함

---

## 세이브 파일 관리

### 1. 수동 삭제
해당 폴더로 가서 .json 파일 삭제

### 2. 게임 내 삭제
- Load Game 화면: Delete 키
- New Game 화면: Delete 키 (예정)
- Save Point 화면: Delete 키 (예정)

### 3. 전체 초기화
saves 폴더 전체 삭제

---

## 디버깅

### 1. 파일 존재 확인
```lua
local filepath = "saves/save_1.json"
local info = love.filesystem.getInfo(filepath)
if info then
    print("File exists: " .. filepath)
    print("Size: " .. info.size .. " bytes")
else
    print("File not found: " .. filepath)
end
```

### 2. 모든 세이브 파일 나열
```lua
function save:listAllSaves()
    local files = love.filesystem.getDirectoryItems(self.SAVE_DIRECTORY)
    print("Save files:")
    for _, file in ipairs(files) do
        print("  - " .. file)
    end
end
```

### 3. 파일 내용 읽기
```lua
local contents = love.filesystem.read("saves/save_1.json")
print(contents)
```

---

## 개발 중 팁

### 1. 테스트용 세이브 빠르게 생성
```lua
-- 개발자 콘솔에서 실행
for i = 1, 3 do
    local data = {
        hp = 100,
        max_hp = 100,
        map = "assets/maps/level1/area1.lua",
        x = 400,
        y = 250
    }
    save_sys:saveGame(i, data)
end
```

### 2. 세이브 폴더 열기 단축키
```lua
-- main.lua 또는 debug system에 추가
if key == "f10" then
    save_sys:openSaveFolder()
end
```

### 3. 세이브 상태 출력
```lua
function save:printStatus()
    print("=== Save System Status ===")
    print("Directory: " .. love.filesystem.getSaveDirectory())
    print("Has saves: " .. tostring(self:hasSaveFiles()))
    print("Recent slot: " .. tostring(self:loadRecentSlot()))
    
    for i = 1, self.MAX_SLOTS do
        local info = self:getSlotInfo(i)
        if info.exists then
            print(string.format("Slot %d: %s (HP: %d/%d)", 
                i, info.map_display, info.hp, info.max_hp))
        else
            print(string.format("Slot %d: Empty", i))
        end
    end
end
```

---

## 자주 묻는 질문

### Q: 세이브 파일을 다른 컴퓨터로 옮길 수 있나요?
**A:** 네, save_X.json 파일을 복사하면 됩니다.
```bash
# Windows에서 Linux로
복사: C:\Users\...\LOVE\HelloLove2D\saves\save_1.json
붙여넣기: ~/.local/share/love/HelloLove2D/saves/save_1.json
```

### Q: 세이브 파일을 찾을 수 없어요
**A:** 게임을 한 번 실행하면 폴더가 자동 생성됩니다.
또는 코드로 확인:
```lua
print(love.filesystem.getSaveDirectory())
```

### Q: 세이브 파일을 수정할 수 있나요?
**A:** 네, JSON 파일이므로 텍스트 에디터로 편집 가능합니다.
**주의:** 잘못된 형식으로 수정하면 로드 실패

### Q: 세이브 파일 백업 방법?
**A:** saves 폴더 전체를 복사하세요.
```bash
# 백업
cp -r ~/.local/share/love/HelloLove2D/saves ~/game_backup/

# 복구
cp -r ~/game_backup/saves ~/.local/share/love/HelloLove2D/
```

### Q: 게임 삭제 시 세이브도 삭제되나요?
**A:** 아니요, 세이브는 별도 위치에 보관됩니다.
게임을 삭제해도 세이브는 남아있습니다.
