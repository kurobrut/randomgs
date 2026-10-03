-- Magic Door single-instance guard.
-- Re-executing this updated script shuts down the previous UPDATED instance first.
local GLOBAL_ENV = (getgenv and getgenv()) or _G

-- Stop the previous updated Magic Door instance before starting this one.
if type(GLOBAL_ENV.__MagicDoorShutdown) == "function" then
    pcall(GLOBAL_ENV.__MagicDoorShutdown)
    GLOBAL_ENV.__MagicDoorShutdown = nil
end

-- Generation token: every new execution invalidates older updated instances,
-- even if the previous one is still finishing initialization.
GLOBAL_ENV.__MagicDoorGeneration = (tonumber(GLOBAL_ENV.__MagicDoorGeneration) or 0) + 1
local MAGIC_DOOR_GENERATION = GLOBAL_ENV.__MagicDoorGeneration

-- Auto Farm order: load player/data -> saved position -> list house -> door -> chat.
local function LoadMain()
    if not game:IsLoaded() then game.Loaded:Wait() end
    --// LOAD RAYFIELD
    local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

    --// SINGLE-INSTANCE / CLEANUP TRACKING
    local runtimeAlive = true
    local trackedConnections = {}
    local shutdownMagicDoor

    local function trackConnection(connection)
        if connection then
            table.insert(trackedConnections, connection)
        end
        return connection
    end

    -- Register an EARLY shutdown immediately. This closes the first updated
    -- instance even if you execute this script again before initialization ends.
    local function earlyShutdown()
        if not runtimeAlive then return end
        runtimeAlive = false

        for _, connection in ipairs(trackedConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(trackedConnections)

        pcall(function() Rayfield:Destroy() end)
    end

    GLOBAL_ENV.__MagicDoorShutdown = earlyShutdown

    --// SERVICES
    local HttpService = game:GetService("HttpService")
    local Players = game:GetService("Players")
    local TeleportService = game:GetService("TeleportService")
    local TextChatService = game:GetService("TextChatService")
    local ReplicatedStorage = game:GetService("ReplicatedStorage")

    local player = Players.LocalPlayer
    while not player do
        task.wait()
        player = Players.LocalPlayer
    end

    --// MODULES
    local Fsys = require(ReplicatedStorage:WaitForChild("Fsys")).load
    local ClientData = Fsys("ClientData")
    local ClientToolManager = Fsys("ClientToolManager")
    local Router = Fsys("RouterClient")

    --// TRADING HUB REMOTES
    local API = ReplicatedStorage:WaitForChild("API")
    local TradingHubButtonPressed = API:WaitForChild("TradingServerAPI/ButtonPressed")
    local TradingHubRequestTeleport = API:WaitForChild("ThemedServersAPI/RequestTeleport")

    --// CONFIG
    local configFolder = "MagicDoorConfigs"
    local configFile = configFolder .. "/MagicDoorSettings.json"

    local settings = {
        PlaceDelay = 2,
        ChatDelay = 10,
        ChatMessage = "",
        ChatMode = "Once Per Server",
        ServerHopDelay = 300,
        PlacementDistance = 6,
        MaxPlacementRetries = 3,
        RetryFailedPlacement = true,
        AutoFarm = false,
        AutoServerHop = false,
        NoTradeHop = false,
        AutoAcceptTrades = false,
        TradeMode = "Everyone",
        TradeWhitelist = "",
        AutoTeleportOnJoin = false,
        SavedCFrame = nil,
        MinFreeSlots = 1,
        AvoidVisitedServers = true,
        Notifications = true,
        DebugLogging = false,
    }

    local function debugPrint(...)
        if settings.DebugLogging then
            print("[MagicDoor]", ...)
        end
    end

    local function notify(title, content, duration)
        if not settings.Notifications then
            return
        end

        pcall(function()
            Rayfield:Notify({
                Title = title,
                Content = content,
                Duration = duration or 3,
            })
        end)
    end

    if not isfolder(configFolder) then
        makefolder(configFolder)
    end

    local function mergeSettings(data)
        if type(data) ~= "table" then
            return
        end

        for key, defaultValue in pairs(settings) do
            if data[key] ~= nil and typeof(data[key]) == typeof(defaultValue) then
                settings[key] = data[key]
            end
        end

        -- SavedCFrame defaults to nil, so it is restored separately.
        if type(data.SavedCFrame) == "table" then
            settings.SavedCFrame = data.SavedCFrame
        end
    end

    if isfile(configFile) then
        local ok, data = pcall(function()
            return HttpService:JSONDecode(readfile(configFile))
        end)

        if ok then
            mergeSettings(data)
        end
    end

    local function saveConfig()
        local ok, err = pcall(function()
            writefile(configFile, HttpService:JSONEncode(settings))
        end)

        if not ok then
            warn("[MagicDoor] Config save failed:", err)
        end
    end

    -- Automation states are restored from MagicDoorSettings.json after a hop/rejoin.
    -- Do not force them OFF here, otherwise the saved ON state is lost on startup.

    --// RUNTIME STATE
    local state = {
        farmSession = 0,
        hopSession = 0,
        noTradeHopSession = 0,
        farmLoopActive = false,
        hopLoopActive = false,
        noTradeHopLoopActive = false,
        placing = false,
        sendingChat = false,
        teleporting = false,
        teleportRequest = 0,
        chatSentThisServer = false,
        preparedJobId = nil,
        houseListed = false,
        inTrade = false,
        tradeSignalName = "None",
        lastTradeAcceptedAt = os.clock(),
        activeDoorInstance = nil,
        activeDoorPlacedAt = nil,
        noTradeExpiredLogged = false,
        sessionStartedAt = os.clock(),
        stats = {
            DoorsPlaced = 0,
            PlacementFailures = 0,
            ChatsSent = 0,
            ServersVisited = 1,
            HubRequests = 0,
            TradesAccepted = 0,
        },
        visitedServers = {},
    }

    if game.JobId and game.JobId ~= "" then
        state.visitedServers[game.JobId] = true
    end

    --// TELEPORT TO TRADING HUB
    local function teleportToTradingHub(showNotification, isActive)
        if isActive and not isActive() then
            return false, "cancelled"
        end

        if state.teleporting then
            if showNotification ~= false then
                notify("Trading Hub", "A teleport is already in progress.", 2)
            end
            return false, "already_teleporting"
        end

        state.teleporting = true
        state.teleportRequest += 1

        local requestId = state.teleportRequest
        local sourceJobId = game.JobId

        if showNotification ~= false then
            notify("Trading Hub", "Teleporting to Trading Hub...", 2)
        end

        local ok, requested = pcall(function()
            TradingHubButtonPressed:FireServer("trading_teleporter_dialog", "Trading Server")
            task.wait(0.5)

            if isActive and not isActive() then
                return false
            end

            TradingHubRequestTeleport:FireServer("trading", false)
            return true
        end)

        if not ok or not requested then
            state.teleporting = false

            if not ok then
                warn("[MagicDoor] Trading Hub teleport failed:", requested)
                if showNotification ~= false then
                    notify("Trading Hub", "Teleport failed.", 3)
                end
                return false, tostring(requested)
            end

            return false, "cancelled"
        end

        state.stats.HubRequests += 1

        task.delay(30, function()
            if state.teleportRequest == requestId
                and state.teleporting
                and game.JobId == sourceJobId then

                state.teleporting = false
                debugPrint("Trading Hub request timed out; another attempt is allowed.")

                if showNotification ~= false then
                    notify("Trading Hub", "Teleport request timed out. Try again.", 3)
                end
            end
        end)

        return true, "teleport_requested"
    end

    local function canRun(isActive)
        -- A newer execution automatically invalidates all loops from this run.
        if not runtimeAlive or GLOBAL_ENV.__MagicDoorGeneration ~= MAGIC_DOOR_GENERATION then
            return false
        end
        return not isActive or isActive()
    end

    local function waitWhileActive(seconds, isActive)
        local deadline = os.clock() + seconds
        while os.clock() < deadline do
            if not canRun(isActive) then return false end
            task.wait(math.min(0.1, math.max(0, deadline - os.clock())))
        end
        return canRun(isActive)
    end

    local function getCharacterRoot(timeout, isActive)
        local deadline = os.clock() + (timeout or 10)
        while os.clock() < deadline do
            if not canRun(isActive) then return nil, nil end
            local character = player.Character
            local root = character and character:FindFirstChild("HumanoidRootPart")
            local humanoid = character and character:FindFirstChildOfClass("Humanoid")
            if character and character.Parent and root and humanoid and humanoid.Health > 0 then
                return character, root
            end
            task.wait(0.1)
        end
        return nil, nil
    end

    local function waitForPlayerReady(isActive)
        local deadline = os.clock() + 60
        local readyCharacter, readyRoot, readySince
        while os.clock() < deadline do
            if not canRun(isActive) then return false, "cancelled" end
            local character, root = getCharacterRoot(0.25, isActive)
            local dataOk, inventory, houses = pcall(function()
                return ClientData.get("inventory"), ClientData.get("house_manager")
            end)
            if game:IsLoaded() and root and not root.Anchored and dataOk
                and type(inventory) == "table" and type(houses) == "table" then
                if readyCharacter ~= character or readyRoot ~= root then
                    readyCharacter, readyRoot, readySince = character, root, os.clock()
                end
                -- Give spawn initialization time to finish after character/data become ready.
                if os.clock() - readySince >= 2 then return true, character end
            else
                readyCharacter, readyRoot, readySince = nil, nil, nil
            end
            task.wait(0.1)
        end
        return false, "Player or house data did not load within 60 seconds."
    end

    local function cframeToTable(cf)
        return { cf:GetComponents() }
    end

    local function tableToCFrame(data)
        if type(data) ~= "table" or #data < 12 then
            return nil
        end

        for index = 1, 12 do
            local value = data[index]
            if type(value) ~= "number" or value ~= value or math.abs(value) == math.huge then
                return nil
            end
        end
        local ok, cf = pcall(function()
            return CFrame.new(table.unpack(data, 1, 12))
        end)

        return ok and cf or nil
    end

    local function teleportToSavedPosition(showNotification, isActive)
        local function failed(reason)
            if showNotification and reason ~= "cancelled" then notify("Position", reason, 3) end
            return false, reason
        end
        local saved = tableToCFrame(settings.SavedCFrame)
        if not saved then return failed("Save a valid position first.") end
        local character, root = getCharacterRoot(10, isActive)
        if not canRun(isActive) then return failed("cancelled") end
        if not root then return failed("A live character was not found.") end

        root.CFrame = saved
        root.AssemblyLinearVelocity = Vector3.zero
        root.AssemblyAngularVelocity = Vector3.zero
        -- Do not list/place while the character is still spawning or being moved back.
        if not waitWhileActive(1, isActive) then return failed("cancelled") end
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if player.Character ~= character or not root.Parent or not humanoid or humanoid.Health <= 0 then
            return failed("Character changed during teleport. Start again after spawning.")
        end
        if (root.Position - saved.Position).Magnitude > 6 then
            return failed("Teleport did not settle at the saved position. Try again.")
        end
        if showNotification then notify("Position", "Teleported to saved position.", 2) end
        return true, character
    end

    local function listHouseForTrade(isActive)
        if not canRun(isActive) then return false, "cancelled" end

        local ok, result = pcall(function()
            return Router.get("HousingAPI/ListHouse"):InvokeServer()
        end)

        if not canRun(isActive) then return false, "cancelled" end

        -- If the house was already listed before this script started, Adopt Me can
        -- reject/return false for a second ListHouse request. That must NOT stop
        -- Auto Door + Auto Message. Treat an already-listed response as prepared.
        if not ok then
            local message = string.lower(tostring(result or ""))
            if message:find("already", 1, true) or message:find("listed", 1, true) then
                state.houseListed = true
                state.preparedJobId = game.JobId
                debugPrint("House appears to already be listed; continuing Auto Farm.")
                return true, "already_listed"
            end
            return false, "House listing request failed: " .. tostring(result)
        end

        if result == false then
            -- A false response is commonly returned when this same house is already
            -- listed. Continue instead of aborting the door/message loop.
            state.houseListed = true
            state.preparedJobId = game.JobId
            debugPrint("ListHouse returned false; assuming existing listing and continuing.")
            return true, "already_listed_or_existing"
        end

        -- A nil/true return confirms request completion.
        if not waitWhileActive(0.5, isActive) then return false, "cancelled" end
        state.houseListed = true
        state.preparedJobId = game.JobId
        return true, "listed"
    end

    local function isAtSavedPosition()
        local saved = tableToCFrame(settings.SavedCFrame)
        local character = player.Character
        local root = character and character:FindFirstChild("HumanoidRootPart")
        local humanoid = character and character:FindFirstChildOfClass("Humanoid")

        if not saved or not root or not humanoid or humanoid.Health <= 0 then
            return false
        end

        return (root.Position - saved.Position).Magnitude <= 6
    end

    local function setupAlreadyPrepared()
        return state.preparedJobId == game.JobId
            and state.houseListed
            and isAtSavedPosition()
    end

    --// CHAT
    local function sendMessage(msg, isActive)
        if not canRun(isActive) then return false, "cancelled" end
        if state.sendingChat or type(msg) ~= "string" or msg == "" then
            return false, "empty_or_busy"
        end

        state.sendingChat = true
        local sent = false

        local success, err = pcall(function()
            if TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
                local channels = TextChatService:WaitForChild("TextChannels", 5)
                local general = channels and channels:FindFirstChild("RBXGeneral")

                if general and canRun(isActive) then
                    general:SendAsync(msg)
                    sent = true
                end
            else
                local chatEvents = ReplicatedStorage:FindFirstChild("DefaultChatSystemChatEvents")
                local remote = chatEvents and chatEvents:FindFirstChild("SayMessageRequest")

                if remote and canRun(isActive) then
                    remote:FireServer(msg, "All")
                    sent = true
                end
            end
        end)

        state.sendingChat = false

        if not success then
            warn("[MagicDoor] Chat failed:", err)
            return false, tostring(err)
        end

        if sent then
            state.stats.ChatsSent += 1
            return true, "sent"
        end

        return false, "chat_remote_not_found"
    end

    --// MAGIC DOOR
    local function autoEquipMagicDoor(isActive)
        local ok, inventory = pcall(function()
            return ClientData.get("inventory")
        end)

        if not ok or type(inventory) ~= "table" then
            return false, "inventory_unavailable"
        end

        for _, items in pairs(inventory) do
            if type(items) == "table" then
                for _, item in pairs(items) do
                    if type(item) == "table" then
                        local itemId = tostring(item.id or ""):lower()
                        local itemKind = tostring(item.kind or ""):lower()

                        if itemId:find("magic_house_door", 1, true)
                            or itemKind:find("magic_house_door", 1, true) then

                            if not canRun(isActive) then return false, "cancelled" end
                            local equipOk, equipErr = pcall(function()
                                ClientToolManager.backpack_equip(item)
                            end)

                            if not equipOk then
                                return false, tostring(equipErr)
                            end

                            if not waitWhileActive(0.25, isActive) then return false, "cancelled" end
                            return true, "equipped"
                        end
                    end
                end
            end
        end

        return false, "no_door"
    end

    --// PLACED MAGIC DOOR TRACKING
    -- Tracks the actual placed door so Auto Farm can wait for it to disappear
    -- instead of repeatedly trying to place another door on a timer.
    local function looksLikeMagicDoorInstance(obj)
        if not obj then return false end
        local name = string.lower(tostring(obj.Name or ""))
        return name:find("magic_house_door", 1, true) ~= nil
            or (name:find("magic", 1, true) ~= nil and name:find("door", 1, true) ~= nil)
    end

    local function getInstancePosition(obj)
        if not obj or not obj.Parent then return nil end
        if obj:IsA("BasePart") then
            return obj.Position
        elseif obj:IsA("Model") then
            local ok, pivot = pcall(function() return obj:GetPivot() end)
            if ok and pivot then return pivot.Position end
        end

        local part = obj:FindFirstChildWhichIsA("BasePart", true)
        return part and part.Position or nil
    end

    local function normalizeDoorCandidate(obj)
        if not obj then return nil end

        local current = obj
        for _ = 1, 5 do
            if looksLikeMagicDoorInstance(current) then
                return current
            end
            current = current.Parent
            if not current or current == workspace then break end
        end

        return looksLikeMagicDoorInstance(obj) and obj or nil
    end

    local function doorStillExists(door)
        return typeof(door) == "Instance"
            and door.Parent ~= nil
            and door:IsDescendantOf(workspace)
    end

    local function waitForActiveDoorToDisappear(isActive)
        local door = state.activeDoorInstance
        if not doorStillExists(door) then
            state.activeDoorInstance = nil
            return true
        end

        debugPrint("Waiting for placed Magic Door to disappear:", door:GetFullName())

        while canRun(isActive) and doorStillExists(door) do
            task.wait(0.2)
        end

        if not canRun(isActive) then
            return false
        end

        state.activeDoorInstance = nil
        state.activeDoorPlacedAt = nil
        debugPrint("Placed Magic Door disappeared; replacement is allowed.")
        return true
    end

    local function placeMagicDoorOnce(isActive)
        if not canRun(isActive) then return false, "cancelled" end
        local character, root = getCharacterRoot(5, isActive)
        if not root then
            return false, "no_character"
        end

        local equipped, equipReason = autoEquipMagicDoor(isActive)
        if not equipped then
            return false, equipReason
        end

        if not canRun(isActive) then return false, "cancelled" end
        if player.Character ~= character or not root.Parent then return false, "character_changed" end
        local placeCFrame = root.CFrame
            * CFrame.new(0, -3, -math.max(2, settings.PlacementDistance))
            * CFrame.Angles(0, math.rad(180), 0)

        local remote
        local remoteOk = pcall(function()
            remote = Router.get("PlaceableToolAPI/CreatePlaceable")
        end)

        if not remoteOk or not remote then
            return false, "place_remote_missing"
        end

        -- Capture the newly-created door without doing continuous Workspace scans.
        -- DescendantAdded is connected only around the placement request.
        local detectedDoor = nil
        local captureConnection
        captureConnection = workspace.DescendantAdded:Connect(function(obj)
            if detectedDoor then return end

            local candidate = normalizeDoorCandidate(obj)
            if not candidate then return end

            task.defer(function()
                if detectedDoor or not candidate.Parent then return end
                local pos = getInstancePosition(candidate)
                if pos and (pos - placeCFrame.Position).Magnitude <= 25 then
                    detectedDoor = candidate
                end
            end)
        end)

        if not canRun(isActive) then
            captureConnection:Disconnect()
            return false, "cancelled"
        end

        local success, result = pcall(function()
            return remote:InvokeServer(placeCFrame)
        end)

        if not canRun(isActive) then
            captureConnection:Disconnect()
            return false, "cancelled"
        end
        if not success then
            captureConnection:Disconnect()
            return false, "invoke_failed"
        end

        if not result then
            captureConnection:Disconnect()
            return false, "invalid_spot_or_cooldown"
        end

        -- Some builds may return the created Instance directly.
        if typeof(result) == "Instance" then
            detectedDoor = normalizeDoorCandidate(result) or result
        end

        if not waitWhileActive(0.6, isActive) then
            captureConnection:Disconnect()
            return false, "cancelled"
        end

        pcall(function()
            local useRemote = Router.get("PlaceableToolAPI/UseMagicHouseDoor")
            if useRemote and canRun(isActive) then
                useRemote:FireServer()
            end
        end)

        -- Give replication a short window to expose the placed door.
        local detectDeadline = os.clock() + 1.5
        while not detectedDoor and os.clock() < detectDeadline and canRun(isActive) do
            task.wait(0.05)
        end
        captureConnection:Disconnect()

        if detectedDoor and detectedDoor.Parent then
            state.activeDoorInstance = detectedDoor
            state.activeDoorPlacedAt = os.clock()
            debugPrint("Tracking placed Magic Door:", detectedDoor:GetFullName())
        else
            -- Do not spam placement if the exact instance could not be resolved.
            -- A short fallback delay preserves the previous safe behavior.
            state.activeDoorInstance = nil
            state.activeDoorPlacedAt = os.clock()
            debugPrint("Placed door instance was not resolved; using placement-delay fallback.")
        end

        state.stats.DoorsPlaced += 1
        return true, "placed"
    end

    local function autoPlaceMagicDoor(showErrors, isActive)
        if state.placing then
            return false, "busy"
        end

        state.placing = true
        local maxAttempts = settings.RetryFailedPlacement and math.max(1, settings.MaxPlacementRetries + 1) or 1
        local lastReason = "unknown"

        for attempt = 1, maxAttempts do
            local callOk, success, reason = pcall(placeMagicDoorOnce, isActive)
            if not callOk then success, reason = false, tostring(success) end
            if not canRun(isActive) or reason == "cancelled" then
                state.placing = false
                return false, "cancelled"
            end
            lastReason = reason

            if success then
                state.placing = false
                debugPrint("Door placed on attempt", attempt)
                return true, reason
            end

            if reason == "no_door" then
                break
            end

            if attempt < maxAttempts then
                if not waitWhileActive(0.75, isActive) then
                    state.placing = false
                    return false, "cancelled"
                end
            end
        end

        state.stats.PlacementFailures += 1
        state.placing = false

        if showErrors then
            local message = "Placement failed: " .. tostring(lastReason)
            if lastReason == "no_door" then
                message = "Magic House Door not found."
            end
            notify("Door", message, 3)
        end

        return false, lastReason
    end

    --// CHAT MODE HELPER
    -- After Every Door: send immediately after a successful door placement, then
    -- keep sending every ChatDelay seconds while THAT exact door still exists.
    -- The loop ends as soon as the door disappears, so the next placed door gets
    -- its own fresh chat loop.
    local doorChatSession = 0

    local function startAfterEveryDoorChat(door, isActive)
        doorChatSession += 1
        local myDoorChatSession = doorChatSession

        if not canRun(isActive) or settings.ChatMessage == "" then
            return
        end

        task.spawn(function()
            while canRun(isActive)
                and myDoorChatSession == doorChatSession
                and settings.ChatMode == "After Every Door"
                and settings.ChatMessage ~= "" do

                -- If the exact placed door was detected, stop the moment it is gone.
                if door and not doorStillExists(door) then
                    break
                end

                sendMessage(settings.ChatMessage, isActive)

                local delayLeft = math.max(1, settings.ChatDelay)
                while delayLeft > 0 do
                    if not canRun(isActive)
                        or myDoorChatSession ~= doorChatSession
                        or settings.ChatMode ~= "After Every Door"
                        or settings.ChatMessage == "" then
                        return
                    end

                    if door and not doorStillExists(door) then
                        return
                    end

                    local step = math.min(0.2, delayLeft)
                    task.wait(step)
                    delayLeft -= step
                end

                -- If the door instance could not be resolved, only send once for
                -- that placement rather than creating an endless chat loop.
                if not door then
                    break
                end
            end
        end)
    end

    local function maybeSendChatAfterPlacement(isActive)
        if not canRun(isActive) or settings.ChatMessage == "" then
            return
        end

        if settings.ChatMode == "After Every Door" then
            startAfterEveryDoorChat(state.activeDoorInstance, isActive)
        elseif settings.ChatMode == "Once Per Server" and not state.chatSentThisServer then
            local ok = sendMessage(settings.ChatMessage, isActive)
            if ok then
                state.chatSentThisServer = true
            end
        end
    end

    --// ORDERED FARM: READY -> TELEPORT -> LIST HOUSE -> DOOR -> CHAT
    local autoFarmToggle
    local function stopFarm()
        settings.AutoFarm = false
        state.farmLoopActive = false
        state.farmSession += 1
        doorChatSession += 1
        state.activeDoorInstance = nil
        state.activeDoorPlacedAt = nil
        saveConfig()
    end

    local function startFarm()
        if state.farmLoopActive then
            settings.AutoFarm = true
            saveConfig()
            return
        end

        state.farmSession += 1
        local mySession = state.farmSession
        settings.AutoFarm = true
        state.farmLoopActive = true
        saveConfig()

        local function isActive()
            return settings.AutoFarm and state.farmSession == mySession and not state.teleporting
        end

        local function abort(reason)
            if state.farmSession ~= mySession then return end

            -- A server/trading-hub teleport temporarily makes isActive() false.
            -- Preserve the user's saved Auto Farm = ON state so it can resume
            -- automatically after the new server loads.
            if reason == "cancelled" and state.teleporting then
                state.farmLoopActive = false
                state.farmSession += 1
                doorChatSession += 1
                state.activeDoorInstance = nil
                state.activeDoorPlacedAt = nil
                return
            end

            stopFarm()
            if autoFarmToggle then
                pcall(function()
                    autoFarmToggle:Set(false)
                end)
            end
            if reason ~= "cancelled" then
                notify("Auto Farm stopped", tostring(reason), 5)
            end
        end

        task.spawn(function()
            local runOk, runError = pcall(function()
                notify("Auto Farm", "Waiting for your player and house data to load...", 2)

                local ready, readyReason = waitForPlayerReady(isActive)
                if not ready then
                    abort(readyReason)
                    return
                end

                -- Do the expensive setup only once per server while the saved
                -- position/listed-house state is still valid.
                if setupAlreadyPrepared() then
                    notify("Auto Farm", "Setup already ready. Resuming farm/chat.", 2)
                else
                    notify("Auto Farm", "Teleporting to your saved position...", 2)
                    local moved, preparedCharacter = teleportToSavedPosition(false, isActive)
                    if not moved then
                        abort(preparedCharacter)
                        return
                    end

                    local humanoid = preparedCharacter:FindFirstChildOfClass("Humanoid")
                    if not humanoid or humanoid.Health <= 0 then
                        abort("Character is not ready.")
                        return
                    end

                    notify("Auto Farm", "Listing your house for trade...", 2)
                    local listed, listReason = listHouseForTrade(isActive)
                    if not listed then
                        abort(listReason)
                        return
                    end

                    state.preparedJobId = game.JobId
                    state.houseListed = true
                end

                local preparedCharacter = player.Character
                if not preparedCharacter then
                    abort("Character is missing.")
                    return
                end

                local function characterIsActive()
                    local humanoid = preparedCharacter:FindFirstChildOfClass("Humanoid")
                    return isActive()
                        and player.Character == preparedCharacter
                        and preparedCharacter.Parent ~= nil
                        and humanoid ~= nil
                        and humanoid.Health > 0
                end

                local independentChatStarted = false

                local firstDoorPlacement = true

                while characterIsActive() do
                    -- If we have a tracked door, do not attempt another placement
                    -- until that exact door has disappeared from Workspace.
                    if state.activeDoorInstance and doorStillExists(state.activeDoorInstance) then
                        if not waitForActiveDoorToDisappear(characterIsActive) then
                            break
                        end
                    elseif not firstDoorPlacement then
                        -- Fallback only when the game did not expose the created door Instance.
                        -- This avoids rapid placement spam while keeping compatibility.
                        if not waitWhileActive(
                            math.max(1, settings.PlaceDelay),
                            characterIsActive
                        ) then
                            break
                        end
                    end

                    if not characterIsActive() then break end

                    local placed = autoPlaceMagicDoor(false, characterIsActive)
                    if not characterIsActive() then break end

                    if placed then
                        -- In After Every Door mode, this is now tied to an actual
                        -- successful placement. When a tracked door disappears,
                        -- the replacement is placed first and THEN the message sends.
                        maybeSendChatAfterPlacement(characterIsActive)
                        firstDoorPlacement = false

                        if not independentChatStarted then
                            independentChatStarted = true
                            task.spawn(function()
                                while characterIsActive() do
                                    if settings.ChatMode == "Independent"
                                        and settings.ChatMessage ~= "" then
                                        sendMessage(settings.ChatMessage, characterIsActive)
                                    end

                                    if not waitWhileActive(
                                        math.max(1, settings.ChatDelay),
                                        characterIsActive
                                    ) then
                                        break
                                    end
                                end
                            end)
                        end
                    else
                        -- Placement failed: wait before retrying so we do not hammer
                        -- CreatePlaceable every frame/loop iteration.
                        if not waitWhileActive(
                            math.max(1, settings.PlaceDelay),
                            characterIsActive
                        ) then
                            break
                        end
                    end
                end

                if isActive() then
                    state.houseListed = false
                    state.preparedJobId = nil
                    abort("Character respawned. Turn Auto Farm on again after spawning.")
                else
                    abort("cancelled")
                end
            end)

            if not runOk then
                abort(runError)
            end
        end)
    end

    --// SERVER HOP THROUGH TRADING HUB MATCHMAKING
    local function serverHop(showNotification, isActive)
        return teleportToTradingHub(showNotification, isActive)
    end

    trackConnection(TeleportService.TeleportInitFailed:Connect(function(failedPlayer, result, errorMessage)
        if failedPlayer == player then
            state.teleporting = false
            debugPrint("TeleportInitFailed", tostring(result), tostring(errorMessage))
        end
    end))

    local serverHopStatusLabel

    local function setServerHopStatus(text)
        if serverHopStatusLabel then
            pcall(function()
                serverHopStatusLabel:Set(text)
            end)
        end
    end

    local function formatHopCountdown(seconds)
        seconds = math.max(0, math.ceil(tonumber(seconds) or 0))
        local minutes = math.floor(seconds / 60)
        local secs = seconds % 60
        if minutes > 0 then
            return string.format("%dm %02ds", minutes, secs)
        end
        return string.format("%ds", secs)
    end

    local function stopServerHop()
        settings.AutoServerHop = false
        state.hopLoopActive = false
        state.hopSession += 1
        setServerHopStatus("Status: Auto Server Hop is OFF")
        saveConfig()
    end

    local function startServerHop()
        if state.hopLoopActive then
            settings.AutoServerHop = true
            saveConfig()
            return
        end

        state.hopSession += 1
        local mySession = state.hopSession
        settings.AutoServerHop = true
        state.hopLoopActive = true
        saveConfig()
        local function isActive()
            return settings.AutoServerHop and state.hopSession == mySession
        end

        task.spawn(function()
            while settings.AutoServerHop and state.hopSession == mySession do
                local delayLeft = math.max(10, settings.ServerHopDelay)

                while delayLeft > 0 and settings.AutoServerHop and state.hopSession == mySession do
                    setServerHopStatus("Status: Teleporting in " .. formatHopCountdown(delayLeft))

                    local step = math.min(1, delayLeft)
                    task.wait(step)
                    delayLeft -= step
                end

                if settings.AutoServerHop and state.hopSession == mySession then
                    setServerHopStatus("Status: Teleporting to Trading Hub...")
                    local requested = serverHop(false, isActive)

                    if not requested and settings.AutoServerHop and state.hopSession == mySession then
                        setServerHopStatus("Status: Teleport failed — restarting countdown...")
                        task.wait(1)
                    end
                end
            end

            if state.hopSession == mySession and not settings.AutoServerHop then
                setServerHopStatus("Status: Auto Server Hop is OFF")
            end
        end)
    end

    -- Forward declarations used by the no-trade timer and trade UI watcher.
    local cachedTradeGui
    local updateCachedTradeState

    --// NO-TRADE 5 MINUTE HOP
    local NO_TRADE_HOP_SECONDS = 5 * 60
    local noTradeHopToggle

    local function resetNoTradeTimer(reason)
        state.lastTradeAcceptedAt = os.clock()
        state.noTradeExpiredLogged = false
        debugPrint("No-trade timer reset:", tostring(reason or "trade accepted"))
    end

    local function stopNoTradeHop()
        settings.NoTradeHop = false
        state.noTradeHopLoopActive = false
        state.noTradeHopSession += 1
        saveConfig()
    end

    local function startNoTradeHop()
        if state.noTradeHopLoopActive then
            settings.NoTradeHop = true
            saveConfig()
            return
        end

        state.noTradeHopSession += 1
        local mySession = state.noTradeHopSession
        settings.NoTradeHop = true
        state.noTradeHopLoopActive = true
        resetNoTradeTimer("toggle enabled")
        saveConfig()

        local function isActive()
            return runtimeAlive
                and settings.NoTradeHop
                and state.noTradeHopSession == mySession
        end

        task.spawn(function()
            while isActive() do
                local elapsed = os.clock() - state.lastTradeAcceptedAt
                local remaining = NO_TRADE_HOP_SECONDS - elapsed

                if remaining <= 0 then
                    -- Revalidate the cached trade GUI before trusting inTrade.
                    -- Do NOT reset another full five minutes just because a trade
                    -- is active; wait for it to close, then hop immediately.
                    if state.inTrade and cachedTradeGui then
                        updateCachedTradeState()
                    end

                    if state.inTrade then
                        if not state.noTradeExpiredLogged then
                            state.noTradeExpiredLogged = true
                            debugPrint("No-trade timer expired; waiting for active trade to close.")
                        end
                    elseif not state.teleporting then
                        notify(
                            "No Trade Hop",
                            "No trade accepted for 5 minutes. Hopping to another Trading Hub...",
                            4
                        )

                        local requested = serverHop(false, isActive)

                        -- The current instance should stop trying after a successful
                        -- teleport request. If it failed, begin another 5-minute window.
                        if requested then
                            break
                        else
                            resetNoTradeTimer("hop request failed")
                        end
                    end
                end

                task.wait(1)
            end

            if state.noTradeHopSession == mySession then
                state.noTradeHopLoopActive = false
            end
        end)
    end

    local function markTradeAccepted(source)
        resetNoTradeTimer(source or "trade accepted")
        debugPrint("Accepted/entered trade detected:", tostring(source))
    end

    --// ACTIVE TRADE UI DETECTION (LOW-LAG / EVENT-DRIVEN)
    -- We do ONE initial search for the trade container, then cache it and
    -- watch only its Visible/Enabled property. No constant PlayerGui scans.
    local PlayerGui = player:WaitForChild("PlayerGui")
    cachedTradeGui = nil
    local tradeGuiPropertyConnection = nil
    local tradeGuiAncestryConnection = nil
    local tradeGuiDescendantAddedConnection = nil
    local tradeGuiAncestorConnections = {}
    local tradeActionConnections = {}
    local tradeActionObjects = {}
    local tradeUpdateScheduled = false
    local TRADE_UI_DEBOUNCE = 0.12

    -- A child trade frame can remain Visible=true while one of its parents is
    -- hidden. Check the complete GUI ancestry so we don't leave inTrade stuck.
    local function guiIsEffectivelyVisible(obj)
        if not obj or not obj.Parent then
            return false
        end

        local current = obj
        while current and current ~= PlayerGui do
            if current:IsA("ScreenGui") then
                if not current.Enabled then
                    return false
                end
            elseif current:IsA("GuiObject") then
                if not current.Visible then
                    return false
                end
            end
            current = current.Parent
        end

        return current == PlayerGui
    end

    local function isTradeNamedContainer(obj)
        if not obj then return false end
        if not (obj:IsA("ScreenGui") or obj:IsA("Frame") or obj:IsA("CanvasGroup")) then
            return false
        end

        local name = string.lower(obj.Name or "")
        return name:find("trade", 1, true) ~= nil
    end

    local function getTradeActionKind(obj)
        if not obj then return nil end
        local name = string.lower(obj.Name or "")

        if name:find("accept", 1, true) then return "accept" end
        if name:find("decline", 1, true) then return "decline" end
        if name:find("confirm", 1, true) then return "confirm" end
        if name:find("offer", 1, true) then return "offer" end

        return nil
    end

    local function hasTradeAction(obj)
        -- Candidate discovery may happen while the trade UI is hidden, so this
        -- only checks whether the container owns trade-action controls.
        for _, descendant in ipairs(obj:GetDescendants()) do
            if getTradeActionKind(descendant) then
                return true
            end
        end

        return false
    end

    local function countVisibleTradeActionKinds(container)
        if not container or not container.Parent then
            return 0
        end

        -- Do NOT rescan the whole trade GUI here. The action controls are cached
        -- once when the trade container is bound and as new controls are added.
        local kinds = {}
        local writeIndex = 1

        for readIndex = 1, #tradeActionObjects do
            local entry = tradeActionObjects[readIndex]
            local obj = entry and entry.object
            local kind = entry and entry.kind

            if obj and obj.Parent and obj:IsDescendantOf(container) then
                tradeActionObjects[writeIndex] = entry
                writeIndex += 1

                if kind and guiIsEffectivelyVisible(obj) then
                    kinds[kind] = true
                end
            end
        end

        for index = #tradeActionObjects, writeIndex, -1 do
            tradeActionObjects[index] = nil
        end

        local count = 0
        for _ in pairs(kinds) do
            count += 1
        end
        return count
    end

    local function tradeGuiIsActuallyActive(container)
        local visibleKinds = countVisibleTradeActionKinds(container)

        -- Be conservative when ENTERING a trade so a persistent background
        -- trade container cannot create a false positive. Once a real trade has
        -- been detected, keep it active while at least one trade action remains.
        if state.inTrade then
            return visibleKinds >= 1
        end

        return visibleKinds >= 2
    end

    local function isTradeGuiCandidate(obj)
        return isTradeNamedContainer(obj) and hasTradeAction(obj)
    end

    local function setTradeUiActive(active, source)
        active = active == true

        if active and not state.inTrade then
            state.inTrade = true
            state.tradeSignalName = source or "Trade UI"
            markTradeAccepted("manual/active trade UI")
        elseif not active and state.inTrade then
            state.inTrade = false
            state.tradeSignalName = source or "Trade UI closed"
        end
    end

    local function disconnectCachedTradeGuiSignals()
        if tradeGuiPropertyConnection then
            pcall(function() tradeGuiPropertyConnection:Disconnect() end)
            tradeGuiPropertyConnection = nil
        end

        if tradeGuiAncestryConnection then
            pcall(function() tradeGuiAncestryConnection:Disconnect() end)
            tradeGuiAncestryConnection = nil
        end

        if tradeGuiDescendantAddedConnection then
            pcall(function() tradeGuiDescendantAddedConnection:Disconnect() end)
            tradeGuiDescendantAddedConnection = nil
        end

        for _, connection in ipairs(tradeActionConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(tradeActionConnections)
        table.clear(tradeActionObjects)
        tradeUpdateScheduled = false

        for _, connection in ipairs(tradeGuiAncestorConnections) do
            pcall(function() connection:Disconnect() end)
        end
        table.clear(tradeGuiAncestorConnections)
    end

    updateCachedTradeState = function()
        if not runtimeAlive then return end

        if not cachedTradeGui or not cachedTradeGui.Parent then
            setTradeUiActive(false, "Trade UI removed")
            return
        end

        setTradeUiActive(
            tradeGuiIsActuallyActive(cachedTradeGui),
            "UI: " .. tostring(cachedTradeGui:GetFullName())
        )
    end

    -- Adopt Me can flip many trade UI objects in the same frame when a request
    -- arrives. Coalesce all those changes into one state check instead of doing
    -- a full check for every individual Visible change.
    local function scheduleTradeStateUpdate()
        if not runtimeAlive or tradeUpdateScheduled then
            return
        end

        tradeUpdateScheduled = true
        task.delay(TRADE_UI_DEBOUNCE, function()
            tradeUpdateScheduled = false
            if runtimeAlive then
                updateCachedTradeState()
            end
        end)
    end

    local function watchTradeActionObject(obj)
        if not obj or not obj:IsA("GuiObject") then
            return
        end

        local kind = getTradeActionKind(obj)
        if not kind then
            return
        end

        for _, entry in ipairs(tradeActionObjects) do
            if entry.object == obj then
                return
            end
        end

        table.insert(tradeActionObjects, {
            object = obj,
            kind = kind,
        })

        local ok, connection = pcall(function()
            return obj:GetPropertyChangedSignal("Visible"):Connect(scheduleTradeStateUpdate)
        end)
        if ok and connection then
            table.insert(tradeActionConnections, connection)
            trackConnection(connection)
        end
    end

    local function bindTradeGui(candidate)
        if not runtimeAlive or not candidate or candidate == cachedTradeGui then
            return
        end

        disconnectCachedTradeGuiSignals()
        cachedTradeGui = candidate

        local propertyName = candidate:IsA("ScreenGui") and "Enabled" or "Visible"

        local ok, propertyConnection = pcall(function()
            return candidate:GetPropertyChangedSignal(propertyName):Connect(scheduleTradeStateUpdate)
        end)

        if ok and propertyConnection then
            tradeGuiPropertyConnection = propertyConnection
            trackConnection(propertyConnection)
        end

        -- Watch the actual trade action controls too. The outer trade container
        -- may stay visible forever while only its buttons are shown/hidden.
        for _, descendant in ipairs(candidate:GetDescendants()) do
            watchTradeActionObject(descendant)
        end

        tradeGuiDescendantAddedConnection = candidate.DescendantAdded:Connect(function(obj)
            if not runtimeAlive then return end
            watchTradeActionObject(obj)
            scheduleTradeStateUpdate()
        end)
        trackConnection(tradeGuiDescendantAddedConnection)

        -- Also watch parent GUI visibility. Adopt Me often hides a parent frame
        -- while leaving the inner trade frame itself Visible=true.
        local ancestor = candidate.Parent
        while ancestor and ancestor ~= PlayerGui do
            local ancestorProperty = nil
            if ancestor:IsA("ScreenGui") then
                ancestorProperty = "Enabled"
            elseif ancestor:IsA("GuiObject") then
                ancestorProperty = "Visible"
            end

            if ancestorProperty then
                local watchObject = ancestor
                local watchProperty = ancestorProperty
                local watchOk, connection = pcall(function()
                    return watchObject:GetPropertyChangedSignal(watchProperty):Connect(scheduleTradeStateUpdate)
                end)
                if watchOk and connection then
                    table.insert(tradeGuiAncestorConnections, connection)
                    trackConnection(connection)
                end
            end
            ancestor = ancestor.Parent
        end

        tradeGuiAncestryConnection = candidate.AncestryChanged:Connect(function(_, parent)
            if not runtimeAlive then return end

            if parent == nil then
                setTradeUiActive(false, "Trade UI removed")
                disconnectCachedTradeGuiSignals()
                cachedTradeGui = nil
            end
        end)
        trackConnection(tradeGuiAncestryConnection)

        updateCachedTradeState()
        debugPrint("Cached trade GUI:", candidate:GetFullName())
    end

    local function tryBindTradeGuiFrom(obj)
        if not runtimeAlive or cachedTradeGui then
            return
        end

        -- Check only the added object and its ancestors. This is cheap compared
        -- with rescanning the entire PlayerGui tree after every UI change.
        local current = obj
        while current and current ~= PlayerGui do
            if isTradeNamedContainer(current) and isTradeGuiCandidate(current) then
                bindTradeGui(current)
                return
            end
            current = current.Parent
        end
    end

    -- One-time startup discovery only. This replaces the old 0.35-second polling.
    task.defer(function()
        if not runtimeAlive or cachedTradeGui then return end

        for _, obj in ipairs(PlayerGui:GetDescendants()) do
            if not runtimeAlive or cachedTradeGui then break end
            if isTradeNamedContainer(obj) and isTradeGuiCandidate(obj) then
                bindTradeGui(obj)
                break
            end
        end
    end)

    -- After startup, only inspect newly-added objects and their ancestors.
    trackConnection(PlayerGui.DescendantAdded:Connect(function(obj)
        if not runtimeAlive or cachedTradeGui then return end
        task.defer(tryBindTradeGuiFrom, obj)
    end))

    --// TRADE HELPERS
    local function resolvePlayer(obj)
        if typeof(obj) == "Instance" and obj:IsA("Player") then
            return obj
        elseif typeof(obj) == "number" then
            return Players:GetPlayerByUserId(obj)
        elseif typeof(obj) == "string" then
            return Players:FindFirstChild(obj)
        end
        return nil
    end

    local function parseWhitelist()
        local result = {}
        for name in string.gmatch(settings.TradeWhitelist or "", "[^,%s]+") do
            result[string.lower(name)] = true
        end
        return result
    end

    local function shouldAcceptTrade(fromPlayer)
        if not fromPlayer then
            return false
        end

        if settings.TradeMode == "Everyone" then
            return true
        elseif settings.TradeMode == "Friends Only" then
            local ok, isFriend = pcall(function()
                return player:IsFriendsWith(fromPlayer.UserId)
            end)
            return ok and isFriend
        elseif settings.TradeMode == "Whitelist" then
            return parseWhitelist()[string.lower(fromPlayer.Name)] == true
        end

        return false
    end

    local TradeRequestEvent
    pcall(function()
        TradeRequestEvent = Router.get_event("TradeAPI/TradeRequestReceived")
    end)

    if TradeRequestEvent then
        trackConnection(TradeRequestEvent.OnClientEvent:Connect(function(...)
            if not runtimeAlive or not settings.AutoAcceptTrades then
                return
            end

            local args = { ... }
            local fromPlayer = resolvePlayer(args[1])
            if not shouldAcceptTrade(fromPlayer) then
                return
            end

            local ok, remote = pcall(function()
                return Router.get("TradeAPI/AcceptOrDeclineTradeRequest")
            end)

            if ok and remote then
                local accepted = pcall(function()
                    remote:InvokeServer(fromPlayer, true)
                end)

                if accepted then
                    state.stats.TradesAccepted += 1
                    markTradeAccepted("auto accepted trade from " .. tostring(fromPlayer.Name))
                    debugPrint("Accepted trade from", fromPlayer.Name)
                end
            end
        end))
    else
        warn("[MagicDoor] TradeRequestReceived event not found.")
    end

    --// WINDOW
    local Window = Rayfield:CreateWindow({
        Name = "Magic Door",
        LoadingTitle = "Magic Door Utility",
        ConfigurationSaving = {
            Enabled = true,
            FolderName = "MagicDoorConfigs",
            FileName = "RayfieldConfig",
        },
        KeySystem = false,
    })

    local MainTab = Window:CreateTab("🪄 Main", 4483362458)
    local SettingsTab = Window:CreateTab("⚙️ Settings", 4483362458)

    assert(MainTab, "[MagicDoor] Rayfield failed to create Main tab")
    assert(SettingsTab, "[MagicDoor] Rayfield failed to create Settings tab")
    assert(type(MainTab.CreateButton) == "function", "[MagicDoor] This Rayfield build does not support Tab:CreateButton")

    --// TOP: NO-TRADE HOP
    MainTab:CreateSection("⏱️ Trade Timeout")

    noTradeHopToggle = MainTab:CreateToggle({
        Name = "Hop If No Trade For 5 Minutes",
        CurrentValue = settings.NoTradeHop,
        Flag = "HopIfNoTrade5Min",
        Callback = function(value)
            if value then
                startNoTradeHop()
                notify(
                    "No Trade Hop",
                    "Enabled. The 5-minute timer resets whenever you accept/enter a trade.",
                    4
                )
            else
                stopNoTradeHop()
                notify("No Trade Hop", "Disabled.", 2)
            end
        end,
    })

    MainTab:CreateLabel("If no trade is accepted for 5 minutes, it hops through the Trading Hub.")

    --// FARM UI
    MainTab:CreateSection("🪄 Magic Door Farm")

    MainTab:CreateLabel("Auto Farm: load player > saved position > list house > door > message.")
    autoFarmToggle = MainTab:CreateToggle({
        Name = "Auto Farm (Door + Chat)",
        CurrentValue = settings.AutoFarm,
        Flag = "AutoFarm",
        Callback = function(value)
            if value then
                startFarm()
                notify("Auto Farm", "Starting the ordered setup...", 2)
            else
                stopFarm()
                notify("Auto Farm", "Stopped.", 2)
            end
        end,
    })

    MainTab:CreateSlider({
        Name = "Place Delay",
        Range = {1, 60},
        Increment = 1,
        Suffix = "s",
        CurrentValue = settings.PlaceDelay,
        Callback = function(value)
            settings.PlaceDelay = value
            saveConfig()
        end,
    })

    MainTab:CreateSlider({
        Name = "Placement Distance",
        Range = {2, 20},
        Increment = 1,
        Suffix = " studs",
        CurrentValue = settings.PlacementDistance,
        Callback = function(value)
            settings.PlacementDistance = value
            saveConfig()
        end,
    })

    MainTab:CreateButton({
        Name = "Place One Door",
        Callback = function()
            local ok, reason = autoPlaceMagicDoor(true)
            if ok then
                notify("Door", "Door placed successfully.", 2)
                maybeSendChatAfterPlacement()
            else
                debugPrint("Manual placement failed", reason)
            end
        end,
    })

    --// CHAT UI
    MainTab:CreateSection("💬 Auto Chat")

    MainTab:CreateInput({
        Name = "Message",
        PlaceholderText = "Type message...",
        RemoveTextAfterFocusLost = false,
        CurrentValue = settings.ChatMessage,
        Callback = function(text)
            settings.ChatMessage = tostring(text or "")
            saveConfig()
        end,
    })

    MainTab:CreateDropdown({
        Name = "Chat Mode",
        Options = { "Once Per Server", "After Every Door", "Independent" },
        CurrentOption = { settings.ChatMode },
        MultipleOptions = false,
        Callback = function(option)
            local value = type(option) == "table" and option[1] or option
            if value then
                settings.ChatMode = value
                saveConfig()
            end
        end,
    })

    MainTab:CreateSlider({
        Name = "Chat Delay (Independent Mode)",
        Range = {1, 120},
        Increment = 1,
        Suffix = "s",
        CurrentValue = settings.ChatDelay,
        Callback = function(value)
            settings.ChatDelay = value
            saveConfig()
        end,
    })

    MainTab:CreateButton({
        Name = "Send Test Message",
        Callback = function()
            local ok = sendMessage(settings.ChatMessage)
            notify("Chat", ok and "Message sent." or "Message was not sent.", 2)
        end,
    })

    --// POSITION UI
    MainTab:CreateSection("📍 Saved Position")

    MainTab:CreateToggle({
        Name = "Auto Teleport to Saved Position on Join",
        CurrentValue = settings.AutoTeleportOnJoin,
        Callback = function(value)
            settings.AutoTeleportOnJoin = value
            saveConfig()
        end,
    })

    MainTab:CreateButton({
        Name = "Save Current Position",
        Callback = function()
            local _, root = getCharacterRoot(5)
            if not root then
                notify("Position", "Could not find your character.", 3)
                return
            end

            settings.SavedCFrame = cframeToTable(root.CFrame)
            saveConfig()
            notify("Position", "Current position saved.", 2)
        end,
    })

    MainTab:CreateButton({
        Name = "Teleport to Saved Position",
        Callback = function()
            teleportToSavedPosition(true)
        end,
    })

    --// TRADE UI
    MainTab:CreateSection("🏠 House / Trade")

    MainTab:CreateButton({
        Name = "List House for Trade",
        Callback = function()
            local ok, reason = listHouseForTrade()
            notify("House", ok and "House listing request completed." or tostring(reason), 3)
        end,
    })

    MainTab:CreateButton({
        Name = "Unlist House for Trade",
        Callback = function()
            local ok = pcall(function()
                Router.get("HousingAPI/UnlistHouse"):InvokeServer()
            end)

            if ok then
                state.houseListed = false
                state.preparedJobId = nil
            end
            notify("House", ok and "House unlisted." or "Failed to unlist house.", 2)
        end,
    })

    MainTab:CreateToggle({
        Name = "Auto Accept Trades",
        CurrentValue = settings.AutoAcceptTrades,
        Callback = function(value)
            settings.AutoAcceptTrades = value
            saveConfig()
            notify("Auto Trade", value and "Enabled." or "Disabled.", 2)
        end,
    })

    MainTab:CreateDropdown({
        Name = "Accept Trades From",
        Options = { "Everyone", "Friends Only", "Whitelist" },
        CurrentOption = { settings.TradeMode },
        MultipleOptions = false,
        Callback = function(option)
            local value = type(option) == "table" and option[1] or option
            if value then
                settings.TradeMode = value
                saveConfig()
            end
        end,
    })

    MainTab:CreateInput({
        Name = "Trade Whitelist",
        PlaceholderText = "user1, user2, user3",
        RemoveTextAfterFocusLost = false,
        CurrentValue = settings.TradeWhitelist,
        Callback = function(text)
            settings.TradeWhitelist = tostring(text or "")
            saveConfig()
        end,
    })

    MainTab:CreateButton({
        Name = "Show Trade / Hop Timer Status",
        Callback = function()
            local elapsed = math.max(0, os.clock() - state.lastTradeAcceptedAt)
            local remaining = math.max(0, NO_TRADE_HOP_SECONDS - elapsed)

            notify(
                "Trade Timer",
                string.format(
                    "%s | In trade: %s | Time left: %dm %02ds",
                    settings.NoTradeHop and "ENABLED" or "DISABLED",
                    state.inTrade and "YES" or "NO",
                    math.floor(remaining / 60),
                    math.floor(remaining % 60)
                ),
                6
            )
        end,
    })

    --// TRADING HUB UI
    MainTab:CreateSection("🏙️ Trading Hub")

    MainTab:CreateButton({
        Name = "Teleport to Trading Hub",
        Callback = function()
            teleportToTradingHub()
        end,
    })

    --// SERVER HOP UI
    MainTab:CreateSection("🌍 Server Hop")
    MainTab:CreateLabel("Auto Hop requests a Trading Hub teleport after each Hop Delay.")
    serverHopStatusLabel = MainTab:CreateLabel(
        settings.AutoServerHop
            and ("Status: Teleporting in " .. formatHopCountdown(math.max(10, settings.ServerHopDelay)))
            or "Status: Auto Server Hop is OFF"
    )

    local autoServerHopToggle = MainTab:CreateToggle({
        Name = "Auto Server Hop",
        CurrentValue = settings.AutoServerHop,
        Flag = "AutoServerHop",
        Callback = function(value)
            if value then
                startServerHop()
                notify("Server Hop", "Auto hop to Trading Hub started.", 2)
            else
                stopServerHop()
                notify("Server Hop", "Auto hop stopped.", 2)
            end
        end,
    })

    MainTab:CreateSlider({
        Name = "Hop Delay",
        Range = {10, 3600},
        Increment = 10,
        Suffix = "s",
        CurrentValue = settings.ServerHopDelay,
        Callback = function(value)
            settings.ServerHopDelay = value
            saveConfig()
        end,
    })

    MainTab:CreateSlider({
        Name = "Minimum Free Slots",
        Range = {1, 20},
        Increment = 1,
        Suffix = " slots",
        CurrentValue = settings.MinFreeSlots,
        Callback = function(value)
            settings.MinFreeSlots = value
            saveConfig()
        end,
    })

    MainTab:CreateToggle({
        Name = "Avoid Visited Servers",
        CurrentValue = settings.AvoidVisitedServers,
        Callback = function(value)
            settings.AvoidVisitedServers = value
            saveConfig()
        end,
    })

    MainTab:CreateButton({
        Name = "Hop Server Now",
        Callback = function()
            serverHop(true)
        end,
    })

    --// SESSION UI
    MainTab:CreateSection("📊 Session")

    MainTab:CreateButton({
        Name = "Show Session Stats",
        Callback = function()
            local runtime = math.floor(os.clock() - state.sessionStartedAt)
            local minutes = math.floor(runtime / 60)
            local seconds = runtime % 60

            notify(
                "Session Stats",
                string.format(
                    "Doors: %d | Failed: %d | Chats: %d | Hub requests: %d | Trades: %d | Runtime: %dm %ds",
                    state.stats.DoorsPlaced,
                    state.stats.PlacementFailures,
                    state.stats.ChatsSent,
                    state.stats.HubRequests,
                    state.stats.TradesAccepted,
                    minutes,
                    seconds
                ),
                8
            )
        end,
    })

    MainTab:CreateButton({
        Name = "Reset Session Stats",
        Callback = function()
            state.stats.DoorsPlaced = 0
            state.stats.PlacementFailures = 0
            state.stats.ChatsSent = 0
            state.stats.ServersVisited = 1
            state.stats.HubRequests = 0
            state.stats.TradesAccepted = 0
            state.sessionStartedAt = os.clock()
            notify("Session", "Stats reset.", 2)
        end,
    })

    --// SETTINGS TAB
    SettingsTab:CreateSection("Placement Reliability")

    SettingsTab:CreateToggle({
        Name = "Retry Failed Placement",
        CurrentValue = settings.RetryFailedPlacement,
        Callback = function(value)
            settings.RetryFailedPlacement = value
            saveConfig()
        end,
    })

    SettingsTab:CreateSlider({
        Name = "Max Placement Retries",
        Range = {0, 10},
        Increment = 1,
        Suffix = " retries",
        CurrentValue = settings.MaxPlacementRetries,
        Callback = function(value)
            settings.MaxPlacementRetries = value
            saveConfig()
        end,
    })

    SettingsTab:CreateSection("Interface / Debug")

    SettingsTab:CreateToggle({
        Name = "Notifications",
        CurrentValue = settings.Notifications,
        Callback = function(value)
            settings.Notifications = value
            saveConfig()
        end,
    })

    SettingsTab:CreateToggle({
        Name = "Debug Logging",
        CurrentValue = settings.DebugLogging,
        Callback = function(value)
            settings.DebugLogging = value
            saveConfig()
        end,
    })

    SettingsTab:CreateButton({
        Name = "Save Settings Now",
        Callback = function()
            saveConfig()
            notify("Settings", "Saved.", 2)
        end,
    })

    SettingsTab:CreateButton({
        Name = "Clear Visited Server History",
        Callback = function()
            state.visitedServers = {}
            if game.JobId and game.JobId ~= "" then
                state.visitedServers[game.JobId] = true
            end
            notify("Server Hop", "Visited-server history cleared.", 2)
        end,
    })


    --// HOUSE SPAWNER TAB
    local HouseTab = Window:CreateTab("🏠 House Spawner", 4483362458)

    local selectedHouseId = nil
    local houseNames = {}
    local houseMap = {}
    local HouseDropdown

    local function refreshHouseList()
        table.clear(houseNames)
        table.clear(houseMap)

        local dataOk, houses = pcall(function() return ClientData.get("house_manager") end)
        if not dataOk or type(houses) ~= "table" then houses = {} end

        for _, house in pairs(houses) do
            local displayName = house.name or ("House " .. tostring(house.house_id))

            table.insert(houseNames, displayName)
            houseMap[displayName] = house.house_id
        end

        table.sort(houseNames)

        if HouseDropdown then
            HouseDropdown:Refresh(houseNames)
        end
    end

    HouseDropdown = HouseTab:CreateDropdown({
        Name = "Select House",
        Options = {},
        CurrentOption = {},
        MultipleOptions = false,
        Callback = function(option)
            local name = typeof(option) == "table" and option[1] or option

            selectedHouseId = houseMap[name]

            Rayfield:Notify({
                Title = "House Selected",
                Content = tostring(name),
                Duration = 2
            })
        end
    })

    HouseTab:CreateButton({
        Name = "Refresh Houses",
        Callback = function()
            refreshHouseList()

            Rayfield:Notify({
                Title = "Refreshed",
                Content = "Loaded " .. tostring(#houseNames) .. " houses",
                Duration = 2
            })
        end
    })

    HouseTab:CreateButton({
        Name = "Spawn Selected House",
        Callback = function()
            if not selectedHouseId then
                Rayfield:Notify({
                    Title = "Error",
                    Content = "Select a house first",
                    Duration = 3
                })
                return
            end

            local success, err = pcall(function()
                Router.get("HousingAPI/SpawnHouse"):FireServer(selectedHouseId)
            end)

            if success then
                Rayfield:Notify({
                    Title = "Success",
                    Content = "House spawned",
                    Duration = 3
                })
            else
                Rayfield:Notify({
                    Title = "Failed",
                    Content = tostring(err),
                    Duration = 3
                })
            end
        end
    })

    refreshHouseList()

    --// REGISTER CLEAN SHUTDOWN FOR THE NEXT EXECUTION
    shutdownMagicDoor = function()
        if not runtimeAlive then
            return
        end

        runtimeAlive = false

        -- Stop runtime loops owned by this instance without changing the
        -- user's saved ON/OFF preferences. The next server should resume them.
        state.farmLoopActive = false
        state.hopLoopActive = false
        state.noTradeHopLoopActive = false

        state.farmSession += 1
        doorChatSession += 1
        state.hopSession += 1
        state.noTradeHopSession += 1
        state.teleportRequest += 1

        for _, connection in ipairs(trackedConnections) do
            pcall(function()
                connection:Disconnect()
            end)
        end
        table.clear(trackedConnections)

        pcall(function()
            Rayfield:Destroy()
        end)

        if GLOBAL_ENV.__MagicDoorShutdown == shutdownMagicDoor then
            GLOBAL_ENV.__MagicDoorShutdown = nil
        end
    end

    -- Replace the early shutdown with the complete shutdown now that all state exists.
    GLOBAL_ENV.__MagicDoorShutdown = shutdownMagicDoor

    --// RESUME SAVED AUTOMATION AFTER A HOP / RE-EXECUTION
    -- MagicDoorSettings.json is the authoritative source for these automation
    -- states. Rayfield Flags still save the UI state, but we explicitly resume
    -- the loops so executor/Rayfield load timing cannot leave them OFF.
    local resumeAutoFarm = settings.AutoFarm == true
    local resumeAutoServerHop = settings.AutoServerHop == true
    local resumeNoTradeHop = settings.NoTradeHop == true

    task.defer(function()
        task.wait(0.5)
        if not runtimeAlive then return end

        if resumeAutoFarm and not state.farmLoopActive then
            startFarm()
            if autoFarmToggle then
                pcall(function() autoFarmToggle:Set(true) end)
            end
        end

        if resumeAutoServerHop and not state.hopLoopActive then
            startServerHop()
            if autoServerHopToggle then
                pcall(function() autoServerHopToggle:Set(true) end)
            end
        end

        if resumeNoTradeHop and not state.noTradeHopLoopActive then
            startNoTradeHop()
            if noTradeHopToggle then
                pcall(function() noTradeHopToggle:Set(true) end)
            end
        end
    end)

    -- Optional join teleport never starts a separate door/chat loop.
    -- Starting/stopping Auto Farm invalidates this task so it cannot move you later.
    if settings.AutoTeleportOnJoin then
        local startupSession = state.farmSession
        task.spawn(function()
            local function startupIsActive()
                return settings.AutoTeleportOnJoin and state.farmSession == startupSession
                    and not settings.AutoFarm and not state.teleporting
            end
            local ready = waitForPlayerReady(startupIsActive)
            if ready and startupIsActive() then teleportToSavedPosition(true, startupIsActive) end
        end)
    end

    notify("Magic Door", "Ready. Save a position, enter a message, then enable Auto Farm.", 4)
end

LoadMain()
