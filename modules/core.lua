-- core.lua
-- Core helpers, info/goppie utils, and FishingAutomation.
_G.F.findP = function()
	-- Every call site retries this when _G._p is missing, and a registry
	-- sweep can take hundreds of ms; don't hammer it when the hook can't
	-- be found.
	if _G._findPFailedAt and os.clock() - _G._findPFailedAt < 5 then
		return nil
	end

	local registryOk, registry = pcall(function()
		return debug.getregistry()
	end)
	if not registryOk or type(registry) ~= "table" then
		return nil
	end

	for _, fn in pairs(registry) do
		if type(fn) == "function" then
			local upvaluesOk, upvalues = pcall(debug.getupvalues, fn)
			if upvaluesOk and type(upvalues) == "table" then
				for _, upvalue in pairs(upvalues) do
					local ok, result = pcall(function()
						return upvalue.NPCChat
					end)

					if ok and type(result) == "table" then
						_G._findPFailedAt = nil
						return upvalue
					end
				end
			end
		end
	end

	_G._findPFailedAt = os.clock()
	return nil
end

task.defer(function()
	local ok, found = pcall(_G.F.findP)
	_G._p = ok and found or nil
end)

_G.F.safeTableGet = function(object, key)
	if type(object) ~= "table" then
		return nil
	end

	local ok, value = pcall(function()
		return object[key]
	end)

	if ok then
		return value
	end

	return nil
end

_G.F.safeTableSet = function(object, key, value)
	if type(object) ~= "table" then
		return false
	end

	return pcall(function()
		object[key] = value
	end)
end

_G.F.normalizeInfoKey = function(value)
	return string.gsub(string.lower(tostring(value or "")), "[^%w]", "")
end

_G.F.formatInfoValue = function(value)
	if value == nil then
		return "N/A"
	end

	if type(value) == "number" then
		local sign = value < 0 and "-" or ""
		local integer, fraction = tostring(math.abs(value)):match("^(%d+)(%.%d+)$")
		integer = integer or tostring(math.floor(math.abs(value)))
		local formatted = string.reverse(integer):gsub("(%d%d%d)", "%1,")
		formatted = string.reverse(formatted):gsub("^,", "")
		return sign .. formatted .. (fraction or "")
	end

	if type(value) == "boolean" then
		return value and "Yes" or "No"
	end

	return tostring(value)
end

_G.F.getLeaderstatValue = function(aliases)
	local player = _G.Player
	local leaderstats = player and player:FindFirstChild("leaderstats")
	if not leaderstats then
		return nil
	end

	local aliasLookup = {}
	for _, alias in ipairs(aliases) do
		aliasLookup[_G.F.normalizeInfoKey(alias)] = true
	end

	for _, child in ipairs(leaderstats:GetChildren()) do
		if aliasLookup[_G.F.normalizeInfoKey(child.Name)] then
			local ok, value = pcall(function()
				return child.Value
			end)
			if ok and value ~= nil then
				return value
			end
		end
	end

	return nil
end

_G.F.parseInfoNumberText = function(text)
	local match = tostring(text or ""):match("[-+]?%d[%d,]*")
	if not match then
		return nil
	end

	local parsed = tonumber((match:gsub(",", "")))
	return parsed
end

_G.F.getNearbyGuiNumber = function(guiObject)
	if not guiObject then
		return nil
	end

	local containers = { guiObject.Parent }
	if guiObject.Parent and guiObject.Parent.Parent then
		table.insert(containers, guiObject.Parent.Parent)
	end

	for _, container in ipairs(containers) do
		if container then
			for _, descendant in ipairs(container:GetDescendants()) do
				if descendant ~= guiObject and (descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox")) then
					local value = _G.F.parseInfoNumberText(descendant.Text)
					if value ~= nil then
						return value
					end
				end
			end
		end
	end

	return nil
end

_G.F.getPlayerGuiInfoValue = function(aliases)
	local playerGui = _G.Player and _G.Player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return nil
	end

	local aliasLookup = {}
	for _, alias in ipairs(aliases) do
		aliasLookup[_G.F.normalizeInfoKey(alias)] = true
	end

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if descendant:IsA("TextLabel") or descendant:IsA("TextButton") or descendant:IsA("TextBox") then
			local text = tostring(descendant.Text or "")
			local normalizedText = _G.F.normalizeInfoKey(text)
			local guiName = _G.F.normalizeInfoKey(descendant.Name)

			for aliasKey in pairs(aliasLookup) do
				if normalizedText == aliasKey or guiName == aliasKey or string.find(normalizedText, aliasKey, 1, true) or string.find(guiName, aliasKey, 1, true) then
					local directValue = _G.F.parseInfoNumberText(text)
					if directValue ~= nil then
						return directValue
					end

					local nearbyValue = _G.F.getNearbyGuiNumber(descendant)
					if nearbyValue ~= nil then
						return nearbyValue
					end
				end
			end
		end
	end

	return nil
end

_G.F.findInfoValueInTable = function(root, aliases, maxDepth)
	if type(root) ~= "table" then
		return nil
	end

	local aliasLookup = {}
	for _, alias in ipairs(aliases) do
		aliasLookup[_G.F.normalizeInfoKey(alias)] = true
	end

	local visited = {}
	local function scan(value, depth)
		if type(value) ~= "table" or visited[value] or depth > maxDepth then
			return nil
		end

		visited[value] = true

		local ok, found = pcall(function()
			for key, child in pairs(value) do
				if aliasLookup[_G.F.normalizeInfoKey(key)] and type(child) ~= "table" and type(child) ~= "function" then
					return child
				end
			end

			for _, child in pairs(value) do
				local nested = scan(child, depth + 1)
				if nested ~= nil then
					return nested
				end
			end
		end)

		if ok then
			return found
		end

		return nil
	end

	return scan(root, 0)
end

_G.F.getInformationRoots = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local roots = {}
	local function add(root)
		if type(root) == "table" then
			table.insert(roots, root)
		end
	end

	add(_G._p)

	if type(_G._p) == "table" then
		for _, key in ipairs({ "PlayerData", "playerData", "Data", "data", "SaveData", "saveData", "PDS", "pds", "Menu", "DataManager" }) do
			add(_G.F.safeTableGet(_G._p, key))
		end

		local dataManager = _G.F.safeTableGet(_G._p, "DataManager")
		if type(dataManager) == "table" then
			for _, key in ipairs({ "currentSave", "currentData", "playerData", "data", "saveData", "currentChunk" }) do
				add(_G.F.safeTableGet(dataManager, key))
			end
		end
	end

	return roots
end

_G.F.getInformationValue = function(aliases)
	local leaderstatValue = _G.F.getLeaderstatValue(aliases)
	if leaderstatValue ~= nil then
		return leaderstatValue
	end

	for _, root in ipairs(_G.F.getInformationRoots()) do
		local value = _G.F.findInfoValueInTable(root, aliases, 5)
		if value ~= nil then
			return value
		end
	end

	return nil
end

_G.F.getInformationSnapshot = function()
	local definitions = {
		{ key = "money", label = "Money", aliases = { "money", "cash", "dollars", "lumidollars", "loomidollars", "lumiDollars" } },
		{ key = "tix", label = "Tix", aliases = { "tix", "ticket", "tickets", "eventtickets", "eventTix" } },
		{ key = "bp", label = "BP", aliases = { "bp", "battlepoints", "battlePoints", "battle_points", "battlepoint" } },
	}

	local snapshot = {}
	for _, definition in ipairs(definitions) do
		table.insert(snapshot, {
			key = definition.key,
			label = definition.label,
			value = _G.F.getInformationValue(definition.aliases),
		})
	end

	return snapshot
end

_G.F.refreshInformationLabels = function()
	if type(_G.informationLabels) ~= "table" then
		return
	end

	local loadedCount = 0
	for _, item in ipairs(_G.F.getInformationSnapshot()) do
		local label = _G.informationLabels[item.key]
		if label and type(label.Set) == "function" then
			if item.value ~= nil then
				loadedCount = loadedCount + 1
			end

			pcall(function()
				label:Set(item.label .. ": " .. _G.F.formatInfoValue(item.value))
			end)
		end
	end

	if _G.informationLabels.status and type(_G.informationLabels.status.Set) == "function" then
		pcall(function()
			_G.informationLabels.status:Set("Loaded: " .. tostring(loadedCount) .. "/3")
		end)
	end
end

_G.isActiveFlag = function(value)
	return value ~= nil and value ~= false and value ~= 0
end

_G.F.isBattleEnded = function(battle)
	return type(battle) == "table" and _G.F.safeTableGet(battle, "ended") == true
end

_G.F.isRealBattle = function(battle)
	return type(battle) == "table"
		and battle.ended ~= true
		and (battle.kind ~= nil or battle.state ~= nil or battle.battleId ~= nil)
end

_G.F.isBattleSetupPending = function(battle)
	if type(battle) ~= "table" or battle.ended then
		return true
	end

	return battle.setupComplete ~= true
end

_G.F.isFishingBattleStarting = function(battle)
	return type(battle) == "table"
		and battle.fshPct ~= nil
		and battle.setupComplete ~= true
end

_G.F.getContainerCurrentBattle = function(container)
	local battle = _G.F.safeTableGet(container, "currentBattle")
	if _G.F.isBattleEnded(battle) then
		_G.F.safeTableSet(container, "currentBattle", nil)
		_G.fastForwardBattles[battle] = nil
		return nil
	end

	if type(battle) ~= "table" then
		return nil
	end

	return battle
end

_G.F.normalizeFormeKey = function(value)
	if value == nil then
		return nil
	end

	local text = tostring(value):lower():gsub("^%s+", ""):gsub("%s+$", "")
	if text == "" then
		return nil
	end

	return text
end

_G.F.rebuildExcludedFormes = function()
	_G.excludedFormes = {}

	for _, entry in pairs(_G.EXCLUDED_FORMES) do
		local key = _G.F.normalizeFormeKey(entry)
		if key then
			_G.excludedFormes[key] = true
		end
	end

	for _, entry in pairs(_G.GOPPIE_FORMES) do
		local key = _G.F.normalizeFormeKey(entry)
		if key then
			_G.excludedFormes[key] = true
		end
	end
end

_G.F.rebuildExcludedFormes()

_G.F.getFormeMatchCandidates = function(value)
	local key = _G.F.normalizeFormeKey(value)
	if key == nil then
		return {}
	end

	local candidates = { key }

	local suffix = string.match(key, "%-([^%-]+)$")
	if suffix and suffix ~= key then
		table.insert(candidates, suffix)
	end

	local barePattern = string.match(key, "%-pattern(%d+)$")
	if barePattern then
		table.insert(candidates, "pattern" .. barePattern)
	end

	return candidates
end

_G.F.isMeaningfulFormeValue = function(value)
	if value == nil or value == false then
		return false
	end

	return _G.F.normalizeFormeKey(value) ~= nil
end

_G.F.isExcludedForme = function(value)
	for _, key in ipairs(_G.F.getFormeMatchCandidates(value)) do
		if _G.excludedFormes[key] then
			return true
		end

		for excludedKey in pairs(_G.excludedFormes) do
			if #excludedKey <= 2 then
				if key == excludedKey or string.sub(key, -(#excludedKey + 1)) == "-" .. excludedKey then
					return true
				end
			elseif string.find(key, excludedKey, 1, true) or string.find(excludedKey, key, 1, true) then
				return true
			end
		end
	end

	return false
end

_G.F.addExcludedForme = function(value)
	if not _G.F.isMeaningfulFormeValue(value) then
		return false
	end

	local key = _G.F.normalizeFormeKey(value)
	for _, entry in ipairs(_G.EXCLUDED_FORMES) do
		if _G.F.normalizeFormeKey(entry) == key then
			return false
		end
	end

	table.insert(_G.EXCLUDED_FORMES, tostring(value))
	_G.F.rebuildExcludedFormes()
	return true
end

_G.F.isGoppieMonster = function(monster)
	if type(monster) ~= "table" then
		return false
	end

	local function valueMatches(value)
		local name = _G.F.normalizeLoomianSearchName(value)
		return name == "goppie" or string.find(name, "goppie", 1, true) ~= nil
	end

	local modelData = _G.F.safeTableGet(monster, "modelData")
	local sprite = _G.F.safeTableGet(monster, "sprite")
	local spriteModelData = type(sprite) == "table" and _G.F.safeTableGet(sprite, "modelData") or nil

	return valueMatches(monster.name)
		or valueMatches(monster.species)
		or valueMatches(monster.nickname)
		or valueMatches(type(modelData) == "table" and _G.F.safeTableGet(modelData, "name") or nil)
		or valueMatches(type(sprite) == "table" and _G.F.safeTableGet(sprite, "name") or nil)
		or valueMatches(type(spriteModelData) == "table" and _G.F.safeTableGet(spriteModelData, "name") or nil)
end

_G.F.getGoppieVariantName = function(value)
	if not _G.F.isMeaningfulFormeValue(value) then
		return nil
	end

	local text = tostring(value)
	local key = _G.F.normalizeLoomianSearchName(text)
	if string.find(key, "goppie", 1, true) and key ~= "goppie" then
		return text
	end

	return nil
end

_G.F.getMonsterGoppieVariantName = function(monster)
	if type(monster) ~= "table" then
		return nil
	end

	local modelData = _G.F.safeTableGet(monster, "modelData")
	local sprite = _G.F.safeTableGet(monster, "sprite")
	local spriteModelData = type(sprite) == "table" and _G.F.safeTableGet(sprite, "modelData") or nil

	for _, value in pairs({
		name = monster.name,
		species = monster.species,
		nickname = monster.nickname,
		modelName = type(modelData) == "table" and _G.F.safeTableGet(modelData, "name") or nil,
		spriteName = type(sprite) == "table" and _G.F.safeTableGet(sprite, "name") or nil,
		spriteModelName = type(spriteModelData) == "table" and _G.F.safeTableGet(spriteModelData, "name") or nil
	}) do
		local variantName = _G.F.getGoppieVariantName(value)
		if variantName then
			return variantName
		end
	end

	return nil
end

_G.F.findGoppieNameDeep = function(root)
	if type(root) ~= "table" then
		return nil
	end

	local seen = {}

	local function scan(value, depth)
		if depth > 6 then
			return nil
		end

		if type(value) == "string" and string.find(_G.F.normalizeLoomianSearchName(value), "goppie", 1, true) then
			return value
		elseif type(value) == "table" and not seen[value] then
			seen[value] = true

			for _, childValue in pairs(value) do
				local found = scan(childValue, depth + 1)
				if found then
					return found
				end
			end
		end

		return nil
	end

	return scan(root, 0)
end

_G.F.normalizeGoppieFormeFromCaptureValue = function(value)
	if type(value) == "string" then
		return _G.F.getGoppieVariantName(value)
	elseif type(value) == "table" then
		local goppieName = _G.F.findGoppieNameDeep(value)
		if _G.F.isMeaningfulFormeValue(_G.F.getGoppieVariantName(goppieName)) then
			return goppieName
		end

		local directForme = _G.F.getMonsterGoppieVariantName(value) or _G.F.getMonsterFormeValue(value)
		if _G.F.isMeaningfulFormeValue(directForme) and _G.F.isGoppieMonster(value) then
			return directForme
		end

		local deepForme = _G.F.findGoppieFormeValueDeep(value)
		if _G.F.isMeaningfulFormeValue(deepForme) then
			return deepForme
		end
	end

	return nil
end

_G.F.addCapturedGoppieFormeFromArgs = function(...)
	local battle = _G.F.getCurrentBattle()
	if battle and _G.F.registerCaughtGoppieFormeFromBattle(battle) then
		return true
	end

	local args = { ... }

	for _, value in ipairs(args) do
		local formeValue = _G.F.normalizeGoppieFormeFromCaptureValue(value)
		if _G.F.isMeaningfulFormeValue(formeValue) then
			_G.lastAutoFishingGoppieForme = formeValue
			_G.lastAutoFishingGoppieFormeAt = os.clock()

			local added = _G.F.addGoppieForme(formeValue)
			pcall(function()
				_G.OrionLib:MakeNotification({
					Name = "Goppie Formes",
					Content = (added and "Saved caught forme: " or "Forme already saved: ") .. tostring(formeValue),
					Time = 4
				})
			end)
			return true
		end
	end

	return false
end

_G.F.isGoppieCaptureNetworkEvent = function(eventName)
	return eventName == "OnCaptureDCGoppie" or eventName == "OnCaptureT5Goppie"
end

_G.F.makeGoppieCaptureCallback = function(eventName, callback)
	return function(...)
		_G.F.addCapturedGoppieFormeFromArgs(...)

		if type(callback) == "function" then
			return callback(...)
		end
	end
end

_G.F.installGoppieCaptureNetworkHook = function()
	if _G.goppieCaptureNetworkHooked then
		return
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local network = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Network") or nil
	if type(network) ~= "table" then
		return
	end

	local bindEvent = _G.F.safeTableGet(network, "bindEvent")
	if type(bindEvent) == "function" then
		local originalBindEvent = bindEvent
		_G.F.safeTableSet(network, "bindEvent", function(self, eventName, callback, ...)
			if _G.F.isGoppieCaptureNetworkEvent(eventName) and type(callback) == "function" then
				callback = _G.F.makeGoppieCaptureCallback(eventName, callback)
			end

			return originalBindEvent(self, eventName, callback, ...)
		end)
		_G.goppieCaptureNetworkHooked = true
	end

	if type(debug) == "table" and type(debug.getupvalues) == "function" then
		pcall(function()
			local upvalues = { debug.getupvalues(bindEvent) }
			for _, upvalue in ipairs(upvalues) do
				if type(upvalue) == "table" then
					for eventName, callback in pairs(upvalue) do
						if _G.F.isGoppieCaptureNetworkEvent(eventName) and type(callback) == "function" then
							upvalue[eventName] = _G.F.makeGoppieCaptureCallback(eventName, callback)
						end
					end
				end
			end
		end)
	end
end

_G.F.findGoppieFormeValueDeep = function(root)
	if type(root) ~= "table" then
		return nil
	end

	local seen = {}
	local foundGoppie = false
	local formeValue = nil

	local function scan(value, key, depth)
		if depth > 6 or (formeValue and foundGoppie) then
			return
		end

		if type(value) == "string" or type(value) == "number" then
			local loweredValue = _G.F.normalizeLoomianSearchName(value)
			if string.find(loweredValue, "goppie", 1, true) then
				foundGoppie = true
			end

			local loweredKey = _G.F.normalizeLoomianSearchName(key)
			local keyLooksLikeForme = string.find(loweredKey, "forme", 1, true)
				or string.find(loweredKey, "form", 1, true)
				or string.find(loweredKey, "variant", 1, true)
				or string.find(loweredKey, "pattern", 1, true)
				or string.find(loweredKey, "color", 1, true)
				or string.find(loweredKey, "colour", 1, true)

			if keyLooksLikeForme
				and _G.F.isMeaningfulFormeValue(value)
				and loweredValue ~= "goppie"
				and loweredValue ~= "m"
				and loweredValue ~= "f" then
				formeValue = formeValue or tostring(value)
			end
		elseif type(value) == "table" and not seen[value] then
			seen[value] = true

			for childKey, childValue in pairs(value) do
				scan(childValue, childKey, depth + 1)
			end
		end
	end

	scan(root, nil, 0)

	if foundGoppie and _G.F.isMeaningfulFormeValue(formeValue) then
		return formeValue
	end

	return nil
end

_G.F.rememberAutoFishingGoppieFormeFromBattle = function(battle)
	if not _G.autoFishingEnabled or type(battle) ~= "table" then
		return nil
	end

	local foe = _G.F.getBattleFoeMonster(battle)
	local deepFormeValue = _G.F.findGoppieFormeValueDeep(battle)
	if not _G.F.isGoppieMonster(foe) and not _G.F.isMeaningfulFormeValue(deepFormeValue) then
		_G.lastAutoFishingGoppieForme = nil
		_G.lastAutoFishingGoppieFormeAt = 0
		return nil
	end

	local formeValue = _G.F.getMonsterGoppieVariantName(foe) or _G.F.getMonsterFormeValue(foe) or deepFormeValue
	if _G.F.isMeaningfulFormeValue(formeValue) then
		_G.lastAutoFishingGoppieForme = formeValue
		_G.lastAutoFishingGoppieFormeAt = os.clock()
		if _G.lastAutoFishingGoppieNotice ~= tostring(formeValue) then
			_G.lastAutoFishingGoppieNotice = tostring(formeValue)
			pcall(function()
				_G.OrionLib:MakeNotification({
					Name = "Auto Fishing",
					Content = "Detected Goppie forme: " .. tostring(formeValue),
					Time = 2
				})
			end)
		end
		return formeValue
	end

	return nil
end

_G.F.getFishingGoppieFormeValue = function(battle)
	if type(battle) ~= "table" then
		return nil
	end

	local foe = _G.F.getBattleFoeMonster(battle)
	return _G.F.getMonsterGoppieVariantName(foe)
		or _G.F.getMonsterFormeValue(foe)
		or _G.F.findGoppieFormeValueDeep(battle)
end

_G.F.isGoppieFormeSaved = function(value)
	if not _G.F.isMeaningfulFormeValue(value) then
		return false
	end

	for _, candidate in ipairs(_G.F.getFormeMatchCandidates(value)) do
		for _, entry in ipairs(_G.GOPPIE_FORMES) do
			local savedKey = _G.F.normalizeFormeKey(entry)
			if savedKey == candidate then
				return true
			end

			for _, savedCandidate in ipairs(_G.F.getFormeMatchCandidates(entry)) do
				if savedCandidate == candidate then
					return true
				end
			end
		end
	end

	return false
end

_G.F.isFishingGoppieBattle = function(battle)
	return type(battle) == "table"
		and battle.kind == "wild"
		and battle.fshPct ~= nil
end

_G.F.isAutoFishingExcludedGoppieBattle = function(battle)
	if not _G.autoFishingEnabled or type(battle) ~= "table" then
		return false
	end

	local foe = _G.F.getBattleFoeMonster(battle)
	local formeValue = _G.F.getFishingGoppieFormeValue(battle)
	if not _G.F.isMeaningfulFormeValue(formeValue) then
		return false
	end

	return (_G.F.isGoppieMonster(foe) or _G.F.isMeaningfulFormeValue(formeValue))
		and _G.F.isGoppieFormeSaved(formeValue)
end

_G.F.shouldCatchFishingGoppieBattle = function(battle)
	if not _G.F.isFishingGoppieBattle(battle) or not _G.F.hasWildFoeLoaded(battle) then
		return false
	end

	local foe = _G.F.getBattleFoeMonster(battle)
	local formeValue = _G.F.getFishingGoppieFormeValue(battle)
	if not _G.F.isGoppieMonster(foe) and not _G.F.isMeaningfulFormeValue(formeValue) then
		return false
	end

	if not _G.F.isMeaningfulFormeValue(formeValue) then
		return false
	end

	return not _G.F.isGoppieFormeSaved(formeValue)
end

_G.F.setFastForwardEnabled = function(value)
	_G.fastForwardEnabled = value and true or false

	if _G.fastForwardEnabled then
		local battle = _G.F.getCurrentBattle()
		_G.F.setBattleFastForward(true, battle)
		_G.F.applyBattleAnimationFastForward(battle, false)
	else
		_G.F.clearAllBattleFastForward()
	end
end

_G.F.setAutoFishingEnabled = function(value)
	_G.autoFishingEnabled = value and true or false

	if _G.FishingAutomation then
		_G.FishingAutomation:setEnabled(_G.autoFishingEnabled)
	end
end

_G.F.safeSetParagraph = function(paragraph, text)
	pcall(function()
		if paragraph and type(paragraph.Set) == "function" then
			paragraph:Set(text)
		end
	end)
end

_G.FishingAutomation = (function()
	local api = {}
	local statusParagraph = nil
	local lastCastAt = 0
	local casting = false
	local originalFishMiniGame = nil
	local fishMiniGameHook = nil
	local hookedFishingModule = nil
	local originalSetupScene = nil
	local hookedSetupSceneOwner = nil

	local function restoreSetupSceneHook()
		if hookedSetupSceneOwner and originalSetupScene then
			if _G.F.safeTableGet(hookedSetupSceneOwner, "setupScene") ~= originalSetupScene then
				_G.F.safeTableSet(hookedSetupSceneOwner, "setupScene", originalSetupScene)
			end
		end

		originalSetupScene = nil
		hookedSetupSceneOwner = nil
	end

	local function installFishingSetupSceneHook()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		for _, containerName in ipairs({ "BattleClient", "Battle" }) do
			local battleClient = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, containerName) or nil
			if type(battleClient) == "table" then
				if hookedSetupSceneOwner == battleClient and originalSetupScene then
					return true
				end

				local original = _G.F.safeTableGet(battleClient, "setupScene")
				if type(original) == "function" and original ~= originalSetupScene then
					if not originalSetupScene then
						originalSetupScene = original
					end

					hookedSetupSceneOwner = battleClient
					_G.F.safeTableSet(battleClient, "setupScene", function(self, ...)
						return originalSetupScene(self, ...)
					end)

					return true
				end
			end
		end

		return false
	end

	local function setStatus(text)
		_G.F.safeSetParagraph(statusParagraph, text)
	end

	local function getFishingModule()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local fishing = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Fishing") or nil
		if type(fishing) ~= "table" then
			return nil, "Fishing is not ready."
		end

		return fishing
	end

	local function getFishingPool()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local currentChunk = type(_G._p) == "table" and _G._p.DataManager and _G._p.DataManager.currentChunk or nil
		local regionData = type(currentChunk) == "table" and currentChunk.regionData or nil
		local pool = type(regionData) == "table" and regionData.Fishing or nil
		if not pool then
			return nil, "This chunk has no fishing encounters."
		end

		return pool
	end

	local function restoreMiniGameHook()
		if hookedFishingModule and fishMiniGameHook and _G.F.safeTableGet(hookedFishingModule, "FishMiniGame") == fishMiniGameHook then
			_G.F.safeTableSet(hookedFishingModule, "FishMiniGame", originalFishMiniGame)
		end

		originalFishMiniGame = nil
		fishMiniGameHook = nil
		hookedFishingModule = nil
	end

	local function cleanupAutoReelState(animations)
		pcall(function()
			if type(animations) == "table" then
				if animations.pullUp then
					animations.pullUp:Stop(0.5)
				end
				if animations.pullDown then
					animations.pullDown:Stop(0.5)
				end
			end
		end)

		pcall(function()
			_G.RunService:UnbindFromRenderStep("loomFishingGame")
		end)

		pcall(function()
			local mouseManager = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "MouseManager") or nil
			local setMouseIconEnabled = type(mouseManager) == "table" and _G.F.safeTableGet(mouseManager, "SetMouseIconEnabled") or nil
			if type(setMouseIconEnabled) == "function" then
				setMouseIconEnabled(mouseManager, true)
			end
		end)

		pcall(function()
			local guiService = game:GetService("GuiService")
			local selected = guiService.SelectedObject
			if selected and selected:IsDescendantOf(game) then
				guiService.SelectedObject = nil
			end
		end)
	end

	local function waitForFishCatchResult(fishId)
		local catchResult = nil

		if fishId == nil then
			return true
		end

		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local network = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Network") or nil
		if type(network) ~= "table" or type(_G.F.safeTableGet(network, "get")) ~= "function" then
			return true
		end

		task.spawn(function()
			local ok, value = pcall(function()
				return network:get("PDS", "fshchi", fishId)
			end)

			if ok then
				catchResult = value
			end
		end)

		local deadline = os.clock() + 3
		while catchResult == nil and os.clock() < deadline do
			task.wait()
		end

		if catchResult == nil then
			return true
		end

		return catchResult
	end

	local function installMiniGameHook(fishing)
		if hookedFishingModule == fishing and fishMiniGameHook then
			return true
		end

		restoreMiniGameHook()

		local original = _G.F.safeTableGet(fishing, "FishMiniGame")
		if type(original) ~= "function" then
			return false, "Fishing minigame is not ready."
		end

		originalFishMiniGame = original
		hookedFishingModule = fishing
		fishMiniGameHook = function(self, animations, rod, fishId)
			if not _G.autoFishingEnabled then
				return originalFishMiniGame(self, animations, rod, fishId)
			end

			local catchResult = waitForFishCatchResult(fishId)
			cleanupAutoReelState(animations)
			task.wait(0.2)

			return 0.85, catchResult
		end

		if not _G.F.safeTableSet(fishing, "FishMiniGame", fishMiniGameHook) then
			restoreMiniGameHook()
			return false, "Could not hook fishing minigame."
		end

		return true
	end

	local function getWaterRaycastParams()
		local params = RaycastParams.new()
		params.FilterDescendantsInstances = { workspace.Terrain }
		params.FilterType = Enum.RaycastFilterType.Include
		params.IgnoreWater = false
		return params
	end

	local function findFishableWaterPosition()
		local root = _G.F.getRoot()
		if not root then
			return nil, "Character root is not ready."
		end

		local look = root.CFrame.LookVector * Vector3.new(1, 0, 1)
		if look.Magnitude < 0.01 then
			look = Vector3.new(0, 0, -1)
		else
			look = look.Unit
		end

		local right = root.CFrame.RightVector * Vector3.new(1, 0, 1)
		if right.Magnitude < 0.01 then
			right = Vector3.new(1, 0, 0)
		else
			right = right.Unit
		end

		local params = getWaterRaycastParams()
		for _, distance in ipairs({ 5, 7.5, 10, 13, 16, 20 }) do
			for _, sideOffset in ipairs({ 0, -3, 3, -6, 6 }) do
				local origin = root.Position + look * distance + right * sideOffset + Vector3.new(0, 8, 0)
				local result = workspace:Raycast(origin, Vector3.new(0.001, -60, 0.001), params)
				if result and result.Material == Enum.Material.Water then
					return result.Position
				end
			end
		end

		return nil, "Face fishable water and stand closer."
	end

	local function isNpcChatLocked()
		local chat = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "NPCChat") or nil
		if type(chat) ~= "table" then
			return false
		end

		for _, methodName in ipairs({ "isChatting", "isAwaitingManualAdvance", "isAwaitingChoice", "isChoosing", "isBusy" }) do
			local method = _G.F.safeTableGet(chat, methodName)
			if type(method) == "function" then
				local ok, result = pcall(function()
					return method(chat)
				end)

				if ok and result then
					return true
				end
			end
		end

		return false
	end

	function api:setEnabled(value)
		_G.autoFishingEnabled = value and true or false

		if not _G.autoFishingEnabled then
			restoreMiniGameHook()
			restoreSetupSceneHook()
			casting = false
			setStatus("Auto Fishing is off.")
		else
			installFishingSetupSceneHook()
			setStatus("Face water to start fishing.")
		end
	end

	function api:isEnabled()
		return _G.autoFishingEnabled
	end

	function api:castOnce()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		if _G.F.getCurrentBattle() then
			return false, "Battle already active."
		end

		if casting then
			return false, "Fishing already in progress."
		end

		if isNpcChatLocked() then
			return false, "NPC chat is busy."
		end

		local fishing, fishingReason = getFishingModule()
		if not fishing then
			return false, fishingReason
		end

		if not getFishingPool() then
			return false, "This chunk has no fishing encounters."
		end

		local hooked, hookReason = installMiniGameHook(fishing)
		if not hooked then
			return false, hookReason
		end

		if not installFishingSetupSceneHook() then
			return false, "Battle setup hook is not ready."
		end

		local waterPosition, waterReason = findFishableWaterPosition()
		if not waterPosition then
			return false, waterReason
		end

		local masterControl = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "MasterControl") or nil
		if type(masterControl) == "table" and masterControl.WalkEnabled == false then
			masterControl.WalkEnabled = true
		end

		_G.F.setFastForwardEnabled(false)
		casting = true
		lastCastAt = os.clock()

		task.spawn(function()
			local ok, err = pcall(function()
				if type(_G.F.safeTableGet(fishing, "OnWaterClicked")) == "function" then
					fishing:OnWaterClicked(waterPosition)
				else
					fishing:Fish(waterPosition)
				end
			end)

			casting = false
			if not ok then
				warn("[Auto Fishing] " .. tostring(err))
				setStatus(tostring(err))
			elseif _G.F.getCurrentBattle() then
				setStatus("Fishing battle started.")
			else
				setStatus("Waiting for next cast.")
			end
		end)

		setStatus("Casting...")
		return true
	end

	function api:runCycle()
		if not _G.autoFishingEnabled then
			return false
		end

		if casting or _G.F.getCurrentBattle() then
			return false
		end

		if os.clock() - lastCastAt < _G.autoFishingDelay then
			return false
		end

		return self:castOnce()
	end

	function api:attachUi(tab)
		statusParagraph = tab:AddLabel("Idle")
		_G.fishingStatusLabel = statusParagraph

		_G.configUi.autoFishingToggle = tab:AddToggle({
			Name = "Auto Fishing",
			Default = _G.autoFishingEnabled,
			Color = Color3.fromRGB(70, 170, 255),
			Callback = function(value)
				_G.F.setAutoFishingEnabled(value)
			end
		})

		tab:AddButton({
			Name = "Cast Now",
			Icon = "waves",
			Callback = function()
				local started, reason = api:castOnce()
				if not started and reason then
					_G.OrionLib:MakeNotification({
						Name = "Auto Fishing",
						Content = reason,
						Time = 4
					})
				end
			end
		})

		tab:AddSlider({
			Name = "Cast Delay",
			Min = 0.75,
			Max = 6,
			Default = _G.autoFishingDelay,
			Increment = 0.25,
			ValueName = "s",
			Callback = function(value)
				_G.autoFishingDelay = value
			end
		})

	end

	function api:restoreMiniGameHook()
		restoreMiniGameHook()
	end

	return api
end)()

_G.FishingAutomation = _G.FishingAutomation

return { name = "core" }
