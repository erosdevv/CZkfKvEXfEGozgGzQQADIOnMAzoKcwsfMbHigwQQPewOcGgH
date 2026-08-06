-- static.lua
-- Soft-reset / Arceros StaticAutomation.
_G.StaticAutomation = (function()
	local api = {}
	local enabled = false
	local toggle = nil
	local promptCount = 0
	local softResetCount = 0
	local statsLabel = nil
	local currentBattle = nil
	local battleFirstSeenAt = 0
	local lastRunAttemptAt = 0
	local lastInteractAt = 0
	local lastSpecialNoticeAt = 0

	local interactDelay = 0.45
	local softResetPromptPhase = 0
	local waitingForPromptDismiss = false
	local clickedPromptInstance = nil
	local clickedPromptText = nil
	local lastPromptClickAt = 0
	local promptFirstSeenAt = 0
	local lastSeenPromptText = nil

	local promptClickMinVisible = 0.15
	local promptPhaseAdvanceDelay = 0.6
	local promptClickGap = 0.8
	local clickedPromptButton = nil
	local lastPromptSeenAt = 0
	local promptSequenceGrace = 0.75
	local promptSequenceTimeout = 6
	local arcerosWalkActive = false
	local arcerosWalkStartedAt = 0
	local lastSoftResetChatAdvanceAt = 0
	local softResetChatAdvanceGap = 0.45
	local chatBoxCache = nil
	local runAttemptBattle = nil
	local runAttemptStartedAt = 0
	local chunkNotReadySince = 0
	local chunkStuckNotified = false
	local battleStuckDumped = false
	local battleForceEnded = false
	local foeLoadedAt = 0
	local walkArcerosToLavaTrigger
	local isSoftResetDialogueActive
	local isSoftResetSequenceActive

	-- The chunk unloads while a soft reset teleports the player; anything we
	-- do during that window (walking, advancing chat, interacting) races the
	-- game's own transition and can wedge it, so everything active waits on
	-- this.
	local function isCurrentChunkReady()
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local dataManager = type(_G._p) == "table" and _G._p.DataManager or nil
		return type(dataManager) == "table" and type(dataManager.currentChunk) == "table"
	end

	local function refreshStatus()
		if statsLabel then
			pcall(function()
				statsLabel:Set(string.format("Soft Resets: %d", softResetCount))
			end)
		end

		if _G.arcerosStatsLabel then
			pcall(function()
				_G.arcerosStatsLabel:Set(string.format("Soft Resets: %d", softResetCount))
			end)
		end

		if _G.updateStatus then
			_G.updateStatus()
		end
	end

	local function getGuiContainers()
		local containers = {}

		pcall(function()
			local playerGui = _G.Player and _G.Player:FindFirstChildOfClass("PlayerGui")
			if playerGui then
				table.insert(containers, playerGui)
			end
		end)

		pcall(function()
			local coreGui = game:GetService("CoreGui")
			if coreGui then
				table.insert(containers, coreGui)
			end
		end)

		if type(gethui) == "function" then
			local ok, hui = pcall(gethui)
			if ok and hui then
				table.insert(containers, hui)
			end
		end

		pcall(function()
			if type(_G._p) ~= "table" then
				_G._p = _G.F.findP()
			end

			local utilities = type(_G._p) == "table" and _G._p.Utilities or nil
			if utilities and utilities.frontGui then
				table.insert(containers, utilities.frontGui)
			end
		end)

		return containers
	end

	local function isGuiItemVisible(item)
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

	local function clickPromptButton(button)
		if not button then
			return false
		end

		-- Prefer the real mouse; fall back to signal/virtual clicks only
		-- when that isn't possible (window unfocused, no executor support).
		if _G.F.realMouseClickGuiObject(button) then
			return true
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

	local promptCacheValue = nil
	local promptCacheCheckedAt = 0
	local promptCacheScanAt = 0
	local promptCacheHoldFor = 0.05
	local promptRescanGap = 0.2

	local function scanForVisibleYesOrNoPrompt()
		local promptFrame = _G.F.findVisibleBattleYesOrNoPrompt()
		if promptFrame then
			return promptFrame
		end

		for _, container in ipairs(getGuiContainers()) do
			local ok, descendants = pcall(function()
				return container:GetDescendants()
			end)

			if ok then
				for _, item in ipairs(descendants) do
					if item.Name == "YesOrNoPrompt" and isGuiItemVisible(item) then
						return item
					end
				end
			end
		end

		return nil
	end

	local function findVisibleYesOrNoPrompt()
		local now = os.clock()

		-- Several checks per tick funnel through here; serve them all from
		-- one result instead of re-scanning every GUI tree each time.
		if now - promptCacheCheckedAt < promptCacheHoldFor then
			return promptCacheValue
		end

		if promptCacheValue then
			local live = false
			pcall(function()
				live = promptCacheValue.Parent ~= nil
					and promptCacheValue:IsDescendantOf(game)
					and isGuiItemVisible(promptCacheValue)
			end)

			if live then
				promptCacheCheckedAt = now
				return promptCacheValue
			end

			promptCacheValue = nil
		end

		if now - promptCacheScanAt < promptRescanGap then
			promptCacheCheckedAt = now
			return nil
		end

		promptCacheScanAt = now
		promptCacheValue = scanForVisibleYesOrNoPrompt()
		promptCacheCheckedAt = now
		return promptCacheValue
	end

	local function getYesOrNoPromptButtons(promptRoot)
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
			if item:IsA("ImageButton") and isGuiItemVisible(item) then
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

	local function resetSoftResetPromptState()
		softResetPromptPhase = 0
		waitingForPromptDismiss = false
		clickedPromptInstance = nil
		clickedPromptText = nil
		clickedPromptButton = nil
		lastPromptClickAt = 0
		promptFirstSeenAt = 0
		lastSeenPromptText = nil
		lastPromptSeenAt = 0
	end

	local function getPromptText(promptRoot)
		local texts = {}

		pcall(function()
			for _, item in ipairs(promptRoot:GetDescendants()) do
				if item:IsA("TextLabel") and item.Text ~= "" then
					table.insert(texts, item.Text)
				end
			end
		end)

		return table.concat(texts, "|")
	end

	local function clickCurrentPrompt(promptFrame, promptText)
		local wantYes = softResetPromptPhase == 1
		local yesButton, noButton = getYesOrNoPromptButtons(promptFrame)
		local targetButton = wantYes and yesButton or noButton

		if not targetButton or not clickPromptButton(targetButton) then
			return false
		end

		waitingForPromptDismiss = true
		clickedPromptInstance = promptFrame
		clickedPromptText = promptText
		clickedPromptButton = targetButton
		lastPromptClickAt = os.clock()
		return true
	end

	local function isClickedButtonStillLive()
		if not clickedPromptButton then
			return false
		end

		local live = false
		pcall(function()
			live = clickedPromptButton.Parent ~= nil
				and clickedPromptButton:IsDescendantOf(game)
				and isGuiItemVisible(clickedPromptButton)
		end)

		return live
	end

	local function handleStaticRestartPrompt()
		local promptFrame = findVisibleYesOrNoPrompt()
		local promptText = promptFrame and getPromptText(promptFrame) or nil
		local now = os.clock()

		if promptFrame then
			lastPromptSeenAt = now
		end

		if waitingForPromptDismiss then
			local samePrompt = promptFrame ~= nil
				and promptFrame == clickedPromptInstance
				and promptText == clickedPromptText
				and isClickedButtonStillLive()

			-- The game may reuse the exact same frame, text, and buttons for the
			-- next question. If the prompt still looks identical shortly after a
			-- click, assume the click was consumed and it's now showing the next
			-- question, rather than re-clicking the same answer.
			if samePrompt and now - lastPromptClickAt < promptPhaseAdvanceDelay then
				return false
			end

			waitingForPromptDismiss = false
			clickedPromptInstance = nil
			clickedPromptText = nil
			clickedPromptButton = nil
			local completedSoftReset = softResetPromptPhase == 1
			softResetPromptPhase = softResetPromptPhase + 1
			if softResetPromptPhase >= 2 then
				softResetPromptPhase = 0
			end
			if completedSoftReset then
				softResetCount = softResetCount + 1
			end
			promptCount = promptCount + 1
			refreshStatus()

			if not samePrompt then
				-- The prompt visibly changed, so the next question is already
				-- loaded; no need to keep the inter-click spacing.
				lastPromptClickAt = 0
			end

			if not promptFrame then
				promptFirstSeenAt = 0
				lastSeenPromptText = nil
				return true
			end
			-- Fall through so the new question gets answered once it settles.
		end

		if not promptFrame then
			promptFirstSeenAt = 0
			lastSeenPromptText = nil
			return false
		end

		-- Let the prompt finish appearing (and its text settle) before clicking.
		if lastSeenPromptText ~= promptText or promptFirstSeenAt == 0 then
			lastSeenPromptText = promptText
			promptFirstSeenAt = now
			return false
		end

		if now - promptFirstSeenAt < promptClickMinVisible then
			return false
		end

		-- Keep answers spaced out so the next question has time to load in.
		if lastPromptClickAt > 0 and now - lastPromptClickAt < promptClickGap then
			return false
		end

		return clickCurrentPrompt(promptFrame, promptText)
	end

	local function advanceSoftResetNpcChat()
		if findVisibleYesOrNoPrompt() then
			return false
		end

		if not isCurrentChunkReady() then
			return false
		end

		local now = os.clock()
		if now - lastSoftResetChatAdvanceAt < softResetChatAdvanceGap then
			return false
		end

		if not _G.F.advanceSoftResetNpcChat or type(_G.F.advanceSoftResetNpcChat) ~= "function" then
			return false
		end

		if not _G.F.advanceSoftResetNpcChat() then
			return false
		end

		lastSoftResetChatAdvanceAt = now
		return true
	end

	local function handleSoftResetDialogue()
		advanceSoftResetNpcChat()
		return handleStaticRestartPrompt()
	end

	isSoftResetDialogueActive = function()
		if findVisibleYesOrNoPrompt() then
			return true
		end

		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local chat = type(_G._p) == "table" and _G._p.NPCChat or nil
		if type(chat) ~= "table" then
			return false
		end

		local awaitingManual = false
		pcall(function()
			if type(chat.isAwaitingManualAdvance) == "function" then
				awaitingManual = chat:isAwaitingManualAdvance()
			end
		end)

		if awaitingManual then
			return true
		end

		if not (_G.arcerosAutoEnabled or enabled) then
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

		local utilities = type(_G._p) == "table" and _G._p.Utilities or nil
		local frontGui = utilities and utilities.frontGui
		if not frontGui then
			return false
		end

		local chatBox = chatBoxCache
		if not (chatBox and chatBox.Parent and chatBox:IsDescendantOf(frontGui)) then
			chatBox = frontGui:FindFirstChild("ChatBox", true)
			chatBoxCache = chatBox
		end

		return chatBox ~= nil and isGuiItemVisible(chatBox)
	end

	isSoftResetSequenceActive = function()
		if findVisibleYesOrNoPrompt() then
			return true
		end

		if isSoftResetDialogueActive() then
			return true
		end

		local now = os.clock()

		if waitingForPromptDismiss or softResetPromptPhase ~= 0 then
			-- The next prompt in the sequence may still be on its way; don't
			-- start a new interaction, which would reset the prompt phase.
			if now - lastPromptSeenAt <= promptSequenceTimeout then
				return true
			end

			-- The sequence appears to have died; recover.
			resetSoftResetPromptState()
			return false
		end

		return lastPromptSeenAt > 0 and now - lastPromptSeenAt < promptSequenceGrace
	end

	local function normalizeInteractKind(value)
		return string.lower(string.gsub(tostring(value or ""), "%s+", ""))
	end

	local function getStaticChunkRoots()
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

	local function getInanimateInteractPosition(model, tag)
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

	local function collectChunkInanimateInteracts()
		local entries = {}
		local seen = {}

		for _, root in ipairs(getStaticChunkRoots()) do
			local ok, descendants = pcall(function()
				return root:GetDescendants()
			end)

			if ok then
				for _, item in ipairs(descendants) do
					if item.Name == "#InanimateInteract" and item:IsA("StringValue") and not seen[item] then
						seen[item] = true

						local model = item.Parent
						if model then
							table.insert(entries, {
								tag = item,
								model = model,
								kind = tostring(item.Value or ""),
								position = getInanimateInteractPosition(model, item)
							})
						end
					end
				end
			end
		end

		return entries
	end

	local function listChunkInteractKinds(entries)
		local kinds = {}
		local seen = {}

		for _, entry in ipairs(entries) do
			local kind = entry.kind
			if kind ~= "" and not seen[kind] then
				seen[kind] = true
				table.insert(kinds, kind)
			end
		end

		table.sort(kinds)
		return kinds
	end

	local function findNearestChunkInanimateInteract()
		local root = _G.F.getRoot()
		if not root then
			return nil, "Character root is not ready."
		end

		local entries = collectChunkInanimateInteracts()
		if #entries == 0 then
			return nil, "No #InanimateInteract tags found in the current chunk."
		end

		local wanted = normalizeInteractKind(_G.staticInteractTarget)
		local bestEntry = nil
		local bestDistance = math.huge

		for _, entry in ipairs(entries) do
			local matchesTarget = wanted == "" or normalizeInteractKind(entry.kind) == wanted
			if matchesTarget and entry.position then
				local distance = (root.Position - entry.position).Magnitude
				if distance < bestDistance then
					bestEntry = entry
					bestDistance = distance
				end
			end
		end

		if not bestEntry then
			local kinds = listChunkInteractKinds(entries)
			local available = #kinds > 0 and table.concat(kinds, ", ") or "unknown"

			if wanted ~= "" then
				return nil, string.format("No #InanimateInteract with value '%s' in this chunk. Available: %s", _G.staticInteractTarget, available)
			end

			return nil, "No usable #InanimateInteract tags found in the current chunk."
		end

		return bestEntry
	end

	local function resolveStaticBattleKind()
		if _G.arcerosAutoEnabled then
			return "arceros", nil
		end

		local wanted = normalizeInteractKind(_G.staticInteractTarget)
		if wanted == "arceros" then
			return "arceros", nil
		end

		if wanted ~= "" then
			return _G.staticInteractTarget, nil
		end

		local entries = collectChunkInanimateInteracts()
		if #entries == 0 then
			return nil, "No #InanimateInteract tags found. Set Interact Target (e.g. cephalops)."
		end

		local kinds = listChunkInteractKinds(entries)
		if #kinds == 1 then
			return kinds[1], nil
		end

		local entry, reason = findNearestChunkInanimateInteract()
		if entry then
			return entry.kind, nil
		end

		if #kinds > 1 then
			return nil, string.format("Multiple interacts in chunk (%s). Set Interact Target.", table.concat(kinds, ", "))
		end

		return nil, reason or "Could not resolve a static interact target."
	end

	local STATIC_REGION_KEYS = {
		cephalops = "csq",
		burnslug = "slug",
		spooker21 = "spooker",
	}

	local function buildSoftResetRoamerConfig(monsterName, roamFlag, monsterLookDir, resetCF, roamer)
		return {
			monsterName = monsterName,
			[roamFlag] = true,
			monsterLookDir = monsterLookDir,
			owm = roamer,
			resetCF = resetCF
		}
	end

	local function buildStaticBattleConfig(kind, chunk, gameState)
		local normalizedKind = normalizeInteractKind(kind)
		local regionData = chunk.regionData

		if normalizedKind == "cephalops" then
			local roamer = chunk.roamer
			if not roamer then
				return nil, nil, "Cephalops roamer is not loaded in this chunk."
			end

			local pool = regionData and regionData.csq
			if type(pool) ~= "table" then
				return nil, nil, "regionData.csq is not available in this chunk."
			end

			return pool, {
				musicVolume = 0.7,
				musicId = { 9116975080, 9116943160 },
				softResetInfo = buildSoftResetRoamerConfig(
					"Cephalops",
					"doesRoam",
					Vector3.new(-1, 0, 0),
					CFrame.new(-600, 220.5, 1010, 0, 0, -1, 0, 1, 0, 1, 0, 0),
					roamer
				)
			}
		end

		if normalizedKind == "spooker21" then
			local roamer = chunk.roamer
			if not roamer then
				return nil, nil, "Nevermare roamer is not loaded in this chunk."
			end

			local pool = regionData and regionData.spooker
			if type(pool) ~= "table" then
				return nil, nil, "regionData.spooker is not available in this chunk."
			end

			return pool, {
				musicVolume = 0.6,
				musicId = { 7796745359, 7796747076 },
				softResetInfo = buildSoftResetRoamerConfig(
					"Nevermare",
					"doesRoamUFGraveyard",
					Vector3.new(0, 0, -1),
					CFrame.new(-1432, 32.6, 3067.5, -1, 0, 0, 0, 1, 0, 0, 0, -1),
					roamer
				)
			}
		end

		if normalizedKind == "phage" then
			local phage = gameState._phage
			if not phage then
				return nil, nil, "Elephage overworld model is not loaded."
			end

			local pool = regionData and regionData.phage
			if type(pool) ~= "table" then
				return nil, nil, "regionData.phage is not available in this chunk."
			end

			return pool, {
				musicVolume = 0.34,
				musicId = { 9733031349, 9733032843 },
				softResetInfo = buildSoftResetRoamerConfig(
					"Elephage",
					"doesRoam",
					Vector3.new(0, 0, -1),
					CFrame.new(5.7, 7.25, 107.4, -1, 0, 0, 0, 1, 0, 0, 0, -1),
					phage
				)
			}
		end

		if normalizedKind == "arceros" then
			local pool = regionData and regionData.beastLava
			if type(pool) ~= "table" then
				return nil, nil, "regionData.beastLava is not available. Stand in Beasts of Judgement (chunk27)."
			end

			-- Without the scene, doWildBattle nil-indexes partway through
			-- setup and leaves a half-initialized battle.
			local builtInScene = _G.F.getArcerosBattleScene()
			if not builtInScene then
				return nil, nil, "Arceros battle scene is not loaded."
			end

			return pool, {
				musicVolume = 0.8,
				musicId = { 15235696765, 15235699127 },
				useBuiltInScene = builtInScene,
				softResetInfo = {
					isBeastsOfJudgementRoam = true,
					monsterName = "Arceros",
					resetCF = CFrame.new(6319.5, 10.2, 1466.7, 0.41174382, 0, -0.911299646, 0, 1, 0, 0.911299646, 0, 0.41174382),
				},
			}
		end

		if normalizedKind == "burnslug" then
			local pool = regionData and regionData.slug
			if type(pool) ~= "table" then
				return nil, nil, "regionData.slug is not available in this chunk."
			end

			return pool, {}
		end

		local regionKey = STATIC_REGION_KEYS[normalizedKind] or kind
		local pool = regionData and (regionData[regionKey] or regionData[normalizedKind])

		if type(pool) ~= "table" then
			for key, value in pairs(regionData or {}) do
				if normalizeInteractKind(key) == normalizedKind and type(value) == "table" then
					pool = value
					break
				end
			end
		end

		if type(pool) ~= "table" then
			return nil, nil, string.format("No regionData battle pool found for '%s'.", tostring(kind))
		end

		return pool, {}
	end

	local function findStaticInteractEntry(kind)
		local normalizedKind = normalizeInteractKind(kind)

		for _, entry in ipairs(collectChunkInanimateInteracts()) do
			if normalizeInteractKind(entry.kind) == normalizedKind then
				return entry
			end
		end

		return nil
	end

	walkArcerosToLavaTrigger = function(manualRequest)
		if arcerosWalkActive then
			return true
		end

		if not isCurrentChunkReady() then
			return false, "Waiting for the chunk to load."
		end

		local lavaTrigger = _G.F.getSelectedBeastTrigger()
		if not lavaTrigger or not lavaTrigger:IsA("BasePart") then
			return false
		end

		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		local root = _G.F.getRoot()
		if not root then
			return false, "Character root is not ready."
		end

		local lookDir = -lavaTrigger.CFrame.RightVector
		local standPos = lavaTrigger.Position + lookDir * 5

		arcerosWalkActive = true
		arcerosWalkStartedAt = os.clock()

		task.spawn(function()
			local deadline = os.clock() + 60
			local startedWalk = false

			while os.clock() < deadline do
				if not arcerosWalkActive then
					break
				end

				if not manualRequest and not _G.arcerosAutoEnabled and not enabled then
					break
				end

				if _G.F.getCurrentBattle() then
					break
				end

				local blocked = false
				pcall(function()
					blocked = isSoftResetSequenceActive() or not isCurrentChunkReady()
				end)

				if blocked then
					task.wait(0.2)
				else
					local masterControl = type(_G._p) == "table" and _G._p.MasterControl or nil
					if type(masterControl) == "table" and masterControl.WalkEnabled ~= false then
						if not startedWalk then
							pcall(function()
								masterControl:WalkTo(standPos, 8)
							end)
							startedWalk = true
						end

						local liveRoot = _G.F.getRoot()
						if liveRoot then
							local distance = (liveRoot.Position - standPos).Magnitude
							if distance <= 4 then
								pcall(function()
									masterControl:WalkTo(lavaTrigger.Position + lookDir * 2, 8)
								end)
								task.wait(1.5)
								break
							end
						end
					end

					task.wait(0.2)
				end
			end

			arcerosWalkActive = false
		end)

		return true
	end

	local function startNaturalStaticEncounter(kindOverride)
		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		if type(_G._p) ~= "table" then
			return false, "Hook is not ready."
		end

		if _G.F.getCurrentBattle()
			or (_G._p.BattleClient and _G._p.BattleClient.currentBattle)
			or (_G._p.Battle and _G._p.Battle.currentBattle) then
			return false, "Battle already active."
		end

		local kind, kindReason
		if kindOverride and kindOverride ~= "" then
			kind = kindOverride
		else
			kind, kindReason = resolveStaticBattleKind()
		end

		if not kind then
			return false, kindReason
		end

		local isArcerosKind = normalizeInteractKind(kind) == "arceros"

		if not _G.F.getRoot() then
			return false, "Waiting for the character to load."
		end

		if not isArcerosKind then
			local masterControl = _G._p.MasterControl
			if type(masterControl) == "table" and masterControl.WalkEnabled == false then
				return false, "Cannot interact right now."
			end
		end

		if isArcerosKind then
			if arcerosWalkActive then
				return false
			end

			-- Never fall through to the generic interact/doWildBattle paths
			-- for Arceros: starting the battle any way other than touching
			-- the lava trigger can nil-index inside the game's battle setup
			-- and leave a half-initialized battle (one camera move, no
			-- player side, never completes). Verify every piece and wait
			-- until all of it is loaded.
			if not isCurrentChunkReady() then
				return false, "Waiting for the chunk to load."
			end

			local lavaTrigger = _G.F.getSelectedBeastTrigger()
			if not lavaTrigger then
				return false, "Waiting for the soft reset trigger to load."
			end

			local walked, walkReason = walkArcerosToLavaTrigger()
			if walked then
				return false
			end

			return false, walkReason or "Waiting for the soft reset trigger walk."
		end

		local inanimateInteract = _G._p.InanimateInteract
		local handler = type(inanimateInteract) == "table" and inanimateInteract[kind] or nil
		local entry = findStaticInteractEntry(kind)

		if type(handler) == "function" then
			-- Calling the game's handler with a missing model nil-indexes
			-- partway through its battle setup; wait until it's loaded.
			if not entry or not entry.model or not entry.model.Parent then
				return false, string.format("Overworld model for '%s' is not loaded.", tostring(kind))
			end

			resetSoftResetPromptState()

			local ok, result = pcall(function()
				return handler(entry.model)
			end)

			if not ok then
				return false, tostring(result)
			end

			resetSoftResetPromptState()
			return true
		end

		local chunk = _G._p.DataManager and _G._p.DataManager.currentChunk
		if type(chunk) ~= "table" then
			return false, "Current chunk is not ready."
		end

		local pool, options, buildReason = buildStaticBattleConfig(kind, chunk, _G._p)
		if type(pool) ~= "table" then
			return false, buildReason or string.format("No battle config for '%s'.", tostring(kind))
		end

		local battleClient = _G._p.BattleClient or _G._p.Battle
		if type(battleClient) ~= "table" or type(battleClient.doWildBattle) ~= "function" then
			return false, "BattleClient is not ready."
		end

		local ok, result = pcall(function()
			resetSoftResetPromptState()
			return battleClient:doWildBattle(pool, options or {})
		end)

		if not ok then
			return false, tostring(result)
		end

		resetSoftResetPromptState()
		return true
	end

	local function getPromptWorldPosition(prompt)
		local parent = prompt and prompt.Parent

		if not parent then
			return nil
		end

		if parent:IsA("Attachment") then
			return parent.WorldPosition
		end

		if parent:IsA("BasePart") then
			return parent.Position
		end

		local part = parent:FindFirstAncestorWhichIsA("BasePart")
		return part and part.Position or nil
	end

	local function findNearestEnabledProximityPrompt()
		local root = _G.F.getRoot()
		if not root then
			return nil, "Character root is not ready."
		end

		local ok, descendants = pcall(function()
			return workspace:GetDescendants()
		end)

		if not ok then
			return nil, "Workspace prompts are not available."
		end

		local bestPrompt = nil
		local bestDistance = math.huge

		for _, item in ipairs(descendants) do
			if item:IsA("ProximityPrompt") and item.Enabled then
				local position = getPromptWorldPosition(item)

				if position then
					local distance = (root.Position - position).Magnitude
					local maxDistance = tonumber(item.MaxActivationDistance) or 10

					if distance <= maxDistance + 6 and distance < bestDistance then
						bestPrompt = item
						bestDistance = distance
					end
				end
			end
		end

		if not bestPrompt then
			return nil, "Stand near the static encounter prompt."
		end

		return bestPrompt
	end

	local function findNearestEnabledClickDetector()
		local root = _G.F.getRoot()
		if not root then
			return nil, "Character root is not ready."
		end

		local ok, descendants = pcall(function()
			return workspace:GetDescendants()
		end)

		if not ok then
			return nil, "Workspace click detectors are not available."
		end

		local bestDetector = nil
		local bestDistance = math.huge

		for _, item in ipairs(descendants) do
			if item:IsA("ClickDetector") then
				local parent = item.Parent
				local part = parent and (parent:IsA("BasePart") and parent or parent:FindFirstAncestorWhichIsA("BasePart"))

				if part then
					local distance = (root.Position - part.Position).Magnitude
					local maxDistance = tonumber(item.MaxActivationDistance) or 32

					if distance <= maxDistance + 6 and distance < bestDistance then
						bestDetector = item
						bestDistance = distance
					end
				end
			end
		end

		if not bestDetector then
			return nil, "Stand near the static encounter prompt."
		end

		return bestDetector
	end

	local function triggerProximityPrompt(prompt)
		if not prompt then
			return false
		end

		if type(fireproximityprompt) == "function" then
			local ok = pcall(function()
				fireproximityprompt(prompt)
			end)

			if ok then
				return true
			end
		end

		local ok = pcall(function()
			prompt:InputHoldBegin()
			task.wait((tonumber(prompt.HoldDuration) or 0) + 0.05)
			prompt:InputHoldEnd()
		end)

		return ok
	end

	local function triggerClickDetector(detector)
		if not detector then
			return false
		end

		if type(fireclickdetector) == "function" then
			local ok = pcall(function()
				fireclickdetector(detector)
			end)

			if ok then
				return true
			end
		end

		return false
	end

	local function resetBattleState()
		currentBattle = nil
		battleFirstSeenAt = 0
		lastRunAttemptAt = 0
		battleStuckDumped = false
		battleForceEnded = false
		foeLoadedAt = 0
	end

	local function notifyStaticSpecial(foe, specialValue, specialReason)
		local now = os.clock()
		if now - lastSpecialNoticeAt < 2 then
			return
		end

		lastSpecialNoticeAt = now
		local wasBeastHunt = _G.arcerosAutoEnabled
		enabled = false
		_G.arcerosAutoEnabled = false

		if type(toggle) == "table" and type(toggle.Set) == "function" and toggle.Value ~= false then
			task.defer(function()
				toggle:Set(false)
			end)
		end

		if _G.configUi.autoArcerosToggle and type(_G.configUi.autoArcerosToggle.Set) == "function" then
			task.defer(function()
				_G.configUi.autoArcerosToggle:Set(false)
			end)
		end

		pcall(function()
			_G.OrionLib:MakeNotification({
				Name = wasBeastHunt and (_G.F.getSelectedBeastName() .. " Hunt Paused") or "Static Hunt Paused",
				Content = string.format("Found %s (%s: %s).", tostring(foe and (foe.name or foe.species) or "wild Loomian"), tostring(specialReason), tostring(specialValue)),
				Time = 8
			})
		end)

		refreshStatus()
	end

	function api:isAutomationActive()
		return enabled or _G.arcerosAutoEnabled
	end

	function api:checkBattleFoe(battle)
		if not self:isAutomationActive() or not _G.F.hasWildFoeLoaded(battle) then
			return false
		end

		if _G.arcerosAutoEnabled then
			local foe = _G.F.getBattleFoeMonster(battle)
			local gleamValue = foe and _G.F.getMonsterGleamValue(foe)
			if _G.isActiveFlag(gleamValue) then
				notifyStaticSpecial(foe, gleamValue, "Gleaming/Gamma")
				return true
			end

			return false
		end

		local foe, specialValue, specialReason = _G.F.getStaticHuntSpecialFoe(battle)
		if foe then
			notifyStaticSpecial(foe, specialValue, specialReason)
			return true
		end

		return false
	end

	function api:isArcerosWalking()
		return arcerosWalkActive
	end

	function api:walkToArcerosTrigger()
		return walkArcerosToLavaTrigger(true)
	end

	function api:isEnabled()
		return enabled
	end

	function api:setEnabled(value)
		enabled = value and true or false

		if not enabled and not _G.arcerosAutoEnabled then
			resetBattleState()
			resetSoftResetPromptState()
			arcerosWalkActive = false
		end

		refreshStatus()
	end

	function api:attachToggle(newToggle)
		toggle = newToggle
	end

	function api:getPromptCount()
		return promptCount
	end

	function api:getSoftResetCount()
		return softResetCount
	end

	function api:attachStatsLabel(label)
		statsLabel = label
		refreshStatus()
	end

	function api:resetStats()
		promptCount = 0
		softResetCount = 0
		resetSoftResetPromptState()
		refreshStatus()
	end

	function api:serviceSoftResetDialogue()
		if not self:isAutomationActive() then
			return
		end

		pcall(function()
			if type(_G._p) ~= "table" then
				_G._p = _G.F.findP()
			end

			handleSoftResetDialogue()
		end)

		if not _G.arcerosAutoEnabled or arcerosWalkActive or _G.F.getCurrentBattle() then
			return
		end

		local blocked = false
		pcall(function()
			blocked = isSoftResetSequenceActive()
		end)

		if blocked then
			return
		end

		pcall(function()
			local lavaTrigger = _G.F.getSelectedBeastTrigger()
			if lavaTrigger and walkArcerosToLavaTrigger then
				walkArcerosToLavaTrigger()
			end
		end)
	end

	function api:serviceBattle()
		if not self:isAutomationActive() then
			return
		end

		if type(_G._p) ~= "table" then
			_G._p = _G.F.findP()
		end

		self:serviceSoftResetDialogue()

		local battle = _G.F.getCurrentBattle()
		if type(battle) ~= "table" then
			return
		end

		if self:checkBattleFoe(battle) then
			return
		end

		if _G.fastForwardEnabled or enabled or _G.arcerosAutoEnabled then
			_G.F.setBattleFastForward(true, battle)
			_G.F.applyBattleAnimationFastForward(battle, false)
		end

		if battle.ended then
			_G.F.clearBattleRunTiming(battle)
			return
		end

		local now = os.clock()

		if currentBattle ~= battle then
			currentBattle = battle
			battleFirstSeenAt = now
			battleStuckDumped = false
			battleForceEnded = false
			foeLoadedAt = 0
		end

		local battleAge = now - battleFirstSeenAt

		-- A soft-reset battle should be over within a few seconds. If one
		-- sits around, log its state once so the wedge is visible in the
		-- console instead of hanging silently.
		if battleAge >= 15 and not battleStuckDumped then
			battleStuckDumped = true
			pcall(function()
				warn(string.format(
					"[Auto Static] Battle stuck for %ds: setupComplete=%s state=%s battleId=%s turn=%s CanRun=%s foeLoaded=%s menuOpen=%s linked=%s",
					math.floor(battleAge),
					tostring(_G.F.safeTableGet(battle, "setupComplete")),
					tostring(_G.F.safeTableGet(battle, "state")),
					tostring(_G.F.safeTableGet(battle, "battleId")),
					tostring(_G.F.safeTableGet(battle, "turn")),
					tostring(_G.F.safeTableGet(battle, "CanRun")),
					tostring(_G.F.hasWildFoeLoaded(battle)),
					tostring(_G.F.isBattleMainMenuOpen()),
					tostring(_G.F.isBattleLinkedToBattleGui(battle))
				))
			end)
		end

		-- Last resort: force the battle closed so the hunt can't wedge on a
		-- battle that never becomes runnable. The next soft reset restores
		-- clean state either way.
		if battleAge >= 25 and not battleForceEnded then
			battleForceEnded = true
			warn("[Auto Static] Battle stuck for 25s; force-ending it.")

			task.spawn(function()
				pcall(function()
					local network = type(_G._p) == "table" and _G._p.Network or nil
					local battleId = _G.F.safeTableGet(battle, "battleId")
					if type(network) == "table" and type(network.get) == "function" and battleId then
						network:get("BattleFunction", battleId, "tryRun")
					end
				end)
			end)

			task.spawn(function()
				task.wait(3)

				pcall(function()
					if not _G.F.isBattleEnded(battle) then
						_G.F.finishNaturalBattleRun(battle, true)
					end
				end)

				pcall(function()
					_G.F.releaseFinishedBattle(battle)
				end)
			end)

			return
		end

		if not _G.F.isStaticBattleReadyToEnd(battle) then
			return
		end

		if foeLoadedAt == 0 then
			foeLoadedAt = now
		end

		-- The foe's special flags (gleam/wisp) can replicate a beat after
		-- the monster entry itself appears; hold every run attempt long
		-- enough for checkBattleFoe to see the settled flags first, so a
		-- Gleaming pauses the hunt instead of being run from.
		if now - foeLoadedAt < 1 then
			return
		end

		-- The built-in-scene battle sometimes never shows a detectable run
		-- menu; after waiting on it for a while, use the timed run path so
		-- the battle still gets ended instead of wedging the hunt.
		local allowTimedFallback = battleAge >= 6

		if not _G.F.isBattleRunMenuReady(battle, allowTimedFallback) then
			return
		end

		if now - lastRunAttemptAt < 0.35 then
			return
		end

		lastRunAttemptAt = now

		-- tryRun invokes the server and can yield forever if the battle is
		-- not ready server-side; run the attempt on its own thread so a
		-- stuck invoke can't kill this service loop, and don't stack a new
		-- attempt on the same battle until the old one finishes or times out.
		if runAttemptBattle == battle and now - runAttemptStartedAt < 8 then
			return
		end

		runAttemptBattle = battle
		runAttemptStartedAt = now

		task.spawn(function()
			pcall(function()
				_G.F.naturalRunFromBattle(battle, allowTimedFallback)
			end)

			if runAttemptBattle == battle then
				runAttemptBattle = nil
			end
		end)
	end

	function api:runCycle()
		if not self:isAutomationActive() then
			return false
		end

		if _G.F.getCurrentBattle() then
			return false
		end

		if arcerosWalkActive then
			return false
		end

		if isSoftResetSequenceActive() then
			pcall(handleSoftResetDialogue)
			return false, "Waiting for the static prompt."
		end

		local now = os.clock()

		if not isCurrentChunkReady() then
			if chunkNotReadySince == 0 then
				chunkNotReadySince = now
			elseif now - chunkNotReadySince >= 30 and not chunkStuckNotified then
				chunkStuckNotified = true
				warn("[Auto Static] Chunk has not reloaded for 30s; the soft reset looks stuck. A rejoin may be needed.")

				pcall(function()
					_G.OrionLib:MakeNotification({
						Name = "Arceros",
						Content = "Chunk has not reloaded for 30s. The soft reset looks stuck; a rejoin may be needed.",
						Time = 10,
					})
				end)
			end

			return false, "Waiting for the chunk to load."
		end

		chunkNotReadySince = 0
		chunkStuckNotified = false

		if now - lastInteractAt < interactDelay then
			return false
		end

		lastInteractAt = now
		return startNaturalStaticEncounter()
	end

	function api:startInteraction(kind)
		if _G.F.getCurrentBattle() then
			return false, "Battle already active."
		end

		return startNaturalStaticEncounter(kind)
	end

	return api
end)()

return { name = "static" }
