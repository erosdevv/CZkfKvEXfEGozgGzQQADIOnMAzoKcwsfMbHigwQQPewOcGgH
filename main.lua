-- main.lua
-- Entry point for LLSPLOIT.
-- Paste this entire file into your executor, or loadstring it from the raw GitHub URL:
--   loadstring(game:HttpGet("https://raw.githubusercontent.com/erosdevv/CZkfKvEXfEGozgGzQQADIOnMAzoKcwsfMbHigwQQPewOcGgH/main/main.lua?v=" .. tostring(tick())))()

local BRANCH = "main"
local SCRIPT_VERSION = "auto-trainer-heal-restore-4"
local REPO   = "https://raw.githubusercontent.com/erosdevv/CZkfKvEXfEGozgGzQQADIOnMAzoKcwsfMbHigwQQPewOcGgH/" .. BRANCH
local ENV    = (getgenv and getgenv()) or _G

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

local EXPORT_KEYS = {
	"FishingAutomation",
	"StaticAutomation",
	"CatchAutomation",
	"ArcadeAutomation",
	"OrionLib",
}

local function store(key, value)
	_G[key] = value
	ENV[key] = value
end

local function applyExports(result)
	if type(result) ~= "table" then
		return
	end
	for _, key in ipairs(EXPORT_KEYS) do
		if result[key] ~= nil then
			store(key, result[key])
		end
	end
end

-- Two-phase load: download every module first (HttpGet yields), then run them
-- back-to-back with no yields so task.defer/spawn cannot race unfinished modules.
local function downloadModule(name)
	-- Cache-bust raw CDN so module updates are visible immediately.
	local url = REPO .. "/modules/" .. name .. ".lua?v=" .. SCRIPT_VERSION .. "-" .. tostring(os.clock())
	local src = game:HttpGet(url)
	if type(src) ~= "string" or src == "" or src:sub(1, 3) == "404" then
		error("[LLSPLOIT] Failed to download '" .. name .. "' from " .. url)
	end
	local chunk, compileErr = loadstring(src)
	if not chunk then
		error("[LLSPLOIT] Compile error in '" .. name .. "': " .. tostring(compileErr))
	end
	if setfenv then
		pcall(setfenv, chunk, ENV)
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
	applyExports(result)
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
			local notify = ENV.__llsploitBootNotify or _G.__llsploitBootNotify or __llsploitBootNotify
			if type(notify) == "function" then
				notify("Orion ready, building UI...")
			end
		end
	end
end, debug.traceback)

if not loadOk then
	warn("[LLSPLOIT] Failed to load:\n" .. tostring(loadErr))
	local notify = ENV.__llsploitBootNotify or _G.__llsploitBootNotify or __llsploitBootNotify
	if type(notify) == "function" then
		notify("Load failed - check console (F9)")
	end
	pcall(function()
		local orion = ENV.OrionLib or _G.OrionLib
		if orion then
			orion:MakeNotification({
				Name = "LLSPLOIT",
				Content = "Failed to load. Check the output console.",
				Time = 8,
			})
		end
	end)
	return
end

-- Re-assert automations onto shared env before post-load hooks / UI use.
for _, key in ipairs(EXPORT_KEYS) do
	local value = ENV[key] or _G[key]
	if value ~= nil then
		store(key, value)
	end
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

local orion = ENV.OrionLib or _G.OrionLib
orion:Init()

-- Apply UserId HumanoidDescription onto the local character (real avatar + packs).
task.defer(function()
	if type(_G.F) == "table" and type(_G.F.startLocalOnlyAvatar) == "function" and _G.localAvatarEnabled then
		local ok, result = pcall(_G.F.startLocalOnlyAvatar, _G.localAvatarUserId)
		if ok and result then
			pcall(function()
				orion:MakeNotification({
					Name = "Avatar Swap",
					Content = "Applied avatar " .. tostring(_G.localAvatarUserId or result),
					Time = 3
				})
			end)
		end
	end
end)

task.defer(function()
	for _ = 1, 30 do
		if type(_G.F) == "table" and _G.F.ensureP() then
			_G.F.syncJackMiscSettings()
			_G.F.installJackStyleGameplayHooks()
			_G.F.jackInstallDoTrainerBattleHook()
			_G.F.jackStartBattleLoops()
			pcall(_G.F.jackRefreshTrainerTargetFromChunk)
			break
		end
		task.wait(0.5)
	end
end)
