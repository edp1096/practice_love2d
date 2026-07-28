-- Small non-blocking localhost TCP backend for Linux, macOS, and Windows.

local socket = {}
local ffi = require "ffi"
local platform = love.system.getOS()
local is_windows = platform == "Windows"
local is_macos = platform == "OS X"

local AF_INET = 2
local SOCK_STREAM = 1
local backend
local winsock_started = false

if is_windows then
    ffi.cdef [[
        typedef uintptr_t SOCKET;
        typedef unsigned short sa_family_t;
        typedef unsigned short in_port_t;
        typedef unsigned long in_addr_t;

        struct in_addr { in_addr_t s_addr; };
        struct sockaddr {
            sa_family_t sa_family;
            char sa_data[14];
        };
        struct sockaddr_in {
            sa_family_t sin_family;
            in_port_t sin_port;
            struct in_addr sin_addr;
            unsigned char sin_zero[8];
        };

        int __stdcall WSAStartup(unsigned short version, void* data);
        int __stdcall WSACleanup(void);
        int __stdcall WSAGetLastError(void);
        SOCKET __stdcall socket(int domain, int type, int protocol);
        int __stdcall bind(SOCKET handle, const struct sockaddr* address,
                           int address_length);
        int __stdcall listen(SOCKET handle, int backlog);
        SOCKET __stdcall accept(SOCKET handle, struct sockaddr* address,
                                int* address_length);
        int __stdcall recv(SOCKET handle, char* buffer, int length, int flags);
        int __stdcall send(SOCKET handle, const char* buffer,
                           int length, int flags);
        int __stdcall closesocket(SOCKET handle);
        int __stdcall ioctlsocket(SOCKET handle, long command,
                                  unsigned long* argument);
        int __stdcall setsockopt(SOCKET handle, int level, int option,
                                 const char* value, int length);
        in_port_t __stdcall htons(in_port_t value);
        in_addr_t __stdcall htonl(in_addr_t value);
    ]]
    backend = ffi.load("ws2_32")
else
    ffi.cdef [[
        typedef unsigned short sa_family_t;
        typedef unsigned short in_port_t;
        typedef unsigned int in_addr_t;
        typedef unsigned int socklen_t;
        typedef long ssize_t;

        struct in_addr { in_addr_t s_addr; };
        struct sockaddr {
            sa_family_t sa_family;
            char sa_data[14];
        };
        struct sockaddr_in {
            sa_family_t sin_family;
            in_port_t sin_port;
            struct in_addr sin_addr;
            unsigned char sin_zero[8];
        };

        int socket(int domain, int type, int protocol);
        int bind(int handle, const struct sockaddr* address,
                 socklen_t address_length);
        int listen(int handle, int backlog);
        int accept(int handle, struct sockaddr* address,
                   socklen_t* address_length);
        ssize_t recv(int handle, void* buffer, size_t length, int flags);
        ssize_t send(int handle, const void* buffer, size_t length, int flags);
        int setsockopt(int handle, int level, int option,
                       const void* value, socklen_t length);
        int fcntl(int handle, int command, ...);
        int close(int handle);
        in_port_t htons(in_port_t value);
        in_addr_t htonl(in_addr_t value);
    ]]
    backend = ffi.C
end

local function lastError()
    if is_windows then return tonumber(backend.WSAGetLastError()) end
    return ffi.errno()
end

local function wouldBlock(error_code)
    if is_windows then return error_code == 10035 end
    if is_macos then return error_code == 35 end
    return error_code == 11
end

local function invalid(handle)
    if handle == nil then return true end
    if is_windows then return handle == ffi.cast("SOCKET", -1) end
    return handle < 0
end

local function setNonblocking(handle)
    if is_windows then
        local enabled = ffi.new("unsigned long[1]", 1)
        return backend.ioctlsocket(
            handle,
            ffi.cast("long", 0x8004667e),
            enabled
        ) == 0
    end

    local F_GETFL = 3
    local F_SETFL = 4
    local O_NONBLOCK = is_macos and 0x4 or 0x800
    local flags = backend.fcntl(handle, F_GETFL)
    if flags < 0 then return false end
    return backend.fcntl(
        handle,
        F_SETFL,
        ffi.new("int", bit.bor(flags, O_NONBLOCK))
    ) == 0
end

local function setOptions(handle)
    local level = is_windows and 0xffff or (is_macos and 0xffff or 1)
    local reuse_option = is_windows and 4 or (is_macos and 4 or 2)
    local enabled = ffi.new("int[1]", 1)
    backend.setsockopt(
        handle,
        level,
        reuse_option,
        ffi.cast(is_windows and "const char*" or "const void*", enabled),
        ffi.sizeof(enabled)
    )
    if is_macos then
        backend.setsockopt(
            handle,
            level,
            0x1022,
            ffi.cast("const void*", enabled),
            ffi.sizeof(enabled)
        )
    end
end

function socket.startServer(port)
    if is_windows and not winsock_started then
        local data = ffi.new("uint8_t[512]")
        if backend.WSAStartup(0x0202, data) ~= 0 then
            return nil, "WSAStartup failed"
        end
        winsock_started = true
    end

    local handle = backend.socket(AF_INET, SOCK_STREAM, 0)
    if invalid(handle) then
        local error_code = lastError()
        socket.cleanup()
        return nil, "socket() failed: " .. error_code
    end
    setOptions(handle)
    if not setNonblocking(handle) then
        socket.close(handle)
        socket.cleanup()
        return nil, "could not make debug socket non-blocking"
    end

    local address = ffi.new("struct sockaddr_in")
    address.sin_family = AF_INET
    address.sin_port = backend.htons(port)
    address.sin_addr.s_addr = backend.htonl(0x7f000001)
    if backend.bind(
        handle,
        ffi.cast("const struct sockaddr*", address),
        ffi.sizeof(address)
    ) ~= 0 then
        local error_code = lastError()
        socket.close(handle)
        socket.cleanup()
        return nil, "bind() failed: " .. error_code
    end
    if backend.listen(handle, 4) ~= 0 then
        local error_code = lastError()
        socket.close(handle)
        socket.cleanup()
        return nil, "listen() failed: " .. error_code
    end
    return handle
end

function socket.accept(server)
    local client = backend.accept(server, nil, nil)
    if invalid(client) then
        local error_code = lastError()
        if wouldBlock(error_code) then return nil end
        return nil, "accept() failed: " .. error_code
    end
    setOptions(client)
    if not setNonblocking(client) then
        socket.close(client)
        return nil, "could not make client socket non-blocking"
    end
    return client
end

function socket.receive(client, maximum)
    local buffer = ffi.new("uint8_t[?]", maximum)
    local received = tonumber(backend.recv(client, buffer, maximum, 0))
    if received > 0 then
        return ffi.string(buffer, received)
    elseif received == 0 then
        return nil, "closed"
    end
    local error_code = lastError()
    if wouldBlock(error_code) then return nil, "wait" end
    return nil, "recv() failed: " .. error_code
end

function socket.send(client, data)
    local flags = (not is_windows and not is_macos) and 0x4000 or 0
    local sent = tonumber(backend.send(client, data, #data, flags))
    if sent >= 0 then return sent end
    local error_code = lastError()
    if wouldBlock(error_code) then return nil, "wait" end
    return nil, "send() failed: " .. error_code
end

function socket.close(handle)
    if invalid(handle) then return end
    if is_windows then
        backend.closesocket(handle)
    else
        backend.close(handle)
    end
end

function socket.cleanup()
    if is_windows and winsock_started then
        backend.WSACleanup()
        winsock_started = false
    end
end

return socket
