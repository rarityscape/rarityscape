-- JSON for the rarity API's request and response bodies (the plugin API has no JSON library).
-- encode: tables become arrays when they have items 1..n (or are marked with json.array, for
-- an empty array), objects otherwise. decode: objects -> tables with string keys, arrays ->
-- sequences; null is dropped (nil).

local json = {}

local ARRAY = {} -- metatable marking a table as a JSON array

-- Marks a table (possibly empty) to encode as an array.
function json.array(items)
    return setmetatable(items or {}, ARRAY)
end

local ESCAPES = { ['"'] = '\\"', ["\\"] = "\\\\", ["\b"] = "\\b", ["\f"] = "\\f", ["\n"] = "\\n",
                  ["\r"] = "\\r", ["\t"] = "\\t" }

local function encodeString(text)
    return '"' .. text:gsub('[%c"\\]', function(c)
        return ESCAPES[c] or string.format("\\u%04x", c:byte())
    end) .. '"'
end

local function encode(value, out)
    local kind = type(value)
    if kind == "table" then
        if getmetatable(value) == ARRAY or #value > 0 then
            out[#out + 1] = "["
            for i, item in ipairs(value) do
                out[#out + 1] = i > 1 and "," or ""
                encode(item, out)
            end
            out[#out + 1] = "]"
        else
            out[#out + 1] = "{"
            local first = true
            for key, item in pairs(value) do
                out[#out + 1] = (first and "" or ",") .. encodeString(tostring(key)) .. ":"
                first = false
                encode(item, out)
            end
            out[#out + 1] = "}"
        end
    elseif kind == "string" then
        out[#out + 1] = encodeString(value)
    elseif kind == "number" then
        out[#out + 1] = math.type(value) == "integer" and string.format("%d", value) or string.format("%.14g", value)
    elseif kind == "boolean" then
        out[#out + 1] = tostring(value)
    else
        error("json: can't encode a " .. kind)
    end
end

function json.encode(value)
    local out = {}
    encode(value, out)
    return table.concat(out)
end

-- Decoding: each function takes the text and a position, returns the value and the position
-- after it. Errors carry the position.

local function skipSpace(text, pos)
    return text:find("[^ \t\r\n]", pos) or #text + 1
end

-- UTF-8 bytes for a code point (from \uXXXX escapes)
local function utf8Char(code)
    if code < 0x80 then
        return string.char(code)
    elseif code < 0x800 then
        return string.char(0xC0 | (code >> 6), 0x80 | (code & 0x3F))
    elseif code < 0x10000 then
        return string.char(0xE0 | (code >> 12), 0x80 | ((code >> 6) & 0x3F), 0x80 | (code & 0x3F))
    end
    return string.char(0xF0 | (code >> 18), 0x80 | ((code >> 12) & 0x3F), 0x80 | ((code >> 6) & 0x3F),
        0x80 | (code & 0x3F))
end

local UNESCAPES = { b = "\b", f = "\f", n = "\n", r = "\r", t = "\t" }

local function decodeString(text, pos) -- pos is at the opening quote
    if text:sub(pos, pos) ~= '"' then
        error("json: expected a string at " .. pos)
    end
    local parts, i = {}, pos + 1
    while true do
        local j = text:find('["\\]', i)
        if j == nil then
            error("json: unterminated string at " .. pos)
        end
        parts[#parts + 1] = text:sub(i, j - 1)
        if text:sub(j, j) == '"' then
            return table.concat(parts), j + 1
        end
        local escape = text:sub(j + 1, j + 1)
        if escape == "u" then
            local code = tonumber(text:sub(j + 2, j + 5), 16)
            i = j + 6
            if code >= 0xD800 and code <= 0xDBFF and text:sub(i, i + 1) == "\\u" then -- surrogate pair
                code = 0x10000 + (code - 0xD800) * 0x400 + (tonumber(text:sub(i + 2, i + 5), 16) - 0xDC00)
                i = i + 6
            end
            parts[#parts + 1] = utf8Char(code)
        else
            parts[#parts + 1] = UNESCAPES[escape] or escape
            i = j + 2
        end
    end
end

local decodeValue

-- Shared by objects and arrays: items separated by commas until `close`
local function decodeList(text, pos, close, readItem)
    pos = skipSpace(text, pos + 1)
    if text:sub(pos, pos) == close then
        return pos + 1
    end
    while true do
        pos = skipSpace(text, readItem(pos))
        local separator = text:sub(pos, pos)
        if separator == close then
            return pos + 1
        elseif separator ~= "," then
            error("json: expected ',' or '" .. close .. "' at " .. pos)
        end
        pos = skipSpace(text, pos + 1)
    end
end

decodeValue = function(text, pos)
    pos = skipSpace(text, pos)
    local c = text:sub(pos, pos)
    if c == "{" then
        local object = {}
        return object, decodeList(text, pos, "}", function(at)
            local key
            key, at = decodeString(text, at)
            at = skipSpace(text, at)
            if text:sub(at, at) ~= ":" then
                error("json: expected ':' at " .. at)
            end
            object[key], at = decodeValue(text, at + 1)
            return at
        end)
    elseif c == "[" then
        local array = {}
        return array, decodeList(text, pos, "]", function(at)
            local item
            item, at = decodeValue(text, at)
            array[#array + 1] = item
            return at
        end)
    elseif c == '"' then
        return decodeString(text, pos)
    elseif c == "-" or c:match("%d") then
        local number = text:match("^-?%d+%.?%d*[eE]?[-+]?%d*", pos)
        return tonumber(number), pos + #number
    elseif text:sub(pos, pos + 3) == "true" then
        return true, pos + 4
    elseif text:sub(pos, pos + 4) == "false" then
        return false, pos + 5
    elseif text:sub(pos, pos + 3) == "null" then
        return nil, pos + 4
    end
    error("json: unexpected '" .. c .. "' at " .. pos)
end

function json.decode(text)
    local value, pos = decodeValue(text, 1)
    if skipSpace(text, pos) <= #text then
        error("json: trailing characters at " .. pos)
    end
    return value
end

return json
