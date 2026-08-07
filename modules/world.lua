-- world.lua
-- UMV, mining, ctrl-click TP, anti-AFK, jack camera.
_G.F.getRoot = function()
	local ok, root = pcall(function()
		local character = _G.Player.Character or _G.Player.CharacterAdded:Wait()
		return character:FindFirstChild("HumanoidRootPart")
	end)

	if ok then
		return root
	end

	return nil
end

local WallSparkleCollectionService = game:GetService("CollectionService")

_G.F.isWallSparklePart = function(instance)
	local cfg = _G.WALL_SPARKLE_CONFIG
	return instance:IsA("BasePart") and string.lower(instance.Name) == string.lower(cfg.TARGET_NAME)
end

_G.F.getOrCreateWallSparkleChild = function(parent, className, name)
	local existing = parent:FindFirstChild(name)
	if existing and existing.ClassName == className then
		return existing
	end

	local created = Instance.new(className)
	created.Name = name
	created.Parent = parent
	return created
end

_G.F.captureWallSparkleOriginal = function(part)
	if _G.WALL_SPARKLE_ORIGINALS[part] then
		return
	end

	_G.WALL_SPARKLE_ORIGINALS[part] = {
		Material = part.Material,
		Color = part.Color,
		CastShadow = part.CastShadow,
	}
end

_G.F.applyWallSparkleMarker = function(part)
	if not _G.F.isWallSparklePart(part) then
		return false
	end

	local cfg = _G.WALL_SPARKLE_CONFIG
	_G.F.captureWallSparkleOriginal(part)

	part:SetAttribute("ThroughWallsVisible", true)
	part.Material = Enum.Material.Neon
	part.Color = cfg.PART_COLOR
	part.CastShadow = false

	local highlight = _G.F.getOrCreateWallSparkleChild(part, "Highlight", cfg.HIGHLIGHT_NAME)
	highlight.Adornee = part
	highlight.Enabled = true
	highlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
	highlight.FillColor = cfg.FILL_COLOR
	highlight.OutlineColor = cfg.OUTLINE_COLOR
	highlight.FillTransparency = 0.35
	highlight.OutlineTransparency = 0

	local billboard = _G.F.getOrCreateWallSparkleChild(part, "BillboardGui", cfg.BILLBOARD_NAME)
	billboard.Adornee = part
	billboard.AlwaysOnTop = true
	billboard.Enabled = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 100000
	billboard.Size = UDim2.fromOffset(34, 18)
	billboard.StudsOffsetWorldSpace = Vector3.new(0, 1.15, 0)

	local label = _G.F.getOrCreateWallSparkleChild(billboard, "TextLabel", "Label")
	label.BackgroundTransparency = 0.15
	label.BackgroundColor3 = Color3.fromRGB(8, 17, 23)
	label.BorderSizePixel = 0
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = "WS"
	label.TextColor3 = Color3.fromRGB(255, 236, 122)
	label.TextScaled = true
	label.TextStrokeTransparency = 0.35
	label.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)

	if not WallSparkleCollectionService:HasTag(part, cfg.TAG_NAME) then
		WallSparkleCollectionService:AddTag(part, cfg.TAG_NAME)
	end

	return true
end

_G.F.removeWallSparkleMarker = function(part)
	if not part or not part:IsA("BasePart") then
		return
	end

	local cfg = _G.WALL_SPARKLE_CONFIG
	local highlight = part:FindFirstChild(cfg.HIGHLIGHT_NAME)
	if highlight then
		highlight:Destroy()
	end

	local billboard = part:FindFirstChild(cfg.BILLBOARD_NAME)
	if billboard then
		billboard:Destroy()
	end

	part:SetAttribute("ThroughWallsVisible", nil)

	if WallSparkleCollectionService:HasTag(part, cfg.TAG_NAME) then
		WallSparkleCollectionService:RemoveTag(part, cfg.TAG_NAME)
	end

	local original = _G.WALL_SPARKLE_ORIGINALS[part]
	if original then
		part.Material = original.Material
		part.Color = original.Color
		part.CastShadow = original.CastShadow
		_G.WALL_SPARKLE_ORIGINALS[part] = nil
	end
end

_G.F.scanWallSparkleParts = function()
	local count = 0

	for _, instance in ipairs(workspace:GetDescendants()) do
		if _G.F.isWallSparklePart(instance) and _G.F.applyWallSparkleMarker(instance) then
			count += 1
		end
	end

	_G.wallSparkleUmvCount = count
	return count
end

_G.F.setWallSparkleUmvStatus = function(text)
	local statusText = tostring(text or "Idle")

	if _G.wallSparkleUmvStatusLabel and type(_G.wallSparkleUmvStatusLabel.Set) == "function" then
		pcall(function()
			_G.wallSparkleUmvStatusLabel:Set("Status: " .. statusText)
		end)
	end
end

_G.F.refreshWallSparkleUmvUi = function()
	if _G.wallSparkleUmvCountLabel and type(_G.wallSparkleUmvCountLabel.Set) == "function" then
		pcall(function()
			_G.wallSparkleUmvCountLabel:Set("Marked: " .. tostring(_G.wallSparkleUmvCount or 0))
		end)
	end
end

_G.F.refreshUmvMiningUi = function()
	if _G.umvMiningRevealedCountLabel and type(_G.umvMiningRevealedCountLabel.Set) == "function" then
		pcall(function()
			_G.umvMiningRevealedCountLabel:Set("Revealed: " .. tostring(_G.umvMiningRevealedCount or 0))
		end)
	end
end

_G.F.clearAllWallSparkleMarkers = function()
	local cfg = _G.WALL_SPARKLE_CONFIG

	for _, part in ipairs(WallSparkleCollectionService:GetTagged(cfg.TAG_NAME)) do
		_G.F.removeWallSparkleMarker(part)
	end

	for _, instance in ipairs(workspace:GetDescendants()) do
		if _G.F.isWallSparklePart(instance) and instance:GetAttribute("ThroughWallsVisible") then
			_G.F.removeWallSparkleMarker(instance)
		end
	end

	_G.wallSparkleUmvCount = 0
	_G.F.refreshWallSparkleUmvUi()
end

_G.F.setWallSparkleUmvEnabled = function(value)
	value = value and true or false
	if _G.wallSparkleUmvEnabled == value then
		return
	end

	_G.wallSparkleUmvEnabled = value

	if value then
		if not _G.wallSparkleUmvDescendantConnection then
			_G.wallSparkleUmvDescendantConnection = workspace.DescendantAdded:Connect(function(instance)
				if _G.wallSparkleUmvEnabled and _G.F.isWallSparklePart(instance) then
					if _G.F.applyWallSparkleMarker(instance) then
						_G.wallSparkleUmvCount += 1
						_G.F.refreshWallSparkleUmvUi()
					end
				end
			end)
		end

		local count = _G.F.scanWallSparkleParts()
		_G.F.setWallSparkleUmvStatus(string.format("Enabled ÃƒÆ’Ã†â€™Ãƒâ€šÃ‚Â¢ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â€šÂ¬Ã…Â¡Ãƒâ€šÃ‚Â¬ÃƒÆ’Ã‚Â¢ÃƒÂ¢Ã¢â‚¬Å¡Ã‚Â¬Ãƒâ€šÃ‚Â %d WallSparkle part(s) marked.", count))
	else
		if _G.wallSparkleUmvDescendantConnection then
			_G.wallSparkleUmvDescendantConnection:Disconnect()
			_G.wallSparkleUmvDescendantConnection = nil
		end

		_G.F.clearAllWallSparkleMarkers()
		_G.F.setWallSparkleUmvStatus("Disabled.")
	end

	_G.F.refreshWallSparkleUmvUi()
end

_G.F.umvMiningAssetId = function(value)
	return tostring(value or ""):match("%d+")
end

_G.F.umvMiningSameAtlas = function(guiObject)
	return _G.F.umvMiningAssetId(guiObject.Image) == _G.UMV_MINING_ATLAS_ID
end

_G.F.umvMiningIsMiningGrid = function(candidate)
	if not candidate:IsA("ImageButton") then
		return false
	end

	if not _G.F.umvMiningSameAtlas(candidate) then
		return false
	end

	return candidate.ImageRectSize == Vector2.new(352, 256)
		and candidate.ImageRectOffset == Vector2.new(16, 16)
end

_G.F.isUmvMiningHiddenIcon = function(descendant)
	if not descendant:IsA("ImageLabel") or not _G.F.umvMiningSameAtlas(descendant) then
		return false
	end

	if descendant:GetAttribute("UmvMiningHiddenItem") then
		return true
	end

	return descendant.ZIndex == 3
end

_G.F.umvMiningGetRevealZIndex = function(grid)
	local maxZ = grid.ZIndex or 1

	for _, descendant in ipairs(grid:GetDescendants()) do
		if descendant:IsA("GuiObject") and not _G.F.isUmvMiningHiddenIcon(descendant) then
			maxZ = math.max(maxZ, descendant.ZIndex)
		end
	end

	return maxZ + 10
end

_G.F.applyUmvMiningReveal = function(icon, grid)
	if not _G.F.isUmvMiningHiddenIcon(icon) then
		return false
	end

	if not grid or not _G.F.umvMiningIsMiningGrid(grid) then
		return false
	end

	if not _G.umvMiningRevealOriginals[icon] then
		_G.umvMiningRevealOriginals[icon] = {
			ZIndex = icon.ZIndex,
			ImageTransparency = icon.ImageTransparency,
			BackgroundTransparency = icon.BackgroundTransparency,
			Active = icon.Active,
			Selectable = icon.Selectable,
			Visible = icon.Visible,
		}
	end

	icon:SetAttribute("UmvMiningHiddenItem", true)
	icon.ZIndex = _G.F.umvMiningGetRevealZIndex(grid)
	icon.ImageTransparency = 0
	icon.BackgroundTransparency = 1
	icon.Active = false
	icon.Selectable = false
	icon.Visible = true

	return true
end

_G.F.removeUmvMiningReveal = function(icon)
	if not icon or not icon:IsA("GuiObject") then
		return
	end

	local original = _G.umvMiningRevealOriginals[icon]
	if original then
		icon.ZIndex = original.ZIndex
		icon.ImageTransparency = original.ImageTransparency
		icon.BackgroundTransparency = original.BackgroundTransparency
		icon.Active = original.Active
		icon.Selectable = original.Selectable
		icon.Visible = original.Visible
		_G.umvMiningRevealOriginals[icon] = nil
	end

	icon:SetAttribute("UmvMiningHiddenItem", nil)
end

_G.F.clearUmvMiningReveal = function()
	local icons = {}
	for icon in pairs(_G.umvMiningRevealOriginals) do
		table.insert(icons, icon)
	end

	for _, icon in ipairs(icons) do
		_G.F.removeUmvMiningReveal(icon)
	end

	_G.umvMiningRevealedCount = 0
	_G.F.refreshUmvMiningUi()
end

_G.F.revealUmvMiningHiddenItems = function()
	local player = _G.Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return 0
	end

	local count = 0

	for _, grid in ipairs(_G.F.umvMiningFindGrids(playerGui)) do
		for _, descendant in ipairs(grid:GetDescendants()) do
			if _G.F.isUmvMiningHiddenIcon(descendant) and _G.F.applyUmvMiningReveal(descendant, grid) then
				count += 1
			end
		end
	end

	_G.umvMiningRevealedCount = count
	_G.F.refreshUmvMiningUi()
	return count
end

_G.F.umvMiningFindGrids = function(playerGui)
	local grids = {}

	for _, descendant in ipairs(playerGui:GetDescendants()) do
		if _G.F.umvMiningIsMiningGrid(descendant) then
			table.insert(grids, descendant)
		end
	end

	return grids
end

_G.F.onUmvMiningPlayerGuiDescendant = function(descendant)
	if _G.F.umvMiningIsMiningGrid(descendant) then
		if _G.umvMiningRevealEnabled then
			task.defer(_G.F.revealUmvMiningHiddenItems)
		end
		return
	end

	if not _G.umvMiningRevealEnabled or not _G.F.isUmvMiningHiddenIcon(descendant) then
		return
	end

	local parent = descendant.Parent
	while parent do
		if _G.F.umvMiningIsMiningGrid(parent) then
			if _G.F.applyUmvMiningReveal(descendant, parent) then
				_G.umvMiningRevealedCount += 1
				_G.F.refreshUmvMiningUi()
			end
			break
		end
		parent = parent.Parent
	end
end

_G.F.stopUmvMiningPlayerGuiWatcher = function()
	if _G.umvMiningRevealEnabled then
		return
	end

	if _G.umvMiningPlayerGuiWatchConnection then
		_G.umvMiningPlayerGuiWatchConnection:Disconnect()
		_G.umvMiningPlayerGuiWatchConnection = nil
	end
end

_G.F.ensureUmvMiningPlayerGuiWatcher = function()
	if not _G.umvMiningRevealEnabled or _G.umvMiningPlayerGuiWatchConnection then
		return
	end

	local player = _G.Players.LocalPlayer
	local playerGui = player and player:FindFirstChildOfClass("PlayerGui")
	if not playerGui then
		return
	end

	_G.umvMiningPlayerGuiWatchConnection = playerGui.DescendantAdded:Connect(_G.F.onUmvMiningPlayerGuiDescendant)
end

_G.F.startUmvMiningRevealLoop = function()
	if _G.umvMiningRevealLoopAlive then
		return
	end

	_G.umvMiningRevealLoopAlive = true

	task.spawn(function()
		while _G.umvMiningRevealEnabled and _G.uiAlive do
			_G.F.revealUmvMiningHiddenItems()
			task.wait(0.35)
		end

		_G.umvMiningRevealLoopAlive = false
	end)
end

_G.F.setUmvMiningRevealEnabled = function(value)
	value = value and true or false
	if _G.umvMiningRevealEnabled == value then
		return
	end

	_G.umvMiningRevealEnabled = value

	if value then
		_G.F.ensureUmvMiningPlayerGuiWatcher()

		if not _G.umvMiningPlayerGuiWatchConnection then
			task.spawn(function()
				local player = _G.Players.LocalPlayer
				if not player then
					return
				end

				player:WaitForChild("PlayerGui", 30)
				_G.F.ensureUmvMiningPlayerGuiWatcher()

				if _G.umvMiningRevealEnabled then
					_G.F.revealUmvMiningHiddenItems()
					_G.F.startUmvMiningRevealLoop()
				end
			end)
		else
			_G.F.revealUmvMiningHiddenItems()
			_G.F.startUmvMiningRevealLoop()
		end
	else
		_G.F.clearUmvMiningReveal()
		_G.F.stopUmvMiningPlayerGuiWatcher()
	end
end

-- UMV remote sparkle miner: TP to nearest WS sparkle, sync mine point, fire game click.
_G.remoteSparkleMineEnabled = false
_G.remoteSparkleMineKeyConnection = nil
_G.remoteSparkleMineStatusLabel = nil
_G.REMOTE_SPARKLE_STANDOFF = 10
_G.REMOTE_SPARKLE_FRONT_CLEARANCE = 3
_G.REMOTE_SPARKLE_Y_PADDING_BELOW = 8
_G.REMOTE_SPARKLE_Y_PADDING_ABOVE = 5
_G._remoteSparkleYLimitsCache = nil
_G.cachedMiningModule = nil
_G.cachedMiningModuleAt = 0
_G.MINING_MODULE_CACHE_TTL = 1.5

_G.F.clearRemoteSparkleYLimitsCache = function()
	_G._remoteSparkleYLimitsCache = nil
end

_G.F.clearMiningModuleCache = function()
	_G.cachedMiningModule = nil
	_G.cachedMiningModuleAt = 0
end

_G.F.partIsNamedWall = function(part)
	return typeof(part) == "Instance" and part:IsA("BasePart") and string.lower(part.Name) == "wall"
end

_G.F.getMiningChunk = function()
	for _, chunkName in ipairs({ "chunk17b", "chunk17a", "chunk17c" }) do
		local chunk = workspace:FindFirstChild(chunkName)
		if chunk then
			return chunk
		end
	end

	return nil
end

_G.F.getBeastsChunkMap = function()
	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local currentChunk = type(_G._p) == "table" and _G._p.DataManager and _G._p.DataManager.currentChunk or nil

	if type(currentChunk) == "table" then
		if currentChunk.map then
			return currentChunk.map
		end

		if type(currentChunk.GetMap) == "function" then
			local ok, map = pcall(function()
				return currentChunk:GetMap()
			end)

			if ok and map then
				return map
			end
		end
	end

	-- The chunk map goes nil while a soft reset reloads the chunk, and this
	-- gets polled every tick; reuse the last found map and keep the tree
	-- searches below on a cooldown instead of sweeping workspace each call.
	local cached = _G._beastsChunkMapCache
	if typeof(cached) == "Instance" and cached:IsDescendantOf(game) then
		return cached
	end
	_G._beastsChunkMapCache = nil

	local now = os.clock()
	if _G._beastsChunkScanAt and now - _G._beastsChunkScanAt < 3 then
		return nil
	end
	_G._beastsChunkScanAt = now

	for _, chunkName in ipairs({ "chunk27", "Chunk27" }) do
		local wsChunk = workspace:FindFirstChild(chunkName)
		if wsChunk then
			if wsChunk:FindFirstChild("SoftResetTriggers", true) then
				_G._beastsChunkMapCache = wsChunk
				return wsChunk
			end

			local nestedMap = wsChunk:FindFirstChild("map")
			if nestedMap and nestedMap:FindFirstChild("SoftResetTriggers", true) then
				_G._beastsChunkMapCache = nestedMap
				return nestedMap
			end
		end
	end

	for _, descendant in ipairs(workspace:GetDescendants()) do
		if descendant.Name == "SoftResetTriggers" then
			local lavaTrigger = descendant:FindFirstChild("Lava")
			if lavaTrigger and lavaTrigger:IsA("BasePart") then
				_G._beastsChunkMapCache = descendant.Parent
				return descendant.Parent
			end
		end
	end

	return nil
end

_G.F.getSelectedBeastName = function()
	local name = tostring(_G.beastTarget or "")
	if _G.BEAST_HUNTS[name] then
		return name
	end

	return "Arceros"
end

_G.F.getBeastTrigger = function(beastName)
	if not _G.BEAST_HUNTS[beastName] then
		beastName = _G.F.getSelectedBeastName()
	end

	local map = _G.F.getBeastsChunkMap()
	if not map then
		return nil, nil
	end

	-- Reuse the last resolved trigger while it still belongs to the current
	-- map; this gets polled every tick, so avoid re-walking the map tree.
	_G._beastTriggerCache = _G._beastTriggerCache or {}

	local cached = _G._beastTriggerCache[beastName]
	if typeof(cached) == "Instance" and cached:IsDescendantOf(map) then
		return cached, map
	end
	_G._beastTriggerCache[beastName] = nil

	local triggers = map:FindFirstChild("SoftResetTriggers")
	if not triggers then
		local now = os.clock()
		if _G._beastTriggerScanAt and now - _G._beastTriggerScanAt < 3 then
			return nil, map
		end
		_G._beastTriggerScanAt = now

		for _, descendant in ipairs(map:GetDescendants()) do
			if descendant.Name == "SoftResetTriggers" then
				triggers = descendant
				break
			end
		end
	end

	if not triggers then
		return nil, map
	end

	for _, triggerName in ipairs(_G.BEAST_HUNTS[beastName].triggerNames) do
		local trigger = triggers:FindFirstChild(triggerName)
		if trigger and trigger:IsA("BasePart") then
			_G._beastTriggerCache[beastName] = trigger
			return trigger, map
		end
	end

	-- Trigger names can change between game updates; fall back to any
	-- BasePart trigger that no other beast's name list claims.
	local claimed = {}
	for otherName, otherInfo in pairs(_G.BEAST_HUNTS) do
		if otherName ~= beastName then
			for _, triggerName in ipairs(otherInfo.triggerNames) do
				claimed[string.lower(triggerName)] = true
			end
		end
	end

	for _, child in ipairs(triggers:GetChildren()) do
		if child:IsA("BasePart") and not claimed[string.lower(child.Name)] then
			_G._beastTriggerCache[beastName] = child
			return child, map
		end
	end

	return nil, map
end

_G.F.getSelectedBeastTrigger = function()
	return _G.F.getBeastTrigger(_G.F.getSelectedBeastName())
end

_G.F.getArcerosLavaTrigger = function()
	return _G.F.getBeastTrigger("Arceros")
end

_G.F.getBeastBattleScene = function(beastName)
	if not _G.BEAST_HUNTS[beastName] then
		beastName = _G.F.getSelectedBeastName()
	end

	local map = _G.F.getBeastsChunkMap()
	if not map then
		return nil
	end

	local scenes = map:FindFirstChild("BuiltInBattleScenes")
	if not scenes then
		for _, descendant in ipairs(map:GetDescendants()) do
			if descendant.Name == "BuiltInBattleScenes" then
				scenes = descendant
				break
			end
		end
	end

	if not scenes then
		return nil
	end

	-- Scene children mirror the trigger names (e.g. "Lava").
	for _, sceneName in ipairs(_G.BEAST_HUNTS[beastName].triggerNames) do
		local scene = scenes:FindFirstChild(sceneName)
		if scene then
			return scene
		end
	end

	return nil
end

_G.F.getArcerosBattleScene = function()
	return _G.F.getBeastBattleScene("Arceros")
end

_G.F.getMiningWallsModel = function()
	local chunk = _G.F.getMiningChunk()
	if not chunk then
		return nil
	end

	local walls = chunk:FindFirstChild("Walls")
	if walls then
		return walls
	end

	local map = chunk:FindFirstChild("map")
	if map then
		return map:FindFirstChild("Walls")
	end

	return nil
end

_G.F.getRemoteSparkleYLimits = function()
	if _G._remoteSparkleYLimitsCache then
		return _G._remoteSparkleYLimitsCache[1], _G._remoteSparkleYLimitsCache[2]
	end

	local yMin = math.huge
	local yMax = -math.huge

	local function absorbPart(part)
		if not part:IsA("BasePart") then
			return
		end

		local halfY = part.Size.Y * 0.5
		yMin = math.min(yMin, part.Position.Y - halfY)
		yMax = math.max(yMax, part.Position.Y + halfY)
	end

	local walls = _G.F.getMiningWallsModel()
	if walls then
		for _, descendant in ipairs(walls:GetDescendants()) do
			absorbPart(descendant)
		end
	end

	local chunk = _G.F.getMiningChunk()
	if chunk then
		for _, descendant in ipairs(chunk:GetDescendants()) do
			if _G.F.partIsNamedWall(descendant) then
				absorbPart(descendant)
			end
		end
	end

	if yMin == math.huge then
		yMin, yMax = -500, 500
	else
		yMin -= _G.REMOTE_SPARKLE_Y_PADDING_BELOW
		yMax += _G.REMOTE_SPARKLE_Y_PADDING_ABOVE
	end

	_G._remoteSparkleYLimitsCache = { yMin, yMax }
	return yMin, yMax
end

_G.F.clampRemoteSparkleY = function(y)
	local yMin, yMax = _G.F.getRemoteSparkleYLimits()
	return math.clamp(y, yMin, yMax)
end

_G.F.isSparkleWithinYLimits = function(sparklePart)
	if typeof(sparklePart) ~= "Instance" then
		return false
	end

	local yMin, yMax = _G.F.getRemoteSparkleYLimits()
	local sparkleY = sparklePart.Position.Y
	return sparkleY >= yMin and sparkleY <= yMax
end

_G.F.isSparkleTouchingWall = function(sparklePart)
	if typeof(sparklePart) ~= "Instance" or not sparklePart:IsA("BasePart") then
		return false
	end

	local ok, touchingParts = pcall(function()
		return sparklePart:GetTouchingParts()
	end)

	if ok and type(touchingParts) == "table" then
		for _, part in touchingParts do
			if _G.F.partIsNamedWall(part) then
				return true
			end
		end
	end

	local probeDirections = {
		sparklePart.CFrame.LookVector,
		-sparklePart.CFrame.LookVector,
		sparklePart.CFrame.RightVector,
		-sparklePart.CFrame.RightVector,
		sparklePart.CFrame.UpVector,
		-sparklePart.CFrame.UpVector,
	}

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { sparklePart }

	for _, direction in ipairs(probeDirections) do
		if direction.Magnitude > 0.01 then
			local hit = workspace:Raycast(sparklePart.Position, direction.Unit * 4, params)
			if hit and _G.F.partIsNamedWall(hit.Instance) then
				return true
			end
		end
	end

	local wallsModel = _G.F.getMiningWallsModel()
	if wallsModel then
		for _, descendant in ipairs(wallsModel:GetDescendants()) do
			if _G.F.partIsNamedWall(descendant) then
				local localPosition = descendant.CFrame:PointToObjectSpace(sparklePart.Position)
				local halfSize = descendant.Size * 0.5
				local offsetX = math.max(math.abs(localPosition.X) - halfSize.X, 0)
				local offsetY = math.max(math.abs(localPosition.Y) - halfSize.Y, 0)
				local offsetZ = math.max(math.abs(localPosition.Z) - halfSize.Z, 0)
				if Vector3.new(offsetX, offsetY, offsetZ).Magnitude <= 2.5 then
					return true
				end
			end
		end
	end

	return false
end

_G.F.getSparkleFrontVector = function(sparklePart)
	if typeof(sparklePart) ~= "Instance" or not sparklePart:IsA("BasePart") then
		return nil
	end

	local front = sparklePart.CFrame.LookVector
	front = Vector3.new(front.X, 0, front.Z)
	if front.Magnitude < 0.05 then
		return nil
	end

	return front.Unit
end

_G.F.raycastSparkleWall = function(sparklePart, direction, distance)
	if typeof(sparklePart) ~= "Instance" or not sparklePart:IsA("BasePart") or typeof(direction) ~= "Vector3" then
		return nil
	end

	if direction.Magnitude < 0.01 then
		return nil
	end

	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { sparklePart }

	local ok, hit = pcall(function()
		return workspace:Raycast(sparklePart.Position, direction.Unit * (distance or 5), params)
	end)

	if ok and hit and _G.F.partIsNamedWall(hit.Instance) then
		return hit
	end

	return nil
end

_G.F.getSparkleTeleportFrontVector = function(sparklePart)
	local front = _G.F.getSparkleFrontVector(sparklePart)
	if not front then
		return nil
	end

	local frontWall = _G.F.raycastSparkleWall(sparklePart, front, 5)
	local backWall = _G.F.raycastSparkleWall(sparklePart, -front, 5)

	-- Prefer the open side of the sparkle's Front face. If the wall is in
	-- front, stand behind it instead; if the wall is behind, stand in front.
	if frontWall and not backWall then
		return -front
	end

	return front
end

_G.F.isSparkleFrontFaceUsable = function(sparklePart)
	local front = _G.F.getSparkleTeleportFrontVector(sparklePart)
	if not front then
		return false
	end

	local wallBehind = _G.F.raycastSparkleWall(sparklePart, -front, 5)
	local wallAhead = _G.F.raycastSparkleWall(sparklePart, front, _G.REMOTE_SPARKLE_FRONT_CLEARANCE)

	return wallBehind ~= nil and wallAhead == nil
end

_G.F.isValidMiningSparkle = function(sparklePart)
	return _G.F.isWallSparklePart(sparklePart)
		and _G.F.isSparkleWithinYLimits(sparklePart)
		and _G.F.isSparkleTouchingWall(sparklePart)
		and _G.F.isSparkleFrontFaceUsable(sparklePart)
end

_G.F.setRemoteSparkleMineStatus = function(text)
	if _G.remoteSparkleMineStatusLabel and type(_G.remoteSparkleMineStatusLabel.Set) == "function" then
		pcall(function()
			_G.remoteSparkleMineStatusLabel:Set("Remote Mine: " .. tostring(text))
		end)
	end
end

_G.F.getActiveWallSparkles = function()
	local sparkles = {}

	for _, inst in ipairs(workspace:GetDescendants()) do
		if inst.Parent == workspace and _G.F.isValidMiningSparkle(inst) then
			table.insert(sparkles, inst)
		end
	end

	if #sparkles == 0 then
		for _, inst in ipairs(workspace:GetDescendants()) do
			if _G.F.isValidMiningSparkle(inst) then
				table.insert(sparkles, inst)
			end
		end
	end

	return sparkles
end

_G.F.getNearestWallSparkle = function(worldPosition)
	if typeof(worldPosition) ~= "Vector3" then
		return nil
	end

	local ranked = {}

	for _, sparkle in ipairs(_G.F.getActiveWallSparkles()) do
		table.insert(ranked, {
			part = sparkle,
			distance = (worldPosition - sparkle.Position).Magnitude,
		})
	end

	table.sort(ranked, function(a, b)
		return a.distance < b.distance
	end)

	if ranked[1] then
		return ranked[1].part
	end

	return nil
end

_G.F.temporarilyDisableCharacterCollision = function(character, duration)
	if typeof(character) ~= "Instance" then
		return
	end

	local originals = {}
	for _, descendant in ipairs(character:GetDescendants()) do
		if descendant:IsA("BasePart") then
			originals[descendant] = descendant.CanCollide
			pcall(function()
				descendant.CanCollide = false
			end)
		end
	end

	task.delay(duration or 1.25, function()
		for part, canCollide in pairs(originals) do
			if typeof(part) == "Instance" and part.Parent then
				pcall(function()
					part.CanCollide = canCollide
				end)
			end
		end
	end)
end

_G.F.teleportCharacterToSparkle = function(sparklePart)
	local player = _G.Players.LocalPlayer
	local character = player and player.Character
	local humanoidRootPart = character and character:FindFirstChild("HumanoidRootPart")
	if not humanoidRootPart or typeof(sparklePart) ~= "Instance" then
		return false
	end

	if not _G.F.isValidMiningSparkle(sparklePart) then
		return false
	end

	local sparklePosition = sparklePart.Position
	local front = _G.F.getSparkleTeleportFrontVector(sparklePart)
	if not front then
		return false
	end

	_G.F.temporarilyDisableCharacterCollision(character, 1.5)
	pcall(function()
		humanoidRootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
		humanoidRootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
	end)

	local stand = sparklePosition + front * _G.REMOTE_SPARKLE_STANDOFF
	local standY = _G.F.clampRemoteSparkleY(sparklePosition.Y + 2)
	humanoidRootPart.CFrame = CFrame.new(
		Vector3.new(stand.X, standY, stand.Z),
		sparklePosition
	)
	return true
end

_G.F.findMinePointForSparkle = function(sparklePart, mining)
	if typeof(sparklePart) ~= "Instance" then
		return nil
	end

	mining = mining or _G.F.getMiningModule(true)
	if not mining then
		return nil
	end

	local minePoints = _G.F.safeTableGet(mining, "MinePoints")
	if type(minePoints) ~= "table" then
		return nil
	end

	for _, minePoint in pairs(minePoints) do
		if type(minePoint) == "table" and _G.F.safeTableGet(minePoint, "Part") == sparklePart then
			return minePoint
		end
	end

	local nearestPoint = nil
	local nearestDistance = nil

	for _, minePoint in pairs(minePoints) do
		if type(minePoint) == "table" then
			local part = _G.F.safeTableGet(minePoint, "Part")
			if part and part.Parent then
				local distance = (part.Position - sparklePart.Position).Magnitude
				if not nearestDistance or distance < nearestDistance then
					nearestPoint = minePoint
					nearestDistance = distance
				end
			end
		end
	end

	return nearestPoint
end

_G.F.syncMinePointForSparkle = function(sparklePart)
	if typeof(sparklePart) ~= "Instance" then
		return false
	end

	local targetPosition = sparklePart.Position
	local targetCFrame = sparklePart.CFrame

	local function applyToMinePoint(minePoint)
		if type(minePoint) ~= "table" then
			return false
		end

		return pcall(function()
			minePoint.Position = targetPosition
			minePoint.CFrame = targetCFrame
		end)
	end

	local mining = _G.F.getMiningModule(true)
	local minePoint = _G.F.findMinePointForSparkle(sparklePart, mining)
	if minePoint and applyToMinePoint(minePoint) then
		return true
	end

	if type(getconnections) ~= "function" or type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
		return false
	end

	local player = _G.Players.LocalPlayer
	local mouse = player and player:GetMouse()
	if not mouse then
		return false
	end

	local ok, connections = pcall(getconnections, mouse.Button1Down)
	if not ok or type(connections) ~= "table" then
		return false
	end

	for _, connection in ipairs(connections) do
		local handler = connection.Function
		if type(handler) ~= "function" then
			continue
		end

		for index = 1, 128 do
			local uvOk, value = pcall(debug.getupvalue, handler, index)
			if not uvOk then
				break
			end

			if type(value) == "table" then
				local minePoints = _G.F.safeTableGet(value, "MinePoints")
				if type(minePoints) == "table" then
					local matched = _G.F.findMinePointForSparkle(sparklePart, value)
					if matched and applyToMinePoint(matched) then
						return true
					end
				end
			end
		end
	end

	return false
end

_G.F.isMiningClickHandler = function(handler)
	if type(handler) ~= "function" or type(debug) ~= "table" or type(debug.getupvalue) ~= "function" then
		return false
	end

	for index = 1, 64 do
		local uvOk, value = pcall(debug.getupvalue, handler, index)
		if not uvOk then
			break
		end

		if type(value) == "table" and type(_G.F.safeTableGet(value, "MinePoints")) == "table" then
			return true
		end
	end

	return false
end

_G.F.fireGameMiningClick = function()
	if type(getconnections) ~= "function" then
		return false, "Executor needs getconnections."
	end

	local player = _G.Players.LocalPlayer
	local mouse = player and player:GetMouse()
	if not mouse then
		return false, "No mouse."
	end

	local ok, connections = pcall(getconnections, mouse.Button1Down)
	if not ok or type(connections) ~= "table" or #connections == 0 then
		return false, "No mining click handler. Click a wall once first."
	end

	for _, connection in ipairs(connections) do
		local handler = connection.Function
		if type(handler) == "function" and _G.F.isMiningClickHandler(handler) and pcall(handler) then
			return true
		end
	end

	for _, connection in ipairs(connections) do
		if type(connection.Function) == "function" and pcall(connection.Function) then
			return true
		end
	end

	return false, "Mining click handler failed."
end

_G.F.runRemoteSparkleMine = function()
	local player = _G.Players.LocalPlayer
	local mouse = player and player:GetMouse()
	if not mouse then
		return false, "No mouse."
	end

	local sparkles = _G.F.getActiveWallSparkles()
	if #sparkles == 0 then
		return false, "No valid sparkles (need Wall contact, front face, and Y bounds)."
	end

	local sparkle = _G.F.getNearestWallSparkle(mouse.Hit.Position)
	if not sparkle then
		return false, "No valid sparkle near crosshair."
	end

	return _G.F.runRemoteSparkleMineAt(sparkle)
end

_G.F.setRemoteSparkleMineEnabled = function(value)
	value = value and true or false
	if _G.remoteSparkleMineEnabled == value then
		return
	end

	_G.remoteSparkleMineEnabled = value

	_G.F.clearRemoteSparkleYLimitsCache()

	if _G.remoteSparkleMineKeyConnection then
		_G.remoteSparkleMineKeyConnection:Disconnect()
		_G.remoteSparkleMineKeyConnection = nil
	end

	if not value then
		_G.F.setRemoteSparkleMineStatus("Off")
		return
	end

	_G.remoteSparkleMineKeyConnection = _G.UserInputService.InputBegan:Connect(function(input, processed)
		if processed or not _G.remoteSparkleMineEnabled then
			return
		end
		if input.KeyCode ~= Enum.KeyCode.E then
			return
		end

		_G.F.setRemoteSparkleMineStatus("Mining...")
		task.spawn(function()
			local ok, reason = _G.F.runRemoteSparkleMine()
			if ok then
				_G.F.setRemoteSparkleMineStatus("Done - press E for next.")
			else
				_G.F.setRemoteSparkleMineStatus(reason or "Failed")
			end
		end)
	end)

	_G.F.setRemoteSparkleMineStatus("Ready - " .. tostring(#_G.F.getActiveWallSparkles()) .. " sparkle(s). Press E.")
end


_G.F.isMiningModuleTable = function(candidate)
	if type(candidate) ~= "table" then
		return false
	end

	local minePoints = _G.F.safeTableGet(candidate, "MinePoints")
	local startDive = _G.F.safeTableGet(candidate, "StartDive")
	local createMinePoint = _G.F.safeTableGet(candidate, "CreateMinePoint")
	local batteryLevel = _G.F.safeTableGet(candidate, "BatteryLevel")

	return type(minePoints) == "table"
		and type(startDive) == "function"
		and type(createMinePoint) == "function"
		and type(batteryLevel) == "number"
end

_G.F.scanFunctionUpvaluesForMiningModule = function()
	if type(debug) ~= "table" or type(debug.getregistry) ~= "function" or type(debug.getupvalue) ~= "function" then
		return nil
	end

	local ok, registry = pcall(debug.getregistry)
	if not ok or type(registry) ~= "table" then
		return nil
	end

	for _, fn in pairs(registry) do
		if type(fn) == "function" then
			for index = 1, 160 do
				local uvOk, upvalue = pcall(debug.getupvalue, fn, index)
				if not uvOk then
					break
				end

				if _G.F.isMiningModuleTable(upvalue) then
					return upvalue
				end
			end
		end
	end

	return nil
end

_G.F.scanRegistryForMiningModule = function()
	if type(debug) ~= "table" or type(debug.getregistry) ~= "function" then
		return nil
	end

	local ok, registry = pcall(debug.getregistry)
	if not ok or type(registry) ~= "table" then
		return nil
	end

	for _, value in ipairs(registry) do
		if _G.F.isMiningModuleTable(value) then
			return value
		end
	end

	return nil
end

_G.F.getMiningModule = function(forceRefresh)
	if not forceRefresh
		and _G.cachedMiningModule
		and _G.F.isMiningModuleTable(_G.cachedMiningModule)
		and (os.clock() - _G.cachedMiningModuleAt) < _G.MINING_MODULE_CACHE_TTL then
		return _G.cachedMiningModule
	end

	if type(_G._p) ~= "table" then
		_G._p = _G.F.findP()
	end

	local mining = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Mining") or nil
	if not _G.F.isMiningModuleTable(mining) then
		mining = _G.F.scanFunctionUpvaluesForMiningModule()
	end
	if not _G.F.isMiningModuleTable(mining) then
		mining = _G.F.scanRegistryForMiningModule()
	end

	if _G.F.isMiningModuleTable(mining) then
		_G.cachedMiningModule = mining
		_G.cachedMiningModuleAt = os.clock()
		return mining
	end

	_G.F.clearMiningModuleCache()
	return nil
end

_G.F.runRemoteSparkleMineAt = function(sparklePart)
	if typeof(sparklePart) ~= "Instance" then
		return false, "Invalid sparkle."
	end

	if not _G.F.teleportCharacterToSparkle(sparklePart) then
		return false, "Teleport failed (invalid sparkle, front face, or Y limit)."
	end

	task.wait(0.35)
	_G.F.syncMinePointForSparkle(sparklePart)

	local clicked, reason = _G.F.fireGameMiningClick()
	if clicked then
		return true
	end

	return false, reason or "Click failed after teleport."
end


_G.F.isCtrlHeld = function()
	return _G.UserInputService:IsKeyDown(Enum.KeyCode.LeftControl)
		or _G.UserInputService:IsKeyDown(Enum.KeyCode.RightControl)
end

_G.F.disconnectCtrlClickTp = function()
	if _G.ctrlClickTpConnection then
		_G.ctrlClickTpConnection:Disconnect()
		_G.ctrlClickTpConnection = nil
	end
end

_G.F.tryCtrlClickTeleport = function()
	if not _G.ctrlClickTpEnabled or not _G.F.isCtrlHeld() then
		return
	end

	local player = _G.Players.LocalPlayer
	local mouse = player:GetMouse()
	local target = mouse.Target
	local hit = mouse.Hit

	if not target or not hit then
		return
	end

	local playerGui = player:FindFirstChildOfClass("PlayerGui")
	if playerGui and target:IsDescendantOf(playerGui) then
		return
	end

	local character = player.Character
	if not character then
		return
	end

	local humanoidRootPart = character:FindFirstChild("HumanoidRootPart")
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	local destination = hit.Position + Vector3.new(0, 3, 0)

	if humanoidRootPart then
		humanoidRootPart.CFrame = CFrame.new(destination)
	elseif humanoid then
		humanoid:MoveTo(hit.Position)
	end
end

_G.F.setCtrlClickTpEnabled = function(value)
	value = value and true or false
	if _G.ctrlClickTpEnabled == value then
		return
	end

	_G.ctrlClickTpEnabled = value
	_G.F.disconnectCtrlClickTp()

	if not value then
		return
	end

	local player = _G.Players.LocalPlayer
	local mouse = player:GetMouse()

	_G.ctrlClickTpConnection = mouse.Button1Down:Connect(function()
		_G.F.tryCtrlClickTeleport()
	end)
end

_G.F.setAntiAfkEnabled = function(value)
	value = value and true or false
	if _G.antiAfkEnabled == value then
		return
	end

	_G.antiAfkEnabled = value

	if _G.antiAfkIdleConnection then
		_G.antiAfkIdleConnection:Disconnect()
		_G.antiAfkIdleConnection = nil
	end

	if not value then
		return
	end

	local player = _G.Player or _G.Players.LocalPlayer
	local virtualUser = game:GetService("VirtualUser")

	_G.antiAfkIdleConnection = player.Idled:Connect(function()
		pcall(function()
			virtualUser:CaptureController()
			virtualUser:ClickButton2(Vector2.new())
		end)
	end)
end

_G.F.applyJackCameraSettings = function()
	local player = _G.Player or _G.Players.LocalPlayer
	if not player then
		return false, "Player is not ready."
	end

	pcall(function()
		if _G.jackOriginalCameraMaxZoomDistance == nil then
			_G.jackOriginalCameraMaxZoomDistance = player.CameraMaxZoomDistance
		end
		if _G.jackOriginalCameraOcclusionMode == nil then
			_G.jackOriginalCameraOcclusionMode = player.DevCameraOcclusionMode
		end
	end)

	local ok, err = pcall(function()
		player.CameraMaxZoomDistance = 90000
		player.DevCameraOcclusionMode = Enum.DevCameraOcclusionMode.Invisicam
	end)

	if not ok then
		return false, tostring(err)
	end

	return true
end

_G.F.restoreJackCameraSettings = function()
	local player = _G.Player or _G.Players.LocalPlayer
	if not player then
		return
	end

	pcall(function()
		if _G.jackOriginalCameraMaxZoomDistance ~= nil then
			player.CameraMaxZoomDistance = _G.jackOriginalCameraMaxZoomDistance
		end
		if _G.jackOriginalCameraOcclusionMode ~= nil then
			player.DevCameraOcclusionMode = _G.jackOriginalCameraOcclusionMode
		end
	end)

	_G.jackOriginalCameraMaxZoomDistance = nil
	_G.jackOriginalCameraOcclusionMode = nil
end

_G.F.setJackCameraEnabled = function(value)
	value = value and true or false
	if _G.jackCameraEnabled == value then
		return true
	end

	_G.jackCameraEnabled = value
	_G.jackCameraLoopId = (_G.jackCameraLoopId or 0) + 1
	local loopId = _G.jackCameraLoopId

	if not value then
		_G.F.restoreJackCameraSettings()
		return true
	end

	local ok, reason = _G.F.applyJackCameraSettings()
	if not ok then
		_G.jackCameraEnabled = false
		return false, reason
	end

	task.spawn(function()
		while _G.uiAlive and _G.jackCameraEnabled and _G.jackCameraLoopId == loopId do
			_G.F.applyJackCameraSettings()
			task.wait(2)
		end
	end)

	return true
end

_G.F.openDeveloperConsole = function()
	local starterGui = game:GetService("StarterGui")
	local ok, err = pcall(function()
		starterGui:SetCore("DevConsoleVisible", true)
	end)

	if not ok then
		return false, tostring(err)
	end

	return true
end

-- Apply another UserId's HumanoidDescription onto the local character.
-- Uses the real avatar (no fake overlay), so animation packs / Animate work normally.
_G.localAvatarState = _G.localAvatarState or {
	characterConn = nil,
	originalDescription = nil,
	appliedUserId = nil,
	applying = false,
}

_G.LOCAL_AVATAR_USER_ID_POOL = {
	1, -- Roblox
	156, -- builderman
	261, -- John Doe classic-era
	5774246,
	1560650,
	338287387,
	4810427201,
	1553281596,
	1890850136,
	308165,
	2295360,
	24936,
	20321238,
	1231234,
	27636987,
}

_G.F.pickLocalAvatarUserId = function(preferred)
	local preferredId = tonumber(preferred)
	if preferredId and preferredId > 0 then
		return preferredId
	end

	local pool = _G.LOCAL_AVATAR_USER_ID_POOL
	if type(pool) ~= "table" or #pool == 0 then
		return 1
	end

	return pool[math.random(1, #pool)]
end

_G.F.captureOriginalAvatarDescription = function(humanoid)
	local state = _G.localAvatarState
	if type(state) ~= "table" or state.originalDescription ~= nil or not humanoid then
		return
	end

	local ok, description = pcall(function()
		return humanoid:GetAppliedDescription()
	end)
	if ok and description ~= nil then
		local cloneOk, cloned = pcall(function()
			return description:Clone()
		end)
		state.originalDescription = (cloneOk and cloned) or description
	end
end

_G.F.clearLocalOnlyAvatar = function()
	local state = _G.localAvatarState
	if type(state) ~= "table" then
		return
	end

	state.appliedUserId = nil

	local player = game:GetService("Players").LocalPlayer
	local character = player and player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or state.originalDescription == nil then
		return
	end

	pcall(function()
		if humanoid.ApplyDescriptionReset then
			humanoid:ApplyDescriptionReset(state.originalDescription)
		else
			humanoid:ApplyDescription(state.originalDescription)
		end
	end)
end

_G.F.applyLocalOnlyAvatar = function(userId)
	if not _G.localAvatarEnabled then
		return false, "Local avatar is disabled."
	end

	local state = _G.localAvatarState
	if type(state) == "table" and state.applying then
		return false, "Avatar apply already in progress."
	end

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player then
		return false, "LocalPlayer missing."
	end

	local character = player.Character
	if not character then
		return false, "Character not ready."
	end

	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return false, "Humanoid not ready."
	end

	userId = _G.F.pickLocalAvatarUserId(userId or _G.localAvatarUserId)
	_G.localAvatarUserId = userId

	if type(state) == "table" then
		state.applying = true
	end

	local ok, err = pcall(function()
		_G.F.captureOriginalAvatarDescription(humanoid)

		local okDesc, description = pcall(function()
			return Players:GetHumanoidDescriptionFromUserId(userId)
		end)
		if not okDesc or description == nil then
			error("Could not load avatar description for " .. tostring(userId), 0)
		end

		-- ApplyDescriptionReset clears current accessories/clothing/anims then applies the target.
		local applied = false
		if humanoid.ApplyDescriptionReset then
			local okApply = pcall(function()
				humanoid:ApplyDescriptionReset(description)
			end)
			applied = okApply
		end
		if not applied then
			local okApply, applyErr = pcall(function()
				humanoid:ApplyDescription(description)
			end)
			if not okApply then
				error(applyErr or "ApplyDescription failed", 0)
			end
		end

		state.appliedUserId = userId
	end)

	if type(state) == "table" then
		state.applying = false
	end

	if not ok then
		return false, tostring(err)
	end

	return true, userId
end

_G.F.startLocalOnlyAvatar = function(userId)
	_G.localAvatarEnabled = true

	local Players = game:GetService("Players")
	local player = Players.LocalPlayer
	if not player then
		return false, "LocalPlayer missing."
	end

	local state = _G.localAvatarState
	if state.characterConn then
		pcall(function()
			state.characterConn:Disconnect()
		end)
		state.characterConn = nil
	end

	state.characterConn = player.CharacterAdded:Connect(function()
		-- New character = new body; capture a fresh original next apply.
		state.originalDescription = nil
		state.appliedUserId = nil
		task.wait(0.5)
		if _G.localAvatarEnabled then
			pcall(_G.F.applyLocalOnlyAvatar, _G.localAvatarUserId)
		end
	end)

	if player.Character then
		return _G.F.applyLocalOnlyAvatar(userId)
	end

	return true, "Waiting for character."
end

_G.F.stopLocalOnlyAvatar = function()
	_G.localAvatarEnabled = false
	local state = _G.localAvatarState
	if type(state) == "table" and state.characterConn then
		pcall(function()
			state.characterConn:Disconnect()
		end)
		state.characterConn = nil
	end
	_G.F.clearLocalOnlyAvatar()
	return true
end

_G.F.setLocalAvatarEnabled = function(value)
	if value then
		return _G.F.startLocalOnlyAvatar(_G.localAvatarUserId)
	end
	return _G.F.stopLocalOnlyAvatar()
end

_G.F.rerollLocalOnlyAvatar = function()
	_G.localAvatarUserId = nil
	return _G.F.startLocalOnlyAvatar(nil)
end

return { name = "world" }
