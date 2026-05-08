-- Attente chargement
if not game:IsLoaded() then
    game.Loaded:Wait()
end

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local me = Players.LocalPlayer
while not me do
    task.wait()
    me = Players.LocalPlayer
end

local char = me.Character or me.CharacterAdded:Wait()
char:WaitForChild("Humanoid")
char:WaitForChild("HumanoidRootPart")

local remotes = ReplicatedStorage:WaitForChild("Remotes")
local replication = remotes:WaitForChild("Replication")
local bulletInit = replication:WaitForChild("BulletInit")

repeat task.wait() until workspace.CurrentCamera

-- Nettoyage
for _, v in pairs(workspace:GetChildren()) do
    if v:IsA("Part") and v.Size == Vector3.new(0.2, 0.2, 0.2) then
        v:Destroy()
    end
end


-- ══════════════════════════════════════
-- CONFIG
-- ══════════════════════════════════════
local CREDITS    = "DM noayyy on Discord if any issue"
local SPEED      = 100
local GRAVITY    = 25
local FOV_RADIUS = 150


-- ══════════════════════════════════════
local active       = true
local aimbotOn     = false
local espOn        = false
local cachedAimDir = nil
local espDrawings  = {}


local fovCircle = Drawing.new("Circle")
fovCircle.Visible      = true
fovCircle.Radius       = FOV_RADIUS
fovCircle.Color        = Color3.fromRGB(255, 255, 255)
fovCircle.Thickness    = 1
fovCircle.Filled       = false
fovCircle.Transparency = 0.8


local function isInFOV(targetPos)
    local camera = workspace.CurrentCamera
    local screenPos, onScreen = camera:WorldToViewportPoint(targetPos)
    if not onScreen then return false end
    local center = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    return (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude <= FOV_RADIUS
end


local function getBestTarget()
    local me     = game.Players.LocalPlayer
    local myChar = me.Character
    if not myChar or not myChar:FindFirstChild("HumanoidRootPart") then return nil end
    local myPos = myChar.HumanoidRootPart.Position
    local myID  = me:GetAttribute("ID")
    local closest, closestDist = nil, math.huge
    for _, p in ipairs(game.Players:GetPlayers()) do
        if p == me then continue end
        if not p.Character then continue end
        if not p.Character:FindFirstChild("HumanoidRootPart") then continue end
        local theirID = p:GetAttribute("ID")
        if myID ~= nil and theirID ~= nil and theirID == myID then continue end
        local hum = p.Character:FindFirstChild("Humanoid")
        if not hum or hum.Health <= 0 then continue end
        if not isInFOV(p.Character.HumanoidRootPart.Position + Vector3.new(0, 1, 0)) then continue end
        local d = (p.Character.HumanoidRootPart.Position - myPos).Magnitude
        if d < closestDist then closest = p; closestDist = d end
    end
    return closest
end


local function hasLineOfSight(origin, targetPos, targetChar)
    local params = RaycastParams.new()
    params.FilterDescendantsInstances = {game.Players.LocalPlayer.Character, targetChar}
    params.FilterType = Enum.RaycastFilterType.Exclude
    return workspace:Raycast(origin, targetPos - origin, params) == nil
end


local function computeAimDir(origin, target)
    if not target then return nil end
    local root = target.Character.HumanoidRootPart
    local targetPos = root.Position + Vector3.new(0, 1, 0)
    if not hasLineOfSight(origin, targetPos, target.Character) then return nil end
    local dist = (targetPos - origin).Magnitude
    local t = dist / SPEED
    local vel = root.AssemblyLinearVelocity
    local clampedVel = Vector3.new(vel.X, math.clamp(vel.Y, -10, 10), vel.Z)
    local predicted = targetPos + clampedVel * t
    if not hasLineOfSight(origin, predicted, target.Character) then predicted = targetPos end
    local drop = 0.5 * GRAVITY * t * t
    return ((predicted + Vector3.new(0, drop, 0)) - origin).Unit
end


local function clearESP()
    for _, d in pairs(espDrawings) do
        for _, v in ipairs(d) do pcall(function() v:Remove() end) end
    end
    espDrawings = {}
end


local function updateESP()
    if not espOn then return end
    local me     = game.Players.LocalPlayer
    local myID   = me:GetAttribute("ID")
    local camera = workspace.CurrentCamera
    local activePlayers = {}

    for _, p in ipairs(game.Players:GetPlayers()) do
        if p == me then continue end
        if not p.Character then continue end
        local root = p.Character:FindFirstChild("HumanoidRootPart")
        local hum  = p.Character:FindFirstChild("Humanoid")
        if not root or not hum or hum.Health <= 0 then continue end

        activePlayers[p.Name] = true

        local theirID = p:GetAttribute("ID")
        local isEnemy = not (myID ~= nil and theirID ~= nil and theirID == myID)
        local color   = isEnemy and Color3.fromRGB(255, 60, 60) or Color3.fromRGB(60, 255, 120)

        local headVP, headVis = camera:WorldToViewportPoint(root.Position + Vector3.new(0, 2.8, 0))
        local feetVP, feetVis = camera:WorldToViewportPoint(root.Position - Vector3.new(0, 3.2, 0))
        local visible = headVis and feetVis and headVP.Z > 0

        -- Crée les drawings une seule fois par joueur
        if not espDrawings[p.Name] then
            local d = {}
            for i = 1, 4 do
                local line = Drawing.new("Line")
                line.Thickness = 1; line.Transparency = 1; line.Visible = false
                d[i] = line
            end
            local nameTag = Drawing.new("Text")
            nameTag.Size = 13; nameTag.Center = true; nameTag.Outline = true; nameTag.Visible = false
            d[5] = nameTag
            local barBg = Drawing.new("Line")
            barBg.Thickness = 3; barBg.Transparency = 1; barBg.Color = Color3.fromRGB(40,40,40); barBg.Visible = false
            d[6] = barBg
            local barFill = Drawing.new("Line")
            barFill.Thickness = 3; barFill.Transparency = 1; barFill.Visible = false
            d[7] = barFill
            local distTag = Drawing.new("Text")
            distTag.Size = 11; distTag.Center = true; distTag.Outline = true
            distTag.Color = Color3.fromRGB(200,200,200); distTag.Visible = false
            d[8] = distTag
            espDrawings[p.Name] = d
        end

        local d = espDrawings[p.Name]

        if not visible then
            for _, v in ipairs(d) do v.Visible = false end
            continue
        end

        local top    = math.min(headVP.Y, feetVP.Y)
        local bottom = math.max(headVP.Y, feetVP.Y)
        local h  = bottom - top
        local w  = h * 0.5
        local cx = (headVP.X + feetVP.X) / 2

        -- Box
        local corners = {
            {Vector2.new(cx-w/2, top),    Vector2.new(cx+w/2, top)},
            {Vector2.new(cx+w/2, top),    Vector2.new(cx+w/2, bottom)},
            {Vector2.new(cx+w/2, bottom), Vector2.new(cx-w/2, bottom)},
            {Vector2.new(cx-w/2, bottom), Vector2.new(cx-w/2, top)},
        }
        for i, c in ipairs(corners) do
            d[i].From = c[1]; d[i].To = c[2]; d[i].Color = color; d[i].Visible = true
        end

        -- Nom
        d[5].Text = p.Name; d[5].Position = Vector2.new(cx, top - 16)
        d[5].Color = color; d[5].Visible = true

        -- HP fond
        local barX = cx - w/2 - 6
        d[6].From = Vector2.new(barX, top); d[6].To = Vector2.new(barX, bottom); d[6].Visible = true

        -- HP fill
        local hpRatio = math.clamp(hum.Health / hum.MaxHealth, 0, 1)
        d[7].From = Vector2.new(barX, bottom - h * hpRatio)
        d[7].To   = Vector2.new(barX, bottom)
        d[7].Color = Color3.fromHSV(hpRatio * 0.33, 1, 1); d[7].Visible = true

        -- Distance
        local myChar = me.Character
        if myChar and myChar:FindFirstChild("HumanoidRootPart") then
            local dist = math.floor((root.Position - myChar.HumanoidRootPart.Position).Magnitude)
            d[8].Text = dist.."m"; d[8].Position = Vector2.new(cx, bottom + 3); d[8].Visible = true
        end
    end

    -- Cache les drawings des joueurs inactifs
    for name, d in pairs(espDrawings) do
        if not activePlayers[name] then
            for _, v in ipairs(d) do v.Visible = false end
        end
    end
end


local remote = game:GetService("ReplicatedStorage").Remotes.Replication.BulletInit


-- Aimbot loop
local aimLoop = game:GetService("RunService").Heartbeat:Connect(function(dt)
    if not active then return end
    local camera = workspace.CurrentCamera
    fovCircle.Position = Vector2.new(camera.ViewportSize.X / 2, camera.ViewportSize.Y / 2)
    fovCircle.Radius   = FOV_RADIUS

    local target = getBestTarget()
    fovCircle.Color = target and Color3.fromRGB(255, 50, 50) or Color3.fromRGB(255, 255, 255)

    if aimbotOn and target then
        cachedAimDir = computeAimDir(camera.CFrame.Position, target)
    else
        cachedAimDir = nil
    end

    updateESP()
end)


local oldNamecall
oldNamecall = hookmetamethod(game, "__namecall", function(self, ...)
    local args = {...}
    local method = getnamecallmethod()
    if self == remote and method == "FireServer" and active and aimbotOn then
        local bulletData = args[2]
        if bulletData and bulletData[1] and cachedAimDir then
            bulletData[1][3] = cachedAimDir
        end
    end
    return oldNamecall(self, unpack(args))
end)


-- ══════════════════════════════════════
-- GUI
-- ══════════════════════════════════════
local gui = Instance.new("ScreenGui")
gui.Name = "AimBot"
gui.ResetOnSpawn = false
gui.Parent = game.Players.LocalPlayer.PlayerGui


local main = Instance.new("Frame")
main.Size = UDim2.new(0, 220, 0, 240)
main.Position = UDim2.new(0, 12, 0, 12)
main.BackgroundColor3 = Color3.fromRGB(15, 15, 15)
main.BackgroundTransparency = 0.1
main.BorderSizePixel = 0
main.ClipsDescendants = true
main.Parent = gui
Instance.new("UICorner", main).CornerRadius = UDim.new(0, 8)


local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 34)
titleBar.BackgroundColor3 = Color3.fromRGB(25, 25, 25)
titleBar.BorderSizePixel = 0
titleBar.Parent = main


local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -12, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.TextColor3 = Color3.fromRGB(255, 255, 255)
titleLabel.Text = "Overkill AimBot"
titleLabel.Font = Enum.Font.GothamBold
titleLabel.TextSize = 14
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = titleBar


local draggingGui, dragStart, startPos = false, nil, nil
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        draggingGui = true; dragStart = input.Position; startPos = main.Position
    end
end)
titleBar.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then draggingGui = false end
end)
game:GetService("UserInputService").InputChanged:Connect(function(input)
    if draggingGui and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        main.Position = UDim2.new(startPos.X.Scale, startPos.X.Offset + delta.X, startPos.Y.Scale, startPos.Y.Offset + delta.Y)
    end
end)


local sep0 = Instance.new("Frame")
sep0.Size = UDim2.new(1, 0, 0, 1)
sep0.Position = UDim2.new(0, 0, 0, 34)
sep0.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
sep0.BorderSizePixel = 0
sep0.Parent = main


local function makeToggle(yPos, labelText, state, callback)
    local row = Instance.new("Frame")
    row.Size = UDim2.new(1, -20, 0, 30)
    row.Position = UDim2.new(0, 10, 0, yPos)
    row.BackgroundTransparency = 1
    row.Parent = main

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(0.65, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(210, 210, 210)
    lbl.Text = labelText
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 13
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = row

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(0, 48, 0, 22)
    btn.Position = UDim2.new(1, -48, 0.5, -11)
    btn.BackgroundColor3 = state and Color3.fromRGB(50, 180, 80) or Color3.fromRGB(180, 50, 50)
    btn.TextColor3 = Color3.fromRGB(255, 255, 255)
    btn.Text = state and "ON" or "OFF"
    btn.Font = Enum.Font.GothamBold
    btn.TextSize = 12
    btn.BorderSizePixel = 0
    btn.Parent = row
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 4)

    btn.MouseButton1Click:Connect(function()
        state = not state
        btn.Text = state and "ON" or "OFF"
        btn.BackgroundColor3 = state and Color3.fromRGB(50, 180, 80) or Color3.fromRGB(180, 50, 50)
        callback(state)
    end)
end


local function makeSlider(yPos, labelText, minVal, maxVal, currentVal, callback)
    local container = Instance.new("Frame")
    container.Size = UDim2.new(1, -20, 0, 44)
    container.Position = UDim2.new(0, 10, 0, yPos)
    container.BackgroundTransparency = 1
    container.Parent = main

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 0, 18)
    lbl.BackgroundTransparency = 1
    lbl.TextColor3 = Color3.fromRGB(210, 210, 210)
    lbl.Text = labelText .. ": " .. currentVal
    lbl.Font = Enum.Font.Gotham
    lbl.TextSize = 12
    lbl.TextXAlignment = Enum.TextXAlignment.Left
    lbl.Parent = container

    local track = Instance.new("Frame")
    track.Size = UDim2.new(1, 0, 0, 5)
    track.Position = UDim2.new(0, 0, 0, 26)
    track.BackgroundColor3 = Color3.fromRGB(55, 55, 55)
    track.BorderSizePixel = 0
    track.Parent = container
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)

    local fill = Instance.new("Frame")
    fill.Size = UDim2.new((currentVal - minVal) / (maxVal - minVal), 0, 1, 0)
    fill.BackgroundColor3 = Color3.fromRGB(60, 180, 255)
    fill.BorderSizePixel = 0
    fill.Parent = track
    Instance.new("UICorner", fill).CornerRadius = UDim.new(1, 0)

    local knob = Instance.new("TextButton")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.Position = UDim2.new((currentVal - minVal) / (maxVal - minVal), -7, 0.5, -7)
    knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
    knob.Text = ""
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local sliding = false
    knob.MouseButton1Down:Connect(function() sliding = true end)
    game:GetService("UserInputService").InputEnded:Connect(function(i)
        if i.UserInputType == Enum.UserInputType.MouseButton1 then sliding = false end
    end)
    game:GetService("RunService").Heartbeat:Connect(function()
        if not sliding then return end
        local mouse = game.Players.LocalPlayer:GetMouse()
        local rel = math.clamp((mouse.X - track.AbsolutePosition.X) / track.AbsoluteSize.X, 0, 1)
        local val = math.floor(minVal + rel * (maxVal - minVal))
        fill.Size = UDim2.new(rel, 0, 1, 0)
        knob.Position = UDim2.new(rel, -7, 0.5, -7)
        lbl.Text = labelText .. ": " .. val
        callback(val)
    end)
end


makeToggle(44,  "Aimbot", aimbotOn, function(s) aimbotOn = s; if not s then cachedAimDir = nil end end)
makeToggle(80,  "ESP",    espOn,    function(s) espOn = s; if not s then clearESP() end end)
makeSlider(116, "FOV",    10, 400,  FOV_RADIUS, function(v) FOV_RADIUS = v end)


local sep1 = Instance.new("Frame")
sep1.Size = UDim2.new(1, -20, 0, 1)
sep1.Position = UDim2.new(0, 10, 0, 172)
sep1.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
sep1.BorderSizePixel = 0
sep1.Parent = main


local unloadBtn = Instance.new("TextButton")
unloadBtn.Size = UDim2.new(1, -20, 0, 28)
unloadBtn.Position = UDim2.new(0, 10, 0, 181)
unloadBtn.BackgroundColor3 = Color3.fromRGB(180, 40, 40)
unloadBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
unloadBtn.Text = "Unload"
unloadBtn.Font = Enum.Font.GothamBold
unloadBtn.TextSize = 13
unloadBtn.BorderSizePixel = 0
unloadBtn.Parent = main
Instance.new("UICorner", unloadBtn).CornerRadius = UDim.new(0, 4)


local sep2 = Instance.new("Frame")
sep2.Size = UDim2.new(1, -20, 0, 1)
sep2.Position = UDim2.new(0, 10, 0, 217)
sep2.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
sep2.BorderSizePixel = 0
sep2.Parent = main


local creditsLabel = Instance.new("TextLabel")
creditsLabel.Size = UDim2.new(1, -20, 0, 20)
creditsLabel.Position = UDim2.new(0, 10, 0, 220)
creditsLabel.BackgroundTransparency = 1
creditsLabel.TextColor3 = Color3.fromRGB(100, 100, 100)
creditsLabel.Text = CREDITS
creditsLabel.Font = Enum.Font.Gotham
creditsLabel.TextSize = 11
creditsLabel.TextXAlignment = Enum.TextXAlignment.Center
creditsLabel.Parent = main


unloadBtn.MouseButton1Click:Connect(function()
    active = false
    aimLoop:Disconnect()
    fovCircle:Remove()
    clearESP()
    for _, v in pairs(workspace:GetChildren()) do
        if v:IsA("Part") and v.Size == Vector3.new(0.2, 0.2, 0.2) then v:Destroy() end
    end
    gui:Destroy()
end)


print("AimBot On (my first script)— " .. CREDITS)
