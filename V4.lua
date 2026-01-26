-- Zeraa V4 - AutoV4 Complete + FullMoon Server Finder
-- Event-driven, TaskManager, Robust Auto Trial & Auto Train
-- New: FullMoon server scanning & shared jobId file (FoundFMSV.txt)
-- WARNING: Automation may violate Roblox ToS. Use at your own risk.

-- CONFIG (tweak to your needs)
_G.V4_Config = _G.V4_Config or {}
_G.V4_Config.LockTiers = _G.V4_Config.LockTiers or 10
_G.V4_Config.Helper = _G.V4_Config.Helper or { "HelperAccount1", "HelperAccount2" }
_G.V4_Config.V4FarmList = _G.V4_Config.V4FarmList or { "MainAccount1" }

-- FullMoon Finder config
_G.V4_Config.AccountFindSVFullMoon = _G.V4_Config.AccountFindSVFullMoon or false
-- When scanning servers, prefer servers where:
--  - minutesUntilFull <= FullMoonSoonThresholdSeconds OR
--  - minutesUntilEnd >= FullMoonEndThresholdSeconds (i.e., moon already active with enough remaining time)
_G.V4_Config.FullMoonSoonThresholdSeconds = _G.V4_Config.FullMoonSoonThresholdSeconds or (6 * 60) -- 6 minutes before full
_G.V4_Config.FullMoonEndThresholdSeconds = _G.V4_Config.FullMoonEndThresholdSeconds or (6 * 60)  -- 6 minutes left until moon ends
-- File path to save found jobId (executor writefile/readfile area)
_G.V4_Config.FoundFMSV_File = _G.V4_Config.FoundFMSV_File or "Zeraa/FoundFMSV.txt"
_G.V4_Config.TriedServers_File = _G.V4_Config.TriedServers_File or "Zeraa/TriedSV.txt"

-- Auto behavior flags (defaults)
_G.AutoDoor = _G.AutoDoor or false
_G.AutoUseRace = _G.AutoUseRace or false
_G.AutoTrial = _G.AutoTrial or false
_G.AutoTrainV4 = _G.AutoTrainV4 or false
_G.AutoKillPlayers = _G.AutoKillPlayers or false
_G.DebugMode = _G.DebugMode or false  -- set true to print warnings/debug

-- Tunables
local LOOP_INTERVALS = {
    AutoDoor = 0.35,
    AutoTrial = 0.5,
    AutoTrain = 0.45,
    AutoKillPlayers = 0.6,
    AutoBuy = 5,
    AntiIdle = 60,
    RemoteThrottle = 0.22 -- minimum seconds between invokes
}
local DISTANCES = {
    Attack = 60,
    TrialAggro = 1000,
    PvPRange = 800,
    GatherRange = 300
}
local HIGH_FLY_Y = 2000 -- Y coordinate when flying during transformed farm

-- Services
local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local VirtualUser = game:GetService("VirtualUser")
local TeleportService = game:GetService("TeleportService")
local PathfindingService = game:GetService("PathfindingService")
local HttpService = game:GetService("HttpService")

local LocalPlayer = Players.LocalPlayer

-- Utilities
local function dbg(...)
    if _G.DebugMode then
        pcall(function() print("[ZeraaV4 DEBUG]", ...) end)
    end
end

local function safeFind(obj, ...)
    if not obj then return nil end
    local cur = obj
    for i = 1, select("#", ...) do
        local name = select(i, ...)
        if typeof(name) == "string" then
            cur = cur:FindFirstChild(name)
            if not cur then return nil end
        else
            return nil
        end
    end
    return cur
end

local function getCharacter()
    return LocalPlayer and LocalPlayer.Character or nil
end

local function getHRP()
    local char = getCharacter()
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
end

local function isAlive()
    local char = getCharacter()
    if not char then return false end
    local humanoid = char:FindFirstChild("Humanoid")
    return humanoid and humanoid.Health and humanoid.Health > 0
end

-- File helpers (use executor-provided functions if available)
local function fileExists(path)
    if type(isfile) == "function" then
        local ok, res = pcall(function() return isfile(path) end)
        if ok then return res end
    end
    return false
end

local function writeFileSafe(path, contents)
    if type(writefile) == "function" then
        local ok, res = pcall(function() writefile(path, contents) end)
        if not ok then warn("writefile failed:", res) end
        return ok
    else
        warn("writefile not available in this executor. Cannot save:", path)
        return false
    end
end

local function readFileSafe(path)
    if type(readfile) == "function" then
        local ok, res = pcall(function() return readfile(path) end)
        if ok then return res end
    end
    return nil
end

local function appendToFile(path, line)
    local content = ""
    if fileExists(path) then content = readFileSafe(path) or "" end
    content = content .. tostring(line) .. "\n"
    writeFileSafe(path, content)
end

-- Simple remote queue with throttle (to reduce rapid invokes)
local RemoteQueue = {}
RemoteQueue._lastTime = 0
RemoteQueue._queue = {}
RemoteQueue._processing = false

function RemoteQueue:enqueue(fn)
    table.insert(self._queue, fn)
    self:_process()
end

function RemoteQueue:_process()
    if self._processing then return end
    self._processing = true
    spawn(function()
        while #self._queue > 0 do
            local now = tick()
            local delta = now - self._lastTime
            if delta < LOOP_INTERVALS.RemoteThrottle then
                task.wait(LOOP_INTERVALS.RemoteThrottle - delta)
            end
            local fn = table.remove(self._queue, 1)
            pcall(fn)
            self._lastTime = tick()
            task.wait(0.01)
        end
        self._processing = false
    end)
end

local function safeInvoke(name, ...)
    RemoteQueue:enqueue(function()
        local rem = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild(name)
        if not rem and ReplicatedStorage:FindFirstChild(name) then rem = ReplicatedStorage[name] end
        if rem and rem.InvokeServer then
            local ok, res = pcall(function() return rem:InvokeServer(...) end)
            if not ok and _G.DebugMode then warn("InvokeServer", name, res) end
        end
    end)
end

local function safeFire(name, ...)
    RemoteQueue:enqueue(function()
        local rem = ReplicatedStorage:FindFirstChild("Remotes") and ReplicatedStorage.Remotes:FindFirstChild(name)
        if not rem and ReplicatedStorage:FindFirstChild(name) then rem = ReplicatedStorage[name] end
        if rem and rem.FireServer then
            local ok, res = pcall(function() rem:FireServer(...) end)
            if not ok and _G.DebugMode then warn("FireServer", name, res) end
        end
    end)
end

-- VirtualInputManager helper (safe)
local function sendKey(key)
    local ok, vim = pcall(function() return game:GetService("VirtualInputManager") end)
    if ok and vim then
        pcall(function()
            vim:SendKeyEvent(true, key, false, game)
            task.wait(0.08)
            vim:SendKeyEvent(false, key, false, game)
        end)
    end
end

-- SmartMove: teleport if far, tween otherwise; with cleanup
local function SmartMove(targetCFrame)
    if not targetCFrame then return end
    local hrp = getHRP()
    if not hrp then return end
    local dist = (hrp.Position - targetCFrame.Position).Magnitude
    if dist > 2000 then
        hrp.CFrame = targetCFrame
        return
    end

    local speed = 300
    local time = math.clamp(dist / speed, 0.05, 8)
    local info = TweenInfo.new(time, Enum.EasingStyle.Linear)
    local bv = Instance.new("BodyVelocity")
    bv.Velocity = Vector3.new(0,0,0)
    bv.MaxForce = Vector3.new(1e5,1e5,1e5)
    bv.Parent = hrp

    -- Save and disable collisions temporarily
    local char = getCharacter()
    local originalCollides = {}
    if char then
        for _, part in pairs(char:GetDescendants()) do
            if part:IsA("BasePart") then
                originalCollides[part] = part.CanCollide
                part.CanCollide = false
            end
        end
    end

    local tween = TweenService:Create(hrp, info, {CFrame = targetCFrame})
    tween:Play()
    local finished = false
    local function cleanup()
        if finished then return end
        finished = true
        if bv and bv.Parent then pcall(function() bv:Destroy() end) end
        if char then
            for part, val in pairs(originalCollides) do
                if part and part:IsA("BasePart") then
                    pcall(function() part.CanCollide = val end)
                end
            end
        end
    end
    tween.Completed:Connect(cleanup)
    task.delay(time + 2, cleanup)
end

-- Equip weapon: prefer named tools, fallback to first melee
local function EquipWeapon()
    local char = getCharacter()
    local hrp = getHRP()
    if not char or not hrp then return end
    local humanoid = char:FindFirstChild("Humanoid")
    if not humanoid then return end

    -- if already holding tool, return
    local toolInHand = nil
    for _, obj in pairs(char:GetChildren()) do
        if obj:IsA("Tool") then toolInHand = obj; break end
    end
    if toolInHand then return end

    local backpack = LocalPlayer:FindFirstChild("Backpack")
    if not backpack then return end
    local prefer = {"Godhuman", "Cursed Dual Katana"}
    for _, name in pairs(prefer) do
        if backpack:FindFirstChild(name) then
            pcall(function() humanoid:EquipTool(backpack[name]) end)
            return
        end
    end
    for _, v in pairs(backpack:GetChildren()) do
        if v:IsA("Tool") and v.ToolTip == "Melee" then
            pcall(function() humanoid:EquipTool(v) end)
            return
        end
    end
end

-- Safe Attack: controlled cooldown, safe remote calls
local LastAttack = 0
local AttackCD = 0.2
local function SafeAttack()
    if tick() - LastAttack < AttackCD then return end
    if not isAlive() then return end
    LastAttack = tick()

    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return end
    local hrp = getHRP()
    if not hrp then return end
    for _, e in pairs(enemies:GetChildren()) do
        if e and e:FindFirstChild("Humanoid") and e.Humanoid.Health > 0 and e:FindFirstChild("HumanoidRootPart") then
            local root = e.HumanoidRootPart
            if (root.Position - hrp.Position).Magnitude < DISTANCES.Attack then
                pcall(function()
                    VirtualUser:CaptureController()
                    VirtualUser:Button1Down(Vector2.new(1280, 672))
                    task.delay(0.12, function() pcall(function() VirtualUser:Button1Up(Vector2.new(1280, 672)) end) end)
                    local net = ReplicatedStorage:FindFirstChild("Modules") and ReplicatedStorage.Modules:FindFirstChild("Net")
                    if net then
                        if net:FindFirstChild("RegisterAttack") then pcall(function() net["RegisterAttack"]:FireServer(0) end) end
                        if net:FindFirstChild("RegisterHit") then pcall(function() net["RegisterHit"]:FireServer(root) end) end
                    end
                end)
                break
            end
        end
    end
end

-- Auto Haki (Buso)
local function AutoHaki()
    if not isAlive() then return end
    local char = getCharacter()
    if not char then return end
    if not char:FindFirstChild("HasBuso") then
        safeInvoke("CommF_", "Buso")
    end
end

-- Target Manager: returns best target for farming (by name list/pref)
local TargetManager = {}
TargetManager.preferNames = { ["Reborn Skeleton"] = true, ["Living Zombie"] = true, ["Skeleton"] = true }

function TargetManager:getBestFarmTarget()
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return nil end
    local hrp = getHRP()
    if not hrp then return nil end
    -- prefer by name then distance
    local best, bestDist = nil, math.huge
    for _, e in pairs(enemies:GetChildren()) do
        if e and e:FindFirstChild("Humanoid") and e.Humanoid.Health > 0 and e:FindFirstChild("HumanoidRootPart") then
            local n = e.Name
            local dist = (e.HumanoidRootPart.Position - hrp.Position).Magnitude
            if dist < 1500 then
                local score = dist
                if self.preferNames[n] then score = score - 200 -- favor
                end
                if score < bestDist then bestDist = score; best = e end
            end
        end
    end
    return best
end

-- Gather nearby mobs (gentle)
local function gatherNearbyTo(target)
    if not target or not target:FindFirstChild("HumanoidRootPart") then return end
    local enemies = Workspace:FindFirstChild("Enemies")
    if not enemies then return end
    local hrp = getHRP()
    if not hrp then return end
    for _, v in pairs(enemies:GetChildren()) do
        if v and v:FindFirstChild("HumanoidRootPart") and (v.HumanoidRootPart.Position - hrp.Position).Magnitude < DISTANCES.GatherRange then
            pcall(function()
                v.HumanoidRootPart.CFrame = target.HumanoidRootPart.CFrame
                v.HumanoidRootPart.CanCollide = false
            end)
        end
    end
end

-- Trial logic per race (improved)
local ToT_Center = CFrame.new(28282, 14896, -11)
local RaceDoors = {
    ["Human"] = CFrame.new(29221, 14890, -206),
    ["Skypiea"] = CFrame.new(28960, 14919, 235),
    ["Fishman"] = CFrame.new(28231, 14890, -211),
    ["Mink"] = CFrame.new(29012, 14890, -380),
    ["Ghoul"] = CFrame.new(28674, 14890, 445),
    ["Cyborg"] = CFrame.new(28502, 14895, -423)
}

local function findFinishPartByHeuristics()
    if not Workspace:FindFirstChild("Map") then return nil end
    local map = Workspace.Map
    for _, v in pairs(map:GetDescendants()) do
        if v:IsA("BasePart") and (v.Name == "FinishPoint" or v.Name == "EndPoint" or v.Name:lower():find("finish")) then
            return v
        end
    end
    return nil
end

-- Determine if transformed: check character flag or Data-based flag
local function isTransformed()
    local char = getCharacter()
    if char and char:FindFirstChild("RaceTransformed") then return true end
    local data = LocalPlayer:FindFirstChild("Data")
    if data then
        local v = data:FindFirstChild("RaceTransformed") or data:FindFirstChild("Transformed") or data:FindFirstChild("IsTransformed")
        if v and (v.Value == true or v.Value == 1) then return true end
    end
    return false
end

-- AutoTrial handler (single iteration)
local function handleAutoTrialIteration()
    if not isAlive() then return end
    local data = LocalPlayer:FindFirstChild("Data")
    local race = data and data:FindFirstChild("Race") and data.Race.Value or nil
    if not race then return end

    local hrp = getHRP()
    if not hrp then return end

    if race == "Human" or race == "Ghoul" then
        local enemies = Workspace:FindFirstChild("Enemies")
        if enemies then
            for _, v in pairs(enemies:GetChildren()) do
                if v and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 and v:FindFirstChild("HumanoidRootPart") then
                    local root = v.HumanoidRootPart
                    if (root.Position - hrp.Position).Magnitude < DISTANCES.TrialAggro then
                        SmartMove(root.CFrame * CFrame.new(0,5,0))
                        AutoHaki()
                        EquipWeapon()
                        SafeAttack()
                        pcall(function()
                            root.CFrame = hrp.CFrame * CFrame.new(0,0,-4)
                            root.CanCollide = false
                        end)
                    end
                end
            end
        end

    elseif race == "Mink" then
        local finish = findFinishPartByHeuristics()
        if finish and finish:IsA("BasePart") then
            local hrp = getHRP()
            if hrp then hrp.CFrame = finish.CFrame end
        end

    elseif race == "Skypiea" or race == "Angel" then
        -- Try to find sky trial model and endpoint
        local skyTrial = Workspace:FindFirstChild("Map") and Workspace.Map:FindFirstChild("SkyTrial")
        if skyTrial and skyTrial:IsA("Model") then
            local endPart = skyTrial:FindFirstChild("snowisland_Cylinder.081") or skyTrial:FindFirstChildWhichIsA("BasePart")
            if endPart then SmartMove(endPart.CFrame * CFrame.new(0,5,0)) end
        end

    elseif race == "Cyborg" then
        if (getHRP().Position - ToT_Center.Position).Magnitude > 500 then
            -- move back to ToT to bypass trial if needed
            local hrp = getHRP()
            if hrp then hrp.CFrame = ToT_Center end
        end

    elseif race == "Fishman" then
        local sea = Workspace:FindFirstChild("SeaBeasts")
        if sea then
            for _, v in pairs(sea:GetChildren()) do
                if v and v:FindFirstChild("HumanoidRootPart") and v:FindFirstChild("Humanoid") and v.Humanoid.Health > 0 then
                    SmartMove(v.HumanoidRootPart.CFrame * CFrame.new(0, 50, 0))
                    EquipWeapon()
                    -- Spam combo keys safely
                    sendKey("Z"); task.wait(0.06); sendKey("X"); task.wait(0.06); sendKey("C")
                end
            end
        end
    end
end

-- AutoTrain (Maru Style) main loop iteration
local function handleAutoTrainIteration()
    if not isAlive() then return end
    local char = getCharacter()
    if not char then return end

    if isTransformed() then
        -- Stage: transformed -> fly up and spam skill to keep farming while up
        local hrp = getHRP()
        if not hrp then return end
        local targetFly = CFrame.new(hrp.Position.X, HIGH_FLY_Y, hrp.Position.Z)
        SmartMove(targetFly)
        -- spam a skill occasionally to maintain combat and gain XP
        if tick() % 2 < 0.3 then
            sendKey("Z")
        end
    else
        -- Stage: farm nộ on ground -> when ready, use race and transform
        local target = TargetManager:getBestFarmTarget()
        if target and target:FindFirstChild("HumanoidRootPart") then
            SmartMove(target.HumanoidRootPart.CFrame * CFrame.new(0,5,0))
            AutoHaki()
            EquipWeapon()
            SafeAttack()
            gatherNearbyTo(target)
            -- attempt to activate race when ready (single press)
            sendKey("Y")
        else
            -- go to training area
            SmartMove(CFrame.new(-9513, 164, 5786)) -- train mob CFrame
        end
    end
end

-- PvP: auto kill players in PvP area
local function handleAutoKillPlayersIteration()
    if not isAlive() then return end
    local hrp = getHRP()
    if not hrp then return end
    for _, pl in pairs(Players:GetPlayers()) do
        if pl ~= LocalPlayer and pl.Character and pl.Character:FindFirstChild("Humanoid") and pl.Character.Humanoid.Health > 0 then
            local otherHrp = pl.Character:FindFirstChild("HumanoidRootPart")
            if otherHrp and (otherHrp.Position - hrp.Position).Magnitude < DISTANCES.PvPRange then
                SmartMove(otherHrp.CFrame * CFrame.new(0,4,0))
                AutoHaki()
                EquipWeapon()
                SafeAttack()
                sendKey("Z"); sendKey("X")
            end
        end
    end
end

-- AutoBuyGear background
local function handleAutoBuyIteration()
    safeInvoke("CommF_", "UpgradeRace", "Buy")
end

-- Anti Idle
local function handleAntiIdleIteration()
    pcall(function()
        VirtualUser:CaptureController()
        VirtualUser:ClickButton2(Vector2.new())
    end)
end

-- Task Manager (start/stop tasks)
local TaskManager = {}
TaskManager.tasks = {}

function TaskManager:start(name, fn, interval)
    if self.tasks[name] then return end
    local handle = { stopped = false }
    self.tasks[name] = handle
    spawn(function()
        while not handle.stopped do
            local ok, err = pcall(fn)
            if not ok and _G.DebugMode then warn("Task", name, "error:", err) end
            task.wait(interval or 0.5)
        end
    end)
    dbg("Started task", name)
end

function TaskManager:stop(name)
    local t = self.tasks[name]
    if t then t.stopped = true; self.tasks[name] = nil; dbg("Stopped task", name) end
end

function TaskManager:stopAll()
    for name, t in pairs(self.tasks) do
        t.stopped = true
        self.tasks[name] = nil
    end
    dbg("Stopped all tasks")
end

function TaskManager:status(name)
    return self.tasks[name] ~= nil
end

-- Lifecycle: start/stop core tasks depending on flags
local function refreshTasks()
    if _G.AutoDoor then
        TaskManager:start("AutoDoor", function()
            local hrp = getHRP()
            if not hrp then return end
            if hrp.Position.Y < 14000 then
                hrp.CFrame = ToT_Center
            else
                local data = LocalPlayer:FindFirstChild("Data")
                local race = data and data.Race and data.Race.Value
                if race and RaceDoors[race] then SmartMove(RaceDoors[race]) end
            end
        end, LOOP_INTERVALS.AutoDoor)
    else
        TaskManager:stop("AutoDoor")
    end

    if _G.AutoUseRace then
        TaskManager:start("AutoUseRace", function()
            if not isAlive() then return end
            pcall(function()
                local cam = Workspace.CurrentCamera
                if cam and game.Lighting and game.Lighting.GetMoonDirection then
                    cam.CFrame = CFrame.lookAt(cam.CFrame.Position, game.Lighting:GetMoonDirection() * 10000)
                end
                safeFire("CommE", "ActivateAbility")
            end)
        end, 1)
    else
        TaskManager:stop("AutoUseRace")
    end

    if _G.AutoTrial then
        TaskManager:start("AutoTrial", function() handleAutoTrialIteration() end, LOOP_INTERVALS.AutoTrial)
    else
        TaskManager:stop("AutoTrial")
    end

    if _G.AutoTrainV4 then
        TaskManager:start("AutoTrain", function() handleAutoTrainIteration() end, LOOP_INTERVALS.AutoTrain)
    else
        TaskManager:stop("AutoTrain")
    end

    if _G.AutoKillPlayers then
        TaskManager:start("AutoKillPlayers", function() handleAutoKillPlayersIteration() end, LOOP_INTERVALS.AutoKillPlayers)
    else
        TaskManager:stop("AutoKillPlayers")
    end

    -- Always run auto-buy and anti-idle as background if not present
    TaskManager:start("AutoBuyGear", handleAutoBuyIteration, LOOP_INTERVALS.AutoBuy)
    TaskManager:start("AntiIdle", handleAntiIdleIteration, LOOP_INTERVALS.AntiIdle)
end

-- Character lifecycle: restore equipment, re-initialize
local function onCharacterAdded(char)
    dbg("CharacterAdded")
    -- give a small delay for parts to load
    task.wait(0.6)
    EquipWeapon()
    -- ensure tasks respond to new char
    refreshTasks()
end

local function onCharacterRemoving()
    dbg("CharacterRemoving")
end

-- Hook player character
if LocalPlayer then
    if LocalPlayer.Character then
        onCharacterAdded(LocalPlayer.Character)
    end
    LocalPlayer.CharacterAdded:Connect(function(c) onCharacterAdded(c) end)
    LocalPlayer.CharacterRemoving:Connect(function() onCharacterRemoving() end)
end

-- React to flags change (exposed as _G toggles) - basic watcher
spawn(function()
    local prev = {
        AutoDoor = _G.AutoDoor,
        AutoUseRace = _G.AutoUseRace,
        AutoTrial = _G.AutoTrial,
        AutoTrainV4 = _G.AutoTrainV4,
        AutoKillPlayers = _G.AutoKillPlayers
    }
    while task.wait(0.6) do
        if _G.AutoDoor ~= prev.AutoDoor or _G.AutoUseRace ~= prev.AutoUseRace or _G.AutoTrial ~= prev.AutoTrial or _G.AutoTrainV4 ~= prev.AutoTrainV4 or _G.AutoKillPlayers ~= prev.AutoKillPlayers then
            prev.AutoDoor = _G.AutoDoor
            prev.AutoUseRace = _G.AutoUseRace
            prev.AutoTrial = _G.AutoTrial
            prev.AutoTrainV4 = _G.AutoTrainV4
            prev.AutoKillPlayers = _G.AutoKillPlayers
            refreshTasks()
        end
    end
end)

-- FullMoon server detection heuristics
-- This function attempts to detect a moon timer/state on the current server using several common patterns.
-- Returns:
--   {found = true/false, isFull = true/false, secondsUntilFull = number or nil, secondsUntilEnd = number or nil}
local function checkCurrentServerMoon()
    local result = { found = false, isFull = false, secondsUntilFull = nil, secondsUntilEnd = nil }

    -- Heuristic 1: Look in Workspace for known objects
    pcall(function()
        -- common possibilities in various scripts/games
        local candidates = {}
        if Workspace:FindFirstChild("Moon") then table.insert(candidates, Workspace.Moon) end
        if Workspace:FindFirstChild("FullMoon") then table.insert(candidates, Workspace.FullMoon) end
        if Workspace:FindFirstChild("MoonEvent") then table.insert(candidates, Workspace.MoonEvent) end
        if Workspace:FindFirstChild("Event") then table.insert(candidates, Workspace.Event) end

        for _, obj in pairs(Workspace:GetDescendants()) do
            if obj:IsA("NumberValue") or obj:IsA("IntValue") or obj:IsA("BoolValue") or obj:IsA("StringValue") or obj:IsA("ObjectValue") then
                local lname = obj.Name:lower()
                if lname:find("moon") or lname:find("fullmoon") or lname:find("moonstart") or lname:find("moon_time") then
                    table.insert(candidates, obj)
                end
            end
        end

        -- inspect candidates
        for _, c in pairs(candidates) do
            if not c then continue end
            -- check boolean flags
            if c:IsA("BoolValue") then
                result.found = true
                result.isFull = c.Value
            end
            -- number or int values as timers or minutes
            if c:IsA("NumberValue") or c:IsA("IntValue") then
                result.found = true
                local v = c.Value
                -- if value seems like seconds or minutes heuristics:
                if v > 1000 then
                    -- probably in seconds (large)
                    -- treat as seconds until full or seconds left
                    if tostring(c.Name):lower():find("until") or tostring(c.Name):lower():find("left") or tostring(c.Name):lower():find("time") then
                        result.secondsUntilFull = tonumber(v)
                    end
                else
                    -- treat as minutes maybe
                    if tostring(c.Name):lower():find("until") then
                        result.secondsUntilFull = tonumber(v) * 60
                    elseif tostring(c.Name):lower():find("left") or tostring(c.Name):lower():find("remaining") then
                        result.secondsUntilEnd = tonumber(v) * 60
                    end
                end
            end

            -- Object with attributes (some games use attributes on parts)
            if c:IsA("BasePart") or c:IsA("Model") then
                local ok, attrs = pcall(function() return c:GetAttributes() end)
                if ok and attrs then
                    -- check common attribute names
                    if attrs.IsFullMoon ~= nil then
                        result.found = true
                        result.isFull = attrs.IsFullMoon == true
                    end
                    if attrs.SecondsUntilFull ~= nil then
                        result.found = true
                        result.secondsUntilFull = tonumber(attrs.SecondsUntilFull)
                    end
                    if attrs.SecondsUntilEnd ~= nil then
                        result.found = true
                        result.secondsUntilEnd = tonumber(attrs.SecondsUntilEnd)
                    end
                    if attrs.MinutesUntilFull ~= nil then
                        result.found = true
                        result.secondsUntilFull = tonumber(attrs.MinutesUntilFull) * 60
                    end
                    if attrs.MinutesUntilEnd ~= nil then
                        result.found = true
                        result.secondsUntilEnd = tonumber(attrs.MinutesUntilEnd) * 60
                    end
                end
            end
        end
    end)

    -- Heuristic 2: check ReplicatedStorage or Modules for common values
    pcall(function()
        local rs = ReplicatedStorage
        if rs then
            for _, name in pairs({"FullMoon", "Moon", "MoonData", "MoonTimer", "EventData"}) do
                local node = rs:FindFirstChild(name)
                if node and not result.found then
                    -- try to read children values
                    for _, child in pairs(node:GetDescendants()) do
                        if child:IsA("NumberValue") or child:IsA("IntValue") then
                            local lname = child.Name:lower()
                            result.found = true
                            if lname:find("until") or lname:find("time") then
                                local v = child.Value
                                if v and v > 0 then result.secondsUntilFull = tonumber(v) end
                            elseif lname:find("left") or lname:find("end") or lname:find("remain") then
                                local v = child.Value
                                if v and v > 0 then result.secondsUntilEnd = tonumber(v) end
                            end
                        elseif child:IsA("BoolValue") then
                            result.found = true
                            if child.Name:lower():find("full") then result.isFull = child.Value end
                        end
                    end
                end
            end
        end
    end)

    -- Heuristic 3: Lighting cues (some games use Lighting/TimeOfDay or effects)
    pcall(function()
        local light = game:GetService("Lighting")
        if light then
            -- some devs set Lighting:SetMinutesBeforeFullMoon or similar; not reliable
            -- check for custom attributes on Lighting
            local ok, attrs = pcall(function() return light:GetAttributes() end)
            if ok and attrs then
                if attrs.IsFullMoon ~= nil then
                    result.found = true
                    result.isFull = attrs.IsFullMoon == true
                end
                if attrs.SecondsUntilFull ~= nil then
                    result.found = true
                    result.secondsUntilFull = tonumber(attrs.SecondsUntilFull)
                end
            end
        end
    end)

    -- Additional heuristic: check LocalPlayer.Data if present
    pcall(function()
        local data = LocalPlayer:FindFirstChild("Data")
        if data then
            for _, child in pairs(data:GetDescendants()) do
                if child:IsA("NumberValue") or child:IsA("IntValue") then
                    local lname = child.Name:lower()
                    if lname:find("moon") or lname:find("full") or lname:find("moon_time") then
                        result.found = true
                        if lname:find("until") or lname:find("time") then result.secondsUntilFull = tonumber(child.Value) end
                        if lname:find("left") or lname:find("end") then result.secondsUntilEnd = tonumber(child.Value) end
                    end
                elseif child:IsA("BoolValue") then
                    local lname = child.Name:lower()
                    if lname:find("full") or lname:find("ismoon") then
                        result.found = true
                        result.isFull = child.Value
                    end
                end
            end
        end
    end)

    -- Final normalization: if we have minutes values (rare) convert them to seconds already attempted above
    -- If nothing found, return found = false
    return result
end

-- Save found server jobId to file for other accs/helpers to read
local function saveFoundServer(jobId)
    if not jobId then return false end
    local ok = writeFileSafe(_G.V4_Config.FoundFMSV_File, tostring(jobId))
    if ok then
        dbg("Saved Found FullMoon jobId:", jobId)
    end
    return ok
end

local function readFoundServer()
    if not fileExists(_G.V4_Config.FoundFMSV_File) then return nil end
    local content = readFileSafe(_G.V4_Config.FoundFMSV_File)
    if not content then return nil end
    return tostring(content):gsub("%s+", "")
end

-- Server listing via Roblox games API
-- returns table of server entries {id = jobId, playing = n, maxPlayers = n}
local function fetchServerList(cursor)
    local placeId = tostring(game.PlaceId)
    local url = "https://games.roblox.com/v1/games/" .. placeId .. "/servers/Public?sortOrder=Desc&limit=100"
    if cursor and cursor ~= "" then
        url = url .. "&cursor=" .. HttpService:UrlEncode(cursor)
    end
    local ok, res = pcall(function() return HttpService:GetAsync(url, true) end)
    if not ok or not res or res == "" then
        return nil
    end
    local decoded = nil
    pcall(function() decoded = HttpService:JSONDecode(res) end)
    return decoded
end

-- Choose server to hop to: prefer those with space and not in tried list
local function pickServerFromList(serverList, tried)
    if not serverList or not serverList.data then return nil end
    for _, s in pairs(serverList.data) do
        local jobId = tostring(s.id or s.idStr or s.guid or s.jobId)
        local playing = s.playing or s.players or 0
        local maxp = s.maxPlayers or s.max or 0
        if jobId and jobId ~= tostring(game.JobId) and (not tried[jobId]) then
            -- pick server (optionally prefer near-full servers if you want high mob spawn)
            return jobId
        end
    end
    return nil
end

-- Mark jobId as tried in TriedServers_File
local function markServerTried(jobId)
    if not jobId then return end
    local content = ""
    if fileExists(_G.V4_Config.TriedServers_File) then content = readFileSafe(_G.V4_Config.TriedServers_File) or "" end
    -- append if not already present
    if not tostring(content):find(jobId) then
        appendToFile(_G.V4_Config.TriedServers_File, jobId)
    end
end

-- Build tried set
local function loadTriedSet()
    local set = {}
    if fileExists(_G.V4_Config.TriedServers_File) then
        local content = readFileSafe(_G.V4_Config.TriedServers_File) or ""
        for line in string.gmatch(content, "[^\r\n]+") do
            set[tostring(line)] = true
        end
    end
    return set
end

-- Clear tried set (helper)
local function clearTried()
    if type(writefile) == "function" then
        pcall(function() writefile(_G.V4_Config.TriedServers_File, "") end)
    end
end

-- MAIN FullMoon scanning routine:
-- On each server startup (script run), if AccountFindSVFullMoon enabled, check current server's moon.
-- If server satisfies condition, save jobId to FoundFMSV_File and stop scanning.
-- Otherwise, fetch server list and teleport to new candidate server (TeleportToPlaceInstance). Mark tried.
-- Note: TeleportToPlaceInstance will move you to a new server and script restarts there — this is intended behavior.
local function performFullMoonScanOnce()
    if not _G.V4_Config.AccountFindSVFullMoon then return end
    -- Check current server for moon
    local info = checkCurrentServerMoon()
    dbg("FullMoon check on current server", info and HttpService:JSONEncode(info) or "nil")
    if info and info.found then
        -- Evaluate condition:
        -- If already full and enough time left => good
        if info.isFull and (not info.secondsUntilEnd or info.secondsUntilEnd >= _G.V4_Config.FullMoonEndThresholdSeconds) then
            saveFoundServer(game.JobId)
            pcall(function() game.StarterGui:SetCore("SendNotification", {Title="ZeraaV4", Text = "Found server with Full Moon: " .. tostring(game.JobId), Duration = 5}) end)
            return true
        end
        -- If not full but will be within SoonThreshold
        if (info.secondsUntilFull and info.secondsUntilFull <= _G.V4_Config.FullMoonSoonThresholdSeconds) then
            saveFoundServer(game.JobId)
            pcall(function() game.StarterGui:SetCore("SendNotification", {Title="ZeraaV4", Text = "Server will be FullMoon soon: " .. tostring(game.JobId) .. " in " .. tostring(math.floor((info.secondsUntilFull or 0)/60)) .. "m", Duration = 5}) end)
            return true
        end
    end

    -- Not found here: scan other servers and teleport
    -- Build tried set
    local tried = loadTriedSet()
    -- If tried file is huge, consider clearing
    local maxAttempts = 60 -- cap number of teleports per run to avoid infinite loops
    local attempts = 0
    local cursor = nil

    while attempts < maxAttempts do
        local servers = fetchServerList(cursor)
        if not servers then
            dbg("Failed to fetch server list (FullMoonScanner)")
            break
        end
        local job = pickServerFromList(servers, tried)
        if job then
            -- mark as tried and teleport
            markServerTried(job)
            pcall(function() game.StarterGui:SetCore("SendNotification", {Title="ZeraaV4", Text = "Trying server: " .. job, Duration = 3}) end)
            -- Teleport. After teleport script restarts on target server and will run performFullMoonScanOnce again.
            pcall(function()
                TeleportService:TeleportToPlaceInstance(game.PlaceId, job, LocalPlayer)
            end)
            return false -- function won't continue after teleport, but return for clarity
        end
        -- If cursor for pagination exists, advance
        cursor = servers.nextPageCursor
        if not cursor then break end
        attempts = attempts + 1
        task.wait(0.3)
    end

    -- If we reach here, we failed to find candidate servers
    dbg("FullMoon scan exhausted (no candidate jobs found). Clearing tried list and will retry later.")
    clearTried()
    return false
end

-- If FoundFMSV.txt exists, optionally spam-join that server jobId (helper accounts)
-- SpamJoin behavior: repeatedly attempt TeleportToPlaceInstance to that jobId until success or timeout
local function spamJoinFoundServerLoop()
    if not _G.V4_Config.AccountFindSVFullMoon then return end
    spawn(function()
        while task.wait(2) do
            local saved = readFoundServer()
            if saved and saved ~= "" then
                -- attempt join
                local job = tostring(saved)
                dbg("Attempting spam-join to found job:", job)
                local ok, err = pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId, job, LocalPlayer) end)
                if not ok and _G.DebugMode then
                    warn("TeleportToPlaceInstance failed:", err)
                end
                -- if teleport succeeded script will restart in target server
                task.wait(1.0)
            else
                task.wait(6)
            end
        end
    end)
end

-- If we are in fullmoon-scan mode, run the scan as soon as script starts
spawn(function()
    task.wait(1) -- small startup delay
    if _G.V4_Config.AccountFindSVFullMoon then
        -- If a jobId is already saved and this is not the target, helpers will spam join it
        local savedJob = readFoundServer()
        if savedJob and savedJob ~= "" then
            -- If current server is the saved server, do nothing (we're already in target)
            if tostring(game.JobId) == tostring(savedJob) then
                pcall(function() game.StarterGui:SetCore("SendNotification", {Title="ZeraaV4", Text = "Arrived at saved FullMoon server: " .. tostring(savedJob), Duration = 4}) end)
                -- keep normal AutoV4 tasks running
            else
                -- If you want this account to immediately attempt to join saved server (helper behavior),
                -- call teleport to that jobId (spam join).
                -- By default we will start spamJoin loop to attempt and not force immediate teleport.
                spamJoinFoundServerLoop()
            end
        else
            -- No saved job: perform scan on current server and possibly teleport to candidates
            performFullMoonScanOnce()
        end
    end
end)

-- Notifications (safe)
local function Notify(msg)
    pcall(function()
        game.StarterGui:SetCore("SendNotification", {Title = "Zeraa V4", Text = msg, Duration = 4})
    end)
end

-- Initial start of normal tasks
refreshTasks()

Notify("Zeraa V4 (AutoV4 + FullMoon Finder) loaded. Use _G flags to control behavior.")

-- Exposed quick commands
_G.ZeraaV4 = _G.ZeraaV4 or {}
_G.ZeraaV4.startAll = function()
    _G.AutoDoor = true; _G.AutoUseRace = true; _G.AutoTrial = true; _G.AutoTrainV4 = true; _G.AutoKillPlayers = false
    refreshTasks()
end
_G.ZeraaV4.stopAll = function()
    _G.AutoDoor = false; _G.AutoUseRace = false; _G.AutoTrial = false; _G.AutoTrainV4 = false; _G.AutoKillPlayers = false
    TaskManager:stopAll()
end
_G.ZeraaV4.debug = function(val) _G.DebugMode = val; Notify("DebugMode = " .. tostring(val)) end
_G.ZeraaV4.clearFound = function() if fileExists(_G.V4_Config.FoundFMSV_File) then writeFileSafe(_G.V4_Config.FoundFMSV_File, "") end end
_G.ZeraaV4.clearTried = function() clearTried() end

-- End of file
