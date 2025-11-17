-- Static file server for LÖVE2D web build
-- Usage: lua server.lua [port]

local LUASOCKET_DIR = "vendor/socket"

package.path = package.path .. ";./?.lua;" .. LUASOCKET_DIR .. "/?.lua"
package.cpath = package.cpath .. ";./?.dll;" .. LUASOCKET_DIR .. "/?/core.dll"

local socket = require("socket")

local port = tonumber(arg[1]) or 8080

-- MIME types
local mime_types = {
    html = "text/html",
    css = "text/css",
    js = "application/javascript",
    png = "image/png",
    jpg = "image/jpeg",
    jpeg = "image/jpeg",
    gif = "image/gif",
    svg = "image/svg+xml",
    wasm = "application/wasm",
    data = "application/octet-stream",
    json = "application/json",
    woff = "font/woff",
    woff2 = "font/woff2",
    ttf = "font/ttf",
    ico = "image/x-icon"
}

local function get_mime_type(path)
    local ext = path:match("%.([^%.]+)$")
    return mime_types[ext] or "application/octet-stream"
end

local function send_response(client, status, content_type, body)
    local response = string.format(
        "HTTP/1.1 %s\r\n" ..
        "Content-Type: %s\r\n" ..
        "Content-Length: %d\r\n" ..
        "Access-Control-Allow-Origin: *\r\n" ..
        "Cross-Origin-Opener-Policy: same-origin\r\n" ..
        "Cross-Origin-Embedder-Policy: require-corp\r\n" ..
        "Cache-Control: no-cache\r\n" ..
        "Connection: close\r\n" ..
        "\r\n",
        status, content_type, #body
    )
    client:send(response)
    client:send(body)
end

local function serve_file(client, filepath)
    local file = io.open(filepath, "rb")
    if not file then
        send_response(client, "404 Not Found", "text/plain", "404 Not Found")
        return
    end

    local content = file:read("*all")
    file:close()

    local mime_type = get_mime_type(filepath)
    send_response(client, "200 OK", mime_type, content)
end

local function handle_client(client)
    client:settimeout(10)

    local request_line = client:receive()
    if not request_line then return end

    local method, path = request_line:match("^(%S+)%s+(%S+)")
    if not path then return end

    -- Strip query string
    path = path:match("^([^?]*)") or path

    -- Read headers (but we don't need them for static files)
    while true do
        local line = client:receive()
        if not line or line == "" then break end
    end

    -- Log request
    print(string.format("[%s] %s %s", os.date("%H:%M:%S"), method, path))

    -- Default to index.html
    if path == "/" then
        path = "/index.html"
    end

    -- Security: prevent directory traversal
    path = path:gsub("%.%.", "")

    -- Serve file (current directory is web_build)
    local filepath = "." .. path
    serve_file(client, filepath)
end

-- Create and bind server
local server = socket.tcp()
server:setoption("reuseaddr", true)  -- Allow immediate port reuse
assert(server:bind("*", port))
server:listen(5)
server:settimeout(0.1)

print("=========================================")
print("Static File Server for LÖVE2D Web Build")
print("=========================================")
print("Server running at http://localhost:" .. port)
print("Press Ctrl+C to stop")
print("")

-- Main server loop
while true do
    local client = server:accept()
    if client then
        local ok, err = pcall(handle_client, client)
        if not ok then
            print("Error handling request:", err)
        end
        client:close()
    end
end
