-- Request signatures for the rarity API. Must match the
-- backend's src/signature.js: X-Signature is "<version>=<64 hex>", HMAC-SHA256 keyed with the
-- signing key (secret.lua) over
--   METHOD \n path \n X-Player-ID \n body
-- The key is readable in this plugin, so this keeps out requests made without the plugin and
-- edited payloads, not someone who reads the plugin.

local secret = require("secret")
local sha256 = require("lib/sha256")

local sign = {}

-- The X-Signature header value for a request. `path` is the path after the base URL.
function sign.header(method, path, playerID, body)
    local message = method .. "\n" .. path .. "\n" .. playerID .. "\n" .. body
    return secret.version .. "=" .. sha256.hmacHex(secret.key, message)
end

return sign
