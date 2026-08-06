-- arcade.lua
-- ArcadeAutomation (Disc Drop).
local ArcadeAutomation = (function()
	local api = {}

	local discDropStatusLabel = nil
	local discDropLiveLabel = nil
	local discDropRecordsLabel = nil

	local arcadeRemoteKey = "W8iupZbUTwip9WF0zpAvmA"

	local function setLabelText(label, text)
		if label and type(label.Set) == "function" then
			pcall(function()
				label:Set(tostring(text or ""))
			end)
		end
	end

	local function formatDiscDropNumber(value)
		local number = math.floor(tonumber(value) or 0)
		local text = tostring(number)
		local formatted = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
		if formatted:sub(1, 1) == "," then
			formatted = formatted:sub(2)
		end
		return formatted
	end

	local function refreshDiscDropRecordsLabel()
		setLabelText(
			discDropRecordsLabel,
			string.format(
				"Last score: %s | Best score: %s",
				formatDiscDropNumber(_G.discDropLastScore),
				formatDiscDropNumber(_G.discDropHighScore)
			)
		)
	end

	local function updateDiscDropUi(grid, movesMade, message)
		local score = type(grid) == "table" and tonumber(grid.score) or 0
		local combo = type(grid) == "table" and tonumber(grid.combo) or 0

		setLabelText(discDropStatusLabel, tostring(message or "Idle"))
		setLabelText(
			discDropLiveLabel,
			string.format(
				"Score: %s | Moves: %d | Combo: %d",
				formatDiscDropNumber(score),
				movesMade or 0,
				combo or 0
			)
		)
		refreshDiscDropRecordsLabel()
	end

	local function setDiscDropStatus(text)
		setLabelText(discDropStatusLabel, text)
		refreshDiscDropRecordsLabel()
	end

	local function recordDiscDropGameScore(grid)
		local finalScore = type(grid) == "table" and math.floor(tonumber(grid.score) or 0) or 0
		_G.discDropLastScore = finalScore

		if finalScore > _G.discDropHighScore then
			_G.discDropHighScore = finalScore
		end
	end

	local function ensureP()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		return type(_G._p) == "table"
	end

	local function newArray(size)
		if type(table.create) == "function" then
			return table.create(size)
		end

		return {}
	end

	local function getArcadeRemote(remoteName)
		local ok, remote = pcall(function()
			local remoteFolder = game:GetService("ReplicatedStorage"):FindFirstChild("Remote")
			return remoteFolder and remoteFolder:FindFirstChild(remoteName)
		end)

		if ok then
			return remote
		end

		return nil
	end

	local function directNetworkGet(actionName, ...)
		local remote = getArcadeRemote("REQ") or getArcadeRemote("GET")
		if not remote or type(remote.InvokeServer) ~= "function" then
			return false
		end

		local args = { ... }
		local ok, result = pcall(function()
			return remote:InvokeServer(arcadeRemoteKey, actionName, unpack(args))
		end)

		if ok and result ~= nil and result ~= false then
			return true, result, "direct-key"
		end

		ok, result = pcall(function()
			return remote:InvokeServer(actionName, unpack(args))
		end)

		if ok and result ~= nil and result ~= false then
			return true, result, "direct-bare"
		end

		return false
	end

	local function directNetworkPost(actionName, ...)
		local remote = getArcadeRemote("EVT") or getArcadeRemote("POST")
		if not remote or type(remote.FireServer) ~= "function" then
			return false
		end

		local args = { ... }
		local ok = pcall(function()
			remote:FireServer(arcadeRemoteKey, actionName, unpack(args))
		end)

		if ok then
			return true
		end

		ok = pcall(function()
			remote:FireServer(actionName, unpack(args))
		end)

		return ok
	end

	local function networkGet(actionName, ...)
		ensureP()

		local args = { ... }
		local network = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Network") or nil
		local getMethod = type(network) == "table" and _G.F.safeTableGet(network, "get") or nil

		if type(getMethod) == "function" then
			local ok, result = pcall(function()
				return getMethod(network, actionName, unpack(args))
			end)

			if ok and result ~= nil and result ~= false then
				return true, result, "network"
			end
		end

		local connection = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Connection") or nil
		getMethod = type(connection) == "table" and _G.F.safeTableGet(connection, "get") or nil

		if type(getMethod) == "function" then
			local ok, result = pcall(function()
				return getMethod(connection, actionName, unpack(args))
			end)

			if ok and result ~= nil and result ~= false then
				return true, result, "connection"
			end
		end

		return directNetworkGet(actionName, ...)
	end

	local function networkPost(actionName, ...)
		ensureP()

		local args = { ... }
		local network = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Network") or nil
		local postMethod = type(network) == "table" and _G.F.safeTableGet(network, "post") or nil

		if type(postMethod) == "function" then
			local ok = pcall(function()
				postMethod(network, actionName, unpack(args))
			end)

			if ok then
				return true
			end
		end

		local connection = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "Connection") or nil
		postMethod = type(connection) == "table" and _G.F.safeTableGet(connection, "post") or nil

		if type(postMethod) == "function" then
			local ok = pcall(function()
				postMethod(connection, actionName, unpack(args))
			end)

			if ok then
				return true
			end
		end

		return directNetworkPost(actionName, ...)
	end

	local function getDiscDropGridClass()
		ensureP()

		local arcadeController = type(_G._p) == "table" and _G.F.safeTableGet(_G._p, "ArcadeController") or nil
		local gridClass = type(arcadeController) == "table" and _G.F.safeTableGet(arcadeController, "DiscDropGrid") or nil

		if type(gridClass) == "table" and type(gridClass.new) == "function" then
			return gridClass
		end

		return nil
	end

	local function cloneDiscDropGrid(grid)
		if type(grid) ~= "table" or type(grid.grid) ~= "table" then
			return nil
		end

		local clone = setmetatable({}, getmetatable(grid))
		clone.score = tonumber(grid.score) or 0
		clone.combo = tonumber(grid.combo) or 1
		clone.nextBombScore = tonumber(grid.nextBombScore) or 5000
		clone.guiHandler = nil
		clone.srand = Random.new(math.random(1, 1000000000))
		clone.grid = newArray(8)

		for y = 1, 8 do
			clone.grid[y] = newArray(8)
			local row = grid.grid[y]

			for x = 1, 8 do
				local cell = type(row) == "table" and row[x] or nil
				clone.grid[y][x] = {
					value = type(cell) == "table" and cell.value or 0,
					x = x,
					y = y
				}
			end
		end

		return clone
	end

	local function scoreDiscDropMove(grid, move)
		local clone = cloneDiscDropGrid(grid)
		if not clone or type(clone.TrySwap) ~= "function" then
			return -math.huge
		end

		local beforeScore = tonumber(clone.score) or 0
		local ok, swapped = pcall(function()
			return clone:TrySwap(move[1], move[2], move[3], move[4])
		end)

		if not ok or not swapped then
			return -math.huge
		end

		local afterScore = tonumber(clone.score) or beforeScore
		local scoreGain = afterScore - beforeScore
		local combo = tonumber(clone.combo) or 1
		return scoreGain * 1000 + combo + math.random()
	end

	local function chooseDiscDropMove(grid)
		if type(grid) ~= "table" or type(grid.GetPossibleMoveList) ~= "function" then
			return nil
		end

		local ok, moves = pcall(function()
			return grid:GetPossibleMoveList()
		end)

		if not ok or type(moves) ~= "table" then
			return nil
		end

		local bestMove = nil
		local bestScore = -math.huge

		for index = 1, #moves - 1, 2 do
			local first = moves[index]
			local second = moves[index + 1]

			if type(first) == "table" and type(second) == "table" then
				local move = { first.x, first.y, second.x, second.y }
				local score = scoreDiscDropMove(grid, move)

				if score > bestScore then
					bestScore = score
					bestMove = move
				end
			end
		end

		return bestMove
	end

	local function renderDiscDropStatus(grid, movesMade, message)
		updateDiscDropUi(grid, movesMade, message)
	end

	local function runAutoDiscDrop()
		local gridClass = getDiscDropGridClass()
		if not gridClass then
			setDiscDropStatus("ArcadeController.DiscDropGrid is not loaded.")
			return false, "ArcadeController.DiscDropGrid is not loaded. Open the arcade area once, then turn this on."
		end

		local okSeed, seed = networkGet("DiscDrop_NewGame")
		if not okSeed then
			setDiscDropStatus("Could not start a Disc Drop game.")
			return false, "Could not start a Disc Drop game."
		end

		local okGrid, grid = pcall(function()
			return gridClass.new(seed)
		end)

		if not okGrid or type(grid) ~= "table" then
			setDiscDropStatus("Could not build the Disc Drop grid.")
			return false, "Could not build the Disc Drop grid."
		end

		local startedAt = os.clock()
		local movesMade = 0
		local lastScore = tonumber(grid.score) or 0
		local lastMove = nil
		renderDiscDropStatus(grid, movesMade, "Started")

		while _G.autoDiscDropEnabled and _G.uiAlive do
			local move = chooseDiscDropMove(grid)
			if not move then
				break
			end

			local okMove = networkPost("DiscDrop_Move", move[1], move[2], move[3], move[4])
			if not okMove then
				setDiscDropStatus("Could not send Disc Drop move.")
				return false, "Could not send Disc Drop move."
			end

			local swapped = false
			pcall(function()
				swapped = grid:TrySwap(move[1], move[2], move[3], move[4])
			end)

			if not swapped then
				break
			end

			movesMade = movesMade + 1
			lastMove = move

			local currentScore = tonumber(grid.score) or lastScore
			if currentScore > lastScore then
				lastScore = currentScore
			end

			renderDiscDropStatus(grid, movesMade, "Playing")
			task.wait(0.08)
		end

		recordDiscDropGameScore(grid)
		networkPost("DiscDrop_Finish", math.floor(os.clock() - startedAt), true)
		renderDiscDropStatus(grid, movesMade, movesMade > 0 and "Finished" or "No moves")
		return movesMade > 0, movesMade > 0 and nil or "No Disc Drop moves were available."
	end

	function api:isDiscDropEnabled()
		return _G.autoDiscDropEnabled
	end

	function api:setDiscDropEnabled(value, keepVisual)
		_G.autoDiscDropEnabled = value == true

		if not _G.autoDiscDropEnabled and not keepVisual then
			setLabelText(discDropStatusLabel, "Stopped.")
			setLabelText(discDropLiveLabel, "Score: 0 | Moves: 0 | Combo: 0")
			refreshDiscDropRecordsLabel()
		end
	end

	function api:stopAll()
		_G.autoDiscDropEnabled = false
		setLabelText(discDropStatusLabel, "Stopped.")
		setLabelText(discDropLiveLabel, "Score: 0 | Moves: 0 | Combo: 0")
		refreshDiscDropRecordsLabel()
	end

	function api:runAutoDiscDrop()
		return runAutoDiscDrop()
	end

	function api:refreshStats()
		refreshDiscDropRecordsLabel()
	end

	function api:attachUi(tab)
		if not tab then
			return
		end

		_G.configUi.autoDiscDropToggle = tab:AddToggle({
			Name = "Auto Disc Drop",
			Default = _G.autoDiscDropEnabled,
			Color = Color3.fromRGB(90, 170, 255),
			Callback = function(value)
				_G.F.setAutoDiscDropEnabled(value)
			end
		})

		discDropStatusLabel = tab:AddLabel("Idle")
		discDropLiveLabel = tab:AddLabel("Score: 0 | Moves: 0 | Combo: 0")
		discDropRecordsLabel = tab:AddLabel("Last score: 0 | Best score: 0")
		_G.discDropStatusLabel = discDropStatusLabel
		_G.discDropLiveLabel = discDropLiveLabel
		_G.discDropRecordsLabel = discDropRecordsLabel
		refreshDiscDropRecordsLabel()
	end

	return api
end)()

_G.ArcadeAutomation = ArcadeAutomation
if getgenv then
	getgenv().ArcadeAutomation = ArcadeAutomation
end

return { name = "arcade", ArcadeAutomation = ArcadeAutomation }
