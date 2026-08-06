-- catch.lua
-- CatchAutomation for wild encounters.
_G.CatchAutomation = (function()
	local api = {}

	local lastCatchDiscRequest = nil
	local pendingCatchDiscRequest = nil
	local pendingCatchDiscAt = 0
	local lastDiscAttemptAt = 0
	local lastBattleObject = nil
	local lastPreparedCatchBattle = nil
	local awaitingCaptureNicknamePrompt = false
	local awaitingCaptureNicknameSince = 0
	local catchAwaitingNickname = false
	local waitingForNicknamePromptDismiss = false
	local clickedNicknamePromptInstance = nil
	local lastNicknamePromptAttemptAt = 0
	local lastNicknamePromptServiceAt = 0
	local NICKNAME_PROMPT_SCAN_INTERVAL = 0.25

	local pendingCapturedGoppieForme = nil
	local registeredCapturedGoppieForme = false

	local function resetCaptureNicknamePromptState()
		awaitingCaptureNicknamePrompt = false
		awaitingCaptureNicknameSince = 0
		catchAwaitingNickname = false
		waitingForNicknamePromptDismiss = false
		clickedNicknamePromptInstance = nil
		lastNicknamePromptAttemptAt = 0
		lastNicknamePromptServiceAt = 0

		pendingCapturedGoppieForme = nil
		registeredCapturedGoppieForme = false
	end


	local function rememberPendingCapturedGoppieForme(battle)
		pendingCapturedGoppieForme = nil

		if type(battle) ~= "table" then
			return
		end

		local foe = _G.F.getBattleFoeMonster(battle)
		local formeValue = _G.F.getFishingGoppieFormeValue(battle)
		if _G.F.isMeaningfulFormeValue(formeValue)
			and (_G.F.isGoppieMonster(foe) or _G.F.isFishingGoppieBattle(battle)) then
			pendingCapturedGoppieForme = formeValue
			_G.lastAutoFishingGoppieForme = formeValue
			_G.lastAutoFishingGoppieFormeAt = os.clock()
		end
	end

	local function registerPendingCapturedGoppieForme()
		if not _G.F.isMeaningfulFormeValue(pendingCapturedGoppieForme) then
			rememberPendingCapturedGoppieForme(_G.F.getCurrentBattle())
		end

		if not _G.F.isMeaningfulFormeValue(pendingCapturedGoppieForme)
			and _G.F.isMeaningfulFormeValue(_G.lastAutoFishingGoppieForme)
			and os.clock() - _G.lastAutoFishingGoppieFormeAt <= 90 then
			pendingCapturedGoppieForme = _G.lastAutoFishingGoppieForme
		end

		if registeredCapturedGoppieForme then
			return
		end

		local battle = _G.F.getCurrentBattle()
		if battle and _G.F.registerCaughtGoppieFormeFromBattle(battle) then
			registeredCapturedGoppieForme = true
			return
		end

		if _G.F.isMeaningfulFormeValue(pendingCapturedGoppieForme)
			and (_G.F.addGoppieForme(pendingCapturedGoppieForme) or _G.F.isGoppieFormeSaved(pendingCapturedGoppieForme)) then
			registeredCapturedGoppieForme = true
		end
	end

	local function resetCatchDiscState()
		lastCatchDiscRequest = nil
		pendingCatchDiscRequest = nil
		pendingCatchDiscAt = 0
		if _G.resetCatchUiTiming then
			_G.resetCatchUiTiming()
		end
	end

	local function normalizePromptText(value)
		local text = string.lower(tostring(value or ""))
		text = string.gsub(text, "%s+", " ")
		return text
	end

	local function findAncestorGuiButton(item)
		local current = item

		while current do
			if current:IsA("GuiButton") then
				return current
			end

			current = current.Parent
		end

		return nil
	end

	local getPromptGuiContainers
	local isPromptGuiVisible
	local getBattleGuiPromptYesOrNoMethod

	local function findGuiButtonByText(text)
		local wanted = normalizePromptText(text)

		for _, container in ipairs(getPromptGuiContainers()) do
			local ok, descendants = pcall(function()
				return container:GetDescendants()
			end)

			if ok then
				for _, item in ipairs(descendants) do
					if (item:IsA("TextLabel") or item:IsA("TextButton") or item:IsA("TextBox")) and isPromptGuiVisible(item) then
						local okText, itemText = pcall(function()
							return item.Text
						end)

						if okText and normalizePromptText(itemText) == wanted then
							local button = item:IsA("GuiButton") and item or findAncestorGuiButton(item)

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

	local function getVisiblePromptTextSnapshot()
		local parts = {}

		for _, container in ipairs(getPromptGuiContainers()) do
			local ok, descendants = pcall(function()
				return container:GetDescendants()
			end)

			if ok then
				for _, item in ipairs(descendants) do
					local visible = isPromptGuiVisible(item)
					if not visible and item:IsA("GuiObject") then
						visible = item.AbsoluteSize.X > 4 and item.AbsoluteSize.Y > 4
					end

					if visible then
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
			end
		end

		return string.lower(table.concat(parts, " "))
	end

	local function visibleTextContainsCaptureNickname()
		local snapshot = getVisiblePromptTextSnapshot()
		if snapshot == "" then
			return false
		end

		if string.find(snapshot, "nickname", 1, true)
			or string.find(snapshot, "give a nickname", 1, true)
			or string.find(snapshot, "no nickname", 1, true) then
			return true
		end

		return string.find(snapshot, "captured", 1, true) ~= nil
			and string.find(snapshot, "nickname", 1, true) ~= nil
	end

	getPromptGuiContainers = function()
		local containers = {}
		local seen = {}

		local function addContainer(container)
			if container and not seen[container] then
				seen[container] = true
				table.insert(containers, container)
			end
		end

		pcall(function()
			if type(_G._p) ~= "table" then
				_G._p = _G.F.findP()
			end

			local utilities = type(_G._p) == "table" and _G._p.Utilities or nil
			local frontGui = utilities and utilities.frontGui or nil
			addContainer(frontGui)
		end)

		pcall(function()
			local playerGui = _G.Player and _G.Player:FindFirstChildOfClass("PlayerGui")
			addContainer(playerGui)
		end)

		return containers
	end

	isPromptGuiVisible = function(item)
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

	local function findVisibleYesOrNoPromptFrame()
		for _, container in ipairs(getPromptGuiContainers()) do
			local ok, descendants = pcall(function()
				return container:GetDescendants()
			end)

			if ok then
				for _, item in ipairs(descendants) do
					if item.Name == "YesOrNoPrompt" and isPromptGuiVisible(item) then
						return item
					end
				end
			end
		end

		local okBattleGui, battlePrompt = pcall(function()
			if type(_G._p) ~= "table" then
				_G._p = _G.F.findP()
			end

			local battleGui = type(_G._p) == "table" and _G._p.BattleGui or nil
			if type(battleGui) ~= "table" then
				return nil
			end

			for _, value in pairs(battleGui) do
				if type(value) == "Instance" and value.Name == "YesOrNoPrompt" and isPromptGuiVisible(value) then
					return value
				end
			end

			return nil
		end)

		if okBattleGui and battlePrompt then
			return battlePrompt
		end

		local promptYesOrNo = getBattleGuiPromptYesOrNoMethod()
		if type(promptYesOrNo) == "function" and type(debug) == "table" and type(debug.getupvalues) == "function" then
			local okUpvalues, upvalues = pcall(function()
				return { debug.getupvalues(promptYesOrNo) }
			end)

			if okUpvalues then
				for _, upvalue in ipairs(upvalues) do
					if type(upvalue) == "table" and upvalue.Visible == true then
						if typeof(upvalue.gui) == "Instance" then
							return upvalue.gui.Parent or upvalue.gui
						end

						return upvalue
					end
				end
			end
		end

		return nil
	end

	local function getPromptSearchRoot(promptRoot)
		if typeof(promptRoot) == "Instance" then
			return promptRoot
		end

		if type(promptRoot) == "table" and typeof(promptRoot.gui) == "Instance" then
			return promptRoot.gui
		end

		return promptRoot
	end

	local getYesOrNoPromptButtons

	local function getYesOrNoNoButton(promptRoot)
		promptRoot = getPromptSearchRoot(promptRoot)
		if not promptRoot then
			return nil
		end

		local _, noButton = getYesOrNoPromptButtons(promptRoot)
		if noButton then
			return noButton
		end

		local ok, descendants = pcall(function()
			return promptRoot:GetDescendants()
		end)

		if not ok then
			return nil
		end

		local bestButton = nil
		local bestY = -math.huge

		for _, item in ipairs(descendants) do
			if item:IsA("ImageButton") and isPromptGuiVisible(item) then
				local y = item.Position.Y.Scale + (item.Position.Y.Offset / math.max(item.AbsoluteSize.Y, 1))
				if y > bestY then
					bestY = y
					bestButton = item
				end
			end
		end

		return bestButton
	end

	local function fireGuiButtonSignals(button)
		if not button then
			return false
		end

		local clicked = false

		if type(_G.F) == "table" and type(_G.F.clickGuiButtonOnce) == "function" then
			clicked = _G.F.clickGuiButtonOnce(button) or clicked
		end

		if type(_G.F) == "table" and type(_G.F.activateGuiButton) == "function" then
			clicked = _G.F.activateGuiButton(button) or clicked
		end

		local okActivate = pcall(function()
			button:Activate()
		end)
		clicked = clicked or okActivate

		return clicked
	end

	getYesOrNoPromptButtons = function(promptRoot)
		promptRoot = getPromptSearchRoot(promptRoot)
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
			if item:IsA("ImageButton") and isPromptGuiVisible(item) then
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

	getBattleGuiPromptYesOrNoMethod = function()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local battleGui = type(_G._p) == "table" and _G._p.BattleGui or nil
		if type(battleGui) ~= "table" then
			return nil
		end

		local promptYesOrNo = _G.F.safeTableGet(battleGui, "promptYesOrNo") or _G.F.safeTableGet(battleGui, "PromptYesOrNo")
		if type(promptYesOrNo) ~= "function" then
			return nil
		end

		return promptYesOrNo
	end

	local function getBattleGuiYesOrNoLiveState()
		local promptYesOrNo = getBattleGuiPromptYesOrNoMethod()
		local promptFrame = nil
		local yesNoSignal = nil
		local noButton = nil

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
							noButton = getYesOrNoNoButton(upvalue.gui) or noButton
						end
					end

					if typeof(upvalue) == "Instance" and upvalue:IsA("ImageButton") and isPromptGuiVisible(upvalue) then
						local y = upvalue.Position.Y.Scale + (upvalue.Position.Y.Offset / math.max(upvalue.AbsoluteSize.Y, 1))
						if y >= 0.5 then
							noButton = upvalue
						end
					end
				end
			end
		end

		if not promptFrame then
			promptFrame = findVisibleYesOrNoPromptFrame()
		end

		if promptFrame and not noButton then
			noButton = getYesOrNoNoButton(getPromptSearchRoot(promptFrame))
		end

		local promptOpen = false
		if type(promptFrame) == "table" and promptFrame.Visible == true then
			promptOpen = true
		elseif typeof(promptFrame) == "Instance" and isPromptGuiVisible(promptFrame) then
			promptOpen = true
		elseif yesNoSignal ~= nil then
			promptOpen = true
		end

		if promptOpen and not noButton then
			noButton = findGuiButtonByText("No")
		end

		return promptOpen, yesNoSignal, noButton, promptFrame
	end

	local function clickBattleGuiPromptButton(button)
		if not button then
			return false
		end

		return fireGuiButtonSignals(button)
	end

	local function handleCaptureNicknamePrompt()
		local promptOpen, yesNoSignal, noButton, promptFrame = getBattleGuiYesOrNoLiveState()

		if waitingForNicknamePromptDismiss then
			if promptOpen or promptFrame then
				if os.clock() - lastNicknamePromptAttemptAt > 0.6 then
					waitingForNicknamePromptDismiss = false
					clickedNicknamePromptInstance = nil
				else
					return false
				end
			else

			waitingForNicknamePromptDismiss = false
			clickedNicknamePromptInstance = nil
			awaitingCaptureNicknamePrompt = false
			catchAwaitingNickname = false
			return true
			end
		end

		if not promptOpen and not promptFrame then
			return false
		end

		local hasNicknameText = visibleTextContainsCaptureNickname()

		if hasNicknameText then
			awaitingCaptureNicknamePrompt = true
			awaitingCaptureNicknameSince = os.clock()
			catchAwaitingNickname = true
		end

		if catchAwaitingNickname and awaitingCaptureNicknameSince > 0 and os.clock() - awaitingCaptureNicknameSince > 45 then
			catchAwaitingNickname = false
			awaitingCaptureNicknamePrompt = false
			return false
		end

		if not catchAwaitingNickname and not awaitingCaptureNicknamePrompt and not hasNicknameText then
			return false
		end

		if clickedNicknamePromptInstance ~= nil and clickedNicknamePromptInstance == promptFrame then
			return false
		end

		noButton = noButton or findGuiButtonByText("No")

		if noButton and clickBattleGuiPromptButton(noButton) then
			waitingForNicknamePromptDismiss = true
			clickedNicknamePromptInstance = promptFrame
			lastNicknamePromptAttemptAt = os.clock()
			return true
		end

		return false
	end

	local function isWildBattleCatchable(battle)
		if type(battle) ~= "table" or battle.ended or battle.done or battle.kind ~= "wild" then
			return false
		end

		if battle.isHeavyBag or battle.IsNoliBattle or battle.isRaid2v1 then
			return false
		end

		local request = battle.fulfillingRequest
		if type(request) == "table" and request.requestType ~= nil and request.requestType ~= "move" then
			return false
		end

		if battle.state ~= "input" and not _G.F.isBattleMainMenuOpen() then
			return false
		end

		if not _G.F.hasWildFoeLoaded(battle) then
			return false
		end

		local hasRoom = battle.fulfillingRequest and battle.fulfillingRequest.hasRoom
		if hasRoom == false then
			return false
		end

		return true
	end

	local function getCatchRequestKey(battle)
		local request = type(battle) == "table" and battle.fulfillingRequest or nil
		if type(request) == "table" then
			return request
		end

		if type(battle) ~= "table" then
			return nil
		end

		return table.concat({
			tostring(_G.F.safeTableGet(battle, "battleId")),
			tostring(_G.F.safeTableGet(battle, "turn")),
			tostring(_G.F.safeTableGet(battle, "state")),
		}, "|")
	end

	local function tryThrowCaptureDisc(battle, discId)
		if not isWildBattleCatchable(battle) then
			resetCatchDiscState()
			return false, "Battle is not ready to throw a disc."
		end

		local requestKey = getCatchRequestKey(battle)
		if requestKey == lastCatchDiscRequest then
			if os.clock() - lastDiscAttemptAt > 2.5
				and not catchAwaitingNickname
				and not (_G.isCatchUiActive and _G.isCatchUiActive()) then
				lastCatchDiscRequest = nil
				resetCatchDiscState()
			else
				return false, "Disc already thrown for this turn."
			end
		end

		if requestKey == lastCatchDiscRequest then
			return false, "Disc already thrown for this turn."
		end

		if pendingCatchDiscRequest ~= requestKey then
			pendingCatchDiscRequest = requestKey
			pendingCatchDiscAt = os.clock()
			if _G.resetCatchUiTiming then
				_G.resetCatchUiTiming()
			end
			return false, "Disc throw queued."
		end

		if os.clock() - pendingCatchDiscAt < 0.35 and not (_G.isCatchUiActive and _G.isCatchUiActive()) then
			return false, "Waiting for battle input listener."
		end

		local threw, reason = _G.naturalCatchFromBattle(battle, discId, _G.autoCatchDisc)
		if threw then
			lastCatchDiscRequest = requestKey
			pendingCatchDiscRequest = nil
			catchAwaitingNickname = true
			awaitingCaptureNicknamePrompt = true
			awaitingCaptureNicknameSince = os.clock()
			lastNicknamePromptServiceAt = 0
			rememberPendingCapturedGoppieForme(battle)
			return true
		end

		return false, reason or "Catch UI not ready."
	end

	function api:isEnabled()
		return _G.autoCatchEnabled
	end

	function api:managesBattles()
		return _G.autoCatchEnabled
	end

	function api:shouldCatchBattle(battle)
		return _G.F.shouldCatchWildBattle(battle)
	end

	function api:resetState()
		resetCatchDiscState()
		resetCaptureNicknamePromptState()
		lastDiscAttemptAt = 0
		lastBattleObject = nil
		lastPreparedCatchBattle = nil
	end

	function api:serviceNicknamePrompt()
		_G.F.installGoppieCaptureNetworkHook()

		if visibleTextContainsCaptureNickname() then
			awaitingCaptureNicknamePrompt = true
			awaitingCaptureNicknameSince = os.clock()
			catchAwaitingNickname = true
			registerPendingCapturedGoppieForme()
		end

		if not _G.autoCatchEnabled and not _G.autoFishingEnabled then
			if not catchAwaitingNickname and not awaitingCaptureNicknamePrompt and not waitingForNicknamePromptDismiss then
				return
			end
		elseif _G.autoCatchEnabled then
			if not catchAwaitingNickname and not awaitingCaptureNicknamePrompt and not waitingForNicknamePromptDismiss then
				return
			end
		end

		local now = os.clock()
		if now - lastNicknamePromptServiceAt < NICKNAME_PROMPT_SCAN_INTERVAL then
			return
		end
		lastNicknamePromptServiceAt = now

		local promptOpen = select(1, getBattleGuiYesOrNoLiveState())
		local promptFrame = findVisibleYesOrNoPromptFrame()
		local recentAutoFishingGoppie = _G.autoFishingEnabled
			and _G.F.isMeaningfulFormeValue(_G.lastAutoFishingGoppieForme)
			and os.clock() - _G.lastAutoFishingGoppieFormeAt <= 90
		local looksLikeNicknamePrompt = visibleTextContainsCaptureNickname()
			or ((promptOpen or promptFrame) and recentAutoFishingGoppie)
			or ((promptOpen or promptFrame) and (_G.autoFishingEnabled or _G.autoCatchEnabled))

		if _G.isCatchUiActive and _G.isCatchUiActive() and not promptOpen and not promptFrame and not catchAwaitingNickname and not looksLikeNicknamePrompt then
			return
		end

		handleCaptureNicknamePrompt()
	end

	function api:serviceBattle()
		if not _G.autoCatchEnabled then
			return
		end

		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local battle = _G.F.getCurrentBattle()
		if type(battle) ~= "table" or battle.ended then
			if lastBattleObject then
				lastBattleObject = nil
				lastPreparedCatchBattle = nil
				resetCatchDiscState()
				resetCaptureNicknamePromptState()
			end
			return
		end

		if battle ~= lastBattleObject then
			lastBattleObject = battle
			lastPreparedCatchBattle = nil
			resetCatchDiscState()
		end

		if battle.kind ~= "wild" then
			return
		end

		if _G.F.isBattleSetupPending(battle) then
			return
		end

		if not _G.F.shouldCatchWildBattle(battle) then
			return
		end

		if _G.autoBringEnabled and lastPreparedCatchBattle ~= battle then
			lastPreparedCatchBattle = battle
			_G.F.releaseBattleAutomationForCapture(battle)
		end

		if not _G.F.hasWildFoeLoaded(battle) then
			return
		end

		local discId = _G.normalizeCaptureDiscId(_G.autoCatchDisc)
		if not discId then
			return
		end

		local now = os.clock()
		local catchUiBusy = _G.isCatchUiActive and _G.isCatchUiActive()
		local minDelay = catchUiBusy and 0.45 or 0.35

		if now - lastDiscAttemptAt < minDelay then
			return
		end

		local threw, reason = tryThrowCaptureDisc(battle, discId)
		if threw
			or reason == "Disc already thrown for this turn."
			or reason == "Disc throw queued."
			or reason == "Disc selected."
			or reason == "Disc opened."
			or reason == "Opening bag."
			or reason == "Waiting for disc detail."
			or reason == "Waiting for requested disc detail."
			or reason == "Waiting for bag items."
			or reason == "Requested disc button not found."
			or reason == "Use button not found." then
			lastDiscAttemptAt = now
		end
	end

	return api
end)()

return { name = "catch" }
