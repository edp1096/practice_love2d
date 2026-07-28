-- Process-scoped single-instance lock for desktop builds.

local locker = {}

local platform = love.system.getOS()
local is_desktop =
    platform == "Windows" or platform == "Linux" or platform == "OS X"
local is_windows = platform == "Windows"
local ffi = is_desktop and require("ffi") or nil

local lock_handle = nil
local kernel32 = nil

if is_desktop then
    if is_windows then
        ffi.cdef [[
            void* __stdcall CreateMutexA(void* attributes, int initial_owner,
                                         const char* name);
            unsigned long __stdcall GetLastError(void);
            int __stdcall CloseHandle(void* object);
        ]]
        kernel32 = ffi.load("kernel32")
    else
        ffi.cdef [[
            void* fopen(const char* filename, const char* mode);
            int fileno(void* stream);
            int flock(int fd, int operation);
            int fclose(void* stream);
        ]]
    end
end

local function init_windows_lock()
    local ERROR_ALREADY_EXISTS = 183
    lock_handle =
        kernel32.CreateMutexA(nil, 1, "MyLOVEGame_SingleInstance")
    if lock_handle == nil or lock_handle == ffi.NULL then
        return false
    end
    if kernel32.GetLastError() == ERROR_ALREADY_EXISTS then
        kernel32.CloseHandle(lock_handle)
        lock_handle = nil
        return false
    end
    return true
end

local function init_unix_lock()
    local LOCK_EX = 2
    local LOCK_NB = 4
    local lock_path =
        love.filesystem.getSaveDirectory() .. "/instance.lock"
    lock_handle = ffi.C.fopen(lock_path, "a+")
    if lock_handle == nil or lock_handle == ffi.NULL then
        return false
    end
    if ffi.C.flock(ffi.C.fileno(lock_handle), bit.bor(LOCK_EX, LOCK_NB)) ~= 0 then
        ffi.C.fclose(lock_handle)
        lock_handle = nil
        return false
    end
    return true
end

function locker:ProcInit()
    if not is_desktop then return true end
    local success =
        is_windows and init_windows_lock() or init_unix_lock()
    if not success then
        love.window.showMessageBox(
            "Already Running",
            "Game is already running!   \n",
            "error"
        )
        love.event.quit()
        return false
    end
    return true
end

function locker:ProcQuit()
    if not lock_handle then return end
    if is_windows then
        kernel32.CloseHandle(lock_handle)
    else
        ffi.C.fclose(lock_handle)
    end
    lock_handle = nil
end

return locker
