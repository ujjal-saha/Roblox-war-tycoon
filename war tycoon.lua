local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")

local env = (getgenv and getgenv()) or _G

-- ==========================================
-- SETTINGS
-- ==========================================
local BANNED_WORDS = {
	"parts oil exchange",
	"oil exchange",
	"parts",
	-- Removed "operation": it also matched "Operations" in the purchase-button labels.
}
local DEBUG = false           -- true = print what the script is thinking to the console (F9)
local REBIRTH_REQUIRE_PAD = false -- if true, a rebirth sign is only accepted when a pad is found next to it
local REBIRTH_NEAR_DIST = 500 -- rebirth buttons this close to your Cash Collector also count as yours
local MAX_ATTEMPTS = 4        -- tries per button before skipping it
local COLLECT_WAIT = 1.5      -- seconds spent standing on the collector
local CHECK_WAIT = 0.7        -- seconds to wait after TPing to a button before checking money
local MAX_REBIRTH = 12        -- the player can never enter more than this
local REBIRTH_CONFIRM_MIN_CASH = 500000 -- screenshot rebirth confirmation cost; the dialog cost is also read dynamically
local REBIRTH_CONFIRM_TIMEOUT = 8 -- seconds to wait for the confirmation dialog
local REBIRTH_SKIP_TIME = 30  -- if a rebirth button does not work, wait this many seconds before trying it again
local DESPAWN_MIN_SECONDS = 100 -- a fallen barrel shows "DESPAWN: ~600"; other loot shows "DESPAWN: 30" and is ignored

local function dbg(...)
	if DEBUG then warn("[AutoBuyer]", ...) end
end

-- ==========================================
-- CLEAN UP OLD RUN
-- ==========================================
local guiName = "AutoBuyerUI"
local oldGui = playerGui:FindFirstChild(guiName)
if oldGui then oldGui:Destroy() end

if env.AutoBuyerConnections then
	for _, c in pairs(env.AutoBuyerConnections) do c:Disconnect() end
end
env.AutoBuyerConnections = {}
env.AutoBuyerRunId = (env.AutoBuyerRunId or 0) + 1
local myRunId = env.AutoBuyerRunId

local running = false
local rebirthLimit = 0        -- 0 = rebirth buttons OFF

-- ==========================================
-- GUI
-- ==========================================
local screenGui = Instance.new("ScreenGui")
screenGui.Name = guiName
screenGui.ResetOnSpawn = false
screenGui.Parent = playerGui

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 240, 0, 250)
mainFrame.Position = UDim2.new(1, -260, 0, 20)
mainFrame.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
mainFrame.BorderSizePixel = 2
mainFrame.BorderColor3 = Color3.fromRGB(80, 80, 80)
mainFrame.Active = true
mainFrame.Parent = screenGui

local topBar = Instance.new("TextLabel")
topBar.Size = UDim2.new(1, 0, 0, 30)
topBar.BackgroundColor3 = Color3.fromRGB(20, 20, 20)
topBar.TextColor3 = Color3.fromRGB(200, 200, 200)
topBar.Text = "≡ Auto Buyer (drag) ≡"
topBar.Font = Enum.Font.SourceSansBold
topBar.TextSize = 16
topBar.Parent = mainFrame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(1, -20, 0, 45)
toggleButton.Position = UDim2.new(0, 10, 0, 40)
toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
toggleButton.TextColor3 = Color3.fromRGB(255, 255, 255)
toggleButton.TextScaled = true
toggleButton.Font = Enum.Font.SourceSansBold
toggleButton.Text = "OFF"
toggleButton.Parent = mainFrame

local rebirthBox = Instance.new("TextBox")
rebirthBox.Size = UDim2.new(1, -20, 0, 35)
rebirthBox.Position = UDim2.new(0, 10, 0, 92)
rebirthBox.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
rebirthBox.TextColor3 = Color3.fromRGB(255, 255, 0)
rebirthBox.PlaceholderColor3 = Color3.fromRGB(160, 160, 160)
rebirthBox.PlaceholderText = "Rebirths (0-" .. MAX_REBIRTH .. ", 0 = off)"
rebirthBox.Text = ""
rebirthBox.ClearTextOnFocus = false
rebirthBox.TextScaled = true
rebirthBox.Font = Enum.Font.SourceSansBold
rebirthBox.Parent = mainFrame

local testButton = Instance.new("TextButton")
testButton.Size = UDim2.new(1, -20, 0, 28)
testButton.Position = UDim2.new(0, 10, 0, 132)
testButton.BackgroundColor3 = Color3.fromRGB(60, 60, 120)
testButton.TextColor3 = Color3.fromRGB(255, 255, 255)
testButton.TextScaled = true
testButton.Font = Enum.Font.SourceSansBold
testButton.Text = "Run airdrop now (test)"
testButton.Parent = mainFrame

local statusLabel = Instance.new("TextLabel")
statusLabel.Size = UDim2.new(1, -20, 0, 35)
statusLabel.Position = UDim2.new(0, 10, 0, 165)
statusLabel.BackgroundTransparency = 1
statusLabel.TextColor3 = Color3.fromRGB(0, 255, 100)
statusLabel.TextScaled = true
statusLabel.Font = Enum.Font.SourceSans
statusLabel.Text = "Idle"
statusLabel.Parent = mainFrame

-- Local completion readout, populated from the game's PlayerGui.
local completionLabel = Instance.new("TextLabel")
completionLabel.Name = "CompletionLabel"
completionLabel.Size = UDim2.new(1, -20, 0, 22)
completionLabel.Position = UDim2.new(0, 10, 0, 201)
completionLabel.BackgroundTransparency = 1
completionLabel.TextColor3 = Color3.fromRGB(160, 220, 255)
completionLabel.Text = "Completion: --%"
completionLabel.TextXAlignment = Enum.TextXAlignment.Left
completionLabel.TextScaled = true
completionLabel.Font = Enum.Font.SourceSansBold
completionLabel.Parent = mainFrame

local completionBarBackground = Instance.new("Frame")
completionBarBackground.Name = "CompletionBarBackground"
completionBarBackground.Size = UDim2.new(1, -20, 0, 12)
completionBarBackground.Position = UDim2.new(0, 10, 0, 226)
completionBarBackground.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
completionBarBackground.BorderSizePixel = 0
completionBarBackground.ClipsDescendants = true
completionBarBackground.Parent = mainFrame

local completionBarCorner = Instance.new("UICorner")
completionBarCorner.CornerRadius = UDim.new(1, 0)
completionBarCorner.Parent = completionBarBackground

local completionBarFill = Instance.new("Frame")
completionBarFill.Name = "CompletionBarFill"
completionBarFill.Size = UDim2.new(0, 0, 1, 0)
completionBarFill.BackgroundColor3 = Color3.fromRGB(45, 220, 95)
completionBarFill.BorderSizePixel = 0
completionBarFill.Parent = completionBarBackground

local completionFillCorner = Instance.new("UICorner")
completionFillCorner.CornerRadius = UDim.new(1, 0)
completionFillCorner.Parent = completionBarFill

local completionPercent = nil
local completionEArmed = true
local completionEPressing = false
local completionEStatus = nil
local completionRequiredCash = REBIRTH_CONFIRM_MIN_CASH

local function setCompletionDisplay(percent)
	completionPercent = percent
	if percent == nil then
		completionLabel.Text = "Completion: --%"
		completionBarFill.Size = UDim2.new(0, 0, 1, 0)
		return
	end

	local clampedPercent = math.clamp(percent, 0, 100)
	if completionEPressing then
		completionLabel.Text = ("Completion: %g%% | %s"):format(clampedPercent, completionEStatus or "Rebirth pending")
	else
		completionLabel.Text = ("Completion: %g%%"):format(clampedPercent)
	end
	completionBarFill.Size = UDim2.new(clampedPercent / 100, 0, 1, 0)
end

local function setStatus(text)
	statusLabel.Text = text
end

-- Dragging
local dragging, dragInput, dragStart, startPos
table.insert(env.AutoBuyerConnections, topBar.InputBegan:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
		dragging = true
		dragStart = input.Position
		startPos = mainFrame.Position
		input.Changed:Connect(function()
			if input.UserInputState == Enum.UserInputState.End then dragging = false end
		end)
	end
end))
table.insert(env.AutoBuyerConnections, topBar.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
		dragInput = input
	end
end))
table.insert(env.AutoBuyerConnections, UserInputService.InputChanged:Connect(function(input)
	if input == dragInput and dragging then
		local delta = input.Position - dragStart
		mainFrame.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
	end
end))

-- ==========================================
-- PRICE / MONEY PARSING
-- ==========================================
local SUFFIX = { [""] = 1, k = 1e3, m = 1e6, b = 1e9, t = 1e12 }

local function parsePrice(text)
	local lower = string.lower(text)
	local num, suf = string.match(lower, "%$%s*([%d%.,]+)%s*([kmbt]?)")
	if num then
		num = string.gsub(num, ",", "")
		local n = tonumber(num)
		if n then return n * (SUFFIX[suf] or 1) end
	end
	if string.find(lower, "free") then return 0 end
	return nil
end

-- true only if the text is really shown on screen (hidden labels are ignored)
local function labelVisible(label, root)
	if label.TextTransparency >= 1 then return false end
	local cur = label
	while cur and cur ~= root do
		if cur:IsA("GuiObject") and not cur.Visible then return false end
		if cur:IsA("LayerCollector") and not cur.Enabled then return false end
		cur = cur.Parent
	end
	return true
end

-- Read "Completion 15%" from the game's local UI. Some games put the word and
-- percentage in separate labels, so also combine nearby ancestor text and use
-- the nearest percentage label as a fallback.
local function isCompletionTextObject(obj)
	return obj:IsA("TextLabel") or obj:IsA("TextButton") or obj:IsA("TextBox")
end

local function getCompletionText(obj)
	local ok, text = pcall(function() return obj.ContentText end)
	if not ok or not text or text == "" then
		text = obj.Text
	end
	return tostring(text or "")
end

local function parseCompletionPercent(text)
	local lower = string.lower(text)
	local _, completionEnd = string.find(lower, "completion", 1, true)
	if not completionEnd then return nil end
	local afterCompletion = string.sub(text, completionEnd + 1)
	local numberText = string.match(afterCompletion, "([%d]+%.?[%d]*)%s*%%")
	return numberText and tonumber(numberText) or nil
end

local function parseAnyPercent(text)
	local numberText = string.match(text, "([%d]+%.?[%d]*)%s*%%")
	return numberText and tonumber(numberText) or nil
end

local function combineCompletionText(root)
	local pieces = {}
	local function addText(obj)
		if isCompletionTextObject(obj) and not obj:IsDescendantOf(screenGui)
			and labelVisible(obj, playerGui) then
			local text = getCompletionText(obj)
			if text ~= "" then table.insert(pieces, text) end
		end
	end

	if isCompletionTextObject(root) then addText(root) end
	for _, child in ipairs(root:GetDescendants()) do addText(child) end
	return table.concat(pieces, " ")
end

local function completionLayerCollector(obj)
	local current = obj
	while current and current ~= playerGui do
		if current:IsA("LayerCollector") then return current end
		current = current.Parent
	end
	return nil
end

local function readCompletionPercent()
	local completionObjects = {}
	local percentObjects = {}

	for _, obj in ipairs(playerGui:GetDescendants()) do
		if isCompletionTextObject(obj) and not obj:IsDescendantOf(screenGui)
			and labelVisible(obj, playerGui) then
			local text = getCompletionText(obj)
			local lower = string.lower(text)

			if string.find(lower, "completion", 1, true) then
				local percent = parseCompletionPercent(text)
				if percent ~= nil then return percent end
				table.insert(completionObjects, obj)
			end

			local percent = parseAnyPercent(text)
			if percent ~= nil then
				table.insert(percentObjects, { object = obj, value = percent })
			end
		end
	end

	for _, completionObject in ipairs(completionObjects) do
		local scope = completionObject.Parent
		while scope and scope ~= playerGui do
			local percent = parseCompletionPercent(combineCompletionText(scope))
			if percent ~= nil then return percent end
			scope = scope.Parent
		end
	end

	-- Last resort for separate labels that don't share a text container.
	local nearestValue, nearestDistanceSquared = nil, math.huge
	for _, completionObject in ipairs(completionObjects) do
		local completionRoot = completionLayerCollector(completionObject)
		local completionCenter = completionObject.AbsolutePosition + completionObject.AbsoluteSize / 2
		for _, candidate in ipairs(percentObjects) do
			local percentObject = candidate.object
			if percentObject ~= completionObject
				and completionLayerCollector(percentObject) == completionRoot then
				local percentCenter = percentObject.AbsolutePosition + percentObject.AbsoluteSize / 2
				local delta = completionCenter - percentCenter
				local distanceSquared = delta.X * delta.X + delta.Y * delta.Y
				if distanceSquared < nearestDistanceSquared then
					nearestDistanceSquared = distanceSquared
					nearestValue = candidate.value
				end
			end
		end
	end
	if nearestValue ~= nil and nearestDistanceSquared <= 300 * 300 then
		return nearestValue
	end
	return nil
end

local lastCollectorPos = nil   -- set by the scanner, used to know which rebirth buttons are near your base
local lockedCollectorPart = nil -- FIX: once a Cash Collector is chosen we stick to it (no more flipping to the 2nd one)
local trackedBarrel = nil      -- tracked oil barrel; declared here so all movement helpers can check it
local barrelRecoveryPending = false
local barrelRecoveryTargetPart = nil
local barrelRecoveryTargetPos = nil
local barrelRecoveryAttempted = false

local function isBarrelCarried()
	local char = player.Character
	if not char then return false end

	local obj = trackedBarrel and trackedBarrel.obj
	if obj and obj.Parent then
		if obj:IsDescendantOf(char) then return true end

		-- Some games keep the barrel in Workspace and attach it to the character with a joint.
		local function isBarrelPart(part)
			return part ~= nil and (part == obj or part:IsDescendantOf(obj))
		end
		local function isCharacterPart(part)
			return part ~= nil and part:IsDescendantOf(char)
		end
		local function partForAttachment(attachment)
			local current = attachment and attachment.Parent
			while current and current ~= workspace do
				if current:IsA("BasePart") then return current end
				current = current.Parent
			end
			return nil
		end
		local function jointCarriesBarrel(joint)
			local part0, part1
			if joint:IsA("WeldConstraint") or joint:IsA("Weld") or joint:IsA("Motor6D") then
				part0, part1 = joint.Part0, joint.Part1
			elseif joint:IsA("AlignPosition") or joint:IsA("AlignOrientation") then
				part0 = partForAttachment(joint.Attachment0)
				part1 = partForAttachment(joint.Attachment1)
			end
			return (isBarrelPart(part0) and isCharacterPart(part1))
				or (isBarrelPart(part1) and isCharacterPart(part0))
		end
		local function hasCarryJoint(container)
			for _, item in ipairs(container:GetDescendants()) do
				if jointCarriesBarrel(item) then return true end
			end
			return false
		end

		if hasCarryJoint(obj) or hasCarryJoint(char) then return true end
	end

	-- Also detect a barrel Tool/Model already in the character (for example, after a script restart).
	for _, item in ipairs(char:GetChildren()) do
		if item:IsA("Tool") or item:IsA("Model") then
			local name = string.lower(item.Name)
			if string.find(name, "barrel", 1, true) or string.find(name, "oil", 1, true) then
				return true
			end
		end
	end

	return false
end

-- Remember a carried/tracked barrel if the character dies. After respawn, the
-- main loop will locate the dropped barrel from its floating "DESPAWN: ..." label and recover it.
local function watchCharacterForBarrelDeath(character)
	task.spawn(function()
		local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if not humanoid then return end

		local connection = humanoid.Died:Connect(function()
			local barrel = trackedBarrel
			if barrel or isBarrelCarried() then
				barrelRecoveryPending = true
				barrelRecoveryAttempted = false
				barrelRecoveryTargetPart = barrel and barrel.targetPart or nil
				barrelRecoveryTargetPos = nil
				if barrelRecoveryTargetPart and barrelRecoveryTargetPart.Parent then
					pcall(function() barrelRecoveryTargetPos = barrelRecoveryTargetPart.Position end)
				end
				trackedBarrel = nil
				setStatus("Died with barrel; scanning for the fallen barrel (DESPAWN label)...")
				dbg("Character died with a barrel pending; will search DESPAWN labels")
			end
		end)
		table.insert(env.AutoBuyerConnections, connection)
	end)
end

if player.Character then
	watchCharacterForBarrelDeath(player.Character)
end
table.insert(env.AutoBuyerConnections, player.CharacterAdded:Connect(watchCharacterForBarrelDeath))

-- Money reader
local function getMoney()
	local leaderstats = player:FindFirstChild("leaderstats")
	if leaderstats then
		for _, stat in pairs(leaderstats:GetChildren()) do
			local n = string.lower(stat.Name)
			if (string.find(n, "cash", 1, true) or string.find(n, "money", 1, true) or string.find(n, "coin", 1, true)) then
				local v = tonumber(stat.Value)
				if v then return v end
			end
		end
	end

	local preferred, biggest = nil, nil
	for _, obj in pairs(playerGui:GetDescendants()) do
		if obj:IsA("TextLabel") and not obj:IsDescendantOf(screenGui)
			and not obj:FindFirstAncestorWhichIsA("BillboardGui")
			and not obj:FindFirstAncestorWhichIsA("SurfaceGui")
			and labelVisible(obj, playerGui) then
			local txt = obj.Text
			if string.match(txt, "^%s*%$%s*%d") then
				local n = parsePrice(txt)
				if n then
					-- labels called Cash / Money are the best guess
					local isMoneyName = false
					local cur = obj
					while cur and cur ~= playerGui do
						local nm = string.lower(cur.Name)
						if string.find(nm, "cash", 1, true) or string.find(nm, "money", 1, true) then
							isMoneyName = true
							break
						end
						cur = cur.Parent
					end
					if isMoneyName and (not preferred or n > preferred) then preferred = n end
					if not biggest or n > biggest then biggest = n end
				end
			end
		end
	end
	return preferred or biggest
end

-- ==========================================
-- SCANNER
-- ==========================================
-- Resolve GUI Adornee/parent values to a BasePart. BillboardGui Adornee may be an
-- Attachment or Model, not only a BasePart; support those so the scanner doesn't skip it.
local function resolvePurchaseTargetPart(gui)
	local function asPart(inst)
		if not inst then return nil end
		if inst:IsA("BasePart") then return inst end

		if inst:IsA("Attachment") then
			local current = inst.Parent
			while current and current ~= workspace do
				if current:IsA("BasePart") then return current end
				current = current.Parent
			end
		elseif inst:IsA("Model") then
			return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true)
		elseif inst:IsA("Folder") then
			return inst:FindFirstChildWhichIsA("BasePart", true)
		end

		return nil
	end

	return asPart(gui.Adornee) or asPart(gui.Parent)
end

local function scan()
	local collector = nil
	local collectorCands = {}   -- FIX: collect ALL "Cash to collect" candidates, pick one at the end
	local buttons = {}
	local savedParts = {}

	local function checkGuiObject(obj)
		if not (obj:IsA("BillboardGui") or obj:IsA("SurfaceGui")) then return end

		local targetPart = resolvePurchaseTargetPart(obj)
		if not (targetPart and targetPart:IsA("BasePart")) or savedParts[targetPart] then return end

		-- ownership check
		local currentParent = targetPart.Parent
		local belongsToMe = false
		while currentParent and currentParent ~= workspace do
			local ownerValue = currentParent:FindFirstChild("Owner")
			if (ownerValue and ownerValue:IsA("ObjectValue") and ownerValue.Value == player) or currentParent.Name == player.Name then
				belongsToMe = true
				break
			end
			currentParent = currentParent.Parent
		end
		if not belongsToMe then return end

		local fullText = ""
		local hasPrice = false
		local isExcluded = false
		local seenText = {}

		for _, child in pairs(obj:GetDescendants()) do
			if (child:IsA("TextLabel") or child:IsA("TextButton")) and labelVisible(child, obj) then
				local rawText = child.ContentText
				if not rawText or rawText == "" then rawText = child.Text end

				if rawText ~= "" and rawText ~= "Label" then
					local cleanText = string.gsub(rawText, "\n", " ")
					local lowerText = string.lower(cleanText)

					if not seenText[lowerText] then
						seenText[lowerText] = true
						fullText = fullText .. cleanText .. " "
					end

					if string.find(lowerText, "%$") or string.find(lowerText, "free") then
						hasPrice = true
					end
					if string.find(lowerText, "/s") or string.find(lowerText, "r%$") or string.find(lowerText, "robux") or string.find(lowerText, "%+") then
						isExcluded = true
					end
				end
			end
		end

		local finalLowerText = string.lower(fullText)
		for _, bannedWord in ipairs(BANNED_WORDS) do
			if string.find(finalLowerText, bannedWord) then
				isExcluded = true
				break
			end
		end

		if string.len(fullText) > 2 and hasPrice and not isExcluded then
			savedParts[targetPart] = true

			if string.find(finalLowerText, "cash to collect") then
				-- FIX: just remember it, the choice is made after the scan
				table.insert(collectorCands, { part = targetPart, gui = obj, text = fullText, isCollector = true })
			else
				local price = parsePrice(fullText)
				if price then
					table.insert(buttons, { part = targetPart, gui = obj, text = fullText, price = price })
				end
			end
		end
	end

	-- small pauses so a big map does not freeze the game
	local n = 0
	for _, obj in pairs(workspace:GetDescendants()) do
		checkGuiObject(obj)
		n = n + 1
		if n % 3000 == 0 then task.wait() end
	end
	for _, obj in pairs(playerGui:GetDescendants()) do
		if not obj:IsDescendantOf(screenGui) then checkGuiObject(obj) end
	end

	-- FIX: pick the collector. Keep the locked one if it still exists, else lock the one closest to the player.
	if lockedCollectorPart and lockedCollectorPart.Parent then
		for _, c in ipairs(collectorCands) do
			if c.part == lockedCollectorPart then collector = c break end
		end
	end
	if not collector and #collectorCands > 0 then
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
		local bestD
		for _, c in ipairs(collectorCands) do
			local d = root and (c.part.Position - root.Position).Magnitude or 0
			if not bestD or d < bestD then collector, bestD = c, d end
		end
		if collector then
			lockedCollectorPart = collector.part
			dbg("Locked collector:", collector.part:GetFullName())
		end
	end
	if collector then lastCollectorPos = collector.part.Position end

	return collector, buttons
end

-- ==========================================
-- TELEPORT
-- ==========================================
local function teleportTo(part, isCollector)
	if barrelRecoveryPending or isBarrelCarried() or trackedBarrel then
		setStatus("Barrel pending recovery/exchange; blocking teleport")
		dbg("Blocked teleport while barrel is tracked or carried")
		return false
	end

	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	if not (rootPart and part and part.Parent) then return false end

	local offset = CFrame.new(0, 2.5, 0)
	if isCollector then offset = CFrame.new(0, 2.5, 4) end

	rootPart.Anchored = true
	char:PivotTo(part.CFrame * offset)
	task.wait(0.3)
	rootPart.Anchored = false
	return true
end

local function isAlive(btn)
	return btn.part and btn.part.Parent and btn.gui and btn.gui.Parent
end

-- ==========================================
-- AIRDROP HANDLING
-- ==========================================
local VirtualInputManager = game:GetService("VirtualInputManager")
local RunService = game:GetService("RunService")
local HOLD_TIME = 3          -- seconds to hold E
local SEARCH_TIMEOUT = 10    -- seconds to keep searching for the barrel / airdrop
local FLY_SPEED = 40         -- FIX: was 100. Slower = the game is less likely to reset you (and the barrel)
local RECENT_WINDOW = 90     -- an object counts as "new" if it appeared in the last 90 s
local airdropPending = false
local handlingAirdrop = false
local lastAirdropEnd = 0
-- trackedBarrel is declared with the scanner state above; it stores { obj = Model/Part }.

local SCAN_INTERVAL = 6       -- seconds between automatic scans for the barrel / airdrop
local SCAN_CHUNK = 1500        -- objects checked before pausing one frame (keeps the game smooth)
local AIRDROP_COOLDOWN = 20    -- seconds to wait after a finished run before another auto trigger

local function triggerAirdrop(reason, ignoreCooldown)
	if not running or airdropPending or handlingAirdrop or completionEPressing then return end
	if not ignoreCooldown and os.clock() - lastAirdropEnd < AIRDROP_COOLDOWN then return end
	airdropPending = true
	setStatus("Airdrop found (" .. reason .. ")")
end

table.insert(env.AutoBuyerConnections, testButton.MouseButton1Click:Connect(function()
	if running then
		triggerAirdrop("manual", true)
	else
		setStatus("Turn ON first")
	end
end))

-- true if a REAL "Oil ... studs" or "Airdrop ... studs" floating label exists right now.
-- It works through the objects in small chunks and pauses between them, so it never freezes the game.
local function realTargetExists()
	local function scanRoot(root)
		local list = root:GetDescendants()
		for i, obj in ipairs(list) do
			if obj:IsA("BillboardGui") and not obj:IsDescendantOf(screenGui) then
				local text = ""
				for _, c in ipairs(obj:GetDescendants()) do
					if c:IsA("TextLabel") or c:IsA("TextButton") then
						local raw = c.ContentText
						if not raw or raw == "" then raw = c.Text end
						text = text .. raw .. " "
					end
				end
				local lower = string.lower(text)
				if string.find(lower, "studs", 1, true)
					and (string.find(lower, "airdrop", 1, true) or string.find(lower, "oil", 1, true)) then
					return true
				end
			end
			if i % SCAN_CHUNK == 0 then task.wait() end
		end
		return false
	end
	return scanRoot(playerGui) or scanRoot(workspace)
end

-- automatic scan every few seconds (only while the script is ON and idle)
task.spawn(function()
	while env.AutoBuyerRunId == myRunId do
		task.wait(SCAN_INTERVAL)
		if running and not airdropPending and not handlingAirdrop and not completionEPressing
			and os.clock() - lastAirdropEnd >= AIRDROP_COOLDOWN then
			local ok, found = pcall(realTargetExists)
			if ok and found then triggerAirdrop("auto scan") end
		end
	end
end)

-- The barrel and the airdrop each have a floating label in the air: "Oil 6.14k studs" /
-- "Airdrop 3.92k studs". The decoy "Oil Barrel" materials have NO such label, so we look for the label.
local function parseStuds(text)
	local num, suf = string.match(string.lower(text), "([%d%.,]+)%s*([kmb]?)%s*studs")
	if not num then return nil end
	num = string.gsub(num, ",", "")
	local n = tonumber(num)
	if not n then return nil end
	return n * (SUFFIX[suf] or 1)
end

local function resolveGuiPart(obj)
	local a = obj.Adornee
	if a then
		if a:IsA("BasePart") then return a end
		if a:IsA("Attachment") and a.Parent and a.Parent:IsA("BasePart") then return a.Parent end
		if a:IsA("Model") then return a.PrimaryPart or a:FindFirstChildWhichIsA("BasePart", true) end
	end
	local par = obj.Parent
	if par then
		if par:IsA("BasePart") then return par end
		if par:IsA("Attachment") and par.Parent and par.Parent:IsA("BasePart") then return par.Parent end
		if par:IsA("Model") or par:IsA("Folder") then return par:FindFirstChildWhichIsA("BasePart", true) end
	end
	return nil
end

local function promptPosition(prompt)
	local par = prompt.Parent
	if par and par:IsA("BasePart") then return par.Position end
	if par and par:IsA("Attachment") then return par.WorldPosition end
	if par and par:IsA("Model") then return par:GetPivot().Position end
	return nil
end

-- the E prompt (hold E) that belongs to the thing the label is attached to
local function findPromptFor(part)
	local cur = part
	for _ = 1, 3 do
		if not cur or cur == workspace then break end
		local best, bestD
		for _, d in pairs(cur:GetDescendants()) do
			if d:IsA("ProximityPrompt") then
				local pp = promptPosition(d)
				if pp then
					local dist = (pp - part.Position).Magnitude
					if dist <= 40 and (not bestD or dist < bestD) then best, bestD = d, dist end
				end
			end
		end
		if best then return best end
		cur = cur.Parent
	end
	return nil
end

-- FIX: never returns your own prompts or the prompt of the barrel you are carrying
-- (pressing E on the barrel's own prompt DROPS it - that was making the barrel "disappear")
local function nearestPromptTo(pos, radius)
	local char = player.Character
	local best, bestD
	for _, obj in pairs(workspace:GetDescendants()) do
		if obj:IsA("ProximityPrompt") and obj.Enabled
			and not (char and obj:IsDescendantOf(char))
			and not (trackedBarrel and trackedBarrel.obj and obj:IsDescendantOf(trackedBarrel.obj)) then
			local pp = promptPosition(obj)
			if pp then
				local d = (pp - pos).Magnitude
				if d <= radius and (not bestD or d < bestD) then best, bestD = obj, d end
			end
		end
	end
	return best
end

-- ==========================================
-- FALLEN BARREL SEARCH (NEW)
-- A barrel that was picked up / dropped / left behind shows a floating label
-- "DESPAWN: 595" (the timer counts down from about 600). Other loot on the map also has
-- "DESPAWN: 30" labels, so only timers >= DESPAWN_MIN_SECONDS count as the barrel.
-- If we know where the barrel was last seen, the closest label to that spot wins.
-- ==========================================
local function findDespawnTargets()
	local found, seen = {}, {}
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local refPos = barrelRecoveryTargetPos

	local function check(obj)
		if not (obj:IsA("BillboardGui") or obj:IsA("SurfaceGui")) then return end
		if obj:IsDescendantOf(screenGui) then return end

		local text = ""
		for _, c in ipairs(obj:GetDescendants()) do
			if c:IsA("TextLabel") or c:IsA("TextButton") then
				local raw = c.ContentText
				if not raw or raw == "" then raw = c.Text end
				if raw ~= "" then text = text .. string.gsub(raw, "\n", " ") .. " " end
			end
		end

		local lower = string.lower(text)
		local secs = tonumber(string.match(lower, "despawn%s*:?%s*(%d+)"))
		if not secs or secs < DESPAWN_MIN_SECONDS then return end   -- not the barrel (e.g. DESPAWN: 30)

		local part = resolveGuiPart(obj)
		if not part or not part.Parent or seen[part] then return end
		if char and part:IsDescendantOf(char) then return end        -- that one is on us, not fallen
		seen[part] = true

		table.insert(found, {
			part = part,
			prompt = findPromptFor(part),
			despawn = secs,
			dist = root and (part.Position - root.Position).Magnitude or math.huge,
			refDist = refPos and (part.Position - refPos).Magnitude or nil,
			text = text,
		})
	end

	local n = 0
	for _, obj in pairs(workspace:GetDescendants()) do
		check(obj)
		n = n + 1
		if n % 3000 == 0 then task.wait() end
	end
	for _, obj in pairs(playerGui:GetDescendants()) do check(obj) end

	table.sort(found, function(x, y)
		if x.refDist and y.refDist then return x.refDist < y.refDist end
		return x.dist < y.dist
	end)
	return found
end

-- kind = "oil", "airdrop" or "despawn" (fallen barrel, found through its DESPAWN label)
local function findFloatingTargets(kind)
	if kind == "despawn" then
		local list = findDespawnTargets()
		if #list == 0 then
			-- old way as a backup: the "Oil ... studs" label (only exists while the barrel is not picked up)
			list = findFloatingTargets("oil")
		end
		return list
	end

	local found, seen = {}, {}
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")

	local function check(obj)
		if not obj:IsA("BillboardGui") then return end
		if obj:IsDescendantOf(screenGui) then return end

		local text = ""
		for _, c in pairs(obj:GetDescendants()) do
			if c:IsA("TextLabel") or c:IsA("TextButton") then
				local raw = c.ContentText
				if not raw or raw == "" then raw = c.Text end
				if raw ~= "" then text = text .. string.gsub(raw, "\n", " ") .. " " end
			end
		end

		local lower = string.lower(text)
		if not string.find(lower, "studs", 1, true) then return end
		local thisKind
		if string.find(lower, "airdrop", 1, true) then
			thisKind = "airdrop"
		elseif string.find(lower, "oil", 1, true) then
			thisKind = "oil"
		else
			return
		end
		if thisKind ~= kind then return end

		local part = resolveGuiPart(obj)
		if not part or seen[part] then return end
		seen[part] = true

		table.insert(found, {
			part = part,
			prompt = findPromptFor(part),
			labelDist = parseStuds(lower),
			dist = root and (part.Position - root.Position).Magnitude or math.huge,
			text = text,
		})
	end

	local n = 0
	for _, obj in pairs(workspace:GetDescendants()) do
		check(obj)
		n = n + 1
		if n % 3000 == 0 then task.wait() end
	end
	for _, obj in pairs(playerGui:GetDescendants()) do check(obj) end

	-- nearest first (distance shown on the label)
	table.sort(found, function(x, y)
		return (x.labelDist or x.dist) < (y.labelDist or y.dist)
	end)
	return found
end

local function holdE(seconds, prompt)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")

	-- no prompt given (or it vanished): use the nearest enabled prompt around us
	if not (prompt and prompt.Parent) and root then
		prompt = nearestPromptTo(root.Position, 40)
	end

	local actionBefore
	if prompt then
		actionBefore = prompt.ActionText
		seconds = math.max(seconds, (prompt.HoldDuration or 0) + 0.5)
		pcall(function() prompt.RequiresLineOfSight = false end)

		-- too far for the prompt to work? step a little closer (only for short distances)
		local pp = promptPosition(prompt)
		if pp and root then
			local d = (pp - root.Position).Magnitude
			if d > (prompt.MaxActivationDistance - 1) and d <= 60 then
				char:PivotTo(CFrame.new(pp + Vector3.new(0, 2.5, 0)))
				task.wait(0.3)
			end
			dbg(("Holding E %.1fs | prompt %s | hold=%s | dist=%d"):format(seconds, prompt:GetFullName(), tostring(prompt.HoldDuration), (pp - root.Position).Magnitude))
		end
	else
		dbg("Holding E: NO prompt found nearby, keyboard only")
	end

	-- 1) hold the prompt directly (works even if the game window has no keyboard focus)
	if prompt then pcall(function() prompt:InputHoldBegin() end) end
	-- 2) hold the real E key (two different ways, whichever the executor supports)
	pcall(function() VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game) end)
	if keypress then pcall(keypress, 0x45) end

	local t0 = os.clock()
	while os.clock() - t0 < seconds and running do
		task.wait(0.1)
	end

	if prompt then pcall(function() prompt:InputHoldEnd() end) end
	pcall(function() VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game) end)
	if keyrelease then pcall(keyrelease, 0x45) end
	task.wait(0.3)

	-- 3) backup: if the prompt is STILL there and unchanged (so the pickup did not happen), fire it instantly
	-- FIX: never while we are carrying the barrel (it could drop it)
	if prompt and fireproximityprompt and prompt.Parent and prompt.Enabled
		and prompt.ActionText == actionBefore and not trackedBarrel then
		local oldHold = prompt.HoldDuration
		pcall(function() prompt.HoldDuration = 0 end)
		pcall(fireproximityprompt, prompt)
		pcall(function() prompt.HoldDuration = oldHold end)
	end
end

-- Slow noclip flight through walls. The character is NOT anchored (anchoring / teleporting
-- can make the game drop what you carry), it is pushed with a BodyVelocity instead.
local function flyTo(targetCFrame, label)
	if (barrelRecoveryPending or isBarrelCarried() or trackedBarrel)
		and label ~= "Exchange" and label ~= "Cash Collector" then
		setStatus("Barrel pending recovery/exchange; blocking movement to " .. label)
		dbg("Blocked flight while barrel is tracked or carried:", label)
		return false
	end

	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	local humanoid = char and char:FindFirstChildOfClass("Humanoid")
	if not rootPart then return false end

	local noclipConn = RunService.Stepped:Connect(function()
		for _, p in ipairs(char:GetDescendants()) do
			if p:IsA("BasePart") then p.CanCollide = false end
		end
	end)

	local bv = Instance.new("BodyVelocity")
	bv.MaxForce = Vector3.new(1e9, 1e9, 1e9)
	bv.Velocity = Vector3.zero
	bv.Parent = rootPart

	local bg = Instance.new("BodyGyro")
	bg.MaxTorque = Vector3.new(1e9, 1e9, 1e9)
	bg.P = 1e5
	bg.CFrame = CFrame.new(rootPart.Position, rootPart.Position + rootPart.CFrame.LookVector * Vector3.new(1, 0, 1) + Vector3.new(0, 0.001, 0))
	bg.Parent = rootPart

	if humanoid then humanoid.PlatformStand = true end

	local goal = targetCFrame.Position
	local startDist = (goal - rootPart.Position).Magnitude
	local timeout = os.clock() + (startDist / FLY_SPEED) + 15
	local lastStatus = 0

	while running and os.clock() < timeout and rootPart.Parent do
		local diff = goal - rootPart.Position
		local dist = diff.Magnitude
		if dist < 3 then break end

		-- full speed, slows down near the goal
		bv.Velocity = diff.Unit * math.min(FLY_SPEED, dist * 4)
		RunService.Heartbeat:Wait()

		if os.clock() - lastStatus > 0.25 then
			lastStatus = os.clock()
			setStatus(("Flying to %s: %d studs"):format(label, dist))
		end
	end

	bv:Destroy()
	bg:Destroy()
	if humanoid then humanoid.PlatformStand = false end
	if rootPart.Parent then
		rootPart.AssemblyLinearVelocity = Vector3.zero
	end
	noclipConn:Disconnect()
	return true
end

-- the thing that actually gets picked up (model if small, else the part the prompt sits on)
local function trackObjFor(prompt, part)
	local base = prompt and prompt.Parent or part
	if base and base:IsA("Attachment") then base = base.Parent end
	if not base then return part end
	local model = base:IsA("Model") and base or base:FindFirstAncestorWhichIsA("Model")
	if model and model ~= workspace and #model:GetDescendants() < 60 then return model end
	return base
end

local function objPosition(obj)
	if obj:IsA("Model") then return obj:GetPivot().Position end
	return obj.Position
end

-- teleport (used to GET to the barrel / airdrop / dropped barrel; flying is only used while carrying)
local function tpToPos(pos, label)
	if isBarrelCarried() then
		setStatus("Carrying barrel; exchange it before teleporting")
		dbg("Blocked teleport while carrying the barrel:", label)
		return false
	end

	pcall(function() player:RequestStreamAroundAsync(pos) end)
	task.wait(0.5)
	local char = player.Character
	local rootPart = char and char:FindFirstChild("HumanoidRootPart")
	if not rootPart then return false end
	setStatus("Teleporting to " .. label)
	rootPart.Anchored = true
	char:PivotTo(CFrame.new(pos + Vector3.new(0, 3, 0)))
	task.wait(0.5)
	rootPart.Anchored = false
	return true
end

local function visitTarget(label, kind, allowBarrelRecovery)
	if not allowBarrelRecovery and (barrelRecoveryPending or isBarrelCarried() or trackedBarrel) then
		setStatus("Barrel pending recovery/exchange; skipping " .. label)
		dbg("Skipped target while barrel is pending:", label)
		return nil
	end

	local characterAtStart = player.Character
	local deadline = os.clock() + SEARCH_TIMEOUT
	local found
	repeat
		found = findFloatingTargets(kind)
		if #found == 0 then task.wait(0.5) end
	until #found > 0 or os.clock() > deadline or not running

	if #found == 0 then
		dbg(label, "NOT FOUND (no floating '" .. kind .. "' label)")
		setStatus(label .. " not found")
		task.wait(1)
		return nil
	end

	dbg(label, "labels found:", #found)
	for i = 1, math.min(3, #found) do
		local f = found[i]
		dbg(("  #%d prompt=%s label=%s despawn=%s dist=%d  %s"):format(i, tostring(f.prompt ~= nil), tostring(f.labelDist), tostring(f.despawn), f.dist == math.huge and -1 or f.dist, f.part:GetFullName()))
	end

	local target = found[1]
	local goal = target.part.Position
	if target.prompt then goal = promptPosition(target.prompt) or goal end

	-- teleport there (loads the area first)
	if not tpToPos(goal, label) then return nil end
	if not running then return nil end
	task.wait(1)   -- let the area load in

	-- the label floats in the air, the real E prompt is on the item itself
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local prompt = target.prompt
	if not (prompt and prompt.Parent) and root then
		prompt = nearestPromptTo(root.Position, 40)
	end
	if prompt and root then
		local pp = promptPosition(prompt)
		if pp and (pp - root.Position).Magnitude > 6 then
			if not tpToPos(pp, label) then return nil end
			if not running then return nil end
			task.wait(0.4)
		end
	else
		dbg(label, "no E prompt found near the label - holding E anyway")
	end

	setStatus("Holding E (" .. label .. ")")
	holdE(HOLD_TIME, prompt)

	-- Remember the barrel: after pickup its floating label changes, so the scan can not find it anymore.
	if kind == "oil" or kind == "despawn" then
		local trackedObject = trackObjFor(prompt, target.part)
		trackedBarrel = { obj = trackedObject, targetPart = target.part }
		dbg("Tracking barrel object:", trackedObject:GetFullName())

		-- If death/respawn happened during the pickup attempt, switch to UI-based recovery.
		if characterAtStart ~= player.Character then
			barrelRecoveryPending = true
			barrelRecoveryAttempted = false
			barrelRecoveryTargetPart = target.part
			barrelRecoveryTargetPos = target.part.Parent and target.part.Position or nil
			trackedBarrel = nil
			setStatus("Died during pickup; scanning for the fallen barrel...")
		end
	end

	return target.part
end

local function belongsToMe(part)
	local currentParent = part.Parent
	while currentParent and currentParent ~= workspace do
		local ownerValue = currentParent:FindFirstChild("Owner")
		if (ownerValue and ownerValue:IsA("ObjectValue") and ownerValue.Value == player) or currentParent.Name == player.Name then
			return true
		end
		currentParent = currentParent.Parent
	end
	return false
end

-- Finds the Oil Exchange in your base. It tries several ways, since the reference text
-- "$100,000 PARTS $100,000 OIL EXCHANGE" is a price-bearing purchase label, not the target:
--   1) a non-price floating/surface label containing both "oil" and "exchange"
--   2) a non-purchase hold-E prompt containing "exchange" (some prompts omit "oil")
--   3) a part / model with "exchange" in its name (purchase buttons are filtered)
--   4) if no exchanger candidate exists, the floating "Resource Collection ... studs" UI
-- Best pick: has an E prompt > is in your tycoon > is not a buy pad > closest to you.
local function findExchange(refPos)
	local cands, seen = {}, {}
	local priceBearingExchangePads = {}

	-- Match the reference label/name "Parts ... Oil Exchange". The screenshot text
	-- "$100,000 PARTS $100,000 OIL EXCHANGE" identifies a price-bearing purchase pad,
	-- not the physical exchanger.
	local function isOilExchangeText(text)
		local lower = string.lower(text or "")
		return string.find(lower, "oil", 1, true) ~= nil
			and string.find(lower, "exchange", 1, true) ~= nil
	end

	local function hasExchangeText(text)
		return string.find(string.lower(text or ""), "exchange", 1, true) ~= nil
	end

	local function hasPurchaseCue(text)
		local lower = string.lower(text or "")
		return string.find(lower, "$", 1, true) ~= nil
			or string.find(lower, "buy", 1, true) ~= nil
			or string.find(lower, "purchase", 1, true) ~= nil
			or string.find(lower, "unlock", 1, true) ~= nil
			or string.find(lower, "cost", 1, true) ~= nil
	end

	local function partOf(inst)
		if inst:IsA("BasePart") then return inst end
		if inst:IsA("Attachment") and inst.Parent and inst.Parent:IsA("BasePart") then return inst.Parent end
		if inst:IsA("Model") then return inst.PrimaryPart or inst:FindFirstChildWhichIsA("BasePart", true) end
		return nil
	end

	local function add(part, prompt, isBuyPad)
		if not part then return end
		local targetPrompt = prompt or findPromptFor(part)
		if targetPrompt and hasPurchaseCue(targetPrompt.ActionText .. " " .. targetPrompt.ObjectText) then return end
		if seen[part] then return end
		seen[part] = true
		table.insert(cands, {
			part = part,
			prompt = targetPrompt,
			owned = belongsToMe(part),
			buyPad = isBuyPad,
			dist = (part.Position - refPos).Magnitude,
		})
	end

	local function scanList(list)
		for i, obj in ipairs(list) do
			if obj:IsA("BillboardGui") or obj:IsA("SurfaceGui") then
				local text = ""
				for _, c in ipairs(obj:GetDescendants()) do
					if c:IsA("TextLabel") or c:IsA("TextButton") then
						local raw = c.ContentText
						if not raw or raw == "" then raw = c.Text end
						text = text .. raw .. " "
					end
				end
				local lower = string.lower((string.gsub(text, "\n", " ")))
				local hasPrice = string.find(lower, "$", 1, true) ~= nil
				if isOilExchangeText(lower) then
					local part = resolveGuiPart(obj)
					if hasPrice then
						-- Exclude this purchase pad even if its prompt/model name also says "Oil Exchange".
						if part then priceBearingExchangePads[part] = true end
					else
						add(part, nil, false)
					end
				end

			elseif obj:IsA("ProximityPrompt") then
				local txt = string.lower(obj.ActionText .. " " .. obj.ObjectText)
				local names, cur = "", obj.Parent
				for _ = 1, 3 do
					if cur and cur ~= workspace then
						names = names .. " " .. string.lower(cur.Name)
						cur = cur.Parent
					end
				end
				local combinedText = txt .. " " .. names
				-- Some exchanger prompts are simply named "Exchange"; ownership/distance
				-- and purchase-word filtering distinguish them from the price button.
				if hasExchangeText(combinedText) and not hasPurchaseCue(combinedText) then
					add(partOf(obj.Parent), obj, false)
				end

			elseif (obj:IsA("BasePart") or obj:IsA("Model"))
				and hasExchangeText(obj.Name) and not hasPurchaseCue(obj.Name) then
				add(partOf(obj), nil, false)
			end

			if i % 2000 == 0 then task.wait() end
		end
	end

	scanList(workspace:GetDescendants())
	scanList(playerGui:GetDescendants())

	-- ignore far away ones that are not in your tycoon (other players' bases)
	local good = {}
	for _, c in ipairs(cands) do
		if not priceBearingExchangePads[c.part] and (c.owned or c.dist <= 500) then
			table.insert(good, c)
		end
	end

	table.sort(good, function(x, y)
		if (x.prompt ~= nil) ~= (y.prompt ~= nil) then return x.prompt ~= nil end
		if x.owned ~= y.owned then return x.owned end
		if x.buyPad ~= y.buyPad then return not x.buyPad end
		return x.dist < y.dist
	end)
	if good[1] then return good[1] end

	-- Fallback: if no physical Oil Exchange candidate is available, use the
	-- floating "Resource Collection ... studs" marker shown in the reference image.
	local fallback, fallbackDistance
	local fallbackSeen = {}
	local function scanResourceCollection(root)
		local list = root:GetDescendants()
		for i, obj in ipairs(list) do
			if (obj:IsA("BillboardGui") or obj:IsA("SurfaceGui"))
				and obj.Enabled and not obj:IsDescendantOf(screenGui) then
				local text = ""
				for _, label in ipairs(obj:GetDescendants()) do
					if (label:IsA("TextLabel") or label:IsA("TextButton"))
						and labelVisible(label, obj) then
						local raw = label.ContentText
						if not raw or raw == "" then raw = label.Text end
						text = text .. raw .. " "
					end
				end
				local lower = string.lower((string.gsub(text, "\n", " ")))
				if string.find(lower, "resource collection", 1, true)
					and string.find(lower, "studs", 1, true) then
					local part = resolveGuiPart(obj)
					if part and not fallbackSeen[part] then
						fallbackSeen[part] = true
						local labelDistance = parseStuds(lower)
						-- Anchor fallback ranking to the remembered Cash Collector, not the
						-- changing distance printed in the floating UI.
						local collectionOrigin = lastCollectorPos or refPos
						local worldDistance = (part.Position - collectionOrigin).Magnitude
						local sortDistance = worldDistance
						if not fallbackDistance or sortDistance < fallbackDistance then
							fallbackDistance = sortDistance
							fallback = {
								part = part,
								prompt = findPromptFor(part),
								owned = belongsToMe(part),
								buyPad = false,
								dist = worldDistance,
								labelDist = labelDistance,
								resourceFallback = true,
							}
						end
					end
				end
			end
			if i % 2000 == 0 then task.wait() end
		end
	end

	scanResourceCollection(workspace)
	scanResourceCollection(playerGui)
	return fallback
end

-- true if we picked a barrel up earlier, it still exists, but it is lying far away from us (dropped)
local function isBarrelDropped()
	local b = trackedBarrel
	if not (b and b.obj and b.obj.Parent) then return false end   -- gone = exchanged / despawned
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return false end
	if b.obj:IsDescendantOf(char) then return false end            -- carried
	return (objPosition(b.obj) - root.Position).Magnitude > 15
end

-- if the barrel was dropped on the way: go back to it and pick it up again
local function recoverBarrel()
	for _ = 1, 3 do
		if not running or not isBarrelDropped() then return end
		local pos = objPosition(trackedBarrel.obj)
		dbg("Barrel was dropped, picking it up again at", tostring(pos))
		setStatus("Barrel dropped! Picking up again...")
		tpToPos(pos, "dropped barrel")
		if not running then return end
		task.wait(0.8)
		local char = player.Character
		local root = char and char:FindFirstChild("HumanoidRootPart")
		-- the dropped barrel is NOT carried now, so its prompt is the one we want here
		local prompt = nil
		if root then
			local best, bestD
			for _, d in pairs(trackedBarrel.obj:GetDescendants()) do
				if d:IsA("ProximityPrompt") and d.Enabled then
					local pp = promptPosition(d)
					if pp then
						local dist = (pp - root.Position).Magnitude
						if dist <= 25 and (not bestD or dist < bestD) then best, bestD = d, dist end
					end
				end
			end
			prompt = best
		end
		-- while recovering, do not let the carry-protection block the pickup fallback
		local saved = trackedBarrel
		trackedBarrel = nil
		holdE(HOLD_TIME, prompt)
		trackedBarrel = saved
		task.wait(0.6)
	end
end

local function visitExchange()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not root then return end

	-- If a tracked barrel was dropped, recover it before travelling back to base.
	if isBarrelDropped() then
		recoverBarrel()
		if not running then return end
		if isBarrelDropped() then
			setStatus("Barrel still dropped; recovering before Exchange")
			return
		end
	end

	-- When delivering a barrel, return to the remembered Cash Collector first so
	-- the base is streamed in; then search for the physical Oil Exchange nearby.
	local barrelPending = barrelRecoveryPending or trackedBarrel ~= nil or isBarrelCarried()
	if barrelPending then
		if lockedCollectorPart and lockedCollectorPart.Parent then
			lastCollectorPos = lockedCollectorPart.Position
		end
		if not lastCollectorPos then
			pcall(scan)
		end

		local collectorPos = lastCollectorPos
		if collectorPos then
			pcall(function() player:RequestStreamAroundAsync(collectorPos) end)
			setStatus("Returning to remembered Cash Collector...")
			local collectorCFrame = CFrame.new(collectorPos + Vector3.new(0, 3, 4))
			if not flyTo(collectorCFrame, "Cash Collector") then return end
			if not running then return end
			task.wait(1)
			char = player.Character
			root = char and char:FindFirstChild("HumanoidRootPart")
			if not root then return end
		else
			dbg("No remembered Cash Collector position; searching for the Oil Exchange from here")
		end
	end

	setStatus("Searching for the Oil Exchange near the Cash Collector...")
	local cand
	local deadline = os.clock() + 8
	repeat
		local ok, result = pcall(findExchange, root.Position)
		cand = ok and result or nil
		if not cand then task.wait(1) end
	until cand or os.clock() > deadline or not running

	if not cand then
		dbg("Oil Exchange and Resource Collection fallback NOT FOUND")
		setStatus("Oil Exchange / Resource Collection not found!")
		task.wait(3)
		return
	end

	local exchangeTargetName = cand.resourceFallback and "Resource Collection" or "Oil Exchange"
	if cand.resourceFallback then
		dbg("Oil Exchange not found; using Resource Collection UI fallback:", cand.part:GetFullName())
	end

	local function goal()
		local pos = cand.part.Position
		if cand.prompt and cand.prompt.Parent then pos = promptPosition(cand.prompt) or pos end
		return CFrame.new(pos + Vector3.new(0, 2.5, 0))
	end

	pcall(function() player:RequestStreamAroundAsync(goal().Position) end)
	setStatus("Flying to " .. exchangeTargetName)
	if not flyTo(goal(), "Exchange") then return end
	if not running then return end

	-- dropped it on the way? go get it again, then come back
	if isBarrelDropped() then
		recoverBarrel()
		if not running then return end
		if not flyTo(goal(), "Exchange") then return end
		if not running then return end
	end
	task.wait(1)

	setStatus("Holding E (" .. exchangeTargetName .. ")")
	holdE(HOLD_TIME, (cand.prompt and cand.prompt.Parent) and cand.prompt or nil)
	task.wait(1)
	if isBarrelCarried() then
		setStatus("Still carrying barrel; exchange did not complete")
		dbg("Still carrying barrel after trying the Oil Exchange")
	else
		trackedBarrel = nil   -- exchange removed/detached it from the character
	end
end

-- Is the fallen barrel's DESPAWN label (or, as a backup, its Oil label) still on the map?
local function barrelRecoveryLabelStillVisible()
	local targets = findFloatingTargets("despawn")
	if not barrelRecoveryTargetPos then
		return #targets > 0
	end
	for _, target in ipairs(targets) do
		if (target.part.Position - barrelRecoveryTargetPos).Magnitude <= 25 then
			return true
		end
	end
	return false
end

local function clearBarrelRecovery()
	barrelRecoveryPending = false
	barrelRecoveryAttempted = false
	barrelRecoveryTargetPart = nil
	barrelRecoveryTargetPos = nil
end

-- After death, locate the fallen barrel from its floating "DESPAWN: ~595" label,
-- pick it up again, then exchange it before allowing any other target.
local function recoverDroppedBarrelFromUI()
	if not barrelRecoveryPending then return true end

	-- If a previous recovery attempt already attached/tracked it, finish the exchange first.
	if trackedBarrel or isBarrelCarried() then
		setStatus("Barrel recovered; exchanging before continuing...")
		if running then visitExchange() end
		if trackedBarrel or isBarrelCarried() then return false end
		barrelRecoveryAttempted = true

		if not barrelRecoveryLabelStillVisible() then
			clearBarrelRecovery()
			setStatus("Dropped barrel exchanged")
			return true
		end
	end

	-- NEW: search by the DESPAWN label (nearest to where the barrel was last seen)
	local targets = findFloatingTargets("despawn")
	local target = nil
	if barrelRecoveryTargetPos then
		local bestDistance = math.huge
		for _, candidate in ipairs(targets) do
			local distance = (candidate.part.Position - barrelRecoveryTargetPos).Magnitude
			if distance < bestDistance then
				target, bestDistance = candidate, distance
			end
		end
		if bestDistance > 25 then target = nil end
	end
	-- If the barrel moved when it dropped, fall back to the best DESPAWN label (list is already sorted).
	if not target and #targets > 0 then target = targets[1] end

	if not target then
		if barrelRecoveryAttempted and not barrelRecoveryLabelStillVisible() then
			clearBarrelRecovery()
			setStatus("Fallen barrel no longer on the map")
			return true
		end
		setStatus("Scanning for the fallen barrel (DESPAWN label)...")
		return false
	end

	barrelRecoveryTargetPart = target.part
	barrelRecoveryTargetPos = target.part.Position
	trackedBarrel = nil
	local recoveredPart = visitTarget("Fallen barrel", "despawn", true)
	if not recoveredPart then return false end

	barrelRecoveryTargetPart = recoveredPart
	barrelRecoveryTargetPos = recoveredPart.Position
	barrelRecoveryAttempted = true
	if trackedBarrel or isBarrelCarried() then
		setStatus("Fallen barrel found; exchanging...")
		if running then visitExchange() end
	end
	if trackedBarrel or isBarrelCarried() then return false end

	if barrelRecoveryLabelStillVisible() then
		trackedBarrel = nil
		setStatus("Fallen barrel still visible; rescanning...")
		return false
	end

	clearBarrelRecovery()
	setStatus("Fallen barrel recovered and exchanged")
	return true
end

local function handleAirdrop()
	airdropPending = false
	handlingAirdrop = true

	-- remember where the base is, we fly back here after collecting
	local char = player.Character
	local homeCFrame = char and char:GetPivot()
	if lastCollectorPos then
		homeCFrame = CFrame.new(lastCollectorPos + Vector3.new(0, 3, 4))   -- the base = next to your Cash Collector
	end

	if barrelRecoveryPending and not recoverDroppedBarrelFromUI() then
		setStatus("Waiting to recover dropped barrel before airdrop")
		airdropPending = false
		handlingAirdrop = false
		lastAirdropEnd = os.clock()
		return
	end

	-- A tracked barrel is treated as pending delivery even if the game keeps its
	-- model in Workspace instead of parenting it to the character. Do not clear it.
	if trackedBarrel or isBarrelCarried() then
		setStatus("Barrel pending exchange before airdrop...")
		if running then visitExchange() end
		if barrelRecoveryPending or trackedBarrel or isBarrelCarried() then
			setStatus("Barrel still pending; retrying exchange")
			airdropPending = false
			handlingAirdrop = false
			lastAirdropEnd = os.clock()
			return
		end
	end

	setStatus("AIRDROP! Searching...")
	if running then visitTarget("Oil Barrel", "oil") end
	if barrelRecoveryPending then
		if not recoverDroppedBarrelFromUI() then
			setStatus("Waiting to recover dropped barrel before airdrop")
			airdropPending = false
			handlingAirdrop = false
			lastAirdropEnd = os.clock()
			return
		end
	elseif running then
		recoverBarrel()   -- recover it before going elsewhere if it was dropped
	end

	-- Always finish the oil-barrel exchange attempt before visiting the airdrop.
	-- This avoids teleporting away with a barrel the game still considers held.
	if running and (trackedBarrel or isBarrelCarried()) then
		setStatus("Barrel found; exchanging before airdrop...")
		visitExchange()
	end
	if barrelRecoveryPending or trackedBarrel or isBarrelCarried() then
		setStatus("Barrel still pending; retrying exchange")
		airdropPending = false
		handlingAirdrop = false
		lastAirdropEnd = os.clock()
		return
	end

	if running then visitTarget("Airdrop", "airdrop") end
	if running then recoverBarrel() end

	-- fly back to the base, then to the Parts Oil Exchange and press E
	if running and homeCFrame then
		setStatus("Flying back to base...")
		flyTo(homeCFrame, "base")
	end
	if running then recoverBarrel() end
	if running then visitExchange() end

	airdropPending = false
	handlingAirdrop = false
	lastAirdropEnd = os.clock()
end

-- ==========================================
-- REBIRTH BUTTONS (first priority, no money check)
-- ==========================================
local rebirthCache = {}   -- key -> { pos = Vector3, num = number, text = string }  (remembers far buttons)
local rebirthDone = {}    -- key -> true when the button was bought (it disappeared)
local rebirthSkip = {}    -- key -> time until we try it again
local rejectLogged = {}   -- so the console is not spammed with the same message

local function clearRebirthMemory()
	rebirthCache = {}
	rebirthDone = {}
	rebirthSkip = {}
end

local function makeKey(text, pos)
	return text .. "@" .. math.floor(pos.X + 0.5) .. "," .. math.floor(pos.Y + 0.5) .. "," .. math.floor(pos.Z + 0.5)
end

local function rejectOnce(reason, text)
	local k = reason .. "|" .. text
	if not rejectLogged[k] then
		rejectLogged[k] = true
		dbg("Rebirth text REJECTED (" .. reason .. "):", text)
	end
end

-- the yellow pad you stand on is a separate part next to the sign: find it
local function findPadNear(part)
	local ok, parts = pcall(function() return workspace:GetPartBoundsInRadius(part.Position, 16) end)
	if not ok or not parts then return nil end
	local best, bestD
	for _, p in ipairs(parts) do
		local isPad = p:FindFirstChildWhichIsA("TouchInterest") ~= nil
		if not isPad then
			local c = p.Color
			isPad = (c.R > 0.9 and c.G > 0.9 and c.B < 0.35)   -- yellow
		end
		if isPad and not (player.Character and p:IsDescendantOf(player.Character)) then
			local d = (p.Position - part.Position).Magnitude
			if not bestD or d < bestD then best, bestD = p, d end
		end
	end
	return best
end

-- looks at all buttons that are currently loaded and finds the ones that say "N Rebirths"
local function findLoadedRebirths()
	local loaded = {}

	local function check(obj)
		if not (obj:IsA("BillboardGui") or obj:IsA("SurfaceGui")) then return end

		local fullText = ""
		for _, child in pairs(obj:GetDescendants()) do
			if (child:IsA("TextLabel") or child:IsA("TextButton")) and labelVisible(child, obj) then
				local raw = child.ContentText
				if not raw or raw == "" then raw = child.Text end
				if raw ~= "" and raw ~= "Label" then
					fullText = fullText .. string.gsub(raw, "\n", " ") .. " "
				end
			end
		end

		local lower = string.lower(fullText)
		-- only things that mention "rebirth" are interesting
		if not string.find(lower, "rebirth", 1, true) then return end

		if string.find(lower, "operation", 1, true) then return end
		-- check 1: the info signs use CAPITAL letters ("4 REBIRTHS"), the real button uses "4 Rebirths"
		if string.find(fullText, "%d+%s*REBIRTH") then
			rejectOnce("capital letters = info sign", fullText)
			return
		end
		-- check 1b: info pads are whole sentences ("Get to 6 Rebirths to be able to purchase ...")
		-- a real button is short: "Garage 1 Rebirth"
		if #fullText > 40 or string.find(lower, "construction", 1, true) or string.find(lower, "info", 1, true)
			or string.find(lower, "get to", 1, true) or string.find(lower, "to be able", 1, true) or string.find(lower, "purchase", 1, true) then
			rejectOnce("info text (sentence)", fullText)
			return
		end
		local numStr = string.match(fullText, "(%d+)%s*Rebirth")
		if not numStr then
			rejectOnce("no number before 'rebirth'", fullText)
			return
		end
		local num = tonumber(numStr)
		if not num then return end

		local part = obj.Adornee
		if not part then
			if obj.Parent:IsA("BasePart") then
				part = obj.Parent
			elseif obj.Parent:IsA("Attachment") and obj.Parent.Parent:IsA("BasePart") then
				part = obj.Parent.Parent
			elseif obj.Parent:IsA("Model") or obj.Parent:IsA("Folder") then
				part = obj.Parent:FindFirstChildWhichIsA("BasePart", true)
			end
		end
		if not (part and part:IsA("BasePart")) then
			rejectOnce("no part found", fullText)
			return
		end
		local mine = belongsToMe(part)
		if not mine and lastCollectorPos then
			mine = (part.Position - lastCollectorPos).Magnitude <= REBIRTH_NEAR_DIST
		end
		if not mine then
			rejectOnce("not in your base: " .. part:GetFullName(), fullText)
			return
		end

		local pad = findPadNear(part)
		if REBIRTH_REQUIRE_PAD and not pad then
			rejectOnce("no pad next to sign", fullText)
			return
		end
		part = pad or part   -- stand on the pad if we found it

		local key = makeKey(lower, part.Position)
		loaded[key] = { key = key, part = part, gui = obj, num = num, text = fullText }
		-- remember it, so we go there to load it later if it unloads
		if not rebirthCache[key] then
			dbg("Rebirth button ACCEPTED:", fullText, "->", part:GetFullName())
		end
		rebirthCache[key] = { pos = part.Position, num = num, text = fullText }
	end

	local n = 0
	for _, obj in pairs(workspace:GetDescendants()) do
		check(obj)
		n = n + 1
		if n % 3000 == 0 then task.wait() end
	end
	return loaded
end

local function rebirthWanted(key, num)
	if num > rebirthLimit then return false end
	if rebirthDone[key] then return false end
	if rebirthSkip[key] and os.clock() < rebirthSkip[key] then return false end
	return true
end

-- tries to buy one rebirth button (just stand on it, no money check)
local function buyRebirth(entry)
	for attempt = 1, MAX_ATTEMPTS do
		if not (running and env.AutoBuyerRunId == myRunId) or airdropPending or completionEPressing then return end
		if not isAlive(entry) then
			rebirthDone[entry.key] = true
			return
		end
		setStatus(("Rebirth %d (%d/%d)"):format(entry.num, attempt, MAX_ATTEMPTS))
		if not teleportTo(entry.part, false) then
			rebirthDone[entry.key] = true
			return
		end
		task.wait(CHECK_WAIT)
		if not isAlive(entry) then
			rebirthDone[entry.key] = true
			return
		end
	end
	-- did not work (maybe not enough rebirths yet) -> try again later
	rebirthSkip[entry.key] = os.clock() + REBIRTH_SKIP_TIME
end

-- goes through every wanted rebirth button, lowest number first
local function doRebirthButtons()
	if rebirthLimit <= 0 then return end

	-- the "is it my base" check needs the collector position, scan once to get it
	if not lastCollectorPos then pcall(scan) end

	local loaded = findLoadedRebirths()
	local list = {}

	for key, entry in pairs(loaded) do
		if rebirthWanted(key, entry.num) then table.insert(list, entry) end
	end

	-- far buttons that are not loaded right now: remember them, so we go there to load them
	for key, info in pairs(rebirthCache) do
		if not loaded[key] and rebirthWanted(key, info.num) then
			table.insert(list, { key = key, num = info.num, farPos = info.pos })
		end
	end

	if #list == 0 then
		local now = os.clock()
		if not env.AutoBuyerLastRebirthNote or now - env.AutoBuyerLastRebirthNote > 15 then
			env.AutoBuyerLastRebirthNote = now
			dbg("No rebirth button to press (limit = " .. rebirthLimit .. "). Look above for REJECTED lines.")
		end
	end

	table.sort(list, function(a, b) return a.num < b.num end)

	for _, entry in ipairs(list) do
		if not (running and env.AutoBuyerRunId == myRunId) or airdropPending or completionEPressing
			or barrelRecoveryPending or trackedBarrel or isBarrelCarried() then return end

		if entry.farPos then
			-- button is far away and not loaded: ask the game to load that area, then TP there
			setStatus("Loading far button (" .. entry.num .. ")")
			pcall(function() player:RequestStreamAroundAsync(entry.farPos) end)
			task.wait(0.5)

			local char = player.Character
			local rootPart = char and char:FindFirstChild("HumanoidRootPart")
			if rootPart then
				rootPart.Anchored = true
				char:PivotTo(CFrame.new(entry.farPos + Vector3.new(0, 4, 0)))
				task.wait(0.8)
				rootPart.Anchored = false
			end

			-- wait a little for the button to load in, then look again
			local fresh
			local deadline = os.clock() + 4
			repeat
				fresh = findLoadedRebirths()[entry.key]
				if not fresh then task.wait(0.4) end
			until fresh or os.clock() > deadline or not running

			if fresh then
				buyRebirth(fresh)
			else
				rebirthSkip[entry.key] = os.clock() + REBIRTH_SKIP_TIME
			end
		else
			buyRebirth(entry)
		end
	end
end

-- input box: only numbers, never more than MAX_REBIRTH
table.insert(env.AutoBuyerConnections, rebirthBox.FocusLost:Connect(function()
	local n = tonumber(string.match(rebirthBox.Text, "%d+")) or 0
	if n > MAX_REBIRTH then n = MAX_REBIRTH end
	if n < 0 then n = 0 end
	rebirthLimit = n
	rebirthBox.Text = (n > 0) and tostring(n) or ""
	clearRebirthMemory()
	setStatus(n > 0 and ("Rebirth limit: " .. n) or "Rebirth buttons OFF")
end))

-- ==========================================
-- MAIN LOOP
-- ==========================================
local function stillRunning()
	return running and env.AutoBuyerRunId == myRunId
end

local function mainLoop()
	while stillRunning() do
		-- Pause movement and purchases while the completion rebirth dialog is being confirmed.
		if completionEPressing then
			task.wait(0.1)
			continue
		end

		-- Death while carrying is handled before any airdrop, rebirth, collector, or button trip.
		if barrelRecoveryPending then
			if not recoverDroppedBarrelFromUI() then
				task.wait(1)
				continue
			end
		end

		if airdropPending then handleAirdrop() end
		if not stillRunning() then break end
		-- A death can happen inside the airdrop handler; recover before any other movement.
		if barrelRecoveryPending then
			if not recoverDroppedBarrelFromUI() then
				task.wait(1)
				continue
			end
		end

		-- Carrying a barrel takes priority over every other target. Keep retrying the
		-- Oil Exchange and do not visit rebirths, the collector, or purchase pads yet.
		if trackedBarrel or isBarrelCarried() then
			setStatus("Barrel pending; exchanging before other actions...")
			visitExchange()
			if barrelRecoveryPending then
				if not recoverDroppedBarrelFromUI() then
					task.wait(1)
					continue
				end
			end
			if trackedBarrel or isBarrelCarried() then
				task.wait(1)
				continue
			end
		end

		-- 0. rebirth buttons FIRST (no money check)
		doRebirthButtons()
		if not stillRunning() then break end
		if completionEPressing or airdropPending then continue end

		setStatus("Scanning...")
		local collector, buttons = scan()

		if not collector then
			setStatus("No 'Cash to collect' found")
			task.wait(2)
			continue
		end

		-- 1. go to collector and collect
		setStatus("Collecting cash...")
		teleportTo(collector.part, true)
		task.wait(COLLECT_WAIT)
		if not stillRunning() then break end
		if completionEPressing or airdropPending then continue end

		-- 2. check money
		local money = getMoney()
		if not money then
			setStatus("Can't read money!")
			task.wait(2)
			continue
		end

		-- 3. affordable buttons (price <= money), cheapest first
		local affordable = {}
		for _, b in ipairs(buttons) do
			if b.price <= money then table.insert(affordable, b) end
		end
		table.sort(affordable, function(a, b) return a.price < b.price end)

		if #affordable == 0 then
			local cheapest
			for _, b in ipairs(buttons) do
				if not cheapest or b.price < cheapest then cheapest = b.price end
			end
			setStatus(("Cash %s | %d buttons | cheapest %s"):format(tostring(money), #buttons, tostring(cheapest)))
			task.wait(3)
			continue -- loop goes straight back to the collector
		end

		-- 4. visit each affordable button
		for _, btn in ipairs(affordable) do
			if not stillRunning() or airdropPending or completionEPressing then break end

			local current = getMoney() or money
			if btn.price > current then
				continue -- no longer affordable
			end

			local bought = false
			for attempt = 1, MAX_ATTEMPTS do
				if not stillRunning() or airdropPending or completionEPressing then break end
				if not isAlive(btn) then bought = true break end

				setStatus(("Buying (%d/%d): %s"):format(attempt, MAX_ATTEMPTS, string.sub(btn.text, 1, 24)))
				local before = getMoney()
				if not teleportTo(btn.part, false) then bought = true break end
				task.wait(CHECK_WAIT)

				local after = getMoney()
				if not isAlive(btn) or (before and after and after < before) then
					bought = true
					break
				end
			end

			if not bought and stillRunning() and not airdropPending then
				setStatus("Skipped: " .. string.sub(btn.text, 1, 24))
				task.wait(0.3)
			end
		end

		-- 5. loop restarts -> back to the rebirth buttons, then the collector
	end

	setStatus("Idle")
end

-- ==========================================
-- SAFE INPUT RELEASE
-- Do not manually reparent equipped Tools: ACS_Client can keep a FireGun task
-- running and then index a missing weapon. Releasing the mouse is sufficient here.
-- ==========================================
local function releaseMouse()
	pcall(function() VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 0) end)
end

-- Increase the user's rebirth target only after the Rebirth confirmation dialog closes.
-- Keep 0 = off, and respect the configured maximum.
local function incrementRebirthLimit()
	local entered = tonumber(string.match(rebirthBox.Text, "%d+"))
	local current = math.clamp(entered or rebirthLimit or 0, 0, MAX_REBIRTH)
	if current <= 0 then return end

	local nextLimit = math.min(current + 1, MAX_REBIRTH)
	if nextLimit ~= current then
		rebirthLimit = nextLimit
		rebirthBox.Text = tostring(nextLimit)
		clearRebirthMemory()
		setStatus("Rebirth limit increased to " .. tostring(nextLimit))
	else
		rebirthLimit = current
		rebirthBox.Text = tostring(current)
	end
end

local function visibleGuiText(root)
	local pieces = {}
	local function appendText(obj)
		if isCompletionTextObject(obj) and labelVisible(obj, playerGui) then
			local text = getCompletionText(obj)
			if text ~= "" then table.insert(pieces, text) end
		end
	end

	if isCompletionTextObject(root) then appendText(root) end
	for _, child in ipairs(root:GetDescendants()) do appendText(child) end
	return table.concat(pieces, " ")
end

local function parseRebirthCost(text)
	local lower = string.lower(text or "")
	local amount, suffix = string.match(lower, "cost%s*:%s*%$?%s*([%d%.,]+)%s*([kmbt]?)")
	if not amount then return nil end
	amount = string.gsub(amount, ",", "")
	local value = tonumber(amount)
	if not value then return nil end
	return value * (SUFFIX[suffix] or 1)
end

local function normalizedButtonText(button)
	local text = string.lower(getCompletionText(button))
	local trimmed = string.gsub(text, "^%s*(.-)%s*$", "%1")
	return trimmed
end

local function findDialogButton(scope, wantedText)
	if not scope then return nil end
	for _, obj in ipairs(scope:GetDescendants()) do
		if obj:IsA("TextButton") and labelVisible(obj, playerGui)
			and normalizedButtonText(obj) == string.lower(wantedText) then
			return obj
		end
	end
	return nil
end

local function findRebirthConfirmation()
	for _, obj in ipairs(playerGui:GetDescendants()) do
		if obj:IsA("TextButton") and labelVisible(obj, playerGui)
			and normalizedButtonText(obj) == "confirm" then
			local scope = obj.Parent
			while scope and scope ~= playerGui do
				local text = visibleGuiText(scope)
				local lower = string.lower(text)
				local cost = parseRebirthCost(text)
				if cost and string.find(lower, "rebirth", 1, true) then
					return obj, cost, scope
				end
				scope = scope.Parent
			end
		end
	end
	return nil, nil, nil
end

local function waitForRebirthConfirmation(timeout)
	local deadline = os.clock() + timeout
	repeat
		local button, cost, scope = findRebirthConfirmation()
		if button then return button, cost, scope end
		task.wait(0.2)
	until os.clock() >= deadline
	return nil, nil, nil
end

local function clickGuiButton(button)
	if not (button and button.Parent and labelVisible(button, playerGui)) then return false end
	local center = button.AbsolutePosition + button.AbsoluteSize / 2
	local downWorked = pcall(function()
		VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, true, game, 0)
	end)
	if downWorked then
		task.wait(0.08)
		pcall(function()
			VirtualInputManager:SendMouseButtonEvent(center.X, center.Y, 0, false, game, 0)
		end)
		return true
	end
	return pcall(function() button:Activate() end)
end

local function finishCompletionAction()
	completionEPressing = false
	completionEStatus = nil
	if completionPercent ~= nil then setCompletionDisplay(completionPercent) end
end

local function pressCompletionE()
	if completionEPressing then return end
	completionEPressing = true
	completionEStatus = "Holding E"
	setCompletionDisplay(completionPercent or 100)

	pcall(function()
		VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
	end)
	if keypress then pcall(keypress, 0x45) end

	task.wait(2)

	pcall(function()
		VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
	end)
	if keyrelease then pcall(keyrelease, 0x45) end

	completionEStatus = "Waiting for confirmation"
	setCompletionDisplay(completionPercent or 100)
	local confirmButton, cost, dialog = waitForRebirthConfirmation(REBIRTH_CONFIRM_TIMEOUT)
	if not confirmButton then
		setStatus("Rebirth confirmation not found; target unchanged")
		finishCompletionAction()
		return
	end

	completionRequiredCash = math.max(REBIRTH_CONFIRM_MIN_CASH, cost)
	local cash = getMoney()
	if not cash or cash < cost then
		local cancelButton = findDialogButton(dialog, "cancel")
		local cancelled = cancelButton and clickGuiButton(cancelButton)
		setStatus(("Need $%s cash to confirm rebirth"):format(tostring(cost)))
		completionEArmed = cancelled == true
		finishCompletionAction()
		return
	end

	if not running or env.AutoBuyerRunId ~= myRunId then
		local cancelButton = findDialogButton(dialog, "cancel")
		if cancelButton then clickGuiButton(cancelButton) end
		setStatus("Auto Buyer stopped; rebirth not confirmed")
		finishCompletionAction()
		return
	end

	completionEStatus = "Confirming rebirth"
	setCompletionDisplay(completionPercent or 100)
	setStatus(("Confirming rebirth ($%s)"):format(tostring(cost)))
	if not clickGuiButton(confirmButton) then
		setStatus("Could not click Rebirth Confirm; target unchanged")
		finishCompletionAction()
		return
	end

	local confirmed = false
	local closeDeadline = os.clock() + REBIRTH_CONFIRM_TIMEOUT
	repeat
		task.wait(0.2)
		local stillOpen = findRebirthConfirmation()
		if not stillOpen then
			confirmed = true
			break
		end
	until os.clock() >= closeDeadline

	if confirmed then
		task.wait(0.4)
		local oldLimit = rebirthLimit
		incrementRebirthLimit()
		if rebirthLimit > oldLimit then
			setStatus("Rebirth confirmed; target advanced to " .. tostring(rebirthLimit))
		else
			setStatus("Rebirth confirmed; target is OFF or already at maximum")
		end
	else
		setStatus("Rebirth confirmation stayed open; target unchanged")
	end
	finishCompletionAction()
end

-- Keep the local completion display updated, even while AutoBuyer is OFF.
-- Auto E is only sent while the AutoBuyer toggle is ON and the barrel/airdrop
-- handler is idle. If blocked, the 100% trigger stays armed until it can run.
task.spawn(function()
	while env.AutoBuyerRunId == myRunId and screenGui.Parent do
		local percent = readCompletionPercent()
		setCompletionDisplay(percent)

		if percent ~= nil then
			if percent < 100 then
				completionEArmed = true
			elseif completionEArmed and not completionEPressing and running and not airdropPending
				and not handlingAirdrop and not barrelRecoveryPending
				and not isBarrelCarried() then
				local cash = getMoney()
				if cash and cash >= completionRequiredCash then
					completionEArmed = false
					task.spawn(pressCompletionE)
				else
					completionLabel.Text = ("Completion: %g%% | Need $%s"):format(
						math.clamp(percent, 0, 100), tostring(completionRequiredCash))
				end
			end
		end

		task.wait(0.5)
	end
end)

-- ==========================================
-- TOGGLE
-- ==========================================
table.insert(env.AutoBuyerConnections, toggleButton.MouseButton1Click:Connect(function()
	running = not running
	if running then
		toggleButton.Text = "ON"
		toggleButton.BackgroundColor3 = Color3.fromRGB(50, 200, 80)
		-- read the box again in case the player typed but did not press Enter
		local n = tonumber(string.match(rebirthBox.Text, "%d+")) or 0
		rebirthLimit = math.clamp(n, 0, MAX_REBIRTH)
		clearRebirthMemory()
		lockedCollectorPart = nil   -- re-pick the closest collector each time you switch ON
		releaseMouse()   -- release any stuck mouse-down state; do not reparent the ACS weapon
		task.spawn(mainLoop)
	else
		toggleButton.Text = "OFF"
		toggleButton.BackgroundColor3 = Color3.fromRGB(200, 50, 50)
		setStatus("Stopping...")
	end
end))