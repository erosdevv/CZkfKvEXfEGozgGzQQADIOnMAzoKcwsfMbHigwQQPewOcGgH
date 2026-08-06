-- globals.lua
-- Services, shared state, and player-list privacy helpers.

_G.Players = game:GetService("Players")
_G.UserInputService = game:GetService("UserInputService")
_G.RunService = game:GetService("RunService")
_G.HttpService = game:GetService("HttpService")

_G.Player = _G.Players.LocalPlayer

local __llsploitHiddenPlayerLists = setmetatable({}, { __mode = "k" })

local function __llsploitDisableCorePlayerList()
	pcall(function()
		game:GetService("StarterGui"):SetCoreGuiEnabled(Enum.CoreGuiType.PlayerList, false)
	end)
end

local function __llsploitIsCustomPlayerListRoot(instance)
	if not instance or not instance:IsA("ScrollingFrame") then
		return false
	end

	return instance:FindFirstChild("MainContainer", true) ~= nil
		and instance:FindFirstChild("BadgeContainer", true) ~= nil
		and instance:FindFirstChild("AvatarIcon", true) ~= nil
end

local function __llsploitIsLocalPlayerIdentityCard(instance)
	if not instance or not instance:IsA("Frame") then
		return false
	end

	if instance:FindFirstAncestorWhichIsA("ScrollingFrame") then
		return false
	end

	local badgeContainer = instance:FindFirstChild("BadgeContainer")
	local mainContainer = instance:FindFirstChild("MainContainer")
	if not badgeContainer or not mainContainer then
		return false
	end

	local nameContainer = mainContainer:FindFirstChild("NameContainer")
	local displayNameContainer = mainContainer:FindFirstChild("DisplayNameContainer")
	if not nameContainer or not displayNameContainer then
		return false
	end

	local localPlayer = _G.Player
	if not localPlayer then
		return false
	end

	local usernameText = tostring(nameContainer.Text or "")
	local displayNameText = tostring(displayNameContainer.Text or "")
	local hasAvatarIcon = mainContainer:FindFirstChild("AvatarIcon") ~= nil

	return hasAvatarIcon and (
		usernameText == localPlayer.Name
		or usernameText == "@" .. localPlayer.Name
		or usernameText == localPlayer.DisplayName
		or displayNameText == localPlayer.DisplayName
	)
end

local function __llsploitIsLocalPlayerTopbarHitbox(instance)
	if not instance or not instance:IsA("ImageButton") then
		return false
	end

	local parent = instance.Parent
	if not parent or string.lower(parent.Name) ~= "topbar" then
		return false
	end

	return instance.BackgroundTransparency >= 1
		and instance.Image == ""
		and instance.Size.X.Offset == 210
		and instance.AnchorPoint.X == 1
end

local function __llsploitHideCustomPlayerList(instance)
	if __llsploitHiddenPlayerLists[instance] then
		return
	end

	__llsploitHiddenPlayerLists[instance] = true

	local function applyHiddenState()
		if not instance.Parent then
			__llsploitHiddenPlayerLists[instance] = nil
			return
		end

		pcall(function()
			instance.Visible = false
			instance.Active = false
			instance.ScrollingEnabled = false
			instance.ScrollBarImageTransparency = 1
			instance.BackgroundTransparency = 1
		end)
	end

	applyHiddenState()

	pcall(function()
		instance:GetPropertyChangedSignal("Visible"):Connect(applyHiddenState)
	end)

	pcall(function()
		instance.AncestryChanged:Connect(function(_, parent)
			if parent then
				applyHiddenState()
			else
				__llsploitHiddenPlayerLists[instance] = nil
			end
		end)
	end)
end

local function __llsploitHideLocalPlayerTopbarInstance(instance)
	if __llsploitHiddenPlayerLists[instance] then
		return
	end

	__llsploitHiddenPlayerLists[instance] = true

	local function applyHiddenState()
		if not instance.Parent then
			__llsploitHiddenPlayerLists[instance] = nil
			return
		end

		pcall(function()
			instance.Visible = false
		end)

		pcall(function()
			instance.Active = false
		end)

		pcall(function()
			instance.AutoButtonColor = false
		end)
	end

	applyHiddenState()

	pcall(function()
		instance:GetPropertyChangedSignal("Visible"):Connect(applyHiddenState)
	end)

	pcall(function()
		instance.AncestryChanged:Connect(function(_, parent)
			if parent then
				applyHiddenState()
			else
				__llsploitHiddenPlayerLists[instance] = nil
			end
		end)
	end)
end

local function __llsploitApplyPlayerPrivacySuppression(instance)
	if __llsploitIsCustomPlayerListRoot(instance) then
		__llsploitHideCustomPlayerList(instance)
		return true
	end

	if __llsploitIsLocalPlayerIdentityCard(instance) or __llsploitIsLocalPlayerTopbarHitbox(instance) then
		__llsploitHideLocalPlayerTopbarInstance(instance)
		return true
	end

	return false
end

local function __llsploitScanForPlayerLists(container)
	if not container then
		return
	end

	for _, descendant in ipairs(container:GetDescendants()) do
		__llsploitApplyPlayerPrivacySuppression(descendant)
	end
end

local function __llsploitTrackPlayerLists(container)
	if not container then
		return
	end

	__llsploitScanForPlayerLists(container)

	pcall(function()
		container.DescendantAdded:Connect(function(descendant)
			__llsploitApplyPlayerPrivacySuppression(descendant)
		end)
	end)
end

_G.F = {}

-- Static
_G.staticInteractTarget = ""
_G.arcerosAutoEnabled = false
_G.beastTarget = "Arceros"

-- Beasts of Judgement soft-reset hunts. The trigger names are search
-- candidates for children of SoftResetTriggers; if none match, the first
-- unclaimed BasePart trigger is used, so new/renamed triggers still work.
_G.BEAST_HUNTS = {
	Arceros = { triggerNames = { "Lava" } },
	Glacadia = { triggerNames = { "Ice", "Glacier", "Frost", "Snow", "Glacadia" } },
}
_G.arcerosStatsLabel = nil
_G.fastForwardEnabled = false
_G.windowFocused = true

-- Movement
_G.ctrlClickTpEnabled = false
_G.ctrlClickTpConnection = nil

-- General
_G.savingDisabled = false

_G.antiAfkEnabled = false
_G.antiAfkIdleConnection = nil
_G.jackCameraEnabled = false
_G.jackCameraLoopId = 0
_G.jackOriginalCameraMaxZoomDistance = nil
_G.jackOriginalCameraOcclusionMode = nil
_G.autoHealEnabled = false
_G.autoHealDelay = 8
_G.activeRepellentEnabled = false
_G.activeRepellentDelay = 20
_G.skipDialogueEnabled = false
_G.denyReassignMoveEnabled = false
_G.denySwitchRequestEnabled = false
_G.denyNicknameEnabled = false
_G.disableShowProgressEnabled = false
_G.autoBattleEnabled = false
_G.noUnstuckCooldownEnabled = false
_G.lastAutoHealAt = 0
_G.lastActiveRepellentAt = 0

-- Trainer
_G.trainerId = 69
_G.autoTrainerEnabled = false
_G.trainerSwitchPromptFirstSeenAt = 0
_G.trainerSwitchPromptLastText = nil
_G.trainerSwitchPromptLastClickAt = 0
_G.trainerSwitchPromptClickedInstance = nil
_G.autoTrainerDelay = 1.5
_G.autoMoveSlot = 1
_G.autoMoveOneEnabled = false
_G.autoMoveOneDelay = 0.2

-- Rally
_G.autoRallyEnabled = false
_G.rallyDelay = 1
_G.rallyKept = 0
_G.rallyReleased = 0
_G.lastRallyActionText = "Idle"
_G.keepGleaming = true
_G.keepSecretAbility = true
_G.keepAll = false
_G.alwaysKeepText = ""
_G.alwaysKeepList = {}
_G.MARK_RELEASE = 1
_G.MARK_KEEP = 2

-- Encounter
_G.autoEncounterEnabled = false
_G.encounterTargetLoomian = ""
_G.autoEncounterDelay = 1.25
_G.focusedRunDelay = 0.12
_G.backgroundRunDelay = 0.35
_G.encounterReleaseDelay = 0.75
_G.focusedEndDelay = 0.15
_G.backgroundEndDelay = 1.25
_G.fastForwardStuckDelay = 4
_G.naturalRunPausedSpecialBattle = nil
_G.encounterTargetStopBattle = nil
_G.autoEncounterPausedBattle = nil
_G.autoEncounterPausedDisplayName = nil
_G.autoEncounterPausedReason = nil

_G.autoCatchEnabled = false
_G.autoCatchDisc = "Adv. Disc"
_G.autoBringEnabled = false
_G.stopOnGleaming = true
_G.stopOnGamma = true
_G.stopOnWisp = true

-- Fishing
_G.autoFishingEnabled = false
_G.autoFishingDelay = 1.75
_G.lastAutoFishingGoppieForme = nil
_G.lastAutoFishingGoppieFormeAt = 0
_G.lastAutoFishingGoppieNotice = nil
_G.goppieCaptureNetworkHooked = false
_G.goppieFormesTextbox = nil

_G.ROAMING_LEGENDARY_STOPS = {
	duskit = true,
	ikazune = true,
	protogon = true,
	mutagon = true,
	cephalops = true,
	wabalisc = true,
	metronette = true,
	nevermare = true,
	akhalos = true,
	gargolem = true,
	elephage = true,
	odoyaga = true,
	arceros = true,
	dakuda = true,
	glacadia = true,
	cosmeleon = true,
}

-- Fossil
_G.TARGET_PETROLITH_INTERACT = "PetrolithTable"
_G.autoFossilEnabled = false
_G.autoFossilDelay = 5
_G.autoFossilAutoRelease = true
_G.autoFossilKeepSecretAbility = true
_G.autoFossilReviveTarget = "All Loomians"
_G.autoFossilTargetEnabled = _G.autoFossilTargetEnabled or {}
_G.fossilScanResults = _G.fossilScanResults or { counts = {}, total = 0, scannedAt = 0 }
_G.fossilScanLabel = nil
_G.fossilTargetDropdown = nil
_G.PETROLITH_REVIVE_CATALOG = {
	{ id = "pyke", kind = 1, speciesId = 99, loomian = "Pyke", fossil = "Marrow" },
	{ id = "zaleo", kind = 2, speciesId = 101, loomian = "Zaleo", fossil = "Fang" },
	{ id = "dobo", kind = 3, speciesId = 103, loomian = "Dobo", fossil = "Feather" },
	{ id = "kyogo", kind = 4, speciesId = 105, loomian = "Kyogo", fossil = "Egg" },
	{ id = "ceratot", kind = 5, speciesId = 121, loomian = "Ceratot", fossil = "Thorn" },
	{ id = "nautling", kind = 8, speciesId = 248, loomian = "Nautling", fossil = "Spiral" },
	{ id = "yutiny", kind = 6, speciesId = 251, loomian = "Yutiny", fossil = "Skull ABC" },
	{ id = "venile", kind = 7, speciesId = 254, loomian = "Venile", fossil = "Skull ABD" },
	{ id = "morphezu", kind = 9, speciesId = 303, loomian = "Morphezu", fossil = "Atmos", lone = true },
	{ id = "behemoroth", kind = 10, speciesId = 304, loomian = "Behemoroth", fossil = "Terris", lone = true },
	{ id = "leviatross", kind = 11, speciesId = 305, loomian = "Leviatross", fossil = "Aquatis", lone = true },
}
_G.totalFossilBatches = 0
_G.totalFossilRevived = 0
_G.lastFossilQueuedCount = 0
_G.lastFossilBatchText = "Idle"
_G.fossilBusy = false
_G.nextAutoFossilAt = 0
-- Tracks whether Auto Fossil has revived anything since its last PC clean, so it
-- can run one "Clean Fossil PC Now" sweep after every selected fossil is revived.
_G.autoFossilRevivedSinceClean = false
_G.fossilStatusLabel = nil
_G.fossilStatsLabel = nil
_G.fossilMachineLabel = nil

-- Arcade
_G.autoDiscDropEnabled = false
_G.discDropStatusLabel = nil
_G.discDropLiveLabel = nil
_G.discDropRecordsLabel = nil
_G.discDropLastScore = 0
_G.discDropHighScore = 0

-- Information / Tix Boonary automation
_G.autoBoonaryEnabled = false
_G.autoBoonaryTixThreshold = 999999
_G.autoBoonaryGroup = 49
_G.autoBoonaryBusy = false
_G.autoBoonaryTriggered = false
_G.autoBoonaryStatusLabel = nil
_G.autoBoonaryScanNodeLimit = 5000

-- Egg Rain
_G.autoEggRainEnabled = false
_G.autoEggRainDelay = 0.25
_G.eggRainStatusLabel = nil
_G.EGG_RAIN_TARGET_NAME = "Part"
_G.EGG_RAIN_TARGET_SIZE = Vector3.new(15, 1, 1)
_G.EGG_RAIN_SIZE_TOLERANCE = 0.05

-- UMV (WallSparkle through-walls visibility)
_G.wallSparkleUmvEnabled = false
_G.wallSparkleUmvCount = 0
_G.wallSparkleUmvStatusLabel = nil
_G.wallSparkleUmvCountLabel = nil
_G.wallSparkleUmvDescendantConnection = nil
_G.WALL_SPARKLE_ORIGINALS = setmetatable({}, { __mode = "k" })
_G.WALL_SPARKLE_CONFIG = {
	TARGET_NAME = "WallSparkle",
	HIGHLIGHT_NAME = "WallSparkle_ThroughWalls_Highlight",
	BILLBOARD_NAME = "WallSparkle_ThroughWalls_Marker",
	TAG_NAME = "WallSparkleThroughWalls",
	FILL_COLOR = Color3.fromRGB(255, 211, 67),
	OUTLINE_COLOR = Color3.fromRGB(0, 255, 255),
	PART_COLOR = Color3.fromRGB(255, 223, 92),
}

-- UMV mining hidden item reveal
_G.umvMiningRevealEnabled = false
_G.umvMiningRevealedCount = 0
_G.umvMiningRevealedCountLabel = nil
_G.umvMiningRevealLoopAlive = false
_G.umvMiningPlayerGuiWatchConnection = nil
_G.umvMiningRevealOriginals = setmetatable({}, { __mode = "k" })
_G.UMV_MINING_ATLAS_ID = "17203205985"

-- UMV remote sparkle miner (see runRemoteSparkleMine below)

-- Shops
_G.SHOP_DEFINITIONS = {
	{ Id = "battle", Label = "Battle Shop" },
	{ Id = "LoomianVoucher", Label = "Loomian Vouchers" },
	{ Id = "mount", Label = "Sawyer's Saddles" },
	{ Id = "halloween", Label = "Dr. Haloine" },
	{ Id = "typediscs", Label = "Disc Crafting" },
	{ Id = "holiday2022", Label = "Mr. Jolly" },
	{ Id = "cake", Label = "Head Chef's Goodies" },
	{ Id = "meteor", Label = "???" },
	{ Id = "fishtrash", Label = "Junk 4 Junk" },
	{ Id = "arcade", Label = "Arcade Prizes" },
	{ Id = "egg", Label = "Cool Colleggtibles" },
	{ Id = "frxSub", Label = "Supplies" },
	{ Id = "jolly3", Label = "Peppermint Swap" },
	{ Id = "tennistag", Label = "Redeem Tickets" },
}

_G.EXCLUDED_FORMES = {
	"pattern",
	'f',
	'm'
}
_G.GOPPIE_FORMES = {}
_G.GOPPIE_FORMES_FILE = "GOPPIE-FORMES.json"
_G.excludedFormes = {}

_G.uiAlive = true

__llsploitDisableCorePlayerList()
__llsploitTrackPlayerLists(game:GetService("CoreGui"))
__llsploitTrackPlayerLists(_G.Player and _G.Player:FindFirstChildOfClass("PlayerGui"))

pcall(function()
	if gethui then
		__llsploitTrackPlayerLists(gethui())
	end
end)

task.spawn(function()
	while _G.uiAlive do
		__llsploitDisableCorePlayerList()
		__llsploitScanForPlayerLists(game:GetService("CoreGui"))
		__llsploitScanForPlayerLists(_G.Player and _G.Player:FindFirstChildOfClass("PlayerGui"))

		pcall(function()
			if gethui then
				__llsploitScanForPlayerLists(gethui())
			end
		end)

		task.wait(0.5)
	end
end)

_G.fastForwardBattles = setmetatable({}, { __mode = "k" })
_G.updateStatus = nil
_G.rallyStatsLabel = nil
_G.rallyStatusLabel = nil
_G.fishingStatusLabel = nil
_G.informationLabels = {}

return { name = "globals" }
