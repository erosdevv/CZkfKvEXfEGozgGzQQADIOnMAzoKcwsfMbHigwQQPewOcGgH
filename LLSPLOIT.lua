-- LLSPLOIT.lua
-- Compatibility entrypoint. Prefer loading main.lua directly:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/LLSPLOIT/main/main.lua"))()

local BRANCH = "main"
local url = "https://raw.githubusercontent.com/erosdevv/LLSPLOIT/" .. BRANCH .. "/main.lua"
local src = game:HttpGet(url)
local chunk, err = loadstring(src)
if not chunk then
	error("[LLSPLOIT] Failed to compile main.lua: " .. tostring(err))
end
return chunk()
