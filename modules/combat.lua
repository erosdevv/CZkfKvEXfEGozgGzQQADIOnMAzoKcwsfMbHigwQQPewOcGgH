-- combat.lua
-- Heal, trainer/auto-move, prompts, camera hooks, servers.
_G.F.ensureP = function()
	if type(_G._p) ~= "table" then
		_G._findPFailedAt = nil
		local ok, found = pcall(_G.F.findP)
		_G._p = ok and found or nil
	end

	return type(_G._p) == "table"
end

_G.F.pdsTryGetAny = function(actionSpecs)
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local network = _G.F.safeTableGet(_G._p, "Network")
	local getMethod = type(network) == "table" and _G.F.safeTableGet(network, "get") or nil
	if type(getMethod) ~= "function" then
		return false, "Network.get is not ready."
	end

	local lastErr = nil
	for _, spec in ipairs(actionSpecs or {}) do
		local actionName = spec[1]
		local args = spec.args or {}
		local ok, result = pcall(function()
			return getMethod(network, "PDS", actionName, unpack(args))
		end)

		if ok and result ~= false and result ~= nil then
			return true, result, actionName
		end

		lastErr = ok and tostring(result) or tostring(result)
	end

	return false, lastErr or "No PDS action succeeded."
end

-- Jack-style direct Network:get helpers (heal uses "heal", not "PDS").
_G.F.networkGet = function(actionName, ...)
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local args = { ... }
	local network = _G.F.safeTableGet(_G._p, "Network")
	local getMethod = type(network) == "table" and _G.F.safeTableGet(network, "get") or nil
	if type(getMethod) ~= "function" then
		return false, "Network.get is not ready."
	end

	local ok, result = pcall(function()
		return getMethod(network, actionName, unpack(args))
	end)
	return ok, result
end

_G.F.isPartyFullHealth = function()
	local ok, result = _G.F.networkGet("PDS", "areFullHealth")
	return ok and result == true
end

_G.F.runAutoHealOnce = function(force)
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	if not force and _G.F.isPartyFullHealth() then
		return true, "Party already at full health."
	end

	if not force and not _G.F.jackCanAutoHealNow() then
		return false, "Auto heal conditions are not met."
	end

	local currentChunk = _G.F.safeTableGet(_G._p, "DataManager")
	currentChunk = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "currentChunk") or nil
	local chunkData = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "data") or nil
	local regionData = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "regionData") or nil
	local blackOutTo = type(regionData) == "table" and regionData.BlackOutTo or nil
	if not blackOutTo and type(chunkData) == "table" then
		blackOutTo = chunkData.blackOutTo
	end

	-- MrJack: outdoor path only when HasOutsideHealers + a blackout target exist.
	local canOutdoorHeal = (not force)
		and type(chunkData) == "table"
		and chunkData.HasOutsideHealers
		and blackOutTo ~= nil

	if canOutdoorHeal then
		if not _G.jackOutdoorHealRunning then
			_G.jackOutdoorHealRunning = true
			task.spawn(function()
				local ok, err = pcall(_G.F.jackPerformOutdoorHeal)
				_G.jackOutdoorHealRunning = false
				if not ok then
					warn("[Auto Heal] " .. tostring(err))
				end
			end)
		end
		return true, "Outdoor heal started."
	end

	local ok, result = _G.F.networkGet("heal", nil, "HealMachine1")
	if ok and result ~= false then
		return true, result
	end

	return false, tostring(result or "Heal request failed.")
end

_G.F.jackIsLoomianCareDisabled = function()
	local objectiveManager = _G.F.safeTableGet(_G._p, "ObjectiveManager")
	if type(objectiveManager) ~= "table" then
		return false
	end

	local disabledBy = objectiveManager.disabledBy
	if disabledBy == "LoomianCare" then
		return true
	end

	if type(disabledBy) == "table" and disabledBy.LoomianCare then
		return true
	end

	return false
end

_G.F.jackCanAutoHealNow = function()
	if not _G.F.ensureP() then
		return false
	end

	local masterControl = _G.F.safeTableGet(_G._p, "MasterControl")
	if type(masterControl) == "table" and masterControl.WalkEnabled == false then
		return false
	end

	local menu = _G.F.safeTableGet(_G._p, "Menu")
	if type(menu) == "table" and menu.enabled == false then
		return false
	end

	local currentChunk = _G.F.safeTableGet(_G._p, "DataManager")
	currentChunk = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "currentChunk") or nil
	if type(currentChunk) == "table" and currentChunk.indoors then
		return false
	end

	if _G.jackOutdoorHealRunning then
		return false
	end

	if _G.F.jackGetBattle() then
		return false
	end

	if _G.F.jackIsLoomianCareDisabled() then
		return false
	end

	return true
end

_G.F.jackAnnounceAutoHeal = function()
	local chat = _G.F.safeTableGet(_G._p, "NPCChat")
	if type(chat) ~= "table" or type(chat.Say) ~= "function" then
		return
	end

	pcall(function()
		chat:Say("[ma][LLSPLOIT]Auto healing...")
	end)
end

_G.F.jackPerformOutdoorHeal = function()
	if not _G.F.ensureP() then
		return false
	end

	local currentChunk = _G.F.safeTableGet(_G._p, "DataManager")
	currentChunk = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "currentChunk") or nil
	if type(currentChunk) ~= "table" then
		return false
	end

	local savedCFrame = nil
	local character = _G.Player and _G.Player.Character
	local root = character and character.PrimaryPart
	if root then
		savedCFrame = root.CFrame
	end

	local blackOutTo = _G.F.safeTableGet(currentChunk, "regionData")
	blackOutTo = type(blackOutTo) == "table" and blackOutTo.BlackOutTo or nil
	if not blackOutTo then
		local chunkData = _G.F.safeTableGet(currentChunk, "data")
		blackOutTo = type(chunkData) == "table" and chunkData.blackOutTo or nil
	end

	if not blackOutTo then
		local ok, result = _G.F.networkGet("heal", nil, "HealMachine1")
		return ok and result ~= false
	end

	local originalChunkId = currentChunk.id
	local restoreWalkEnabled = nil
	local utilities = _G.F.safeTableGet(_G._p, "Utilities")

	local masterControl = _G.F.safeTableGet(_G._p, "MasterControl")
	if type(masterControl) == "table" then
		restoreWalkEnabled = masterControl.WalkEnabled
		masterControl.WalkEnabled = false
	end

	local menu = _G.F.safeTableGet(_G._p, "Menu")
	if type(menu) == "table" then
		pcall(function()
			if type(menu.disable) == "function" then
				menu:disable()
			end
			if type(menu.fastClose) == "function" then
				menu:fastClose(3)
			end
		end)
	end

	if type(utilities) == "table" and type(utilities.FadeOut) == "function" then
		pcall(function()
			utilities:FadeOut(1)
		end)
	end

	task.spawn(_G.F.jackAnnounceAutoHeal)

	if type(utilities) == "table" and type(utilities.TeleportToSpawnBox) == "function" then
		pcall(function()
			utilities:TeleportToSpawnBox()
		end)
	end

	if type(currentChunk.unbindIndoorCam) == "function" then
		pcall(function()
			currentChunk:unbindIndoorCam()
		end)
	end
	if type(currentChunk.destroy) == "function" then
		pcall(function()
			currentChunk:destroy()
		end)
	end

	-- MrJack settle before loading the blackout / Health Center chunk.
	task.wait(2)

	local dataManager = _G.F.safeTableGet(_G._p, "DataManager")
	if type(dataManager) == "table" and type(dataManager.loadChunk) == "function" then
		local okLoad, loaded = pcall(function()
			return dataManager:loadChunk(blackOutTo)
		end)
		if okLoad and type(loaded) == "table" then
			currentChunk = loaded
		else
			currentChunk = dataManager.currentChunk
		end
	end

	if type(currentChunk) ~= "table" then
		return false
	end

	local door = type(currentChunk.getDoor) == "function" and currentChunk:getDoor("HealthCenter") or nil
	local room = type(currentChunk.getRoom) == "function" and currentChunk:getRoom("HealthCenter", door, 1) or nil

	task.wait()
	local okHealer, healerId = _G.F.networkGet("getHealer", "HealthCenter")
	if not okHealer or not healerId then
		task.wait()
		okHealer, healerId = _G.F.networkGet("getHealer", "HealthCenter")
	end

	if okHealer and healerId then
		_G.F.networkGet("heal", "HealthCenter", healerId)
	else
		_G.F.networkGet("heal", nil, "HealMachine1")
	end

	if type(room) == "table" and type(room.Destroy) == "function" then
		pcall(function()
			room:Destroy()
		end)
	end

	if originalChunkId then
		if type(currentChunk.destroy) == "function" then
			pcall(function()
				currentChunk:destroy()
			end)
		end

		dataManager = _G.F.safeTableGet(_G._p, "DataManager")
		if type(dataManager) == "table" and type(dataManager.loadChunk) == "function" then
			pcall(function()
				dataManager:loadChunk(originalChunkId)
			end)
		end

		if savedCFrame and type(utilities) == "table" and type(utilities.Teleport) == "function" then
			pcall(function()
				utilities:Teleport(savedCFrame)
			end)
		end

		menu = _G.F.safeTableGet(_G._p, "Menu")
		if type(menu) == "table" and type(menu.enable) == "function" then
			pcall(function()
				menu:enable()
			end)
		end

		local chat = _G.F.safeTableGet(_G._p, "NPCChat")
		if type(chat) == "table" and type(chat.manualAdvance) == "function" then
			pcall(function()
				chat:manualAdvance()
			end)
		end

		if type(utilities) == "table" and type(utilities.FadeIn) == "function" then
			pcall(function()
				utilities:FadeIn(1)
			end)
		end

		masterControl = _G.F.safeTableGet(_G._p, "MasterControl")
		if type(masterControl) == "table" then
			masterControl.WalkEnabled = restoreWalkEnabled ~= false
		end
	end

	return true
end

_G.jackAutoBattle = _G.jackAutoBattle or { Move = "Disabled", Trainer = "Disabled" }
_G.jackSyncingDropdownUi = false
_G.jackLastTrainerListSignature = ""
_G.jackTrainerList = _G.jackTrainerList or {}
_G.jackTrainerConfigs = _G.jackTrainerConfigs or {}
_G.jackTrainerBattleKeys = _G.jackTrainerBattleKeys or {}
_G.jackTrainerDropdownOptions = _G.jackTrainerDropdownOptions or { "Disabled" }
_G.jackBattleLoopsStarted = _G.jackBattleLoopsStarted or false

_G.F.jackGetBattle = function()
	if not _G.F.ensureP() then
		return nil
	end

	local battleModule = _G.F.safeTableGet(_G._p, "Battle")
	local battle = type(battleModule) == "table" and _G.F.safeTableGet(battleModule, "currentBattle") or nil
	if type(battle) == "table" and not battle.ended and not battle.done then
		return battle
	end

	return _G.F.getCurrentBattle()
end

_G.F.jackHasBattleGuiInstance = function()
	local player = _G.Player
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui") or nil
	local mainGui = playerGui and playerGui:FindFirstChild("MainGui") or nil
	return mainGui and mainGui:FindFirstChild("BattleGui", true) or nil
end

_G.F.jackCanStartTrainerBattle = function()
	if _G.jackOutdoorHealRunning then
		return false
	end

	if _G.autoHealEnabled then
		if _G.F.isPartyFullHealth() then
			return true
		end
		return false
	end

	return true
end

_G.F.jackEnterGameContext = function()
	if type(setthreadcontext) == "function" then
		pcall(setthreadcontext, 2)
	elseif type(syn) == "table" and type(syn.set_thread_identity) == "function" then
		pcall(syn.set_thread_identity, 2)
	end
end

_G.jackMoveBusy = _G.jackMoveBusy or false
_G.jackMoveBusyToken = _G.jackMoveBusyToken or 0

_G.F.jackMarkMoveBusy = function(duration)
	_G.jackMoveBusy = true
	_G.jackMoveBusyToken = (_G.jackMoveBusyToken or 0) + 1
	local token = _G.jackMoveBusyToken
	task.delay(tonumber(duration) or 0.35, function()
		if _G.jackMoveBusyToken == token then
			_G.jackMoveBusy = false
		end
	end)
end

_G.F.jackIsMoveBusy = function()
	return _G.jackMoveBusy == true or _G.jackOutdoorHealRunning == true
end

_G.F.setDropdownUiValue = function(dropdown, value)
	if type(dropdown) ~= "table" or type(dropdown.Set) ~= "function" then
		return
	end

	_G.jackSyncingDropdownUi = true
	pcall(function()
		dropdown:Set(value)
	end)
	_G.jackSyncingDropdownUi = false
end

_G.F.getJackTrainerListSignature = function()
	return table.concat(_G.jackTrainerList, "\31")
end

_G.F.jackBuildTrainerDropdownOptions = function()
	local options = { "Disabled" }
	for _, trainerName in ipairs(_G.jackTrainerList) do
		if trainerName ~= "Disabled" and not table.find(options, trainerName) then
			table.insert(options, trainerName)
		end
	end
	return options
end

_G.F.jackSyncTrainerDropdown = function(forceValue)
	local options = _G.F.jackBuildTrainerDropdownOptions()
	_G.jackTrainerDropdownOptions = options

	local dropdown = _G.configUi and _G.configUi.jackTrainerDropdown
	if type(dropdown) == "table" and type(dropdown.Refresh) == "function" then
		dropdown:Refresh(options, true)
	end

	local selected = forceValue or _G.jackAutoBattle.Trainer or "Disabled"
	if not table.find(options, selected) then
		selected = "Disabled"
		_G.jackAutoBattle.Trainer = "Disabled"
	end

	if type(dropdown) == "table" and type(dropdown.Set) == "function" then
		_G.F.setDropdownUiValue(dropdown, selected)
	end
end

_G.F.jackIsNpcModel = function(model)
	if model == nil then
		return false
	end
	local modelType = type(model)
	if modelType == "userdata" then
		return true
	end
	-- Some executors report Instances via typeof only.
	local ok, kind = pcall(typeof, model)
	return ok and kind == "Instance"
end

_G.F.jackProcessTrainerNpc = function(npc)
	if type(npc) ~= "table" or not _G.F.jackIsNpcModel(npc.model) then
		return
	end

	if not _G.F.ensureP() then
		return
	end

	local currentChunk = _G.F.safeTableGet(_G._p, "DataManager")
	currentChunk = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "currentChunk") or nil
	local battles = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "battles") or nil
	if type(battles) ~= "table" then
		return
	end

	-- MrJack: read #Battle.Value as-is (no tonumber), fallback "Mrjack".
	local battleId = nil
	local okBattle, battleValue = pcall(function()
		return npc.model:FindFirstChild("#Battle")
	end)
	if okBattle and battleValue then
		local okValue, value = pcall(function()
			return battleValue.Value
		end)
		if okValue and value ~= nil and value ~= "" then
			battleId = value
		end
	end
	if battleId == nil then
		battleId = "Mrjack"
	end

	local trainerData = battles[tostring(battleId)] or battles[battleId]
	if type(trainerData) ~= "table" then
		return
	end

	-- MrJack hard-requires RematchQuestion before mapping/list insert.
	if not trainerData.RematchQuestion then
		return
	end

	local trainerName = trainerData.Name or trainerData.name
	if type(trainerName) ~= "string" or trainerName == "" then
		return
	end

	_G.jackTrainerBattleKeys[trainerName] = tostring(battleId)
	_G.jackTrainerConfigs[trainerName] = {
		trainer = trainerData,
		opponentBaseNPC = npc,
		battleKey = tostring(battleId),
	}

	-- MrJack insert gate: UV5 is Battle.setupScene (always truthy), so list
	-- insert effectively requires regionData.BattleScene.
	local regionData = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "regionData") or nil
	local hasBattleScene = type(regionData) == "table" and regionData.BattleScene and true or false
	if hasBattleScene and not table.find(_G.jackTrainerList, trainerName) then
		table.insert(_G.jackTrainerList, trainerName)
	end
end

_G.F.jackScanTrainerNpcs = function()
	if not _G.F.ensureP() then
		return
	end

	local currentChunk = _G.F.safeTableGet(_G._p, "DataManager")
	currentChunk = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "currentChunk") or nil
	local battles = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "battles") or nil
	if type(battles) ~= "table" or next(battles) == nil then
		_G.jackTrainerList = {}
		_G.jackTrainerConfigs = {}
		_G.jackTrainerBattleKeys = {}
		return
	end

	local collectionManager = _G.F.safeTableGet(_G._p, "CollectionManager")
	if type(collectionManager) ~= "table" or type(collectionManager.GetNPCs) ~= "function" then
		return
	end

	local ok, npcs = pcall(function()
		return collectionManager:GetNPCs()
	end)
	if not ok or type(npcs) ~= "table" then
		return
	end

	-- MrJack builds Names from chunk.battles and prunes stale dropdown entries.
	local battleNames = {}
	for _, battleData in pairs(battles) do
		if type(battleData) == "table" then
			local name = battleData.Name or battleData.name
			if type(name) == "string" and name ~= "" then
				battleNames[name] = true
			end
		end
	end

	for index = #_G.jackTrainerList, 1, -1 do
		local name = _G.jackTrainerList[index]
		if name ~= "Disabled" and not battleNames[name] then
			table.remove(_G.jackTrainerList, index)
			_G.jackTrainerConfigs[name] = nil
			_G.jackTrainerBattleKeys[name] = nil
		end
	end

	-- MrJack ForLooP iterates the full GetNPCs map (not ipairs-only).
	local seen = {}
	for _, npc in pairs(npcs) do
		if type(npc) == "table" and not seen[npc] then
			seen[npc] = true
			pcall(function()
				_G.F.jackProcessTrainerNpc(npc)
			end)
		end
	end

	table.sort(_G.jackTrainerList, function(a, b)
		return tostring(a) < tostring(b)
	end)
end

-- MrJack runs GetNPCs discovery on its own LooP, independent of Trainer Target.
_G.F.jackRefreshTrainerTargetFromChunk = function()
	if not _G.F.ensureP() then
		return
	end

	local currentChunk = _G.F.safeTableGet(_G._p, "DataManager")
	currentChunk = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "currentChunk") or nil
	local battles = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "battles") or nil
	local hasBattles = type(battles) == "table" and next(battles) ~= nil

	if hasBattles then
		_G.F.jackScanTrainerNpcs()
	elseif #_G.jackTrainerList > 0 then
		_G.jackTrainerList = {}
		_G.jackTrainerConfigs = {}
		_G.jackTrainerBattleKeys = {}
	end

	local signature = _G.F.getJackTrainerListSignature()
	if signature ~= _G.jackLastTrainerListSignature then
		_G.jackLastTrainerListSignature = signature
		local forceValue = nil
		if #_G.jackTrainerList == 0 then
			forceValue = "Disabled"
		end
		_G.F.jackSyncTrainerDropdown(forceValue)
	end
end

_G.F.jackInstallDoTrainerBattleHook = function()
	if _G.jackDoTrainerBattleHooked or not _G.F.ensureP() then
		return
	end

	local battleModule = _G.F.safeTableGet(_G._p, "Battle")
	if type(battleModule) ~= "table" or type(battleModule.doTrainerBattle) ~= "function" then
		return
	end

	if battleModule.__jackDoTrainerBattleHooked then
		_G.jackDoTrainerBattleHooked = true
		return
	end

	local original = battleModule.doTrainerBattle
	battleModule.doTrainerBattle = function(self, config, ...)
		while not _G.F.jackCanStartTrainerBattle() do
			task.wait()
		end

		_G.F.jackEnterGameContext()
		return original(self, config, ...)
	end

	battleModule.__jackDoTrainerBattleHooked = true
	_G.jackDoTrainerBattleHooked = true
end

_G.F.jackGetBattleGuiMoveName = function(moveData)
	if type(moveData) ~= "table" then
		return nil
	end

	local name = moveData.move or moveData.name or moveData.Name
	if type(name) == "string" and name ~= "" then
		return name
	end

	return nil
end

_G.F.jackFindMoveSlotByName = function(battleGui, moveName)
	if type(battleGui) ~= "table" or type(moveName) ~= "string" then
		return nil
	end

	local moves = battleGui.moves
	if type(moves) ~= "table" then
		return nil
	end

	for slot = 1, 4 do
		local moveData = moves[slot]
		if _G.F.jackGetBattleGuiMoveName(moveData) == moveName and not moveData.disabled then
			return slot
		end
	end

	for slot, moveData in pairs(moves) do
		local numeric = tonumber(slot)
		if numeric and _G.F.jackGetBattleGuiMoveName(moveData) == moveName and not moveData.disabled then
			return numeric
		end
	end

	return nil
end

_G.F.jackGetBattleFoe = function(battle, battleGui)
	if type(battleGui) == "table" then
		for _, key in ipairs({ "foe", "opponent", "activeFoe", "enemyMonster" }) do
			local foe = battleGui[key]
			if type(foe) == "table" then
				return foe
			end
		end
	end

	if type(battle) ~= "table" then
		return nil
	end

	local side = battle.p2 or battle.opponent or battle.foeSide
	if type(side) == "table" then
		local active = side.active or side.monsters and side.monsters[side.activeIndex or 1]
		if type(active) == "table" then
			return active
		end
		if type(side.monsters) == "table" then
			for _, monster in ipairs(side.monsters) do
				if type(monster) == "table" then
					return monster
				end
			end
		end
	end

	return nil
end

_G.F.jackGetFoeHpRatio = function(foe)
	if type(foe) ~= "table" then
		return nil
	end

	local hp, maxHp
	for _, key in ipairs({ "hp", "cHp", "chp", "curHp", "currentHp", "curHP", "health", "HP" }) do
		local value = foe[key]
		if type(value) == "number" then
			hp = value
			break
		end
	end

	for _, key in ipairs({ "maxhp", "maxHp", "maxHP", "mhp", "maxHealth", "MaxHP" }) do
		local value = foe[key]
		if type(value) == "number" and value > 0 then
			maxHp = value
			break
		end
	end

	if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
		return hp / maxHp
	end

	return nil
end

_G.F.jackResolveWildAutoMoveSlot = function(battle, battleGui, fallbackSlot)
	fallbackSlot = math.clamp(math.floor(tonumber(fallbackSlot) or 1), 1, 4)
	if type(battle) ~= "table" or battle.kind ~= "wild" or type(battleGui) ~= "table" then
		return fallbackSlot
	end

	local foe = _G.F.jackGetBattleFoe(battle, battleGui)
	if _G.useSpareEnabled then
		local ratio = _G.F.jackGetFoeHpRatio(foe)
		if type(ratio) == "number" and ratio <= 0.2 then
			local spareSlot = _G.F.jackFindMoveSlotByName(battleGui, "Spare")
			if spareSlot then
				return spareSlot
			end
		end
	end

	local corruptMove = tostring(_G.corruptMove or "Disabled")
	if foe and foe.corrupt and string.find(corruptMove, "Move", 1, true) then
		local corruptSlot = tonumber(string.match(corruptMove, "(%d+)"))
		if corruptSlot then
			return math.clamp(math.floor(corruptSlot), 1, 4)
		end
	end

	return fallbackSlot
end

_G.F.jackUseBattleGuiMove = function(moveSlot)
	if not _G.F.ensureP() then
		return false
	end

	if _G.F.jackIsMoveBusy() then
		return false
	end

	if not _G.F.jackHasBattleGuiInstance() then
		return false
	end

	moveSlot = math.clamp(math.floor(tonumber(moveSlot) or 1), 1, 4)

	local battle = _G.F.jackGetBattle()
	if type(battle) ~= "table" then
		return false
	end

	local battleGui = _G.F.getBattleGuiModule()
	if type(battleGui) ~= "table" then
		return false
	end

	if battle.state ~= "input" then
		if _G.F.isBattleMainMenuOpen() and type(battleGui.mainButtonClicked) == "function" then
			pcall(function()
				battleGui:mainButtonClicked(1)
			end)
		end
		return false
	end

	local moves = battleGui.moves
	local moveData = type(moves) == "table" and moves[moveSlot] or nil
	if type(moveData) ~= "table" then
		return false
	end

	if type(battleGui.onMoveClicked) ~= "function" then
		if type(battleGui.mainButtonClicked) == "function" then
			pcall(function()
				battleGui:mainButtonClicked(1)
			end)
		end
		return false
	end

	if moveData.energy and moveData.energy > 0 then
		local activeMonster = battleGui.activeMonster
		if type(activeMonster) == "table"
			and type(activeMonster.energy) == "number"
			and activeMonster.energy < moveData.energy
			and not activeMonster.bypassEnergy then
			if type(battleGui.fightSelectionGroup) == "table" and type(battleGui.fightSelectionGroup.LoseFocus) == "function" then
				pcall(function()
					battleGui.fightSelectionGroup:LoseFocus()
				end)
			end
			if type(battleGui.inputEvent) == "table" and type(battleGui.inputEvent.fire) == "function" then
				pcall(function()
					battleGui.inputEvent:fire("rest 0")
				end)
			end
			if type(battleGui.exitButtonsMoveChosen) == "function" then
				pcall(function()
					battleGui:exitButtonsMoveChosen()
				end)
			end
			_G.F.jackMarkMoveBusy(0.35)
			return true
		end
	end

	if not moveData.disabled then
		_G.F.jackEnterGameContext()
		pcall(function()
			battleGui:onMoveClicked(moveSlot)
		end)
		_G.F.jackMarkMoveBusy(0.35)
		return true
	end

	return false
end

_G.F.jackRunAutoMoveTick = function(allowWild)
	if _G.jackAutoBattle.Move == "Disabled" then
		return false
	end

	if string.find(_G.jackAutoBattle.Move, "Move", 1, true) == nil then
		return false
	end

	local battle = _G.F.jackGetBattle()
	if type(battle) == "table" and battle.kind == "wild" and not allowWild then
		return false
	end

	local moveSlot = tonumber(string.match(_G.jackAutoBattle.Move, "(%d+)")) or 1
	local battleGui = _G.F.getBattleGuiModule()
	if allowWild then
		moveSlot = _G.F.jackResolveWildAutoMoveSlot(battle, battleGui, moveSlot)
	end

	return _G.F.jackUseBattleGuiMove(moveSlot)
end

_G.F.jackRunAutoTrainerTick = function()
	if _G.jackAutoBattle.Trainer == "Disabled" then
		return false
	end

	if not _G.F.ensureP() then
		return false
	end

	-- Discovery/sync is owned by jackRefreshTrainerTargetFromChunk (always-on loop).
	local currentChunk = _G.F.safeTableGet(_G._p, "DataManager")
	currentChunk = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "currentChunk") or nil
	local battles = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "battles") or nil
	if type(battles) ~= "table" or next(battles) == nil then
		return false
	end

	if not table.find(_G.jackTrainerList, _G.jackAutoBattle.Trainer) then
		return false, "Trainer is not loaded in this area."
	end

	local config = _G.jackTrainerConfigs[_G.jackAutoBattle.Trainer]
	if type(config) ~= "table" then
		return false, "Trainer config is not ready."
	end

	local opponentBaseNPC = config.opponentBaseNPC
	local opponentModel = type(opponentBaseNPC) == "table" and opponentBaseNPC.model or nil
	if not _G.F.jackIsNpcModel(opponentModel) then
		return false, "Trainer NPC is not nearby."
	end
	local inWorkspace = false
	pcall(function()
		inWorkspace = opponentModel:IsDescendantOf(workspace)
	end)
	if not inWorkspace then
		return false, "Trainer NPC is not nearby."
	end

	local battleKey = _G.jackTrainerBattleKeys[_G.jackAutoBattle.Trainer]
	if battleKey and not battles[battleKey] and not battles[tonumber(battleKey)] then
		table.remove(_G.jackTrainerList, table.find(_G.jackTrainerList, _G.jackAutoBattle.Trainer))
		_G.jackTrainerConfigs[_G.jackAutoBattle.Trainer] = nil
		_G.jackTrainerBattleKeys[_G.jackAutoBattle.Trainer] = nil
		_G.F.jackSyncTrainerDropdown("Disabled")
		return false, "Trainer battle data left this area."
	end

	local masterControl = _G.F.safeTableGet(_G._p, "MasterControl")
	if type(masterControl) == "table" and masterControl.WalkEnabled == false then
		return false
	end

	local activeBattle = _G.F.jackGetBattle()
	if activeBattle then
		return false
	end

	if not table.find(_G.jackTrainerList, _G.jackAutoBattle.Trainer) then
		return false
	end

	local playerData = _G.F.safeTableGet(_G._p, "PlayerData")
	local completedEvents = type(playerData) == "table" and _G.F.safeTableGet(playerData, "completedEvents") or nil
	if type(completedEvents) == "table" and not completedEvents.ChooseBeginner then
		return false
	end

	if not _G.F.jackCanStartTrainerBattle() then
		return false
	end

	local trainerData = config.trainer
	if type(trainerData) ~= "table" then
		return false, "Trainer battle data is missing."
	end

	local battleConfig = {
		trainer = trainerData,
		opponentBaseNPC = opponentBaseNPC,
	}

	if trainerData.Name == "Tamyra" and type(currentChunk) == "table" and currentChunk.id == "chunk20" then
		battleConfig.fshPct = 0.9
	end

	local battleModule = _G.F.safeTableGet(_G._p, "Battle")
	if type(battleModule) ~= "table" or type(battleModule.doTrainerBattle) ~= "function" then
		return false, "Battle.doTrainerBattle is not ready."
	end

	local ok, err = pcall(function()
		battleModule:doTrainerBattle(battleConfig)
	end)
	if not ok then
		return false, tostring(err)
	end

	return true
end

_G.F.jackStartBattleLoops = function()
	if _G.jackBattleLoopsStarted then
		return
	end

	_G.jackBattleLoopsStarted = true

	-- MrJack: continuous GetNPCs trainer discovery, even while Target is Disabled.
	task.spawn(function()
		while _G.uiAlive do
			pcall(_G.F.jackRefreshTrainerTargetFromChunk)
			task.wait(0.25)
		end
	end)

	task.spawn(function()
		while _G.uiAlive do
			if _G.jackAutoBattle.Move ~= "Disabled" then
				-- MrJack Auto Move is trainer/non-wild only. Wild moves are owned
				-- by the Farm encounter loop via useMoveOne(allowWild=true).
				pcall(_G.F.jackRunAutoMoveTick, false)
			end
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while _G.uiAlive do
			local battle = _G.F.jackGetBattle()
			if battle and _G.jackAutoBattle.Trainer ~= "Disabled" then
				_G.F.setBattleFastForward(true, battle)
				_G.F.skipEncounterCutscene(battle)
				pcall(function()
					_G.F.dismissTrainerSwitchPrompt()
				end)
				pcall(function()
					_G.F.dismissMasteryReport()
				end)
			elseif _G.jackAutoBattle.Trainer ~= "Disabled" then
				_G.F.jackRunAutoTrainerTick()
			end

			if _G.jackAutoBattle.Trainer ~= "Disabled" then
				pcall(function()
					_G.F.clickThroughNpcChat()
				end)
			end

			task.wait(0.1)
		end
	end)
end

_G.F.jackSyncMoveDropdown = function(forceValue)
	local dropdown = _G.configUi and _G.configUi.jackMoveDropdown
	if not dropdown then
		return
	end

	_G.F.setDropdownUiValue(dropdown, forceValue or _G.jackAutoBattle.Move or "Disabled")
end

_G.F.jackSetAutoMove = function(value)
	_G.jackAutoBattle.Move = value or "Disabled"
	_G.autoMoveOneEnabled = _G.jackAutoBattle.Move ~= "Disabled"
end

_G.F.jackSetAutoTrainer = function(value)
	_G.jackAutoBattle.Trainer = value or "Disabled"
	_G.autoTrainerEnabled = _G.jackAutoBattle.Trainer ~= "Disabled"

	-- Auto Battle + Trainer Target means trainer farming, not grass encounters.
	if _G.autoBattleEnabled then
		if _G.autoTrainerEnabled then
			_G.F.setAutoEncounterEnabled(false)
		else
			_G.F.setAutoEncounterEnabled(true)
		end
		if _G.configUi and _G.configUi.autoEncounterToggle then
			_G.F.setToggleUi(_G.configUi.autoEncounterToggle, _G.autoEncounterEnabled)
		end
	end
end

-- Legacy wrappers kept for encounter automation.
_G.F.jackSetAutoMoveEnabled = function(value)
	if value then
		_G.F.jackSetAutoMove(_G.jackAutoBattle.Move ~= "Disabled" and _G.jackAutoBattle.Move or "Move 1")
	else
		_G.F.jackSetAutoMove("Disabled")
	end
end

_G.F.jackSetAutoTrainerEnabled = function(value)
	if value and _G.jackAutoBattle.Trainer == "Disabled" then
		local firstTrainer = _G.jackTrainerList[2] or _G.jackTrainerList[1]
		if firstTrainer and firstTrainer ~= "Disabled" then
			_G.F.jackSetAutoTrainer(firstTrainer)
			return
		end
	end
	_G.F.jackSetAutoTrainer(value and _G.jackAutoBattle.Trainer ~= "Disabled" and _G.jackAutoBattle.Trainer or "Disabled")
end

_G.F.jackRunAutoMoveOnce = _G.F.jackRunAutoMoveTick
_G.F.jackRunAutoTrainerOnce = _G.F.jackRunAutoTrainerTick

_G.F.getRepelModule = function()
	if not _G.F.ensureP() then
		return nil
	end

	return _G.F.safeTableGet(_G._p, "Repel")
end

_G.F.useActiveRepellentOnce = function(force)
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local repel = _G.F.getRepelModule()
	if type(repel) ~= "table" then
		return false, "Repel module is not ready."
	end

	local beforeSteps = tonumber(repel.steps) or 0
	if not force and beforeSteps >= 10 then
		return true, "Repellent still active (" .. tostring(beforeSteps) .. " steps)."
	end

	local ok, err = pcall(function()
		repel.steps = 100
	end)
	if not ok then
		return false, tostring(err or "Failed to refresh repellent.")
	end

	local afterSteps = tonumber(repel.steps) or 0
	if afterSteps < 10 then
		return false, "Repellent steps did not update (still " .. tostring(afterSteps) .. ")."
	end

	return true, "Repellent refreshed to " .. tostring(afterSteps) .. " steps."
end

_G.F.setFastBattleEnabled = function(value)
	_G.F.setFastForwardEnabled(value)
end

_G.F.setAutoBattleEnabled = function(value)
	_G.autoBattleEnabled = value and true or false

	local trainerSelected = type(_G.jackAutoBattle) == "table"
		and _G.jackAutoBattle.Trainer
		and _G.jackAutoBattle.Trainer ~= "Disabled"

	-- Wild grass only when Auto Battle is on and no Trainer Target is selected.
	-- Trainer mode uses doTrainerBattle via the always-on trainer tick instead.
	if _G.autoBattleEnabled then
		_G.F.setAutoEncounterEnabled(not trainerSelected)
		if _G.jackAutoBattle.Move == "Disabled" then
			_G.F.jackSetAutoMove("Move 1")
		end
	else
		_G.F.setAutoEncounterEnabled(false)
		_G.F.jackSetAutoMove("Disabled")
	end
	_G.autoMoveOneEnabled = _G.jackAutoBattle.Move ~= "Disabled"
	_G.F.setFastBattleEnabled(_G.autoBattleEnabled)
	_G.skipDialogueEnabled = _G.autoBattleEnabled
	_G.denyReassignMoveEnabled = _G.autoBattleEnabled
	_G.denySwitchRequestEnabled = _G.autoBattleEnabled
	_G.denyNicknameEnabled = _G.autoBattleEnabled
	_G.disableShowProgressEnabled = _G.autoBattleEnabled

	if _G.configUi.autoEncounterToggle then _G.F.setToggleUi(_G.configUi.autoEncounterToggle, _G.autoEncounterEnabled) end
	if _G.configUi.jackMoveDropdown then
		_G.F.jackSyncMoveDropdown(_G.jackAutoBattle.Move)
	end
	if _G.configUi.fastForwardToggle then _G.F.setToggleUi(_G.configUi.fastForwardToggle, _G.fastForwardEnabled) end
	if _G.configUi.skipDialogueToggle then _G.F.setToggleUi(_G.configUi.skipDialogueToggle, _G.skipDialogueEnabled) end
	if _G.configUi.denyReassignMoveToggle then _G.F.setToggleUi(_G.configUi.denyReassignMoveToggle, _G.denyReassignMoveEnabled) end
	if _G.configUi.denySwitchRequestToggle then _G.F.setToggleUi(_G.configUi.denySwitchRequestToggle, _G.denySwitchRequestEnabled) end
	if _G.configUi.denyNicknameToggle then _G.F.setToggleUi(_G.configUi.denyNicknameToggle, _G.denyNicknameEnabled) end
	if _G.configUi.disableShowProgressToggle then _G.F.setToggleUi(_G.configUi.disableShowProgressToggle, _G.disableShowProgressEnabled) end
end

_G.F.openRallyTeam = function()
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local rally, reason = _G.F.getRallyModule()
	if not rally then
		return false, reason or "Rally module is not ready."
	end

	if type(rally.openRallyTeamMenu) ~= "function" then
		return false, "Rally team menu opener was not found."
	end

	local ok, err = pcall(function()
		if type(_G._p.Menu) == "table" and type(_G._p.Menu.disable) == "function" then
			_G._p.Menu:disable()
		end
		rally:openRallyTeamMenu()
		if type(_G._p.Menu) == "table" and type(_G._p.Menu.enable) == "function" then
			_G._p.Menu:enable()
		end
	end)

	return ok, ok and nil or tostring(err)
end

_G.F.openRallied = function()
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local rally, reason = _G.F.getRallyModule()
	if not rally then
		return false, reason or "Rally module is not ready."
	end

	if type(rally.openRalliedMonstersMenu) ~= "function" then
		return false, "Rallied menu opener was not found."
	end

	local ok, err = pcall(function()
		if type(_G._p.Menu) == "table" and type(_G._p.Menu.disable) == "function" then
			_G._p.Menu:disable()
		end
		rally:openRalliedMonstersMenu()
		if type(_G._p.Menu) == "table" and type(_G._p.Menu.enable) == "function" then
			_G._p.Menu:enable()
		end
	end)

	return ok, ok and nil or tostring(err)
end

_G.F.openPcMenu = function()
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local menu = _G.F.safeTableGet(_G._p, "Menu")
	local pc = type(menu) == "table" and _G.F.safeTableGet(menu, "pc") or nil
	if type(pc) == "table" and type(pc.bootUp) == "function" then
		local ok, err = pcall(function()
			pc:bootUp()
		end)
		if ok then
			return true
		end
		return false, tostring(err)
	end

	return false, "Menu.pc:bootUp() is not ready."
end

_G.F.denyBattlePromptByKeywords = function(keywords)
	local promptOpen, yesNoSignal, noButton, promptFrame = _G.F.getBattleYesOrNoLiveState()
	if not promptOpen and not promptFrame then
		return false
	end

	local text = string.lower(_G.F.getVisibleBattlePromptTextSnapshot() or "")
	if text == "" then
		return false
	end

	for _, keyword in ipairs(keywords or {}) do
		if string.find(text, string.lower(keyword), 1, true) then
			return _G.F.fireBattleYesOrNoAnswer(false, yesNoSignal, noButton)
		end
	end

	return false
end

_G.F.servicePromptDenials = function()
	if _G.denySwitchRequestEnabled then
		_G.F.denyBattlePromptByKeywords({ "switch", "will you switch" })
	end
	if _G.denyNicknameEnabled then
		_G.F.denyBattlePromptByKeywords({ "nickname", "give a nickname" })
	end
	if _G.denyReassignMoveEnabled then
		_G.F.denyBattlePromptByKeywords({ "forget", "replace", "reassign", "learn a new", "learned" })
	end
end

_G.F.skipBattleTheaterPuzzles = function()
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local candidates = {
		_G.F.safeTableGet(_G._p, "BattleTheater"),
		_G.F.safeTableGet(_G._p, "Theater"),
		type(_G._p.Menu) == "table" and _G.F.safeTableGet(_G._p.Menu, "battleTheater") or nil,
		type(_G._p.DataManager) == "table" and _G.F.safeTableGet(_G._p.DataManager, "currentChunk") or nil,
	}

	for _, module in ipairs(candidates) do
		if type(module) == "table" then
			for _, methodName in ipairs({ "skipPuzzle", "SkipPuzzle", "completePuzzle", "CompletePuzzle", "solvePuzzle", "SolvePuzzle", "skipPuzzles", "SkipPuzzles" }) do
				local method = _G.F.safeTableGet(module, methodName)
				if type(method) == "function" then
					local ok, result = pcall(method, module)
					if ok and result ~= false then
						return true, result
					end
				end
			end
		end
	end

	local ok, result, actionName = _G.F.pdsTryGetAny({
		{ "skipBattleTheaterPuzzle" },
		{ "skipTheaterPuzzle" },
		{ "completeBattleTheaterPuzzle" },
		{ "completeTheaterPuzzle" },
	})
	if ok then
		return true, result, actionName
	end

	return false, "No Battle Theater puzzle skipper was found in this area."
end

_G.showProgressHookOriginal = _G.showProgressHookOriginal or nil
_G.resetLastUnstuckHookOriginal = _G.resetLastUnstuckHookOriginal or nil
_G.battleTheatrePuzzleHookOriginals = _G.battleTheatrePuzzleHookOriginals or {}
_G.jackNpcChatHookOriginals = _G.jackNpcChatHookOriginals or {}
_G.jackMiscSettings = _G.jackMiscSettings or {}
_G.jackIgnoreNpcSession = _G.jackIgnoreNpcSession or {}
_G.jackBitBufferGetBitOriginal = _G.jackBitBufferGetBitOriginal or nil

_G.F.syncJackMiscSettings = function()
	_G.jackMiscSettings.NoNick = _G.denyNicknameEnabled and true or false
	_G.jackMiscSettings.NoSwitch = _G.denySwitchRequestEnabled and true or false
	_G.jackMiscSettings.NoNewMoves = _G.denyReassignMoveEnabled and true or false
	_G.jackMiscSettings.NoProgress = _G.disableShowProgressEnabled and true or false
end

-- MrJack Ignore NPC Battle: wrap BitBuffer.GetBit so trainers already seen on
-- this map are treated as defeated while the toggle is on.
_G.F.jackIgnoreNpcGetBit = function(...)
	local packed = { ... }
	local session = _G.jackIgnoreNpcSession
	if type(session) ~= "table" then
		session = {}
		_G.jackIgnoreNpcSession = session
	end

	local currentChunk = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "DataManager") or nil
	currentChunk = type(currentChunk) == "table" and _G.F.safeTableGet(currentChunk, "currentChunk") or nil
	local map = type(currentChunk) == "table" and currentChunk.map or nil
	if map ~= nil and not table.find(session, map) then
		if type(table.clear) == "function" then
			table.clear(session)
		else
			for i = #session, 1, -1 do
				session[i] = nil
			end
		end
		table.insert(session, map)
	end

	local playerData = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "PlayerData") or nil
	local defeatedTrainers = type(playerData) == "table" and playerData.defeatedTrainers or nil
	local target = packed[1]
	local trainerId = packed[2]

	if target == defeatedTrainers and trainerId ~= nil then
		if _G.ignoreNpcBattleEnabled and table.find(session, trainerId) then
			return true
		end

		if not table.find(session, trainerId) then
			table.insert(session, trainerId)
		end

		_G.F.jackEnterGameContext()
	end

	local original = _G.jackBitBufferGetBitOriginal
	if type(original) == "function" then
		return original(...)
	end

	return false
end

_G.F.jackInstallIgnoreNpcBattleHook = function()
	if not _G.F.ensureP() then
		return false
	end

	local bitBuffer = _G.F.safeTableGet(_G._p, "BitBuffer")
	if type(bitBuffer) ~= "table" or type(bitBuffer.GetBit) ~= "function" then
		return false
	end

	if bitBuffer.__jackIgnoreNpcHooked then
		return true
	end

	_G.jackBitBufferGetBitOriginal = bitBuffer.GetBit
	bitBuffer.GetBit = function(...)
		return _G.F.jackIgnoreNpcGetBit(...)
	end
	bitBuffer.__jackIgnoreNpcHooked = true
	return true
end

_G.F.endCurrentBattleForce = function()
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local battle = _G.F.jackGetBattle() or _G.F.getCurrentBattle()
	if type(battle) ~= "table" then
		return false, "No active battle."
	end

	if battle.CanRun == false then
		return false, "This battle cannot be force-ended (CanRun is false)."
	end

	local battleGui = _G.F.getBattleGuiModule()
	local idle = type(battleGui) == "table" and battleGui.IdleCameraController or nil
	if type(idle) == "table" and type(idle.quit) == "function" then
		pcall(function()
			idle:quit(battle)
		end)
	end

	pcall(function()
		_G.F.callBattleCameraMethod("stopIdleCamera", battle)
		_G.F.callBattleCameraMethod("StopIdleCamera", battle)
	end)

	pcall(function()
		battle.ended = true
		if battle.BattleEnded and type(battle.BattleEnded.Fire) == "function" then
			battle.BattleEnded:Fire()
		end
	end)

	return true, "Battle ended."
end

_G.F.processJackNpcChatSay = function(args)
	if type(args) ~= "table" then
		args = { args }
	end

	local textIndex = nil
	local text = nil
	for i = 2, math.min(#args, 4) do
		if type(args[i]) == "string" and string.lower(string.sub(args[i], 1, 5)) == "[y/n]" then
			textIndex = i
			text = args[i]
			break
		end
	end

	if not text and type(args[2]) == "string" then
		textIndex = 2
		text = args[2]
	end

	if type(text) ~= "string" then
		return args, false
	end

	if string.sub(text, 1, 8) == "[NoSkip]" then
		local stripped = { args[1], string.sub(text, 9) }
		for i = 3, #args do
			stripped[#stripped + 1] = args[i]
		end
		return stripped, true
	end

	local isYn = string.lower(string.sub(text, 1, 5)) == "[y/n]"
	if isYn then
		if _G.jackMiscSettings.NoSwitch and string.find(text, "Will you switch Loomians", 1, true) then
			args[textIndex] = "Auto Deny Swicth Question Enabled!"
			return args, true
		end

		if _G.jackMiscSettings.NoNick and string.find(text, "Give a nickname to the", 1, true) then
			args[textIndex] = "Auto Deny Nickname Enabled!"
			return args, true
		end

		if _G.jackMiscSettings.NoNewMoves then
			local lower = string.lower(text)
			if string.find(lower, "reassign its moves", 1, true) then
				args[textIndex] = "Auto Deny Reassign Move Enabled!"
				return args, true
			end
			if string.find(lower, " to give up on learning ", 1, true) then
				return "Y/N", true
			end
		end
	end

	-- MrJack Skip Dialogue: strip [y/n] / [gamepad] prefixes so prompts and
	-- dialogue advance through the hooked Say/message path (poll remains as backup).
	if _G.skipDialogueEnabled then
		local out = {}
		local changed = false
		for i = 1, #args do
			local value = args[i]
			if type(value) == "string" then
				local s = value
				local lowerPrefix5 = string.lower(string.sub(s, 1, 5))
				local lowerPrefix9 = string.lower(string.sub(s, 1, 9))
				if lowerPrefix5 == "[y/n]" then
					s = string.sub(s, 6)
					changed = true
				elseif lowerPrefix9 == "[gamepad]" then
					s = string.sub(s, 10)
					changed = true
				else
					changed = true
				end
				out[i] = s
			else
				out[i] = value
			end
		end
		if changed then
			return out, true
		end
	end

	return args, false
end

_G.F.wrapJackNpcChatHandler = function(host, methodName)
	if type(host) ~= "table" then
		return
	end

	local original = host[methodName]
	if type(original) ~= "function" then
		return
	end

	_G.jackNpcChatHookOriginals[host] = _G.jackNpcChatHookOriginals[host] or {}
	if _G.jackNpcChatHookOriginals[host][methodName] then
		return
	end

	_G.jackNpcChatHookOriginals[host][methodName] = original
	host[methodName] = function(...)
		_G.F.syncJackMiscSettings()
		local packed = { ... }
		local first, filtered = _G.F.processJackNpcChatSay(packed)

		if first == "Y/N" then
			return filtered
		end

		if filtered then
			local chat = type(_G._p) == "table" and _G._p.NPCChat or nil
			if type(chat) == "table" then
				if _G.skipDialogueEnabled then
					chat.fastForward = true
				end
				if type(chat.choose) == "function" then
					-- Deny path for rewritten Y/N prompts (NoSwitch / NoNick / NoNewMoves).
					local text = type(first) == "table" and first[2] or nil
					if type(text) == "string" and string.find(text, "Auto Deny", 1, true) then
						pcall(function()
							chat:choose(2)
						end)
					end
				end
			end
			_G.F.jackEnterGameContext()
			return original(unpack(first))
		end

		_G.F.jackEnterGameContext()
		return original(...)
	end
end

_G.F.jackInstallSwitchMonsterBusyHook = function()
	if not _G.F.ensureP() then
		return false
	end

	local battleGui = _G.F.safeTableGet(_G._p, "BattleGui")
	if type(battleGui) ~= "table" or type(battleGui.switchMonster) ~= "function" then
		return false
	end

	if battleGui.__jackSwitchMonsterHooked then
		return true
	end

	local original = battleGui.switchMonster
	battleGui.switchMonster = function(self, ...)
		local packed = { ... }
		local latch = packed[3] ~= false
		if latch then
			_G.jackMoveBusy = true
		end

		_G.F.jackEnterGameContext()
		local results = { pcall(original, self, ...) }

		if latch then
			_G.jackMoveBusy = false
		end

		if results[1] then
			return unpack(results, 2)
		end
	end

	battleGui.__jackSwitchMonsterHooked = true
	_G.jackSwitchMonsterOriginal = original
	return true
end

_G.jackFastBattleHookOriginals = _G.jackFastBattleHookOriginals or {}

_G.F.jackWrapNamedMethod = function(host, methodName, wrapperFactory)
	if type(host) ~= "table" or type(methodName) ~= "string" then
		return false
	end

	local original = host[methodName]
	if type(original) ~= "function" then
		return false
	end

	_G.jackFastBattleHookOriginals[host] = _G.jackFastBattleHookOriginals[host] or {}
	if _G.jackFastBattleHookOriginals[host][methodName] then
		return true
	end

	_G.jackFastBattleHookOriginals[host][methodName] = original
	host[methodName] = wrapperFactory(original)
	return true
end

_G.F.jackInstallFastBattleHooks = function()
	if not _G.F.ensureP() then
		return false
	end

	local battleGui = _G.F.safeTableGet(_G._p, "BattleGui")
	if type(battleGui) == "table" then
		for _, methodName in ipairs({
			"animWeather", "animStatus", "animAbility", "animBoost", "animHit", "animMove",
		}) do
			_G.F.jackWrapNamedMethod(battleGui, methodName, function(original)
				return function(...)
					if _G.fastForwardEnabled then
						return
					end
					_G.F.jackEnterGameContext()
					return original(...)
				end
			end)
		end

		_G.F.jackWrapNamedMethod(battleGui, "setCameraIfLookingAway", function(original)
			return function(self, battle, ...)
				local previous = nil
				if type(battle) == "table" then
					previous = battle.fastForward
					if _G.fastForwardEnabled then
						battle.fastForward = true
					end
				end
				_G.F.jackEnterGameContext()
				local ok, a, b, c = pcall(original, self, battle, ...)
				if type(battle) == "table" then
					battle.fastForward = previous or false
				end
				if ok then
					return a, b, c
				end
			end
		end)
	end

	local roundedFrame = _G.F.safeTableGet(_G._p, "RoundedFrame")
	if type(roundedFrame) == "table" then
		_G.F.jackWrapNamedMethod(roundedFrame, "setFillbarRatio", function(original)
			return function(self, a, b, animate, ...)
				if _G.fastForwardEnabled and (_G.F.jackGetBattle() or _G.F.getCurrentBattle()) then
					animate = false
				end
				_G.F.jackEnterGameContext()
				return original(self, a, b, animate, ...)
			end
		end)
	end

	local function wrapFastForwardBracket(host, methodName, battleIndex)
		_G.F.jackWrapNamedMethod(host, methodName, function(original)
			return function(...)
				local packed = { ... }
				local owner = packed[battleIndex]
				local battle = type(owner) == "table" and (owner.battle or owner) or nil
				local previous = nil
				if type(battle) == "table" then
					previous = battle.fastForward
					battle.fastForward = _G.fastForwardEnabled and true or false
				end
				_G.F.jackEnterGameContext()
				local results = { pcall(original, ...) }
				if type(battle) == "table" then
					battle.fastForward = previous or false
				end
				if results[1] then
					return unpack(results, 2)
				end
			end
		end)
	end

	local sprite = _G.F.safeTableGet(_G._p, "BattleClientSprite")
	if type(sprite) == "table" then
		for _, methodName in ipairs({
			"animFaint", "animSummon", "animUnsummon", "monsterIn", "monsterOut",
			"animEmulate", "animScapegoat", "animScapegoatIn", "animScapegoatOut", "animRecolor",
		}) do
			wrapFastForwardBracket(sprite, methodName, 1)
		end
	end

	local side = _G.F.safeTableGet(_G._p, "BattleClientSide")
	if type(side) == "table" then
		for _, methodName in ipairs({ "switchOut", "faint", "swapTo", "dragIn" }) do
			wrapFastForwardBracket(side, methodName, 1)
		end
	end

	return true
end

_G.F.installJackStyleGameplayHooks = function()
	if not _G.F.ensureP() then
		return false
	end

	_G.F.syncJackMiscSettings()
	_G.F.jackInstallIgnoreNpcBattleHook()
	_G.F.jackInstallSwitchMonsterBusyHook()
	_G.F.jackInstallFastBattleHooks()

	local menu = _G.F.safeTableGet(_G._p, "Menu")
	local mastery = type(menu) == "table" and _G.F.safeTableGet(menu, "mastery") or nil
	if type(mastery) == "table" and type(mastery.showProgressUpdate) == "function" then
		if not _G.showProgressHookOriginal then
			_G.showProgressHookOriginal = mastery.showProgressUpdate
		end
		mastery.showProgressUpdate = function(...)
			_G.F.syncJackMiscSettings()
			if _G.jackMiscSettings.NoProgress or _G.disableShowProgressEnabled then
				return
			end
			_G.F.jackEnterGameContext()
			return _G.showProgressHookOriginal(...)
		end
	end

	local chat = _G.F.safeTableGet(_G._p, "NPCChat")
	if type(chat) == "table" then
		for _, methodName in ipairs({ "Say", "say" }) do
			_G.F.wrapJackNpcChatHandler(chat, methodName)
		end
	end

	local battleGui = _G.F.safeTableGet(_G._p, "BattleGui")
	if type(battleGui) == "table" then
		_G.F.wrapJackNpcChatHandler(battleGui, "message")
	end

	return true
end

_G.F.restoreJackStyleGameplayHooks = function()
	if not _G.F.ensureP() then
		return
	end

	local menu = _G.F.safeTableGet(_G._p, "Menu")
	local mastery = type(menu) == "table" and _G.F.safeTableGet(menu, "mastery") or nil
	if type(mastery) == "table" and _G.showProgressHookOriginal then
		pcall(function()
			mastery.showProgressUpdate = _G.showProgressHookOriginal
		end)
		_G.showProgressHookOriginal = nil
	end

	for host, methods in pairs(_G.jackNpcChatHookOriginals) do
		if type(host) == "table" and type(methods) == "table" then
			for methodName, original in pairs(methods) do
				if type(original) == "function" then
					pcall(function()
						host[methodName] = original
					end)
				end
			end
		end
	end
	_G.jackNpcChatHookOriginals = {}

	for host, methods in pairs(_G.jackFastBattleHookOriginals) do
		if type(host) == "table" and type(methods) == "table" then
			for methodName, original in pairs(methods) do
				if type(original) == "function" then
					pcall(function()
						host[methodName] = original
					end)
				end
			end
		end
	end
	_G.jackFastBattleHookOriginals = {}

	local battleGui = _G.F.safeTableGet(_G._p, "BattleGui")
	if type(battleGui) == "table" and type(_G.jackSwitchMonsterOriginal) == "function" then
		pcall(function()
			battleGui.switchMonster = _G.jackSwitchMonsterOriginal
			battleGui.__jackSwitchMonsterHooked = nil
		end)
		_G.jackSwitchMonsterOriginal = nil
	end

	local bitBuffer = _G.F.safeTableGet(_G._p, "BitBuffer")
	if type(bitBuffer) == "table" and type(_G.jackBitBufferGetBitOriginal) == "function" then
		pcall(function()
			bitBuffer.GetBit = _G.jackBitBufferGetBitOriginal
			bitBuffer.__jackIgnoreNpcHooked = nil
		end)
		_G.jackBitBufferGetBitOriginal = nil
	end

	local options = type(menu) == "table" and _G.F.safeTableGet(menu, "options") or nil
	if type(options) == "table" and _G.resetLastUnstuckHookOriginal then
		pcall(function()
			options.resetLastUnstuckTick = _G.resetLastUnstuckHookOriginal
		end)
		_G.resetLastUnstuckHookOriginal = nil
	end

	for module, originals in pairs(_G.battleTheatrePuzzleHookOriginals) do
		if type(module) == "table" and type(originals) == "table" then
			pcall(function()
				if originals.enablePuzzleControls then
					module.enablePuzzleControls = originals.enablePuzzleControls
				end
				if originals.EnablePuzzleControls then
					module.EnablePuzzleControls = originals.EnablePuzzleControls
				end
			end)
		end
	end
	_G.battleTheatrePuzzleHookOriginals = {}
end

_G.F.applyNoUnstuckCooldown = function()
	if not _G.F.ensureP() then
		return false
	end

	for _, module in ipairs({
		_G.F.safeTableGet(_G._p, "MasterControl"),
		type(_G._p.Menu) == "table" and _G.F.safeTableGet(_G._p.Menu, "unstuck") or nil,
		_G.F.safeTableGet(_G._p, "Unstuck"),
	}) do
		if type(module) == "table" then
			for _, key in ipairs({ "unstuckCooldown", "UnstuckCooldown", "lastUnstuck", "LastUnstuck", "unstuckAt", "nextUnstuckAt", "_unstuckCooldown" }) do
				pcall(function()
					module[key] = 0
				end)
			end
		end
	end

	return true
end

_G.F.rejoinServer = function()
	local teleportService = game:GetService("TeleportService")
	local ok, err = pcall(function()
		teleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, _G.Player)
	end)
	return ok, ok and nil or tostring(err)
end

_G.F.getPublicServers = function(cursor)
	local url = string.format(
		"https://games.roblox.com/v1/games/%s/servers/Public?sortOrder=Asc&limit=100%s",
		tostring(game.PlaceId),
		cursor and ("&cursor=" .. _G.HttpService:UrlEncode(cursor)) or ""
	)

	local ok, body = pcall(function()
		return game:HttpGet(url)
	end)
	if not ok then
		return nil, tostring(body)
	end

	local decodeOk, data = pcall(function()
		return _G.HttpService:JSONDecode(body)
	end)
	if not decodeOk or type(data) ~= "table" then
		return nil, "Could not decode server list."
	end

	return data
end

_G.F.teleportToServer = function(serverId)
	local teleportService = game:GetService("TeleportService")
	local ok, err = pcall(function()
		teleportService:TeleportToPlaceInstance(game.PlaceId, serverId, _G.Player)
	end)
	return ok, ok and nil or tostring(err)
end

_G.F.switchServer = function(findMostEmpty)
	local bestServer = nil
	local cursor = nil

	for _ = 1, findMostEmpty and 5 or 1 do
		local data, reason = _G.F.getPublicServers(cursor)
		if not data then
			return false, reason
		end

		for _, server in ipairs(data.data or {}) do
			if server.id ~= game.JobId and tonumber(server.playing) and tonumber(server.maxPlayers)
				and tonumber(server.playing) < tonumber(server.maxPlayers) then
				if not bestServer
					or (findMostEmpty and tonumber(server.playing) < tonumber(bestServer.playing))
					or (not findMostEmpty and math.random() < 0.35) then
					bestServer = server
				end
			end
		end

		cursor = data.nextPageCursor
		if not cursor then
			break
		end
	end

	if not bestServer then
		return false, "No joinable server found."
	end

	return _G.F.teleportToServer(bestServer.id)
end

-- "Disable Saving" rides the game's cutscene state: while a cutscene is marked
-- active the game suppresses saving. Toggle ON = StartCutscene, OFF = EndCutscene.
_G.F.setSavingDisabled = function(value)
	local enabled = value and true or false

	-- Early return matters: OrionLib fires toggle callbacks during AddToggle
	-- (creation), and an error thrown there aborts building the rest of the
	-- tab. With Default=false this makes the creation-time call a no-op.
	if _G.savingDisabled == enabled then
		return true
	end

	if type(_G._p) ~= "table" then
		local ok, found = pcall(_G.F.findP)
		_G._p = ok and found or nil
	end

	local cutsceneManager = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "CutsceneManager") or nil
	local methodName = enabled and "StartCutscene" or "EndCutscene"
	local method = type(cutsceneManager) == "table" and _G.F.safeTableGet(cutsceneManager, methodName) or nil

	if type(method) ~= "function" then
		return false, "CutsceneManager." .. methodName .. " is not available."
	end

	local ok, err = pcall(function()
		method(cutsceneManager)
	end)

	if not ok then
		return false, tostring(err)
	end

	_G.savingDisabled = enabled
	return true
end

_G.F.callBattleCameraMethod = function(methodName, battle)
	if type(_G._p) ~= "table" then
		return
	end

	local battleCamera = _G.F.safeTableGet(_G._p, "BattleCamera")
	local method = type(battleCamera) == "table" and _G.F.safeTableGet(battleCamera, methodName) or nil
	if type(method) ~= "function" then
		return
	end

	if pcall(function()
		method(battleCamera, battle)
	end) then
		return
	end

	if pcall(function()
		method(battleCamera)
	end) then
		return
	end

	pcall(function()
		method(battle)
	end)
end

-- The game's idle battle camera (BattleCamera.startIdleCamera) pans between the
-- battlers with cinematic tweens that keep reading battle.CoordinateFrame1/2 and
-- the side sprites every frame. Our automations end/tear down battles the instant
-- they're runnable, so those fields go nil underneath the camera and its
-- render-step callbacks spam "attempt to index nil with 'p'/'Position'/'Y'".
--
-- One hook on _p.BattleCamera covers every battle mode (static, encounter,
-- trainer, fishing, catch). We (1) pcall-guard setCamera/setCameraIfLookingAway
-- so a torn-down battle can never error inside a render step, and (2) skip the
-- purely-cosmetic idle camera entirely while automation is active.
_G.battleCameraHooked = false

_G.F.shouldSuppressBattleCameraIdle = function()
	if _G.fastForwardEnabled
		or _G.autoEncounterEnabled
		or _G.autoEncounterPausedBattle ~= nil
		or _G.autoFishingEnabled
		or _G.autoTrainerEnabled
		or _G.autoCatchEnabled then
		return true
	end

	local staticActive = false
	pcall(function()
		staticActive = _G.StaticAutomation and _G.StaticAutomation:isAutomationActive() or false
	end)

	return staticActive
end

_G.F.installBattleCameraSafetyHooks = function()
	if _G.battleCameraHooked then
		return
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local battleCamera = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "BattleCamera") or nil
	if type(battleCamera) ~= "table" then
		return
	end

	local originalSetCamera = _G.F.safeTableGet(battleCamera, "setCamera")
	if type(originalSetCamera) == "function" and not battleCamera.__llsploitSetCameraGuard then
		_G.F.safeTableSet(battleCamera, "setCamera", function(...)
			pcall(originalSetCamera, ...)
		end)
		battleCamera.__llsploitSetCameraGuard = true
	end

	local originalLookAway = _G.F.safeTableGet(battleCamera, "setCameraIfLookingAway")
	if type(originalLookAway) == "function" and not battleCamera.__llsploitLookAwayGuard then
		_G.F.safeTableSet(battleCamera, "setCameraIfLookingAway", function(...)
			pcall(originalLookAway, ...)
		end)
		battleCamera.__llsploitLookAwayGuard = true
	end

	local originalStartIdle = _G.F.safeTableGet(battleCamera, "startIdleCamera")
	if type(originalStartIdle) == "function" and not battleCamera.__llsploitStartIdleGuard then
		_G.F.safeTableSet(battleCamera, "startIdleCamera", function(...)
			if _G.F.shouldSuppressBattleCameraIdle() then
				return
			end
			pcall(originalStartIdle, ...)
		end)
		battleCamera.__llsploitStartIdleGuard = true
	end

	_G.battleCameraHooked = true
end

_G.F.clearCurrentBattleReference = function(battle)
	if type(_G._p) ~= "table" or type(battle) ~= "table" then
		return
	end

	for _, containerName in ipairs({ "Battle", "BattleClient" }) do
		local container = _G.F.safeTableGet(_G._p, containerName)
		if type(container) == "table" and _G.F.safeTableGet(container, "currentBattle") == battle then
			_G.F.safeTableSet(container, "currentBattle", nil)
		end
	end
end

_G.F.releaseFinishedBattle = function(battle)
	if type(battle) ~= "table" then
		return
	end

	_G.F.clearBattleRunTiming(battle)
	_G.F.setBattleFastForward(false, battle)

	_G.F.callBattleCameraMethod("stopIdleCamera", battle)
	_G.F.callBattleCameraMethod("StopIdleCamera", battle)

	pcall(function()
		_G.RunService:UnbindFromRenderStep("BattleCamera")
	end)

	_G.F.clearCurrentBattleReference(battle)
end

_G.F.releaseBattleAutomationForCapture = function(battle)
	if type(battle) ~= "table" then
		return
	end

	_G.F.clearBattleRunTiming(battle)
	_G.F.applyBattleAnimationFastForward(battle, false, false)
	_G.F.setBattleFastForward(false, battle)
end

_G.F.setAutoEncounterToggleState = function(value)
	if _G.configUi.autoEncounterToggle and type(_G.configUi.autoEncounterToggle.Set) == "function" then
		pcall(function()
			_G.configUi.autoEncounterToggle:Set(value and true or false)
		end)
	end
end

_G.F.pauseAutoEncounterForBattle = function(battle, displayName, reason, notificationTitle)
	if type(battle) ~= "table" then
		return false
	end

	if _G.autoEncounterPausedBattle == battle then
		return true
	end

	_G.autoEncounterPausedBattle = battle
	_G.autoEncounterPausedDisplayName = displayName
	_G.autoEncounterPausedReason = reason

	_G.F.releaseBattleAutomationForCapture(battle)
	_G.autoEncounterEnabled = false
	_G.F.setAutoEncounterToggleState(false)

	pcall(function()
		local content
		if reason and reason ~= "" and reason ~= "Target" then
			content = string.format(
				"Found %s (%s). Auto Encounter paused until this encounter ends.",
				tostring(displayName),
				tostring(reason)
			)
		else
			content = string.format(
				"Found %s. Auto Encounter paused until this encounter ends.",
				tostring(displayName)
			)
		end

		_G.OrionLib:MakeNotification({
			Name = notificationTitle or "Auto Encounter Paused",
			Content = content,
			Time = 8,
		})
	end)

	return true
end

_G.F.resumeAutoEncounterAfterPausedBattle = function(battle)
	if not _G.autoEncounterPausedBattle then
		return false
	end

	if battle and _G.autoEncounterPausedBattle ~= battle then
		return false
	end

	local displayName = _G.autoEncounterPausedDisplayName or "encounter"
	_G.autoEncounterPausedBattle = nil
	_G.autoEncounterPausedDisplayName = nil
	_G.autoEncounterPausedReason = nil

	_G.autoEncounterEnabled = true
	_G.F.setAutoEncounterToggleState(true)

	pcall(function()
		_G.OrionLib:MakeNotification({
			Name = "Auto Encounter Resumed",
			Content = string.format("Auto Encounter resumed after %s.", tostring(displayName)),
			Time = 4,
		})
	end)

	return true
end

_G.F.pauseNaturalRunForSpecialBattle = function(battle)
	if type(battle) ~= "table" or not _G.F.hasWildFoeLoaded(battle) then
		return false
	end

	if _G.naturalRunPausedSpecialBattle == battle then
		return true
	end

	local foe, specialValue, specialReason = _G.F.getWildSpecialFoeForStop(battle)
	if not foe then
		return false
	end

	_G.naturalRunPausedSpecialBattle = battle

	local displayName = _G.F.getEncounterFoeSpeciesName(foe)
	if displayName == "" then
		displayName = tostring(foe.name or foe.species or "wild Loomian")
	end

	return _G.F.pauseAutoEncounterForBattle(battle, displayName, specialReason, "Auto Encounter Paused")
end

_G.F.clearNaturalRunSpecialPause = function(battle)
	if not battle or _G.naturalRunPausedSpecialBattle == battle then
		_G.naturalRunPausedSpecialBattle = nil
	end

	if not battle or _G.encounterTargetStopBattle == battle then
		_G.encounterTargetStopBattle = nil
	end
end

_G.F.setTemporaryBattleFlag = function(object, key, value, resetDelay)
	if type(object) ~= "table" then
		return
	end

	if not _G.F.safeTableSet(object, key, value) then
		return
	end

	task.delay(resetDelay or 0.35, function()
		if _G.F.safeTableGet(object, key) == value then
			_G.F.safeTableSet(object, key, false)
		end
	end)
end

_G.F.skipEncounterCutscene = function(battle)
	if type(battle) ~= "table" then
		return
	end

	_G.F.applyBattleAnimationFastForward(battle, false)
	_G.F.setTemporaryBattleFlag(battle, "skipping", true, 0.35)
	_G.F.setTemporaryBattleFlag(battle, "skipRequested", true, 0.35)
	_G.F.setTemporaryBattleFlag(battle, "skipIntroRequested", true, 0.35)

	_G.F.callMethodsIfPresent(battle, {
		"skipIntro", "SkipIntro",
		"skipCutscene", "SkipCutscene",
		"skip", "Skip",
		"finishIntro", "FinishIntro"
	})

	local scene = _G.F.safeTableGet(battle, "scene")
	if type(scene) == "table" then
		_G.F.applyFastForwardFlagsToTable(scene, true)
		_G.F.setTemporaryBattleFlag(scene, "skipping", true, 0.35)

		_G.F.callMethodsIfPresent(scene, {
			"skip", "Skip",
			"finish", "Finish",
			"skipIntro", "SkipIntro"
		})
	end

	if type(_G._p) == "table" and type(_G._p.NPCChat) == "table" then
		pcall(function()
			_G._p.NPCChat.fastForward = true
			_G._p.NPCChat.skipping = true
		end)

		_G.F.callMethodsIfPresent(_G._p.NPCChat, {
			"advance", "Advance",
			"next", "Next",
			"skip", "Skip",
			"close", "Close",
			"finish", "Finish"
		})
	end
end

_G.F.skipTrainerText = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	if type(_G._p) ~= "table" or type(_G._p.NPCChat) ~= "table" then
		return
	end

	pcall(function()
		_G._p.NPCChat.fastForward = true
		_G._p.NPCChat.skipping = true
	end)

	pcall(function()
		for _, methodName in ipairs({
			"choose", "Choose",
			"answer", "Answer",
			"respond", "Respond",
			"select", "Select",
			"selectOption", "SelectOption",
			"optionChosen", "OptionChosen"
		}) do
			local method = _G.F.safeTableGet(_G._p.NPCChat, methodName)
			if type(method) == "function" then
				pcall(function()
					method(_G._p.NPCChat, false)
				end)
				pcall(function()
					method(_G._p.NPCChat, "No")
				end)
				pcall(function()
					method(_G._p.NPCChat, 2)
				end)
			end
		end
	end)

	pcall(function()
		if type(_G._p.NPCChat.isChatting) == "function" and _G._p.NPCChat:isChatting() then
			_G._p.NPCChat:clear()
		end
	end)

	pcall(function()
		if type(_G._p.NPCChat.manualAdvance) == "function"
			and (type(_G._p.NPCChat.isAwaitingManualAdvance) ~= "function" or _G._p.NPCChat:isAwaitingManualAdvance()) then
			_G._p.NPCChat:manualAdvance()
		end
	end)

	_G.F.callMethodsIfPresent(_G._p.NPCChat, {
		"manualAdvance", "ManualAdvance",
		"advance", "Advance",
		"next", "Next",
		"skip", "Skip",
		"close", "Close",
		"finish", "Finish",
		"continue", "Continue"
	})
end

_G.F.clickThroughNpcChat = function()
	_G.F.skipTrainerText()

	pcall(function()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		if type(_G._p) == "table" and type(_G._p.NPCChat) == "table" then
			_G._p.NPCChat.TextSpeedMultiplier = 100

			if type(_G._p.NPCChat.isChatting) == "function" and _G._p.NPCChat:isChatting() and type(_G._p.NPCChat.clear) == "function" then
				_G._p.NPCChat:clear()
			end
		end
	end)
end

-- Mastery report ("Mastery Progress") appears after a battle grants a mastery
-- level-up. In doTrainerBattle the game calls mastery:showProgressUpdate(...)
-- synchronously and blocks on the report's OK button, so a level-up would
-- otherwise freeze Auto Trainer until the user clicks OK manually.
--
-- The report text is rendered per-glyph (Utilities.Write), so it has no readable
-- .Text to match on. We key off the report's fake-watch ImageButton
-- (rbxassetid://1935359631, created only by Menu:createFakeWatch, which is used
-- only by the mastery report), then look for a visible "OK" label when present
-- and otherwise click the bottom-right actionable button inside the report.
_G.MASTERY_WATCH_IMAGE = "rbxassetid://1935359631"
_G.MASTERY_SCROLL_TOP_IMAGE = "rbxassetid://3763595294"
_G.masteryReportLastClickAt = 0
_G.masteryReportOkFirstSeenAt = 0
_G.masteryReportOkButton = nil

_G.F.normalizeGuiSearchText = function(value)
	local text = string.lower(tostring(value or ""))
	text = string.gsub(text, "%s+", " ")
	text = string.gsub(text, "[^%w%s]", "")
	return string.gsub(text, "^%s*(.-)%s*$", "%1")
end

_G.F.guiTextLooksLikeOk = function(value)
	local normalized = _G.F.normalizeGuiSearchText(value)
	if normalized == "" then
		return false
	end

	if normalized == "ok" or normalized == "buttona ok" then
		return true
	end

	return string.find(normalized, " ok", 1, true) ~= nil
		or string.find(normalized, "ok ", 1, true) ~= nil
		or string.find(normalized, "buttona ok", 1, true) ~= nil
end

_G.F.findAncestorGuiButton = function(item)
	local current = item

	while current do
		if current:IsA("GuiButton") then
			return current
		end

		current = current.Parent
	end

	return nil
end

_G.F.collectGuiTextSnapshot = function(root)
	if typeof(root) ~= "Instance" then
		return ""
	end

	local parts = {}
	local ok, descendants = pcall(function()
		return root:GetDescendants()
	end)

	if not ok then
		return ""
	end

	for _, item in ipairs(descendants) do
		if _G.F.isGuiChainVisible(item) then
			if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
				local okText, text = pcall(function()
					return item.Text
				end)

				if okText and type(text) == "string" and text ~= "" then
					table.insert(parts, text)
				end
			end

			local okContent, contentText = pcall(function()
				return item.ContentText
			end)

			if okContent and type(contentText) == "string" and contentText ~= "" then
				table.insert(parts, contentText)
			end
		end
	end

	return table.concat(parts, " ")
end

_G.F.getMasteryGuiContainers = function()
	local containers = {}
	local seen = {}

	local function add(container)
		if typeof(container) == "Instance" and not seen[container] then
			seen[container] = true
			table.insert(containers, container)
		end
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	if type(_G._p) == "table" then
		local utilities = _G.F.safeTableGet(_G._p, "Utilities")
		add(type(utilities) == "table" and _G.F.safeTableGet(utilities, "frontGui") or nil)

		local menu = _G.F.safeTableGet(_G._p, "Menu")
		add(type(menu) == "table" and _G.F.safeTableGet(menu, "frontContainer") or nil)
	end

	pcall(function()
		local playerGui = _G.Player and _G.Player:FindFirstChildOfClass("PlayerGui")
		add(playerGui)
	end)

	return containers
end

_G.F.getMasteryReportRoot = function()
	for _, container in ipairs(_G.F.getMasteryGuiContainers()) do
		local ok, descendants = pcall(function()
			return container:GetDescendants()
		end)

		if ok then
			for _, item in ipairs(descendants) do
				if item:IsA("ImageButton") and item.Image == _G.MASTERY_WATCH_IMAGE and _G.F.isGuiChainVisible(item) then
					return item
				end
			end
		end
	end

	for _, container in ipairs(_G.F.getMasteryGuiContainers()) do
		local ok, descendants = pcall(function()
			return container:GetDescendants()
		end)

		if ok then
			for _, item in ipairs(descendants) do
				if item:IsA("ScrollingFrame")
					and item.TopImage == _G.MASTERY_SCROLL_TOP_IMAGE
					and _G.F.isGuiChainVisible(item) then
					local current = item.Parent

					while current do
						if current:IsA("ImageButton") and current.Image == _G.MASTERY_WATCH_IMAGE then
							return current
						end

						current = current.Parent
					end
				end
			end
		end
	end

	return nil
end

_G.F.findMasteryReportOkButtonByText = function(reportRoot)
	local roots = {}

	if typeof(reportRoot) == "Instance" then
		table.insert(roots, reportRoot)
	else
		for _, container in ipairs(_G.F.getMasteryGuiContainers()) do
			table.insert(roots, container)
		end
	end

	for _, root in ipairs(roots) do
		local ok, descendants = pcall(function()
			return root:GetDescendants()
		end)

		if ok then
			for _, item in ipairs(descendants) do
				if _G.F.isGuiChainVisible(item) then
					local itemText = nil

					if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
						local okText, text = pcall(function()
							return item.Text
						end)

						if okText then
							itemText = text
						end
					end

					if not itemText then
						local okContent, contentText = pcall(function()
							return item.ContentText
						end)

						if okContent then
							itemText = contentText
						end
					end

					if _G.F.guiTextLooksLikeOk(itemText) then
						local button = item:IsA("GuiButton") and item or _G.F.findAncestorGuiButton(item)
						if button then
							return button
						end
					end
				end
			end
		end
	end

	return nil
end

_G.F.findMasteryReportOkButton = function(reportRoot)
	if typeof(reportRoot) ~= "Instance" then
		return _G.F.findMasteryReportOkButtonByText(nil)
	end

	local textButton = _G.F.findMasteryReportOkButtonByText(reportRoot)
	if textButton then
		return textButton
	end

	local ok, descendants = pcall(function()
		return reportRoot:GetDescendants()
	end)

	if not ok then
		return nil
	end

	local reportPos = reportRoot.AbsolutePosition
	local reportSize = reportRoot.AbsoluteSize
	local reportBottom = reportPos.Y + reportSize.Y
	local bestButton = nil
	local bestScore = -math.huge

	for _, item in ipairs(descendants) do
		if item ~= reportRoot and item:IsA("GuiButton") and _G.F.isGuiChainVisible(item) then
			local itemText = _G.F.collectGuiTextSnapshot(item)
			if _G.F.guiTextLooksLikeOk(itemText) then
				return item
			end

			local pos = item.AbsolutePosition
			local size = item.AbsoluteSize
			if size.X > 0 and size.Y > 0 then
				local centerX = pos.X + (size.X / 2)
				local centerY = pos.Y + (size.Y / 2)
				local inLowerHalf = centerY >= reportPos.Y + (reportSize.Y * 0.5)
				local inRightSide = centerX >= reportPos.X + (reportSize.X * 0.45)
				local nearReportBottom = pos.Y + size.Y >= reportBottom - math.max(reportSize.Y * 0.2, 24)

				if inLowerHalf and inRightSide and nearReportBottom then
					local score = centerX + (centerY * 0.01)
					if score > bestScore then
						bestScore = score
						bestButton = item
					end
				end
			end
		end
	end

	if bestButton then
		return bestButton
	end

	local fallbackY = -math.huge

	for _, item in ipairs(descendants) do
		if item ~= reportRoot and item:IsA("GuiButton") and _G.F.isGuiChainVisible(item) then
			local y = item.AbsolutePosition.Y
			if y > fallbackY then
				fallbackY = y
				bestButton = item
			end
		end
	end

	return bestButton
end

_G.F.isMasteryReportVisible = function()
	local reportRoot = _G.F.getMasteryReportRoot()
	if reportRoot then
		return true
	end

	for _, container in ipairs(_G.F.getMasteryGuiContainers()) do
		local snapshot = _G.F.collectGuiTextSnapshot(container)
		if string.find(_G.F.normalizeGuiSearchText(snapshot), "mastery progress", 1, true) then
			return true
		end
	end

	return false
end

_G.F.dismissMasteryReport = function()
	if not _G.F.isMasteryReportVisible() then
		_G.masteryReportOkFirstSeenAt = 0
		_G.masteryReportOkButton = nil
		return false
	end

	local reportRoot = _G.F.getMasteryReportRoot()
	local okButton = _G.F.findMasteryReportOkButton(reportRoot)
	if not okButton then
		_G.masteryReportOkFirstSeenAt = 0
		_G.masteryReportOkButton = nil
		return false
	end

	local now = os.clock()
	if okButton ~= _G.masteryReportOkButton then
		_G.masteryReportOkButton = okButton
		_G.masteryReportOkFirstSeenAt = now
		return false
	end

	if now - _G.masteryReportOkFirstSeenAt < 0.2 then
		return false
	end

	if now - _G.masteryReportLastClickAt < 0.4 then
		return false
	end
	_G.masteryReportLastClickAt = now

	return _G.F.activateGuiButton(okButton) and true or false
end

_G.F.isTrainerSwitchPromptText = function(text)
	local lower = string.lower(tostring(text or ""))
	if lower == "" then
		return false
	end

	if string.find(lower, "switch loomian", 1, true) then
		return true
	end

	return string.find(lower, "send in", 1, true) ~= nil
		and string.find(lower, "will you", 1, true) ~= nil
end

_G.F.isCaptureNicknamePromptText = function(text)
	local lower = string.lower(tostring(text or ""))
	if lower == "" then
		return false
	end

	if string.find(lower, "nickname", 1, true)
		or string.find(lower, "give a nickname", 1, true)
		or string.find(lower, "no nickname", 1, true) then
		return true
	end

	return string.find(lower, "captured", 1, true) ~= nil
		and string.find(lower, "nickname", 1, true) ~= nil
end

_G.F.getVisibleBattlePromptTextSnapshot = function()
	local parts = {}
	local seen = {}

	local function addContainer(container)
		if container and not seen[container] then
			seen[container] = true
			table.insert(parts, container)
		end
	end

	pcall(function()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local utilities = type(_G._p) == "table" and _G._p.Utilities or nil
		addContainer(utilities and utilities.frontGui or nil)
	end)

	pcall(function()
		local playerGui = _G.Player and _G.Player:FindFirstChildOfClass("PlayerGui")
		addContainer(playerGui)
	end)

	local texts = {}

	for _, container in ipairs(parts) do
		local ok, descendants = pcall(function()
			return container:GetDescendants()
		end)

		if ok then
			for _, item in ipairs(descendants) do
				if _G.F.isGuiChainVisible(item) then
					if item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox") then
						local okText, text = pcall(function()
							return item.Text
						end)

						if okText and type(text) == "string" and text ~= "" then
							table.insert(texts, text)
						end
					end

					local okContent, contentText = pcall(function()
						return item.ContentText
					end)

					if okContent and type(contentText) == "string" and contentText ~= "" then
						table.insert(texts, contentText)
					end
				end
			end
		end
	end

	return string.lower(table.concat(texts, " "))
end

_G.F.findVisibleBattleYesOrNoPrompt = function()
	local function findIn(container)
		if not container then
			return nil
		end

		local ok, descendants = pcall(function()
			return container:GetDescendants()
		end)

		if not ok then
			return nil
		end

		for _, item in ipairs(descendants) do
			if item.Name == "YesOrNoPrompt" and _G.F.isGuiChainVisible(item) then
				return item
			end
		end

		return nil
	end

	pcall(function()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end
	end)

	local utilities = type(_G._p) == "table" and _G._p.Utilities or nil
	local promptFrame = findIn(utilities and utilities.frontGui or nil)
	if promptFrame then
		return promptFrame
	end

	local playerGui = _G.Player and _G.Player:FindFirstChildOfClass("PlayerGui")
	promptFrame = findIn(playerGui)
	if promptFrame then
		return promptFrame
	end

	local battleGui = type(_G._p) == "table" and _G._p.BattleGui or nil
	if type(battleGui) == "table" then
		for _, value in pairs(battleGui) do
			if typeof(value) == "Instance" and value.Name == "YesOrNoPrompt" and _G.F.isGuiChainVisible(value) then
				return value
			end
		end
	end

	return nil
end

_G.F.getBattleYesOrNoPromptButtons = function(promptRoot)
	if typeof(promptRoot) ~= "Instance" then
		if type(promptRoot) == "table" and typeof(promptRoot.gui) == "Instance" then
			promptRoot = promptRoot.gui.Parent or promptRoot.gui
		else
			return nil, nil
		end
	end

	if not promptRoot then
		return nil, nil
	end

	local buttons = {}
	local ok, descendants = pcall(function()
		return promptRoot:GetDescendants()
	end)

	if not ok then
		return nil, nil
	end

	for _, item in ipairs(descendants) do
		if item:IsA("ImageButton") and _G.F.isGuiChainVisible(item) then
			table.insert(buttons, item)
		end
	end

	table.sort(buttons, function(left, right)
		local leftY = left.Position.Y.Scale + (left.Position.Y.Offset / math.max(left.AbsoluteSize.Y, 1))
		local rightY = right.Position.Y.Scale + (right.Position.Y.Offset / math.max(right.AbsoluteSize.Y, 1))
		return leftY < rightY
	end)

	return buttons[1], buttons[2]
end

_G.F.getBattleYesOrNoLiveState = function()
	local promptFrame = nil
	local yesNoSignal = nil
	local noButton = nil

	pcall(function()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local battleGui = type(_G._p) == "table" and _G._p.BattleGui or nil
		local promptYesOrNo = battleGui
			and (_G.F.safeTableGet(battleGui, "promptYesOrNo") or _G.F.safeTableGet(battleGui, "PromptYesOrNo"))
			or nil

		if type(promptYesOrNo) == "function" and type(debug) == "table" and type(debug.getupvalues) == "function" then
			local ok, upvalues = pcall(function()
				return { debug.getupvalues(promptYesOrNo) }
			end)

			if ok then
				for _, upvalue in ipairs(upvalues) do
					if type(upvalue) == "table" and type(upvalue.Fire) == "function" and type(upvalue.Wait) == "function" then
						yesNoSignal = upvalue
					end

					if type(upvalue) == "table" and upvalue.Visible == true then
						promptFrame = upvalue
						if typeof(upvalue.gui) == "Instance" then
							local _, foundNo = _G.F.getBattleYesOrNoPromptButtons(upvalue.gui.Parent or upvalue.gui)
							noButton = foundNo or noButton
						end
					end

					if typeof(upvalue) == "Instance" and upvalue:IsA("ImageButton") and _G.F.isGuiChainVisible(upvalue) then
						local y = upvalue.Position.Y.Scale + (upvalue.Position.Y.Offset / math.max(upvalue.AbsoluteSize.Y, 1))
						if y >= 0.5 then
							noButton = upvalue
						end
					end
				end
			end
		end
	end)

	if not promptFrame then
		promptFrame = _G.F.findVisibleBattleYesOrNoPrompt()
	end

	if promptFrame and not noButton then
		local searchRoot = promptFrame
		if type(promptFrame) == "table" and typeof(promptFrame.gui) == "Instance" then
			searchRoot = promptFrame.gui.Parent or promptFrame.gui
		end
		_, noButton = _G.F.getBattleYesOrNoPromptButtons(searchRoot)
	end

	local promptOpen = false
	if type(promptFrame) == "table" and promptFrame.Visible == true then
		promptOpen = true
	elseif typeof(promptFrame) == "Instance" and _G.F.isGuiChainVisible(promptFrame) then
		promptOpen = true
	end

	return promptOpen, yesNoSignal, noButton, promptFrame
end

_G.F.fireBattleYesOrNoAnswer = function(answer, yesNoSignal, noButton)
	local clicked = false

	if yesNoSignal and type(yesNoSignal.Fire) == "function" then
		local okFire = pcall(function()
			yesNoSignal:Fire(answer and true or false)
		end)
		clicked = clicked or okFire

		if type(firesignal) == "function" then
			local okSignal, signal = pcall(function()
				return yesNoSignal
			end)

			if okSignal and signal then
				local okSignalFire = pcall(function()
					firesignal(signal, answer and true or false)
				end)
				clicked = clicked or okSignalFire
			end
		end
	end

	if noButton then
		clicked = _G.F.activateGuiButton(noButton) or clicked
		clicked = _G.F.clickGuiButtonOnce(noButton) or clicked
	end

	return clicked
end

-- Trainer battles ask "Will you switch Loomians?" when the foe sends out a new
-- Loomian. BattleGui.message skips the prompt while battle.fastForward is true,
-- but if fast-forward is off for even one frame the prompt blocks on Wait().
-- Auto-click No so trainer farming never stalls on this dialog.
_G.F.dismissTrainerSwitchPrompt = function()
	if _G.jackAutoBattle.Trainer == "Disabled" then
		return false
	end

	local battle = _G.F.getCurrentBattle()
	if type(battle) ~= "table" or battle.ended or battle.done then
		_G.trainerSwitchPromptFirstSeenAt = 0
		_G.trainerSwitchPromptLastText = nil
		_G.trainerSwitchPromptClickedInstance = nil
		return false
	end

	if battle.kind ~= "trainer" then
		return false
	end

	_G.F.setBattleFastForward(true, battle)

	local promptOpen, yesNoSignal, noButton, promptFrame = _G.F.getBattleYesOrNoLiveState()
	if not promptOpen and not promptFrame then
		_G.trainerSwitchPromptFirstSeenAt = 0
		_G.trainerSwitchPromptLastText = nil
		return false
	end

	local promptText = _G.F.getVisibleBattlePromptTextSnapshot()
	if _G.F.isCaptureNicknamePromptText(promptText) then
		return false
	end

	local now = os.clock()
	if promptText ~= _G.trainerSwitchPromptLastText or _G.trainerSwitchPromptFirstSeenAt == 0 then
		_G.trainerSwitchPromptLastText = promptText
		_G.trainerSwitchPromptFirstSeenAt = now
		return false
	end

	if now - _G.trainerSwitchPromptFirstSeenAt < 0.15 then
		return false
	end

	if _G.trainerSwitchPromptClickedInstance ~= nil
		and _G.trainerSwitchPromptClickedInstance == promptFrame
		and now - _G.trainerSwitchPromptLastClickAt < 0.8 then
		return false
	end

	if now - _G.trainerSwitchPromptLastClickAt < 0.35 then
		return false
	end

	_G.trainerSwitchPromptLastClickAt = now
	_G.trainerSwitchPromptClickedInstance = promptFrame

	return _G.F.fireBattleYesOrNoAnswer(false, yesNoSignal, noButton)
end

_G.F.startAutoTrainer = function()
	return _G.F.jackRunAutoTrainerTick()
end

_G.F.useMoveOne = function(_battle)
	return _G.F.jackRunAutoMoveTick(_G.autoEncounterEnabled and true or false)
end

return { name = "combat" }
