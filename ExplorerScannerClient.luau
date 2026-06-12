--!strict
-- Explorer Scanner + RSpy-style UI  [PRODUCTION BUILD]
-- LocalScript › StarterPlayerScripts
-- Client-only: scans replicated instances, classifies NPCs / Items / Interactables / Vehicles,
-- and shows a searchable explorer UI with live log, inspector, highlight, refresh, and pause.

local Players           = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local StarterGui        = game:GetService("StarterGui")

local LocalPlayer = Players.LocalPlayer
local PlayerGui   = LocalPlayer:WaitForChild("PlayerGui")

-- ─── Config ────────────────────────────────────────────────────────────────
local BATCH_PER_TICK = 40
local SCAN_DELAY     = 0.03
local MAX_ROWS       = 250
local MAX_LOGS       = 220

local TABS: { string } = {
	"Dashboard", "All", "NPC", "Item",
	"Interactable", "Vehicle", "Patterns", "Log", "Unknown",
}

local COLOR: { [string]: Color3 } = {
	Bg      = Color3.fromRGB(18,  18,  22),
	Panel   = Color3.fromRGB(24,  24,  29),
	Panel2  = Color3.fromRGB(30,  30,  36),
	Stroke  = Color3.fromRGB(70,  70,  84),
	Text    = Color3.fromRGB(240, 240, 245),
	Muted   = Color3.fromRGB(165, 165, 176),
	Accent  = Color3.fromRGB(92,  126, 255),
	-- FIX: distinct colours for log row kinds
	Found   = Color3.fromRGB(80,  220, 130),
	Removed = Color3.fromRGB(220, 90,  90),
	Info    = Color3.fromRGB(180, 180, 220),
}

-- ─── Types ─────────────────────────────────────────────────────────────────
type Entry = {
	Instance      : Instance,
	Name          : string,
	ClassName     : string,
	Category      : string,
	Reason        : string,
	Confidence    : number,
	ParentPath    : string,
	ChildrenCount : number,
	Tags          : { string },
	Attributes    : { [string]: any },
	Position      : Vector3?,
	BaseName      : string,
}

type LogItem = {
	Kind : string,
	Text : string,
	Time : number,
}

-- ─── State ─────────────────────────────────────────────────────────────────
local activeByInstance: { [Instance]: Entry } = {}
local categoryCounts: { [string]: number }    = {
	All = 0, NPC = 0, Item = 0, Interactable = 0, Vehicle = 0, Unknown = 0,
}

local logs:      { LogItem }  = {}
local queue:     { Instance } = {}
local queueHead               = 1

-- FIX: weak keys so GC'd instances are collected automatically and never accumulate
local queued:    { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: { [Instance]: boolean }
local analyzed:  { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: { [Instance]: boolean }
local destroyed: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: { [Instance]: boolean }

local currentTab  = "Dashboard"
local searchText  = ""
local liveEnabled = true
local paused      = false
local uiDirty     = true
local isRunning   = true
-- FIX: only reset scroll position when the tab actually changes, not on every live refresh
local tabJustChanged = true

local selectedEntry:    Entry?     = nil
local selectedHighlight: Highlight? = nil

-- FIX: track all external connections so we can clean up on GUI destroy
local connections: { RBXScriptConnection } = {}

-- ─── Utility ───────────────────────────────────────────────────────────────
local function safeToString(v: any): string
	local ok, result = pcall(tostring, v)
	return ok and (result :: string) or "<unprintable>"
end

local function queueSize(): number
	return math.max(0, #queue - queueHead + 1)
end

local function queuePush(obj: Instance)
	queue[#queue + 1] = obj
end

local function queuePop(): Instance?
	if queueHead > #queue then return nil end

	local obj           = queue[queueHead]
	queue[queueHead]    = nil
	queueHead          += 1

	if queueHead > 128 and queueHead > (#queue * 0.5) then
		local compacted: { Instance } = {}
		for i = queueHead, #queue do
			compacted[#compacted + 1] = queue[i]
		end
		queue     = compacted
		queueHead = 1
	end

	return obj
end

local function cleanName(name: string): string
	local base = name:gsub("%d+$", "")
	base       = base:gsub("[_%-%s]+$", "")
	return base
end

local function getTags(obj: Instance): { string }
	local ok, tags = pcall(function() return CollectionService:GetTags(obj) end)
	if not ok or not tags then return {} end
	local result: { string } = {}
	for _, tag in ipairs(tags :: { string }) do
		result[#result + 1] = tag
	end
	return result
end

local function hasTag(obj: Instance, tag: string): boolean
	local ok, result = pcall(function() return CollectionService:HasTag(obj, tag) end)
	return ok and result == true
end

local function safePosition(obj: Instance): Vector3?
	if obj:IsA("BasePart") then
		return (obj :: BasePart).Position
	end
	if obj:IsA("Model") then
		local ok, pivot = pcall(function() return (obj :: Model):GetPivot() end)
		if ok then return (pivot :: CFrame).Position end
	end
	return nil
end

local function fullName(obj: Instance?): string
	if not obj then return "nil" end
	local ok, result = pcall(function() return (obj :: Instance):GetFullName() end)
	return ok and (result :: string) or obj.Name
end

local function findDescendantWhichIsA(root: Instance, className: string): Instance?
	for _, d in root:GetDescendants() do
		if d:IsA(className) then return d end
	end
	return nil
end

-- ─── Classification ────────────────────────────────────────────────────────
local function isInteresting(obj: Instance): boolean
	if obj:IsA("Tool")
		or obj:IsA("Humanoid")
		or obj:IsA("ProximityPrompt")
		or obj:IsA("ClickDetector")
		or obj:IsA("VehicleSeat")
		or obj:IsA("Seat")
		or obj:IsA("AnimationController")
	then return true end

	local n = string.lower(obj.Name)
	if n:find("npc") or n:find("item") or n:find("loot")
		or n:find("quest") or n:find("shop") or n:find("vendor") or n:find("door")
	then return true end

	if obj:IsA("Model") then
		if obj:FindFirstChildOfClass("Humanoid") ~= nil then return true end
		if obj:FindFirstChild("HumanoidRootPart", true) ~= nil then return true end
		if findDescendantWhichIsA(obj, "ProximityPrompt") ~= nil then return true end
		if findDescendantWhichIsA(obj, "ClickDetector")   ~= nil then return true end
	end

	return false
end

-- FIX: reason strings in a lookup table instead of an if-chain
local CATEGORY_REASONS: { [string]: string } = {
	NPC          = "Humanoid / character-like structure",
	Item         = "Tool / pickup-like structure",
	Interactable = "Prompt / click interaction found",
	Vehicle      = "Seat / vehicle-like structure",
}

local function classify(obj: Instance): (string, number, string)
	local npcScore      = 0
	local itemScore     = 0
	local interactScore = 0
	local vehicleScore  = 0
	local nameLower     = string.lower(obj.Name)

	-- Tag-based scoring (high weight)
	if hasTag(obj, "NPC") or hasTag(obj, "Enemy") or hasTag(obj, "Character") then npcScore      += 100 end
	if hasTag(obj, "Item") or hasTag(obj, "Loot") or hasTag(obj, "Collectible") then itemScore    += 100 end
	if hasTag(obj, "Interactable") or hasTag(obj, "Clickable") or hasTag(obj, "Prompt") then interactScore += 100 end
	if hasTag(obj, "Vehicle") then vehicleScore += 100 end

	-- Name heuristics
	if nameLower:find("npc") or nameLower:find("enemy") or nameLower:find("guard") or nameLower:find("villager") then npcScore      += 20 end
	if nameLower:find("item") or nameLower:find("loot") or nameLower:find("key") or nameLower:find("potion") or nameLower:find("sword") then itemScore    += 16 end
	if nameLower:find("door") or nameLower:find("button") or nameLower:find("lever") or nameLower:find("shop") or nameLower:find("vendor") or nameLower:find("prompt") then interactScore += 16 end
	if nameLower:find("car") or nameLower:find("truck") or nameLower:find("boat") or nameLower:find("vehicle") then vehicleScore  += 16 end

	-- Class-based scoring
	if obj:IsA("Tool") then
		itemScore += 100
		if obj:FindFirstChild("Handle") then itemScore += 20 end
	end

	if obj:IsA("VehicleSeat") or obj:IsA("Seat") then vehicleScore  += 85 end
	if obj:IsA("ClickDetector") or obj:IsA("ProximityPrompt") then interactScore += 100 end

	if obj:IsA("Humanoid") then
		npcScore += 100
		local parent = obj.Parent
		if parent and parent:IsA("Model") then
			if parent:FindFirstChild("HumanoidRootPart") then npcScore += 35 end
			if parent:FindFirstChild("Head") then npcScore += 10 end
			if parent:FindFirstChildOfClass("Animator") then npcScore += 10 end
		end
	end

	if obj:IsA("Model") then
		if obj:FindFirstChildOfClass("Humanoid") then npcScore += 90 end
		if obj:FindFirstChild("HumanoidRootPart") then npcScore += 20 end
		if findDescendantWhichIsA(obj, "ProximityPrompt") then interactScore += 20 end
		if findDescendantWhichIsA(obj, "ClickDetector")   then interactScore += 20 end
		if findDescendantWhichIsA(obj, "VehicleSeat") or findDescendantWhichIsA(obj, "Seat") then vehicleScore += 20 end
	end

	local bestCategory = "Unknown"
	local bestScore    = 0
	local scores = { NPC = npcScore, Item = itemScore, Interactable = interactScore, Vehicle = vehicleScore }

	for category, score in pairs(scores) do
		if score > bestScore then
			bestScore    = score
			bestCategory = category
		end
	end

	if bestScore <= 0 then return "Unknown", 0, "No strong signals" end
	return bestCategory, bestScore, CATEGORY_REASONS[bestCategory] or "Unknown"
end

-- ─── Log ───────────────────────────────────────────────────────────────────
local function logEvent(kind: string, text: string)
	logs[#logs + 1] = { Kind = kind, Text = text, Time = os.clock() }
	-- FIX: O(1) trim via table.move instead of O(n) table.remove(logs, 1)
	if #logs > MAX_LOGS then
		table.move(logs, 2, #logs, 1)
		logs[#logs] = nil :: any
	end
	uiDirty = true
end

-- ─── Highlight ─────────────────────────────────────────────────────────────
-- FIX: createHighlight now takes the adornee directly — cleaner call site
local function createHighlight(adornee: Instance): Highlight
	local hl                  = Instance.new("Highlight")
	hl.Name                   = "ScannerHighlight"
	hl.FillColor              = COLOR.Accent
	hl.OutlineColor           = Color3.fromRGB(255, 255, 255)
	hl.FillTransparency       = 0.6
	hl.OutlineTransparency    = 0.05
	hl.DepthMode              = Enum.HighlightDepthMode.Occluded
	hl.Adornee                = adornee
	hl.Enabled                = true
	hl.Parent                 = workspace
	return hl
end

local function updateSelection(entry: Entry?)
	selectedEntry = entry

	if selectedHighlight then
		selectedHighlight:Destroy()
		selectedHighlight = nil
	end

	if entry and entry.Instance and entry.Instance.Parent then
		selectedHighlight = createHighlight(entry.Instance)
	end
end

-- FIX: Glow now properly toggles the highlight (original called setDetail — same as Inspect)
local function toggleGlow(entry: Entry)
	if selectedEntry == entry then
		updateSelection(nil)
	else
		updateSelection(entry)
	end
	uiDirty = true
end

-- ─── Scan Entries ──────────────────────────────────────────────────────────
local function addEntry(obj: Instance)
	if analyzed[obj] or destroyed[obj] then return end
	analyzed[obj] = true

	local category, confidence, reason = classify(obj)

	-- FIX: GetAttributes can throw on locked instances — guard it
	local attrs: { [string]: any } = {}
	local ok, rawAttrs = pcall(function() return obj:GetAttributes() end)
	if ok and rawAttrs then
		attrs = rawAttrs :: { [string]: any }
	end

	local entry: Entry = {
		Instance      = obj,
		Name          = obj.Name,
		ClassName     = obj.ClassName,
		Category      = category,
		Reason        = reason,
		Confidence    = confidence,
		ParentPath    = fullName(obj.Parent),
		ChildrenCount = #obj:GetChildren(),
		Tags          = getTags(obj),
		Attributes    = attrs,
		Position      = safePosition(obj),
		BaseName      = cleanName(obj.Name),
	}

	activeByInstance[obj]        = entry
	categoryCounts.All          += 1
	categoryCounts[category]     = (categoryCounts[category] or 0) + 1

	local tagText = (#entry.Tags > 0) and table.concat(entry.Tags, ", ") or "No tags"
	logEvent("Found", `{entry.Category}: {entry.Name} ({entry.ClassName}) • {tagText}`)
	uiDirty = true
end

local function removeEntry(obj: Instance)
	destroyed[obj] = true
	queued[obj]    = nil
	analyzed[obj]  = nil

	local entry = activeByInstance[obj]
	if not entry then return end

	activeByInstance[obj]         = nil
	categoryCounts.All             = math.max(0, categoryCounts.All - 1)
	categoryCounts[entry.Category] = math.max(0, (categoryCounts[entry.Category] or 0) - 1)
	logEvent("Removed", `{entry.Category}: {entry.Name}`)

	if selectedEntry and selectedEntry.Instance == obj then
		updateSelection(nil)
	end
	uiDirty = true
end

local function resetScan()
	activeByInstance = {}
	categoryCounts   = { All = 0, NPC = 0, Item = 0, Interactable = 0, Vehicle = 0, Unknown = 0 }
	logs             = {}
	queue            = {}
	queueHead        = 1

	-- FIX: reinitialise as fresh weak tables so old entries don't linger
	queued    = setmetatable({}, { __mode = "k" }) :: { [Instance]: boolean }
	analyzed  = setmetatable({}, { __mode = "k" }) :: { [Instance]: boolean }
	destroyed = setmetatable({}, { __mode = "k" }) :: { [Instance]: boolean }

	selectedEntry = nil
	if selectedHighlight then
		selectedHighlight:Destroy()
		selectedHighlight = nil
	end
	uiDirty = true
end

-- ─── UI Build ──────────────────────────────────────────────────────────────
-- FIX: if this LocalScript is re-run (e.g. executor re-injection / live reload),
-- remove any previous instance of the GUI so connections/highlights don't double up
local existingGui = PlayerGui:FindFirstChild("ExplorerScannerGui")
if existingGui then
	existingGui:Destroy()
end

local screenGui               = Instance.new("ScreenGui")
screenGui.Name                = "ExplorerScannerGui"
screenGui.ResetOnSpawn        = false
screenGui.IgnoreGuiInset      = true
screenGui.ZIndexBehavior      = Enum.ZIndexBehavior.Sibling
-- FIX: raise DisplayOrder so the GUI stays above most game UI layers (default is 0)
screenGui.DisplayOrder        = 10
screenGui.Parent              = PlayerGui

local root                    = Instance.new("Frame")
root.Name                     = "Root"
root.AnchorPoint              = Vector2.new(0.5, 0.5)
root.Position                 = UDim2.fromScale(0.5, 0.5)
root.Size                     = UDim2.fromOffset(1020, 620)
root.BackgroundColor3         = COLOR.Bg
root.BorderSizePixel          = 0
root.Parent                   = screenGui
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = root
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.3; s.Color = COLOR.Stroke; s.Parent = root
end

local topBar                  = Instance.new("Frame")
topBar.BackgroundColor3       = COLOR.Panel
topBar.BorderSizePixel        = 0
topBar.Size                   = UDim2.new(1, 0, 0, 56)
topBar.Parent                 = root
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 16); c.Parent = topBar
end

local title                   = Instance.new("TextLabel")
title.BackgroundTransparency  = 1
title.Position                = UDim2.fromOffset(16, 0)
title.Size                    = UDim2.new(0, 420, 1, 0)
title.Font                    = Enum.Font.GothamBold
title.Text                    = "Instance Explorer Scanner"
title.TextColor3              = COLOR.Text
title.TextSize                = 18
title.TextXAlignment          = Enum.TextXAlignment.Left
title.Parent                  = topBar

local statusLabel                  = Instance.new("TextLabel")
statusLabel.BackgroundTransparency = 1
statusLabel.AnchorPoint            = Vector2.new(1, 0.5)
statusLabel.Position               = UDim2.new(1, -16, 0.5, 0)
statusLabel.Size                   = UDim2.fromOffset(250, 20)
statusLabel.Font                   = Enum.Font.Gotham
statusLabel.Text                   = "Idle"
statusLabel.TextColor3             = COLOR.Muted
statusLabel.TextSize               = 13
statusLabel.TextXAlignment         = Enum.TextXAlignment.Right
statusLabel.Parent                 = topBar

local searchBox                    = Instance.new("TextBox")
searchBox.Name                     = "SearchBox"
searchBox.PlaceholderText          = "Search name, class, parent, tags, attributes…"
searchBox.Text                     = ""
searchBox.ClearTextOnFocus         = false
searchBox.Font                     = Enum.Font.Gotham
searchBox.TextSize                 = 14
searchBox.TextColor3               = COLOR.Text
searchBox.PlaceholderColor3        = COLOR.Muted
searchBox.BackgroundColor3         = COLOR.Panel2
searchBox.BorderSizePixel          = 0
searchBox.Position                 = UDim2.fromOffset(16, 70)
searchBox.Size                     = UDim2.new(0, 390, 0, 38)
searchBox.Parent                   = root
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = searchBox
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.45; s.Color = COLOR.Stroke; s.Parent = searchBox
end

-- Button factory
local function makeButton(text: string, width: number): TextButton
	local btn              = Instance.new("TextButton")
	btn.AutoButtonColor    = false
	btn.Text               = text
	btn.Font               = Enum.Font.GothamSemibold
	btn.TextSize           = 13
	btn.TextColor3         = COLOR.Text
	btn.BackgroundColor3   = COLOR.Panel2
	btn.BorderSizePixel    = 0
	btn.Size               = UDim2.fromOffset(width, 38)
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = btn
		local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.45; s.Color = COLOR.Stroke; s.Parent = btn
	end
	-- FIX: track the active hover tween so rapid MouseEnter/MouseLeave don't queue competing tweens
	local hoverTween: Tween? = nil
	local function playHover(color: Color3)
		if hoverTween then hoverTween:Cancel() end
		hoverTween = TweenService:Create(btn, TweenInfo.new(0.12), { BackgroundColor3 = color })
		hoverTween:Play()
	end
	btn.MouseEnter:Connect(function() playHover(COLOR.Stroke) end)
	btn.MouseLeave:Connect(function() playHover(COLOR.Panel2) end)
	return btn
end

local buttonRow                    = Instance.new("Frame")
buttonRow.BackgroundTransparency   = 1
-- FIX: widened to fit total button widths + padding (416px) instead of 372px,
-- so layout no longer depends on right-aligned overflow beyond the frame bounds
buttonRow.Position                 = UDim2.new(1, -436, 0, 70)
buttonRow.Size                     = UDim2.fromOffset(420, 38)
buttonRow.Parent                   = root
do
	local l = Instance.new("UIListLayout")
	l.FillDirection       = Enum.FillDirection.Horizontal
	l.HorizontalAlignment = Enum.HorizontalAlignment.Right
	l.Padding             = UDim.new(0, 8)
	l.Parent              = buttonRow
end

-- FIX: explicit LayoutOrder so buttons render Refresh→Pause→Live→Clear→Copy, not alphabetically
local refreshButton = makeButton("Refresh", 84); refreshButton.LayoutOrder = 1; refreshButton.Parent = buttonRow
local pauseButton   = makeButton("Pause",   74); pauseButton.LayoutOrder   = 2; pauseButton.Parent   = buttonRow
local liveButton    = makeButton("Live On", 86); liveButton.LayoutOrder    = 3; liveButton.Parent    = buttonRow
local clearButton   = makeButton("Clear",   74); clearButton.LayoutOrder   = 4; clearButton.Parent   = buttonRow
local copyButton    = makeButton("Copy",    66); copyButton.LayoutOrder    = 5; copyButton.Parent    = buttonRow

-- Left panel (tabs)
local leftPanel              = Instance.new("Frame")
leftPanel.BackgroundColor3   = COLOR.Panel
leftPanel.BorderSizePixel    = 0
leftPanel.Position           = UDim2.fromOffset(16, 120)
leftPanel.Size               = UDim2.new(0, 220, 1, -136)
leftPanel.Parent             = root
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = leftPanel
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.35; s.Color = COLOR.Stroke; s.Parent = leftPanel
end

local leftTitle                   = Instance.new("TextLabel")
leftTitle.BackgroundTransparency  = 1
leftTitle.Position                = UDim2.fromOffset(14, 10)
leftTitle.Size                    = UDim2.new(1, -28, 0, 22)
leftTitle.Font                    = Enum.Font.GothamBold
leftTitle.Text                    = "Tabs"
leftTitle.TextColor3              = COLOR.Text
leftTitle.TextSize                = 15
leftTitle.TextXAlignment          = Enum.TextXAlignment.Left
leftTitle.Parent                  = leftPanel

-- FIX: wrap tabList in a ScrollingFrame so extra tabs don't clip
local tabScroll                        = Instance.new("ScrollingFrame")
tabScroll.BackgroundTransparency       = 1
tabScroll.BorderSizePixel              = 0
tabScroll.Position                     = UDim2.fromOffset(12, 38)
tabScroll.Size                         = UDim2.new(1, -24, 1, -50)
tabScroll.ScrollBarThickness           = 4
tabScroll.ScrollBarImageColor3         = COLOR.Stroke
-- FIX: restrict scrolling to the Y axis
tabScroll.ScrollingDirection           = Enum.ScrollingDirection.Y
tabScroll.AutomaticCanvasSize          = Enum.AutomaticSize.Y
tabScroll.CanvasSize                   = UDim2.new()
tabScroll.Parent                       = leftPanel

local tabList                      = Instance.new("Frame")
tabList.BackgroundTransparency     = 1
tabList.Size                       = UDim2.new(1, 0, 1, 0)
tabList.AutomaticSize              = Enum.AutomaticSize.Y
tabList.Parent                     = tabScroll
do
	local l = Instance.new("UIListLayout"); l.Padding = UDim.new(0, 8); l.Parent = tabList
end

-- Right panel (content)
local rightPanel              = Instance.new("Frame")
rightPanel.BackgroundColor3   = COLOR.Panel
rightPanel.BorderSizePixel    = 0
rightPanel.Position           = UDim2.fromOffset(250, 120)
rightPanel.Size               = UDim2.new(1, -266, 1, -136)
rightPanel.Parent             = root
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 14); c.Parent = rightPanel
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.35; s.Color = COLOR.Stroke; s.Parent = rightPanel
end

local contentHeader                   = Instance.new("TextLabel")
contentHeader.BackgroundTransparency  = 1
contentHeader.Position                = UDim2.fromOffset(14, 10)
contentHeader.Size                    = UDim2.new(1, -28, 0, 22)
contentHeader.Font                    = Enum.Font.GothamBold
contentHeader.Text                    = "Dashboard"
contentHeader.TextColor3              = COLOR.Text
contentHeader.TextSize                = 15
contentHeader.TextXAlignment          = Enum.TextXAlignment.Left
contentHeader.Parent                  = rightPanel

local contentFrame                    = Instance.new("ScrollingFrame")
contentFrame.Name                     = "Content"
contentFrame.BackgroundTransparency   = 1
contentFrame.BorderSizePixel          = 0
contentFrame.Position                 = UDim2.fromOffset(12, 38)
contentFrame.Size                     = UDim2.new(1, -24, 1, -170)
contentFrame.ScrollBarThickness       = 6
contentFrame.ScrollBarImageColor3     = COLOR.Stroke
contentFrame.AutomaticCanvasSize      = Enum.AutomaticSize.Y
contentFrame.CanvasSize               = UDim2.new()
contentFrame.Parent                   = rightPanel
do
	local l = Instance.new("UIListLayout")
	l.Padding    = UDim.new(0, 8)
	l.SortOrder  = Enum.SortOrder.LayoutOrder
	l.Parent     = contentFrame
end

-- Detail panel (bottom of right panel)
local detailPanel              = Instance.new("Frame")
detailPanel.BackgroundColor3   = COLOR.Bg
detailPanel.BorderSizePixel    = 0
detailPanel.Position           = UDim2.new(0, 12, 1, -118)
detailPanel.Size               = UDim2.new(1, -24, 0, 106)
detailPanel.Parent             = rightPanel
do
	local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = detailPanel
	local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.35; s.Color = COLOR.Stroke; s.Parent = detailPanel
end

local detailText                    = Instance.new("TextLabel")
detailText.BackgroundTransparency   = 1
detailText.Position                 = UDim2.fromOffset(12, 8)
detailText.Size                     = UDim2.new(1, -24, 1, -16)
detailText.Font                     = Enum.Font.Code
detailText.TextSize                 = 13
detailText.TextColor3               = COLOR.Text
detailText.TextXAlignment           = Enum.TextXAlignment.Left
detailText.TextYAlignment           = Enum.TextYAlignment.Top
detailText.TextWrapped              = true
detailText.Text                     = "Select something to inspect metadata."
detailText.Parent                   = detailPanel

local tabButtons: { [string]: TextButton } = {}

-- ─── UI Logic ──────────────────────────────────────────────────────────────
local function setDetail(entry: Entry?)
	updateSelection(entry)

	if not entry then
		detailText.Text = "Select something to inspect metadata."
		return
	end

	local tagsText           = (#entry.Tags > 0) and table.concat(entry.Tags, ", ") or "None"
	local attrLines: { string } = {}
	for k, v in pairs(entry.Attributes) do
		attrLines[#attrLines + 1] = `{k} = {safeToString(v)}`
	end
	table.sort(attrLines)
	local attrsText = (#attrLines > 0) and table.concat(attrLines, "\n") or "None"

	detailText.Text = table.concat({
		`Name:     {entry.Name}`,
		`Class:    {entry.ClassName}`,
		`Category: {entry.Category}  (score {entry.Confidence})`,
		`Parent:   {entry.ParentPath}`,
		`Children: {entry.ChildrenCount}`,
		`BaseName: {entry.BaseName}`,
		`Tags:     {tagsText}`,
		`Position: {entry.Position and tostring(entry.Position) or "None"}`,
		`Reason:   {entry.Reason}`,
		"",
		"Attributes:",
		attrsText,
	}, "\n")
end

local function clearContent()
	-- FIX: scroll back to top only when switching tabs, so live updates
	-- (new entries/logs arriving) don't yank the user's scroll position around
	if tabJustChanged then
		contentFrame.CanvasPosition = Vector2.new(0, 0)
		tabJustChanged = false
	end
	for _, child in ipairs(contentFrame:GetChildren()) do
		if child:IsA("GuiObject") then child:Destroy() end
	end
end

-- Card widget
local function createCard(titleText: string, valueText: string, subText: string)
	local card            = Instance.new("Frame")
	card.BackgroundColor3 = COLOR.Panel2
	card.BorderSizePixel  = 0
	card.Size             = UDim2.new(1, 0, 0, 82)
	card.Parent           = contentFrame
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = card
		local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.45; s.Color = COLOR.Stroke; s.Parent = card
	end

	local function lbl(pos: UDim2, sz: UDim2, font: Enum.Font, tsize: number, col: Color3, txt: string)
		local l                  = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position               = pos
		l.Size                   = sz
		l.Font                   = font
		l.TextSize               = tsize
		l.TextColor3             = col
		l.TextXAlignment         = Enum.TextXAlignment.Left
		l.TextTruncate           = Enum.TextTruncate.AtEnd
		l.Text                   = txt
		l.Parent                 = card
	end

	lbl(UDim2.fromOffset(12, 10), UDim2.new(1, -24, 0, 18), Enum.Font.GothamSemibold, 13, COLOR.Muted, titleText)
	lbl(UDim2.fromOffset(12, 28), UDim2.new(1, -24, 0, 24), Enum.Font.GothamBold,     20, COLOR.Text,  valueText)
	lbl(UDim2.fromOffset(12, 54), UDim2.new(1, -24, 0, 18), Enum.Font.Gotham,         12, COLOR.Muted, subText)
end

-- Entry row widget
local function makeRow(entry: Entry)
	local row             = Instance.new("Frame")
	row.BackgroundColor3  = COLOR.Panel2
	row.BorderSizePixel   = 0
	row.Size              = UDim2.new(1, 0, 0, 70)
	row.Parent            = contentFrame
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row
		local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.45; s.Color = COLOR.Stroke; s.Parent = row
	end

	local nameLabel                   = Instance.new("TextLabel")
	nameLabel.BackgroundTransparency  = 1
	nameLabel.Position                = UDim2.fromOffset(12, 8)
	nameLabel.Size                    = UDim2.new(1, -150, 0, 18)
	nameLabel.Font                    = Enum.Font.GothamBold
	nameLabel.TextSize                = 14
	nameLabel.TextColor3              = COLOR.Text
	nameLabel.TextXAlignment          = Enum.TextXAlignment.Left
	-- FIX: truncate so long names don't bleed over the buttons
	nameLabel.TextTruncate            = Enum.TextTruncate.AtEnd
	nameLabel.Text                    = entry.Name
	nameLabel.Parent                  = row

	local metaLabel                   = Instance.new("TextLabel")
	metaLabel.BackgroundTransparency  = 1
	metaLabel.Position                = UDim2.fromOffset(12, 28)
	metaLabel.Size                    = UDim2.new(1, -150, 0, 18)
	metaLabel.Font                    = Enum.Font.Gotham
	metaLabel.TextSize                = 12
	metaLabel.TextColor3              = COLOR.Muted
	metaLabel.TextXAlignment          = Enum.TextXAlignment.Left
	metaLabel.Text                    = `{entry.Category} • {entry.ClassName} • score {entry.Confidence}`
	metaLabel.Parent                  = row

	local inspectBtn          = makeButton("Inspect", 74)
	inspectBtn.AnchorPoint    = Vector2.new(1, 0)
	inspectBtn.Position       = UDim2.new(1, -10, 0, 18)
	inspectBtn.Parent         = row
	inspectBtn.MouseButton1Click:Connect(function() setDetail(entry) end)

	-- FIX: Glow button now calls toggleGlow, not setDetail (was identical to Inspect — bug)
	local glowBtn             = makeButton("Glow", 60)
	glowBtn.AnchorPoint       = Vector2.new(1, 0)
	glowBtn.Position          = UDim2.new(1, -92, 0, 18)
	glowBtn.Parent            = row
	glowBtn.MouseButton1Click:Connect(function() toggleGlow(entry) end)
end

-- Log row widget
local LOG_KIND_COLOR: { [string]: Color3 } = {
	Found   = COLOR.Found,
	Removed = COLOR.Removed,
	Info    = COLOR.Info,
}

local function makeLogRow(item: LogItem)
	local row             = Instance.new("Frame")
	row.BackgroundColor3  = COLOR.Panel2
	row.BorderSizePixel   = 0
	row.Size              = UDim2.new(1, 0, 0, 48)
	row.Parent            = contentFrame
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = row
		local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.5; s.Color = COLOR.Stroke; s.Parent = row
	end

	local kind                   = Instance.new("TextLabel")
	kind.BackgroundTransparency  = 1
	kind.Position                = UDim2.fromOffset(12, 6)
	kind.Size                    = UDim2.new(0, 120, 0, 16)
	kind.Font                    = Enum.Font.GothamBold
	kind.TextSize                = 12
	kind.TextXAlignment          = Enum.TextXAlignment.Left
	-- FIX: colour by log kind instead of always Accent
	kind.TextColor3              = LOG_KIND_COLOR[item.Kind] or COLOR.Accent
	kind.Text                    = item.Kind
	kind.Parent                  = row

	local txt                    = Instance.new("TextLabel")
	txt.BackgroundTransparency   = 1
	txt.Position                 = UDim2.fromOffset(12, 22)
	txt.Size                     = UDim2.new(1, -24, 0, 18)
	txt.Font                     = Enum.Font.Gotham
	txt.TextSize                 = 12
	txt.TextColor3               = COLOR.Text
	txt.TextXAlignment           = Enum.TextXAlignment.Left
	txt.TextTruncate             = Enum.TextTruncate.AtEnd
	txt.Text                     = item.Text
	txt.Parent                   = row
end

-- Pattern group helpers
local function buildPatternGroups(list: { Entry }): { [string]: { Entry } }
	local groups: { [string]: { Entry } } = {}
	for _, entry in ipairs(list) do
		local key    = entry.BaseName
		groups[key]  = groups[key] or {}
		groups[key][#groups[key] + 1] = entry
	end
	return groups
end

local function makePatternRow(baseName: string, entries: { Entry })
	local row             = Instance.new("Frame")
	row.BackgroundColor3  = COLOR.Panel2
	row.BorderSizePixel   = 0
	row.Size              = UDim2.new(1, 0, 0, 62)
	row.Parent            = contentFrame
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 12); c.Parent = row
		local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.45; s.Color = COLOR.Stroke; s.Parent = row
	end

	local label                   = Instance.new("TextLabel")
	label.BackgroundTransparency  = 1
	label.Position                = UDim2.fromOffset(12, 8)
	label.Size                    = UDim2.new(1, -130, 0, 18)
	label.Font                    = Enum.Font.GothamBold
	label.TextSize                = 14
	label.TextColor3              = COLOR.Text
	label.TextXAlignment          = Enum.TextXAlignment.Left
	label.TextTruncate            = Enum.TextTruncate.AtEnd
	label.Text                    = `{baseName}  ×{#entries}`
	label.Parent                  = row

	local previewNames: { string } = {}
	for i = 1, math.min(4, #entries) do previewNames[i] = entries[i].Name end

	local preview                  = Instance.new("TextLabel")
	preview.BackgroundTransparency = 1
	preview.Position               = UDim2.fromOffset(12, 28)
	preview.Size                   = UDim2.new(1, -130, 0, 16)
	preview.Font                   = Enum.Font.Gotham
	preview.TextSize               = 12
	preview.TextColor3             = COLOR.Muted
	preview.TextXAlignment         = Enum.TextXAlignment.Left
	preview.TextTruncate           = Enum.TextTruncate.AtEnd
	preview.Text                   = table.concat(previewNames, ", ")
	preview.Parent                 = row

	local inspectBtn         = makeButton("Inspect", 74)
	inspectBtn.AnchorPoint   = Vector2.new(1, 0)
	inspectBtn.Position      = UDim2.new(1, -10, 0, 14)
	inspectBtn.Parent        = row
	inspectBtn.MouseButton1Click:Connect(function()
		if entries[1] then setDetail(entries[1]) end
	end)
end

-- ─── Tab render helpers ────────────────────────────────────────────────────
local function renderStatsCard()
	createCard("Scanned",       tostring(categoryCounts.All),                `Queue: {queueSize()} • Live: {liveEnabled} • Paused: {paused}`)
	createCard("NPCs",          tostring(categoryCounts.NPC or 0),           "Humanoids, characters, vendors, guards")
	createCard("Items",         tostring(categoryCounts.Item or 0),          "Tools and pickup-like objects")
	createCard("Interactables", tostring(categoryCounts.Interactable or 0),  "Prompts, click detectors, doors, buttons")
	createCard("Vehicles",      tostring(categoryCounts.Vehicle or 0),       "Seats, rideables, vehicle models")
end

local function collectVisibleEntries(category: string): { Entry }
	local results: { Entry } = {}
	local query = string.lower(searchText)

	for _, entry in pairs(activeByInstance) do
		if category == "All" or entry.Category == category then
			if query == "" then
				results[#results + 1] = entry
			else
				local hay = string.lower(table.concat({
					entry.Name, entry.ClassName, entry.Category,
					entry.ParentPath, entry.Reason, table.concat(entry.Tags, ","),
				}, "|"))
				if hay:find(query, 1, true) then
					results[#results + 1] = entry
				end
			end
		end
	end

	-- FIX: sort by category first, then name — original had a dead if-branch that always sorted by name
	table.sort(results, function(a: Entry, b: Entry): boolean
		if a.Category ~= b.Category then return a.Category < b.Category end
		return a.Name < b.Name
	end)

	if #results > MAX_ROWS then
		local trimmed: { Entry } = table.create(MAX_ROWS)
		table.move(results, 1, MAX_ROWS, 1, trimmed)
		return trimmed
	end
	return results
end

local function renderDashboard()
	contentHeader.Text = "Dashboard"
	renderStatsCard()
	createCard(
		"Selection",
		selectedEntry and selectedEntry.Name or "None",
		selectedEntry and selectedEntry.Category or "Click an entry to inspect it"
	)
	createCard("Logs", tostring(#logs), #logs > 0 and logs[#logs].Text or "No activity yet")
end

local function renderLogView()
	contentHeader.Text = "Live Log"
	if #logs == 0 then createCard("Log", "Empty", "Waiting for discoveries…"); return end
	for i = #logs, math.max(1, #logs - MAX_ROWS + 1), -1 do makeLogRow(logs[i]) end
end

local function renderPatterns(list: { Entry })
	contentHeader.Text = "Patterns"
	local groups = buildPatternGroups(list)

	-- FIX: collect and sort keys so render order is deterministic across runs
	local baseNames: { string } = {}
	for baseName, group in pairs(groups) do
		if #group > 1 then baseNames[#baseNames + 1] = baseName end
	end

	if #baseNames == 0 then
		createCard("Pattern Groups", "None", "Repeated names will appear here automatically.")
		return
	end

	table.sort(baseNames)
	for _, baseName in ipairs(baseNames) do
		makePatternRow(baseName, groups[baseName])
	end
end

local function renderEntries(list: { Entry }, headerText: string)
	contentHeader.Text = headerText
	if #list == 0 then createCard("No results", "0", "Try a different tab or search term."); return end
	for _, entry in ipairs(list) do makeRow(entry) end
end

-- ─── Tab buttons ───────────────────────────────────────────────────────────
local function refreshTabStyles()
	for name, button in pairs(tabButtons) do
		if name == currentTab then
			button.BackgroundColor3 = COLOR.Accent
			button.TextColor3       = Color3.fromRGB(255, 255, 255)
		else
			button.BackgroundColor3 = COLOR.Panel2
			button.TextColor3       = COLOR.Text
		end
	end
end

local function setTab(tabName: string)
	currentTab     = tabName
	tabJustChanged = true
	uiDirty        = true
	refreshTabStyles()
end

local function makeTabButton(tabName: string, index: number)
	local btn             = Instance.new("TextButton")
	btn.AutoButtonColor   = false
	btn.Size              = UDim2.new(1, 0, 0, 36)
	btn.BackgroundColor3  = COLOR.Panel2
	btn.BorderSizePixel   = 0
	-- FIX: explicit LayoutOrder so tabs render in TABS order, not alphabetically
	btn.LayoutOrder       = index
	btn.Text              = tabName
	btn.Font              = Enum.Font.GothamSemibold
	btn.TextSize          = 13
	btn.TextColor3        = COLOR.Text
	btn.Parent            = tabList
	do
		local c = Instance.new("UICorner"); c.CornerRadius = UDim.new(0, 10); c.Parent = btn
		local s = Instance.new("UIStroke"); s.Thickness = 1; s.Transparency = 0.45; s.Color = COLOR.Stroke; s.Parent = btn
	end
	btn.MouseButton1Click:Connect(function() setTab(tabName) end)
	tabButtons[tabName] = btn
end

for index, tab in ipairs(TABS) do makeTabButton(tab, index) end

-- ─── View render ───────────────────────────────────────────────────────────
local function renderView()
	clearContent()

	if     currentTab == "Dashboard" then renderDashboard()
	elseif currentTab == "Log"       then renderLogView()
	elseif currentTab == "Patterns"  then renderPatterns(collectVisibleEntries("All"))
	else                                  renderEntries(collectVisibleEntries(currentTab), currentTab)
	end

	-- FIX: throttle statusLabel updates — only write when the text actually changes
	local newStatus = `{currentTab} • {categoryCounts.All} total • queue {queueSize()}`
	if statusLabel.Text ~= newStatus then
		statusLabel.Text = newStatus
	end
	uiDirty = false
end

-- ─── Controls ──────────────────────────────────────────────────────────────
-- FIX: extract shared refresh logic so button and hotkey don't duplicate it
local function doRefresh()
	resetScan()
	for _, obj in ipairs(workspace:GetDescendants()) do
		if isInteresting(obj) then
			queuePush(obj)
			queued[obj] = true
		end
	end
	logEvent("Info", "Scan refreshed")
	uiDirty = true
end

refreshButton.MouseButton1Click:Connect(function() doRefresh() end)

pauseButton.MouseButton1Click:Connect(function()
	paused           = not paused
	pauseButton.Text = paused and "Resume" or "Pause"
	logEvent("Info", paused and "Scanning paused" or "Scanning resumed")
	uiDirty = true
end)

liveButton.MouseButton1Click:Connect(function()
	liveEnabled    = not liveEnabled
	liveButton.Text = liveEnabled and "Live On" or "Live Off"
	logEvent("Info", liveEnabled and "Live scan enabled" or "Live scan disabled")
	uiDirty = true
end)

clearButton.MouseButton1Click:Connect(function()
	logs    = {}
	uiDirty = true
end)

copyButton.MouseButton1Click:Connect(function()
	if not selectedEntry then return end
	local path = fullName(selectedEntry.Instance)
	-- FIX: cast setclipboard through `any` to satisfy --!strict (executor global)
	local ok = pcall(function()
		local fn: ((string) -> ())? = (rawget(_G, "setclipboard") :: any)
		if fn then fn(path) end
	end)
	if ok then
		pcall(function()
			StarterGui:SetCore("SendNotification", {
				Title    = "Scanner",
				Text     = "Copied: " .. path,
				Duration = 2,
			})
		end)
	end
end)

-- FIX: store all external connections so we can disconnect on teardown
-- FIX: debounce search input by 0.15s — only re-render after typing pauses
local searchDebounceToken = 0
connections[#connections + 1] = searchBox:GetPropertyChangedSignal("Text"):Connect(function()
	searchDebounceToken += 1
	local myToken = searchDebounceToken
	local pendingText = searchBox.Text
	task.delay(0.15, function()
		if myToken ~= searchDebounceToken then return end -- a newer keystroke superseded this one
		searchText = pendingText
		uiDirty    = true
	end)
end)

connections[#connections + 1] = workspace.DescendantAdded:Connect(function(obj: Instance)
	-- FIX: also skip already-tracked instances to avoid duplicate analysis
	if not liveEnabled or queued[obj] or analyzed[obj] then return end
	if isInteresting(obj) then
		queuePush(obj)
		queued[obj] = true
	end
end)

connections[#connections + 1] = workspace.DescendantRemoving:Connect(function(obj: Instance)
	removeEntry(obj)
end)

connections[#connections + 1] = UserInputService.InputBegan:Connect(function(input: InputObject, processed: boolean)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.RightShift then
		root.Visible = not root.Visible
	elseif input.KeyCode == Enum.KeyCode.F5 then
		doRefresh()
		logEvent("Info", "Hotkey refresh started")
	elseif input.KeyCode == Enum.KeyCode.Escape then
		if searchBox:IsFocused() then searchBox:ReleaseFocus() end
	end
end)

-- FIX: clean up connections + highlight when the ScreenGui is destroyed.
-- FIX (1): this connection is now stored in `connections` too, and disconnects
-- itself along with everything else (safe to do from within its own handler).
local ancestryConn: RBXScriptConnection
ancestryConn = screenGui.AncestryChanged:Connect(function()
	if screenGui.Parent then return end
	isRunning = false -- FIX (4): signal the main loop to stop instead of polling screenGui.Parent
	for _, conn in ipairs(connections) do conn:Disconnect() end
	table.clear(connections)
	if selectedHighlight then
		selectedHighlight:Destroy()
		selectedHighlight = nil
	end
end)
connections[#connections + 1] = ancestryConn

-- ─── Initial scan ──────────────────────────────────────────────────────────
-- FIX (7): batch the initial descendant walk in chunks with task.wait between
-- them, so very large places don't spend one long unbroken frame here.
task.defer(function()
	local descendants  = workspace:GetDescendants()
	local INIT_CHUNK   = 500
	for i, obj in ipairs(descendants) do
		if isInteresting(obj) then
			queuePush(obj)
			queued[obj] = true
		end
		if i % INIT_CHUNK == 0 then
			task.wait()
		end
	end
	logEvent("Info", "Initial scan queued")
end)

-- ─── Main loop ─────────────────────────────────────────────────────────────
task.spawn(function()
	while isRunning do
		-- FIX (2): wrap the tick body in pcall so an unexpected error on one
		-- instance/render doesn't permanently kill the scan loop.
		local ok, err = pcall(function()
			if not paused then
				local processed = 0
				while processed < BATCH_PER_TICK do
					local obj = queuePop()
					if not obj then break end
					queued[obj] = nil
					-- isInteresting was already verified at queue time; just guard lifecycle
					if obj.Parent and not analyzed[obj] and not destroyed[obj] then
						addEntry(obj)
					end
					processed += 1
				end
			end

			if uiDirty then renderView() end
		end)

		if not ok then
			warn("[ExplorerScanner] main loop error: " .. tostring(err))
		end

		task.wait(SCAN_DELAY)
	end
end)

setTab("Dashboard")
renderView()

-- ─── Public API ────────────────────────────────────────────────────────────
return {
	GetDatabase = function(): { [Instance]: Entry }
		-- FIX: shallow copy so external callers can't mutate internal state directly
		local copy: { [Instance]: Entry } = {}
		for inst, entry in pairs(activeByInstance) do
			copy[inst] = entry
		end
		return copy
	end,
	SetTab    = setTab,
	SetSearch = function(text: string)
		searchText     = text
		searchBox.Text = text
		uiDirty        = true
	end,
	ToggleGui = function()
		root.Visible = not root.Visible
	end,
	Refresh   = doRefresh,
}
