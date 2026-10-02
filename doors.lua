-- Auto Farm order: load player/data -> saved position -> list house -> door -> chat.
local function LoadMain()
    if not game:IsLoaded() then game.Loaded:Wait() end
    --// LOAD RAYFIELD
    local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

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

    -- Safety: do not silently resume automation merely because it was enabled last session.
    -- The saved values remain in the file, but automation starts OFF each execution.
    settings.AutoFarm = false
    settings.AutoServerHop = false

    --// RUNTIME STATE
    local state = {
        farmSession = 0,
        hopSession = 0,
        placing = false,
        sendingChat = false,
        teleporting = false,
        teleportRequest = 0,
        chatSentThisServer = false,
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
            -- Reuse the existing zero-argument remote; the server decides whether listing is allowed.
            return Router.get("HousingAPI/ListHouse"):InvokeServer()
        end)
        if not canRun(isActive) then return false, "cancelled" end
        if not ok then return false, "House listing request failed: " .. tostring(result) end
        if result == false then return false, "The server rejected the house listing." end
        -- A nil return confirms request completion, not the replicated listing state.
        if not waitWhileActive(0.5, isActive) then return false, "cancelled" end
        return true
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

        if not canRun(isActive) then return false, "cancelled" end
        local success, result = pcall(function()
            return remote:InvokeServer(placeCFrame)
        end)

        if not canRun(isActive) then return false, "cancelled" end
        if not success then
            return false, "invoke_failed"
        end

        if not result then
            return false, "invalid_spot_or_cooldown"
        end

        if not waitWhileActive(0.6, isActive) then return false, "cancelled" end

        pcall(function()
            local useRemote = Router.get("PlaceableToolAPI/UseMagicHouseDoor")
            if useRemote and canRun(isActive) then
                useRemote:FireServer()
            end
        end)

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
    local function maybeSendChatAfterPlacement(isActive)
        if not canRun(isActive) or settings.ChatMessage == "" then
            return
        end

        if settings.ChatMode == "After Every Door" then
            sendMessage(settings.ChatMessage, isActive)
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
        state.farmSession += 1
        saveConfig()
    end

    local function startFarm()
        if settings.AutoFarm then return end
        state.farmSession += 1
        local mySession = state.farmSession
        settings.AutoFarm = true
        saveConfig()
        local function isActive()
            return settings.AutoFarm and state.farmSession == mySession and not state.teleporting
        end
        local function abort(reason)
            if state.farmSession ~= mySession then return end
            stopFarm()
            if autoFarmToggle then pcall(function() autoFarmToggle:Set(false) end) end
            if reason ~= "cancelled" then notify("Auto Farm stopped", tostring(reason), 5) end
        end

        task.spawn(function()
            local runOk, runError = pcall(function()
                notify("Auto Farm", "Waiting for your player and house data to load...", 3)
                local ready, readyReason = waitForPlayerReady(isActive)
                if not ready then abort(readyReason); return end

                notify("Auto Farm", "Teleporting to your saved position...", 2)
                local moved, preparedCharacter = teleportToSavedPosition(false, isActive)
                if not moved then abort(preparedCharacter); return end
                local function characterIsActive()
                    local humanoid = preparedCharacter:FindFirstChildOfClass("Humanoid")
                    return isActive() and player.Character == preparedCharacter
                        and preparedCharacter.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
                end

                notify("Auto Farm", "Listing your house for trade...", 2)
                local listed, listReason = listHouseForTrade(characterIsActive)
                if not listed then abort(listReason); return end

                local independentChatStarted = false
                while characterIsActive() do
                    local placed = autoPlaceMagicDoor(false, characterIsActive)
                    if not characterIsActive() then break end
                    if placed then
                        maybeSendChatAfterPlacement(characterIsActive)
                        if not independentChatStarted then
                            independentChatStarted = true
                            -- Even Independent mode waits for the first successful door.
                            task.spawn(function()
                                while characterIsActive() do
                                    if settings.ChatMode == "Independent" and settings.ChatMessage ~= "" then
                                        sendMessage(settings.ChatMessage, characterIsActive)
                                    end
                                    if not waitWhileActive(math.max(1, settings.ChatDelay), characterIsActive) then break end
                                end
                            end)
                        end
                    end
                    if not waitWhileActive(math.max(1, settings.PlaceDelay), characterIsActive) then break end
                end
                if isActive() then
                    abort("Character respawned. Turn Auto Farm on again to repeat the setup.")
                else
                    abort("cancelled")
                end
            end)
            if not runOk then abort(runError) end
        end)
    end

    --// SERVER HOP THROUGH TRADING HUB MATCHMAKING
    local function serverHop(showNotification, isActive)
        return teleportToTradingHub(showNotification, isActive)
    end

    TeleportService.TeleportInitFailed:Connect(function(failedPlayer, result, errorMessage)
        if failedPlayer == player then
            state.teleporting = false
            debugPrint("TeleportInitFailed", tostring(result), tostring(errorMessage))
        end
    end)

    local function stopServerHop()
        settings.AutoServerHop = false
        state.hopSession += 1
        saveConfig()
    end

    local function startServerHop()
        state.hopSession += 1
        local mySession = state.hopSession
        settings.AutoServerHop = true
        saveConfig()
        local function isActive()
            return settings.AutoServerHop and state.hopSession == mySession
        end

        task.spawn(function()
            while settings.AutoServerHop and state.hopSession == mySession do
                local delayLeft = math.max(10, settings.ServerHopDelay)

                while delayLeft > 0 and settings.AutoServerHop and state.hopSession == mySession do
                    local step = math.min(0.5, delayLeft)
                    task.wait(step)
                    delayLeft -= step
                end

                if settings.AutoServerHop and state.hopSession == mySession then
                    serverHop(false, isActive)
                end
            end
        end)
    end

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
        TradeRequestEvent.OnClientEvent:Connect(function(...)
            if not settings.AutoAcceptTrades then
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
                    debugPrint("Accepted trade from", fromPlayer.Name)
                end
            end
        end)
    else
        warn("[MagicDoor] TradeRequestReceived event not found.")
    end

    --// WINDOW
    local Window = Rayfield:CreateWindow({
        Name = "Magic Door",
        LoadingTitle = "Magic Door Utility",
        ConfigurationSaving = {
            Enabled = false,
        },
        KeySystem = false,
    })

    local MainTab = Window:CreateTab("🪄 Main", 4483362458)
    local SettingsTab = Window:CreateTab("⚙️ Settings", 4483362458)

    assert(MainTab, "[MagicDoor] Rayfield failed to create Main tab")
    assert(SettingsTab, "[MagicDoor] Rayfield failed to create Settings tab")
    assert(type(MainTab.CreateButton) == "function", "[MagicDoor] This Rayfield build does not support Tab:CreateButton")

    --// FARM UI
    MainTab:CreateSection("🪄 Magic Door Farm")

    MainTab:CreateLabel("Auto Farm: load player > saved position > list house > door > message.")
    autoFarmToggle = MainTab:CreateToggle({
        Name = "Auto Farm (Door + Chat)",
        CurrentValue = false,
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

    MainTab:CreateToggle({
        Name = "Auto Server Hop",
        CurrentValue = false,
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
