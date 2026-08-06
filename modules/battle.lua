-- battle.lua
-- Battle helpers: fast-forward, monster inspect, natural run.
_G.F.getCurrentBattle = function()
	if type(_G._p) ~= "table" then
		return nil
	end

	local battle = _G.F.getContainerCurrentBattle(_G.F.safeTableGet(_G._p, "Battle"))
	if battle then
		return battle
	end

	battle = _G.F.getContainerCurrentBattle(_G.F.safeTableGet(_G._p, "BattleClient"))
	if battle then
		return battle
	end

	return nil
end


-- Fast forward, rewritten to use the game's own mechanism and nothing else.
--
-- Every battle animation, statbar tween, and inter-action wait in the game is
-- gated on ONE field: battle.fastForward (checked all over BattleClientActions,
-- BattleClientSide, BattleGui). The game's own turbo-replay path does nothing
-- more than set that field. The old implementation deep-scanned battle tables
-- every tick, writing/nil-ing guessed keys and force-clearing "animating" locks
-- on live game state (scene, sides, gui...), which corrupted battles and the
-- camera. Now we only ever touch the one field the game actually reads.
_G.F.applyFastForwardFlagsToTable = function(object, enabled)
	if type(object) ~= "table" then
		return
	end

	_G.F.safeTableSet(object, "fastForward", enabled and true or false)
end

_G.F.setBattleFastForward = function(enabled, battle)
	_G.F.installBattleCameraSafetyHooks()

	battle = battle or _G.F.getCurrentBattle()

	if not battle then
		return
	end

	if enabled then
		_G.fastForwardBattles[battle] = true

		if _G.F.safeTableGet(battle, "fastForward") ~= true then
			_G.F.safeTableSet(battle, "fastForward", true)
		end
	elseif _G.fastForwardBattles[battle] then
		_G.fastForwardBattles[battle] = nil

		if not _G.F.isBattleEnded(battle) then
			_G.F.safeTableSet(battle, "fastForward", false)
		end
	end
end

_G.F.clearBattleFastForward = function()
	for battle in pairs(_G.fastForwardBattles) do
		_G.fastForwardBattles[battle] = nil

		if not _G.F.isBattleEnded(battle) then
			_G.F.safeTableSet(battle, "fastForward", false)
		end
	end
end

_G.F.callMethodsIfPresent = function(object, methodNames)
	if type(object) ~= "table" then
		return
	end

	for _, methodName in ipairs(methodNames) do
		local method = _G.F.safeTableGet(object, methodName)
		if type(method) == "function" then
			pcall(function()
				method(object)
			end)
		end
	end
end

-- Kept as a thin compatibility wrapper: many call sites pass (battle, clearLocks,
-- enabled). All the deep scanning, animator speeding and lock clearing is gone --
-- battle.fastForward is the entire mechanism.
_G.F.applyBattleAnimationFastForward = function(battle, _clearLocks, enabled)
	if type(battle) ~= "table" then
		return
	end

	if enabled == false then
		-- Force-off must work even for battles we never tracked (e.g. cleanup
		-- of leftover state from a previous script run, or pausing automation
		-- on a gleaming encounter so the player can watch it normally).
		_G.fastForwardBattles[battle] = nil

		if not _G.F.isBattleEnded(battle) then
			_G.F.safeTableSet(battle, "fastForward", false)
		end
	else
		_G.F.setBattleFastForward(true, battle)
	end
end

_G.F.clearAllBattleFastForward = function()
	_G.F.clearBattleFastForward()
end

task.defer(function()
	local battle = _G.F.getCurrentBattle()
	if battle then
		_G.F.applyBattleAnimationFastForward(battle, false, false)
	end
end)

_G.F.getBattleProgressSignature = function(battle)
	if type(battle) ~= "table" then
		return "none"
	end

	return table.concat({
		tostring(_G.F.safeTableGet(battle, "state")),
		tostring(_G.F.safeTableGet(battle, "turn")),
		tostring(_G.F.safeTableGet(battle, "request")),
		tostring(_G.F.safeTableGet(battle, "fulfillingRequest")),
		tostring(_G.F.safeTableGet(battle, "done"))
	}, "|")
end

-- "Nudging" a stuck battle is now just re-asserting battle.fastForward. Any
-- wait the game entered before the flag was set finishes on its own; forcing
-- scene/animation locks from outside only corrupted live battle state.
_G.F.nudgeFastForwardBattle = function(battle)
	if type(battle) ~= "table" or _G.F.safeTableGet(battle, "state") == "input" or _G.F.safeTableGet(battle, "done") then
		return
	end

	_G.F.setBattleFastForward(true, battle)
end

-- EventLoomian Legacy stores a Loomian's gleam tier as `shiny` (a number) and
-- mirrors it into the compact `icon` array (element 3). The PC/Party slot icons
-- are built directly from monster.icon via IconUtil.createMonsterIcon, so the
-- `icon` array is the authoritative source when the full data isn't present.
--   tier 1 = Gleaming, tier 2 = Gamma, tier >= 3 = Corrupt / special gleam.
-- Wisp color lives on `wisp` (number) / icon array element 4.
_G.F.getMonsterIconArray = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	local icon = _G.F.safeTableGet(monster, "icon")
	if type(icon) == "table" then
		return icon
	end

	for _, key in ipairs({ "summ", "summary", "data", "modelData", "sprite" }) do
		local container = _G.F.safeTableGet(monster, key)
		if type(container) == "table" then
			local nested = _G.F.safeTableGet(container, "icon")
			if type(nested) == "table" then
				return nested
			end
		end
	end

	return nil
end

_G.F.normalizeGleamTier = function(value)
	if value == true then
		return 1
	end
	if type(value) == "number" and value ~= 0 then
		return value
	end
	return nil
end

-- Instance-safe numeric index read. Some game tables carry a metatable whose
-- __index points at a Roblox Instance (e.g. Workspace.Camera), so a missing
-- numeric key like value[2] falls through and throws "2 is not a valid member
-- of Camera". Route every array read through pcall to stay resilient.
_G.F.safeArrayGet = function(value, index)
	if type(value) ~= "table" then
		return nil
	end

	if typeof and typeof(value) == "Instance" then
		return nil
	end

	local ok, result = pcall(function()
		return value[index]
	end)

	if ok then
		return result
	end

	return nil
end

-- PC box slots store { labelIndex, iconArray } where iconArray is the compact
-- { speciesId, sheetType, gleamTier, wispColor } tuple passed to Monster:getIcon.
_G.F.isMonsterIconArray = function(value)
	if type(value) ~= "table" then
		return false
	end

	local speciesId = _G.F.safeArrayGet(value, 1)
	if type(speciesId) ~= "number" then
		return false
	end

	local sheetType = _G.F.safeArrayGet(value, 2)
	if sheetType ~= nil and type(sheetType) ~= "number" and sheetType ~= true then
		return false
	end

	return true
end

_G.F.unwrapPcSlotData = function(slotData)
	if type(slotData) ~= "table" then
		return nil
	end

	local secondEntry = _G.F.safeArrayGet(slotData, 2)
	if _G.F.isMonsterIconArray(secondEntry) then
		return {
			raw = slotData,
			icon = secondEntry,
			labelIndex = _G.F.safeArrayGet(slotData, 1),
			isPcSlot = true,
		}
	end

	if _G.F.isMonsterIconArray(slotData) then
		return {
			raw = slotData,
			icon = slotData,
			isPcSlot = false,
		}
	end

	local icon = _G.F.getMonsterIconArray(slotData)
	if icon then
		return {
			raw = slotData,
			icon = icon,
			isPcSlot = false,
		}
	end

	return {
		raw = slotData,
		icon = nil,
		isPcSlot = false,
	}
end

_G.F.getSpeciesNameFromId = function(speciesId)
	speciesId = tonumber(speciesId)
	if not speciesId then
		return nil
	end

	_G.F.speciesNameCache = _G.F.speciesNameCache or {}
	if _G.F.speciesNameCache[speciesId] then
		return _G.F.speciesNameCache[speciesId]
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	if type(_G._p) == "table" then
		local constants = _G.F.safeTableGet(_G._p, "Constants")
		if type(constants) == "table" then
			for _, key in ipairs({ "MONSTERS", "monsters", "Loomians", "loomians", "DEX", "dex" }) do
				local monsterTable = _G.F.safeTableGet(constants, key)
				if type(monsterTable) == "table" then
					local entry = monsterTable[speciesId]
					if entry ~= nil then
						local name = type(entry) == "table" and (entry.name or entry.n or entry.species) or entry
						if name ~= nil and tostring(name) ~= "" then
							_G.F.speciesNameCache[speciesId] = tostring(name)
							return _G.F.speciesNameCache[speciesId]
						end
					end
				end
			end
		end

		local monsterModule = _G.F.safeTableGet(_G._p, "Monster")
		if type(monsterModule) == "table" then
			for _, methodName in ipairs({ "getName", "getNameFromId", "idToName", "getDexName" }) do
				local method = monsterModule[methodName]
				if type(method) == "function" then
					local ok, name = pcall(method, monsterModule, speciesId)
					if ok and name ~= nil and tostring(name) ~= "" then
						_G.F.speciesNameCache[speciesId] = tostring(name)
						return _G.F.speciesNameCache[speciesId]
					end
				end
			end
		end
	end

	return nil
end

_G.F.getMonsterGleamTier = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	if _G.F.isMonsterIconArray(monster) then
		return _G.F.normalizeGleamTier(_G.F.safeArrayGet(monster, 3))
	end

	local unwrapped = _G.F.unwrapPcSlotData(monster)
	if unwrapped and unwrapped.icon then
		local tier = _G.F.normalizeGleamTier(_G.F.safeArrayGet(unwrapped.icon, 3))
		if tier then
			return tier
		end
	end

	for _, key in ipairs({ "shiny", "gleam", "gl", "gleaming" }) do
		local tier = _G.F.normalizeGleamTier(_G.F.safeTableGet(monster, key))
		if tier then
			return tier
		end
	end

	for _, containerKey in ipairs({ "summ", "summary", "data", "modelData", "sprite" }) do
		local container = _G.F.safeTableGet(monster, containerKey)
		if type(container) == "table" then
			for _, key in ipairs({ "shiny", "gleam", "gl", "gleaming" }) do
				local tier = _G.F.normalizeGleamTier(_G.F.safeTableGet(container, key))
				if tier then
					return tier
				end
			end

			local nestedSprite = _G.F.safeTableGet(container, "modelData")
			if type(nestedSprite) == "table" then
				local tier = _G.F.normalizeGleamTier(_G.F.safeTableGet(nestedSprite, "gleam"))
				if tier then
					return tier
				end
			end
		end
	end

	local icon = _G.F.getMonsterIconArray(monster)
	if type(icon) == "table" then
		local tier = _G.F.normalizeGleamTier(_G.F.safeArrayGet(icon, 3))
		if tier then
			return tier
		end
	end

	return nil
end

_G.F.getMonsterGleamValue = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	local tier = _G.F.getMonsterGleamTier(monster)
	if tier then
		return tier
	end

	local shiny = _G.F.safeTableGet(monster, "shiny")
	if _G.isActiveFlag(shiny) then
		return shiny
	end

	local gamma = _G.F.safeTableGet(monster, "gamma")
	if _G.isActiveFlag(gamma) then
		return gamma
	end

	local isGamma = _G.F.safeTableGet(monster, "isGamma")
	if _G.isActiveFlag(isGamma) then
		return isGamma
	end

	local gleam = _G.F.safeTableGet(monster, "gleam")
	if _G.isActiveFlag(gleam) then
		return gleam
	end

	local gleaming = _G.F.safeTableGet(monster, "gleaming")
	if _G.isActiveFlag(gleaming) then
		return gleaming
	end

	local gl = _G.F.safeTableGet(monster, "gl")
	if _G.isActiveFlag(gl) then
		return gl
	end

	local summary = _G.F.safeTableGet(monster, "summ")
	if type(summary) == "table" then
		for _, key in ipairs({ "gl", "gleam", "gleaming", "gamma", "shiny" }) do
			local summaryValue = _G.F.safeTableGet(summary, key)
			if _G.isActiveFlag(summaryValue) then
				return summaryValue
			end
		end
	end

	local modelData = _G.F.safeTableGet(monster, "modelData")
	if type(modelData) == "table" then
		local modelGleam = _G.F.safeTableGet(modelData, "gleam")
		if _G.isActiveFlag(modelGleam) then
			return modelGleam
		end

		local modelGamma = _G.F.safeTableGet(modelData, "gamma")
		if _G.isActiveFlag(modelGamma) then
			return modelGamma
		end
	end

	-- Some flags only land on the sprite's model data (wisp detection
	-- below relies on the same spot); check it for gleam too.
	local sprite = _G.F.safeTableGet(monster, "sprite")
	local spriteModelData = type(sprite) == "table" and _G.F.safeTableGet(sprite, "modelData") or nil
	if type(spriteModelData) == "table" then
		for _, key in ipairs({ "gleam", "gleaming", "gl", "gamma", "shiny" }) do
			local spriteValue = _G.F.safeTableGet(spriteModelData, key)
			if _G.isActiveFlag(spriteValue) then
				return spriteValue
			end
		end
	end

	return nil
end

_G.F.getMonsterWispValue = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	if _G.F.isMonsterIconArray(monster) then
		return _G.F.normalizeGleamTier(_G.F.safeArrayGet(monster, 4))
	end

	local unwrapped = _G.F.unwrapPcSlotData(monster)
	local unwrappedWisp = unwrapped and unwrapped.icon and _G.F.safeArrayGet(unwrapped.icon, 4) or nil
	if unwrappedWisp ~= nil then
		local wisp = _G.F.normalizeGleamTier(unwrappedWisp)
		if wisp then
			return wisp
		end
	end

	local wisp = _G.F.safeTableGet(monster, "wisp")
	if _G.isActiveFlag(wisp) then
		return wisp
	end

	local modelData = _G.F.safeTableGet(monster, "modelData")
	local modelWisp = type(modelData) == "table" and _G.F.safeTableGet(modelData, "wisp") or nil
	if _G.isActiveFlag(modelWisp) then
		return modelWisp
	end

	local sprite = _G.F.safeTableGet(monster, "sprite")
	local spriteModelData = type(sprite) == "table" and _G.F.safeTableGet(sprite, "modelData") or nil
	local spriteWisp = type(spriteModelData) == "table" and _G.F.safeTableGet(spriteModelData, "wisp") or nil
	if _G.isActiveFlag(spriteWisp) then
		return spriteWisp
	end

	local icon = _G.F.getMonsterIconArray(monster)
	local iconWisp = type(icon) == "table" and _G.F.safeArrayGet(icon, 4) or nil
	if _G.isActiveFlag(iconWisp) then
		return iconWisp
	end

	return nil
end
_G.F.getMonsterFormeValue = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	local forme = _G.F.safeTableGet(monster, "Forme")
	if _G.F.isMeaningfulFormeValue(forme) then
		return forme
	end

	forme = _G.F.safeTableGet(monster, "forme")
	if _G.F.isMeaningfulFormeValue(forme) then
		return forme
	end

	local modelData = _G.F.safeTableGet(monster, "modelData")
	local species = _G.F.safeTableGet(monster, "species")
	if type(modelData) == "table" then
		local modelForme = _G.F.safeTableGet(modelData, "Forme")
		if _G.F.isMeaningfulFormeValue(modelForme) then
			return modelForme
		end

		modelForme = _G.F.safeTableGet(modelData, "forme")
		if _G.F.isMeaningfulFormeValue(modelForme) then
			return modelForme
		end

		local modelName = _G.F.safeTableGet(modelData, "name")
		if _G.F.isMeaningfulFormeValue(modelName) and species and _G.F.normalizeFormeKey(modelName) ~= _G.F.normalizeFormeKey(species) then
			return modelName
		end
	end

	local sprite = _G.F.safeTableGet(monster, "sprite")
	local spriteModelData = type(sprite) == "table" and _G.F.safeTableGet(sprite, "modelData") or nil
	if type(spriteModelData) == "table" then
		local spriteForme = _G.F.safeTableGet(spriteModelData, "Forme")
		if _G.F.isMeaningfulFormeValue(spriteForme) then
			return spriteForme
		end

		spriteForme = _G.F.safeTableGet(spriteModelData, "forme")
		if _G.F.isMeaningfulFormeValue(spriteForme) then
			return spriteForme
		end

		local spriteName = _G.F.safeTableGet(spriteModelData, "name")
		if _G.F.isMeaningfulFormeValue(spriteName) and species and _G.F.normalizeFormeKey(spriteName) ~= _G.F.normalizeFormeKey(species) then
			return spriteName
		end
	end

	return nil
end

_G.F.getMonsterTrackedFormeValue = function(monster)
	local formeValue = _G.F.getMonsterFormeValue(monster)
	if not _G.F.isMeaningfulFormeValue(formeValue) then
		return nil
	end

	if _G.F.isExcludedForme(formeValue) then
		return nil
	end

	return formeValue
end

_G.F.getMonsterSpecialValue = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	local gleamValue = _G.F.getMonsterGleamValue(monster)
	if gleamValue then
		return "Gleaming/Gamma", gleamValue
	end

	local wispValue = _G.F.getMonsterWispValue(monster)
	if wispValue then
		return "Wisp", wispValue
	end

	local formeValue = _G.F.getMonsterTrackedFormeValue(monster)
	if formeValue ~= nil then
		return "Forme", formeValue
	end

	return nil
end

_G.F.getBattleFoeMonster = function(battle)
	if type(battle) ~= "table" then
		return nil
	end

	return battle.p2 and battle.p2.monsters and battle.p2.monsters[1]
end

_G.F.normalizeLoomianSearchName = function(value)
	return string.lower(string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
end

_G.F.getMonsterDisplayName = function(monster)
	if type(monster) ~= "table" then
		return ""
	end

	return tostring(monster.name or monster.species or monster.nickname or "")
end

_G.F.getEncounterFoeSpeciesName = function(monster)
	if type(monster) ~= "table" then
		return ""
	end

	local summary = _G.F.safeTableGet(monster, "summ")
	if type(summary) == "table" then
		local speciesName = _G.F.safeTableGet(summary, "name")
		if type(speciesName) == "string" and speciesName ~= "" then
			return speciesName
		end
	end

	return tostring(monster.name or monster.species or "")
end

_G.F.monsterMatchesSearchTarget = function(monster, searchTarget)
	local wanted = _G.F.normalizeLoomianSearchName(searchTarget)
	if wanted == "" then
		return true
	end

	local name = _G.F.normalizeLoomianSearchName(_G.F.getEncounterFoeSpeciesName(monster))
	if name == "" then
		return false
	end

	return name == wanted or string.find(name, wanted, 1, true) ~= nil
end

_G.F.roamingLegendaryStopLookup = nil

_G.F.rebuildRoamingLegendaryStopLookup = function()
	local lookup = {}

	for name, enabled in pairs(_G.ROAMING_LEGENDARY_STOPS or {}) do
		if enabled then
			local key = _G.F.normalizeLoomianSearchName(name)
			if key ~= "" then
				lookup[key] = tostring(name)
			end
		end
	end

	_G.F.roamingLegendaryStopLookup = lookup
end

_G.F.getRoamingLegendaryMatchName = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	local lookup = _G.F.roamingLegendaryStopLookup
	if not lookup then
		_G.F.rebuildRoamingLegendaryStopLookup()
		lookup = _G.F.roamingLegendaryStopLookup
	end

	local name = _G.F.normalizeLoomianSearchName(_G.F.getEncounterFoeSpeciesName(monster))
	if name == "" then
		return nil
	end

	if lookup[name] then
		return lookup[name]
	end

	for key, displayName in pairs(lookup) do
		if string.find(name, key, 1, true) or string.find(key, name, 1, true) then
			return displayName
		end
	end

	return nil
end

_G.F.isMatchingRoamingLegendaryFoe = function(battle)
	if not _G.F.hasWildFoeLoaded(battle) then
		return false
	end

	return _G.F.getRoamingLegendaryMatchName(_G.F.getBattleFoeMonster(battle)) ~= nil
end

_G.F.handleRoamingLegendaryFound = function(battle)
	if type(battle) ~= "table" then
		return
	end

	local foe = _G.F.getBattleFoeMonster(battle)
	local matchName = _G.F.getRoamingLegendaryMatchName(foe)
	if not matchName then
		return
	end

	local displayName = _G.F.getEncounterFoeSpeciesName(foe)
	if displayName == "" then
		displayName = matchName
	end

	_G.F.pauseAutoEncounterForBattle(battle, displayName, "Roaming Legendary", "Roaming Legendary Found")
end

_G.F.rebuildRoamingLegendaryStopLookup()
_G.F.getMonsterGammaValue = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	if _G.F.getMonsterGleamTier(monster) == 2 then
		return 2
	end

	local gamma = _G.F.safeTableGet(monster, "gamma")
	if _G.isActiveFlag(gamma) then
		return gamma
	end

	local isGamma = _G.F.safeTableGet(monster, "isGamma")
	if _G.isActiveFlag(isGamma) then
		return isGamma
	end

	local summary = _G.F.safeTableGet(monster, "summ")
	if type(summary) == "table" then
		local summaryGamma = _G.F.safeTableGet(summary, "gamma")
		if _G.isActiveFlag(summaryGamma) then
			return summaryGamma
		end
	end

	local modelData = _G.F.safeTableGet(monster, "modelData")
	if type(modelData) == "table" then
		local modelGamma = _G.F.safeTableGet(modelData, "gamma")
		if _G.isActiveFlag(modelGamma) then
			return modelGamma
		end
	end

	return nil
end

_G.F.getMonsterGleamingOnlyValue = function(monster)
	if type(monster) ~= "table" or _G.F.getMonsterGammaValue(monster) then
		return nil
	end

	local tier = _G.F.getMonsterGleamTier(monster)
	if tier == 1 then
		return 1
	end

	local shiny = _G.F.safeTableGet(monster, "shiny")
	if _G.isActiveFlag(shiny) then
		return shiny
	end

	local gleam = _G.F.safeTableGet(monster, "gleam")
	if _G.isActiveFlag(gleam) then
		return gleam
	end

	local gleaming = _G.F.safeTableGet(monster, "gleaming")
	if _G.isActiveFlag(gleaming) then
		return gleaming
	end

	local gl = _G.F.safeTableGet(monster, "gl")
	if _G.isActiveFlag(gl) then
		return gl
	end

	local summary = _G.F.safeTableGet(monster, "summ")
	if type(summary) == "table" then
		for _, key in ipairs({ "gl", "gleam", "gleaming", "shiny" }) do
			local summaryValue = _G.F.safeTableGet(summary, key)
			if _G.isActiveFlag(summaryValue) then
				return summaryValue
			end
		end
	end

	local modelData = _G.F.safeTableGet(monster, "modelData")
	if type(modelData) == "table" then
		local modelGleam = _G.F.safeTableGet(modelData, "gleam")
		if _G.isActiveFlag(modelGleam) then
			return modelGleam
		end
	end

	return nil
end

_G.F.getWildSpecialFoeForStop = function(battle)
	local foe = _G.F.getBattleFoeMonster(battle)
	if type(foe) ~= "table" then
		return nil
	end

	if _G.stopOnWisp then
		local wispValue = _G.F.getMonsterWispValue(foe)
		if _G.isActiveFlag(wispValue) then
			return foe, wispValue, "Wisp"
		end
	end

	if _G.stopOnGamma then
		local gammaValue = _G.F.getMonsterGammaValue(foe)
		if _G.isActiveFlag(gammaValue) then
			return foe, gammaValue, "Gamma"
		end
	end

	if _G.stopOnGleaming then
		local gleamValue = _G.F.getMonsterGleamingOnlyValue(foe)
		if _G.isActiveFlag(gleamValue) then
			return foe, gleamValue, "Gleaming"
		end
	end

	return nil
end


_G.F.getStaticHuntSpecialFoe = function(battle)
	local foe = battle and battle.p2 and battle.p2.monsters and battle.p2.monsters[1]
	if type(foe) ~= "table" then
		return nil
	end

	local gleamValue = _G.F.getMonsterGleamValue(foe)
	if _G.isActiveFlag(gleamValue) then
		return foe, gleamValue, "Gleaming/Gamma"
	end

	local wispValue = _G.F.getMonsterWispValue(foe)
	if _G.isActiveFlag(wispValue) then
		return foe, wispValue, "Wisp"
	end

	return nil
end

_G.F.hasWildFoeLoaded = function(battle)
	return type(battle) == "table"
		and type(battle.p2) == "table"
		and type(battle.p2.monsters) == "table"
		and type(battle.p2.monsters[1]) == "table"
end

_G.F.isStaticBattleReadyToEnd = function(battle)
	if type(battle) ~= "table" or battle.ended then
		return false
	end

	if battle.setupComplete ~= true then
		return false
	end

	return _G.F.hasWildFoeLoaded(battle)
end

_G.F.advanceSoftResetNpcChat = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local chat = type(_G._p) == "table" and _G._p.NPCChat or nil
	if type(chat) ~= "table" then
		return false
	end

	local chatting = false
	pcall(function()
		if type(chat.isChatting) == "function" then
			chatting = chat:isChatting()
		end
	end)

	if not chatting then
		return false
	end

	pcall(function()
		chat.fastForward = true
		chat.skipping = true
		chat.TextSpeedMultiplier = 100
	end)

	local advanced = false

	pcall(function()
		if type(chat.isAwaitingManualAdvance) == "function" and chat:isAwaitingManualAdvance()
			and type(chat.manualAdvance) == "function" then
			chat:manualAdvance()
			advanced = true
		end
	end)

	if not advanced then
		pcall(function()
			if type(chat.manualAdvance) == "function" then
				chat:manualAdvance()
			end
		end)

		local utilities = type(_G._p) == "table" and _G._p.Utilities or nil
		local frontGui = utilities and utilities.frontGui
		if frontGui then
			for _, name in ipairs({ "ChatBox", "ChatArrowPointer" }) do
				local item = frontGui:FindFirstChild(name, true)
				if item and _G.F.isGuiChainVisible(item) then
					if _G.F.activateGuiButton(item) or _G.F.clickGuiButtonOnce(item) then
						advanced = true
						break
					end

					local okVim, vim = pcall(function()
						return game:GetService("VirtualInputManager")
					end)

					if okVim and vim and item:IsA("GuiObject") then
						pcall(function()
							local center = item.AbsolutePosition + (item.AbsoluteSize / 2)
							vim:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
							task.wait(0.025)
							vim:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
						end)
						advanced = true
						break
					end
				end
			end
		end

		if not advanced then
			local okVim, vim = pcall(function()
				return game:GetService("VirtualInputManager")
			end)

			if okVim and vim then
				pcall(function()
					local camera = workspace.CurrentCamera
					local viewport = camera and camera.ViewportSize or Vector2.new(1280, 720)
					vim:SendMouseButtonEvent(viewport.X * 0.5, viewport.Y * 0.72, 0, true, game, 0)
					task.wait(0.025)
					vim:SendMouseButtonEvent(viewport.X * 0.5, viewport.Y * 0.72, 0, false, game, 0)
				end)
				advanced = true
			end
		end
	end

	return advanced
end

_G.F.clickGuiButtonOnce = function(button)
	if not button then
		return false
	end

	if type(firesignal) == "function" then
		local okSignal, signal = pcall(function()
			return button.Activated
		end)

		if okSignal and signal then
			local okFire = pcall(function()
				firesignal(signal)
			end)

			if okFire then
				return true
			end
		end
	end

	local okActivate = pcall(function()
		button:Activate()
	end)

	return okActivate
end

_G.F.activateGuiButton = function(button)
	if not button then
		return false
	end

	local clicked = false

	if type(firesignal) == "function" then
		for _, signalName in ipairs({ "Activated", "MouseButton1Click", "MouseButton1Up" }) do
			local okSignal, signal = pcall(function()
				return button[signalName]
			end)

			if okSignal and signal then
				local okFire = pcall(function()
					firesignal(signal)
				end)

				clicked = clicked or okFire
			end
		end
	end

	local okActivate = pcall(function()
		button:Activate()
	end)
	clicked = clicked or okActivate

	local okVim, vim = pcall(function()
		return game:GetService("VirtualInputManager")
	end)

	if okVim and vim then
		local okMouse = pcall(function()
			local center = button.AbsolutePosition + (button.AbsoluteSize / 2)
			vim:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
			task.wait(0.025)
			vim:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
		end)

		clicked = clicked or okMouse
	end

	return clicked
end

_G.F.canUseRealMouse = function()
	-- Real clicks land wherever the OS cursor is; never move/click the
	-- user's mouse while the game window isn't focused.
	if _G.windowFocused == false then
		return false
	end

	return type(mousemoveabs) == "function"
		and (type(mouse1click) == "function"
			or (type(mouse1press) == "function" and type(mouse1release) == "function"))
end

_G.F.realMouseClickGuiObject = function(guiObject)
	if typeof(guiObject) ~= "Instance" or not guiObject:IsA("GuiObject") then
		return false
	end

	if not _G.F.canUseRealMouse() then
		return false
	end

	local ok = pcall(function()
		local inset = game:GetService("GuiService"):GetGuiInset()
		local center = guiObject.AbsolutePosition + (guiObject.AbsoluteSize / 2)
		local x = center.X + inset.X
		local y = center.Y + inset.Y

		local camera = workspace.CurrentCamera
		if camera then
			local viewport = camera.ViewportSize
			if x < 0 or y < 0 or x > viewport.X or y > viewport.Y then
				error("click target is off screen")
			end
		end

		local restoreTo = nil
		pcall(function()
			restoreTo = game:GetService("UserInputService"):GetMouseLocation()
		end)

		mousemoveabs(x, y)
		task.wait(0.03)

		if type(mouse1click) == "function" then
			mouse1click()
		else
			mouse1press()
			task.wait(0.03)
			mouse1release()
		end

		if restoreTo then
			task.wait(0.05)
			mousemoveabs(restoreTo.X, restoreTo.Y)
		end
	end)

	return ok
end

_G.F.isGuiChainVisible = function(item)
	local current = item

	while current do
		if current:IsA("GuiObject") and current.Visible == false then
			return false
		end

		if current:IsA("ScreenGui") and current.Enabled == false then
			return false
		end

		current = current.Parent
	end

	return true
end

_G.F.getBattleGuiModule = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local battleGui = type(_G._p) == "table" and _G._p.BattleGui or nil
	if type(battleGui) ~= "table" then
		return nil
	end

	_G.F.installBattleGuiSafetyHooks(battleGui)
	return battleGui
end

_G.F.installBattleGuiSafetyHooks = function(battleGui)
	if type(battleGui) ~= "table" then
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end
		battleGui = type(_G._p) == "table" and _G._p.BattleGui or nil
	end
	if type(battleGui) ~= "table" or battleGui.__llsploitMainChoicesGuard then
		return
	end

	local originalMainChoices = _G.F.safeTableGet(battleGui, "mainChoices")
	if type(originalMainChoices) == "function" then
		_G.F.safeTableSet(battleGui, "mainChoices", function(self, ...)
			if type(_G._p) ~= "table" then
				_G._p = _G.F.findP()
			end

			local linkedBattle = type(_G._p) == "table" and _G._p.Battle and _G._p.Battle.currentBattle or nil
			if type(linkedBattle) ~= "table" or linkedBattle.battleId == nil or linkedBattle.ended then
				return
			end

			return originalMainChoices(self, ...)
		end)
	end

	battleGui.__llsploitMainChoicesGuard = true
end

task.defer(function()
	_G.F.installBattleGuiSafetyHooks()
end)

task.defer(function()
	_G.F.installBattleCameraSafetyHooks()
end)

_G.F.findBattleRunButtonInGui = function()
	local okPlayer, player = pcall(function()
		return game:GetService("Players").LocalPlayer
	end)

	if not okPlayer or not player then
		return nil
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	-- This gets polled every tick for the whole battle; once the Run item is
	-- known and visible, answer from it directly instead of sweeping
	-- PlayerGui again. A hidden cached item usually means the menu is just
	-- closed, but the game may also have swapped in a different Run item,
	-- so let the rate-limited rescan below keep running rather than pinning
	-- to this instance forever.
	local cachedItem = _G._battleRunItemCache
	if typeof(cachedItem) == "Instance" and cachedItem:IsDescendantOf(playerGui) then
		if _G.F.isGuiChainVisible(cachedItem) then
			local button = cachedItem:FindFirstChild("Button")
			if button and button:IsA("GuiButton") then
				return button
			end
		end
	else
		_G._battleRunItemCache = nil
	end

	local now = os.clock()
	if _G._battleRunScanAt and now - _G._battleRunScanAt < 0.25 then
		return nil
	end
	_G._battleRunScanAt = now

	local ok, descendants = pcall(function()
		return playerGui:GetDescendants()
	end)

	if not ok then
		return nil
	end

	for _, item in ipairs(descendants) do
		if item.Name == "Run" and item:IsA("GuiObject") and _G.F.isGuiChainVisible(item) then
			local button = item:FindFirstChild("Button")
			if button and button:IsA("GuiButton") then
				_G._battleRunItemCache = item
				return button
			end
		end
	end

	return nil
end

_G.F.getBattleRunButton = function()
	local battleGui = _G.F.getBattleGuiModule()
	if battleGui then
		local buttonData = _G.F.safeTableGet(battleGui, "buttonData")
		local runEntry = type(buttonData) == "table" and buttonData.run or nil
		local runUi = type(runEntry) == "table" and runEntry.ui or nil
		if runUi then
			local button = runUi:FindFirstChild("Button")
			if button then
				return button
			end
		end

		local main = _G.F.safeTableGet(battleGui, "main")
		local mainRun = type(main) == "table" and main.run or nil
		if mainRun then
			local button = mainRun:FindFirstChild("Button")
			if button then
				return button
			end
		end
	end

	return _G.F.findBattleRunButtonInGui()
end

_G.F.isBattleMainMenuOpen = function()
	local battleGui = _G.F.getBattleGuiModule()
	if not battleGui then
		return false
	end

	local contexts = _G.F.safeTableGet(battleGui, "currentMenuContexts")
	if type(contexts) == "table" then
		for _, contextName in ipairs(contexts) do
			if contextName == "main"
				or contextName == "mainFirst"
				or contextName == "mainOther"
				or contextName == "mainBagEnabled" then
				return true
			end
		end
	end

	local buttonData = _G.F.safeTableGet(battleGui, "buttonData")
	local runEntry = type(buttonData) == "table" and buttonData.run or nil
	local runUi = type(runEntry) == "table" and runEntry.ui or nil
	if runUi and runUi.Visible == true and _G.F.isGuiChainVisible(runUi) then
		return true
	end

	local main = _G.F.safeTableGet(battleGui, "main")
	local container = type(main) == "table" and main.container or nil
	if container and container.Visible == true and _G.F.isGuiChainVisible(container) then
		return true
	end

	return _G.F.findBattleRunButtonInGui() ~= nil
end

_G.battleRunEarliestAt = {}

_G.F.getBattleRunEarliestAt = function(battle)
	local battleId = battle and battle.battleId
	if not battleId then
		return os.clock()
	end

	if not _G.battleRunEarliestAt[battleId] then
		_G.battleRunEarliestAt[battleId] = os.clock() + 0.65
	end

	return _G.battleRunEarliestAt[battleId]
end

_G.F.clearBattleRunTiming = function(battle)
	local battleId = battle and battle.battleId
	if battleId then
		_G.battleRunEarliestAt[battleId] = nil
	end
end

_G.F.isBattleRunMenuReady = function(battle, allowTimedFallback)
	if not _G.F.isStaticBattleReadyToEnd(battle) then
		return false
	end

	local earliestAt = _G.F.getBattleRunEarliestAt(battle)
	if os.clock() < earliestAt then
		return false
	end

	-- Never try to run before the battle is awaiting input AND the
	-- BattleGui has taken the battle over. setupComplete flips before the
	-- camera pan / GUI load, and the previous battle's menu state can still
	-- read as "open" during the intro ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â running that early corrupts the
	-- battle client. (For fishing this also makes takeOver's mainChoices
	-- run before tryRun ends the battle.)
	if battle.state ~= "input" or not _G.F.isBattleLinkedToBattleGui(battle) then
		return false
	end

	if _G.F.isBattleMainMenuOpen() then
		return true
	end

	if allowTimedFallback then
		return os.clock() >= earliestAt + 0.6
	end

	return false
end

_G.F.finishNaturalBattleRun = function(battle, escaped, masteryUpdate, queueActions)
	if escaped == "partial" or escaped == false or escaped == nil then
		return false
	end

	if type(masteryUpdate) == "table" then
		battle.masteryProgressUpdate = masteryUpdate
	end

	if type(queueActions) == "table" then
		battle.actionQueue = battle.actionQueue or {}
		for _, action in ipairs(queueActions) do
			table.insert(battle.actionQueue, action)
		end
	end

	pcall(function()
		if type(_G._p) == "table" and type(_G._p.BattleCamera) == "table" and type(_G._p.BattleCamera.stopIdleCamera) == "function" then
			_G._p.BattleCamera.stopIdleCamera(battle)
		end
	end)

	pcall(function()
		battle.ended = true
		if battle.BattleEnded then
			battle.BattleEnded:Fire()
		end
	end)

	return true
end

_G.F.isBattleLinkedToBattleGui = function(battle)
	if type(battle) ~= "table" or battle.battleId == nil or type(_G._p) ~= "table" then
		return false
	end

	local linkedBattle = _G._p.Battle and _G._p.Battle.currentBattle
	if type(linkedBattle) ~= "table" or linkedBattle.battleId == nil then
		linkedBattle = _G._p.BattleClient and _G._p.BattleClient.currentBattle
	end

	return linkedBattle == battle
end

_G.F.naturalRunFromBattle = function(battle, allowTimedFallback)
	if type(battle) ~= "table" or battle.CanRun == false or battle.ended then
		return false
	end

	if not _G.F.isBattleRunMenuReady(battle, allowTimedFallback) then
		return false
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local isFishingBattle = battle.fshPct ~= nil

	-- Fishing: skip BattleGui run clicks; they call mainChoices before Battle.currentBattle is set.
	if not isFishingBattle then
		local canClickBattleGui = _G.F.isBattleLinkedToBattleGui(battle)
		local runButton = _G.F.getBattleRunButton()

		-- Prefer clicking Run with the real mouse; fall back to the
		-- module/virtual paths only when that isn't possible.
		if canClickBattleGui and runButton and _G.F.realMouseClickGuiObject(runButton) then
			task.wait(0.2)

			if battle.ended then
				return true
			end
		end

		local battleGui = _G.F.getBattleGuiModule()
		local mainButtonClicked = battleGui and _G.F.safeTableGet(battleGui, "mainButtonClicked") or nil

		if canClickBattleGui and type(mainButtonClicked) == "function" then
			pcall(function()
				mainButtonClicked(battleGui, {}, 4)
			end)

			if battle.ended then
				return true
			end
		end

		if runButton and canClickBattleGui then
			_G.F.clickGuiButtonOnce(runButton)

			if battle.ended then
				return true
			end

			_G.F.activateGuiButton(runButton)

			if battle.ended then
				return true
			end
		end
	end

	local network = type(_G._p) == "table" and _G._p.Network or nil
	local battleId = battle.battleId
	if type(network) ~= "table" or type(network.get) ~= "function" or not battleId then
		return false
	end

	local ok, escaped, masteryUpdate, queueActions = pcall(function()
		return network:get("BattleFunction", battleId, "tryRun")
	end)

	if not ok then
		return false
	end

	return _G.F.finishNaturalBattleRun(battle, escaped, masteryUpdate, queueActions)
end
_G.naturalCatchFromBattle = nil
_G.normalizeCaptureDiscId = nil
_G.isCatchUiActive = nil
_G.resetCatchUiTiming = nil

do
	local CAPTURE_DISC_ALIASES = {
		capture = "capturedisc",
		basic = "basicdisc",
		advanced = "advanceddisc",
		expert = "expertdisc",
		hyper = "hyperdisc",
		ace = "acedisc",
		golden = "goldendisc",
	}

	local catchBagOpenedAt = 0
	local catchDiscSelectedAt = 0
	local catchOpenedBagForRequest = false
	local BAG_ITEMS_READY_DELAY = 0.55
	local DISC_DETAIL_READY_DELAY = 0.4

	local function normalizeCaptureDiscIdImpl(text)
		local trimmed = string.lower(string.gsub(tostring(text or ""), "^%s*(.-)%s*$", "%1"))
		if trimmed == "" then
			return nil
		end

		local compact = string.gsub(trimmed, "[^a-z0-9]", "")
		if compact == "" then
			return nil
		end

		if CAPTURE_DISC_ALIASES[compact] then
			return CAPTURE_DISC_ALIASES[compact]
		end

		if string.find(compact, "disc", 1, true) then
			local withoutCapture = string.gsub(compact, "capture", "")
			if withoutCapture ~= "" and string.find(withoutCapture, "disc", 1, true) then
				return withoutCapture
			end

			return compact
		end

		return compact .. "disc"
	end

	_G.normalizeCaptureDiscId = normalizeCaptureDiscIdImpl

	local function compactDiscSearchText(text)
		return string.gsub(string.lower(tostring(text or "")), "[^a-z0-9]", "")
	end

	local function discItemMatchesSearch(item, discId, discLabel)
		if type(item) ~= "table" then
			return false
		end

		local targetId = normalizeCaptureDiscIdImpl(discLabel) or normalizeCaptureDiscIdImpl(discId) or compactDiscSearchText(discId)
		if targetId == "" then
			return false
		end

		local itemId = compactDiscSearchText(item.id)
		if itemId == targetId or string.find(itemId, targetId, 1, true) or string.find(targetId, itemId, 1, true) then
			return true
		end

		local itemName = compactDiscSearchText(item.name)
		if itemName == targetId or string.find(itemName, targetId, 1, true) or string.find(targetId, itemName, 1, true) then
			return true
		end

		return false
	end

	local function getBattleBagModule()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local menu = type(_G._p) == "table" and _G._p.Menu or nil
		return menu and menu.bag or nil
	end

	local function getBattleBagButton()
		local battleGui = _G.F.getBattleGuiModule()
		if battleGui then
			local buttonData = _G.F.safeTableGet(battleGui, "buttonData")
			local bagEntry = type(buttonData) == "table" and buttonData.bag or nil
			local bagUi = type(bagEntry) == "table" and bagEntry.ui or nil
			if bagUi then
				local button = bagUi:FindFirstChild("Button")
				if button and _G.F.isGuiChainVisible(bagUi) then
					return button
				end
			end

			local main = _G.F.safeTableGet(battleGui, "main")
			local mainBag = type(main) == "table" and main.bag or nil
			if mainBag then
				local button = mainBag:FindFirstChild("Button")
				if button and _G.F.isGuiChainVisible(mainBag) then
					return button
				end
			end
		end

		local okPlayer, player = pcall(function()
			return game:GetService("Players").LocalPlayer
		end)

		if not okPlayer or not player then
			return nil
		end

		local playerGui = player:FindFirstChildOfClass("PlayerGui")
		if not playerGui then
			return nil
		end

		local ok, descendants = pcall(function()
			return playerGui:GetDescendants()
		end)

		if not ok then
			return nil
		end

		for _, item in ipairs(descendants) do
			if item:IsA("GuiObject") and _G.F.isGuiChainVisible(item) and (item.Name == "Items" or item.Name == "Bag") then
				local button = item:FindFirstChild("Button")
				if button and button:IsA("GuiButton") then
					return button
				end
			end
		end

		return nil
	end

	local function isBagOpenInBattle()
		local bag = getBattleBagModule()
		if type(bag) ~= "table" or bag.inBattle ~= true then
			return false
		end

		local battleContainer = bag.battleContainer
		return battleContainer and battleContainer.Visible == true and _G.F.isGuiChainVisible(battleContainer)
	end

	local function isBagItemDetailOpen()
		local bag = getBattleBagModule()
		if type(bag) ~= "table" then
			return false
		end

		local details = bag.battleDetailsContainer
		return details and details.Visible == true and _G.F.isGuiChainVisible(details)
	end

	local function findBattleBagDiscItem(discId, discLabel)
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local network = type(_G._p) == "table" and _G._p.Network or nil
		if type(network) == "table" and type(network.get) == "function" then
			local ok, bagData = pcall(function()
				return network:get("PDS", "getBattleBag")
			end)

			if ok and type(bagData) == "table" then
				for _, itemList in ipairs(bagData) do
					if type(itemList) == "table" then
						for _, item in ipairs(itemList) do
							if discItemMatchesSearch(item, discId, discLabel) then
								return item
							end
						end
					end
				end
			end
		end

		return nil
	end

	local function getGuiItemDisplayName(guiButton)
		if not guiButton then
			return nil
		end

		local ok, descendants = pcall(function()
			return guiButton:GetDescendants()
		end)

		if not ok then
			return nil
		end

		for _, item in ipairs(descendants) do
			if item:IsA("TextLabel") then
				local okText, text = pcall(function()
					return item.Text
				end)

				if okText and type(text) == "string" and text ~= "" and not string.find(text, "^x%d+$") then
					return text
				end
			end
		end

		return nil
	end

	local function findBagDiscButton(discId, discLabel)
		local bag = getBattleBagModule()
		if type(bag) ~= "table" or not bag.battleContainer then
			return nil
		end

		local discContainer = bag.battleContainer:FindFirstChild("DiscContainer")
		local content = discContainer and discContainer:FindFirstChild("ContentContainer")
		if not content then
			return nil
		end

		local ok, children = pcall(function()
			return content:GetChildren()
		end)

		if not ok then
			return nil
		end

		for _, child in ipairs(children) do
			if child:IsA("GuiButton") and _G.F.isGuiChainVisible(child) then
				local displayName = getGuiItemDisplayName(child)
				if displayName and discItemMatchesSearch({ name = displayName, id = displayName }, discId, discLabel) then
					return child
				end
			end
		end

		return nil
	end

	local function clickBagUseButton(bag)
		if type(bag) ~= "table" then
			return false
		end

		if type(bag.useSelectedItemBattle) == "function" and bag.selection then
			pcall(function()
				bag:useSelectedItemBattle()
			end)
			return true
		end

		local useButton = bag.useButtonBattle
		if useButton and _G.F.isGuiChainVisible(useButton) then
			pcall(function()
				useButton:Activate()
			end)
			return true
		end

		local parent = useButton and useButton.Parent
		if parent and parent:IsA("GuiButton") and _G.F.isGuiChainVisible(parent) then
			pcall(function()
				parent:Activate()
			end)
			return true
		end

		return false
	end

	local function openBattleBagFromMain()
		local clicked = false
		local bagButton = getBattleBagButton()
		if not bagButton then
			return false
		end

		if _G.F.clickGuiButtonOnce(bagButton) then
			clicked = true
			task.wait(0.05)

			if isBagOpenInBattle() or isBagItemDetailOpen() then
				return true
			end
		end

		if _G.F.activateGuiButton(bagButton) then
			clicked = true
			task.wait(0.05)

			if isBagOpenInBattle() or isBagItemDetailOpen() then
				return true
			end
		end

		return clicked
	end

	_G.isCatchUiActive = function()
		return isBagOpenInBattle() or isBagItemDetailOpen()
	end

	_G.resetCatchUiTiming = function()
		catchBagOpenedAt = 0
		catchDiscSelectedAt = 0
		catchOpenedBagForRequest = false
	end

	_G.naturalCatchFromBattle = function(battle, discId, discLabel)
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		if _G.F.isBattleSetupPending(battle) then
			return false, "Battle setup not ready."
		end

		local bag = getBattleBagModule()

		if isBagItemDetailOpen() and catchOpenedBagForRequest then
			if catchDiscSelectedAt == 0 then
				catchDiscSelectedAt = os.clock()
				return false, "Waiting for disc detail."
			end

			if type(bag) == "table" and not bag.selection then
				return false, "Waiting for disc detail."
			end

			if os.clock() - catchDiscSelectedAt < DISC_DETAIL_READY_DELAY then
				return false, "Waiting for disc detail."
			end

			clickBagUseButton(bag)
			return true
		end

		if isBagOpenInBattle() and catchOpenedBagForRequest then
			if catchBagOpenedAt == 0 then
				catchBagOpenedAt = os.clock()
				return false, "Waiting for bag items."
			end

			if os.clock() - catchBagOpenedAt < BAG_ITEMS_READY_DELAY then
				return false, "Waiting for bag items."
			end

			local itemData = findBattleBagDiscItem(discId, discLabel)
			if itemData and type(bag) == "table" and type(bag.viewItemBattle) == "function" then
				pcall(function()
					bag:viewItemBattle(itemData)
				end)
				catchDiscSelectedAt = os.clock()
				return false, "Disc opened."
			end

			local discButton = findBagDiscButton(discId, discLabel)
			if discButton then
				pcall(function()
					discButton:Activate()
				end)
				catchDiscSelectedAt = os.clock()
				return false, "Disc selected."
			end

			return false, "Waiting for bag items."
		end

		if not _G.F.isBattleRunMenuReady(battle) then
			return false, "Battle menu not ready."
		end

		if openBattleBagFromMain() then
			catchBagOpenedAt = os.clock()
			catchDiscSelectedAt = 0
			catchOpenedBagForRequest = true
			return false, "Opening bag."
		end

		return false, "Bag button not found."
	end
end

return { name = "battle" }
