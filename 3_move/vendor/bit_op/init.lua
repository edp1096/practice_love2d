-- bit.lua : Lua 5.4용 BitOp 호환 라이브러리
-- Lua 5.4에는 비트 연산자가 내장되어 있으므로 이를 이용함

local bit = {}

-- 숫자를 32비트 정수로 변환
function bit.tobit(x)
    return x & 0xffffffff
end

-- 16진수 문자열로 변환
function bit.tohex(x, n)
    n = n or 8
    return string.format("%0" .. n .. "X", x & 0xffffffff)
end

-- 비트 NOT (~x)
function bit.bnot(x)
    return ~x
end

-- 비트 AND (x & y & ...)
function bit.band(x, y, ...)
    local res = x & y
    for i = 1, select("#", ...) do
        res = res & select(i, ...)
    end
    return res
end

-- 비트 OR (x | y | ...)
function bit.bor(x, y, ...)
    local res = x | y
    for i = 1, select("#", ...) do
        res = res | select(i, ...)
    end
    return res
end

-- 비트 XOR (x ~ y ~ ...)
function bit.bxor(x, y, ...)
    local res = x ~ y
    for i = 1, select("#", ...) do
        res = res ~ select(i, ...)
    end
    return res
end

-- 왼쪽 시프트
function bit.lshift(x, n)
    return (x << n) & 0xffffffff
end

-- 오른쪽 시프트 (논리적)
function bit.rshift(x, n)
    return (x >> n) & 0xffffffff
end

-- 오른쪽 시프트 (산술적: 음수 유지)
function bit.arshift(x, n)
    return x >> n
end

-- 왼쪽 회전 (rotate left)
function bit.rol(x, n)
    n = n % 32
    return ((x << n) | (x >> (32 - n))) & 0xffffffff
end

-- 오른쪽 회전 (rotate right)
function bit.ror(x, n)
    n = n % 32
    return ((x >> n) | (x << (32 - n))) & 0xffffffff
end

-- 바이트 스왑 (32비트)
function bit.bswap(x)
    x = x & 0xffffffff
    return ((x >> 24) & 0xff) |
           ((x >> 8)  & 0xff00) |
           ((x << 8)  & 0xff0000) |
           ((x << 24) & 0xff000000)
end

return bit
