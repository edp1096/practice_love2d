-- locker.lua
-- Make sure there is only single instance of the game. PC only.

local locker = {}

local ffi = require("ffi")
local lockHandle = nil
local kernel32 = nil
local isWindows = love.system.getOS() == "Windows"

-- Define FFI functions once at module load time
if isWindows then
    ffi.cdef [[
        void* CreateMutexA(void* lpMutexAttributes, int bInitialOwner, const char* lpName);
        unsigned long GetLastError();
        int CloseHandle(void* hObject);
    ]]
    kernel32 = ffi.load("kernel32")
else
    ffi.cdef [[
        typedef struct sem_t sem_t;
        sem_t* sem_open(const char *name, int oflag, unsigned int mode, unsigned int value);
        int sem_close(sem_t *sem);
        int sem_unlink(const char *name);
        int sem_trywait(sem_t *sem);
    ]]
end

local function initWindowsLock()
    local ERROR_ALREADY_EXISTS = 183

    if kernel32 then
        lockHandle = kernel32.CreateMutexA(nil, 1, "MyLOVEGame_SingleInstance")
        return kernel32.GetLastError() ~= ERROR_ALREADY_EXISTS
    end
end

local function initUnixLock()
    local O_CREAT = 64
    local O_EXCL = 128
    local SEM_NAME = "/mylovegame_lock"

    lockHandle = ffi.C.sem_open(SEM_NAME, bit.bor(O_CREAT, O_EXCL), 0x1B6, 1)

    if lockHandle == ffi.cast("sem_t*", -1) then
        return false
    end

    if ffi.C.sem_trywait(lockHandle) ~= 0 then
        ffi.C.sem_close(lockHandle)
        ffi.C.sem_unlink(SEM_NAME)
        return false
    end

    return true
end

local function quitWindows()
    if lockHandle then
        if kernel32 then kernel32.CloseHandle(lockHandle) end
        lockHandle = nil
    end
end

local function quitUnix()
    if lockHandle then
        ffi.C.sem_close(lockHandle)
        ffi.C.sem_unlink("/mylovegame_lock")
        lockHandle = nil
    end
end

function locker:ProcInit()
    local success

    -- Use explicit if-else instead of 'and ... or ...' pattern
    if isWindows then
        success = initWindowsLock()
    else
        success = initUnixLock()
    end

    if not success then
        love.window.showMessageBox("Already Running", "Game is already running!   \n", "error")
        love.event.quit()
        return false
    end

    return true
end

function locker:ProcQuit()
    if isWindows then
        quitWindows()
    else
        quitUnix()
    end
end

return locker
