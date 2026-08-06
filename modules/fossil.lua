-- fossil.lua
-- Encounters, fossil revive, config load/save.
_G.F.setAutoDiscDropEnabled = function(value)
	_G.autoDiscDropEnabled = value and true or false

	if _G.ArcadeAutomation then
		if not _G.autoDiscDropEnabled then
			_G.ArcadeAutomation:stopAll()
		end
	end
end

_G.F.setAutoCatchEnabled = function(value)
	_G.autoCatchEnabled = value

	if value and _G.CatchAutomation then
		_G.CatchAutomation:resetState()
	end
end

_G.F.getEncounterPool = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	if type(_G._p) ~= "table" then
		return nil, "Hook is not ready."
	end

	local currentChunk = _G._p.DataManager and _G._p.DataManager.currentChunk
	local regionData = currentChunk and currentChunk.regionData
	if type(regionData) ~= "table" then
		return nil, "Current region has no encounter data."
	end

	if regionData.Grass and not (regionData.NoGrassIndoors and currentChunk.indoors) then
		return regionData.Grass
	end

	if regionData.GrassNotRequired and regionData.Grass then
		return regionData.Grass
	end

	return nil, "No grass encounter pool found here."
end

_G.F.startAutoEncounter = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local battleClient = type(_G._p) == "table" and (_G._p.BattleClient or _G._p.Battle) or nil
	if type(battleClient) ~= "table" then
		return false, "BattleClient is not ready."
	end

	if _G.F.getCurrentBattle() then
		return false, "Battle already active."
	end

	local masterControl = type(_G._p) == "table" and _G._p.MasterControl or nil
	if type(masterControl) == "table" and masterControl.WalkEnabled == false then
		return false, "Movement is disabled."
	end

	local pool, reason = _G.F.getEncounterPool()
	if not pool then
		return false, reason
	end

	local ok, result = pcall(function()
		return battleClient:doWildBattle(pool, {})
	end)

	if not ok then
		return false, tostring(result)
	end

	return true
end

_G.F.shouldFilterEncounterTarget = function()
	return _G.F.normalizeLoomianSearchName(_G.encounterTargetLoomian) ~= ""
end

_G.F.isWrongEncounterTargetFoe = function(battle)
	if not _G.F.shouldFilterEncounterTarget() or not _G.F.hasWildFoeLoaded(battle) then
		return false
	end

	local monster = _G.F.getBattleFoeMonster(battle)
	local name = _G.F.normalizeLoomianSearchName(_G.F.getEncounterFoeSpeciesName(monster))
	if name == "" then
		return false
	end

	return not _G.F.monsterMatchesSearchTarget(monster, _G.encounterTargetLoomian)
end

_G.F.isMatchingEncounterTargetFoe = function(battle)
	if not _G.F.shouldFilterEncounterTarget() or not _G.F.hasWildFoeLoaded(battle) then
		return false
	end

	local monster = _G.F.getBattleFoeMonster(battle)
	local name = _G.F.normalizeLoomianSearchName(_G.F.getEncounterFoeSpeciesName(monster))
	if name == "" then
		return false
	end

	return _G.F.monsterMatchesSearchTarget(monster, _G.encounterTargetLoomian)
end

_G.F.handleEncounterTargetMatchFound = function(battle)
	if _G.encounterTargetStopBattle == battle then
		return
	end

	_G.encounterTargetStopBattle = battle

	local foe = _G.F.getBattleFoeMonster(battle)
	local displayName = _G.F.getMonsterDisplayName(foe)
	if displayName == "" then
		displayName = _G.encounterTargetLoomian
	end

	_G.F.pauseAutoEncounterForBattle(battle, displayName, "Target", "Target Found")
end

_G.F.setAutoEncounterEnabled = function(value)
	_G.autoEncounterEnabled = value
end

_G.F.getPetrolithReviveCatalog = function()
	if _G._fossilCatalogMerged then
		return _G._fossilCatalogMerged
	end

	local catalog = {}
	for _, entry in ipairs(_G.PETROLITH_REVIVE_CATALOG) do
		table.insert(catalog, {
			id = entry.id,
			kind = entry.kind,
			speciesId = entry.speciesId,
			loomian = entry.loomian,
			fossil = entry.fossil,
			lone = entry.lone,
		})
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local constants = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Constants") or nil
	local petroliths = type(constants) == "table"
		and (_G.F.safeTableGet(constants, "PETROLITHS")
			or _G.F.safeTableGet(constants, "Petroliths")
			or _G.F.safeTableGet(constants, "petroliths")
			or _G.F.safeTableGet(constants, "Petrolith"))
		or nil

	if type(petroliths) == "table" then
		for kindKey, data in pairs(petroliths) do
			local kind = tonumber(kindKey) or (type(data) == "table" and tonumber(data.kind)) or nil
			if kind then
				local speciesId = type(data) == "table" and (tonumber(data.species) or tonumber(data.speciesId) or tonumber(data.id)) or nil
				local name = type(data) == "table" and (data.name or data.loomian or data.speciesName) or nil
				for _, entry in ipairs(catalog) do
					if entry.kind == kind or (speciesId and entry.speciesId == speciesId) then
						if speciesId then
							entry.speciesId = speciesId
						end
						if type(name) == "string" and name ~= "" then
							entry.loomian = name
						end
					end
				end
			end
		end
	end

	for _, entry in ipairs(catalog) do
		if _G.autoFossilTargetEnabled[entry.id] == nil then
			_G.autoFossilTargetEnabled[entry.id] = true
		end
	end

	_G._fossilCatalogMerged = catalog
	return catalog
end

_G.F.getPetrolithCatalogEntryByKind = function(kind)
	kind = tonumber(kind)
	if not kind then
		return nil
	end

	for _, entry in ipairs(_G.F.getPetrolithReviveCatalog()) do
		if entry.kind == kind then
			return entry
		end
	end

	return nil
end

_G.F.getPetrolithSpeciesIdSet = function()
	local set = {}
	if _G.fossilSpeciesIdSet and next(_G.fossilSpeciesIdSet) then
		for id in pairs(_G.fossilSpeciesIdSet) do
			set[id] = true
		end
		return set
	end

	for _, entry in ipairs(_G.F.getPetrolithReviveCatalog()) do
		if entry.speciesId then
			set[entry.speciesId] = true
		end
	end

	for id in pairs(_G.F.getPetrolithSpeciesIdSetFromConstants()) do
		set[id] = true
	end

	return set
end

_G.F.getPetrolithNameNeedles = function()
	local needles = {}
	for _, entry in ipairs(_G.F.getPetrolithReviveCatalog()) do
		needles[string.lower(entry.loomian)] = true
	end
	return needles
end

_G.F.tableContainsPetrolithLoomian = function(value, depth)
	if type(value) == "string" then
		local lower = string.lower(value)
		for needle in pairs(_G.F.getPetrolithNameNeedles()) do
			if string.find(lower, needle, 1, true) then
				return true
			end
		end
		return string.find(lower, "petrolith", 1, true) ~= nil
	end

	if type(value) ~= "table" or depth <= 0 then
		return false
	end

	local found = false
	pcall(function()
		for _, child in pairs(value) do
			if _G.F.tableContainsPetrolithLoomian(child, depth - 1) then
				found = true
				break
			end
		end
	end)
	return found
end

_G.F.getPetrolithSpeciesIdSetFromConstants = function()
	if _G.fossilSpeciesIdSetFromConstants and next(_G.fossilSpeciesIdSetFromConstants) then
		return _G.fossilSpeciesIdSetFromConstants
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local set = {}
	local constants = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Constants") or nil
	if type(constants) == "table" then
		for _, key in ipairs({ "MONSTERS", "monsters", "Loomians", "loomians", "DEX", "dex" }) do
			local monsterTable = _G.F.safeTableGet(constants, key)
			if type(monsterTable) == "table" then
				pcall(function()
					for id, entry in pairs(monsterTable) do
						local name = type(entry) == "table" and (entry.name or entry.n or entry.species) or entry
						if type(name) == "string" then
							local lowerName = string.lower(name)
							for _, catalogEntry in ipairs(_G.PETROLITH_REVIVE_CATALOG) do
								if lowerName == string.lower(catalogEntry.loomian) then
									local numericId = tonumber(id) or id
									set[numericId] = true
									catalogEntry.speciesId = tonumber(id) or catalogEntry.speciesId
								end
							end
						end
					end
				end)
				if next(set) then
					break
				end
			end
		end
	end

	_G.fossilSpeciesIdSetFromConstants = set
	return set
end

-- Learn real PC species ids from server summaries, like Boonary cleanup does.
_G.F.learnPetrolithSpeciesIds = function(session, forceRefresh)
	if not forceRefresh and _G.fossilSpeciesIdSet and next(_G.fossilSpeciesIdSet) then
		return _G.fossilSpeciesIdSet
	end

	local set = {}
	local keepSet = {}
	for id in pairs(_G.F.getPetrolithSpeciesIdSetFromConstants()) do
		set[id] = true
	end

	local network = _G.F.safeTableGet(_G._p, "Network")
	if type(network) ~= "table" or type(network.get) ~= "function" then
		_G.fossilSpeciesIdSet = set
		_G.fossilKeepSpeciesIdSet = keepSet
		return set
	end

	local checkedSpecies = {}
	for _, box in pairs(session.boxes) do
		if type(box) == "table" then
			for _, slot in pairs(box) do
				local unwrapped = _G.F.unwrapPcSlotData(slot)
				local speciesId = unwrapped and unwrapped.icon and tonumber(_G.F.safeArrayGet(unwrapped.icon, 1)) or nil
				local sheetType = unwrapped and unwrapped.icon and _G.F.safeArrayGet(unwrapped.icon, 2) or nil
				local labelIndex = _G.F.safeArrayGet(slot, 1)
				if speciesId and labelIndex ~= nil and not checkedSpecies[speciesId] then
					checkedSpecies[speciesId] = true
					local ok, summary = pcall(function()
						return network:get("PDS", "cPC", "getSummary", labelIndex)
					end)
					if ok and _G.F.tableContainsPetrolithLoomian(summary, 4) then
						set[speciesId] = true
						if sheetType == 8
							and (_G.F.tableContainsString(summary, "gleam", 4) or _G.F.tableContainsString(summary, "gamma", 4)) then
							keepSet[speciesId] = true
						end
					end
					task.wait(0.05)
				end
			end
		end
	end

	_G.fossilSpeciesIdSet = set
	_G.fossilKeepSpeciesIdSet = keepSet
	return set
end

_G.F.isKeepFossilRevivalPcSlot = function(unwrapped, labelIndex, slotSpeciesId)
	if type(unwrapped) ~= "table" then
		return false
	end

	local tier = _G.F.normalizeGleamTier(_G.F.safeArrayGet(unwrapped.icon, 3))
	local keepByAssetVariant = slotSpeciesId ~= nil and _G.fossilKeepSpeciesIdSet and _G.fossilKeepSpeciesIdSet[slotSpeciesId] == true
	if (tier and tier >= 1) or keepByAssetVariant then
		return true
	end

	if _G.autoFossilKeepSecretAbility then
		return _G.F.isPcSlotSecretAbility(labelIndex)
	end

	return false
end

_G.F.getFossilTargetDropdownLabel = function(entry, count)
	count = math.max(0, tonumber(count) or 0)
	return string.format("%s (%s) - %d ready", entry.loomian, entry.fossil, count)
end

_G.F.buildFossilTargetDropdownOptions = function()
	local options = { "All Loomians" }
	local counts = (_G.fossilScanResults and _G.fossilScanResults.counts) or {}

	for _, entry in ipairs(_G.F.getPetrolithReviveCatalog()) do
		table.insert(options, _G.F.getFossilTargetDropdownLabel(entry, counts[entry.kind]))
	end

	return options
end

_G.F.matchFossilTargetDropdownValue = function(value)
	if type(value) ~= "string" or value == "" or value == "All Loomians" then
		return nil
	end

	for _, entry in ipairs(_G.F.getPetrolithReviveCatalog()) do
		if value == _G.F.getFossilTargetDropdownLabel(entry, (_G.fossilScanResults.counts or {})[entry.kind])
			or string.find(value, entry.loomian .. " (", 1, true) == 1 then
			return entry
		end
	end

	return nil
end

_G.F.getAllowedFossilReviveKinds = function()
	local allowed = {}
	local selectedEntry = _G.F.matchFossilTargetDropdownValue(_G.autoFossilReviveTarget)

	if selectedEntry then
		allowed[selectedEntry.kind] = true
		return allowed
	end

	for _, entry in ipairs(_G.F.getPetrolithReviveCatalog()) do
		if _G.autoFossilTargetEnabled[entry.id] ~= false then
			allowed[entry.kind] = true
		end
	end

	return allowed
end

_G.F.countPetrolithReviveKinds = function(pieces)
	local counts = {}
	if type(pieces) ~= "table" then
		return counts
	end

	local reviveKinds = _G.F.buildPetrolithBatch(pieces, 9999, nil)
	for _, kind in ipairs(reviveKinds) do
		local numericKind = tonumber(kind)
		if numericKind then
			counts[numericKind] = (counts[numericKind] or 0) + 1
		end
	end

	return counts
end

_G.F.refreshFossilScanLabel = function()
	if not (_G.fossilScanLabel and type(_G.fossilScanLabel.Set) == "function") then
		return
	end

	local counts = (_G.fossilScanResults and _G.fossilScanResults.counts) or {}
	local parts = {}
	local total = 0

	for _, entry in ipairs(_G.F.getPetrolithReviveCatalog()) do
		local count = counts[entry.kind] or 0
		total = total + count
		if count > 0 then
			table.insert(parts, string.format("%s x%d", entry.loomian, count))
		end
	end

	local text = total > 0 and table.concat(parts, " | ") or "No complete fossil sets in bag."
	pcall(function()
		_G.fossilScanLabel:Set("Bag: " .. text)
	end)
end

_G.F.syncFossilTargetDropdown = function(forceValue)
	local options = _G.F.buildFossilTargetDropdownOptions()
	if _G.fossilTargetDropdown and type(_G.fossilTargetDropdown.Refresh) == "function" then
		pcall(function()
			_G.fossilTargetDropdown:Refresh(options, true)
		end)
	end

	local selected = forceValue or _G.autoFossilReviveTarget or "All Loomians"
	if not table.find(options, selected) then
		local matched = _G.F.matchFossilTargetDropdownValue(selected)
		if matched then
			selected = _G.F.getFossilTargetDropdownLabel(matched, (_G.fossilScanResults.counts or {})[matched.kind])
		else
			selected = "All Loomians"
		end
		_G.autoFossilReviveTarget = selected
	end

	if _G.fossilTargetDropdown and type(_G.fossilTargetDropdown.Set) == "function" then
		_G.F.setDropdownUiValue(_G.fossilTargetDropdown, selected)
	end
end

_G.F.scanFossilBag = function()
	if not _G.F.ensureP() then
		return false, "Hook is not ready."
	end

	local ok, pieces, limit = _G.F.rallyPdsGet("getPetroliths")
	if not ok then
		return false, "Could not reach the Petrolith service."
	end

	if pieces == "ns" then
		_G.fossilScanResults = { counts = {}, total = 0, scannedAt = os.clock(), careFull = true }
		_G.F.refreshFossilScanLabel()
		_G.F.syncFossilTargetDropdown()
		return false, "Loomian Care is full."
	end

	if type(pieces) ~= "table" then
		return false, "Petrolith data was not ready."
	end

	local counts = _G.F.countPetrolithReviveKinds(pieces)
	local total = 0
	for _, count in pairs(counts) do
		total = total + count
	end

	_G.fossilScanResults = {
		counts = counts,
		total = total,
		limit = tonumber(limit) or 30,
		scannedAt = os.clock(),
	}

	_G.F.refreshFossilScanLabel()
	_G.F.syncFossilTargetDropdown()
	return true, string.format("Found %d revivable Loomian(s).", total)
end

_G.F.isKeepFossilRevivalMonster = function(monster)
	if type(monster) ~= "table" then
		return false
	end

	if _G.F.isGleaming(monster) or _G.isActiveFlag(_G.F.getMonsterGleamValue(monster)) then
		return true, "Gleaming"
	end

	if _G.isActiveFlag(_G.F.getMonsterGammaValue(monster)) then
		return true, "Gamma"
	end

	local gleamTier = _G.F.getMonsterGleamTier(monster)
	if gleamTier and gleamTier >= 1 then
		return true, gleamTier == 2 and "Gamma" or "Gleaming"
	end

	if _G.autoFossilKeepSecretAbility and _G.F.isSecretAbility(monster) then
		return true, "Secret Ability"
	end

	return false
end

_G.F.isPcSlotSecretAbility = function(labelIndex)
	if not _G.autoFossilKeepSecretAbility or labelIndex == nil then
		return false
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local network = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Network") or nil
	if type(network) ~= "table" or type(network.get) ~= "function" then
		return false
	end

	local ok, summary = pcall(function()
		return network:get("PDS", "cPC", "getSummary", labelIndex)
	end)
	if not ok or type(summary) ~= "table" then
		return false
	end

	return _G.F.isSecretAbility(summary)
end

_G.F.cleanFossilRevivalPcBoxes = function(dryRun)
	local session, liveOrReason = _G.F.getPcSession()
	if not session then
		return false, tostring(liveOrReason)
	end

	local isLiveSession = liveOrReason == true

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	-- Always relearn from the current PC session; cached dex ids are unreliable.
	_G.fossilSpeciesIdSet = nil
	_G.fossilKeepSpeciesIdSet = nil
	_G._fossilCatalogMerged = nil

	local learnedIds = {}
	pcall(function()
		learnedIds = _G.F.learnPetrolithSpeciesIds(session, true)
	end)

	if not next(learnedIds) then
		if not isLiveSession then
			_G.F.closePcSession(session)
		end
		return false, "Could not identify Petrolith Loomian species ids from PC data. Open your PC once and try again."
	end

	local seen = 0
	local kept = 0
	local released = 0
	local skippedNoId = 0

	for boxKey, box in pairs(session.boxes) do
		if type(box) == "table" then
			for slotKey, slot in pairs(box) do
				local unwrapped = _G.F.unwrapPcSlotData(slot)
				local speciesId = unwrapped and unwrapped.icon and tonumber(_G.F.safeArrayGet(unwrapped.icon, 1)) or nil
				local labelIndex = _G.F.safeArrayGet(slot, 1)
				local isFossilSlot = speciesId ~= nil and learnedIds[speciesId] == true

				if not isFossilSlot and labelIndex ~= nil and speciesId ~= nil then
					local network = _G.F.safeTableGet(_G._p, "Network")
					if type(network) == "table" and type(network.get) == "function" then
						local ok, summary = pcall(function()
							return network:get("PDS", "cPC", "getSummary", labelIndex)
						end)
						if ok and _G.F.tableContainsPetrolithLoomian(summary, 4) then
							isFossilSlot = true
							learnedIds[speciesId] = true
						end
					end
				end

				if isFossilSlot then
					seen = seen + 1
					local keep = _G.F.isKeepFossilRevivalPcSlot(unwrapped, labelIndex, speciesId)

					if keep then
						kept = kept + 1
					elseif labelIndex == nil then
						skippedNoId = skippedNoId + 1
					elseif dryRun then
						released = released + 1
					else
						_G.F.journalPcRelease(session, labelIndex, boxKey, slotKey)
						released = released + 1
					end
				end
			end
		end
	end

	local commitNote = ""
	if not dryRun and released > 0 and isLiveSession then
		commitNote = " (commits when you close the PC)"
	elseif not isLiveSession then
		local ok, reason = _G.F.closePcSession(session)
		if not dryRun and released > 0 and not ok then
			return false, string.format("Saw %d fossil Loomians, kept %d, but %s", seen, kept, tostring(reason))
		end
		if not dryRun and released > 0 and ok then
			commitNote = " (committed)"
		end
	end

	local summary = string.format(
		"%sFossil PC sweep: %d species ids, %d seen, %d kept, %d %s%s.",
		dryRun and "[DRY RUN] " or "",
		(function()
			local count = 0
			for _ in pairs(learnedIds) do
				count = count + 1
			end
			return count
		end)(),
		seen,
		kept,
		released,
		dryRun and "would release" or "released",
		commitNote
	)

	return true, summary
end

_G.F.processFossilRevivalReleases = function(revivedMonsters)
	if not _G.autoFossilAutoRelease then
		return true, "Auto-release disabled."
	end

	local kept = 0
	local released = 0
	local failed = 0

	if type(revivedMonsters) == "table" then
		for index, monster in ipairs(revivedMonsters) do
			if _G.F.isKeepFossilRevivalMonster(monster) then
				kept = kept + 1
			else
				local ok = _G.F.releaseStoredMonster({ monster = monster })
				if ok then
					released = released + 1
				else
					failed = failed + 1
				end
				_G.F.setFossilStatus(string.format("Releasing extras (%d)...", released))
				task.wait(0.15)
			end
		end
	end

	_G.F.setFossilStatus("Cleaning fossil PC...")
	local pcOk, pcSummary = _G.F.cleanFossilRevivalPcBoxes(false)
	local summary = string.format(
		"Batch cleanup: kept %d, released %d, failed %d%s",
		kept,
		released,
		failed,
		pcOk and (" | " .. tostring(pcSummary)) or (" | PC sweep failed: " .. tostring(pcSummary))
	)

	return true, summary
end

_G.F.fossilNormalizeInteractKind = function(value)
	return string.lower(string.gsub(tostring(value or ""), "%s+", ""))
end

_G.F.getFossilChunkRoots = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local roots = {}
	local currentChunk = type(_G._p) == "table" and _G._p.DataManager and _G._p.DataManager.currentChunk or nil

	if type(currentChunk) == "table" and currentChunk.map then
		table.insert(roots, currentChunk.map)
	end

	if type(currentChunk) == "table" and type(currentChunk.GetMap) == "function" then
		local ok, map = pcall(function()
			return currentChunk:GetMap()
		end)

		if ok and map and map ~= currentChunk.map then
			table.insert(roots, map)
		end
	end

	return roots
end

_G.F.getFossilInteractPosition = function(model, tag)
	local main = model and (model:FindFirstChild("Main") or model:FindFirstChild("Base"))
	if main and main:IsA("BasePart") then
		return main.Position
	end

	local parent = tag and tag.Parent
	if parent and parent:IsA("BasePart") then
		return parent.Position
	end

	if model and model:IsA("Model") and model.PrimaryPart then
		return model.PrimaryPart.Position
	end

	return nil
end

_G.F.collectFossilInanimateInteracts = function()
	local entries = {}

	for _, root in ipairs(_G.F.getFossilChunkRoots()) do
		local ok, descendants = pcall(function()
			return root:GetDescendants()
		end)

		if ok then
			for _, item in ipairs(descendants) do
				if item.Name == "#InanimateInteract" and item:IsA("StringValue") then
					table.insert(entries, {
						tag = item,
						model = item.Parent,
						kind = tostring(item.Value or ""),
						position = _G.F.getFossilInteractPosition(item.Parent, item)
					})
				end
			end
		end
	end

	return entries
end

_G.F.setFossilStatus = function(text)
	_G.lastFossilBatchText = tostring(text or "Idle")

	if _G.fossilStatusLabel and type(_G.fossilStatusLabel.Set) == "function" then
		pcall(function()
			_G.fossilStatusLabel:Set("Status: " .. _G.lastFossilBatchText)
		end)
	end
end

_G.F.refreshFossilStats = function()
	if _G.fossilStatsLabel and type(_G.fossilStatsLabel.Set) == "function" then
		pcall(function()
			_G.fossilStatsLabel:Set(string.format(
				"Batches: %d | Revived: %d | Last Queued: %d",
				_G.totalFossilBatches,
				_G.totalFossilRevived,
				_G.lastFossilQueuedCount
			))
		end)
	end
end

_G.F.getPetrolithTableInfo = function()
	local root = _G.F.getRoot()
	if not root then
		return false, "Character root not ready."
	end

	local wanted = _G.F.fossilNormalizeInteractKind(_G.TARGET_PETROLITH_INTERACT)
	local bestDistance = math.huge
	local found = false

	for _, entry in ipairs(_G.F.collectFossilInanimateInteracts()) do
		if _G.F.fossilNormalizeInteractKind(entry.kind) == wanted and entry.position then
			found = true
			local distance = (root.Position - entry.position).Magnitude
			if distance < bestDistance then
				bestDistance = distance
			end
		end
	end

	if not found then
		return false, "Petrolith Table not found in this chunk."
	end

	return true, string.format("Petrolith Table nearby: %.1f studs", bestDistance)
end

_G.F.refreshPetrolithTableLabel = function()
	local found, message = _G.F.getPetrolithTableInfo()
	local text = found and message or ("Petrolith Table: " .. tostring(message))

	if _G.fossilMachineLabel and type(_G.fossilMachineLabel.Set) == "function" then
		pcall(function()
			_G.fossilMachineLabel:Set(text)
		end)
	end
end

_G.F.clearFossilNpcChat = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	if type(_G._p) ~= "table" or type(_G._p.NPCChat) ~= "table" then
		return
	end

	pcall(function()
		_G._p.NPCChat.fastForward = true
		_G._p.NPCChat.skipping = true
		_G._p.NPCChat.TextSpeedMultiplier = 100
	end)

	pcall(function()
		if type(_G._p.NPCChat.isChatting) == "function"
			and _G._p.NPCChat:isChatting()
			and type(_G._p.NPCChat.clear) == "function" then
			_G._p.NPCChat:clear()
		end
	end)

	pcall(function()
		if type(_G._p.NPCChat.manualAdvance) == "function" then
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

_G.F.getFossilMonsterDisplayName = function(monster, index)
	if type(monster) ~= "table" then
		return "Revive " .. tostring(index)
	end

	local summary = _G.F.safeTableGet(monster, "summ")
	if type(summary) == "table" then
		local nickname = _G.F.safeTableGet(summary, "nickname")
		if type(nickname) == "string" and nickname ~= "" then
			return nickname
		end

		local name = _G.F.safeTableGet(summary, "name")
		if type(name) == "string" and name ~= "" then
			return name
		end
	end

	for _, key in ipairs({ "nickname", "name", "species", "id" }) do
		local value = _G.F.safeTableGet(monster, key)
		if value ~= nil and tostring(value) ~= "" then
			return tostring(value)
		end
	end

	return "Revive " .. tostring(index)
end

_G.F.processFossilReviveFollowUps = function(entries)
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	if type(entries) ~= "table" or type(_G._p) ~= "table" or type(_G._p.Monster) ~= "table" then
		return
	end

	local processor = _G.F.safeTableGet(_G._p.Monster, "processMovesAndEvolution")
	if type(processor) ~= "function" then
		return
	end

	for _, entry in ipairs(entries) do
		pcall(function()
			processor(_G._p.Monster, entry, true)
		end)
	end
end

_G.F.planFossilRegularSet = function(subcountByKey, orderedKeys)
	local reviveCount = 0

	while true do
		local chosen = {}

		for _, key in ipairs(orderedKeys) do
			if (subcountByKey[key] or 0) > 0 then
				table.insert(chosen, key)
			end

			if #chosen >= 3 then
				break
			end
		end

		if #chosen < 3 then
			break
		end

		for _, key in ipairs(chosen) do
			subcountByKey[key] = subcountByKey[key] - 1
		end

		reviveCount = reviveCount + 1
	end

	return reviveCount
end

_G.F.buildPetrolithBatch = function(pieces, limit, allowedKinds)
	local reviveKinds = {}
	local groupedKinds = {}
	local groupedOrder = {}

	local function kindAllowed(kind)
		if allowedKinds == nil then
			return true
		end
		return allowedKinds[tonumber(kind)] == true
	end

	local function tryInsertKind(kind)
		if not kindAllowed(kind) then
			return false
		end
		if #reviveKinds >= limit then
			return false
		end
		table.insert(reviveKinds, kind)
		return true
	end

	for _, piece in ipairs(pieces) do
		local qty = math.max(0, tonumber(piece.qty) or 0)
		local kind = piece.kind

		if qty > 0 and kind ~= nil then
			if piece.lone then
				for _ = 1, qty do
					if not tryInsertKind(kind) then
						return reviveKinds
					end
				end
			else
				local kindKey = tostring(kind)
				local group = groupedKinds[kindKey]
				if not group then
					group = {
						kind = kind,
						subcountByKey = {},
						orderedKeys = {}
					}
					groupedKinds[kindKey] = group
					table.insert(groupedOrder, group)
				end

				local subkey = string.lower(tostring(piece.subkind or ""))
				if subkey ~= "" then
					if group.subcountByKey[subkey] == nil then
						group.subcountByKey[subkey] = 0
						table.insert(group.orderedKeys, subkey)
					end

					group.subcountByKey[subkey] = group.subcountByKey[subkey] + qty
				end
			end
		end
	end

	for _, group in ipairs(groupedOrder) do
		if #reviveKinds >= limit then
			break
		end

		if tonumber(group.kind) == 6 then
			local subcountByKey = group.subcountByKey
			local aCount = subcountByKey.a or 0
			local bCount = subcountByKey.b or 0
			local cCount = subcountByKey.c or 0
			local dCount = subcountByKey.d or 0

			while #reviveKinds < limit and aCount > 0 and bCount > 0 and (cCount > 0 or dCount > 0) do
				-- Yutiny (kind 6) needs a+b+c, Venile (kind 7) needs a+b+d and they
				-- share the a/b skull pieces. When only one twin is selected, prefer
				-- its variant so an unselected sibling never blocks it, and just
				-- discard the sibling-only piece instead of breaking the whole loop.
				local useC
				if cCount > 0 and dCount > 0 then
					useC = kindAllowed(group.kind) or not kindAllowed(7)
				else
					useC = cCount > 0
				end

				local variantKind = useC and group.kind or 7

				if kindAllowed(variantKind) then
					aCount = aCount - 1
					bCount = bCount - 1
					if useC then
						cCount = cCount - 1
					else
						dCount = dCount - 1
					end
					if not tryInsertKind(variantKind) then
						break
					end
				elseif useC then
					cCount = cCount - 1
				else
					dCount = dCount - 1
				end
			end
		else
			local subcountByKey = {}
			for key, value in pairs(group.subcountByKey) do
				subcountByKey[key] = value
			end

			local plannedCount = _G.F.planFossilRegularSet(subcountByKey, group.orderedKeys)
			for _ = 1, plannedCount do
				if not tryInsertKind(group.kind) then
					break
				end
			end
		end
	end

	return reviveKinds
end

_G.F.runAutoFossil = function()
	if _G.fossilBusy then
		return false, "Auto Fossil is already running."
	end

	_G.fossilBusy = true
	_G.F.setFossilStatus("Scanning Petrolith inventory...")

	local scanOk, scanReason = _G.F.scanFossilBag()
	if not scanOk and scanReason and scanReason ~= "Loomian Care is full." then
		_G.fossilBusy = false
		_G.F.setFossilStatus(scanReason)
		return false, scanReason
	end

	local ok, pieces, limit = _G.F.rallyPdsGet("getPetroliths")
	if not ok then
		_G.fossilBusy = false
		_G.F.setFossilStatus("Could not reach the Petrolith service.")
		return false, "Could not reach the Petrolith service."
	end

	if pieces == "ns" then
		_G.fossilBusy = false
		_G.F.setFossilStatus("Loomian Care is full.")
		return false, "Loomian Care is full. Make space before reviving more Petroliths."
	end

	if type(pieces) ~= "table" then
		_G.fossilBusy = false
		_G.F.setFossilStatus("Petrolith data was not ready.")
		return false, "Petrolith data was not ready."
	end

	local numericLimit = math.max(1, tonumber(limit) or (_G.fossilScanResults and _G.fossilScanResults.limit) or 30)
	local allowedKinds = _G.F.getAllowedFossilReviveKinds()
	local reviveKinds = _G.F.buildPetrolithBatch(pieces, numericLimit, allowedKinds)
	_G.lastFossilQueuedCount = #reviveKinds
	_G.F.refreshFossilStats()

	if #reviveKinds == 0 then
		-- Every selected fossil is revived. If Auto Fossil is running and revived at
		-- least one Loomian since the last sweep, run a single PC clean automatically.
		if _G.autoFossilEnabled and _G.autoFossilRevivedSinceClean then
			_G.autoFossilRevivedSinceClean = false
			_G.F.setFossilStatus("All selected fossils revived. Cleaning PC...")

			local cleanOk, cleanSummary = false, nil
			pcall(function()
				cleanOk, cleanSummary = _G.F.cleanFossilRevivalPcBoxes(false)
			end)

			_G.fossilBusy = false
			if cleanOk then
				_G.F.setFossilStatus("All revived | " .. tostring(cleanSummary))
			else
				_G.F.setFossilStatus("All revived. PC clean did not complete.")
			end
			return false, "No complete Petrolith sets found."
		end

		_G.fossilBusy = false
		_G.F.setFossilStatus("No complete Petrolith sets found.")
		return false, "No complete Petrolith sets found."
	end

	_G.F.setFossilStatus(string.format("Reviving %d set(s)...", #reviveKinds))

	local reviveOk, revivedMonsters, partyCount, careCount, followUps = _G.F.rallyPdsGet("revivePetroliths", reviveKinds)
	if not reviveOk then
		_G.fossilBusy = false
		_G.F.setFossilStatus("revivePetroliths failed.")
		return false, "revivePetroliths failed."
	end

	if type(revivedMonsters) ~= "table" then
		_G.fossilBusy = false
		_G.F.setFossilStatus("The Petrolith revive returned no results.")
		return false, "The Petrolith revive returned no results."
	end

	-- The revive RPC has already returned, so the fossils are revived in-game at
	-- this point. The follow-up move/evolution handling, auto-release, and PC
	-- cleanup below can take many seconds (the PC sweep makes a blocking network
	-- call per unidentified slot), so surface the result and update stats now
	-- instead of leaving the label stuck on "Reviving..." until they finish.
	local revivedCount = #revivedMonsters
	local revivedNames = {}

	for index, monster in ipairs(revivedMonsters) do
		table.insert(revivedNames, _G.F.getFossilMonsterDisplayName(monster, index))
	end

	_G.totalFossilBatches = _G.totalFossilBatches + 1
	_G.totalFossilRevived = _G.totalFossilRevived + revivedCount
	_G.F.refreshFossilStats()

	if revivedCount > 0 then
		_G.autoFossilRevivedSinceClean = true
	end

	local partyValue = tonumber(partyCount) or 0
	local careValue = tonumber(careCount) or 0
	local storageText = ""

	if partyValue > 0 or careValue > 0 then
		storageText = string.format(" | Party: %d | Care: %d", partyValue, careValue)
	end

	if _G.autoFossilAutoRelease then
		_G.F.setFossilStatus(string.format("Revived %d Loomian(s)%s | Cleaning up...", revivedCount, storageText))
	else
		_G.F.setFossilStatus(string.format("Revived %d Loomian(s)%s", revivedCount, storageText))
	end

	_G.F.processFossilReviveFollowUps(followUps)
	_G.F.clearFossilNpcChat()

	local releaseOk, releaseSummary = _G.F.processFossilRevivalReleases(revivedMonsters)

	local shortList = revivedCount > 0 and table.concat(revivedNames, ", ") or "Unknown result"
	if #shortList > 150 then
		shortList = string.sub(shortList, 1, 147) .. "..."
	end

	_G.fossilBusy = false
	if releaseOk and releaseSummary then
		_G.F.setFossilStatus(string.format("Revived %d | %s", revivedCount, releaseSummary))
	else
		_G.F.setFossilStatus(string.format("Revived %d Loomian(s)%s", revivedCount, storageText))
	end
	_G.OrionLib:MakeNotification({
		Name = "Auto Fossil",
		Content = shortList,
		Time = 7,
	})

	return true, string.format("Revived %d Loomian(s)%s", revivedCount, storageText)
end

_G.F.disableAllFeatures = function()
	_G.autoEncounterEnabled = false
	_G.autoEncounterPausedBattle = nil
	_G.autoEncounterPausedDisplayName = nil
	_G.autoEncounterPausedReason = nil
	_G.autoCatchEnabled = false
	_G.F.setAutoFishingEnabled(false)
	_G.autoBringEnabled = false
	_G.autoRallyEnabled = false
	_G.autoTrainerEnabled = false
	_G.autoMoveOneEnabled = false
	_G.autoFossilEnabled = false
	_G.autoDiscDropEnabled = false
	_G.autoBoonaryEnabled = false
	_G.autoBoonaryBusy = false
	_G.autoBoonaryTriggered = false
	_G.F.setWallSparkleUmvEnabled(false)
	_G.F.setUmvMiningRevealEnabled(false)
	_G.F.setRemoteSparkleMineEnabled(false)
	_G.F.setCtrlClickTpEnabled(false)
	_G.F.setAntiAfkEnabled(false)
	_G.autoHealEnabled = false
	_G.activeRepellentEnabled = false
	_G.skipDialogueEnabled = false
	_G.denyReassignMoveEnabled = false
	_G.denySwitchRequestEnabled = false
	_G.denyNicknameEnabled = false
	_G.disableShowProgressEnabled = false
	_G.F.setAutoBattleEnabled(false)
	_G.F.jackSetAutoMove("Disabled")
	_G.F.jackSetAutoTrainer("Disabled")
	_G.noUnstuckCooldownEnabled = false
	_G.naturalRunPausedSpecialBattle = nil
	_G.encounterTargetStopBattle = nil
	if _G.StaticAutomation then
		_G.StaticAutomation:setEnabled(false)
	end
	_G.arcerosAutoEnabled = false
	if _G.CatchAutomation then
		_G.CatchAutomation:resetState()
	end
	if _G.ArcadeAutomation then
		_G.ArcadeAutomation:stopAll()
	end
	if _G.savingDisabled then
		_G.F.setSavingDisabled(false)
	end
	_G.F.clearAllBattleFastForward()
	_G.F.restoreJackStyleGameplayHooks()
end

_G.CONFIG_VERSION = 1
_G.CONFIG_AUTOSAVE_FILE = "config.json"
_G.configProfileName = "default"
_G.configUi = {}
_G.applyingConfig = false

_G.CONFIG_DIR = "LLSPLOIT"

_G.F.getConfigDirectory = function()
	if type(os) == "table" and type(os.getenv) == "function" then
		local localAppData = os.getenv("LOCALAPPDATA") or os.getenv("LocalAppData")
		if localAppData and localAppData ~= "" then
			return localAppData .. "\\Potassium\\workspace\\LLSPLOIT"
		end
	end
	return _G.CONFIG_DIR
end

_G.F.sanitizeConfigName = function(name)
	name = tostring(name or "default")
	name = string.gsub(name, "[^%w%-_ ]", "")
	name = string.gsub(name, "^%s*(.-)%s*$", "%1")
	if name == "" then
		name = "default"
	end
	return name
end

_G.F.ensureConfigDirectory = function()
	local dir = _G.F.getConfigDirectory()
	if not makefolder or not isfolder then
		return dir
	end

	pcall(function()
		if isfolder(dir) then
			return
		end

		makefolder(dir)
		if isfolder(dir) then
			return
		end

		local accumulated = ""
		local useBackslash = string.find(dir, "\\", 1, true) ~= nil
		for segment in string.gmatch(dir, "[^/\\]+") do
			if accumulated == "" then
				accumulated = segment
			elseif useBackslash then
				accumulated = accumulated .. "\\" .. segment
			else
				accumulated = accumulated .. "/" .. segment
			end
			if not isfolder(accumulated) then
				makefolder(accumulated)
			end
		end
	end)

	return dir
end

_G.F.getConfigFilePath = function(fileName)
	local dir = _G.F.ensureConfigDirectory()
	if string.find(dir, "\\", 1, true) then
		return dir .. "\\" .. fileName
	end
	return dir .. "/" .. fileName
end

_G.F.getGoppieFormesText = function()
	if #_G.GOPPIE_FORMES == 0 then
		return ""
	end

	return table.concat(_G.GOPPIE_FORMES, ", ")
end

_G.F.syncGoppieFormesTextbox = function()
	if not _G.goppieFormesTextbox then
		return
	end

	local text = _G.F.getGoppieFormesText()
	if type(_G.goppieFormesTextbox.Set) == "function" then
		_G.goppieFormesTextbox:Set(text)
	elseif _G.goppieFormesTextbox.Instance then
		pcall(function()
			_G.goppieFormesTextbox.Instance.Text = text
		end)
	end
end

_G.F.saveGoppieFormesToFile = function(silent)
	if not writefile then
		if not silent then
			warn("[Goppie Formes] writefile is not available in this executor.")
		end
		return false, "writefile unavailable"
	end

	_G.F.ensureConfigDirectory()

	local payload = {
		version = 1,
		formes = _G.GOPPIE_FORMES,
	}

	local ok, encoded = pcall(function()
		return _G.HttpService:JSONEncode(payload)
	end)
	if not ok then
		if not silent then
			warn("[Goppie Formes] Failed to encode save data.")
		end
		return false, "encode failed"
	end

	local path = _G.F.getConfigFilePath(_G.GOPPIE_FORMES_FILE)
	local writeOk, writeErr = pcall(function()
		writefile(path, encoded)
	end)
	if not writeOk then
		if not silent then
			warn("[Goppie Formes] Failed to save: " .. tostring(writeErr))
		end
		return false, tostring(writeErr)
	end

	if not silent then
		pcall(function()
			_G.OrionLib:MakeNotification({
				Name = "Goppie Formes",
				Content = "Saved to " .. path,
				Time = 4,
			})
		end)
	end

	return true
end

_G.F.loadGoppieFormesFromFile = function()
	if not readfile or not isfile then
		return false
	end

	local path = _G.F.getConfigFilePath(_G.GOPPIE_FORMES_FILE)
	if not isfile(path) then
		return false
	end

	local readOk, contents = pcall(function()
		return readfile(path)
	end)
	if not readOk or type(contents) ~= "string" or contents == "" then
		return false
	end

	local decodeOk, data = pcall(function()
		return _G.HttpService:JSONDecode(contents)
	end)
	if not decodeOk or type(data) ~= "table" then
		return false
	end

	local formes = data.formes
	if type(formes) ~= "table" then
		return false
	end

	_G.GOPPIE_FORMES = {}
	for _, entry in ipairs(formes) do
		if _G.F.isMeaningfulFormeValue(entry) then
			table.insert(_G.GOPPIE_FORMES, tostring(entry))
		end
	end

	_G.F.rebuildExcludedFormes()
	return true
end

_G.F.setGoppieFormesFromText = function(text)
	local entries = {}

	for part in string.gmatch(tostring(text or ""), "[^,]+") do
		local trimmed = string.gsub(part, "^%s*(.-)%s*$", "%1")
		if trimmed ~= "" then
			table.insert(entries, trimmed)
		end
	end

	_G.GOPPIE_FORMES = entries
	_G.F.rebuildExcludedFormes()
	_G.F.saveGoppieFormesToFile(true)
end

_G.F.addGoppieForme = function(value)
	if not _G.F.isMeaningfulFormeValue(value) then
		return false
	end

	if _G.F.isGoppieFormeSaved(value) then
		return false
	end

	table.insert(_G.GOPPIE_FORMES, tostring(value))
	_G.F.rebuildExcludedFormes()
	local saved = _G.F.saveGoppieFormesToFile(true)
	_G.F.syncGoppieFormesTextbox()
	if not saved then
		warn("[Goppie Formes] Added " .. tostring(value) .. " in memory but file save failed.")
	end
	return true
end

_G.F.registerCaughtGoppieFormeFromBattle = function(battle)
	if type(battle) ~= "table" then
		return false
	end

	local foe = _G.F.getBattleFoeMonster(battle)
	local formeValue = _G.F.getFishingGoppieFormeValue(battle)
	if not _G.F.isMeaningfulFormeValue(formeValue) then
		return false
	end

	if not _G.F.isGoppieMonster(foe) and not _G.F.isFishingGoppieBattle(battle) then
		return false
	end

	_G.lastAutoFishingGoppieForme = formeValue
	_G.lastAutoFishingGoppieFormeAt = os.clock()

	if _G.F.isGoppieFormeSaved(formeValue) then
		return true
	end

	local added = _G.F.addGoppieForme(formeValue)
	if added then
		pcall(function()
			_G.OrionLib:MakeNotification({
				Name = "Goppie Formes",
				Content = "Saved caught forme: " .. tostring(formeValue),
				Time = 4,
			})
		end)
	end

	return added
end

_G.F.setToggleUi = function(toggle, value)
	if type(toggle) == "table" and type(toggle.Set) == "function" then
		toggle:Set(value and true or false)
	end
end

_G.F.setSliderUi = function(slider, value)
	if type(slider) == "table" and type(slider.Set) == "function" then
		slider:Set(tonumber(value) or slider.Value)
	end
end

_G.F.configBool = function(value, fallback)
	if value == nil then
		return fallback and true or false
	end
	if type(value) == "boolean" then
		return value
	end
	if type(value) == "number" then
		return value ~= 0
	end
	if type(value) == "string" then
		local normalized = string.lower(value)
		if normalized == "true" or normalized == "1" or normalized == "yes" or normalized == "on" then
			return true
		end
		if normalized == "false" or normalized == "0" or normalized == "no" or normalized == "off" then
			return false
		end
	end
	return fallback and true or false
end

_G.F.getToggleConfigValue = function(toggle, fallback)
	if type(toggle) == "table" and toggle.Value ~= nil then
		return toggle.Value and true or false
	end
	return fallback and true or false
end

_G.F.collectConfigSnapshot = function()
	return {
		version = _G.CONFIG_VERSION,
		profile = _G.configProfileName,
		staticInteractTarget = _G.staticInteractTarget,
		beastTarget = _G.F.getSelectedBeastName(),
		autoStaticEnabled = _G.F.getToggleConfigValue(_G.configUi.autoStaticToggle, _G.StaticAutomation and _G.StaticAutomation:isEnabled() or false),
		autoArcerosEnabled = _G.F.getToggleConfigValue(_G.configUi.autoArcerosToggle, _G.arcerosAutoEnabled),
		jackAutoBattleMove = _G.jackAutoBattle.Move,
		jackAutoBattleTrainer = _G.jackAutoBattle.Trainer,
		autoRallyEnabled = _G.F.getToggleConfigValue(_G.configUi.autoRallyToggle, _G.autoRallyEnabled),
		rallyDelay = _G.rallyDelay,
		keepGleaming = _G.F.getToggleConfigValue(_G.configUi.keepGleamingToggle, _G.keepGleaming),
		keepSecretAbility = _G.F.getToggleConfigValue(_G.configUi.keepSecretAbilityToggle, _G.keepSecretAbility),
		keepAll = _G.F.getToggleConfigValue(_G.configUi.keepAllToggle, _G.keepAll),
		alwaysKeepText = _G.alwaysKeepText,
		autoEncounterEnabled = _G.F.getToggleConfigValue(_G.configUi.autoEncounterToggle, _G.autoEncounterEnabled),
		encounterTargetLoomian = _G.encounterTargetLoomian,
		autoEncounterDelay = _G.autoEncounterDelay,
		autoCatchEnabled = _G.F.getToggleConfigValue(_G.configUi.autoCatchToggle, _G.autoCatchEnabled),
		autoCatchDisc = _G.autoCatchDisc,
		stopOnGleaming = _G.F.getToggleConfigValue(_G.configUi.stopOnGleamingToggle, _G.stopOnGleaming),
		stopOnGamma = _G.F.getToggleConfigValue(_G.configUi.stopOnGammaToggle, _G.stopOnGamma),
		stopOnWisp = _G.F.getToggleConfigValue(_G.configUi.stopOnWispToggle, _G.stopOnWisp),
		autoFossilEnabled = _G.F.getToggleConfigValue(_G.configUi.autoFossilToggle, _G.autoFossilEnabled),
		autoFossilDelay = _G.autoFossilDelay,
		autoFossilAutoRelease = _G.autoFossilAutoRelease,
		autoFossilKeepSecretAbility = _G.autoFossilKeepSecretAbility,
		autoFossilReviveTarget = _G.autoFossilReviveTarget,
		autoFossilTargetEnabled = _G.autoFossilTargetEnabled,
		autoDiscDropEnabled = _G.F.getToggleConfigValue(_G.configUi.autoDiscDropToggle, _G.autoDiscDropEnabled),
		discDropHighScore = _G.discDropHighScore,
		discDropMaxScore = _G.discDropMaxScore,
		discDropForceFinishTime = _G.discDropForceFinishTime,
		autoBoonaryEnabled = _G.F.getToggleConfigValue(_G.configUi.autoBoonaryToggle, _G.autoBoonaryEnabled),
		autoBoonaryTixThreshold = _G.autoBoonaryTixThreshold,
		autoBoonaryGroup = _G.autoBoonaryGroup,
		autoFishingEnabled = _G.F.getToggleConfigValue(_G.configUi.autoFishingToggle, _G.autoFishingEnabled),
		autoFishingDelay = _G.autoFishingDelay,
		fastForwardEnabled = _G.F.getToggleConfigValue(_G.configUi.fastForwardToggle, _G.fastForwardEnabled),
		ctrlClickTpEnabled = _G.F.getToggleConfigValue(_G.configUi.ctrlClickTpToggle, _G.ctrlClickTpEnabled),
		antiAfkEnabled = _G.F.getToggleConfigValue(_G.configUi.antiAfkToggle, _G.antiAfkEnabled),
		autoHealEnabled = _G.F.getToggleConfigValue(_G.configUi.autoHealToggle, _G.autoHealEnabled),
		autoHealDelay = _G.autoHealDelay,
		activeRepellentEnabled = _G.F.getToggleConfigValue(_G.configUi.activeRepellentToggle, _G.activeRepellentEnabled),
		activeRepellentDelay = _G.activeRepellentDelay,
		skipDialogueEnabled = _G.F.getToggleConfigValue(_G.configUi.skipDialogueToggle, _G.skipDialogueEnabled),
		denyReassignMoveEnabled = _G.F.getToggleConfigValue(_G.configUi.denyReassignMoveToggle, _G.denyReassignMoveEnabled),
		denySwitchRequestEnabled = _G.F.getToggleConfigValue(_G.configUi.denySwitchRequestToggle, _G.denySwitchRequestEnabled),
		denyNicknameEnabled = _G.F.getToggleConfigValue(_G.configUi.denyNicknameToggle, _G.denyNicknameEnabled),
		disableShowProgressEnabled = _G.F.getToggleConfigValue(_G.configUi.disableShowProgressToggle, _G.disableShowProgressEnabled),
		autoBattleEnabled = _G.F.getToggleConfigValue(_G.configUi.autoBattleToggle, _G.autoBattleEnabled),
		noUnstuckCooldownEnabled = _G.F.getToggleConfigValue(_G.configUi.noUnstuckCooldownToggle, _G.noUnstuckCooldownEnabled),
	}
end

_G.F.applyConfigVariables = function(data)
	if type(data) ~= "table" then
		return false, "Invalid config data."
	end

	if data.autoStaticEnabled ~= nil and _G.StaticAutomation then
		_G.StaticAutomation:setEnabled(_G.F.configBool(data.autoStaticEnabled, false))
	end

	if data.autoArcerosEnabled ~= nil then
		_G.arcerosAutoEnabled = _G.F.configBool(data.autoArcerosEnabled, false)
	end

	if data.beastTarget ~= nil and _G.BEAST_HUNTS[tostring(data.beastTarget)] then
		_G.beastTarget = tostring(data.beastTarget)
	end

	if data.staticInteractTarget ~= nil then
		_G.staticInteractTarget = string.gsub(tostring(data.staticInteractTarget), "^%s*(.-)%s*$", "%1")
	end

	if data.jackAutoBattleMove ~= nil then
		_G.F.jackSetAutoMove(tostring(data.jackAutoBattleMove))
	elseif data.autoMoveOneEnabled ~= nil or data.autoMoveSlot ~= nil then
		if _G.F.configBool(data.autoMoveOneEnabled, false) then
			local slot = math.clamp(math.floor(tonumber(data.autoMoveSlot) or _G.autoMoveSlot or 1), 1, 4)
			_G.F.jackSetAutoMove("Move " .. tostring(slot))
		else
			_G.F.jackSetAutoMove("Disabled")
		end
	end

	if data.jackAutoBattleTrainer ~= nil then
		_G.F.jackSetAutoTrainer(tostring(data.jackAutoBattleTrainer))
	elseif data.autoTrainerEnabled ~= nil and not _G.F.configBool(data.autoTrainerEnabled, false) then
		_G.F.jackSetAutoTrainer("Disabled")
	end

	if data.autoRallyEnabled ~= nil then
		_G.autoRallyEnabled = _G.F.configBool(data.autoRallyEnabled, false)
	end

	if data.rallyDelay ~= nil then
		_G.rallyDelay = tonumber(data.rallyDelay) or _G.rallyDelay
	end

	if data.keepGleaming ~= nil then
		_G.keepGleaming = _G.F.configBool(data.keepGleaming, _G.keepGleaming)
	end

	if data.keepSecretAbility ~= nil then
		_G.keepSecretAbility = _G.F.configBool(data.keepSecretAbility, _G.keepSecretAbility)
	end

	if data.keepAll ~= nil then
		_G.keepAll = _G.F.configBool(data.keepAll, _G.keepAll)
	end

	if data.alwaysKeepText ~= nil then
		_G.F.setAlwaysKeepList(data.alwaysKeepText)
	end

	if data.autoEncounterEnabled ~= nil then
		_G.F.setAutoEncounterEnabled(_G.F.configBool(data.autoEncounterEnabled, false))
	end

	if data.encounterTargetLoomian ~= nil then
		_G.encounterTargetLoomian = string.gsub(tostring(data.encounterTargetLoomian), "^%s*(.-)%s*$", "%1")
	end

	if data.autoEncounterDelay ~= nil then
		_G.autoEncounterDelay = tonumber(data.autoEncounterDelay) or _G.autoEncounterDelay
	end

	if data.autoCatchEnabled ~= nil then
		_G.F.setAutoCatchEnabled(_G.F.configBool(data.autoCatchEnabled, false))
	end

	if data.autoCatchDisc ~= nil then
		_G.autoCatchDisc = string.gsub(tostring(data.autoCatchDisc), "^%s*(.-)%s*$", "%1")
	end

	if data.stopOnGleaming ~= nil then
		_G.stopOnGleaming = _G.F.configBool(data.stopOnGleaming, _G.stopOnGleaming)
	end

	if data.stopOnGamma ~= nil then
		_G.stopOnGamma = _G.F.configBool(data.stopOnGamma, _G.stopOnGamma)
	end

	if data.stopOnWisp ~= nil then
		_G.stopOnWisp = _G.F.configBool(data.stopOnWisp, _G.stopOnWisp)
	end

	if data.autoFossilEnabled ~= nil then
		_G.autoFossilEnabled = _G.F.configBool(data.autoFossilEnabled, false)
	end

	if data.autoFossilDelay ~= nil then
		_G.autoFossilDelay = tonumber(data.autoFossilDelay) or _G.autoFossilDelay
	end

	if data.autoFossilAutoRelease ~= nil then
		_G.autoFossilAutoRelease = _G.F.configBool(data.autoFossilAutoRelease, _G.autoFossilAutoRelease)
	end

	if data.autoFossilKeepSecretAbility ~= nil then
		_G.autoFossilKeepSecretAbility = _G.F.configBool(data.autoFossilKeepSecretAbility, _G.autoFossilKeepSecretAbility)
	end

	if data.autoFossilReviveTarget ~= nil then
		_G.autoFossilReviveTarget = tostring(data.autoFossilReviveTarget)
	end

	if type(data.autoFossilTargetEnabled) == "table" then
		for key, value in pairs(data.autoFossilTargetEnabled) do
			_G.autoFossilTargetEnabled[tostring(key)] = _G.F.configBool(value, true)
		end
	end

	if data.autoDiscDropEnabled ~= nil then
		_G.autoDiscDropEnabled = _G.F.configBool(data.autoDiscDropEnabled, false)
	end

	if data.discDropHighScore ~= nil then
		local parsed = tonumber(data.discDropHighScore)
		if parsed and parsed >= 0 then
			_G.discDropHighScore = math.floor(parsed)
		end
	end

	if data.discDropMaxScore ~= nil then
		if data.discDropMaxScore == false or data.discDropMaxScore == "" then
			_G.discDropMaxScore = nil
		else
			local parsed = tonumber(data.discDropMaxScore)
			if parsed and parsed > 0 then
				_G.discDropMaxScore = math.floor(parsed)
			elseif parsed == 0 then
				_G.discDropMaxScore = nil
			end
		end
	end

	if data.discDropForceFinishTime ~= nil then
		if data.discDropForceFinishTime == false or data.discDropForceFinishTime == "" then
			_G.discDropForceFinishTime = nil
		else
			local parsed = tonumber(data.discDropForceFinishTime)
			if parsed and parsed >= 0 then
				_G.discDropForceFinishTime = math.floor(parsed)
			end
		end
	end

	if data.autoBoonaryEnabled ~= nil then
		_G.F.setAutoBoonaryEnabled(_G.F.configBool(data.autoBoonaryEnabled, false))
	end

	if data.autoBoonaryTixThreshold ~= nil then
		local parsed = tonumber(data.autoBoonaryTixThreshold)
		if parsed and parsed > 0 then
			_G.autoBoonaryTixThreshold = math.floor(parsed)
		end
	end

	if data.autoBoonaryGroup ~= nil then
		local parsed = tonumber(data.autoBoonaryGroup)
		if parsed and parsed > 0 then
			_G.autoBoonaryGroup = math.floor(parsed)
		end
	end


	if data.wallSparkleUmvEnabled ~= nil then
		_G.F.setWallSparkleUmvEnabled(_G.F.configBool(data.wallSparkleUmvEnabled, false))
	end

	if data.umvMiningRevealEnabled ~= nil then
		_G.F.setUmvMiningRevealEnabled(_G.F.configBool(data.umvMiningRevealEnabled, false))
	end

	if data.remoteSparkleMineEnabled ~= nil then
		_G.F.setRemoteSparkleMineEnabled(_G.F.configBool(data.remoteSparkleMineEnabled, false))
	elseif data.remoteMineClickEnabled ~= nil then
		_G.F.setRemoteSparkleMineEnabled(_G.F.configBool(data.remoteMineClickEnabled, false))
	end

	if data.autoFishingEnabled ~= nil then
		_G.F.setAutoFishingEnabled(_G.F.configBool(data.autoFishingEnabled, false))
	end

	if data.autoFishingDelay ~= nil then
		_G.autoFishingDelay = tonumber(data.autoFishingDelay) or _G.autoFishingDelay
	end


	if data.fastForwardEnabled ~= nil then
		_G.F.setFastForwardEnabled(_G.F.configBool(data.fastForwardEnabled, false))
	end

	if data.ctrlClickTpEnabled ~= nil then
		_G.F.setCtrlClickTpEnabled(_G.F.configBool(data.ctrlClickTpEnabled, false))
	end

	if data.antiAfkEnabled ~= nil then
		_G.F.setAntiAfkEnabled(_G.F.configBool(data.antiAfkEnabled, false))
	end

	if data.autoHealEnabled ~= nil then
		_G.autoHealEnabled = _G.F.configBool(data.autoHealEnabled, false)
	end
	if data.autoHealDelay ~= nil then
		_G.autoHealDelay = tonumber(data.autoHealDelay) or _G.autoHealDelay
	end
	if data.activeRepellentEnabled ~= nil then
		_G.activeRepellentEnabled = _G.F.configBool(data.activeRepellentEnabled, false)
	end
	if data.activeRepellentDelay ~= nil then
		_G.activeRepellentDelay = tonumber(data.activeRepellentDelay) or _G.activeRepellentDelay
	end
	if data.skipDialogueEnabled ~= nil then
		_G.skipDialogueEnabled = _G.F.configBool(data.skipDialogueEnabled, false)
	end
	if data.denyReassignMoveEnabled ~= nil then
		_G.denyReassignMoveEnabled = _G.F.configBool(data.denyReassignMoveEnabled, false)
	end
	if data.denySwitchRequestEnabled ~= nil then
		_G.denySwitchRequestEnabled = _G.F.configBool(data.denySwitchRequestEnabled, false)
	end
	if data.denyNicknameEnabled ~= nil then
		_G.denyNicknameEnabled = _G.F.configBool(data.denyNicknameEnabled, false)
	end
	if data.disableShowProgressEnabled ~= nil then
		_G.disableShowProgressEnabled = _G.F.configBool(data.disableShowProgressEnabled, false)
	end
	if data.autoBattleEnabled ~= nil then
		_G.F.setAutoBattleEnabled(_G.F.configBool(data.autoBattleEnabled, false))
	end
	if data.noUnstuckCooldownEnabled ~= nil then
		_G.noUnstuckCooldownEnabled = _G.F.configBool(data.noUnstuckCooldownEnabled, false)
	end

	return true
end

_G.F.syncConfigUiFromVariables = function()
	if not _G.configUi.autoStaticToggle then
		return
	end

	_G.applyingConfig = true
	_G.F.setToggleUi(_G.configUi.autoStaticToggle, _G.StaticAutomation:isEnabled())
	if _G.configUi.autoArcerosToggle then
		_G.F.setToggleUi(_G.configUi.autoArcerosToggle, _G.arcerosAutoEnabled)
	end
	if _G.configUi.beastTargetDropdown and type(_G.configUi.beastTargetDropdown.Set) == "function" then
		pcall(function()
			_G.configUi.beastTargetDropdown:Set(_G.F.getSelectedBeastName())
		end)
	end
	if _G.configUi.jackMoveDropdown and type(_G.configUi.jackMoveDropdown.Set) == "function" then
		pcall(function()
			_G.F.jackSyncMoveDropdown(_G.jackAutoBattle.Move)
		end)
	end
	_G.F.jackSyncTrainerDropdown(_G.jackAutoBattle.Trainer)
	_G.F.setToggleUi(_G.configUi.autoRallyToggle, _G.autoRallyEnabled)
	_G.F.setSliderUi(_G.configUi.rallyDelay, _G.rallyDelay)
	_G.F.setToggleUi(_G.configUi.keepGleamingToggle, _G.keepGleaming)
	_G.F.setToggleUi(_G.configUi.keepSecretAbilityToggle, _G.keepSecretAbility)
	_G.F.setToggleUi(_G.configUi.keepAllToggle, _G.keepAll)
	_G.F.setToggleUi(_G.configUi.autoEncounterToggle, _G.autoEncounterEnabled)
	_G.F.setSliderUi(_G.configUi.encounterDelay, _G.autoEncounterDelay)
	_G.F.setToggleUi(_G.configUi.autoCatchToggle, _G.autoCatchEnabled)
	_G.F.setToggleUi(_G.configUi.stopOnGleamingToggle, _G.stopOnGleaming)
	_G.F.setToggleUi(_G.configUi.stopOnGammaToggle, _G.stopOnGamma)
	_G.F.setToggleUi(_G.configUi.stopOnWispToggle, _G.stopOnWisp)
	_G.F.setToggleUi(_G.configUi.autoFossilToggle, _G.autoFossilEnabled)
	_G.F.setSliderUi(_G.configUi.autoFossilDelay, _G.autoFossilDelay)
	if _G.configUi.autoFossilAutoReleaseToggle then
		_G.F.setToggleUi(_G.configUi.autoFossilAutoReleaseToggle, _G.autoFossilAutoRelease)
	end
	if _G.configUi.autoFossilKeepSecretAbilityToggle then
		_G.F.setToggleUi(_G.configUi.autoFossilKeepSecretAbilityToggle, _G.autoFossilKeepSecretAbility)
	end
	if _G.configUi.fossilTargetToggles then
		for id, toggle in pairs(_G.configUi.fossilTargetToggles) do
			_G.F.setToggleUi(toggle, _G.autoFossilTargetEnabled[id] ~= false)
		end
	end
	_G.F.syncFossilTargetDropdown(_G.autoFossilReviveTarget)
	if _G.configUi.autoDiscDropToggle then
		_G.F.setToggleUi(_G.configUi.autoDiscDropToggle, _G.autoDiscDropEnabled)
	end
	if _G.configUi.discDropMaxScoreBox and type(_G.configUi.discDropMaxScoreBox.Set) == "function" then
		pcall(function()
			_G.configUi.discDropMaxScoreBox:Set(_G.discDropMaxScore and tostring(_G.discDropMaxScore) or "")
		end)
	end
	if _G.configUi.discDropFinishTimeBox and type(_G.configUi.discDropFinishTimeBox.Set) == "function" then
		pcall(function()
			_G.configUi.discDropFinishTimeBox:Set(
				_G.discDropForceFinishTime ~= nil and tostring(_G.discDropForceFinishTime) or ""
			)
		end)
	end
	if _G.ArcadeAutomation then
		_G.ArcadeAutomation:refreshStats()
	end
	if _G.configUi.autoBoonaryToggle then
		_G.F.setToggleUi(_G.configUi.autoBoonaryToggle, _G.autoBoonaryEnabled)
	end
	if _G.configUi.fastForwardToggle then
		_G.F.setToggleUi(_G.configUi.fastForwardToggle, _G.fastForwardEnabled)
	end
	if _G.configUi.autoFishingToggle then
		_G.F.setToggleUi(_G.configUi.autoFishingToggle, _G.autoFishingEnabled)
	end
	if _G.configUi.ctrlClickTpToggle then
		_G.F.setToggleUi(_G.configUi.ctrlClickTpToggle, _G.ctrlClickTpEnabled)
	end
	if _G.configUi.antiAfkToggle then
		_G.F.setToggleUi(_G.configUi.antiAfkToggle, _G.antiAfkEnabled)
	end
	if _G.configUi.autoHealToggle then
		_G.F.setToggleUi(_G.configUi.autoHealToggle, _G.autoHealEnabled)
	end
	if _G.configUi.autoHealDelay then
		_G.F.setSliderUi(_G.configUi.autoHealDelay, _G.autoHealDelay)
	end
	if _G.configUi.activeRepellentToggle then
		_G.F.setToggleUi(_G.configUi.activeRepellentToggle, _G.activeRepellentEnabled)
	end
	if _G.configUi.activeRepellentDelay then
		_G.F.setSliderUi(_G.configUi.activeRepellentDelay, _G.activeRepellentDelay)
	end
	if _G.configUi.skipDialogueToggle then
		_G.F.setToggleUi(_G.configUi.skipDialogueToggle, _G.skipDialogueEnabled)
	end
	if _G.configUi.denyReassignMoveToggle then
		_G.F.setToggleUi(_G.configUi.denyReassignMoveToggle, _G.denyReassignMoveEnabled)
	end
	if _G.configUi.denySwitchRequestToggle then
		_G.F.setToggleUi(_G.configUi.denySwitchRequestToggle, _G.denySwitchRequestEnabled)
	end
	if _G.configUi.denyNicknameToggle then
		_G.F.setToggleUi(_G.configUi.denyNicknameToggle, _G.denyNicknameEnabled)
	end
	if _G.configUi.disableShowProgressToggle then
		_G.F.setToggleUi(_G.configUi.disableShowProgressToggle, _G.disableShowProgressEnabled)
	end
	if _G.configUi.autoBattleToggle then
		_G.F.setToggleUi(_G.configUi.autoBattleToggle, _G.autoBattleEnabled)
	end
	if _G.configUi.noUnstuckCooldownToggle then
		_G.F.setToggleUi(_G.configUi.noUnstuckCooldownToggle, _G.noUnstuckCooldownEnabled)
	end
	_G.F.syncGoppieFormesTextbox()
	_G.applyingConfig = false
end

_G.F.readConfigDataFromFile = function(fileName)
	if not readfile or not isfile then
		return nil
	end

	local path = _G.F.getConfigFilePath(fileName)
	if not isfile(path) then
		return nil
	end

	local readOk, contents = pcall(function()
		return readfile(path)
	end)
	if not readOk or type(contents) ~= "string" or contents == "" then
		return nil
	end

	local decodeOk, data = pcall(function()
		return _G.HttpService:JSONDecode(contents)
	end)
	if decodeOk and type(data) == "table" then
		return data
	end

	return nil
end

_G.F.applyConfigSnapshot = function(data, syncUi)
	if type(data) ~= "table" then
		return false, "Invalid config data."
	end

	if data.profile then
		_G.configProfileName = _G.F.sanitizeConfigName(data.profile)
	end

	local applied, applyErr = _G.F.applyConfigVariables(data)
	if not applied then
		return false, applyErr
	end

	if syncUi then
		_G.F.syncConfigUiFromVariables()
	end

	return true
end

_G.F.saveConfigToFile = function(fileName, snapshot, silent)
	if not writefile then
		if not silent then
			_G.OrionLib:MakeNotification({
				Name = "Config",
				Content = "File save is not supported in this environment.",
				Time = 4,
			})
		end
		return false, "writefile unavailable"
	end

	local payload = snapshot or _G.F.collectConfigSnapshot()
	local ok, encoded = pcall(function()
		return _G.HttpService:JSONEncode(payload)
	end)
	if not ok then
		if not silent then
			_G.OrionLib:MakeNotification({
				Name = "Config",
				Content = "Failed to encode config.",
				Time = 4,
			})
		end
		return false, "encode failed"
	end

	local path = _G.F.getConfigFilePath(fileName)
	local writeOk, writeErr = pcall(function()
		writefile(path, encoded)
	end)
	if not writeOk then
		if not silent then
			_G.OrionLib:MakeNotification({
				Name = "Config",
				Content = "Failed to save config.",
				Time = 4,
			})
		end
		return false, tostring(writeErr)
	end

	if not silent then
		_G.OrionLib:MakeNotification({
			Name = "Config",
			Content = "Saved to " .. path,
			Time = 4,
		})
	end

	return true
end

_G.F.loadConfigFromFile = function(fileName, silent)
	if not readfile or not isfile then
		if not silent then
			_G.OrionLib:MakeNotification({
				Name = "Config",
				Content = "File load is not supported in this environment.",
				Time = 4,
			})
		end
		return false, "readfile unavailable"
	end

	local path = _G.F.getConfigFilePath(fileName)
	if not isfile(path) then
		if not silent then
			_G.OrionLib:MakeNotification({
				Name = "Config",
				Content = "Config file not found.",
				Time = 4,
			})
		end
		return false, "not found"
	end

	local readOk, contents = pcall(function()
		return readfile(path)
	end)
	if not readOk or type(contents) ~= "string" or contents == "" then
		if not silent then
			_G.OrionLib:MakeNotification({
				Name = "Config",
				Content = "Failed to read config.",
				Time = 4,
			})
		end
		return false, "read failed"
	end

	local decodeOk, data = pcall(function()
		return _G.HttpService:JSONDecode(contents)
	end)
	if not decodeOk or type(data) ~= "table" then
		if not silent then
			_G.OrionLib:MakeNotification({
				Name = "Config",
				Content = "Config file is invalid.",
				Time = 4,
			})
		end
		return false, "invalid json"
	end

	if data.profile then
		_G.configProfileName = _G.F.sanitizeConfigName(data.profile)
	end

	local applyOk, applyErr = _G.F.applyConfigSnapshot(data, true)
	if not applyOk then
		if not silent then
			_G.OrionLib:MakeNotification({
				Name = "Config",
				Content = applyErr or "Failed to apply config.",
				Time = 4,
			})
		end
		return false, applyErr
	end

	if not silent then
		_G.OrionLib:MakeNotification({
			Name = "Config",
			Content = "Loaded from " .. path,
			Time = 4,
		})
	end

	return true
end

_G.startupConfig = _G.F.readConfigDataFromFile(_G.CONFIG_AUTOSAVE_FILE)
_G.F.loadGoppieFormesFromFile()
if _G.startupConfig then
	if _G.startupConfig.profile then
		_G.configProfileName = _G.F.sanitizeConfigName(_G.startupConfig.profile)
	end
end

return { name = "fossil" }
