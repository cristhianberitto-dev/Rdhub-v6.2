-- Melee Mastery Farm - interface independente (v6.1)
-- - Hitbox do NPC aumentado de forma CONTROLADA (escala com altura, máx 60) para o ataque alcançar
-- - Auto-click ativo (mouse1click / VirtualUser)
-- - Noclip forçado + clamp de velocidade (anti-crash Delta)
-- - Offset horizontal + correção se começar a afundar
-- - Forças dos BodyMovers controladas

local SharedEnvironment = _G
if type(getgenv) == "function" then
    local ok, env = pcall(getgenv)
    if ok and type(env) == "table" then
        SharedEnvironment = env
    end
end

if type(SharedEnvironment.__MeleeMasteryCleanup) == "function" then
    pcall(SharedEnvironment.__MeleeMasteryCleanup)
end
SharedEnvironment.__MeleeMasterySession = (tonumber(SharedEnvironment.__MeleeMasterySession) or 0) + 1
local SessionId = SharedEnvironment.__MeleeMasterySession
local function IsCurrentSession()
    return SharedEnvironment.__MeleeMasterySession == SessionId
end

repeat task.wait() until game:IsLoaded()

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local VirtualUser = game:GetService("VirtualUser")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local Player = Players.LocalPlayer
local PlayerGui = Player:WaitForChild("PlayerGui", 10)
if not PlayerGui then error("PlayerGui nao carregou; execute depois que o personagem terminar de entrar") end
local Enemies = workspace:FindFirstChild("Enemies")
local Remotes = ReplicatedStorage:FindFirstChild("Remotes")
local CommF = Remotes and Remotes:FindFirstChild("CommF_") or nil

local oldGui
local guiParent
if type(gethui) == "function" then
    local ok, result = pcall(gethui)
    if ok then guiParent = result end
end
guiParent = guiParent or PlayerGui
oldGui = guiParent:FindFirstChild("MeleeMasteryOnlyUI")
if oldGui then oldGui:Destroy() end

local Configs = {
    [2753915549] = {
        SeaName = "Sea 1",
        Enemies = {"Galley Captain"},
        TargetLabel = "Galley Captain (Lv. 650)",
        SpawnPoints = {
            CFrame.new(5985, 70, 4790),
            CFrame.new(5472, 70, 4887)
        }
    },
    [4442272183] = {
        SeaName = "Sea 2",
        Enemies = {"Water Fighter"},
        TargetLabel = "Water Fighter (Lv. 1450)",
        SpawnPoints = {
            CFrame.new(-3339, 290, -10412),
            CFrame.new(-3518, 290, -10419),
            CFrame.new(-3536, 290, -10607),
            CFrame.new(-3345, 280, -10667)
        }
    },
    [7449423635] = {
        SeaName = "Sea 3",
        Enemies = {"Isle Champion"},
        TargetLabel = "Isle Champion (Lv. 2525)",
        SpawnPoints = {
            CFrame.new(-16634, 85, 1106),
            CFrame.new(-16735, 60, 1075),
            CFrame.new(-16888, 35, 1011)
        }
    }
}

local function DetectConfig()
    local placeId = tonumber(game.PlaceId)
    if placeId and Configs[placeId] then
        return Configs[placeId], "PlaceId " .. tostring(placeId)
    end

    local map = workspace:FindFirstChild("Map")
    local cues = {
        [7449423635] = {"TikiOutpost", "Tiki Outpost", "PortTown", "Port Town", "HydraIsland", "FloatingTurtle", "GreatTree", "HauntedCastle"},
        [4442272183] = {"KingdomOfRose", "Kingdom of Rose", "GreenZone", "Green Zone", "CursedShip", "ForgottenIsland", "SnowMountain"},
        [2753915549] = {"FountainCity", "Fountain City", "Jungle", "PirateVillage", "Pirate Village", "MarineStarter", "PirateStarter", "UnderwaterCity"}
    }
    if map then
        for _, place in ipairs({7449423635, 4442272183, 2753915549}) do
            for _, cue in ipairs(cues[place]) do
                if map:FindFirstChild(cue, true) then
                    return Configs[place], "map"
                end
            end
        end
    end

    local currentEnemies = workspace:FindFirstChild("Enemies")
    if currentEnemies then
        for _, enemy in ipairs(currentEnemies:GetChildren()) do
            for place, cfg in pairs(Configs) do
                if table.find(cfg.Enemies, enemy.Name) then
                    return cfg, "NPC"
                end
            end
        end
    end
    return nil, "PlaceId " .. tostring(game.PlaceId) .. " nao reconhecido"
end

local Config, DetectInfo = DetectConfig()

local Enabled = false
local Height = 30
local LoopToken = 0
local spawnIndex = 1
local lastSpawnMove = 0
local lastClick = 0
local MoveToken = 0
local FLIGHT_SPEED = 350
local NoclipEnabled = false
local OriginalCollision = setmetatable({}, {__mode = "k"})
local NoclipConnection = nil
local VelocityClampConnection = nil
local SetNoclip
local StopHover
local StopFlight
local RecoverIfBelowWorld
local HoverMover
local FlightVelocity
local FlightRotation
local LastSafeCFrame = SharedEnvironment.__MeleeMasteryLastSafe
local CurrentTarget = nil

local function Make(className, properties, parent)
    local object = Instance.new(className)
    for key, value in pairs(properties or {}) do
        object[key] = value
    end
    object.Parent = parent
    return object
end

local GUI = Make("ScreenGui", {
    Name = "MeleeMasteryOnlyUI",
    ResetOnSpawn = false,
    ZIndexBehavior = Enum.ZIndexBehavior.Sibling
}, guiParent)

local Main = Make("Frame", {
    Name = "Main",
    Size = UDim2.fromOffset(286, 205),
    Position = UDim2.new(0.5, -143, 0.48, -102),
    BackgroundColor3 = Color3.fromRGB(20, 23, 31),
    BorderSizePixel = 0,
    Active = true
}, GUI)
Make("UICorner", {CornerRadius = UDim.new(0, 10)}, Main)
Make("UIStroke", {Color = Color3.fromRGB(75, 96, 130), Thickness = 1}, Main)
local cameraAtStart = workspace.CurrentCamera
local viewportAtStart = cameraAtStart and cameraAtStart.ViewportSize or Vector2.new(1280, 720)
local responsiveScale = math.clamp(math.min(viewportAtStart.X / 430, viewportAtStart.Y / 340), 0.55, 0.62)
Make("UIScale", {Scale = responsiveScale}, Main)

local FloatingButton = Make("TextButton", {
    Name = "FloatingToggle",
    Size = UDim2.fromOffset(48, 48),
    Position = UDim2.new(1, -64, 0.22, 0),
    BackgroundColor3 = Color3.fromRGB(20, 23, 31),
    BorderSizePixel = 0,
    Text = "MM",
    TextColor3 = Color3.fromRGB(115, 210, 255),
    TextSize = 26,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = true,
    ZIndex = 30,
    Active = true
}, GUI)
Make("UICorner", {CornerRadius = UDim.new(1, 0)}, FloatingButton)
Make("UIStroke", {Color = Color3.fromRGB(75, 170, 225), Thickness = 2}, FloatingButton)

local suppressFloatClick = false
FloatingButton.Activated:Connect(function()
    if suppressFloatClick then
        suppressFloatClick = false
        return
    end
    Main.Visible = not Main.Visible
    FloatingButton.Text = Main.Visible and "−" or "MM"
end)

do
    local floatDragging = false
    local floatStart, floatPosition
    FloatingButton.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            floatDragging = true
            floatStart = input.Position
            floatPosition = FloatingButton.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if floatDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - floatStart
            if delta.Magnitude > 7 then suppressFloatClick = true end
            FloatingButton.Position = UDim2.new(floatPosition.X.Scale, floatPosition.X.Offset + delta.X,
                floatPosition.Y.Scale, floatPosition.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            floatDragging = false
            if suppressFloatClick then
                task.delay(0.25, function() suppressFloatClick = false end)
            end
        end
    end)
end

local Header = Make("TextLabel", {
    Name = "Header",
    Size = UDim2.new(1, -18, 0, 32),
    Position = UDim2.fromOffset(12, 5),
    BackgroundTransparency = 1,
    Text = "MELEE MASTERY FARM",
    TextColor3 = Color3.fromRGB(115, 210, 255),
    TextSize = 15,
    Font = Enum.Font.GothamBold,
    TextXAlignment = Enum.TextXAlignment.Left
}, Main)

local Status = Make("TextLabel", {
    Name = "Status",
    Size = UDim2.new(1, -24, 0, 22),
    Position = UDim2.fromOffset(12, 38),
    BackgroundTransparency = 1,
    Text = Config and (Config.SeaName .. " detectado | UI pronta") or ("UI pronta | Selecione Sea | ID: " .. tostring(game.PlaceId)),
    TextColor3 = Config and Color3.fromRGB(170, 180, 195) or Color3.fromRGB(255, 170, 100),
    TextSize = 10,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left
}, Main)

local Toggle
local SeaButtons = {}
local SeaButtonData = {
    {id = 2753915549, label = "SEA 1"},
    {id = 4442272183, label = "SEA 2"},
    {id = 7449423635, label = "SEA 3"}
}
for index, item in ipairs(SeaButtonData) do
    local button = Make("TextButton", {
        Name = item.label:gsub(" ", ""),
        Size = UDim2.new(1/3, -14, 0, 22),
        Position = UDim2.new((index - 1)/3, 12, 0, 60),
        BackgroundColor3 = Config == Configs[item.id] and Color3.fromRGB(26, 123, 91) or Color3.fromRGB(42, 48, 61),
        BorderSizePixel = 0,
        Text = item.label,
        TextColor3 = Color3.fromRGB(240, 244, 250),
        TextSize = 10,
        Font = Enum.Font.GothamBold,
        AutoButtonColor = true
    }, Main)
    Make("UICorner", {CornerRadius = UDim.new(0, 6)}, button)
    SeaButtons[item.id] = button
end

Toggle = Make("TextButton", {
    Name = "FarmToggle",
    Size = UDim2.new(1, -24, 0, 38),
    Position = UDim2.fromOffset(12, 87),
    BackgroundColor3 = Color3.fromRGB(42, 48, 61),
    BorderSizePixel = 0,
    Text = "Melee Mastery Farm: OFF",
    TextColor3 = Color3.fromRGB(240, 244, 250),
    TextSize = 12,
    Font = Enum.Font.GothamBold,
    AutoButtonColor = true
}, Main)
Make("UICorner", {CornerRadius = UDim.new(0, 7)}, Toggle)

local function SetSelectedSea(placeId)
    if Enabled then
        Enabled = false
        LoopToken += 1
        MoveToken += 1
        CurrentTarget = nil
        if StopHover then StopHover() end
        if StopFlight then StopFlight() end
        SetNoclip(false)
        if RecoverIfBelowWorld then RecoverIfBelowWorld() end
    end
    Config = Configs[placeId]
    for id, button in pairs(SeaButtons) do
        button.BackgroundColor3 = id == placeId and Color3.fromRGB(26, 123, 91) or Color3.fromRGB(42, 48, 61)
    end
    if Config then
        Status.Text = Config.SeaName .. " | alvo direto: " .. Config.TargetLabel
        Status.TextColor3 = Color3.fromRGB(170, 220, 190)
        Toggle.Text = "Melee Mastery Farm: OFF"
        Toggle.BackgroundColor3 = Color3.fromRGB(42, 48, 61)
    end
end

for placeId, button in pairs(SeaButtons) do
    button.Activated:Connect(function()
        SetSelectedSea(placeId)
    end)
end

local HeightText = Make("TextLabel", {
    Name = "HeightLabel",
    Size = UDim2.new(1, -24, 0, 20),
    Position = UDim2.fromOffset(12, 130),
    BackgroundTransparency = 1,
    Text = "Altura acima do NPC: " .. Height,
    TextColor3 = Color3.fromRGB(220, 226, 236),
    TextSize = 11,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left
}, Main)

local SliderBack = Make("Frame", {
    Name = "SliderBack",
    Size = UDim2.new(1, -24, 0, 10),
    Position = UDim2.fromOffset(12, 155),
    BackgroundColor3 = Color3.fromRGB(48, 56, 72),
    BorderSizePixel = 0
}, Main)
Make("UICorner", {CornerRadius = UDim.new(1, 0)}, SliderBack)
local SliderFill = Make("Frame", {
    Name = "SliderFill",
    Size = UDim2.new((Height - 20) / 130, 0, 1, 0),
    BackgroundColor3 = Color3.fromRGB(75, 184, 245),
    BorderSizePixel = 0
}, SliderBack)
Make("UICorner", {CornerRadius = UDim.new(1, 0)}, SliderFill)
local SliderButton = Make("TextButton", {
    Name = "SliderButton",
    Size = UDim2.new(1, 0, 0, 28),
    Position = UDim2.new(0, 0, 0.5, -14),
    BackgroundTransparency = 1,
    Text = "",
    AutoButtonColor = false
}, SliderBack)

local Footer = Make("TextLabel", {
    Name = "Footer",
    Size = UDim2.new(1, -24, 0, 17),
    Position = UDim2.fromOffset(12, 179),
    BackgroundTransparency = 1,
    Text = "Sem quest | Hitbox seguro + auto-click (v6.1)",
    TextColor3 = Color3.fromRGB(125, 137, 157),
    TextSize = 9,
    Font = Enum.Font.Gotham,
    TextXAlignment = Enum.TextXAlignment.Left
}, Main)

do
    local dragging = false
    local dragStart, startPosition
    Header.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = true
            dragStart = input.Position
            startPosition = Main.Position
        end
    end)
    UserInputService.InputChanged:Connect(function(input)
        if dragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
            local delta = input.Position - dragStart
            Main.Position = UDim2.new(startPosition.X.Scale, startPosition.X.Offset + delta.X,
                startPosition.Y.Scale, startPosition.Y.Offset + delta.Y)
        end
    end)
    UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
            dragging = false
        end
    end)
end

local function UpdateHeightFromX(screenX)
    local left = SliderBack.AbsolutePosition.X
    local width = math.max(SliderBack.AbsoluteSize.X, 1)
    local alpha = math.clamp((screenX - left) / width, 0, 1)
    Height = math.clamp(math.floor(20 + alpha * 130 + 0.5), 20, 150)
    SliderFill.Size = UDim2.new((Height - 20) / 130, 0, 1, 0)
    HeightText.Text = "Altura acima do NPC: " .. Height
end

local sliderDragging = false
SliderButton.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = true
        UpdateHeightFromX(input.Position.X)
    end
end)
UserInputService.InputChanged:Connect(function(input)
    if sliderDragging and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        UpdateHeightFromX(input.Position.X)
    end
end)
UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        sliderDragging = false
    end
end)

local function GetCharacterParts()
    local character = Player.Character
    if not character then return nil, nil, nil end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    local root = character:FindFirstChild("HumanoidRootPart")
    if not humanoid or not root or humanoid.Health <= 0 then return nil, nil, nil end

    if not NoclipEnabled and root.Position.Y > 5 then
        LastSafeCFrame = root.CFrame
        SharedEnvironment.__MeleeMasteryLastSafe = LastSafeCFrame
    end
    return character, humanoid, root
end

-- Noclip forçado continuamente (evita colisão com NPC)
SetNoclip = function(enabled)
    NoclipEnabled = enabled
    local character = Player.Character
    if not character then return end

    if enabled then
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                if OriginalCollision[part] == nil then
                    OriginalCollision[part] = part.CanCollide
                end
                part.CanCollide = false
            end
        end

        if NoclipConnection then
            pcall(function() NoclipConnection:Disconnect() end)
        end
        NoclipConnection = RunService.Stepped:Connect(function()
            if not NoclipEnabled or not IsCurrentSession() then return end
            local char = Player.Character
            if not char then return end
            for _, part in ipairs(char:GetDescendants()) do
                if part:IsA("BasePart") and part.CanCollide then
                    part.CanCollide = false
                end
            end
        end)
    else
        if NoclipConnection then
            pcall(function() NoclipConnection:Disconnect() end)
            NoclipConnection = nil
        end
        for _, part in ipairs(character:GetDescendants()) do
            if part:IsA("BasePart") then
                local original = OriginalCollision[part]
                if original ~= nil then
                    part.CanCollide = original
                    OriginalCollision[part] = nil
                end
            end
        end
    end
end

-- Clamp de velocidade: impede valores extremos que costumam fechar o Delta
local function StartVelocityClamp()
    if VelocityClampConnection then
        pcall(function() VelocityClampConnection:Disconnect() end)
    end
    VelocityClampConnection = RunService.Heartbeat:Connect(function()
        if not IsCurrentSession() then return end
        local _, _, root = GetCharacterParts()
        if not root then return end
        local vel = root.AssemblyLinearVelocity
        local maxSpeed = 420
        if vel.Magnitude > maxSpeed then
            root.AssemblyLinearVelocity = vel.Unit * maxSpeed
        end
        -- Evita NaN / Inf
        if vel ~= vel or vel.X ~= vel.X then
            root.AssemblyLinearVelocity = Vector3.zero
        end
    end)
end

local function StopVelocityClamp()
    if VelocityClampConnection then
        pcall(function() VelocityClampConnection:Disconnect() end)
        VelocityClampConnection = nil
    end
end

local function IsTargetName(name)
    if not Config then return false end
    return table.find(Config.Enemies, name) ~= nil
end

local function GetTarget()
    local _, _, playerRoot = GetCharacterParts()
    if not playerRoot or not Config then return nil end

    Enemies = workspace:FindFirstChild("Enemies")
    if not Enemies then
        if Status then Status.Text = "Aguardando pasta Enemies do jogo..." end
        return nil
    end

    -- Mantém o alvo atual enquanto ele estiver vivo
    if CurrentTarget and CurrentTarget.Parent then
        local hum = CurrentTarget:FindFirstChildOfClass("Humanoid")
        local root = CurrentTarget:FindFirstChild("HumanoidRootPart") or CurrentTarget.PrimaryPart
        if hum and hum.Health > 0 and root and IsTargetName(CurrentTarget.Name) then
            return CurrentTarget
        end
    end

    local best, bestDistance = nil, math.huge
    for _, enemy in ipairs(Enemies:GetChildren()) do
        if IsTargetName(enemy.Name) then
            local humanoid = enemy:FindFirstChildOfClass("Humanoid")
            local root = enemy:FindFirstChild("HumanoidRootPart") or enemy.PrimaryPart
            if humanoid and humanoid.Health > 0 and root then
                local distance = (playerRoot.Position - root.Position).Magnitude
                if distance < bestDistance then
                    best, bestDistance = enemy, distance
                end
            end
        end
    end
    CurrentTarget = best
    return best
end

local function MoveSegment(destination, rotation, token)
    local _, _, root = GetCharacterParts()
    if not root then return false end

    if not FlightVelocity or FlightVelocity.Parent ~= root then
        if FlightVelocity then pcall(function() FlightVelocity:Destroy() end) end
        if FlightRotation then pcall(function() FlightRotation:Destroy() end) end

        FlightVelocity = Instance.new("BodyVelocity")
        FlightVelocity.Name = "MeleeMasteryFlightVelocity"
        FlightVelocity.MaxForce = Vector3.new(2.5e5, 2.5e5, 2.5e5)
        FlightVelocity.P = 10000
        FlightVelocity.Velocity = Vector3.zero
        FlightVelocity.Parent = root

        FlightRotation = Instance.new("BodyGyro")
        FlightRotation.Name = "MeleeMasteryFlightRotation"
        FlightRotation.MaxTorque = Vector3.new(2.5e5, 2.5e5, 2.5e5)
        FlightRotation.P = 5000
        FlightRotation.D = 500
        FlightRotation.CFrame = root.CFrame
        FlightRotation.Parent = root
    end

    local currentSpeed = 0
    while Enabled and token == MoveToken and IsCurrentSession() do
        local dt = RunService.Heartbeat:Wait()
        local _, _, currentRoot = GetCharacterParts()
        if not currentRoot then break end

        local delta = destination - currentRoot.Position
        local distance = delta.Magnitude
        if distance <= 4.5 then
            FlightVelocity.Velocity = Vector3.zero
            FlightRotation.CFrame = CFrame.new(currentRoot.Position) * rotation
            currentRoot.AssemblyLinearVelocity = Vector3.zero
            return true
        end

        currentSpeed = math.min(FLIGHT_SPEED, currentSpeed + 600 * dt)
        local brakingSpeed = math.sqrt(2 * 450 * distance)
        local actualSpeed = math.min(currentSpeed, math.max(35, brakingSpeed))
        FlightVelocity.Velocity = delta.Unit * actualSpeed
        FlightRotation.CFrame = CFrame.new(currentRoot.Position) * rotation
    end

    if FlightVelocity then pcall(function() FlightVelocity.Velocity = Vector3.zero end) end
    local _, _, currentRoot = GetCharacterParts()
    if currentRoot then currentRoot.AssemblyLinearVelocity = Vector3.zero end
    return false
end

StopFlight = function()
    if FlightVelocity then
        pcall(function() FlightVelocity:Destroy() end)
        FlightVelocity = nil
    end
    if FlightRotation then
        pcall(function() FlightRotation:Destroy() end)
        FlightRotation = nil
    end
    local _, _, root = GetCharacterParts()
    if root then
        pcall(function()
            root.AssemblyLinearVelocity = Vector3.zero
            root.AssemblyAngularVelocity = Vector3.zero
        end)
    end
end

StopHover = function()
    if HoverMover then
        pcall(function() HoverMover:Destroy() end)
        HoverMover = nil
    end
end

local function HoldAtPosition(position)
    local _, _, root = GetCharacterParts()
    if not root then return end

    if not HoverMover or HoverMover.Parent ~= root then
        StopHover()
        HoverMover = Instance.new("BodyPosition")
        HoverMover.Name = "MeleeMasteryHover"
        HoverMover.MaxForce = Vector3.new(2e5, 3.5e5, 2e5) -- Y um pouco mais forte
        HoverMover.P = 9000
        HoverMover.D = 2000
        HoverMover.Position = position
        HoverMover.Parent = root
    else
        HoverMover.Position = position
    end
end

RecoverIfBelowWorld = function()
    local _, humanoid, root = GetCharacterParts()
    if not root then return end

    local safeCFrame = LastSafeCFrame or (Config and Config.SpawnPoints and Config.SpawnPoints[1])
    if root.Position.Y < 3 and safeCFrame then
        SetNoclip(false)
        StopHover()
        StopFlight()
        root.CFrame = safeCFrame + Vector3.new(0, 8, 0)
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        if humanoid then
            pcall(function() humanoid:ChangeState(Enum.HumanoidStateType.GettingUp) end)
        end
    end
end

local function MoveTo(cf)
    local _, _, root = GetCharacterParts()
    if not root or not Enabled or not IsCurrentSession() then return false end
    if (root.Position - cf.Position).Magnitude <= 14 then return true end

    StopHover()
    MoveToken += 1
    local token = MoveToken
    local destination = cf.Position
    local rotation = cf.Rotation

    SetNoclip(true)
    local cruiseY = math.max(root.Position.Y, destination.Y) + 40
    local liftPoint = Vector3.new(root.Position.X, cruiseY, root.Position.Z)
    local cruisePoint = Vector3.new(destination.X, cruiseY, destination.Z)

    local success = MoveSegment(liftPoint, rotation, token)
    if success then success = MoveSegment(cruisePoint, rotation, token) end
    if success then success = MoveSegment(destination, rotation, token) end

    StopFlight()
    if not Enabled then
        SetNoclip(false)
    end

    if success then
        local _, _, finalRoot = GetCharacterParts()
        if finalRoot and (finalRoot.Position - destination).Magnitude <= 8 then
            finalRoot.AssemblyLinearVelocity = Vector3.zero
            finalRoot.AssemblyAngularVelocity = Vector3.zero
        end
    end
    return success
end

local function EquipMelee()
    local character, humanoid = GetCharacterParts()
    if not character or not humanoid then return false end
    for _, tool in ipairs(character:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == "Melee" then
            return true
        end
    end
    for _, tool in ipairs(Player.Backpack:GetChildren()) do
        if tool:IsA("Tool") and tool.ToolTip == "Melee" then
            pcall(function() humanoid:EquipTool(tool) end)
            return true
        end
    end
    return false
end

local function EnableHaki()
    local character = Player.Character
    if not character or character:FindFirstChild("HasBuso") then return end

    if not CommF or not CommF.Parent then
        local remotes = ReplicatedStorage:FindFirstChild("Remotes")
        CommF = remotes and remotes:FindFirstChild("CommF_") or nil
    end
    if CommF then
        pcall(function() CommF:InvokeServer("Buso") end)
    end
end

local function ClickAttack()
    if os.clock() - lastClick < 0.09 then return end
    lastClick = os.clock()

    local ok = false
    if type(mouse1click) == "function" then
        ok = pcall(mouse1click)
    elseif type(mouse1press) == "function" and type(mouse1release) == "function" then
        ok = pcall(mouse1press)
        task.delay(0.035, function()
            pcall(mouse1release)
        end)
    end

    if not ok then
        pcall(function()
            VirtualUser:CaptureController()
            local camera = workspace.CurrentCamera
            local point = camera and (camera.ViewportSize / 2) or Vector2.new(0, 0)
            VirtualUser:Button1Down(point, camera and camera.CFrame or CFrame.new())
        end)
        task.delay(0.04, function()
            pcall(function()
                local camera = workspace.CurrentCamera
                local point = camera and (camera.ViewportSize / 2) or Vector2.new(0, 0)
                VirtualUser:Button1Up(point, camera and camera.CFrame or CFrame.new())
            end)
        end)
    end
end

-- Aumenta o hitbox do NPC de forma CONTROLADA e proporcional à altura.
-- Assim os ataques melee alcançam quando você está acima.
-- Limite máximo bem mais baixo que as versões antigas (evita crash do Delta).
local function EnlargeTargetHitbox(target)
    local targetRoot = target and (target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart)
    if not targetRoot then return end

    -- Escala com a altura, mas com teto seguro (máx ~60)
    -- Altura 20 → ~32 | Altura 40 → ~48 | Altura 60+ → 60
    local hitboxSize = math.clamp(20 + (Height * 0.7), 28, 60)

    pcall(function()
        targetRoot.Size = Vector3.new(hitboxSize, hitboxSize, hitboxSize)
        targetRoot.CanCollide = false
        targetRoot.Transparency = 1
        targetRoot.Massless = true
    end)

    if type(sethiddenproperty) == "function" then
        pcall(sethiddenproperty, Player, "SimulationRadius", 200)
    end
end

local function FarmLoop(token)
    if not Config then
        Enabled = false
        LoopToken += 1
        MoveToken += 1
        CurrentTarget = nil
        StopHover()
        StopFlight()
        SetNoclip(false)
        StopVelocityClamp()
        Toggle.Text = "Melee Mastery Farm: OFF"
        Toggle.BackgroundColor3 = Color3.fromRGB(42, 48, 61)
        Status.Text = "Escolha SEA 1, SEA 2 ou SEA 3 acima"
        return
    end

    Status.Text = Config.SeaName .. " | alvo direto: " .. Config.TargetLabel .. " | sem missao"
    Status.TextColor3 = Color3.fromRGB(170, 220, 190)

    while Enabled and token == LoopToken and IsCurrentSession() do
        task.wait(0.065)
        local ok, failure = pcall(function()
            local character, humanoid, root = GetCharacterParts()
            if character and humanoid and root then
                local target = GetTarget()
                if target then
                    local targetRoot = target:FindFirstChild("HumanoidRootPart") or target.PrimaryPart
                    if targetRoot then
                        lastSpawnMove = 0

                        -- Offset horizontal maior (4.5 studs) + altura
                        -- Evita ficar exatamente no eixo do NPC
                        local offsetX = 4.5
                        local desiredY = targetRoot.Position.Y + Height
                        local desiredPosition = Vector3.new(
                            targetRoot.Position.X + offsetX,
                            desiredY,
                            targetRoot.Position.Z
                        )

                        local horiz = Vector3.new(root.Position.X - targetRoot.Position.X, 0, root.Position.Z - targetRoot.Position.Z).Magnitude
                        local verticalDiff = root.Position.Y - targetRoot.Position.Y

                        -- Se estiver muito perto horizontalmente ou abaixo da altura desejada, corrige
                        if horiz < 2.5 or verticalDiff < (Height * 0.6) then
                            -- Correção suave por CFrame (só no eixo Y + pequeno X) para sair de dentro
                            local safePos = Vector3.new(
                                targetRoot.Position.X + offsetX,
                                targetRoot.Position.Y + math.max(Height, 28),
                                targetRoot.Position.Z
                            )
                            root.CFrame = CFrame.new(safePos) * (root.CFrame - root.CFrame.Position)
                            root.AssemblyLinearVelocity = Vector3.new(0, 25, 0)
                            desiredPosition = safePos
                        end

                        if (root.Position - desiredPosition).Magnitude > 15 then
                            HoldAtPosition(desiredPosition)
                            MoveTo(CFrame.new(desiredPosition))
                        else
                            SetNoclip(true)
                            HoldAtPosition(desiredPosition)
                        end

                        EquipMelee()
                        EnableHaki()
                        EnlargeTargetHitbox(target)
                        ClickAttack()
                        Status.Text = Config.SeaName .. " | alvo: " .. target.Name .. " | altura " .. tostring(Height)
                        Status.TextColor3 = Color3.fromRGB(170, 220, 190)
                    end
                else
                    CurrentTarget = nil
                    StopHover()
                    if os.clock() - lastSpawnMove > 2.5 then
                        spawnIndex = (spawnIndex % #Config.SpawnPoints) + 1
                        MoveTo(Config.SpawnPoints[spawnIndex])
                        lastSpawnMove = os.clock()
                    end
                    if Status.Text:find("Aguardando pasta Enemies") == nil then
                        Status.Text = Config.SeaName .. " | aguardando reaparecer: " .. Config.TargetLabel
                    end
                end
            else
                Status.Text = "Aguardando personagem carregar..."
                Status.TextColor3 = Color3.fromRGB(255, 190, 100)
            end
        end)
        if not ok then
            Enabled = false
            LoopToken += 1
            MoveToken += 1
            CurrentTarget = nil
            StopHover()
            StopFlight()
            SetNoclip(false)
            StopVelocityClamp()
            Toggle.Text = "Melee Mastery Farm: OFF"
            Toggle.BackgroundColor3 = Color3.fromRGB(42, 48, 61)
            Status.Text = "Erro no farm: " .. string.sub(tostring(failure), 1, 120)
            Status.TextColor3 = Color3.fromRGB(255, 130, 130)
            return
        end
    end
end

Toggle.Activated:Connect(function()
    if not Config then
        Status.Text = "Toque em SEA 1, SEA 2 ou SEA 3 acima"
        Status.TextColor3 = Color3.fromRGB(255, 170, 100)
        return
    end

    Enabled = not Enabled
    if Enabled then
        LoopToken += 1
        local myToken = LoopToken
        CurrentTarget = nil
        SetNoclip(true)
        StartVelocityClamp()
        StopHover()
        StopFlight()
        Toggle.Text = "Melee Mastery Farm: ON"
        Toggle.BackgroundColor3 = Color3.fromRGB(26, 123, 91)
        Status.Text = Config.SeaName .. " | iniciando farm direto: " .. Config.TargetLabel
        Status.TextColor3 = Color3.fromRGB(170, 220, 190)
        task.spawn(FarmLoop, myToken)
    else
        LoopToken += 1
        MoveToken += 1
        CurrentTarget = nil
        StopHover()
        StopFlight()
        SetNoclip(false)
        StopVelocityClamp()
        RecoverIfBelowWorld()
        Toggle.Text = "Melee Mastery Farm: OFF"
        Toggle.BackgroundColor3 = Color3.fromRGB(42, 48, 61)
        Status.Text = Config.SeaName .. " | Farm pausado"
    end
end)

local function SetupCharacter(character)
    task.wait(0.5)
    if not IsCurrentSession() then return end
    StopHover()
    StopFlight()
    SetNoclip(false)

    for _, part in ipairs(character:GetDescendants()) do
        if part:IsA("BasePart") and OriginalCollision[part] ~= nil then
            part.CanCollide = OriginalCollision[part]
            OriginalCollision[part] = nil
        end
    end
    RecoverIfBelowWorld()

    if Enabled then
        SetNoclip(true)
        StartVelocityClamp()
        LoopToken += 1
        task.spawn(FarmLoop, LoopToken)
    end
end

Player.CharacterAdded:Connect(SetupCharacter)

SharedEnvironment.__MeleeMasteryCleanup = function()
    Enabled = false
    LoopToken += 1
    MoveToken += 1
    CurrentTarget = nil
    StopHover()
    StopFlight()
    SetNoclip(false)
    StopVelocityClamp()
    RecoverIfBelowWorld()
    if NoclipConnection then
        pcall(function() NoclipConnection:Disconnect() end)
        NoclipConnection = nil
    end
    if GUI and GUI.Parent then
        GUI:Destroy()
    end
end

print("[MeleeMastery] v6.1 carregada. Hitbox controlado (alcance) + auto-click + anti-sink + clamp de velocidade.")
