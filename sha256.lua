-- SHA-256 in plain Lua, since WoW doesn't come with one.
-- shared.sha256("some text") gives back the 64-character hex hash.
-- Nothing in here needs changing. DeeprunTithe gets an identical copy.

local addon_name, shared = ...

local two_to_the_32 = 4294967296


-- WoW's Lua has no bit operators, so these work through the 32 bits one at a time with plain math

local function bitAnd(a, b)
    local result = 0
    local place_value = 1

    for bit_number = 1, 32 do
        if a % 2 == 1 and b % 2 == 1 then
            result = result + place_value
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        place_value = place_value * 2
    end

    return result
end


local function bitXor(a, b)
    local result = 0
    local place_value = 1

    for bit_number = 1, 32 do
        if a % 2 ~= b % 2 then
            result = result + place_value
        end
        a = math.floor(a / 2)
        b = math.floor(b / 2)
        place_value = place_value * 2
    end

    return result
end


local function bitNot(a)
    return two_to_the_32 - 1 - a
end


local function shiftRight(a, count)
    return math.floor(a / 2 ^ count)
end


-- Bits that fall off the right end come back in on the left
local function rotateRight(a, count)
    local fallen_off = a % 2 ^ count
    return math.floor(a / 2 ^ count) + fallen_off * 2 ^ (32 - count)
end


-- The fixed numbers from the SHA-256 standard
local round_constants = {
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
}


function shared.sha256(message)
    -- Pad the message: one 1 bit, zeros, then the original length in bits as 8 bytes
    local message_bits = #message * 8
    message = message .. "\128"

    while #message % 64 ~= 56 do
        message = message .. "\0"
    end

    for byte_number = 7, 0, -1 do
        message = message .. string.char(math.floor(message_bits / 2 ^ (8 * byte_number)) % 256)
    end

    local hash_values = {
        0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
    }

    -- Work through the message 64 bytes at a time
    for chunk_start = 1, #message, 64 do
        local words = {}

        for word_number = 1, 16 do
            local byte_position = chunk_start + (word_number - 1) * 4
            local byte1, byte2, byte3, byte4 = string.byte(message, byte_position, byte_position + 3)
            words[word_number] = byte1 * 16777216 + byte2 * 65536 + byte3 * 256 + byte4
        end

        for word_number = 17, 64 do
            local word15 = words[word_number - 15]
            local word2 = words[word_number - 2]
            local mix0 = bitXor(bitXor(rotateRight(word15, 7), rotateRight(word15, 18)), shiftRight(word15, 3))
            local mix1 = bitXor(bitXor(rotateRight(word2, 17), rotateRight(word2, 19)), shiftRight(word2, 10))
            words[word_number] = (words[word_number - 16] + mix0 + words[word_number - 7] + mix1) % two_to_the_32
        end

        -- The standard calls these eight working values a through h
        local a = hash_values[1]
        local b = hash_values[2]
        local c = hash_values[3]
        local d = hash_values[4]
        local e = hash_values[5]
        local f = hash_values[6]
        local g = hash_values[7]
        local h = hash_values[8]

        for round = 1, 64 do
            local e_mix = bitXor(bitXor(rotateRight(e, 6), rotateRight(e, 11)), rotateRight(e, 25))
            local choose = bitXor(bitAnd(e, f), bitAnd(bitNot(e), g))
            local temp1 = (h + e_mix + choose + round_constants[round] + words[round]) % two_to_the_32

            local a_mix = bitXor(bitXor(rotateRight(a, 2), rotateRight(a, 13)), rotateRight(a, 22))
            local majority = bitXor(bitXor(bitAnd(a, b), bitAnd(a, c)), bitAnd(b, c))
            local temp2 = (a_mix + majority) % two_to_the_32

            h = g
            g = f
            f = e
            e = (d + temp1) % two_to_the_32
            d = c
            c = b
            b = a
            a = (temp1 + temp2) % two_to_the_32
        end

        hash_values[1] = (hash_values[1] + a) % two_to_the_32
        hash_values[2] = (hash_values[2] + b) % two_to_the_32
        hash_values[3] = (hash_values[3] + c) % two_to_the_32
        hash_values[4] = (hash_values[4] + d) % two_to_the_32
        hash_values[5] = (hash_values[5] + e) % two_to_the_32
        hash_values[6] = (hash_values[6] + f) % two_to_the_32
        hash_values[7] = (hash_values[7] + g) % two_to_the_32
        hash_values[8] = (hash_values[8] + h) % two_to_the_32
    end

    -- Each value as 8 hex characters, written as two halves so big numbers print right
    local hex_text = ""
    for value_number = 1, 8 do
        local value = hash_values[value_number]
        hex_text = hex_text .. string.format("%04x%04x", math.floor(value / 65536), value % 65536)
    end

    return hex_text
end
