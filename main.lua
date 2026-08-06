-- main.lua
-- Entry point for LLSPLOIT.
-- Paste this entire file into your executor, or loadstring it from the raw GitHub URL:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/LLSPLOIT/main/main.lua"))()

local BRANCH = "main"
local REPO   = "https://raw.githubusercontent.com/erosdevv/LLSPLOIT/" .. BRANCH

local MODULES = {
	"boot",
	"orion",
	"globals",
	"core",
	"battle",
	"world",
	"combat",
	"static",
	"shops",
	"catch",
	"arcade",
	"fossil",
	"ui",
}

-- Two-phase load: download every module first (HttpGet yields), then run them
-- back-to-back with no yields so task.defer/spawn cannot race unfinished modules.
local function downloadModule(name)
	local url = REPO .. "/modules/" .. name .. ".lua"
	local src = game:HttpGet(url)
	if type(src) ~= "string" or src == "" or src:sub(1, 3) == "404" then
		error("[LLSPLOIT] Failed to download '" .. name .. "' from " .. url)
	end
	local chunk, compileErr = loadstring(src)
	if not chunk then
		error("[LLSPLOIT] Compile error in '" .. name .. "': " .. tostring(compileErr))
	end
	if setfenv then
		pcall(setfenv, chunk, getfenv and getfenv() or _G)
	end
	return chunk
end

local function runModule(name, chunk)
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

local downloaded = {}
for index, name in ipairs(MODULES) do
	print("[LLSPLOIT] Downloading: " .. name)
	downloaded[index] = {
		name = name,
		chunk = downloadModule(name),
	}
end

local loadOk, loadErr = xpcall(function()
	for _, entry in ipairs(downloaded) do
		runModule(entry.name, entry.chunk)
		if entry.name == "orion" then
			print("[LLSPLOIT] Orion library ready")
			if type(_G.__llsploitBootNotify) == "function" then
				_G.__llsploitBootNotify("Orion ready, building UI...")
			elseif type(__llsploitBootNotify) == "function" then
				__llsploitBootNotify("Orion ready, building UI...")
			end
		end
	end
end, debug.traceback)

if not loadOk then
	warn("[LLSPLOIT] Failed to load:\n" .. tostring(loadErr))
	if type(_G.__llsploitBootNotify) == "function" then
		_G.__llsploitBootNotify("Load failed - check console (F9)")
	elseif type(__llsploitBootNotify) == "function" then
		__llsploitBootNotify("Load failed - check console (F9)")
	end
	pcall(function()
		if _G.OrionLib then
			_G.OrionLib:MakeNotification({
				Name = "LLSPLOIT",
				Content = "Failed to load. Check the output console.",
				Time = 8,
			})
		end
	end)
	return
end

-- Safe to run now: every module has finished defining _G.F / automations.
pcall(function()
	local ok, found = pcall(_G.F.findP)
	_G._p = ok and found or nil
end)
pcall(function()
	_G.F.installBattleGuiSafetyHooks()
end)
pcall(function()
	_G.F.installBattleCameraSafetyHooks()
end)
pcall(function()
	_G.F.installGoppieCaptureNetworkHook()
end)
pcall(function()
	local battle = _G.F.getCurrentBattle()
	if battle then
		_G.F.applyBattleAnimationFastForward(battle, false, false)
	end
end)

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
