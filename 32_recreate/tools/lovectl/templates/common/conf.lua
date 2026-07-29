local headless =
    os.getenv("RECREATE_HEADLESS") == "1" or
    os.getenv("RECREATE_CHECK") == "1"
local automation = os.getenv("RECREATE_AUTOMATION") == "1"

function love.conf(t)
    t.identity = os.getenv("RECREATE_IDENTITY") or "{{IDENTITY}}"
    t.version = "11.5"
    t.console = true
    t.window = headless and false or {
        title = "{{PROJECT_TITLE_LUA}}",
        width = 960,
        height = 540,
        minwidth = 640,
        minheight = 360,
        resizable = true,
        vsync = automation and 0 or 1,
        highdpi = false,
        usedpiscale = true,
    }
    t.modules.audio = not headless
    t.modules.data = true
    t.modules.event = true
    t.modules.font = not headless
    t.modules.graphics = not headless
    t.modules.image = true
    t.modules.joystick = not headless
    t.modules.keyboard = not headless
    t.modules.math = true
    t.modules.mouse = not headless
    t.modules.physics = false
    t.modules.sound = not headless
    t.modules.system = true
    t.modules.thread = false
    t.modules.timer = true
    t.modules.touch = not headless
    t.modules.video = false
    t.modules.window = not headless
end
