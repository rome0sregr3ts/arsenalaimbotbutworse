--[[
  AimAssistTest - LocalScript for YOUR OWN Roblox Studio test place.
  Put in: StarterPlayer > StarterPlayerScripts (as a LocalScript)

  Targets: other players' characters, plus any Model tagged "AimTarget"
  (CollectionService) - tag a few dummy rigs to test solo.

  Defaults:
    Aim (hold)   : Right Mouse
    Aim toggle   : Q
    Show/hide UI : RightShift
  All three can be rebound from the UI.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local CollectionService = game:GetService("CollectionService")

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

---------------------------------------------------------------- settings
local settings = {
	Enabled = true,        -- master on/off (toggled by the toggle key / button)
	StickyLock = true,     -- keep the same target while aim key is held
	WallCheck = true,      -- ignore targets behind walls
	TeamCheck = true,      -- ignore teammates (players on your Team)
	ShowFOV = true,
	FOV = 150,             -- radius in pixels
	Smoothness = 0.6,      -- 0 = instant snap, 0.95 = very slow
	TargetMode = "Head",   -- "Head" or "Body"
	Strength = 1.0,        -- 0.05..1, scales how hard the camera is pulled
	LockAnyDistance = true,-- once locked, stay locked outside the FOV / off-screen
	AlwaysAim = false,     -- hipfire mode: aim assist active without holding the aim key
	UIScale = 1.0,         -- menu size
}

local binds = {
	Aim = Enum.UserInputType.MouseButton2,
	Toggle = Enum.KeyCode.Q,
	Menu = Enum.KeyCode.RightShift,
}

local aimHeld = false
local lockedTarget = nil -- Model

---------------------------------------------------------------- targeting
local function getTargetModels()
	local list = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p ~= player and p.Character then
			table.insert(list, p.Character)
		end
	end
	for _, m in ipairs(CollectionService:GetTagged("AimTarget")) do
		if m:IsA("Model") and m ~= player.Character then
			table.insert(list, m)
		end
	end
	return list
end

-- Players: compared by Roblox Team. Tagged dummies: set a string attribute
-- "Team" on the model equal to a Team's Name to make it a teammate.
-- If you have no team (FFA / neutral), nobody counts as a teammate.
local function isTeammate(model)
	if not settings.TeamCheck or not player.Team then return false end
	local p = Players:GetPlayerFromCharacter(model)
	if p then return p.Team == player.Team end
	local t = model:GetAttribute("Team")
	return t ~= nil and t == player.Team.Name
end

local function getAimPart(model)
	if isTeammate(model) then return nil end
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum or hum.Health <= 0 then return nil end
	if settings.TargetMode == "Body" then
		return model:FindFirstChild("UpperTorso")
			or model:FindFirstChild("Torso")
			or model:FindFirstChild("HumanoidRootPart")
	end
	return model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
end

local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude

local function isVisible(model, part)
	if not settings.WallCheck then return true end
	rayParams.FilterDescendantsInstances = { player.Character }
	local origin = camera.CFrame.Position
	local result = workspace:Raycast(origin, part.Position - origin, rayParams)
	return result == nil or result.Instance:IsDescendantOf(model)
end

-- returns distance from cursor in pixels, or nil if not valid
local function screenDistance(part)
	local pos, onScreen = camera:WorldToViewportPoint(part.Position)
	if not onScreen then return nil end
	local mouse = UserInputService:GetMouseLocation()
	return (Vector2.new(pos.X, pos.Y) - mouse).Magnitude
end

-- isLocked: an existing lock may ignore the FOV / screen position if
-- LockAnyDistance is on (there is no world-distance limit either way).
local function isValid(model, isLocked)
	local part = getAimPart(model)
	if not part then return false end
	if isLocked and settings.LockAnyDistance then
		return isVisible(model, part)
	end
	local d = screenDistance(part)
	return d ~= nil and d <= settings.FOV and isVisible(model, part)
end

local function findBestTarget()
	local best, bestDist = nil, math.huge
	for _, model in ipairs(getTargetModels()) do
		local part = getAimPart(model)
		if part then
			local d = screenDistance(part)
			if d and d <= settings.FOV and d < bestDist and isVisible(model, part) then
				best, bestDist = model, d
			end
		end
	end
	return best
end

---------------------------------------------------------------- UI
local gui = Instance.new("ScreenGui")
gui.Name = "AimAssistTestUI"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.Parent = player:WaitForChild("PlayerGui")

-- FOV circle
local fovCircle = Instance.new("Frame")
fovCircle.AnchorPoint = Vector2.new(0.5, 0.5)
fovCircle.BackgroundTransparency = 1
fovCircle.Parent = gui
local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(1, 0)
fovCorner.Parent = fovCircle
local fovStroke = Instance.new("UIStroke")
fovStroke.Thickness = 1.5
fovStroke.Color = Color3.fromRGB(255, 255, 255)
fovStroke.Parent = fovCircle

-- Main panel
local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(250, 0)
panel.AutomaticSize = Enum.AutomaticSize.Y
panel.Position = UDim2.fromOffset(20, 60)
panel.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
panel.BorderSizePixel = 0
panel.Active = true
panel.Draggable = true -- simple dragging; fine for a test tool
panel.Parent = gui
Instance.new("UICorner", panel).CornerRadius = UDim.new(0, 8)
local panelScale = Instance.new("UIScale", panel)

-- small always-visible button to reopen the menu after closing it
local openBtn = Instance.new("TextButton")
openBtn.Size = UDim2.fromOffset(60, 24)
openBtn.Position = UDim2.fromOffset(20, 28)
openBtn.BackgroundColor3 = Color3.fromRGB(25, 25, 30)
openBtn.TextColor3 = Color3.fromRGB(235, 235, 235)
openBtn.Font = Enum.Font.GothamBold
openBtn.TextSize = 12
openBtn.Text = "Aim UI"
openBtn.Parent = gui
Instance.new("UICorner", openBtn).CornerRadius = UDim.new(0, 6)
openBtn.MouseButton1Click:Connect(function()
	panel.Visible = not panel.Visible
end)

local layout = Instance.new("UIListLayout")
layout.Padding = UDim.new(0, 6)
layout.SortOrder = Enum.SortOrder.LayoutOrder
layout.Parent = panel
local pad = Instance.new("UIPadding")
pad.PaddingTop, pad.PaddingLeft, pad.PaddingRight, pad.PaddingBottom =
	UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8), UDim.new(0, 8)
pad.Parent = panel

local order = 0
local function nextOrder() order += 1 return order end

local function makeLabel(text)
	local l = Instance.new("TextLabel")
	l.Size = UDim2.new(1, 0, 0, 22)
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = Color3.fromRGB(235, 235, 235)
	l.Font = Enum.Font.GothamBold
	l.TextSize = 14
	l.LayoutOrder = nextOrder()
	l.Parent = panel
	return l
end

local function makeButton(text, callback)
	local b = Instance.new("TextButton")
	b.Size = UDim2.new(1, 0, 0, 28)
	b.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
	b.TextColor3 = Color3.fromRGB(235, 235, 235)
	b.Font = Enum.Font.Gotham
	b.TextSize = 13
	b.Text = text
	b.AutoButtonColor = true
	b.LayoutOrder = nextOrder()
	b.Parent = panel
	Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
	b.MouseButton1Click:Connect(callback)
	return b
end

local function makeToggle(name, key)
	local btn
	local function refresh()
		btn.Text = string.format("%s: %s", name, settings[key] and "ON" or "OFF")
		btn.BackgroundColor3 = settings[key] and Color3.fromRGB(40, 110, 60) or Color3.fromRGB(110, 45, 45)
	end
	btn = makeButton("", function()
		settings[key] = not settings[key]
		refresh()
	end)
	refresh()
	return refresh
end

local function makeSlider(name, key, minV, maxV, decimals)
	local label = makeLabel("")
	label.Font = Enum.Font.Gotham
	label.TextSize = 13
	label.Size = UDim2.new(1, 0, 0, 16)

	local bar = Instance.new("Frame")
	bar.Size = UDim2.new(1, 0, 0, 10)
	bar.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
	bar.BorderSizePixel = 0
	bar.LayoutOrder = nextOrder()
	bar.Parent = panel
	Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

	local fill = Instance.new("Frame")
	fill.BackgroundColor3 = Color3.fromRGB(90, 150, 255)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

	local function refresh()
		local a = (settings[key] - minV) / (maxV - minV)
		fill.Size = UDim2.new(a, 0, 1, 0)
		label.Text = string.format("%s: %s", name, string.format("%." .. decimals .. "f", settings[key]))
	end

	local dragging = false
	local function setFromX(x)
		local a = math.clamp((x - bar.AbsolutePosition.X) / bar.AbsoluteSize.X, 0, 1)
		local mult = 10 ^ decimals
		settings[key] = math.floor((minV + (maxV - minV) * a) * mult + 0.5) / mult
		refresh()
	end
	bar.InputBegan:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then
			dragging = true
			setFromX(i.Position.X)
		end
	end)
	UserInputService.InputChanged:Connect(function(i)
		if dragging and i.UserInputType == Enum.UserInputType.MouseMovement then
			setFromX(i.Position.X)
		end
	end)
	UserInputService.InputEnded:Connect(function(i)
		if i.UserInputType == Enum.UserInputType.MouseButton1 then dragging = false end
	end)
	refresh()
end

---------------------------------------------------------------- keybind UI
local function bindName(b)
	return b.Name:gsub("MouseButton1", "LMB"):gsub("MouseButton2", "RMB"):gsub("MouseButton3", "MMB")
end

local rebinding = nil -- name of the bind being rebound
local bindButtons = {}

local function makeBindRow(label, key)
	local btn = makeButton("", function()
		rebinding = key
		bindButtons[key].Text = label .. ": press a key..."
	end)
	bindButtons[key] = btn
	btn.Text = label .. ": " .. bindName(binds[key])
	return label
end

local bindLabels = {
	Aim = makeBindRow("Aim key", "Aim"),
	Toggle = makeBindRow("Toggle key", "Toggle"),
	Menu = makeBindRow("Menu key", "Menu"),
}

local function matches(input, bind)
	if bind.EnumType == Enum.KeyCode then
		return input.KeyCode == bind
	end
	return input.UserInputType == bind
end

---------------------------------------------------------------- build panel order
-- (the rows above were created first; header + toggles/sliders are appended below)
local enabledRefresh = makeToggle("Aim assist", "Enabled")
makeToggle("Wall check", "WallCheck")
makeToggle("Team check", "TeamCheck")
makeToggle("Sticky lock", "StickyLock")
makeToggle("Show FOV", "ShowFOV")
makeSlider("FOV radius", "FOV", 30, 500, 0)
makeToggle("Lock outside FOV", "LockAnyDistance")
makeToggle("Hipfire (no aim key)", "AlwaysAim")

local modeBtn
modeBtn = makeButton("", function()
	settings.TargetMode = settings.TargetMode == "Head" and "Body" or "Head"
	modeBtn.Text = "Aim at: " .. settings.TargetMode
end)
modeBtn.Text = "Aim at: " .. settings.TargetMode

makeSlider("Smoothness", "Smoothness", 0, 0.95, 2)
makeSlider("Strength", "Strength", 0.05, 1, 2)
makeSlider("UI size", "UIScale", 0.6, 1.5, 2)

-- live strength meter: fills toward Strength while locked, drains when not
local meterLabel = makeLabel("Pull meter")
meterLabel.Font = Enum.Font.Gotham
meterLabel.TextSize = 13
meterLabel.Size = UDim2.new(1, 0, 0, 16)
local meterBar = Instance.new("Frame")
meterBar.Size = UDim2.new(1, 0, 0, 12)
meterBar.BackgroundColor3 = Color3.fromRGB(55, 55, 65)
meterBar.BorderSizePixel = 0
meterBar.LayoutOrder = nextOrder()
meterBar.Parent = panel
Instance.new("UICorner", meterBar).CornerRadius = UDim.new(1, 0)
local meterFill = Instance.new("Frame")
meterFill.Size = UDim2.new(0, 0, 1, 0)
meterFill.BackgroundColor3 = Color3.fromRGB(255, 170, 60)
meterFill.BorderSizePixel = 0
meterFill.Parent = meterBar
Instance.new("UICorner", meterFill).CornerRadius = UDim.new(1, 0)
local meterValue = 0

makeButton("Close menu", function()
	panel.Visible = false
end)

-- title goes first
local title = makeLabel("Aim Assist (Test)")
title.LayoutOrder = 0

---------------------------------------------------------------- input
UserInputService.InputBegan:Connect(function(input, processed)
	-- rebinding takes priority
	if rebinding then
		if input.KeyCode == Enum.KeyCode.Escape then
			bindButtons[rebinding].Text = bindLabels[rebinding] .. ": " .. bindName(binds[rebinding])
			rebinding = nil
			return
		end
		local new
		if input.UserInputType == Enum.UserInputType.Keyboard then
			new = input.KeyCode
		elseif input.UserInputType == Enum.UserInputType.MouseButton1
			or input.UserInputType == Enum.UserInputType.MouseButton2
			or input.UserInputType == Enum.UserInputType.MouseButton3 then
			new = input.UserInputType
		end
		if new then
			binds[rebinding] = new
			bindButtons[rebinding].Text = bindLabels[rebinding] .. ": " .. bindName(new)
			rebinding = nil
		end
		return
	end

	if processed then return end

	if matches(input, binds.Toggle) then
		settings.Enabled = not settings.Enabled
		enabledRefresh()
		if not settings.Enabled then lockedTarget = nil end
	elseif matches(input, binds.Menu) then
		panel.Visible = not panel.Visible
	elseif matches(input, binds.Aim) then
		aimHeld = true
	end
end)

UserInputService.InputEnded:Connect(function(input)
	if matches(input, binds.Aim) then
		aimHeld = false
		lockedTarget = nil
	end
end)

---------------------------------------------------------------- main loop
RunService:BindToRenderStep("AimAssistTest", Enum.RenderPriority.Camera.Value + 1, function(dt)
	camera = workspace.CurrentCamera

	-- FOV circle follows the cursor
	local mouse = UserInputService:GetMouseLocation()
	fovCircle.Visible = settings.ShowFOV and settings.Enabled
	fovCircle.Position = UDim2.fromOffset(mouse.X, mouse.Y)
	fovCircle.Size = UDim2.fromOffset(settings.FOV * 2, settings.FOV * 2)

	-- UI size + strength meter (uses last frame's lock state)
	panelScale.Scale = settings.UIScale
	local aiming = aimHeld or settings.AlwaysAim
	local pulling = settings.Enabled and aiming and lockedTarget ~= nil
	meterValue += ((pulling and settings.Strength or 0) - meterValue) * math.min(1, dt * 12)
	meterFill.Size = UDim2.new(math.clamp(meterValue, 0, 1), 0, 1, 0)

	if not (settings.Enabled and aiming) then
		if not aiming then lockedTarget = nil end
		return
	end

	-- target selection / lock
	if settings.StickyLock and lockedTarget and isValid(lockedTarget, true) then
		-- keep current lock
	else
		lockedTarget = findBestTarget()
	end
	if not lockedTarget then return end

	local part = getAimPart(lockedTarget)
	if not part then lockedTarget = nil return end

	-- frame-rate independent smoothing
	local alpha = 1 - settings.Smoothness ^ (dt * 60)
	if settings.Smoothness <= 0 then alpha = 1 end
	alpha = alpha * settings.Strength

	local camPos = camera.CFrame.Position
	camera.CFrame = camera.CFrame:Lerp(CFrame.lookAt(camPos, part.Position), alpha)
end)
