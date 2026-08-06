-- main.lua
-- Entry point / loader for LLSPLOIT.
-- Paste this entire file into your executor, or loadstring it from the raw GitHub URL:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/LLSPLOIT/main/main.lua"))()
--
-- Or load LLSPLOIT.lua directly:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/LLSPLOIT/main/LLSPLOIT.lua"))()

local BRANCH = "main"
local REPO   = "https://raw.githubusercontent.com/erosdevv/LLSPLOIT/" .. BRANCH

local function loadScript(path)
	local url = REPO .. "/" .. path
	local src = game:HttpGet(url)
	local chunk, compileErr = loadstring(src)
	if not chunk then
		error("[LLSPLOIT] Compile error in '" .. path .. "': " .. tostring(compileErr))
	end
	local ok, result = pcall(chunk)
	if not ok then
		error("[LLSPLOIT] Runtime error in '" .. path .. "': " .. tostring(result))
	end
	print("[LLSPLOIT] Loaded: " .. path)
	return result
end

loadScript("LLSPLOIT.lua")
