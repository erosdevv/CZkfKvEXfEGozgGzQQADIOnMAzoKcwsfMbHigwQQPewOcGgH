-- ui.lua
-- Orion window, tabs, and background service loops.
_G.Window = _G.OrionLib:MakeWindow({
	Name = "LLSPLOIT",
	HidePremium = true,
	SaveConfig = false,
	IntroEnabled = false,
	CloseCallback = function()
		_G.uiAlive = false
		_G.F.disableAllFeatures()
	end
})

print("[LLSPLOIT] UI ready")
__llsploitBootNotify("Loaded. Press RightShift if hidden.")
pcall(function()
	_G.OrionLib:MakeNotification({
		Name = "LLSPLOIT",
		Content = "Loaded successfully. Press RightShift if the window is hidden.",
		Time = 4
	})
end)

_G.OverviewTab = _G.Window:MakeTab({ Name = "Overview", Icon = "layout-dashboard" })
_G.EncountersTab = _G.Window:MakeTab({ Name = "Farm", Icon = "sparkles" })
_G.HuntsTab = _G.Window:MakeTab({ Name = "Hunts", Icon = "crosshair" })
_G.BattleTab = _G.Window:MakeTab({ Name = "Battle", Icon = "swords" })
_G.RallyTab = _G.Window:MakeTab({ Name = "Rally", Icon = "users" })
_G.StorageTab = _G.Window:MakeTab({ Name = "Storage", Icon = "archive" })
_G.FossilTab = _G.Window:MakeTab({ Name = "Fossil", Icon = "bone" })
_G.ArcadeTab = _G.Window:MakeTab({ Name = "Arcade", Icon = "gamepad-2" })
_G.SettingsTab = _G.Window:MakeTab({ Name = "Settings", Icon = "settings" })

-- Aliases keep older section builders working after the tab merge.
_G.DashboardTab = _G.OverviewTab
_G.InformationTab = _G.OverviewTab
_G.FishingTab = _G.EncountersTab
_G.TrainersTab = _G.BattleTab
_G.HuntingTab = _G.HuntsTab
_G.StaticTab = _G.HuntsTab
_G.CollectionTab = _G.StorageTab
_G.MinigamesTab = _G.ArcadeTab
_G.ShopTab = _G.SettingsTab
_G.FossilReviveTab = _G.FossilTab
_G.WorldTab = _G.FossilTab

local informationCurrencySection = _G.InformationTab:AddSection({ Name = "Currencies" })
_G.informationLabels.money = informationCurrencySection:AddLabel("Money: N/A")
_G.informationLabels.tix = informationCurrencySection:AddLabel("Tix: N/A")
_G.informationLabels.bp = informationCurrencySection:AddLabel("BP: N/A")

local informationStatusSection = _G.InformationTab:AddSection({ Name = "Status" })
_G.informationLabels.status = informationStatusSection:AddLabel("Loaded: 0/3")
informationStatusSection:AddButton({
	Name = "Refresh Information",
	Icon = "refresh-cw",
	Callback = function()
		_G.F.refreshInformationLabels()
	end
})
_G.F.refreshInformationLabels()


_G.EncountersTab:AddSection({ Name = "Wild Encounters" })

_G.configUi.autoEncounterToggle = _G.EncountersTab:AddToggle({
	Name = "Auto Encounter",
	Default = _G.autoEncounterEnabled,
	Color = Color3.fromRGB(0, 190, 180),
	Callback = function(value)
		_G.F.setAutoEncounterEnabled(value, true)
	end
})

_G.configUi.autoRunToggle = _G.EncountersTab:AddToggle({
	Name = "Auto Run",
	Default = _G.autoRunEnabled,
	Color = Color3.fromRGB(90, 200, 255),
	Callback = function(value)
		_G.F.setAutoRunEnabled(value)
	end
})

_G.configUi.autoFightCorruptToggle = _G.EncountersTab:AddToggle({
	Name = "Fight Corrupt",
	Default = _G.autoFightCorruptEnabled,
	Color = Color3.fromRGB(220, 90, 90),
	Callback = function(value)
		_G.F.setAutoFightCorruptEnabled(value)
	end
})

_G.EncountersTab:AddTextbox({
	Name = "Target Loomian",
	Default = _G.encounterTargetLoomian,
	TextDisappear = false,
	Callback = function(value)
		_G.encounterTargetLoomian = string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
	end
})

_G.configUi.encounterDelay = _G.EncountersTab:AddSlider({
	Name = "Encounter Delay",
	Min = 0.5,
	Max = 6,
	Default = _G.autoEncounterDelay,
	Increment = 0.25,
	ValueName = "s",
	Callback = function(value)
		_G.autoEncounterDelay = value
	end
})

_G.configUi.encounterRunDelay = _G.EncountersTab:AddSlider({
	Name = "Run Delay",
	Min = 1,
	Max = 6,
	Default = _G.encounterRunDelay,
	Increment = 0.25,
	ValueName = "s",
	Callback = function(value)
		_G.encounterRunDelay = value
	end
})

_G.EncountersTab:AddButton({
	Name = "Start Encounter Now",
	Icon = "zap",
	Callback = function()
		local started, reason = _G.F.startAutoEncounter()

		if not started and reason then
			_G.OrionLib:MakeNotification({
				Name = "Auto Encounter",
				Content = reason,
				Time = 4
			})
		end
	end
})

_G.EncountersTab:AddSection({ Name = "Pity" })

_G.configUi.pityTargetDropdown = _G.EncountersTab:AddDropdown({
	Name = "Pity Target",
	Default = _G.pityTargetId == 2 and "Roaming" or "Gleaming",
	Options = { "Gleaming", "Roaming" },
	Callback = function(value)
		_G.pityTargetId = value == "Roaming" and 2 or 1
		if _G.pityBoostsEnabled then
			_G.F.setPityBoostsEnabled(true)
		end
	end
})

_G.configUi.pityBoostsToggle = _G.EncountersTab:AddToggle({
	Name = "Auto Pity Boosts",
	Default = _G.pityBoostsEnabled,
	Color = Color3.fromRGB(255, 180, 80),
	Callback = function(value)
		_G.F.setPityBoostsEnabled(value)
	end
})

_G.EncountersTab:AddButton({
	Name = "Show Pity Status",
	Icon = "info",
	Callback = function()
		local state = _G.F.refreshPityState(true)
		local content
		if (tonumber(state.active) or 0) == 1 then
			content = string.format("Gleaming pity active: %s encounters left.", tostring(state.gleam))
		elseif (tonumber(state.active) or 0) == 2 then
			content = string.format("Roaming pity active: %s encounters left.", tostring(state.roam))
		else
			content = "No pity switch is active."
		end
		if not _G.F.isPityCounting(state) and (tonumber(state.active) or 0) ~= 0 then
			content = content .. "\nWARNING: the matching boost is NOT running - encounters are not counting!"
		end
		_G.OrionLib:MakeNotification({
			Name = "Pity Status",
			Content = content,
			Time = 6,
		})
	end
})

_G.EncountersTab:AddSection({ Name = "Capture Rules" })

_G.configUi.autoCatchToggle = _G.EncountersTab:AddToggle({
	Name = "Auto Catch",
	Default = _G.autoCatchEnabled,
	Color = Color3.fromRGB(255, 120, 180),
	Callback = function(value)
		_G.F.setAutoCatchEnabled(value)
	end
})

_G.EncountersTab:AddTextbox({
	Name = "Capture Disc",
	Default = _G.autoCatchDisc,
	TextDisappear = false,
	Callback = function(value)
		_G.autoCatchDisc = string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
	end
})

_G.configUi.stopOnGleamingToggle = _G.EncountersTab:AddToggle({
	Name = "Stop on Gleaming",
	Default = _G.stopOnGleaming,
	Color = Color3.fromRGB(255, 215, 90),
	Callback = function(value)
		_G.stopOnGleaming = value
	end
})

_G.configUi.stopOnGammaToggle = _G.EncountersTab:AddToggle({
	Name = "Stop on Gamma",
	Default = _G.stopOnGamma,
	Color = Color3.fromRGB(120, 220, 120),
	Callback = function(value)
		_G.stopOnGamma = value
	end
})

_G.configUi.stopOnWispToggle = _G.EncountersTab:AddToggle({
	Name = "Stop on Wisp",
	Default = _G.stopOnWisp,
	Color = Color3.fromRGB(180, 140, 255),
	Callback = function(value)
		_G.stopOnWisp = value
	end
})

_G.configUi.denyNicknameToggle = _G.EncountersTab:AddToggle({
	Name = "Deny Nickname",
	Default = _G.denyNicknameEnabled,
	Color = Color3.fromRGB(180, 150, 255),
	Callback = function(value)
		_G.denyNicknameEnabled = value and true or false
		_G.F.syncJackMiscSettings()
		_G.F.installJackStyleGameplayHooks()
	end
})

_G.EncountersTab:AddSection({ Name = "Wild Move Helpers" })

_G.configUi.useSpareToggle = _G.EncountersTab:AddToggle({
	Name = "Use Spare",
	Default = _G.useSpareEnabled,
	Color = Color3.fromRGB(120, 220, 200),
	Callback = function(value)
		_G.useSpareEnabled = value and true or false
	end
})

local corruptMoveOptions = { "Disabled" }
for slot = 1, 4 do
	table.insert(corruptMoveOptions, "Move " .. tostring(slot))
end

_G.configUi.corruptMoveDropdown = _G.EncountersTab:AddDropdown({
	Name = "Corrupt Move",
	Default = _G.corruptMove,
	Options = corruptMoveOptions,
	Callback = function(value)
		_G.corruptMove = tostring(value or "Disabled")
	end
})

_G.HuntsTab:AddSection({ Name = "Static Hunts" })

_G.configUi.autoStaticToggle = _G.HuntsTab:AddToggle({
	Name = "Auto Static",
	Default = _G.StaticAutomation:isEnabled(),
	Color = Color3.fromRGB(80, 185, 255),
	Callback = function(value)
		_G.StaticAutomation:setEnabled(value)
		if value and _G.arcerosAutoEnabled and _G.configUi.autoArcerosToggle then
			_G.arcerosAutoEnabled = false
			pcall(function()
				_G.configUi.autoArcerosToggle:Set(false)
			end)
		end
	end
})
_G.StaticAutomation:attachToggle(_G.configUi.autoStaticToggle)
_G.StaticAutomation:attachStatsLabel(_G.HuntsTab:AddLabel("Soft Resets: 0"))

_G.HuntsTab:AddTextbox({
	Name = "Interact Target",
	Default = _G.staticInteractTarget,
	TextDisappear = false,
	Callback = function(value)
		_G.staticInteractTarget = string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
	end
})

_G.HuntsTab:AddButton({
	Name = "Interact Now",
	Icon = "zap",
	Callback = function()
		local started, reason = _G.StaticAutomation:startInteraction()
		if not started and reason then
			_G.OrionLib:MakeNotification({ Name = "Static", Content = reason, Time = 4 })
		end
	end
})

_G.HuntsTab:AddSection({ Name = "Beast Soft Resets" })

_G.configUi.beastTargetDropdown = _G.HuntsTab:AddDropdown({
	Name = "Beast",
	Options = { "Arceros", "Glacadia" },
	Default = _G.F.getSelectedBeastName(),
	Callback = function(value)
		if _G.BEAST_HUNTS[tostring(value)] then
			_G.beastTarget = tostring(value)
		end
	end
})

_G.configUi.autoArcerosToggle = _G.HuntsTab:AddToggle({
	Name = "Auto Beast Soft Reset",
	Default = _G.arcerosAutoEnabled,
	Color = Color3.fromRGB(255, 120, 60),
	Callback = function(value)
		_G.arcerosAutoEnabled = value and true or false
		if value then
			if _G.StaticAutomation and _G.StaticAutomation:isEnabled() and _G.configUi.autoStaticToggle then
				_G.StaticAutomation:setEnabled(false)
				pcall(function()
					_G.configUi.autoStaticToggle:Set(false)
				end)
			end
		elseif _G.StaticAutomation and not _G.StaticAutomation:isEnabled() then
			_G.StaticAutomation:setEnabled(false)
		end
	end
})

_G.arcerosStatsLabel = _G.HuntsTab:AddLabel("Soft Resets: 0")

_G.HuntsTab:AddButton({
	Name = "Soft Reset Now",
	Icon = "flame",
	Callback = function()
		local started, reason = _G.StaticAutomation:startInteraction("arceros")
		if not started and reason then
			_G.OrionLib:MakeNotification({ Name = _G.F.getSelectedBeastName(), Content = reason, Time = 4 })
		end
	end
})

_G.HuntsTab:AddButton({
	Name = "Walk to Soft Reset Trigger",
	Icon = "footprints",
	Callback = function()
		if not _G.StaticAutomation then
			return
		end

		local walked, reason = _G.StaticAutomation:walkToArcerosTrigger()
		if not walked and reason then
			_G.OrionLib:MakeNotification({ Name = _G.F.getSelectedBeastName(), Content = reason, Time = 4 })
		elseif not _G.F.getSelectedBeastTrigger() then
			_G.OrionLib:MakeNotification({
				Name = _G.F.getSelectedBeastName(),
				Content = "Soft reset trigger not found. Go to the Beasts of Judgement chamber first.",
				Time = 4
			})
		end
	end
})

_G.HuntsTab:AddButton({
	Name = "Reset Stats",
	Icon = "rotate-ccw",
	Callback = function()
		if _G.StaticAutomation then
			_G.StaticAutomation:resetStats()
		end
	end
})


_G.BattleTab:AddSection({ Name = "Trainer Target" })

do
	-- Seed from whatever is already loaded so the first paint isn't empty.
	pcall(function()
		_G.F.jackRefreshTrainerTargetFromChunk(false)
	end)

	local initialOptions = _G.jackTrainerDropdownOptions or { "Disabled" }
	local initialSelected = _G.F.jackFindTrainerOptionForId(_G.jackAutoBattle.Trainer) or "Disabled"

	_G.configUi.jackTrainerDropdown = _G.BattleTab:AddDropdown({
		Name = "Battleable Trainer",
		Default = initialSelected,
		Options = initialOptions,
		Callback = function(value)
			if _G.jackSyncingDropdownUi then
				return
			end
			_G.F.jackSetAutoTrainer(value)
		end,
	})

	-- Legacy alias: older config sync looked for a textbox under this key.
	_G.configUi.jackTrainerIdTextbox = _G.configUi.jackTrainerDropdown
end

_G.BattleTab:AddButton({
	Name = "Refresh Chunk Trainers",
	Icon = "refresh-cw",
	Callback = function()
		local entries = _G.F.jackRefreshTrainerTargetFromChunk(true)
		local count = type(entries) == "table" and #entries or 0
		_G.OrionLib:MakeNotification({
			Name = "Trainers",
			Content = count > 0
				and (tostring(count) .. " battleable trainer(s) in this chunk.")
				or "No battleable trainers loaded in this chunk.",
			Time = 4,
		})
	end,
})

_G.configUi.autoTrainerDelay = _G.BattleTab:AddSlider({
	Name = "Trainer Requeue Delay",
	Min = 0,
	Max = 5,
	Increment = 0.1,
	Default = _G.autoTrainerDelay or 0,
	ValueName = "s",
	Callback = function(value)
		_G.autoTrainerDelay = tonumber(value) or 0
	end
})

_G.BattleTab:AddLabel("Battle is trainers only. Use Farm for wild encounters. Rematch chat is auto-accepted.")

local jackMoveOptions = { "Disabled" }
for slot = 1, 4 do
	table.insert(jackMoveOptions, "Move " .. tostring(slot))
end

_G.BattleTab:AddSection({ Name = "Trainer Auto Move" })

_G.configUi.jackMoveDropdown = _G.BattleTab:AddDropdown({
	Name = "Auto Move",
	Default = _G.jackAutoBattle.Move,
	Options = jackMoveOptions,
	Callback = function(value)
		if _G.jackSyncingDropdownUi then
			return
		end
		_G.F.jackSetAutoMove(value)
	end,
})

_G.BattleTab:AddSection({ Name = "Trainer Assist" })

_G.configUi.autoBattleToggle = _G.BattleTab:AddToggle({
	Name = "Trainer Assist",
	Default = _G.autoBattleEnabled,
	Color = Color3.fromRGB(255, 115, 120),
	Callback = function(value)
		_G.F.setAutoBattleEnabled(value)
	end
})

_G.BattleTab:AddLabel("Turns on Fast Battle, Skip Dialogue, and prompt denies. Does not touch Farm / wild encounters.")

_G.BattleTab:AddSection({ Name = "Auto Heal" })

_G.configUi.autoHealToggle = _G.BattleTab:AddToggle({
	Name = "Auto Heal (Outdoor Only)",
	Default = _G.autoHealEnabled,
	Color = Color3.fromRGB(120, 255, 160),
	Callback = function(value)
		_G.autoHealEnabled = value and true or false
	end
})

_G.configUi.autoHealDelay = _G.BattleTab:AddSlider({
	Name = "Auto Heal Delay",
	Min = 3,
	Max = 60,
	Increment = 1,
	Default = _G.autoHealDelay,
	ValueName = "s",
	Callback = function(value)
		_G.autoHealDelay = value
	end
})

_G.BattleTab:AddButton({
	Name = "Heal Once",
	Icon = "heart-pulse",
	Callback = function()
		local ok, reason = _G.F.runAutoHealOnce(true)
		_G.OrionLib:MakeNotification({
			Name = "Auto Heal",
			Content = ok and "Heal action sent." or tostring(reason),
			Time = ok and 3 or 5
		})
	end
})

_G.BattleTab:AddSection({ Name = "Battle Speed" })

_G.configUi.fastForwardToggle = _G.BattleTab:AddToggle({
	Name = "Fast Battle",
	Default = _G.fastForwardEnabled,
	Color = Color3.fromRGB(255, 170, 70),
	Callback = function(value)
		_G.F.setFastBattleEnabled(value)
	end
})

_G.BattleTab:AddSection({ Name = "Trainer Prompts" })

_G.configUi.skipDialogueToggle = _G.BattleTab:AddToggle({
	Name = "Skip Dialogue",
	Default = _G.skipDialogueEnabled,
	Color = Color3.fromRGB(90, 200, 255),
	Callback = function(value)
		_G.skipDialogueEnabled = value and true or false
		_G.F.syncJackMiscSettings()
		_G.F.installJackStyleGameplayHooks()
	end
})

_G.configUi.denyReassignMoveToggle = _G.BattleTab:AddToggle({
	Name = "Deny Reassign Move",
	Default = _G.denyReassignMoveEnabled,
	Color = Color3.fromRGB(255, 180, 80),
	Callback = function(value)
		_G.denyReassignMoveEnabled = value and true or false
		_G.F.syncJackMiscSettings()
		_G.F.installJackStyleGameplayHooks()
	end
})

_G.configUi.denySwitchRequestToggle = _G.BattleTab:AddToggle({
	Name = "Deny Switch Request",
	Default = _G.denySwitchRequestEnabled,
	Color = Color3.fromRGB(255, 140, 140),
	Callback = function(value)
		_G.denySwitchRequestEnabled = value and true or false
		_G.F.syncJackMiscSettings()
		_G.F.installJackStyleGameplayHooks()
	end
})

_G.configUi.disableShowProgressToggle = _G.BattleTab:AddToggle({
	Name = "Disable Show Progress",
	Default = _G.disableShowProgressEnabled,
	Color = Color3.fromRGB(120, 220, 170),
	Callback = function(value)
		_G.disableShowProgressEnabled = value and true or false
		_G.F.syncJackMiscSettings()
		_G.F.installJackStyleGameplayHooks()
	end
})

_G.configUi.ignoreNpcBattleToggle = _G.BattleTab:AddToggle({
	Name = "Ignore NPC Battle",
	Default = _G.ignoreNpcBattleEnabled,
	Color = Color3.fromRGB(255, 150, 90),
	Callback = function(value)
		_G.ignoreNpcBattleEnabled = value and true or false
		_G.jackIgnoreNpcSession = {}
		_G.F.installJackStyleGameplayHooks()
	end
})

_G.BattleTab:AddSection({ Name = "Utilities" })

_G.BattleTab:AddButton({
	Name = "End Battle",
	Icon = "x",
	Callback = function()
		local ok, reason = _G.F.endCurrentBattleForce()
		_G.OrionLib:MakeNotification({
			Name = "End Battle",
			Content = ok and "Battle force-ended." or tostring(reason),
			Time = ok and 3 or 5
		})
	end
})

_G.BattleTab:AddButton({
	Name = "Skip Battle Theater Puzzles",
	Icon = "skip-forward",
	Callback = function()
		local ok, reason = _G.F.skipBattleTheaterPuzzles()
		_G.OrionLib:MakeNotification({
			Name = "Battle Theater",
			Content = ok and "Puzzle skip action sent." or tostring(reason),
			Time = ok and 3 or 5
		})
	end
})


_G.RallyTab:AddSection({ Name = "Rally" })

_G.configUi.autoRallyToggle = _G.RallyTab:AddToggle({
	Name = "Auto Rally",
	Default = _G.autoRallyEnabled,
	Color = Color3.fromRGB(90, 220, 145),
	Callback = function(value)
		_G.autoRallyEnabled = value
		if value then
			_G.lastRallyActionText = "Auto Rally enabled."
			_G.F.refreshRallyUI()
		end
	end
})

_G.rallyStatsLabel = _G.RallyTab:AddLabel("Kept: 0 | Released: 0")
_G.rallyStatusLabel = _G.RallyTab:AddLabel("Idle")

_G.configUi.keepGleamingToggle = _G.RallyTab:AddToggle({ Name = "Keep Gleaming", Default = _G.keepGleaming, Color = Color3.fromRGB(255, 215, 90), Callback = function(v) _G.keepGleaming = v end })
_G.configUi.keepSecretAbilityToggle = _G.RallyTab:AddToggle({ Name = "Keep Secret Ability", Default = _G.keepSecretAbility, Color = Color3.fromRGB(149, 88, 204), Callback = function(v) _G.keepSecretAbility = v end })
_G.configUi.keepAllToggle = _G.RallyTab:AddToggle({ Name = "Keep All (no releasing)", Default = _G.keepAll, Color = Color3.fromRGB(255, 120, 120), Callback = function(v) _G.keepAll = v end })

_G.RallyTab:AddTextbox({
	Name = "Always Keep (names, comma-separated)",
	Default = _G.alwaysKeepText,
	TextDisappear = false,
	Callback = function(value) _G.F.setAlwaysKeepList(value) end
})

_G.configUi.rallyDelay = _G.RallyTab:AddSlider({
	Name = "Rally Delay",
	Min = 0.5, Max = 10, Increment = 0.5,
	Default = _G.rallyDelay, ValueName = "s",
	Callback = function(value) _G.rallyDelay = value end
})

_G.RallyTab:AddButton({
	Name = "Handle Rally Now",
	Icon = "zap",
	Callback = function()
		local didWork, reason = _G.F.runAutoRally()
		if not didWork and reason then
			_G.OrionLib:MakeNotification({ Name = "Auto Rally", Content = reason, Time = 4 })
		end
	end
})

_G.RallyTab:AddButton({
	Name = "Open Rally Menu",
	Icon = "menu",
	Callback = function()
		local opened, reason = _G.F.openRallyMenu()
		if not opened and reason then
			_G.OrionLib:MakeNotification({ Name = "Rally", Content = reason, Time = 4 })
		end
	end
})

_G.RallyTab:AddButton({
	Name = "Open Rally Team",
	Icon = "users",
	Callback = function()
		local opened, reason = _G.F.openRallyTeam()
		if not opened and reason then
			_G.OrionLib:MakeNotification({ Name = "Rally Team", Content = reason, Time = 4 })
		end
	end
})

_G.RallyTab:AddButton({
	Name = "Open Rallied",
	Icon = "package-check",
	Callback = function()
		local opened, reason = _G.F.openRallied()
		if not opened and reason then
			_G.OrionLib:MakeNotification({ Name = "Rallied", Content = reason, Time = 4 })
		end
	end
})

_G.RallyTab:AddButton({
	Name = "Reset Rally Stats",
	Icon = "refresh-cw",
	Callback = function()
		_G.rallyKept = 0
		_G.rallyReleased = 0
		_G.lastRallyActionText = "Stats reset."
		_G.F.refreshRallyUI()
	end
})


local informationBoonarySection = _G.StorageTab:AddSection({ Name = "Boonary Storage" })
_G.autoBoonaryStatusLabel = informationBoonarySection:AddLabel("Idle")

_G.configUi.autoBoonaryToggle = informationBoonarySection:AddToggle({
	Name = "Auto Boonary at Tix Cap",
	Default = _G.autoBoonaryEnabled,
	Color = Color3.fromRGB(255, 190, 85),
	Callback = function(value)
		_G.F.setAutoBoonaryEnabled(value)
	end
})

informationBoonarySection:AddTextbox({
	Name = "Tix Threshold",
	Default = tostring(_G.autoBoonaryTixThreshold),
	TextDisappear = false,
	Callback = function(value)
		local parsed = tonumber((tostring(value or ""):gsub(",", "")))
		if parsed and parsed > 0 then
			_G.autoBoonaryTixThreshold = math.floor(parsed)
		else
			_G.OrionLib:MakeNotification({ Name = "Auto Boonary", Content = "Type a numeric Tix threshold.", Time = 4 })
		end
	end
})

informationBoonarySection:AddTextbox({
	Name = "PC Group",
	Default = tostring(_G.autoBoonaryGroup),
	TextDisappear = false,
	Callback = function(value)
		local parsed = tonumber(value)
		if parsed and parsed > 0 then
			_G.autoBoonaryGroup = math.floor(parsed)
		else
			_G.OrionLib:MakeNotification({ Name = "Auto Boonary", Content = "Type a numeric PC group.", Time = 4 })
		end
	end
})

informationBoonarySection:AddButton({
	Name = "Max Buy Boonary",
	Icon = "shopping-cart",
	Callback = function()
		task.spawn(function()
			local ok, reason = _G.F.purchaseMaxArcadeBoonarys()
			if ok then
				_G.OrionLib:MakeNotification({ Name = "Max Buy Boonary", Content = "Purchase succeeded.", Time = 4 })
			else
				_G.OrionLib:MakeNotification({ Name = "Max Buy Boonary", Content = tostring(reason), Time = 6 })
			end
		end)
	end
})

informationBoonarySection:AddButton({
	Name = "Run Boonary Cycle Now",
	Icon = "play",
	Callback = function()
		task.spawn(function()
			local ok, reason = _G.F.runAutoBoonaryCycle()
			if not ok and reason then
				_G.OrionLib:MakeNotification({ Name = "Auto Boonary", Content = tostring(reason), Time = 5 })
			end
		end)
	end
})

informationBoonarySection:AddButton({
	Name = "Release Non-Gleam Boonarys Now",
	Icon = "trash",
	Callback = function()
		task.spawn(function()
			local callOk, ok, reason = pcall(function()
				return _G.F.cleanBoonaryPcBoxes(false)
			end)
			if not callOk then
				_G.OrionLib:MakeNotification({ Name = "Boonary Sweep", Content = tostring(ok), Time = 6 })
				return
			end
			_G.OrionLib:MakeNotification({ Name = "Boonary Sweep", Content = tostring(reason), Time = 6 })
		end)
	end
})

informationBoonarySection:AddButton({
	Name = "Print Boonary Preview",
	Icon = "terminal",
	Callback = function()
		task.spawn(function()
			local callOk, ok, reason = pcall(function()
				-- Dry-run the direct PC session sweep first; fall back to the
				-- legacy heuristic preview if no session is available.
				local sweepOk, sweepReason = _G.F.cleanBoonaryPcBoxes(true)
				if sweepOk then
					return sweepOk, sweepReason
				end
				print("[Auto Boonary Preview] PC session unavailable (" .. tostring(sweepReason) .. "); using legacy scan.")
				return _G.F.printBoonaryStoragePreview(_G.autoBoonaryGroup)
			end)

			if not callOk then
				print("[Auto Boonary Preview] ERROR: " .. tostring(ok))
				_G.F.setAutoBoonaryStatus("Preview error: " .. tostring(ok))
				_G.OrionLib:MakeNotification({ Name = "Auto Boonary Preview", Content = tostring(ok), Time = 5 })
				return
			end

			if not ok and reason then
				_G.OrionLib:MakeNotification({ Name = "Auto Boonary Preview", Content = tostring(reason), Time = 5 })
			end
		end)
	end
})


local collectionUtilitySection = _G.StorageTab:AddSection({ Name = "Party Items & PC" })

_G.configUi.activeRepellentToggle = collectionUtilitySection:AddToggle({
	Name = "Active Repellent",
	Default = _G.activeRepellentEnabled,
	Color = Color3.fromRGB(255, 205, 90),
	Callback = function(value)
		_G.activeRepellentEnabled = value and true or false
		if _G.activeRepellentEnabled then
			local ok, reason = _G.F.useActiveRepellentOnce(true)
			pcall(function()
				_G.OrionLib:MakeNotification({
					Name = "Active Repellent",
					Content = ok and tostring(reason or "Repellent enabled.") or tostring(reason),
					Time = ok and 3 or 5,
				})
			end)
			if not ok then
				warn("[Active Repellent] " .. tostring(reason))
			end
		end
	end
})

_G.configUi.activeRepellentDelay = collectionUtilitySection:AddSlider({
	Name = "Repellent Refresh",
	Min = 10,
	Max = 120,
	Increment = 5,
	Default = _G.activeRepellentDelay,
	ValueName = "s",
	Callback = function(value)
		_G.activeRepellentDelay = value
	end
})

collectionUtilitySection:AddButton({
	Name = "Use Repellent Once",
	Icon = "spray-can",
	Callback = function()
		local ok, reason = _G.F.useActiveRepellentOnce(true)
		_G.OrionLib:MakeNotification({
			Name = "Active Repellent",
			Content = ok and tostring(reason or "Repellent action sent.") or tostring(reason),
			Time = ok and 3 or 5
		})
	end
})

collectionUtilitySection:AddButton({
	Name = "Open PC",
	Icon = "archive",
	Callback = function()
		local ok, reason = _G.F.openPcMenu()
		if not ok then
			_G.OrionLib:MakeNotification({ Name = "Open PC", Content = tostring(reason), Time = 5 })
		end
	end
})


_G.EncountersTab:AddSection({ Name = "Fishing" })
do
	local fishing = _G.FishingAutomation or (getgenv and getgenv().FishingAutomation)
	if not fishing then
		error("[LLSPLOIT] FishingAutomation was not exported by modules/core.lua")
	end
	fishing:attachUi(_G.FishingTab)
end


_G.EncountersTab:AddSection({ Name = "Goppie Tracking" })

_G.goppieFormesTextbox = _G.FishingTab:AddTextbox({
	Name = "Goppie Formes",
	Default = _G.F.getGoppieFormesText(),
	TextDisappear = false,
	Callback = function(value)
		_G.F.setGoppieFormesFromText(value)
	end
})

task.defer(function()
	_G.F.syncGoppieFormesTextbox()
end)


-- Status & scan --------------------------------------------------------------
local fossilStatusSection = _G.FossilReviveTab:AddSection({ Name = "Status" })

_G.fossilStatusLabel = fossilStatusSection:AddLabel("Status: Idle")
_G.fossilStatsLabel = fossilStatusSection:AddLabel("Batches: 0 | Revived: 0 | Last Queued: 0")
_G.fossilMachineLabel = fossilStatusSection:AddLabel("Petrolith Table: searching...")
_G.fossilScanLabel = fossilStatusSection:AddLabel("Bag: not scanned yet")

fossilStatusSection:AddButton({
	Name = "Scan Fossil Bag",
	Icon = "search",
	Callback = function()
		local ok, reason = _G.F.scanFossilBag()
		if not ok and reason then
			_G.OrionLib:MakeNotification({
				Name = "Fossil Scan",
				Content = reason,
				Time = 5,
			})
		end
	end,
})

-- Automation & actions -------------------------------------------------------
local fossilRunSection = _G.FossilReviveTab:AddSection({ Name = "Automation & Actions" })

_G.configUi.autoFossilToggle = fossilRunSection:AddToggle({
	Name = "Auto Fossil",
	Default = _G.autoFossilEnabled,
	Color = Color3.fromRGB(80, 185, 255),
	Callback = function(value)
		_G.autoFossilEnabled = value
		_G.nextAutoFossilAt = 0

		if value then
			_G.F.setFossilStatus("Auto Fossil enabled.")
		else
			_G.F.setFossilStatus("Auto Fossil disabled.")
		end
	end
})

_G.configUi.autoFossilDelay = fossilRunSection:AddSlider({
	Name = "Fossil Loop Delay",
	Min = 1,
	Max = 30,
	Increment = 0.5,
	Default = _G.autoFossilDelay,
	ValueName = "s",
	Callback = function(value)
		_G.autoFossilDelay = value
	end
})

fossilRunSection:AddButton({
	Name = "Revive Fossils Now",
	Icon = "zap",
	Callback = function()
		local success, reason = _G.F.runAutoFossil()
		if not success and reason then
			_G.OrionLib:MakeNotification({
				Name = "Auto Fossil",
				Content = reason,
				Time = 5,
			})
		end
	end
})

fossilRunSection:AddButton({
	Name = "Clean Fossil PC Now",
	Icon = "trash-2",
	Callback = function()
		local ok, reason = _G.F.cleanFossilRevivalPcBoxes(false)
		_G.OrionLib:MakeNotification({
			Name = "Fossil Cleanup",
			Content = ok and tostring(reason) or tostring(reason),
			Time = ok and 6 or 5,
		})
	end,
})

fossilRunSection:AddButton({
	Name = "Reset Fossil Stats",
	Icon = "refresh-cw",
	Callback = function()
		_G.totalFossilBatches = 0
		_G.totalFossilRevived = 0
		_G.lastFossilQueuedCount = 0
		_G.F.refreshFossilStats()
		_G.F.setFossilStatus("Stats reset.")
	end
})

-- Revive targets -------------------------------------------------------------
local fossilTargetSection = _G.FossilReviveTab:AddSection({ Name = "Revive Targets" })

_G.fossilTargetDropdown = fossilTargetSection:AddDropdown({
	Name = "Auto Revive Target",
	Default = _G.autoFossilReviveTarget,
	Options = _G.F.buildFossilTargetDropdownOptions(),
	Callback = function(value)
		if _G.jackSyncingDropdownUi then
			return
		end
		_G.autoFossilReviveTarget = value
	end,
})
_G.configUi.fossilTargetDropdown = _G.fossilTargetDropdown

fossilTargetSection:AddLabel("Pick one Loomian above to revive only that one, or leave it on \"All Loomians\" and use the toggles below to choose which fossils to revive.")

_G.F.getPetrolithReviveCatalog()
_G.configUi.fossilTargetToggles = _G.configUi.fossilTargetToggles or {}
for _, entry in ipairs(_G.F.getPetrolithReviveCatalog()) do
	_G.configUi.fossilTargetToggles[entry.id] = fossilTargetSection:AddToggle({
		Name = "Revive " .. entry.loomian .. " (" .. entry.fossil .. ")",
		Default = _G.autoFossilTargetEnabled[entry.id] ~= false,
		Color = Color3.fromRGB(120, 200, 255),
		Callback = function(value)
			_G.autoFossilTargetEnabled[entry.id] = value and true or false
		end,
	})
end

-- Revive options -------------------------------------------------------------
local fossilOptionsSection = _G.FossilReviveTab:AddSection({ Name = "Revive Options" })

_G.configUi.autoFossilAutoReleaseToggle = fossilOptionsSection:AddToggle({
	Name = "Auto-Release Non Special",
	Default = _G.autoFossilAutoRelease,
	Color = Color3.fromRGB(255, 120, 120),
	Callback = function(value)
		_G.autoFossilAutoRelease = value and true or false
	end,
})

_G.configUi.autoFossilKeepSecretAbilityToggle = fossilOptionsSection:AddToggle({
	Name = "Keep Secret Ability",
	Default = _G.autoFossilKeepSecretAbility,
	Color = Color3.fromRGB(149, 88, 204),
	Callback = function(value)
		_G.autoFossilKeepSecretAbility = value and true or false
	end,
})

fossilOptionsSection:AddLabel("Keeps Gleaming and Gamma automatically. Release sweep follows Boonary-style PC cleanup.")

_G.F.refreshFossilStats()
_G.F.refreshPetrolithTableLabel()
_G.F.syncFossilTargetDropdown()

task.defer(function()
	for _ = 1, 20 do
		if type(_G.F) == "table" and _G.F.ensureP() then
			pcall(_G.F.scanFossilBag)
			break
		end
		task.wait(0.5)
	end
end)


_G.ArcadeTab:AddSection({ Name = "Disc Drop" })
do
	local arcade = _G.ArcadeAutomation or (getgenv and getgenv().ArcadeAutomation)
	if not arcade then
		error("[LLSPLOIT] ArcadeAutomation was not exported by modules/arcade.lua")
	end
	arcade:attachUi(_G.MinigamesTab)
end


_G.SettingsTab:AddSection({ Name = "Shops" })

for _, shopInfo in ipairs(_G.SHOP_DEFINITIONS) do
	local shopId = shopInfo.Id
	local shopLabel = shopInfo.Label

	_G.ShopTab:AddButton({
		Name = shopLabel,
		Icon = "shopping-bag",
		Callback = function()
			local opened, reason = _G.F.openShop(shopId, shopLabel)
			if not opened and reason then
				_G.OrionLib:MakeNotification({
					Name = "Shop",
					Content = tostring(reason),
					Time = 4,
				})
			end
		end
	})
end

-- Build each Settings element in isolation. If any one element's construction
-- throws at runtime (e.g. an OrionLib event-hookup hitting a thread capability
-- error), the failure must stay contained to that element and never abort the
-- rest of the tab -- otherwise the essential Config/Unload controls below get
-- silently dropped along with it.
local function settingsBuild(label, builder)
	local ok, err = pcall(builder)
	if not ok then
		warn("[LLSPLOIT] Settings element '" .. tostring(label) .. "' failed to build: " .. tostring(err))
	end
end

local settingsMovementSection
settingsBuild("Movement section", function()
	settingsMovementSection = _G.SettingsTab:AddSection({ Name = "Movement Utilities" })
end)

if settingsMovementSection then
	settingsBuild("Ctrl + Click Teleport", function()
		_G.configUi.ctrlClickTpToggle = settingsMovementSection:AddToggle({
			Name = "Ctrl + Click Teleport",
			Default = _G.ctrlClickTpEnabled,
			Color = Color3.fromRGB(120, 200, 255),
			Callback = function(value)
				_G.F.setCtrlClickTpEnabled(value)
			end
		})
	end)

	settingsBuild("No Unstuck Cooldown", function()
		_G.configUi.noUnstuckCooldownToggle = settingsMovementSection:AddToggle({
			Name = "No Unstuck Cooldown",
			Default = _G.noUnstuckCooldownEnabled,
			Color = Color3.fromRGB(255, 190, 90),
			Callback = function(value)
				_G.noUnstuckCooldownEnabled = value and true or false
				if _G.noUnstuckCooldownEnabled then
					_G.F.applyNoUnstuckCooldown()
				else
					_G.F.restoreJackStyleGameplayHooks()
				end
			end
		})
	end)
end

local settingsGeneralSection
settingsBuild("General section", function()
	settingsGeneralSection = _G.SettingsTab:AddSection({ Name = "Safety" })
end)

if settingsGeneralSection then
	settingsBuild("Anti AFK", function()
		_G.configUi.antiAfkToggle = settingsGeneralSection:AddToggle({
			Name = "Anti AFK",
			Default = _G.antiAfkEnabled,
			Color = Color3.fromRGB(120, 255, 160),
			Callback = function(value)
				_G.F.setAntiAfkEnabled(value)
			end
		})
	end)

	-- Deliberately not saved to config: silently restoring a no-save state on the
	-- next injection could cost the user hours of progress.
	settingsBuild("Disable Saving", function()
		settingsGeneralSection:AddToggle({
			Name = "Disable Saving",
			Default = _G.savingDisabled,
			Color = Color3.fromRGB(255, 150, 120),
			Callback = function(value)
				local ok, reason = _G.F.setSavingDisabled(value)
				if not ok and reason then
					pcall(function()
						_G.OrionLib:MakeNotification({
							Name = "Disable Saving",
							Content = reason,
							Time = 4
						})
					end)
				end
			end
		})
	end)
end

local settingsAvatarSection
settingsBuild("Local Avatar section", function()
	settingsAvatarSection = _G.SettingsTab:AddSection({ Name = "Local Avatar" })
end)

if settingsAvatarSection then
	settingsBuild("Local Avatar toggle", function()
		_G.configUi.localAvatarToggle = settingsAvatarSection:AddToggle({
			Name = "Avatar Swap",
			Default = _G.localAvatarEnabled,
			Color = Color3.fromRGB(160, 200, 255),
			Callback = function(value)
				local ok, reason = _G.F.setLocalAvatarEnabled(value)
				if value and ok then
					pcall(function()
						_G.OrionLib:MakeNotification({
							Name = "Avatar Swap",
							Content = "Applied avatar " .. tostring(_G.localAvatarUserId or reason),
							Time = 3
						})
					end)
				elseif not ok and reason then
					pcall(function()
						_G.OrionLib:MakeNotification({
							Name = "Avatar Swap",
							Content = tostring(reason),
							Time = 4
						})
					end)
				end
			end
		})
	end)

	settingsBuild("Local Avatar user id", function()
		settingsAvatarSection:AddTextbox({
			Name = "Avatar UserId (optional)",
			Default = _G.localAvatarUserId and tostring(_G.localAvatarUserId) or "",
			TextDisappear = false,
			Callback = function(value)
				local text = string.gsub(tostring(value or ""), "^%s*(.-)%s*$", "%1")
				local id = tonumber(text)
				_G.localAvatarUserId = (id and id > 0) and id or nil
				if _G.localAvatarEnabled and _G.localAvatarUserId then
					pcall(_G.F.applyLocalOnlyAvatar, _G.localAvatarUserId)
				end
			end
		})
	end)

	settingsBuild("Reroll Local Avatar", function()
		settingsAvatarSection:AddButton({
			Name = "Reroll Avatar",
			Icon = "shuffle",
			Callback = function()
				local ok, result = _G.F.rerollLocalOnlyAvatar()
				pcall(function()
					_G.OrionLib:MakeNotification({
						Name = "Avatar Swap",
						Content = ok and ("Applied " .. tostring(result)) or tostring(result),
						Time = 3
					})
				end)
			end
		})
	end)
end

local settingsServerSection
settingsBuild("Server section", function()
	settingsServerSection = _G.SettingsTab:AddSection({ Name = "Server Hop" })
end)

if settingsServerSection then
	settingsBuild("Rejoin", function()
		settingsServerSection:AddButton({
			Name = "Rejoin",
			Icon = "refresh-cw",
			Callback = function()
				local ok, reason = _G.F.rejoinServer()
				if not ok and reason then
					_G.OrionLib:MakeNotification({ Name = "Rejoin", Content = tostring(reason), Time = 5 })
				end
			end
		})
	end)

	settingsBuild("Switch Server", function()
		settingsServerSection:AddButton({
			Name = "Switch Server",
			Icon = "shuffle",
			Callback = function()
				local ok, reason = _G.F.switchServer(false)
				if not ok and reason then
					_G.OrionLib:MakeNotification({ Name = "Switch Server", Content = tostring(reason), Time = 5 })
				end
			end
		})
	end)

	settingsBuild("Find Most Empty Server", function()
		settingsServerSection:AddButton({
			Name = "Find Most Empty Server",
			Icon = "users-round",
			Callback = function()
				local ok, reason = _G.F.switchServer(true)
				if not ok and reason then
					_G.OrionLib:MakeNotification({ Name = "Find Server", Content = tostring(reason), Time = 5 })
				end
			end
		})
	end)
end

settingsBuild("Config section", function()
	_G.SettingsTab:AddSection({ Name = "Config Profiles" })
end)

settingsBuild("Config Name", function()
	_G.SettingsTab:AddTextbox({
		Name = "Config Name",
		Default = _G.configProfileName,
		TextDisappear = false,
		Callback = function(value)
			_G.configProfileName = _G.F.sanitizeConfigName(value)
		end
	})
end)

settingsBuild("Save Config", function()
	_G.SettingsTab:AddButton({
		Name = "Save Config",
		Icon = "save",
		Callback = function()
			local snapshot = _G.F.collectConfigSnapshot()
			snapshot.profile = _G.configProfileName
			local fileName = _G.F.sanitizeConfigName(_G.configProfileName) .. ".json"
			_G.F.saveConfigToFile(fileName, snapshot, false)
			_G.F.saveConfigToFile(_G.CONFIG_AUTOSAVE_FILE, snapshot, true)
		end
	})
end)

settingsBuild("Load Config", function()
	_G.SettingsTab:AddButton({
		Name = "Load Config",
		Icon = "folder-open",
		Callback = function()
			local fileName = _G.F.sanitizeConfigName(_G.configProfileName) .. ".json"
			_G.F.loadConfigFromFile(fileName, false)
		end
	})
end)

settingsBuild("Unload Script", function()
	_G.SettingsTab:AddButton({
		Name = "Unload Script",
		Icon = "power",
		Callback = function()
			_G.uiAlive = false
			_G.F.disableAllFeatures()

			task.defer(function()
				pcall(function()
					_G.OrionLib:Destroy()
				end)
			end)
		end
	})
end)

_G.startupConfigApplied = false
if _G.startupConfig then
	-- Never auto-enable Auto Encounter from autosave on script execute.
	_G.startupConfig.autoEncounterEnabled = nil
	local ok, err = pcall(function()
		_G.F.applyConfigSnapshot(_G.startupConfig, true)
	end)
	if ok then
		_G.startupConfigApplied = true
	else
		warn("[LLSPLOIT] Startup config failed: " .. tostring(err))
	end
end

task.spawn(function()
	while _G.uiAlive do
		_G.F.refreshPetrolithTableLabel()
		task.wait(2)
	end
end)

task.spawn(function()
	local lastNoticeAt = 0

	while _G.uiAlive do
		if _G.autoDiscDropEnabled then
			local didWork, reason = _G.ArcadeAutomation:runAutoDiscDrop()

			if not didWork and reason and os.clock() - lastNoticeAt >= 8 then
				lastNoticeAt = os.clock()
				warn("[Auto Disc Drop] " .. tostring(reason))

				pcall(function()
					_G.OrionLib:MakeNotification({
						Name = "Auto Disc Drop",
						Content = reason,
						Time = 4
					})
				end)
			end

			task.wait(0.25)
		else
			task.wait(0.2)
		end
	end
end)

task.spawn(function()
	while _G.uiAlive do
		if _G.autoFossilEnabled and not _G.fossilBusy and os.clock() >= _G.nextAutoFossilAt then
			local success, reason = _G.F.runAutoFossil()
			_G.nextAutoFossilAt = os.clock() + _G.autoFossilDelay

			if not success and reason and reason ~= "No complete Petrolith sets found." then
				_G.OrionLib:MakeNotification({
					Name = "Auto Fossil",
					Content = reason,
					Time = 5,
				})
			end
		end

		task.wait(0.15)
	end
end)



task.spawn(function()
	while _G.uiAlive do
		if _G.CatchAutomation and _G.CatchAutomation:isEnabled() then
			pcall(function()
				_G.CatchAutomation:serviceBattle()
			end)
			task.wait(0.06)
		else
			task.wait(0.2)
		end
	end
end)

task.spawn(function()
	while _G.uiAlive do
		if _G.CatchAutomation and _G.CatchAutomation:isEnabled() then
			pcall(function()
				_G.CatchAutomation:serviceNicknamePrompt()
			end)
			task.wait(0.12)
		else
			task.wait(0.2)
		end
	end
end)

task.spawn(function()
	while _G.uiAlive do
		pcall(function()
			_G.F.refreshInformationLabels()
		end)
		task.wait(2)
	end
end)

task.spawn(function()
	while _G.uiAlive do
		if _G.autoBoonaryEnabled and not _G.autoBoonaryBusy and not _G.autoBoonaryTriggered then
			local tix = _G.F.getCurrentTixCount()
			if tix and tix >= (tonumber(_G.autoBoonaryTixThreshold) or 999999) then
				_G.autoBoonaryTriggered = true
				_G.F.setAutoBoonaryStatus("Tix threshold reached: " .. _G.F.formatInfoValue(tix))

				task.spawn(function()
					local ok, reason = _G.F.runAutoBoonaryCycle()
					if not ok and reason then
						_G.OrionLib:MakeNotification({
							Name = "Auto Boonary",
							Content = tostring(reason),
							Time = 5,
						})
						_G.autoBoonaryTriggered = false
					end
				end)
			else
				_G.F.setAutoBoonaryStatus("Waiting for " .. _G.F.formatInfoValue(_G.autoBoonaryTixThreshold) .. " Tix.")
			end
		end

		task.wait(2)
	end
end)

_G.UserInputService.WindowFocused:Connect(function() _G.windowFocused = true end)
_G.UserInputService.WindowFocusReleased:Connect(function() _G.windowFocused = false end)
task.spawn(function()
	while _G.uiAlive do
		if _G.StaticAutomation and _G.StaticAutomation:isAutomationActive() then
			pcall(function()
				_G.StaticAutomation:serviceBattle()
			end)
			task.wait(0.06)
		else
			task.wait(0.2)
		end
	end
end)

task.spawn(function()
	local lastNoticeAt = 0
	local quietReasons = {
		["Waiting for static encounter data."] = true,
		["Waiting for battle input."] = true,
		["Waiting for the static prompt."] = true,
		["Waiting for the chunk to load."] = true,
		["Battle is not ready for Run."] = true,
		["Cannot interact right now."] = true
	}

	while _G.uiAlive do
		if _G.StaticAutomation and _G.StaticAutomation:isAutomationActive() then
			local didWork, reason
			local ok, err = pcall(function()
				didWork, reason = _G.StaticAutomation:runCycle()
			end)

			if not ok then
				warn("[Auto Static] " .. tostring(err))
			elseif not didWork and reason and not quietReasons[reason] and os.clock() - lastNoticeAt >= 8 then
				lastNoticeAt = os.clock()
				warn("[Auto Static] " .. tostring(reason))

				pcall(function()
					_G.OrionLib:MakeNotification({
						Name = "Auto Static",
						Content = reason,
						Time = 4
					})
				end)
			end

			task.wait(_G.windowFocused and 0.12 or 0.2)
		else
			task.wait(0.2)
		end
	end
end)
task.spawn(function()
	local lastHealNoticeAt = 0
	local lastRepellentNoticeAt = 0

	while _G.uiAlive do
		local now = os.clock()

		if _G.autoHealEnabled and now - (_G.lastAutoHealAt or 0) >= (_G.autoHealDelay or 8) then
			_G.lastAutoHealAt = now
			local ok, reason = _G.F.runAutoHealOnce()
			if not ok and reason and now - lastHealNoticeAt >= 12 then
				lastHealNoticeAt = now
				warn("[Auto Heal] " .. tostring(reason))
			end
		end

		if _G.activeRepellentEnabled and now - (_G.lastActiveRepellentAt or 0) >= (_G.activeRepellentDelay or 20) then
			_G.lastActiveRepellentAt = now
			local ok, reason = _G.F.useActiveRepellentOnce(false)
			if not ok and reason and now - lastRepellentNoticeAt >= 20 then
				lastRepellentNoticeAt = now
				warn("[Active Repellent] " .. tostring(reason))
			end
		end

		if _G.skipDialogueEnabled then
			pcall(function()
				_G.F.clickThroughNpcChat()
			end)
		end

		if _G.denyReassignMoveEnabled or _G.denySwitchRequestEnabled or _G.denyNicknameEnabled then
			pcall(function()
				_G.F.servicePromptDenials()
			end)
		end

		if _G.disableShowProgressEnabled then
			pcall(function()
				_G.F.dismissMasteryReport()
			end)
		end

		if _G.noUnstuckCooldownEnabled then
			pcall(function()
				_G.F.applyNoUnstuckCooldown()
			end)
		end

		task.wait(0.2)
	end
end)

task.spawn(function()
	local lastNoticeAt = 0
	local quietReasons = {
		["No rallied Loomians waiting."] = true
	}

	while _G.uiAlive do
		if _G.autoRallyEnabled then
			local didWork, reason
			local ok, err = pcall(function()
				didWork, reason = _G.F.runAutoRally()
			end)

			if not ok then
				warn("[Auto Rally] " .. tostring(err))
			elseif not didWork and reason and not quietReasons[reason] and os.clock() - lastNoticeAt >= 8 then
				lastNoticeAt = os.clock()
				warn("[Auto Rally] " .. tostring(reason))
				pcall(function()
					_G.OrionLib:MakeNotification({
						Name = "Auto Rally",
						Content = reason,
						Time = 4
					})
				end)
			end

			task.wait(_G.rallyDelay)
		else
			task.wait(0.2)
		end
	end
end)

do
	_G.CodexGetEndDelay = function()
		local base = math.max(
			_G.encounterRunDelay or 1.5,
			_G.windowFocused and _G.focusedEndDelay or _G.backgroundEndDelay
		)
		if type(_G.F.isPityTrackingActive) == "function" and _G.F.isPityTrackingActive() then
			return math.max(base, _G.pityRunMinDelay or 1)
		end
		return base
	end

	_G.CodexGetEndRetryDelay = function()
		local base = _G.windowFocused and _G.focusedRunDelay or _G.backgroundRunDelay
		if type(_G.F.isPityTrackingActive) == "function" and _G.F.isPityTrackingActive() then
			return math.max(base, 0.35)
		end
		return base
	end

	_G.CodexTryRunBattle = function(battle, forceSkip)
		if not battle then
			return false
		end

		if _G.F.isFishingBattleStarting(battle) or _G.F.isBattleSetupPending(battle) then
			return false
		end

		if _G.F.hasWildFoeLoaded(battle) and not _G.F.isNormalWildEncounter(battle) then
			return false
		end

		if forceSkip and not (_G.F.isEncounterAutomationActive() or _G.autoRunEnabled) then
			if _G.F.shouldSkipWildEncounterIntro(battle) then
				_G.F.setBattleFastForward(true, battle)
				_G.F.skipEncounterCutscene(battle)
			end
		elseif _G.autoEncounterEnabled or _G.autoCatchEnabled then
			_G.F.clearEncounterFastForward(battle)
		end

		if _G.F.shouldAutoRunFromBattle(battle) then
			local menuReadyAt = _G.F.trackBattleAutoRunDelay(battle)
			if not _G.F.canAutoRunFromBattle(battle, menuReadyAt) then
				return false
			end

			if type(_G.F.refreshPityState) == "function" then
				_G.F.refreshPityState()
			end
			return _G.F.naturalRunFromBattle(battle, false, false)
		end

		-- Auto Encounter without Auto Run: still flee normals after delay,
		-- unless Auto Use Move is fighting for EXP.
		if _G.autoEncounterEnabled
			and not (_G.CatchAutomation and _G.CatchAutomation:shouldCatchBattle(battle))
			and _G.F.isNormalWildEncounter(battle) then
			if _G.autoMoveOneEnabled then
				return _G.F.useMoveOne(battle)
			end

			local menuReadyAt = _G.F.trackBattleAutoRunDelay(battle)
			if not _G.F.canFleeAfterAutoRunDelay(battle, menuReadyAt) then
				return false
			end
			return _G.F.naturalRunFromBattle(battle, false, false)
		end

		return false
	end

	-- Always fight corrupt wilds with move 1 (does not require Auto Use Move).
	task.spawn(function()
		while _G.uiAlive do
			if _G.autoFightCorruptEnabled then
				local battle = _G.F.getCurrentBattle()
				if type(battle) == "table"
					and not battle.ended
					and _G.F.isCorruptWildFoe(battle)
					and (
						_G.F.isBattleIntroComplete(battle)
						or _G.F.isBattleMainMenuOpen()
						or _G.F.isBattleMoveMenuOpen()
						or battle.state == "input"
						or battle.readyForActions == true
					) then
					_G.F.useCorruptBattleMoveOne(battle)
					task.wait(0.15)
				else
					task.wait(0.2)
				end
			else
				task.wait(0.25)
			end
		end
	end)

	task.spawn(function()
		local lastBattleObject = nil
		local lastBattleSeenAt = 0
		local battleFirstSeenAt = 0
		local lastEndAttemptAt = 0

		while _G.uiAlive do
			if _G.F.isAutoRunBattleLoopActive() then
				if type(_G._p) ~= "table" then
					_G._p = _G.F.findP()
				end

				if _G.autoMoveOneEnabled then
					pcall(function()
						_G.F.dismissMasteryReport()
					end)
				end

				if type(_G._p) == "table" then
					local battle = _G.F.getCurrentBattle()
					local now = os.clock()

					if battle then
						local catchManaged = _G.CatchAutomation and _G.CatchAutomation:shouldCatchBattle(battle)
						if _G.F.isFishingGoppieBattle(battle)
							and (_G.autoFishingEnabled or _G.fastForwardEnabled or (_G.autoCatchEnabled and catchManaged)) then
							task.wait(_G.windowFocused and _G.focusedRunDelay or _G.backgroundRunDelay)
						else
							lastBattleSeenAt = now

							if battle ~= lastBattleObject then
								if lastBattleObject then
									_G.F.clearBattleRunTiming(lastBattleObject)
								end
								_G.F.clearBattleRunTiming(battle)
								_G.battleMoveLastRequest.corrupt = nil
								_G.battleMovePendingRequest.corrupt = nil
								lastBattleObject = battle
								battleFirstSeenAt = now
								lastEndAttemptAt = 0
								if type(_G.F.refreshPityState) == "function" then
									_G.F.refreshPityState()
								end
							end

							if _G.autoEncounterEnabled or _G.autoEncounterPausedBattle then
								if battle.pauseAfterSwitchFlag == true
									or _G.F.isBattleSetupPending(battle)
									or _G.F.isBattleDialogueActive() then
									_G.F.enforceWildEncounterIntro(battle)
								else
									_G.F.clearEncounterFastForward(battle)
								end
							end

							local targetMatch = _G.F.isMatchingEncounterTargetFoe(battle)
							local roamerMatch = _G.F.isMatchingRoamingLegendaryFoe(battle)

							if targetMatch then
								_G.F.handleEncounterTargetMatchFound(battle)
							end

							if roamerMatch and not catchManaged then
								_G.F.handleRoamingLegendaryFound(battle)
							end

							local automationPausedForGleaming = false
							if not catchManaged then
								automationPausedForGleaming = _G.F.pauseNaturalRunForSpecialBattle(battle)
							end

							local automationPausedForFoundEncounter = _G.autoEncounterPausedBattle == battle
							local menuReadyAt = _G.F.trackBattleAutoRunDelay(battle)

							if battle.ended == true or battle.done == true then
								_G.F.releaseFinishedBattle(battle)
								_G.F.clearCurrentBattleReference(battle)
								_G.F.clearNaturalRunSpecialPause(battle)
								_G.battleMoveLastRequest.corrupt = nil
								_G.battleMovePendingRequest.corrupt = nil
								lastBattleObject = nil
								battleFirstSeenAt = 0
								lastEndAttemptAt = 0
							elseif _G.F.isCorruptWildFoe(battle)
								and (_G.autoRunEnabled or _G.autoEncounterEnabled or _G.autoFightCorruptEnabled) then
								local retryAge = lastEndAttemptAt == 0 and math.huge or now - lastEndAttemptAt
								local readyToFight = _G.F.isBattleIntroComplete(battle)
									or _G.F.isBattleMainMenuOpen()
									or _G.F.isBattleMoveMenuOpen()
									or battle.state == "input"
									or battle.readyForActions == true

								if readyToFight and retryAge >= math.min(0.12, _G.CodexGetEndRetryDelay()) then
									lastEndAttemptAt = now
									_G.F.useCorruptBattleMoveOne(battle)
								end
							elseif (
									_G.F.shouldAutoRunFromBattle(battle)
									or (_G.autoEncounterEnabled and not _G.autoMoveOneEnabled)
									or (_G.autoEncounterEnabled and _G.autoMoveOneEnabled)
								)
								and not automationPausedForFoundEncounter
								and not targetMatch
								and not roamerMatch
								and not catchManaged
								and not automationPausedForGleaming then
								local retryAge = lastEndAttemptAt == 0 and math.huge or now - lastEndAttemptAt

								if _G.autoMoveOneEnabled
									and _G.autoEncounterEnabled
									and retryAge >= _G.CodexGetEndRetryDelay()
									and _G.F.isBattleIntroComplete(battle) then
									lastEndAttemptAt = now
									_G.F.useMoveOne(battle)
								elseif _G.F.isWrongEncounterTargetFoe(battle)
									and _G.F.canFleeAfterAutoRunDelay(battle, menuReadyAt) then
									lastEndAttemptAt = now
									_G.CodexTryRunBattle(battle, false)
								elseif not _G.F.shouldFilterEncounterTarget()
									and _G.F.canFleeAfterAutoRunDelay(battle, menuReadyAt)
									and retryAge >= _G.CodexGetEndRetryDelay() then
									lastEndAttemptAt = now
									_G.CodexTryRunBattle(battle, false)
								end
							end

							task.wait(_G.windowFocused and _G.focusedRunDelay or _G.backgroundRunDelay)
						end
					else
						local releaseDelay = type(_G.F.getEncounterReleaseDelay) == "function"
							and _G.F.getEncounterReleaseDelay()
							or (_G.encounterReleaseDelay or 1.75)

						if lastBattleObject
							and not _G.F.getCurrentBattle()
							and (now - lastBattleSeenAt) >= releaseDelay then
							if _G.encounterPitySettling and type(_G.F.waitForPitySettle) == "function" then
								_G.F.waitForPitySettle(_G.lastEncounterPitySnapshot, _G.pitySettleTimeout)
								_G.encounterPitySettling = false
								_G.lastEncounterPitySnapshot = nil
							end

							_G.F.releaseFinishedBattle(lastBattleObject)
							_G.F.clearCurrentBattleReference(lastBattleObject)
							_G.F.clearNaturalRunSpecialPause(lastBattleObject)
							_G.F.resumeAutoEncounterAfterPausedBattle(lastBattleObject)
							lastBattleObject = nil
							battleFirstSeenAt = 0
							lastEndAttemptAt = 0
						elseif _G.autoEncounterPausedBattle then
							_G.F.resumeAutoEncounterAfterPausedBattle(nil)
						end

						task.wait(_G.windowFocused and 0.18 or 0.15)
					end
				else
					task.wait(0.2)
				end
			else
				_G.F.clearAllBattleFastForward()
				lastBattleObject = nil
				battleFirstSeenAt = 0
				lastEndAttemptAt = 0
				task.wait(0.2)
			end
		end
	end)
end


task.spawn(function()
	local lastFailure = nil
	local lastFailureNoticeAt = 0

	while _G.uiAlive do
		local trainerSelected = type(_G.jackAutoBattle) == "table"
			and _G.jackAutoBattle.Trainer
			and _G.jackAutoBattle.Trainer ~= "Disabled"

		-- Skip wild grass while a trainer is selected so Farm and Battle don't fight.
		if _G.autoEncounterEnabled and not trainerSelected then
			if _G.encounterPitySettling then
				task.wait(0.25)
			else
				if type(_G._p) ~= "table" then
					_G._p = _G.F.findP()
				end

				local started, reason = _G.F.startAutoEncounter()

				if not started and reason and reason ~= "Battle already active." and reason ~= lastFailure then
					lastFailure = reason

					local now = os.clock()
					if now - lastFailureNoticeAt >= 4 then
						lastFailureNoticeAt = now

						pcall(function()
							_G.OrionLib:MakeNotification({
								Name = "Auto Encounter",
								Content = reason,
								Time = 4
							})
						end)
					end
				elseif started then
					lastFailure = nil
				end

				task.wait(_G.autoEncounterDelay)
			end
		else
			lastFailure = nil
			task.wait(0.2)
		end
	end
end)

task.defer(function()
	if not _G.startupConfigApplied then
		_G.F.syncConfigUiFromVariables()
	end

	local lastEncoded = _G.HttpService:JSONEncode(_G.F.collectConfigSnapshot())
	task.spawn(function()
		while _G.uiAlive do
			task.wait(1)
			if not _G.applyingConfig then
				local ok, encoded = pcall(function()
					return _G.HttpService:JSONEncode(_G.F.collectConfigSnapshot())
				end)
				if ok and encoded ~= lastEncoded then
					lastEncoded = encoded
					_G.F.saveConfigToFile(_G.CONFIG_AUTOSAVE_FILE, nil, true)
				end
			end
		end
	end)
end)


do
	_G.CodexTryRunFishingBattle = function(battle, forceSkip)
		if not battle then
			return false
		end

		if _G.F.isFishingBattleStarting(battle) or _G.F.isBattleSetupPending(battle) then
			return false
		end

		if forceSkip then
			_G.F.setBattleFastForward(true, battle)
			_G.F.skipEncounterCutscene(battle)
		elseif _G.fastForwardEnabled then
			_G.F.setBattleFastForward(true, battle)
			_G.F.applyBattleAnimationFastForward(battle, false)
		end

		if _G.CatchAutomation and _G.CatchAutomation:shouldCatchBattle(battle) then
			return false
		end

		if not _G.autoFishingEnabled then
			return false
		end

		if _G.F.isAutoFishingExcludedGoppieBattle(battle) then
			return _G.F.naturalRunFromBattle(battle)
		end

		local foe = _G.F.getBattleFoeMonster(battle)
		local formeValue = _G.F.getFishingGoppieFormeValue(battle)
		if not _G.F.isGoppieMonster(foe) and not _G.F.isMeaningfulFormeValue(formeValue) then
			return _G.F.naturalRunFromBattle(battle)
		end

		return false
	end

	task.spawn(function()
		local lastBattleObject = nil
		local encounterActive = false
		local lastBattleSeenAt = 0
		local battleFirstSeenAt = 0
		local lastEndAttemptAt = 0
		local lastBattleProgressSignature = nil
		local lastBattleProgressAt = 0

		while _G.uiAlive do
			if _G.autoFishingEnabled or _G.fastForwardEnabled or _G.autoCatchEnabled then
				if type(_G._p) ~= "table" then
					_G._p = _G.F.findP()
				end

				if type(_G._p) == "table" then
					local battle = _G.F.getCurrentBattle()
					local now = os.clock()
					local catchManaged = _G.CatchAutomation and _G.CatchAutomation:shouldCatchBattle(battle)
					local fishingBattle = battle and _G.F.isFishingGoppieBattle(battle)
					local manageFishingBattle = fishingBattle
						and (_G.autoFishingEnabled or _G.fastForwardEnabled or (_G.autoCatchEnabled and catchManaged))

					if battle and manageFishingBattle then
						local runAutomationEnabled = _G.autoFishingEnabled
						lastBattleSeenAt = now
						if _G.autoFishingEnabled then
							_G.F.rememberAutoFishingGoppieFormeFromBattle(battle)
						end

						if battle ~= lastBattleObject then
							lastBattleObject = battle
							battleFirstSeenAt = now
							lastEndAttemptAt = 0
							lastBattleProgressSignature = _G.F.getBattleProgressSignature(battle)
							lastBattleProgressAt = now

							if runAutomationEnabled then
								encounterActive = true
							end
						elseif runAutomationEnabled and not encounterActive then
							encounterActive = true
						end

						local automationPausedForGleaming = _G.F.pauseNaturalRunForSpecialBattle(battle)

						if not catchManaged then
							local battleProgressSignature = _G.F.getBattleProgressSignature(battle)
							if battleProgressSignature ~= lastBattleProgressSignature then
								lastBattleProgressSignature = battleProgressSignature
								lastBattleProgressAt = now
							end

							if not _G.F.isBattleSetupPending(battle)
								and (_G.fastForwardEnabled or _G.autoFishingEnabled)
								and not automationPausedForGleaming then
								_G.F.setBattleFastForward(true, battle)
								_G.F.applyBattleAnimationFastForward(battle, false)

								if now - lastBattleProgressAt >= _G.fastForwardStuckDelay then
									_G.F.nudgeFastForwardBattle(battle)
									lastBattleProgressAt = now
								end
							end

							local battleAge = now - battleFirstSeenAt
							local retryAge = lastEndAttemptAt == 0 and math.huge or now - lastEndAttemptAt

							if _G.autoFishingEnabled and not automationPausedForGleaming
								and battleAge >= _G.CodexGetEndDelay() and retryAge >= _G.CodexGetEndRetryDelay() then
								lastEndAttemptAt = now
								_G.CodexTryRunFishingBattle(battle, false)
							end
						end

						task.wait(_G.windowFocused and _G.focusedRunDelay or _G.backgroundRunDelay)
					else
						if lastBattleObject and (now - lastBattleSeenAt) >= _G.encounterReleaseDelay then
							_G.F.releaseFinishedBattle(lastBattleObject)
							_G.F.clearNaturalRunSpecialPause(lastBattleObject)
							lastBattleObject = nil
							battleFirstSeenAt = 0
							lastEndAttemptAt = 0
							lastBattleProgressSignature = nil
							lastBattleProgressAt = 0
						end

						if encounterActive and (now - lastBattleSeenAt) >= _G.encounterReleaseDelay then
							encounterActive = false
						end

						task.wait(_G.windowFocused and 0.18 or 0.15)
					end
				else
					task.wait(0.2)
				end
			else
				lastBattleObject = nil
				encounterActive = false
				battleFirstSeenAt = 0
				lastEndAttemptAt = 0
				lastBattleProgressSignature = nil
				lastBattleProgressAt = 0
				task.wait(0.2)
			end
		end
	end)
end

task.spawn(function()
	local lastNoticeAt = 0
	local quietReasons = {
		["Battle already active."] = true,
		["Fishing already in progress."] = true,
		["NPC chat is busy."] = true
	}

	while _G.uiAlive do
		if _G.FishingAutomation and _G.FishingAutomation:isEnabled() then
			local didWork, reason

			local ok, err = pcall(function()
				didWork, reason = _G.FishingAutomation:runCycle()
			end)

			if not ok then
				warn("[Auto Fishing] " .. tostring(err))
			elseif not didWork and reason and not quietReasons[reason] and os.clock() - lastNoticeAt >= 8 then
				lastNoticeAt = os.clock()
				warn("[Auto Fishing] " .. tostring(reason))

				pcall(function()
					_G.OrionLib:MakeNotification({
						Name = "Auto Fishing",
						Content = reason,
						Time = 4
					})
				end)
			end

			task.wait(0.25)
		else
			task.wait(0.2)
		end
	end
end)

return { name = "ui" }
