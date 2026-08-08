-- arcade.lua
-- ArcadeAutomation (Disc Drop).
local ArcadeAutomation = (function()
	local api = {}

	local discDropStatusLabel = nil
	local discDropLiveLabel = nil
	local discDropRecordsLabel = nil

	local arcadeRemoteKey = "W8iupZbUTwip9WF0zpAvmA"

	local function setLabelText(label, text)
		text = tostring(text or "")
		if not label then
			return
		end
		if type(label.Set) == "function" then
			pcall(function()
				label:Set(text)
			end)
		end
		-- Orion Label:Set can silently no-op on some executors; write Content too.
		pcall(function()
			if type(label.Content) == "userdata" or type(label.Content) == "table" then
				label.Content.Text = text
			end
		end)
	end

	local function readDiscDropScore(grid)
		if type(grid) ~= "table" then
			return 0
		end
		local score = tonumber(rawget(grid, "score")) or tonumber(grid.score) or tonumber(grid.Score)
		if score == nil and type(grid.GetScore) == "function" then
			pcall(function()
				score = tonumber(grid:GetScore())
			end)
		end
		return math.floor(tonumber(score) or 0)
	end

	local function readDiscDropCombo(grid)
		if type(grid) ~= "table" then
			return 0
		end
		local combo = tonumber(rawget(grid, "combo")) or tonumber(grid.combo) or tonumber(grid.Combo)
		if combo == nil and type(grid.GetCombo) == "function" then
			pcall(function()
				combo = tonumber(grid:GetCombo())
			end)
		end
		return math.floor(tonumber(combo) or 0)
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

	local function formatDiscDropTime(seconds)
		seconds = math.max(0, math.floor(tonumber(seconds) or 0))
		local minutes = math.floor(seconds / 60)
		local secs = seconds % 60
		return string.format("%d:%02d", minutes, secs)
	end

	-- Parse "90", "1:30", or "1m30s" into seconds.
	local function parseDiscDropTimeInput(value)
		local text = string.lower(string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1"))
		if text == "" then
			return nil
		end

		local minutes, seconds = string.match(text, "^(%d+)%s*:%s*(%d+)$")
		if minutes and seconds then
			return (tonumber(minutes) * 60) + tonumber(seconds)
		end

		minutes, seconds = string.match(text, "^(%d+)%s*m%s*(%d+)%s*s?$")
		if minutes and seconds then
			return (tonumber(minutes) * 60) + tonumber(seconds)
		end

		minutes = string.match(text, "^(%d+)%s*m$")
		if minutes then
			return tonumber(minutes) * 60
		end

		seconds = string.match(text, "^(%d+)%s*s$")
		if seconds then
			return tonumber(seconds)
		end

		local asNumber = tonumber((text:gsub(",", "")))
		if asNumber and asNumber >= 0 then
			return math.floor(asNumber)
		end

		return nil
	end

	local function parseDiscDropScoreInput(value)
		local text = string.gsub(tostring(value or ""), "[,%s]", "")
		text = string.lower(string.gsub(text, "^%s*(.-)%s*$", "%1"))
		if text == "" or text == "0" or text == "none" or text == "off" or text == "nil" then
			return nil
		end
		local asNumber = tonumber(text)
		if asNumber and asNumber > 0 then
			return math.floor(asNumber)
		end
		return false
	end

	-- Game hard-caps at 999,999 and may auto-finish server-side when hit.
	-- Stop just under that so our DiscDrop_Finish still owns the reported time.
	local DISC_DROP_SERVER_SCORE_CAP = 999999
	local DISC_DROP_SAFE_SCORE_CEILING = 999000

	local function getDiscDropMaxScore()
		local maxScore = tonumber(_G.discDropMaxScore)
		if maxScore and maxScore > 0 then
			maxScore = math.floor(maxScore)
			if maxScore >= DISC_DROP_SERVER_SCORE_CAP then
				return DISC_DROP_SAFE_SCORE_CEILING
			end
			return maxScore
		end
		return DISC_DROP_SAFE_SCORE_CEILING
	end

	-- Prefer the live textbox value (Orion sometimes shows typed text without
	-- firing Callback until enter/focus-lost).
	local function readDiscDropForceFinishTimeFromUi()
		local box = _G.configUi and _G.configUi.discDropFinishTimeBox
		if type(box) ~= "table" then
			return nil
		end

		local raw = nil
		pcall(function()
			if type(box.Value) == "string" or type(box.Value) == "number" then
				raw = box.Value
			elseif type(box.Text) == "string" then
				raw = box.Text
			elseif type(box.Get) == "function" then
				raw = box:Get()
			elseif type(box.Content) == "table" or type(box.Content) == "userdata" then
				raw = box.Content.Text
			end
		end)

		if raw == nil then
			return nil
		end

		local text = string.gsub(tostring(raw or ""), "^%s*(.-)%s*$", "%1")
		if text == "" or string.lower(text) == "off" or string.lower(text) == "none" then
			return nil
		end

		return parseDiscDropTimeInput(text)
	end

	local function resolveDiscDropForceFinishTime()
		local fromUi = readDiscDropForceFinishTimeFromUi()
		if fromUi and fromUi > 0 then
			_G.discDropForceFinishTime = math.floor(fromUi)
			return _G.discDropForceFinishTime
		end

		local forced = tonumber(_G.discDropForceFinishTime)
		if forced and forced > 0 then
			return math.floor(forced)
		end

		return nil
	end

	-- Never submit 0:00. When a force time is set, submit that exact value
	-- (what the Finish Time box is for). Otherwise use real elapsed, floored
	-- up to at least 1 second.
	local function getDiscDropFinishTime(startedAt)
		local elapsed = math.max(0, math.floor((os.clock() - startedAt) + 1e-9))
		local forced = resolveDiscDropForceFinishTime()
		if forced and forced > 0 then
			return math.max(1, math.floor(forced))
		end
		return math.max(1, elapsed)
	end

	local function refreshDiscDropRecordsLabel()
		setLabelText(
			discDropRecordsLabel or _G.discDropRecordsLabel,
			string.format(
				"Last score: %s | Best score: %s",
				formatDiscDropNumber(_G.discDropLastScore),
				formatDiscDropNumber(_G.discDropHighScore)
			)
		)
	end

	local function updateDiscDropUi(grid, movesMade, message)
		local score = readDiscDropScore(grid)
		local combo = readDiscDropCombo(grid)
		local statusLabel = discDropStatusLabel or _G.discDropStatusLabel
		local liveLabel = discDropLiveLabel or _G.discDropLiveLabel

		if message ~= nil then
			setLabelText(statusLabel, tostring(message))
		end
		setLabelText(
			liveLabel,
			string.format(
				"Score: %s | Moves: %d | Combo: %d",
				formatDiscDropNumber(score),
				movesMade or 0,
				combo
			)
		)
		refreshDiscDropRecordsLabel()
	end

	local function setDiscDropStatus(text)
		setLabelText(discDropStatusLabel or _G.discDropStatusLabel, text)
		refreshDiscDropRecordsLabel()
	end

	local function recordDiscDropGameScore(grid)
		local finalScore = readDiscDropScore(grid)
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
		clone.score = readDiscDropScore(grid)
		clone.combo = math.max(1, readDiscDropCombo(grid))
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

		local beforeScore = readDiscDropScore(clone)
		local ok, swapped = pcall(function()
			return clone:TrySwap(move[1], move[2], move[3], move[4])
		end)

		if not ok or not swapped then
			return -math.huge
		end

		local afterScore = readDiscDropScore(clone)
		local scoreGain = afterScore - beforeScore
		local combo = math.max(1, readDiscDropCombo(clone))
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
		local lastScore = readDiscDropScore(grid)
		local maxScore = getDiscDropMaxScore()
		local forcedAtStart = resolveDiscDropForceFinishTime()
		local startMessage = string.format(
			"Started (stop %s, finish %s)",
			formatDiscDropNumber(maxScore),
			forcedAtStart and formatDiscDropTime(forcedAtStart) or "elapsed≥1s"
		)
		renderDiscDropStatus(grid, movesMade, startMessage)

		while _G.autoDiscDropEnabled and _G.uiAlive do
			local currentScoreCheck = readDiscDropScore(grid)
			if currentScoreCheck < lastScore then
				currentScoreCheck = lastScore
			end
			-- Stop before the server 999,999 auto-finish so our Finish owns the time.
			if currentScoreCheck >= maxScore or currentScoreCheck >= DISC_DROP_SAFE_SCORE_CEILING then
				break
			end

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

			local currentScore = readDiscDropScore(grid)
			if currentScore > lastScore then
				lastScore = currentScore
			end

			if currentScore >= maxScore or currentScore >= DISC_DROP_SAFE_SCORE_CEILING then
				renderDiscDropStatus(grid, movesMade, "Score cap reached")
				break
			end

			renderDiscDropStatus(grid, movesMade, "Playing")
		end

		recordDiscDropGameScore(grid)
		local finishTime = getDiscDropFinishTime(startedAt)
		local submitted, submittedTime, via = submitDiscDropFinish(finishTime)
		renderDiscDropStatus(
			grid,
			movesMade,
			string.format(
				"%s (submitted %s%s)",
				movesMade > 0 and "Finished" or "No moves",
				formatDiscDropTime(submittedTime or finishTime),
				submitted and (via and (", " .. via) or "") or ", send failed"
			)
		)
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

		local maxScoreDefault = tonumber(_G.discDropMaxScore)
		_G.configUi.discDropMaxScoreBox = tab:AddTextbox({
			Name = "Max Score (blank = play to ~999k)",
			Default = maxScoreDefault and tostring(maxScoreDefault) or "",
			TextDisappear = false,
			Callback = function(value)
				local parsed = parseDiscDropScoreInput(value)
				if parsed == false then
					_G.OrionLib:MakeNotification({
						Name = "Auto Disc Drop",
						Content = "Max score must be a positive number (or blank for ~999k soft cap).",
						Time = 4,
					})
					return
				end
				_G.discDropMaxScore = parsed
				local message = parsed
					and ("Max score set to " .. formatDiscDropNumber(parsed))
					or "Max score cleared (soft-cap near 999k so Finish time still applies)."
				setDiscDropStatus(message)
			end
		})

		local finishDefault = tonumber(_G.discDropForceFinishTime) or 1
		_G.discDropForceFinishTime = finishDefault
		_G.configUi.discDropFinishTimeBox = tab:AddTextbox({
			Name = "Finish Time (seconds or m:ss)",
			Default = tostring(finishDefault),
			TextDisappear = false,
			Callback = function(value)
				local text = string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
				if text == "" or string.lower(text) == "off" or string.lower(text) == "none" then
					-- Empty still keeps a 1s floor at submit time; store nil to mean "use elapsed".
					_G.discDropForceFinishTime = nil
					setDiscDropStatus("Finish time cleared (submit real elapsed, min 1s).")
					return
				end

				local parsed = parseDiscDropTimeInput(value)
				if not parsed or parsed < 1 then
					_G.OrionLib:MakeNotification({
						Name = "Auto Disc Drop",
						Content = "Finish time must be at least 1 second (e.g. 6 or 0:06).",
						Time = 4,
					})
					return
				end

				_G.discDropForceFinishTime = math.floor(parsed)
				setDiscDropStatus("Finish time set to " .. formatDiscDropTime(parsed) .. " (submitted exactly).")
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
