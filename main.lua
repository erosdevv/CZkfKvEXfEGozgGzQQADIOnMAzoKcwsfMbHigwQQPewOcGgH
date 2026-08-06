-- main.lua
-- Entry point for LLSPLOIT.
-- Paste this entire file into your executor, or loadstring it from the raw GitHub URL:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/LLSPLOIT/main/main.lua"))()

local BRANCH = "main"
local REPO   = "https://raw.githubusercontent.com/erosdevv/LLSPLOIT/" .. BRANCH

local function loadModule(name)
	local url = REPO .. "/modules/" .. name .. ".lua"
	local src = game:HttpGet(url)
	local chunk, compileErr = loadstring(src)
	if not chunk then
		error("[LLSPLOIT] Compile error in '" .. name .. "': " .. tostring(compileErr))
	end
	local ok, result = pcall(chunk)
	if not ok then
		error("[LLSPLOIT] Runtime error in '" .. name .. "': " .. tostring(result))
	end
	if type(result) ~= "table" then
		error("[LLSPLOIT] Module '" .. name .. "' did not return a table")
	end
	print("[LLSPLOIT] Loaded: " .. name)
	return result
end

-- ─────────────────────────────────────────────────────────────────────────────
-- Load modules (order matters — later modules depend on earlier _G state)
-- ─────────────────────────────────────────────────────────────────────────────

loadModule("boot")
loadModule("orion")

print("[LLSPLOIT] Orion library ready")
if type(__llsploitBootNotify) == "function" then
	__llsploitBootNotify("Orion ready, building UI...")
end

local loadOk, loadErr = xpcall(function()
	loadModule("globals")
	loadModule("core")
	loadModule("battle")
	loadModule("world")
	loadModule("combat")
	loadModule("static")
	loadModule("shops")
	loadModule("catch")
	loadModule("arcade")
	loadModule("fossil")
	loadModule("ui")
end, debug.traceback)

if not loadOk then
	warn("[LLSPLOIT] Failed to load:\n" .. tostring(loadErr))
	if type(__llsploitBootNotify) == "function" then
		__llsploitBootNotify("Load failed - check console (F9)")
	end
	pcall(function()
		_G.OrionLib:MakeNotification({
			Name = "LLSPLOIT",
			Content = "Failed to load. Check the output console.",
			Time = 8,
		})
	end)
end

_G.OrionLib:Init()

task.defer(function()
	for _ = 1, 30 do
		if type(_G.F) == "table" and _G.F.ensureP() then
			_G.F.syncJackMiscSettings()
			_G.F.installJackStyleGameplayHooks()
			_G.F.jackInstallDoTrainerBattleHook()
			_G.F.jackScanTrainerNpcs()
			_G.jackLastTrainerListSignature = _G.F.getJackTrainerListSignature()
			_G.F.jackSyncTrainerDropdown()
			_G.F.jackStartBattleLoops()
			break
		end
		task.wait(0.5)
	end
end)
