-- shops.lua
-- Rally, shops, boonary automation helpers.
_G.F.truthy = function(value)
	return value ~= nil and value ~= false and value ~= 0
end

_G.F.refreshRallyUI = function()
	if _G.rallyStatsLabel then
		pcall(function()
			_G.rallyStatsLabel:Set(string.format("Kept: %d | Released: %d", _G.rallyKept, _G.rallyReleased))
		end)
	end
	if _G.rallyStatusLabel then
		pcall(function()
			_G.rallyStatusLabel:Set(_G.lastRallyActionText)
		end)
	end
end

_G.F.setAlwaysKeepList = function(text)
	_G.alwaysKeepText = tostring(text or "")
	_G.alwaysKeepList = {}
	for entry in string.gmatch(_G.alwaysKeepText, "[^,]+") do
		local key = string.lower(string.gsub(entry, "^%s*(.-)%s*$", "%1"))
		if key ~= "" then
			table.insert(_G.alwaysKeepList, key)
		end
	end
end

-- Rally PDS API (from game Rally module):
--   ranchStatus  -> { rallied = number, full = boolean }
--   getRallied   -> { monsters = {...}, max = number, mastery = ... }
--   handleRallied(marks) -> new rallied count
-- Marks: 0 = unmarked, 1 = release, 2 = keep
_G.F.rallyPdsGet = function(actionName, ...)
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local args = { ... }

	for _, remoteKey in ipairs({ "Network", "Connection" }) do
		local remote = type(_G._p) == "table" and _G._p[remoteKey] or nil
		if type(remote) == "table" and type(remote.get) == "function" then
			local ok, result = pcall(function()
				return remote:get("PDS", actionName, unpack(args))
			end)
			if ok then
				return true, result
			end
		end
	end

	local ok, result = pcall(function()
		local remoteFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remote")
		local getRemote = remoteFolder and remoteFolder:FindFirstChild("GET")
		if not getRemote then
			error("GET remote not found")
		end
		return getRemote:InvokeServer("PDS", actionName, unpack(args))
	end)

	if ok then
		return true, result
	end

	return false
end

-- PDS shop flow for Arcade Boonary: maxBuy -> quantity, then buyItem(id, qty).
-- At 999,999 tix and 2,000 tix each, that is 499 Boonarys.
_G.BOONARY_PDS_REQ_KEY = "qYMeR25bQnq/OmfJpFX7Hg"
_G.BOONARY_SHOP_ITEM_ID = "_loom_Boonary"
_G.BOONARY_TIX_PRICE = 2000

_G.F.pdsGetAction = function(actionName, ...)
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local args = { ... }
	local network = type(_G._p) == "table" and _G._p.Network or nil
	if type(network) == "table" and type(network.get) == "function" then
		local ok, value = pcall(function()
			return network:get("PDS", actionName, unpack(args))
		end)
		if ok then
			return true, value
		end
	end

	return _G.F.rallyPdsGet(actionName, unpack(args))
end

_G.F.getBoonaryBuyQuantityFromTix = function(tix)
	tix = tonumber(tix)
	if not tix or tix <= 0 then
		return nil
	end

	local price = tonumber(_G.BOONARY_TIX_PRICE) or 2000
	if price <= 0 then
		return nil
	end

	return math.floor(tix / price)
end

_G.F.getBoonaryMaxBuyErrorMessage = function(code)
	local errorMessages = {
		fb = "Already at max carry for Boonary.",
		nc = "Not enough Battle Tokens.",
		np = "Not enough Cake Points.",
		nt = "Not enough Tickets/Tix.",
		nr = "Not enough resources/vouchers for Boonary.",
		nm = "Not enough Loomicoin.",
		ao = "You already own this item.",
		lc = "Loomian Care is full.",
		dl = "Daily Boonary purchase limit reached.",
	}

	return errorMessages[code] or ("Shop purchase failed: " .. tostring(code))
end

_G.F.rallyPdsReq = function(actionName, ...)
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local args = { ... }

	for _, remoteKey in ipairs({ "Network", "Connection" }) do
		local remote = type(_G._p) == "table" and _G._p[remoteKey] or nil
		for _, methodName in ipairs({ "post", "request" }) do
			local method = type(remote) == "table" and remote[methodName] or nil
			if type(method) == "function" then
				local ok, result = pcall(function()
					return method(remote, "PDS", actionName, unpack(args))
				end)
				if ok then
					return true, result
				end
			end
		end
	end

	local ok, result = pcall(function()
		local remoteFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remote")
		local reqRemote = remoteFolder and remoteFolder:FindFirstChild("REQ")
		if not reqRemote then
			error("REQ remote not found")
		end
		return reqRemote:InvokeServer(_G.BOONARY_PDS_REQ_KEY, "PDS", actionName, unpack(args))
	end)

	if ok then
		return true, result
	end

	return false, result
end

_G.F.getRallyModule = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end
	if type(_G._p) ~= "table" then
		return nil
	end

	if type(_G._p.Menu) == "table" and type(_G._p.Menu.rally) == "table" then
		return _G._p.Menu.rally
	end
	if type(_G._p.Rally) == "table" then
		return _G._p.Rally
	end
	if type(_G._p.DataManager) == "table" and type(_G._p.DataManager.loadModule) == "function" then
		local ok, result = pcall(function()
			return _G._p.DataManager:loadModule("Rally")
		end)
		if ok and type(result) == "table" then
			return result
		end
	end

	return nil
end

_G.F.ensureRallyModule = function()
	local rally = _G.F.getRallyModule()
	if rally then
		return rally
	end

	if type(_G._p) ~= "table" or type(_G._p.DataManager) ~= "table" then
		return nil
	end

	local ok, result = pcall(function()
		if type(_G._p.DataManager.loadModule) == "function" then
			return _G._p.DataManager:loadModule("Rally")
		end
	end)

	if ok and type(result) == "table" then
		if type(_G._p.Menu) == "table" then
			pcall(function()
				_G._p.Menu.rally = result
			end)
		end
		return result
	end

	return nil
end

_G.F.syncRallyBubble = function(newCount)
	local rally = _G.F.ensureRallyModule()
	if not rally or newCount == nil then
		return
	end

	pcall(function()
		rally.ralliedCount = newCount
	end)

	if type(rally.updateNPCBubble) == "function" then
		pcall(function()
			rally:updateNPCBubble(newCount)
		end)
	end
end

_G.F.openRallyMenu = function()
	local rally = _G.F.ensureRallyModule()
	if not rally then
		return false, "Rally module is not loaded."
	end

	if type(rally.openRalliedMonstersMenu) == "function" then
		local ok, err = pcall(function()
			if type(_G._p.Menu) == "table" and type(_G._p.Menu.disable) == "function" then
				_G._p.Menu:disable()
			end
			rally:openRalliedMonstersMenu()
		end)

		pcall(function()
			if type(_G._p.Menu) == "table" and type(_G._p.Menu.enable) == "function" then
				_G._p.Menu:enable()
			end
		end)

		if ok then
			return true
		end
		return false, tostring(err)
	end

	if type(rally.openRallyTeamMenu) == "function" then
		local ok, err = pcall(function()
			if type(_G._p.Menu) == "table" and type(_G._p.Menu.disable) == "function" then
				_G._p.Menu:disable()
			end
			rally:openRallyTeamMenu()
		end)

		pcall(function()
			if type(_G._p.Menu) == "table" and type(_G._p.Menu.enable) == "function" then
				_G._p.Menu:enable()
			end
		end)

		if ok then
			return true
		end
		return false, tostring(err)
	end

	return false, "Rally module has no menu opener."
end

_G.F.getShopModule = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	if type(_G._p) ~= "table" then
		return nil
	end

	local menu = type(_G._p.Menu) == "table" and _G._p.Menu or nil
	local parents = {}
	if type(menu) == "table" then
		table.insert(parents, menu)
	end
	table.insert(parents, _G._p)

	for _, parent in ipairs(parents) do
		for _, key in ipairs({ "shop", "Shop", "shops", "Shops", "mart", "Mart" }) do
			local candidate = _G.F.safeTableGet(parent, key)
			if type(candidate) == "table" or type(candidate) == "function" then
				return candidate
			end
		end
	end

	for _, parent in ipairs(parents) do
		for _, methodName in ipairs({ "openShop", "OpenShop", "openShopMenu", "OpenShopMenu", "openMart", "OpenMart" }) do
			if type(_G.F.safeTableGet(parent, methodName)) == "function" then
				return parent
			end
		end
	end

	local dataManager = type(_G._p.DataManager) == "table" and _G._p.DataManager or nil
	if type(dataManager) == "table" and type(_G.F.safeTableGet(dataManager, "loadModule")) == "function" then
		for _, moduleName in ipairs({ "Shop", "shop", "Shops", "shops", "Mart", "ShopMenu" }) do
			local ok, result = pcall(function()
				return dataManager:loadModule(moduleName)
			end)

			if ok and (type(result) == "table" or type(result) == "function") then
				if type(menu) == "table" and _G.F.safeTableGet(menu, "shop") == nil then
					pcall(function()
						menu.shop = result
					end)
				end

				return result
			end
		end
	end

	return nil
end

_G.F.tryOpenShopWithMethod = function(shopModule, method, shopId, displayName)
	local lastErr = nil
	local attempts = {
		function()
			return method(shopModule, shopId)
		end,
		function()
			return method(shopModule, shopId, displayName)
		end,
		function()
			return method(shopModule, { id = shopId, name = displayName })
		end,
		function()
			return method(shopModule, displayName)
		end,
		function()
			return method(shopId)
		end,
	}

	for _, attempt in ipairs(attempts) do
		local ok, result, extra = pcall(attempt)
		if ok and result ~= false then
			return true
		end

		if ok then
			lastErr = tostring(extra or result or "Shop opener returned false.")
		else
			lastErr = tostring(result)
		end
	end

	return false, lastErr
end

_G.F.openShop = function(shopId, displayName)
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	if type(_G._p) ~= "table" then
		return false, "Hook is not ready."
	end

	local shopModule = _G.F.getShopModule()
	if not shopModule then
		return false, "Shop module is not loaded."
	end

	if type(shopModule) == "function" then
		local ok, result = pcall(function()
			return shopModule(shopId)
		end)

		if ok and result ~= false then
			return true
		end

		return false, ok and "Shop opener returned false." or tostring(result)
	end

	local lastErr = nil
	for _, methodName in ipairs({
		"open", "Open",
		"openShop", "OpenShop",
		"openShopMenu", "OpenShopMenu",
		"openMart", "OpenMart",
		"show", "Show",
	}) do
		local method = _G.F.safeTableGet(shopModule, methodName)
		if type(method) == "function" then
			local opened, reason = _G.F.tryOpenShopWithMethod(shopModule, method, shopId, displayName)
			if opened then
				return true
			end

			lastErr = reason
		end
	end

	return false, lastErr or "Shop module has no known opener."
end

_G.F.setAutoBoonaryStatus = function(text)
	local message = tostring(text or "")
	if message == "" then
		message = "Idle"
	end

	if _G.autoBoonaryStatusLabel and type(_G.autoBoonaryStatusLabel.Set) == "function" then
		pcall(function()
			_G.autoBoonaryStatusLabel:Set(message)
		end)
	end
end

_G.F.getCurrentTixCount = function()
	return tonumber(_G.F.getInformationValue({ "tix", "ticket", "tickets", "eventtickets", "eventTix" }))
end

_G.F.pdsPost = function(actionName, ...)
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local args = { ... }
	for _, remoteKey in ipairs({ "Network", "Connection" }) do
		local remote = type(_G._p) == "table" and _G._p[remoteKey] or nil
		if type(remote) == "table" and type(remote.post) == "function" then
			local ok, result = pcall(function()
				return remote:post("PDS", actionName, unpack(args))
			end)
			if ok and result ~= nil and result ~= false then
				return true, result
			end
		end
	end

	return false, "No acknowledged PDS post path found."
end

_G.F.tryBoonaryPdsAction = function(actionNames, argumentSets)
	local lastReason = nil

	for _, actionName in ipairs(actionNames) do
		for _, args in ipairs(argumentSets) do
			local ok, result = _G.F.rallyPdsGet(actionName, unpack(args))
			if ok and result ~= nil and result ~= false then
				return true, result, actionName
			end

			ok, result = _G.F.pdsPost(actionName, unpack(args))
			if ok then
				return true, result, actionName
			end

			lastReason = tostring(result or actionName)
			task.wait(0.05)
		end
	end

	return false, lastReason or "No candidate action succeeded."
end

-- Real boost API (confirmed working in the pity-boost variant of this script):
--   boostStatus -> { ["1"] = { remaining, paused }, ..., p = { activePity, ... } }
--   useBoost(boostId, count) consumes Ro-Power tokens and starts/extends the boost.
-- Boost id 1 = Gleaming, 2 = Roaming.
_G.GLEAMING_BOOST_ID = 1

_G.F.isBoostRunning = function(boostStatus, boostId)
	local entry = type(boostStatus) == "table" and (boostStatus[tostring(boostId)] or boostStatus[boostId]) or nil
	if type(entry) ~= "table" then
		return false
	end

	local remaining = tonumber(entry[1])
	if remaining == nil or remaining <= 0 then
		return false
	end

	return entry[2] ~= true
end

_G.F.activateGleamingRoPowers = function(count)
	count = math.max(1, math.floor(tonumber(count) or 2))

	local okStatus, boostStatus = _G.F.rallyPdsGet("boostStatus")
	if not okStatus or type(boostStatus) ~= "table" then
		return false, "Could not read boost status from the server."
	end

	local alreadyRunning = _G.F.isBoostRunning(boostStatus, _G.GLEAMING_BOOST_ID)

	local activated = 0
	for _ = 1, count do
		local okUse, tokenCount = _G.F.rallyPdsGet("useBoost", _G.GLEAMING_BOOST_ID, 1)
		if not okUse or not tokenCount then
			-- Out of tokens (or refused); stop here and judge by what's running.
			break
		end
		activated = activated + 1
		task.wait(0.25)
	end

	local okVerify, verifyStatus = _G.F.rallyPdsGet("boostStatus")
	local running = okVerify and _G.F.isBoostRunning(verifyStatus, _G.GLEAMING_BOOST_ID)

	if not running then
		if activated == 0 then
			return false, "Could not start the Gleaming boost (no Ro-Power tokens?)."
		end
		return false, "Used " .. activated .. " Ro-Power token(s) but the Gleaming boost is not running."
	end

	return true, string.format("Gleaming boost running (%d token(s) used%s).",
		activated, alreadyRunning and ", was already active" or "")
end

_G.F.purchaseMaxArcadeBoonarys = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local itemId = _G.BOONARY_SHOP_ITEM_ID
	local ok, maxResult = _G.F.pdsGetAction("maxBuy", itemId)

	if not ok and maxResult == nil then
		local reqOk, reqValue = _G.F.rallyPdsReq("maxBuy", itemId)
		if reqOk then
			ok = true
			maxResult = reqValue
		end
	end

	if type(maxResult) == "string" then
		return false, _G.F.getBoonaryMaxBuyErrorMessage(maxResult)
	end

	if maxResult == true then
		_G.F.setAutoBoonaryStatus("Purchased Boonary(s).")
		return true, 1
	end

	local quantity = nil
	if type(maxResult) == "number" and maxResult > 0 then
		quantity = math.floor(maxResult)
	else
		quantity = _G.F.getBoonaryBuyQuantityFromTix(_G.F.getCurrentTixCount())
	end

	if not quantity or quantity <= 0 then
		return false, tostring(maxResult or "Could not determine Boonary purchase quantity.")
	end

	local buyOk, buyResult = _G.F.pdsGetAction("buyItem", itemId, quantity)
	if buyOk and buyResult then
		_G.F.setAutoBoonaryStatus("Purchased " .. tostring(quantity) .. " Boonary(s).")
		return true, quantity
	end

	if not buyOk then
		local reqOk, reqValue = _G.F.rallyPdsReq("buyItem", itemId, quantity)
		if reqOk and reqValue then
			_G.F.setAutoBoonaryStatus("Purchased " .. tostring(quantity) .. " Boonary(s).")
			return true, quantity
		end
	end

	return false, tostring(buyResult or maxResult or "buyItem failed.")
end

_G.F.getBoonaryMonsterName = function(monster)
	if type(monster) ~= "table" then
		return ""
	end

	local unwrapped = _G.F.unwrapPcSlotData(monster)
	if unwrapped and unwrapped.icon then
		local speciesId = _G.F.safeArrayGet(unwrapped.icon, 1)
		local speciesName = _G.F.getSpeciesNameFromId(speciesId)
		if speciesName then
			return speciesName
		end
		return "Loomian #" .. tostring(speciesId)
	end

	for _, containerKey in ipairs({ "summ", "summary", "modelData", "data" }) do
		local container = _G.F.safeTableGet(monster, containerKey)
		if type(container) == "table" then
			for _, key in ipairs({ "name", "species", "nickname", "id", "num", "dex", "monster", "loomian" }) do
				local value = _G.F.safeTableGet(container, key)
				if value ~= nil and tostring(value) ~= "" then
					return tostring(value)
				end
			end
		end
	end

	local sprite = _G.F.safeTableGet(monster, "sprite")
	local spriteModelData = type(sprite) == "table" and _G.F.safeTableGet(sprite, "modelData") or nil
	if type(spriteModelData) == "table" then
		for _, key in ipairs({ "name", "species", "id", "num", "dex" }) do
			local value = _G.F.safeTableGet(spriteModelData, key)
			if value ~= nil and tostring(value) ~= "" then
				return tostring(value)
			end
		end
	end

	for _, key in ipairs({ "name", "species", "nickname", "id", "num", "dex", "monster", "loomian" }) do
		local value = _G.F.safeTableGet(monster, key)
		if value ~= nil and tostring(value) ~= "" then
			return tostring(value)
		end
	end

	return ""
end

-- Reverse-lookup every species id whose dex name contains "boonary" and cache
-- the set, so per-slot Boonary checks are a numeric compare instead of a name
-- resolution. Cached only once found, so an early call before _p.Constants is
-- ready doesn't poison the cache.
_G.F.getBoonarySpeciesIdSet = function()
	if _G.F.boonarySpeciesIdSet then
		return _G.F.boonarySpeciesIdSet
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
						if type(name) == "string" and string.find(string.lower(name), "boonary", 1, true) then
							set[tonumber(id) or id] = true
						end
					end
				end)
				if next(set) then
					break
				end
			end
		end
	end

	if next(set) then
		_G.F.boonarySpeciesIdSet = set
	end
	return set
end

_G.F.isBoonaryMonster = function(monster)
	-- Priority check: species id from the compact icon array (real PC format),
	-- before falling back to name resolution for other data shapes.
	local unwrapped = _G.F.unwrapPcSlotData(monster)
	if unwrapped and unwrapped.icon then
		local speciesId = tonumber(_G.F.safeArrayGet(unwrapped.icon, 1))
		if speciesId then
			local idSet = _G.F.getBoonarySpeciesIdSet()
			if next(idSet) then
				return idSet[speciesId] == true
			end
		end
	end

	local name = string.lower(_G.F.getBoonaryMonsterName(monster))
	return string.find(name, "boonary", 1, true) ~= nil
end

_G.F.isStorageMonsterLike = function(value)
	if type(value) ~= "table" then
		return false
	end

	-- Real PC slots are positional arrays with no named keys:
	-- { labelIndex, { speciesId, sheetType, gleamTier, wispColor } } ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â or a bare
	-- icon array. Check the shape directly, same as unwrapPcSlotData.
	if _G.F.isMonsterIconArray(value) or _G.F.isMonsterIconArray(_G.F.safeArrayGet(value, 2)) then
		return true
	end

	for _, key in ipairs({ "summ", "summary", "name", "species", "nickname", "id", "num", "dex", "gl", "gleam", "gamma", "isGamma", "shiny", "wisp", "icon", "sa", "ivs", "evs", "moves", "personality" }) do
		if _G.F.safeTableGet(value, key) ~= nil then
			return true
		end
	end

	return false
end

_G.F.getMonsterDebugText = function(monster)
	if type(monster) ~= "table" then
		return ""
	end

	local parts = {}
	for _, key in ipairs({ "name", "species", "nickname", "id", "num", "dex", "gl", "gleam", "gamma", "isGamma", "sa", "personality" }) do
		local value = _G.F.safeTableGet(monster, key)
		if value ~= nil and type(value) ~= "table" and type(value) ~= "function" then
			table.insert(parts, tostring(key) .. "=" .. tostring(value))
		end
	end

	local summary = _G.F.safeTableGet(monster, "summ") or _G.F.safeTableGet(monster, "summary")
	if type(summary) == "table" then
		for _, key in ipairs({ "name", "species", "nickname", "id", "num", "dex", "gl", "gleam", "gamma" }) do
			local value = _G.F.safeTableGet(summary, key)
			if value ~= nil and type(value) ~= "table" and type(value) ~= "function" then
				table.insert(parts, "summ." .. tostring(key) .. "=" .. tostring(value))
			end
		end
	end

	local modelData = _G.F.safeTableGet(monster, "modelData")
	if type(modelData) == "table" then
		for _, key in ipairs({ "name", "species", "id", "num", "dex", "gleam", "gamma" }) do
			local value = _G.F.safeTableGet(modelData, key)
			if value ~= nil and type(value) ~= "table" and type(value) ~= "function" then
				table.insert(parts, "modelData." .. tostring(key) .. "=" .. tostring(value))
			end
		end
	end

	return table.concat(parts, " ")
end

_G.F.isKeepBoonary = function(monster)
	return _G.isActiveFlag(_G.F.getMonsterGleamValue(monster)) or _G.isActiveFlag(_G.F.getMonsterGammaValue(monster))
end

_G.F.formatBoonaryTableKeys = function(value, limit)
	if type(value) ~= "table" then
		return ""
	end

	local keys = {}
	limit = tonumber(limit) or 12

	local ok = pcall(function()
		for key in pairs(value) do
			table.insert(keys, tostring(key))
			if #keys >= limit then
				break
			end
		end
	end)

	if not ok or #keys == 0 then
		return ""
	end

	return table.concat(keys, ", ")
end

_G.F.addBoonaryStorageCandidate = function(candidates, seen, source, value)
	if type(value) ~= "table" or seen[value] then
		return
	end

	seen[value] = true
	table.insert(candidates, {
		source = tostring(source),
		data = value,
		keys = _G.F.formatBoonaryTableKeys(value, 10),
	})
end

_G.F.getLocalBoonaryStorageCandidates = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local candidates = {}
	local seen = {}
	local roots = {}
	local scanned = 0
	local maxNodes = math.max(100, tonumber(_G.autoBoonaryScanNodeLimit) or 5000)

	local function addRoot(source, value)
		if type(value) == "table" then
			table.insert(roots, { source = tostring(source), data = value })
		end
	end

	addRoot("_p", _G._p)

	if type(_G._p) == "table" then
		for _, key in ipairs({ "PC", "pc", "Storage", "storage", "Boxes", "boxes", "Box", "box", "PlayerData", "playerData", "Data", "data", "SaveData", "saveData", "Menu", "DataManager" }) do
			addRoot("_p." .. key, _G.F.safeTableGet(_G._p, key))
		end

		local dataManager = _G.F.safeTableGet(_G._p, "DataManager")
		if type(dataManager) == "table" then
			for _, key in ipairs({ "currentSave", "currentData", "playerData", "data", "saveData" }) do
				addRoot("DataManager." .. key, _G.F.safeTableGet(dataManager, key))
			end

			local loadModule = _G.F.safeTableGet(dataManager, "loadModule")
			if type(loadModule) == "function" then
				for _, moduleName in ipairs({ "PC", "Pc", "Storage", "PCStorage", "MonsterStorage", "Boxes", "Box" }) do
					local ok, module = pcall(function()
						return dataManager:loadModule(moduleName)
					end)
					if ok then
						addRoot("DataManager:loadModule(" .. moduleName .. ")", module)
					end
				end
			end
		end
	end

	local interestingKeys = {
		pc = true,
		pcs = true,
		box = true,
		boxes = true,
		storage = true,
		monsterstorage = true,
		monsters = true,
		mons = true,
	}

	local function scan(source, value, depth)
		if type(value) ~= "table" or depth > 4 or scanned >= maxNodes then
			return
		end

		scanned = scanned + 1

		local ok = pcall(function()
			for key, child in pairs(value) do
				if scanned >= maxNodes then
					break
				end
				if type(child) == "table" then
					local normalized = _G.F.normalizeInfoKey(key)
					if interestingKeys[normalized] or string.find(normalized, "storage", 1, true) or string.find(normalized, "box", 1, true) or string.find(normalized, "pc", 1, true) then
						_G.F.addBoonaryStorageCandidate(candidates, seen, source .. "." .. tostring(key), child)
					end

					if depth < 4 then
						scan(source .. "." .. tostring(key), child, depth + 1)
					end
				end
			end
		end)

		if not ok then
			return
		end
	end

	for _, root in ipairs(roots) do
		_G.F.addBoonaryStorageCandidate(candidates, seen, root.source, root.data)
		scan(root.source, root.data, 0)
	end

	return candidates
end

_G.F.getFastBoonaryPreviewCandidates = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local candidates = {}
	local seen = {}
	local function add(source, value)
		_G.F.addBoonaryStorageCandidate(candidates, seen, source, value)
	end

	add("_p", _G._p)

	if type(_G._p) == "table" then
		for _, key in ipairs({ "PC", "pc", "Storage", "storage", "Boxes", "boxes", "PlayerData", "playerData", "Data", "data", "SaveData", "saveData" }) do
			add("_p." .. key, _G.F.safeTableGet(_G._p, key))
		end

		local dataManager = _G.F.safeTableGet(_G._p, "DataManager")
		add("_p.DataManager", dataManager)

		if type(dataManager) == "table" then
			for _, key in ipairs({ "currentSave", "currentData", "playerData", "data", "saveData" }) do
				add("DataManager." .. key, _G.F.safeTableGet(dataManager, key))
			end
		end

		local menu = _G.F.safeTableGet(_G._p, "Menu")
		add("_p.Menu", menu)
		if type(menu) == "table" then
			for _, key in ipairs({ "pc", "PC", "storage", "Storage", "boxes", "Boxes" }) do
				add("_p.Menu." .. key, _G.F.safeTableGet(menu, key))
			end
		end
	end

	return candidates
end

_G.F.getStorageGroupCandidates = function(groupNumber)
	groupNumber = math.max(1, math.floor(tonumber(groupNumber) or 49))
	local actions = {
		"getPCGroup",
		"getStorageGroup",
		"getBox",
		"getPCBox",
		"getPCData",
		"getStorage",
		"getMonsters",
	}

	local argumentSets = {
		{ groupNumber },
		{ tostring(groupNumber) },
		{ "pc", groupNumber },
		{},
	}

	for _, actionName in ipairs(actions) do
		for _, args in ipairs(argumentSets) do
			local ok, result = _G.F.rallyPdsGet(actionName, unpack(args))
			if ok and type(result) == "table" then
				return result, actionName
			end
			task.wait(0.03)
		end
	end

	local localCandidates = _G.F.getLocalBoonaryStorageCandidates()
	local bestCandidate = nil
	local bestBoonaryCount = 0
	local bestEntryCount = 0

	for _, candidate in ipairs(localCandidates) do
		local allEntries = _G.F.collectStorageGroupEntries(candidate.data, groupNumber)
		local entries = {}
		for _, entry in ipairs(allEntries) do
			if _G.F.isBoonaryMonster(entry.monster) then
				table.insert(entries, entry)
			end
		end

		if #entries > bestBoonaryCount or (#entries == bestBoonaryCount and #allEntries > bestEntryCount) then
			bestCandidate = candidate
			bestBoonaryCount = #entries
			bestEntryCount = #allEntries
		end
	end

	if bestCandidate and bestBoonaryCount > 0 then
		return bestCandidate.data, bestCandidate.source
	end

	if #localCandidates > 0 then
		return {
			__boonaryCandidateList = true,
			candidates = localCandidates,
		}, "local candidates"
	end

	return nil, "No PC storage action succeeded and no local storage candidates were loaded."
end

_G.F.collectStorageGroupEntries = function(data, groupNumber, nodeLimit)
	local entries = {}
	local visited = {}
	local scanned = 0
	local maxNodes = math.max(50, tonumber(nodeLimit) or tonumber(_G.autoBoonaryScanNodeLimit) or 5000)
	groupNumber = math.max(1, math.floor(tonumber(groupNumber) or 49))

	local function add(monster, slot, group)
		if type(monster) ~= "table" or visited[monster] then
			return
		end
		visited[monster] = true
		table.insert(entries, {
			monster = monster,
			slot = slot,
			group = tonumber(group) or groupNumber,
		})
	end

	local function scan(value, depth, currentGroup)
		if type(value) ~= "table" or depth > 6 or scanned >= maxNodes then
			return
		end

		scanned = scanned + 1

		local groupValue = tonumber(_G.F.safeTableGet(value, "group") or _G.F.safeTableGet(value, "box") or currentGroup)
		if groupValue == nil then
			groupValue = currentGroup
		end

		if _G.F.isStorageMonsterLike(value) and (groupValue == nil or tonumber(groupValue) == groupNumber) then
			add(value, _G.F.safeTableGet(value, "slot") or _G.F.safeTableGet(value, "index"), groupValue)
			return
		end

		local directMonsters = _G.F.safeTableGet(value, "monsters") or _G.F.safeTableGet(value, "Mons") or _G.F.safeTableGet(value, "party") or _G.F.safeTableGet(value, "box")
		if type(directMonsters) == "table" then
			for slot, monster in pairs(directMonsters) do
				if type(monster) == "table" and _G.F.isStorageMonsterLike(monster) and (groupValue == nil or tonumber(groupValue) == groupNumber) then
					add(monster, slot, groupValue)
				end
			end
		end

		for key, child in pairs(value) do
			if scanned >= maxNodes then
				break
			end
			local childGroup = groupValue
			local numericKey = tonumber(key)
			if numericKey == groupNumber and type(child) == "table" then
				childGroup = groupNumber
			end
			scan(child, depth + 1, childGroup)
		end
	end

	scan(data, 0, nil)
	return entries
end

_G.F.collectStorageGroupMonsters = function(data, groupNumber)
	local entries = {}

	for _, entry in ipairs(_G.F.collectStorageGroupEntries(data, groupNumber)) do
		if _G.F.isBoonaryMonster(entry.monster) then
			table.insert(entries, entry)
		end
	end

	return entries
end

_G.F.releaseStoredMonster = function(entry)
	if type(entry) ~= "table" or type(entry.monster) ~= "table" then
		return false, "Invalid storage entry."
	end

	local monster = entry.monster
	local identifiers = {}
	for _, key in ipairs({ "id", "uid", "uuid", "pcid", "pcId", "personality", "ident" }) do
		local value = _G.F.safeTableGet(monster, key)
		if value ~= nil then
			table.insert(identifiers, value)
		end
	end

	local actions = {
		"releaseStoredMonster",
		"releaseFromStorage",
		"releaseFromPC",
		"releaseMonster",
		"releaseFromParty",
		"releaseFromCare",
		"deleteStoredMonster",
	}

	local argumentSets = {}
	if entry.group ~= nil and entry.slot ~= nil then
		table.insert(argumentSets, { entry.group, entry.slot })
		if tonumber(entry.group) and tonumber(entry.slot) then
			table.insert(argumentSets, { tonumber(entry.group), tonumber(entry.slot) })
		end
		table.insert(argumentSets, { { group = entry.group, slot = entry.slot } })
	end

	for _, identifier in ipairs(identifiers) do
		table.insert(argumentSets, { identifier })
		table.insert(argumentSets, { entry.group, identifier })
	end

	if #argumentSets == 0 then
		return false, "No safe release identifier for " .. _G.F.getBoonaryMonsterName(monster) .. "."
	end

	return _G.F.tryBoonaryPdsAction(actions, argumentSets)
end

_G.F.releaseStoredBoonary = function(entry)
	return _G.F.releaseStoredMonster(entry)
end

_G.F.cleanBoonaryStorageGroup = function(groupNumber)
	local data, source = _G.F.getStorageGroupCandidates(groupNumber)
	if type(data) ~= "table" then
		return false, tostring(source)
	end
	if data.__boonaryCandidateList then
		return false, "No Boonarys found in loaded local storage candidates."
	end

	local entries = _G.F.collectStorageGroupMonsters(data, groupNumber)
	local kept = 0
	local released = 0
	local failed = 0

	for _, entry in ipairs(entries) do
		if _G.F.isKeepBoonary(entry.monster) then
			kept = kept + 1
		else
			local ok = _G.F.releaseStoredBoonary(entry)
			if ok then
				released = released + 1
			else
				failed = failed + 1
			end
			task.wait(0.2)
		end
	end

	return true, string.format("Group %d via %s: kept %d, released %d, failed %d.", tonumber(groupNumber) or 49, tostring(source), kept, released, failed)
end

-- ============================================================================
-- Direct PC session path (matches the game's real protocol):
--   Session = Network:get("PDS", "openPC")   -> { id, boxes, party, maxBoxes, ... }
--   boxes[boxKey][slotKey] = { labelIndex, { speciesId, sheetType, gleamTier, wispColor } }
--   release: ch.m[tostring(labelIndex)] = { -1, rcount }; boxes[box][slot] = nil
--   commit:  Network:get("PDS", "closePC", Session.id, Session.ch)
-- ============================================================================

_G.F.getPcSession = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end
	if type(_G._p) ~= "table" then
		return nil, "Game framework (_p) not found."
	end

	-- Prefer the live session if the PC UI is open; the game commits its own
	-- ch journal when the player closes the PC, so we must write into it.
	local pcModule = _G.F.safeTableGet(_G._p, "PC")
	local live = type(pcModule) == "table" and _G.F.safeTableGet(pcModule, "pcData") or nil
	if type(live) == "table" and type(_G.F.safeTableGet(live, "boxes")) == "table" then
		return live, true
	end

	local network = _G.F.safeTableGet(_G._p, "Network")
	if type(network) ~= "table" or type(network.get) ~= "function" then
		return nil, "Network module not found."
	end

	local ok, session = pcall(function()
		return network:get("PDS", "openPC")
	end)
	if not ok or type(session) ~= "table" or type(_G.F.safeTableGet(session, "boxes")) ~= "table" then
		return nil, "openPC failed (server refused or returned no boxes)."
	end

	session.ch = { m = {} }
	session.rcount = 0
	return session, false
end

_G.F.journalPcRelease = function(session, labelIndex, boxKey, slotKey)
	if type(session.ch) ~= "table" then
		session.ch = { m = {} }
	end
	if type(session.ch.m) ~= "table" then
		session.ch.m = {}
	end

	session.rcount = (tonumber(session.rcount) or 0) + 1
	session.ch.m[tostring(labelIndex)] = { -1, session.rcount }

	local box = session.boxes[boxKey]
	if type(box) == "table" then
		box[slotKey] = nil
	end
end

_G.F.closePcSession = function(session)
	local network = _G.F.safeTableGet(_G._p, "Network")
	if type(network) ~= "table" or type(network.get) ~= "function" then
		return false, "Network module not found."
	end

	local ok, result = pcall(function()
		return network:get("PDS", "closePC", session.id, session.ch)
	end)
	if not ok or not result then
		return false, "closePC failed; releases were NOT committed."
	end
	return true, result
end

-- Diagnostic lines go to the console AND a buffer that dry runs flush to
-- BOONARY-DIAG.txt in the config folder, so failures are inspectable even
-- without console access.
_G.F.boonaryDiagPrint = function(line)
	line = tostring(line)
	print(line)
	if type(_G.boonaryDiagLines) == "table" then
		table.insert(_G.boonaryDiagLines, line)
	end
end

-- Dump what the PC session actually contains so detection failures are
-- debuggable from the console instead of guessing at data shapes.
_G.F.printBoonaryPcDiagnostics = function(session, isLiveSession)
	local print = _G.F.boonaryDiagPrint
	local function describeValue(value, depth)
		if type(value) ~= "table" then
			return type(value) .. ":" .. tostring(value)
		end
		if depth <= 0 then
			return "table{...}"
		end
		local parts = {}
		local count = 0
		local ok = pcall(function()
			for key, child in pairs(value) do
				count = count + 1
				if count > 8 then
					table.insert(parts, "...")
					break
				end
				table.insert(parts, tostring(key) .. "=" .. describeValue(child, depth - 1))
			end
		end)
		if not ok then
			return "table{unreadable}"
		end
		return "{" .. table.concat(parts, ", ") .. "}"
	end

	print("[Boonary Diag] session source: " .. (isLiveSession and "live PC UI (pcData)" or "openPC network call"))
	print("[Boonary Diag] session keys: " .. describeValue(session, 1))

	local idSet = _G.F.getBoonarySpeciesIdSet()
	local idList = {}
	for id in pairs(idSet) do
		table.insert(idList, tostring(id))
	end
	print("[Boonary Diag] boonary species ids from Constants: " .. (#idList > 0 and table.concat(idList, ", ") or "NONE FOUND (name fallback will be used)"))

	local boxCount = 0
	local slotsPrinted = 0
	for boxKey, box in pairs(session.boxes) do
		boxCount = boxCount + 1
		if type(box) == "table" then
			local slotCount = 0
			pcall(function()
				for _ in pairs(box) do
					slotCount = slotCount + 1
				end
			end)
			if boxCount <= 6 or slotCount > 0 then
				print(string.format("[Boonary Diag] box key=%s (%s) slots=%d", tostring(boxKey), type(boxKey), slotCount))
			end
			for slotKey, slot in pairs(box) do
				if slotsPrinted >= 8 then
					break
				end
				slotsPrinted = slotsPrinted + 1
				local unwrapped = _G.F.unwrapPcSlotData(slot)
				local icon = unwrapped and unwrapped.icon or nil
				local speciesId = icon and _G.F.safeArrayGet(icon, 1) or nil
				local name = _G.F.getBoonaryMonsterName(slot)
				print(string.format("[Boonary Diag]   slot key=%s (%s) raw=%s | icon=%s species=%s name=%s isBoonary=%s",
					tostring(slotKey), type(slotKey), describeValue(slot, 2),
					icon and describeValue(icon, 1) or "nil",
					tostring(speciesId), tostring(name), tostring(_G.F.isBoonaryMonster(slot))))
			end
		else
			print(string.format("[Boonary Diag] box key=%s is a %s, not a table", tostring(boxKey), type(box)))
		end
	end
	print(string.format("[Boonary Diag] total boxes iterated: %d, sample slots printed: %d", boxCount, slotsPrinted))
	if boxCount == 0 then
		print("[Boonary Diag] session.boxes is EMPTY - the server returned no box data on this path.")
	end

	-- Species histogram across every box: the dominant id in the Boonary dump
	-- box identifies the species numerically even with no name table.
	local histogram = {}
	local boxTallies = {}
	for boxKey, box in pairs(session.boxes) do
		if type(box) == "table" then
			for _, slot in pairs(box) do
				local unwrapped = _G.F.unwrapPcSlotData(slot)
				local speciesId = unwrapped and unwrapped.icon and _G.F.safeArrayGet(unwrapped.icon, 1) or nil
				if speciesId ~= nil then
					local key = tostring(speciesId)
					local entry = histogram[key]
					if not entry then
						entry = { count = 0, gleam = 0, boxes = {} }
						histogram[key] = entry
					end
					entry.count = entry.count + 1
					entry.boxes[tostring(boxKey)] = (entry.boxes[tostring(boxKey)] or 0) + 1
					local tier = _G.F.normalizeGleamTier(_G.F.safeArrayGet(unwrapped.icon, 3))
					if tier and tier >= 1 then
						entry.gleam = entry.gleam + 1
					end
				end
			end
		end
	end

	local sorted = {}
	for speciesKey, entry in pairs(histogram) do
		table.insert(sorted, { species = speciesKey, entry = entry })
	end
	table.sort(sorted, function(a, b)
		return a.entry.count > b.entry.count
	end)

	print("[Boonary Diag] species histogram (top 15):")
	for index = 1, math.min(#sorted, 15) do
		local item = sorted[index]
		local boxParts = {}
		for boxKey, count in pairs(item.entry.boxes) do
			table.insert(boxParts, boxKey .. "x" .. count)
		end
		print(string.format("[Boonary Diag]   species=%s count=%d gleam/gamma=%d boxes: %s",
			item.species, item.entry.count, item.entry.gleam, table.concat(boxParts, ", ")))
	end

	-- Ask the server what a few of these actually are; getSummary is what the
	-- real PC UI uses for the stats screen, so it should carry the name.
	local network = _G.F.safeTableGet(_G._p, "Network")
	if type(network) == "table" and type(network.get) == "function" then
		local sampledSpecies = {}
		local sampled = 0
		for _, item in ipairs(sorted) do
			if sampled >= 5 then
				break
			end
			for boxKey, box in pairs(session.boxes) do
				if sampled >= 5 or sampledSpecies[item.species] then
					break
				end
				if type(box) == "table" then
					for _, slot in pairs(box) do
						local unwrapped = _G.F.unwrapPcSlotData(slot)
						local speciesId = unwrapped and unwrapped.icon and _G.F.safeArrayGet(unwrapped.icon, 1) or nil
						if speciesId ~= nil and tostring(speciesId) == item.species then
							local labelIndex = _G.F.safeArrayGet(slot, 1)
							if labelIndex ~= nil then
								sampledSpecies[item.species] = true
								sampled = sampled + 1
								local ok, summary = pcall(function()
									return network:get("PDS", "cPC", "getSummary", labelIndex)
								end)
								print(string.format("[Boonary Diag] getSummary species=%s label=%s -> %s",
									item.species, tostring(labelIndex),
									ok and describeValue(summary, 3) or ("ERROR: " .. tostring(summary))))
								task.wait(0.1)
							end
							break
						end
					end
				end
			end
		end
	else
		print("[Boonary Diag] Network module unavailable; skipped getSummary sampling.")
	end
end

_G.F.tableContainsString = function(value, needle, depth)
	if type(value) == "string" then
		return string.find(string.lower(value), needle, 1, true) ~= nil
	end
	if type(value) ~= "table" or depth <= 0 then
		return false
	end
	local found = false
	pcall(function()
		for _, child in pairs(value) do
			if _G.F.tableContainsString(child, needle, depth - 1) then
				found = true
				break
			end
		end
	end)
	return found
end

_G.F.tableContainsBoonaryString = function(value, depth)
	return _G.F.tableContainsString(value, "boonary", depth)
end

-- The client has no species-name table (names are server-side), so learn
-- which species ids are Boonarys by asking the server for one summary per
-- unique species in the PC and checking it for the string "boonary".
-- The learned set is cached for the rest of the session.
_G.F.learnBoonarySpeciesIds = function(session)
	if _G.F.boonarySpeciesIdSet and next(_G.F.boonarySpeciesIdSet) then
		return _G.F.boonarySpeciesIdSet
	end

	local set = _G.F.getBoonarySpeciesIdSet()
	if next(set) then
		return set
	end

	local network = _G.F.safeTableGet(_G._p, "Network")
	if type(network) ~= "table" or type(network.get) ~= "function" then
		return set
	end

	set = {}
	local keepSet = {}
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
					if ok and _G.F.tableContainsBoonaryString(summary, 4) then
						set[speciesId] = true
						-- sheetType 8 = direct asset-id icon: the gleam/gamma
						-- variant is baked into the asset id itself, with no
						-- per-individual tier in icon[3]. If the summary says
						-- gleam/gamma, every slot with this id is that variant.
						if sheetType == 8 and (_G.F.tableContainsString(summary, "gleam", 4) or _G.F.tableContainsString(summary, "gamma", 4)) then
							keepSet[speciesId] = true
						end
					end
					task.wait(0.05)
				end
			end
		end
	end

	if next(set) then
		_G.F.boonarySpeciesIdSet = set
		_G.F.boonaryKeepSpeciesIdSet = keepSet
	end
	return set
end

-- Sweep every PC box. Per-slot priority: (1) is it a Boonary? (species-id
-- check) -> if not, never touched; (2) is it Gleam/Gamma (or any special
-- gleam tier)? -> skip/keep; (3) otherwise journal a release. dryRun prints
-- what would happen without journaling or committing anything.
_G.F.cleanBoonaryPcBoxes = function(dryRun)
	local session, liveOrReason = _G.F.getPcSession()
	if not session then
		return false, tostring(liveOrReason)
	end
	local isLiveSession = liveOrReason == true

	local print = print
	if dryRun then
		_G.boonaryDiagLines = {}
		print = _G.F.boonaryDiagPrint
		pcall(function()
			_G.F.printBoonaryPcDiagnostics(session, isLiveSession)
		end)
	end

	_G.F.setAutoBoonaryStatus("Identifying Boonary species from server summaries...")
	local learnedIds = {}
	pcall(function()
		learnedIds = _G.F.learnBoonarySpeciesIds(session)
	end)
	if dryRun then
		local idParts = {}
		for id in pairs(learnedIds) do
			table.insert(idParts, tostring(id))
		end
		print("[Boonary Diag] learned boonary species ids: " .. (#idParts > 0 and table.concat(idParts, ", ") or "NONE - every isBoonary check will fail!"))
		local keepParts = {}
		for id in pairs(_G.F.boonaryKeepSpeciesIdSet or {}) do
			table.insert(keepParts, tostring(id))
		end
		if #keepParts > 0 then
			print("[Boonary Diag] asset-id variants kept wholesale (gleam/gamma baked into icon): " .. table.concat(keepParts, ", "))
		end
	end

	-- Hard guarantee: without a positively identified Boonary species id set
	-- (learned from server summaries), refuse to release anything at all.
	-- No name heuristics, no fallbacks.
	if not next(learnedIds) then
		if not isLiveSession then
			_G.F.closePcSession(session)
		end
		local reason = "Could not positively identify the Boonary species from server summaries; refusing to release anything."
		_G.F.setAutoBoonaryStatus(reason)
		return false, reason
	end

	local keepSpeciesIds = _G.F.boonaryKeepSpeciesIdSet or {}
	local boonarySeen = 0
	local kept = 0
	local released = 0
	local skippedNoId = 0

	for boxKey, box in pairs(session.boxes) do
		if type(box) == "table" then
			for slotKey, slot in pairs(box) do
				local unwrapped = _G.F.unwrapPcSlotData(slot)
				-- Exclusive targeting: the slot's species id must be in the
				-- learned Boonary set. Anything else is never touched.
				local slotSpeciesId = unwrapped and unwrapped.icon and tonumber(_G.F.safeArrayGet(unwrapped.icon, 1)) or nil
				if slotSpeciesId ~= nil and learnedIds[slotSpeciesId] == true then
					boonarySeen = boonarySeen + 1

					local tier = _G.F.normalizeGleamTier(_G.F.safeArrayGet(unwrapped.icon, 3))
					local keepByAssetVariant = slotSpeciesId ~= nil and keepSpeciesIds[slotSpeciesId] == true
					if (tier and tier >= 1) or keepByAssetVariant then
						kept = kept + 1
						if dryRun then
							print(string.format("[Boonary PC] box=%s slot=%s tier=%s -> KEEP (%s)",
								tostring(boxKey), tostring(slotKey), tostring(tier),
								keepByAssetVariant and "asset-id variant" or tier == 1 and "Gleaming" or tier == 2 and "Gamma" or "Special"))
						end
					else
						local labelIndex = _G.F.safeArrayGet(slot, 1)
						if labelIndex == nil then
							skippedNoId = skippedNoId + 1
						elseif dryRun then
							released = released + 1
							print(string.format("[Boonary PC] box=%s slot=%s label=%s -> WOULD RELEASE",
								tostring(boxKey), tostring(slotKey), tostring(labelIndex)))
						else
							_G.F.journalPcRelease(session, labelIndex, boxKey, slotKey)
							released = released + 1
						end
					end
				end
			end
		end
	end

	local commitNote = ""
	if not dryRun and released > 0 and isLiveSession then
		commitNote = " (commits when you close the PC)"
	elseif not isLiveSession then
		-- Always close a session we opened ourselves - including dry runs
		-- (empty journal = no changes) - so no PC session is left dangling.
		local ok, reason = _G.F.closePcSession(session)
		if not dryRun and released > 0 then
			if not ok then
				return false, string.format("Saw %d Boonarys, kept %d, but %s", boonarySeen, kept, tostring(reason))
			end
			commitNote = " (committed)"
		end
	end

	local summary = string.format("%sBoonarys: %d seen, %d kept (Gleam/Gamma), %d %s%s%s.",
		dryRun and "[DRY RUN] " or "",
		boonarySeen, kept, released,
		dryRun and "would release" or "released",
		skippedNoId > 0 and (", " .. skippedNoId .. " skipped (no id)") or "",
		commitNote)

	if dryRun and type(_G.boonaryDiagLines) == "table" and writefile then
		pcall(function()
			table.insert(_G.boonaryDiagLines, summary)
			writefile(_G.F.getConfigFilePath("BOONARY-DIAG.txt"), table.concat(_G.boonaryDiagLines, "\n"))
		end)
	end

	_G.F.setAutoBoonaryStatus(summary)
	return true, summary
end

_G.F.printBoonaryStoragePreview = function(groupNumber)
	groupNumber = math.max(1, math.floor(tonumber(groupNumber) or 49))
	print("[Auto Boonary Preview] Starting scan for PC group " .. tostring(groupNumber) .. "...")
	_G.F.setAutoBoonaryStatus("Preview scanning group " .. tostring(groupNumber) .. "...")

	local candidates = _G.F.getFastBoonaryPreviewCandidates()
	print("[Auto Boonary Preview] Fast candidates found: " .. tostring(#candidates))

	if #candidates == 0 then
		local reason = "No fast local storage candidates found."
		print("[Auto Boonary Preview] " .. reason)
		_G.F.setAutoBoonaryStatus(reason)
		return false, reason
	end

	local maxCandidates = math.min(#candidates, 18)
	local bestSource = nil
	local bestEntries = {}
	local bestBoonaries = {}

	for candidateIndex = 1, maxCandidates do
		local candidate = candidates[candidateIndex]
		print(string.format(
			"[Auto Boonary Preview] scanning candidate #%d/%d source=%s keys={%s}",
			candidateIndex,
			maxCandidates,
			tostring(candidate.source),
			tostring(candidate.keys)
		))
		task.wait()

		local allEntries = _G.F.collectStorageGroupEntries(candidate.data, groupNumber, 120)
		local boonaries = {}
		for _, entry in ipairs(allEntries) do
			if _G.F.isBoonaryMonster(entry.monster) then
				table.insert(boonaries, entry)
			end
		end

		print(string.format(
			"[Auto Boonary Preview] candidate #%d entries=%d boonarys=%d",
			candidateIndex,
			#allEntries,
			#boonaries
		))

		if #boonaries > #bestBoonaries or (#boonaries == #bestBoonaries and #allEntries > #bestEntries) then
			bestSource = candidate.source
			bestEntries = allEntries
			bestBoonaries = boonaries
		end

		task.wait()
	end

	local allEntries = bestEntries
	local entries = bestBoonaries
	local kept = 0
	local wouldDelete = 0

	print("[Auto Boonary Preview] Best source=" .. tostring(bestSource) .. " | Group=" .. tostring(groupNumber) .. " | entries seen=" .. tostring(#allEntries) .. " | Boonarys seen=" .. tostring(#entries))

	for index, entry in ipairs(allEntries) do
		local monster = entry.monster
		local name = _G.F.getBoonaryMonsterName(monster)
		local gleamValue = _G.F.getMonsterGleamValue(monster)
		local gammaValue = _G.F.getMonsterGammaValue(monster)
		local isBoonary = _G.F.isBoonaryMonster(monster)
		local keep = isBoonary and _G.F.isKeepBoonary(monster)
		local action = "OTHER"

		if isBoonary then
			if keep then
				kept = kept + 1
				action = "KEEP"
			else
				wouldDelete = wouldDelete + 1
				action = "WOULD DELETE"
			end
		end

		print(string.format(
			"[Auto Boonary Preview] #%d group=%s slot=%s name=%s gleam=%s gamma=%s action=%s keys={%s} fields={%s}",
			index,
			tostring(entry.group),
			tostring(entry.slot),
			tostring(name),
			tostring(gleamValue),
			tostring(gammaValue),
			action,
			_G.F.formatBoonaryTableKeys(monster, 12),
			_G.F.getMonsterDebugText(monster)
		))
	end

	local summary = string.format("Group %d: saw %d, would keep %d, would delete %d.", groupNumber, #entries, kept, wouldDelete)
	print("[Auto Boonary Preview] " .. summary)
	_G.F.setAutoBoonaryStatus(summary)
	return true, summary
end

_G.F.runAutoBoonaryCycle = function()
	if _G.autoBoonaryBusy then
		return false, "Already running."
	end

	_G.autoBoonaryBusy = true
	_G.F.setAutoBoonaryStatus("Activating Gleaming Ro-Powers...")

	local ok, result = _G.F.activateGleamingRoPowers(2)
	if not ok then
		_G.autoBoonaryBusy = false
		_G.F.setAutoBoonaryStatus(result)
		return false, result
	end

	_G.F.setAutoBoonaryStatus("Buying Boonarys from Arcade Prizes...")
	ok, result = _G.F.purchaseMaxArcadeBoonarys()
	if not ok then
		_G.autoBoonaryBusy = false
		_G.F.setAutoBoonaryStatus(result)
		return false, result
	end

	-- No legacy fallback here: cleanBoonaryPcBoxes is the only release path,
	-- and it refuses to act without positive Boonary identification.
	_G.F.setAutoBoonaryStatus("Sweeping PC boxes for Boonarys...")
	ok, result = _G.F.cleanBoonaryPcBoxes(false)

	_G.autoBoonaryBusy = false
	_G.F.setAutoBoonaryStatus(ok and result or tostring(result))
	return ok, result
end

_G.F.setAutoBoonaryEnabled = function(value)
	_G.autoBoonaryEnabled = value and true or false
	if not _G.autoBoonaryEnabled then
		_G.autoBoonaryTriggered = false
		_G.F.setAutoBoonaryStatus("Idle")
	end
end

_G.F.getRanchStatus = function()
	local ok, status = _G.F.rallyPdsGet("ranchStatus")
	if ok and type(status) == "table" then
		return status
	end
	return nil
end

_G.F.getWaitingCount = function()
	local status = _G.F.getRanchStatus()
	if status then
		local count = tonumber(status.rallied)
		if count then
			return count
		end
	end

	local rally = _G.F.ensureRallyModule()
	if rally then
		return tonumber(rally.ralliedCount)
	end

	return nil
end

_G.F.rallyHandleRallied = function(marks)
	local loadingToken = {}

	pcall(function()
		if type(_G._p.DataManager) == "table" and type(_G._p.DataManager.setLoading) == "function" then
			_G._p.DataManager:setLoading(loadingToken, true)
		end
	end)

	local ok, newCount = _G.F.rallyPdsGet("handleRallied", marks)

	pcall(function()
		if type(_G._p.DataManager) == "table" and type(_G._p.DataManager.setLoading) == "function" then
			_G._p.DataManager:setLoading(loadingToken, false)
		end
	end)

	return ok, newCount
end

_G.F.getRalliedMonsterName = function(monster, index)
	local summary = type(monster) == "table" and _G.F.safeTableGet(monster, "summ") or nil
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
	return "Loomian #" .. tostring(index)
end

-- Game Rally UI checks monster.gl == 1 for the gleam icon.
_G.F.isGleaming = function(monster)
	return type(monster) == "table" and monster.gl == 1
end

-- Game Rally UI shows a separate icon when monster.sa is set.
_G.F.isSecretAbility = function(monster)
	if type(monster) ~= "table" then
		return false
	end
	local sa = _G.F.safeTableGet(monster, "sa")
	return sa ~= nil and sa ~= false and sa ~= 0
end

_G.F.isWisp = function(monster)
	if type(monster) ~= "table" then
		return false
	end
	local summary = _G.F.safeTableGet(monster, "summ")
	if type(summary) == "table" and _G.F.truthy(_G.F.safeTableGet(summary, "wisp")) then
		return true
	end
	return _G.F.truthy(_G.F.safeTableGet(monster, "wisp"))
end

_G.F.isAlwaysKeepMatch = function(monster, index)
	if #_G.alwaysKeepList == 0 then
		return false
	end

	local name = string.lower(_G.F.getRalliedMonsterName(monster, index))
	for _, wanted in ipairs(_G.alwaysKeepList) do
		if string.find(name, wanted, 1, true) then
			return true
		end
	end

	return false
end

_G.F.shouldKeepMonster = function(monster, index)
	if _G.keepAll then
		return true, "Keep All"
	end
	if _G.keepGleaming and _G.F.isGleaming(monster) then
		return true, "Gleaming"
	end
	if _G.keepSecretAbility and _G.F.isSecretAbility(monster) then
		return true, "Secret Ability"
	end
	if _G.F.isAlwaysKeepMatch(monster, index) then
		return true, "Always Keep"
	end
	return false
end

_G.F.runAutoRally = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end
	if type(_G._p) ~= "table" then
		return false, "Game hook is not ready."
	end

	_G.F.ensureRallyModule()

	local ranchStatus = _G.F.getRanchStatus()
	local waitingCount = ranchStatus and tonumber(ranchStatus.rallied) or _G.F.getWaitingCount()

	if waitingCount == 0 then
		if ranchStatus and ranchStatus.full then
			_G.lastRallyActionText = "Ranch is full with no inbox to clear."
			_G.F.refreshRallyUI()
			return false, "Ranch is full. Clear your rallied Loomians at Rally Ranch."
		end
		_G.lastRallyActionText = "No rallied Loomians waiting."
		_G.F.refreshRallyUI()
		return false, "No rallied Loomians waiting."
	end

	local ok, data = _G.F.rallyPdsGet("getRallied")
	if not ok then
		_G.lastRallyActionText = "Could not reach Rally service."
		_G.F.refreshRallyUI()
		return false, "Could not reach the Rally service."
	end

	if type(data) ~= "table" or type(data.monsters) ~= "table" or #data.monsters == 0 then
		if waitingCount and waitingCount > 0 then
			_G.lastRallyActionText = string.format("%d waiting but getRallied returned nothing.", waitingCount)
			_G.F.refreshRallyUI()
			return false, string.format("Rally says %d waiting, but getRallied returned no monsters.", waitingCount)
		end
		_G.lastRallyActionText = "No rallied Loomians waiting."
		_G.F.refreshRallyUI()
		return false, "No rallied Loomians waiting."
	end

	local marks = table.create(#data.monsters, 0)
	local kept = 0
	local released = 0
	local keptNames = {}

	for index, monster in ipairs(data.monsters) do
		local keep, reason = _G.F.shouldKeepMonster(monster, index)
		if keep then
			marks[index] = _G.MARK_KEEP
			kept = kept + 1
			table.insert(keptNames, string.format("%s (%s)", _G.F.getRalliedMonsterName(monster, index), reason))
		else
			marks[index] = _G.MARK_RELEASE
			released = released + 1
		end
	end

	if kept == 0 and released == 0 then
		_G.lastRallyActionText = "Nothing marked to keep or release."
		_G.F.refreshRallyUI()
		return false, "Nothing marked to keep or release."
	end

	local handled, newCount = _G.F.rallyHandleRallied(marks)
	if not handled then
		_G.lastRallyActionText = "handleRallied failed."
		_G.F.refreshRallyUI()
		return false, "handleRallied failed."
	end

	_G.rallyKept = _G.rallyKept + kept
	_G.rallyReleased = _G.rallyReleased + released
	_G.lastRallyActionText = string.format("Handled %d: kept %d, released %d.", #data.monsters, kept, released)
	_G.F.refreshRallyUI()
	_G.F.syncRallyBubble(newCount)

	if kept > 0 then
		pcall(function()
			_G.OrionLib:MakeNotification({
				Name = "Rally Keeper",
				Content = string.format("Kept %d: %s", kept, table.concat(keptNames, ", ")),
				Time = 8
			})
		end)
	end

	return true
end


_G.F.shouldCatchWildBattle = function(battle)
	if not _G.autoCatchEnabled then
		return false
	end

	if type(battle) ~= "table" or battle.kind ~= "wild" then
		return false
	end

	if type(_G.F.isCorruptWildFoe) == "function" and _G.F.isCorruptWildFoe(battle) then
		return false
	end

	if _G.F.isFishingGoppieBattle(battle) then
		if not _G.F.hasWildFoeLoaded(battle) then
			return true
		end

		return _G.F.shouldCatchFishingGoppieBattle(battle)
	end

	if not _G.F.hasWildFoeLoaded(battle) then
		return false
	end

	local foe = _G.F.getBattleFoeMonster(battle)
	if _G.F.shouldFilterEncounterTarget() and _G.F.monsterMatchesSearchTarget(foe, _G.encounterTargetLoomian) then
		return true
	end

	if _G.F.isMatchingRoamingLegendaryFoe(battle) then
		return true
	end

	if type(_G.F.getWildSpecialFoeForCatch) == "function" then
		return _G.F.getWildSpecialFoeForCatch(battle) ~= nil
	end

	return _G.F.getWildSpecialFoeForStop(battle) ~= nil
end

return { name = "shops" }
