--==============================================================
-- MAGIC DOOR
-- Clean Lua Structure
--==============================================================

--==============================================================
-- SINGLE INSTANCE
--==============================================================

local GLOBAL_ENV = (getgenv and getgenv()) or _G

if type(GLOBAL_ENV.__MagicDoorShutdown) == "function" then
    pcall(GLOBAL_ENV.__MagicDoorShutdown)
    GLOBAL_ENV.__MagicDoorShutdown = nil
end

GLOBAL_ENV.__MagicDoorGeneration =
    (tonumber(GLOBAL_ENV.__MagicDoorGeneration) or 0) + 1

local SCRIPT_GENERATION = GLOBAL_ENV.__MagicDoorGeneration


--==============================================================
-- WAIT FOR GAME
--==============================================================

if not game:IsLoaded() then
    game.Loaded:Wait()
end


--==============================================================
-- SERVICES
--==============================================================

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TeleportService = game:GetService("TeleportService")
local TextChatService = game:GetService("TextChatService")
local HttpService = game:GetService("HttpService")

local player = Players.LocalPlayer

while not player do
    task.wait()
    player = Players.LocalPlayer
end

local PlayerGui = player:WaitForChild("PlayerGui")


--==============================================================
-- RAYFIELD
--==============================================================

local Rayfield = loadstring(
    game:HttpGet("https://sirius.menu/rayfield")
)()


--==============================================================
-- MODULES
--==============================================================

local Fsys = require(
    ReplicatedStorage:WaitForChild("Fsys")
).load

local ClientData = Fsys("ClientData")
local ClientToolManager = Fsys("ClientToolManager")
local Router = Fsys("RouterClient")


--==============================================================
-- ADOPT ME APIS
--==============================================================

local API = ReplicatedStorage:WaitForChild("API")

local TradingHubButtonPressed =
    API:WaitForChild("TradingServerAPI/ButtonPressed")

local TradingHubRequestTeleport =
    API:WaitForChild("ThemedServersAPI/RequestTeleport")


--==============================================================
-- CONFIG
--==============================================================

local CONFIG_FOLDER = "MagicDoorConfigs"
local CONFIG_FILE = CONFIG_FOLDER .. "/MagicDoorSettings.json"

local config = {
    farm = {
        enabled = false,
        placeDelay = 2,
        placementDistance = 6,
        retryPlacement = true,
        maxRetries = 3,
    },

    chat = {
        message = "",
        delay = 10,
        mode = "Once Per Server",
    },

    trade = {
        autoAccept = false,
        mode = "Everyone",
        whitelist = "",
    },

    hop = {
        autoServerHop = false,
        serverHopDelay = 300,

        noTradeHop = false,
        noTradeTimeout = 300,

        minFreeSlots = 1,
        avoidVisitedServers = true,
    },

    position = {
        autoTeleportOnJoin = false,
        savedCFrame = nil,
    },

    interface = {
        notifications = true,
        debug = false,
    },
}


--==============================================================
-- RUNTIME STATE
--==============================================================

local state = {
    running = true,

    farm = {
        running = false,
        session = 0,
        preparedJobId = nil,
        houseListed = false,
    },

    trade = {
        active = false,
        source = "None",
        gui = nil,
        updateQueued = false,
    },

    door = {
        placing = false,
        instance = nil,
        placedAt = nil,
        chatSession = 0,
    },

    chat = {
        sending = false,
        sentThisServer = false,
        independentRunning = false,
    },

    teleport = {
        active = false,
        requestId = 0,
    },

    serverHop = {
        running = false,
        session = 0,
    },

    noTrade = {
        running = false,
        session = 0,

        deadline = os.clock() + 300,

        paused = false,
        pausedRemaining = 300,
    },

    stats = {
        doorsPlaced = 0,
        placementFailures = 0,
        chatsSent = 0,
        hubRequests = 0,
        tradesAccepted = 0,
    },

    sessionStartedAt = os.clock(),

    visitedServers = {},
}

if game.JobId and game.JobId ~= "" then
    state.visitedServers[game.JobId] = true
end


--==============================================================
-- UI REFERENCES
--==============================================================

local ui = {
    window = nil,

    autoFarmToggle = nil,
    autoServerHopToggle = nil,
    noTradeHopToggle = nil,

    serverHopStatus = nil,

    noTradeGui = nil,
    noTradeStatus = nil,

    houseDropdown = nil,
}


--==============================================================
-- CONNECTIONS
--==============================================================

local connections = {}
local tradeConnections = {}


local function trackConnection(connection)
    if connection then
        table.insert(connections, connection)
    end

    return connection
end


local function disconnectConnections(list)
    for _, connection in ipairs(list) do
        pcall(function()
            connection:Disconnect()
        end)
    end

    table.clear(list)
end


--==============================================================
-- BASIC HELPERS
--==============================================================

local function scriptAlive()
    return state.running
        and GLOBAL_ENV.__MagicDoorGeneration == SCRIPT_GENERATION
end


local function debugPrint(...)
    if config.interface.debug then
        print("[MagicDoor]", ...)
    end
end


local function notify(title, message, duration)
    if not config.interface.notifications then
        return
    end

    pcall(function()
        Rayfield:Notify({
            Title = title,
            Content = tostring(message or ""),
            Duration = duration or 3,
        })
    end)
end


local function canRun(callback)
    if not scriptAlive() then
        return false
    end

    if callback then
        return callback() == true
    end

    return true
end


local function waitActive(seconds, callback)
    local deadline = os.clock() + math.max(0, seconds or 0)

    while os.clock() < deadline do
        if not canRun(callback) then
            return false
        end

        task.wait(
            math.min(
                0.1,
                math.max(0.01, deadline - os.clock())
            )
        )
    end

    return canRun(callback)
end


--==============================================================
-- CONFIG
--==============================================================

local function mergeTable(target, source)
    if type(source) ~= "table" then
        return
    end

    for key, currentValue in pairs(target) do
        local incoming = source[key]

        if incoming ~= nil then
            if type(currentValue) == "table"
                and type(incoming) == "table" then
                mergeTable(currentValue, incoming)
            elseif typeof(currentValue) == typeof(incoming) then
                target[key] = incoming
            end
        end
    end
end


local function migrateOldConfig(data)
    if type(data) ~= "table" then
        return
    end

    -- Already using new structure.
    if data.farm or data.chat or data.trade or data.hop then
        mergeTable(config, data)
        return
    end

    -- Old flat structure support.
    if data.PlaceDelay ~= nil then
        config.farm.placeDelay = data.PlaceDelay
    end

    if data.PlacementDistance ~= nil then
        config.farm.placementDistance = data.PlacementDistance
    end

    if data.RetryFailedPlacement ~= nil then
        config.farm.retryPlacement = data.RetryFailedPlacement
    end

    if data.MaxPlacementRetries ~= nil then
        config.farm.maxRetries = data.MaxPlacementRetries
    end

    if data.AutoFarm ~= nil then
        config.farm.enabled = data.AutoFarm
    end

    if data.ChatMessage ~= nil then
        config.chat.message = data.ChatMessage
    end

    if data.ChatDelay ~= nil then
        config.chat.delay = data.ChatDelay
    end

    if data.ChatMode ~= nil then
        config.chat.mode = data.ChatMode
    end

    if data.AutoAcceptTrades ~= nil then
        config.trade.autoAccept = data.AutoAcceptTrades
    end

    if data.TradeMode ~= nil then
        config.trade.mode = data.TradeMode
    end

    if data.TradeWhitelist ~= nil then
        config.trade.whitelist = data.TradeWhitelist
    end

    if data.AutoServerHop ~= nil then
        config.hop.autoServerHop = data.AutoServerHop
    end

    if data.ServerHopDelay ~= nil then
        config.hop.serverHopDelay = data.ServerHopDelay
    end

    if data.NoTradeHop ~= nil then
        config.hop.noTradeHop = data.NoTradeHop
    end

    if data.MinFreeSlots ~= nil then
        config.hop.minFreeSlots = data.MinFreeSlots
    end

    if data.AvoidVisitedServers ~= nil then
        config.hop.avoidVisitedServers = data.AvoidVisitedServers
    end

    if data.AutoTeleportOnJoin ~= nil then
        config.position.autoTeleportOnJoin = data.AutoTeleportOnJoin
    end

    if type(data.SavedCFrame) == "table" then
        config.position.savedCFrame = data.SavedCFrame
    end

    if data.Notifications ~= nil then
        config.interface.notifications = data.Notifications
    end

    if data.DebugLogging ~= nil then
        config.interface.debug = data.DebugLogging
    end
end


local function loadConfig()
    if not isfolder(CONFIG_FOLDER) then
        makefolder(CONFIG_FOLDER)
    end

    if not isfile(CONFIG_FILE) then
        return
    end

    local ok, data = pcall(function()
        return HttpService:JSONDecode(
            readfile(CONFIG_FILE)
        )
    end)

    if ok then
        migrateOldConfig(data)
    end
end


local function saveConfig()
    local ok, err = pcall(function()
        writefile(
            CONFIG_FILE,
            HttpService:JSONEncode(config)
        )
    end)

    if not ok then
        warn(
            "[MagicDoor] Config save failed:",
            err
        )
    end
end


loadConfig()


--==============================================================
-- CFRAMES
--==============================================================

local function cframeToTable(cf)
    return {
        cf:GetComponents()
    }
end


local function tableToCFrame(values)
    if type(values) ~= "table"
        or #values < 12 then
        return nil
    end

    for index = 1, 12 do
        local value = values[index]

        if type(value) ~= "number"
            or value ~= value
            or math.abs(value) == math.huge then
            return nil
        end
    end

    local ok, result = pcall(function()
        return CFrame.new(
            table.unpack(values, 1, 12)
        )
    end)

    return ok and result or nil
end


--==============================================================
-- CHARACTER
--==============================================================

local function getCharacterRoot(timeout, activeCallback)
    local deadline = os.clock() + (timeout or 10)

    while os.clock() < deadline do
        if not canRun(activeCallback) then
            return nil, nil
        end

        local character = player.Character

        local root =
            character
            and character:FindFirstChild(
                "HumanoidRootPart"
            )

        local humanoid =
            character
            and character:FindFirstChildOfClass(
                "Humanoid"
            )

        if character
            and character.Parent
            and root
            and humanoid
            and humanoid.Health > 0 then
            return character, root
        end

        task.wait(0.1)
    end

    return nil, nil
end


local function waitForPlayerReady(activeCallback)
    local deadline = os.clock() + 60

    local readyCharacter
    local readyRoot
    local readySince

    while os.clock() < deadline do
        if not canRun(activeCallback) then
            return false, "cancelled"
        end

        local character, root =
            getCharacterRoot(
                0.25,
                activeCallback
            )

        local dataOk, inventory, houses =
            pcall(function()
                return
                    ClientData.get("inventory"),
                    ClientData.get("house_manager")
            end)

        if root
            and not root.Anchored
            and dataOk
            and type(inventory) == "table"
            and type(houses) == "table" then
            if readyCharacter ~= character
                or readyRoot ~= root then
                readyCharacter = character
                readyRoot = root
                readySince = os.clock()
            end

            if readySince
                and os.clock() - readySince >= 2 then
                return true, character
            end
        else
            readyCharacter = nil
            readyRoot = nil
            readySince = nil
        end

        task.wait(0.1)
    end

    return false,
        "Player or house data did not load within 60 seconds."
end


--==============================================================
-- POSITION
--==============================================================

local function saveCurrentPosition()
    local _, root =
        getCharacterRoot(5)

    if not root then
        return false,
            "Character not found."
    end

    config.position.savedCFrame =
        cframeToTable(root.CFrame)

    saveConfig()

    return true
end


local function isAtSavedPosition()
    local saved =
        tableToCFrame(
            config.position.savedCFrame
        )

    if not saved then
        return false
    end

    local character = player.Character

    local root =
        character
        and character:FindFirstChild(
            "HumanoidRootPart"
        )

    local humanoid =
        character
        and character:FindFirstChildOfClass(
            "Humanoid"
        )

    if not root
        or not humanoid
        or humanoid.Health <= 0 then
        return false
    end

    return (
        root.Position
        - saved.Position
    ).Magnitude <= 6
end


local function teleportToSavedPosition(showNotification, activeCallback)
    local saved =
        tableToCFrame(
            config.position.savedCFrame
        )

    if not saved then
        if showNotification then
            notify(
                "Position",
                "Save a position first.",
                3
            )
        end

        return false,
            "No saved position."
    end

    local character, root =
        getCharacterRoot(
            10,
            activeCallback
        )

    if not root then
        return false,
            "Character not found."
    end

    root.CFrame = saved
    root.AssemblyLinearVelocity = Vector3.zero
    root.AssemblyAngularVelocity = Vector3.zero

    if not waitActive(
            1,
            activeCallback
        ) then
        return false,
            "cancelled"
    end

    if player.Character ~= character
        or not root.Parent then
        return false,
            "Character changed."
    end

    if (
            root.Position
            - saved.Position
        ).Magnitude > 6 then
        return false,
            "Teleport did not settle."
    end

    if showNotification then
        notify(
            "Position",
            "Teleported to saved position.",
            2
        )
    end

    return true,
        character
end


--==============================================================
-- HOUSE
--==============================================================

local function listHouseForTrade(activeCallback)
    if not canRun(activeCallback) then
        return false, "cancelled"
    end

    local ok, result =
        pcall(function()
            return Router.get(
                "HousingAPI/ListHouse"
            ):InvokeServer()
        end)

    if not canRun(activeCallback) then
        return false, "cancelled"
    end

    if not ok then
        local message =
            tostring(
                result or ""
            ):lower()

        if message:find(
                "already",
                1,
                true
            )
            or message:find(
                "listed",
                1,
                true
            ) then
            state.farm.houseListed = true
            state.farm.preparedJobId = game.JobId

            return true,
                "already_listed"
        end

        return false,
            tostring(result)
    end

    if result == false then
        state.farm.houseListed = true
        state.farm.preparedJobId = game.JobId

        return true,
            "already_listed"
    end

    state.farm.houseListed = true
    state.farm.preparedJobId = game.JobId

    return true,
        "listed"
end


local function unlistHouse()
    local ok, err =
        pcall(function()
            Router.get(
                "HousingAPI/UnlistHouse"
            ):InvokeServer()
        end)

    if ok then
        state.farm.houseListed = false
        state.farm.preparedJobId = nil
    end

    return ok, err
end


local function setupAlreadyPrepared()
    return state.farm.preparedJobId == game.JobId
        and state.farm.houseListed
        and isAtSavedPosition()
end


--==============================================================
-- NO TRADE TIMER GUI
--==============================================================

local function formatNoTradeCountdown(seconds)
    seconds =
        math.max(
            0,
            math.ceil(
                tonumber(seconds) or 0
            )
        )

    return string.format(
        "%d:%02d",
        math.floor(seconds / 60),
        seconds % 60
    )
end


local function ensureNoTradeGui()
    if ui.noTradeGui
        and ui.noTradeGui.Parent then
        return ui.noTradeGui
    end

    local old =
        PlayerGui:FindFirstChild(
            "MagicDoorNoTradeTimer"
        )

    if old then
        old:Destroy()
    end

    local gui = Instance.new("ScreenGui")
    gui.Name = "MagicDoorNoTradeTimer"
    gui.ResetOnSpawn = false
    gui.IgnoreGuiInset = false
    gui.DisplayOrder = 999
    gui.Enabled = config.hop.noTradeHop
    gui.Parent = PlayerGui

    local frame = Instance.new("Frame")
    frame.Name = "TimerFrame"
    frame.Size = UDim2.fromOffset(250, 82)
    frame.Position = UDim2.new(
        0.5,
        -125,
        0,
        70
    )
    frame.BackgroundColor3 =
        Color3.fromRGB(
            24,
            24,
            28
        )
    frame.BackgroundTransparency = 0.08
    frame.BorderSizePixel = 0
    frame.Active = true
    frame.Draggable = true
    frame.Parent = gui

    local corner =
        Instance.new("UICorner")

    corner.CornerRadius =
        UDim.new(0, 12)

    corner.Parent = frame

    local stroke =
        Instance.new("UIStroke")

    stroke.Thickness = 1
    stroke.Transparency = 0.55
    stroke.Color =
        Color3.fromRGB(
            255,
            255,
            255
        )
    stroke.Parent = frame

    local title =
        Instance.new("TextLabel")

    title.BackgroundTransparency = 1
    title.Position =
        UDim2.fromOffset(
            12,
            7
        )
    title.Size =
        UDim2.new(
            1,
            -24,
            0,
            21
        )
    title.Font = Enum.Font.GothamBold
    title.Text = "NO TRADE HOP"
    title.TextColor3 =
        Color3.fromRGB(
            240,
            240,
            245
        )
    title.TextSize = 14
    title.TextXAlignment =
        Enum.TextXAlignment.Left
    title.Parent = frame

    local status =
        Instance.new("TextLabel")

    status.BackgroundTransparency = 1
    status.Position =
        UDim2.fromOffset(
            12,
            30
        )
    status.Size =
        UDim2.new(
            1,
            -24,
            0,
            40
        )
    status.Font = Enum.Font.GothamMedium
    status.Text = "Teleporting in 5:00"
    status.TextColor3 =
        Color3.fromRGB(
            255,
            255,
            255
        )
    status.TextSize = 17
    status.TextWrapped = true
    status.TextXAlignment =
        Enum.TextXAlignment.Left
    status.Parent = frame

    ui.noTradeGui = gui
    ui.noTradeStatus = status

    return gui
end


local function setNoTradeStatus(text)
    ensureNoTradeGui()

    if ui.noTradeStatus then
        ui.noTradeStatus.Text =
            tostring(text or "")
    end
end


local function setNoTradeGuiVisible(value)
    local gui =
        ensureNoTradeGui()

    gui.Enabled =
        value == true
end


--==============================================================
-- NO TRADE TIMER
--==============================================================

local function resetNoTradeTimer(reason)
    local timeout =
        math.max(
            10,
            config.hop.noTradeTimeout
        )

    state.noTrade.paused = false

    state.noTrade.pausedRemaining =
        timeout

    state.noTrade.deadline =
        os.clock() + timeout

    if config.hop.noTradeHop then
        setNoTradeStatus(
            "Teleporting in "
            .. formatNoTradeCountdown(
                timeout
            )
        )
    end

    debugPrint(
        "No Trade timer reset:",
        reason or "reset"
    )
end


local function pauseNoTradeTimer(reason)
    if state.noTrade.paused then
        return
    end

    state.noTrade.pausedRemaining =
        math.max(
            0,
            state.noTrade.deadline
            - os.clock()
        )

    state.noTrade.paused = true

    if config.hop.noTradeHop then
        setNoTradeStatus(
            "TRADE ACTIVE - TIMER PAUSED"
        )
    end

    debugPrint(
        "No Trade timer paused:",
        reason or "trade"
    )
end


local function getNoTradeRemaining()
    if state.noTrade.paused then
        return state.noTrade.pausedRemaining
    end

    return math.max(
        0,
        state.noTrade.deadline
        - os.clock()
    )
end


--==============================================================
-- CHAT
--==============================================================

local function sendMessage(message, activeCallback)
    -- Never send while actively trading.
    if state.trade.active then
        return false,
            "trade_active"
    end

    if state.chat.sending then
        return false,
            "busy"
    end

    if type(message) ~= "string"
        or message == "" then
        return false,
            "empty"
    end

    if not canRun(activeCallback) then
        return false,
            "cancelled"
    end

    state.chat.sending = true

    local sent = false

    local ok, err =
        pcall(function()
            if TextChatService.ChatVersion
                == Enum.ChatVersion.TextChatService then
                local channels =
                    TextChatService:WaitForChild(
                        "TextChannels",
                        5
                    )

                local general =
                    channels
                    and channels:FindFirstChild(
                        "RBXGeneral"
                    )

                if general
                    and not state.trade.active
                    and canRun(activeCallback) then
                    general:SendAsync(
                        message
                    )

                    sent = true
                end
            else
                local chatEvents =
                    ReplicatedStorage:FindFirstChild(
                        "DefaultChatSystemChatEvents"
                    )

                local remote =
                    chatEvents
                    and chatEvents:FindFirstChild(
                        "SayMessageRequest"
                    )

                if remote
                    and not state.trade.active
                    and canRun(activeCallback) then
                    remote:FireServer(
                        message,
                        "All"
                    )

                    sent = true
                end
            end
        end)

    state.chat.sending = false

    if not ok then
        warn(
            "[MagicDoor] Chat error:",
            err
        )

        return false,
            tostring(err)
    end

    if sent then
        state.stats.chatsSent += 1

        return true,
            "sent"
    end

    return false,
        "not_sent"
end


local function waitChatDelay(activeCallback)
    local remaining =
        math.max(
            1,
            config.chat.delay
        )

    while remaining > 0 do
        if not canRun(activeCallback) then
            return false
        end

        -- Freeze chat delay while trading.
        if state.trade.active then
            task.wait(0.2)
        else
            local step =
                math.min(
                    0.2,
                    remaining
                )

            task.wait(step)

            remaining -= step
        end
    end

    return true
end


--==============================================================
-- MAGIC DOOR HELPERS
--==============================================================

local function looksLikeMagicDoor(object)
    if not object then
        return false
    end

    local name =
        tostring(
            object.Name or ""
        ):lower()

    return name:find(
            "magic_house_door",
            1,
            true
        ) ~= nil
        or (
            name:find(
                "magic",
                1,
                true
            )
            and name:find(
                "door",
                1,
                true
            )
        )
end


local function normalizeDoorCandidate(object)
    local current = object

    for _ = 1, 6 do
        if current
            and looksLikeMagicDoor(
                current
            ) then
            return current
        end

        current =
            current
            and current.Parent

        if not current
            or current == workspace then
            break
        end
    end

    return nil
end


local function getInstancePosition(object)
    if not object
        or not object.Parent then
        return nil
    end

    if object:IsA("BasePart") then
        return object.Position
    end

    if object:IsA("Model") then
        local ok, pivot =
            pcall(function()
                return object:GetPivot()
            end)

        if ok and pivot then
            return pivot.Position
        end
    end

    local part =
        object:FindFirstChildWhichIsA(
            "BasePart",
            true
        )

    return part
        and part.Position
        or nil
end


local function doorStillExists(door)
    return typeof(door) == "Instance"
        and door.Parent ~= nil
        and door:IsDescendantOf(
            workspace
        )
end


--==============================================================
-- EQUIP MAGIC DOOR
--==============================================================

local function equipMagicDoor(activeCallback)
    if state.trade.active then
        return false,
            "trade_active"
    end

    local ok, inventory =
        pcall(function()
            return ClientData.get(
                "inventory"
            )
        end)

    if not ok
        or type(inventory) ~= "table" then
        return false,
            "inventory_unavailable"
    end

    for _, category in pairs(
        inventory
    ) do
        if type(category) == "table" then
            for _, item in pairs(
                category
            ) do
                if type(item) == "table" then
                    local id =
                        tostring(
                            item.id or ""
                        ):lower()

                    local kind =
                        tostring(
                            item.kind or ""
                        ):lower()

                    if id:find(
                            "magic_house_door",
                            1,
                            true
                        )
                        or kind:find(
                            "magic_house_door",
                            1,
                            true
                        ) then
                        if state.trade.active then
                            return false,
                                "trade_active"
                        end

                        local equipOk,
                        equipErr =
                            pcall(function()
                                ClientToolManager
                                    .backpack_equip(
                                        item
                                    )
                            end)

                        if not equipOk then
                            return false,
                                tostring(
                                    equipErr
                                )
                        end

                        if not waitActive(
                                0.25,
                                activeCallback
                            ) then
                            return false,
                                "cancelled"
                        end

                        if state.trade.active then
                            return false,
                                "trade_active"
                        end

                        return true,
                            "equipped"
                    end
                end
            end
        end
    end

    return false,
        "no_door"
end


--==============================================================
-- PLACE MAGIC DOOR
--==============================================================

local function placeMagicDoorOnce(activeCallback)
    if state.trade.active then
        return false,
            "trade_active"
    end

    if not canRun(activeCallback) then
        return false,
            "cancelled"
    end

    local character, root =
        getCharacterRoot(
            5,
            activeCallback
        )

    if not root then
        return false,
            "no_character"
    end

    local equipped,
    equipReason =
        equipMagicDoor(
            activeCallback
        )

    if not equipped then
        return false,
            equipReason
    end

    if state.trade.active then
        return false,
            "trade_active"
    end

    if player.Character ~= character
        or not root.Parent then
        return false,
            "character_changed"
    end

    local placementCFrame =
        root.CFrame

        * CFrame.new(
            0,
            -3,
            -math.max(
                2,
                config.farm.placementDistance
            )
        )

        * CFrame.Angles(
            0,
            math.rad(180),
            0
        )

    local remote

    local remoteOk =
        pcall(function()
            remote =
                Router.get(
                    "PlaceableToolAPI/CreatePlaceable"
                )
        end)

    if not remoteOk
        or not remote then
        return false,
            "place_remote_missing"
    end

    local detectedDoor
    local captureConnection

    captureConnection =
        workspace.DescendantAdded
        :Connect(function(object)
            if detectedDoor then
                return
            end

            local candidate =
                normalizeDoorCandidate(
                    object
                )

            if not candidate then
                return
            end

            task.defer(function()
                if detectedDoor
                    or not candidate.Parent then
                    return
                end

                local position =
                    getInstancePosition(
                        candidate
                    )

                if position
                    and (
                        position
                        - placementCFrame.Position
                    ).Magnitude <= 25 then
                    detectedDoor =
                        candidate
                end
            end)
        end)

    if state.trade.active then
        captureConnection:Disconnect()

        return false,
            "trade_active"
    end

    local success, result =
        pcall(function()
            return remote:InvokeServer(
                placementCFrame
            )
        end)

    if not success then
        captureConnection:Disconnect()

        return false,
            "invoke_failed"
    end

    if not result then
        captureConnection:Disconnect()

        return false,
            "invalid_spot_or_cooldown"
    end

    if typeof(result) == "Instance" then
        detectedDoor =
            normalizeDoorCandidate(
                result
            )
            or result
    end

    if not waitActive(
            0.6,
            activeCallback
        ) then
        captureConnection:Disconnect()

        return false,
            "cancelled"
    end

    if state.trade.active then
        captureConnection:Disconnect()

        return false,
            "trade_active"
    end

    pcall(function()
        local useRemote =
            Router.get(
                "PlaceableToolAPI/UseMagicHouseDoor"
            )

        if useRemote
            and not state.trade.active
            and canRun(activeCallback) then
            useRemote:FireServer()
        end
    end)

    local detectDeadline =
        os.clock() + 1.5

    while not detectedDoor
        and os.clock() < detectDeadline
        and canRun(activeCallback) do
        task.wait(0.05)
    end

    captureConnection:Disconnect()

    state.door.instance =
        detectedDoor

    state.door.placedAt =
        os.clock()

    state.stats.doorsPlaced += 1

    return true,
        "placed"
end


local function placeMagicDoor(showErrors, activeCallback)
    if state.trade.active then
        return false,
            "trade_active"
    end

    if state.door.placing then
        return false,
            "busy"
    end

    state.door.placing = true

    local attempts =
        config.farm.retryPlacement
        and math.max(
            1,
            config.farm.maxRetries + 1
        )
        or 1

    local lastReason =
    "unknown"

    for attempt = 1, attempts do
        if state.trade.active then
            state.door.placing = false

            return false,
                "trade_active"
        end

        local callOk,
        success,
        reason =
            pcall(
                placeMagicDoorOnce,
                activeCallback
            )

        if not callOk then
            reason = tostring(success)
            success = false
        end

        lastReason = reason

        if success then
            state.door.placing = false

            debugPrint(
                "Door placed on attempt",
                attempt
            )

            return true,
                reason
        end

        if reason == "trade_active"
            or reason == "cancelled" then
            state.door.placing = false

            return false,
                reason
        end

        if reason == "no_door" then
            break
        end

        if attempt < attempts then
            if not waitActive(
                    0.75,
                    activeCallback
                ) then
                state.door.placing = false

                return false,
                    "cancelled"
            end
        end
    end

    state.door.placing = false
    state.stats.placementFailures += 1

    if showErrors then
        local message =
            lastReason == "no_door"
            and "Magic House Door not found."
            or (
                "Placement failed: "
                .. tostring(lastReason)
            )

        notify(
            "Door",
            message,
            3
        )
    end

    return false,
        lastReason
end


local function waitForDoorToDisappear(activeCallback)
    local door =
        state.door.instance

    if not doorStillExists(door) then
        state.door.instance = nil
        state.door.placedAt = nil

        return true
    end

    while canRun(activeCallback)
        and doorStillExists(door) do
        task.wait(0.2)
    end

    if not canRun(activeCallback) then
        return false
    end

    state.door.instance = nil
    state.door.placedAt = nil

    return true
end


--==============================================================
-- CHAT MODES
--==============================================================

local function startAfterEveryDoorChat(door, activeCallback)
    state.door.chatSession += 1

    local mySession =
        state.door.chatSession

    if config.chat.message == "" then
        return
    end

    task.spawn(function()
        while canRun(activeCallback)
            and state.door.chatSession == mySession
            and config.chat.mode == "After Every Door"
            and config.chat.message ~= "" do
            if door
                and not doorStillExists(door) then
                break
            end

            -- Pause while trade is active.
            while state.trade.active
                and canRun(activeCallback)
                and state.door.chatSession == mySession do
                task.wait(0.2)
            end

            if not canRun(activeCallback) then
                break
            end

            if door
                and not doorStillExists(door) then
                break
            end

            if not state.trade.active then
                sendMessage(
                    config.chat.message,
                    activeCallback
                )
            end

            if not waitChatDelay(
                    activeCallback
                ) then
                break
            end

            if not door then
                break
            end
        end
    end)
end


local function sendChatAfterDoor(activeCallback)
    if state.trade.active
        or config.chat.message == "" then
        return
    end

    if config.chat.mode
        == "After Every Door" then
        startAfterEveryDoorChat(
            state.door.instance,
            activeCallback
        )
    elseif config.chat.mode
        == "Once Per Server"
        and not state.chat.sentThisServer then
        local sent =
            sendMessage(
                config.chat.message,
                activeCallback
            )

        if sent then
            state.chat.sentThisServer = true
        end
    end
end


local function startIndependentChat(activeCallback)
    if state.chat.independentRunning then
        return
    end

    state.chat.independentRunning = true

    task.spawn(function()
        while canRun(activeCallback) do
            while state.trade.active
                and canRun(activeCallback) do
                task.wait(0.2)
            end

            if not canRun(activeCallback) then
                break
            end

            if config.chat.mode == "Independent"
                and config.chat.message ~= "" then
                sendMessage(
                    config.chat.message,
                    activeCallback
                )
            end

            if not waitChatDelay(
                    activeCallback
                ) then
                break
            end
        end

        state.chat.independentRunning = false
    end)
end


--==============================================================
-- TRADING HUB TELEPORT
--==============================================================

local function teleportToTradingHub(showNotification, activeCallback)
    if activeCallback
        and not activeCallback() then
        return false,
            "cancelled"
    end

    if state.teleport.active then
        if showNotification ~= false then
            notify(
                "Trading Hub",
                "A teleport is already in progress.",
                2
            )
        end

        return false,
            "already_teleporting"
    end

    state.teleport.active = true
    state.teleport.requestId += 1

    local requestId =
        state.teleport.requestId

    local sourceJobId =
        game.JobId

    if showNotification ~= false then
        notify(
            "Trading Hub",
            "Teleporting to Trading Hub...",
            2
        )
    end

    local ok, requested =
        pcall(function()
            TradingHubButtonPressed:FireServer(
                "trading_teleporter_dialog",
                "Trading Server"
            )

            task.wait(0.5)

            if activeCallback
                and not activeCallback() then
                return false
            end

            TradingHubRequestTeleport:FireServer(
                "trading",
                false
            )

            return true
        end)

    if not ok
        or not requested then
        state.teleport.active = false

        return false,
            tostring(requested)
    end

    state.stats.hubRequests += 1

    task.delay(30, function()
        if state.teleport.requestId == requestId
            and state.teleport.active
            and game.JobId == sourceJobId then
            state.teleport.active = false

            debugPrint(
                "Trading Hub request timed out."
            )
        end
    end)

    return true,
        "teleport_requested"
end


trackConnection(
    TeleportService.TeleportInitFailed
    :Connect(function(
        failedPlayer,
        result,
        errorMessage
    )
        if failedPlayer == player then
            state.teleport.active = false

            debugPrint(
                "TeleportInitFailed",
                tostring(result),
                tostring(errorMessage)
            )
        end
    end)
)


--==============================================================
-- TRADE DETECTION HELPERS
--==============================================================

local tradeActionObjects = {}


local function guiVisible(object)
    if not object
        or not object.Parent then
        return false
    end

    local current =
        object

    while current
        and current ~= PlayerGui do
        if current:IsA("ScreenGui") then
            if not current.Enabled then
                return false
            end
        elseif current:IsA("GuiObject") then
            if not current.Visible then
                return false
            end
        end

        current =
            current.Parent
    end

    return current == PlayerGui
end


local function getGuiSearchText(object)
    local result =
        tostring(
            object.Name or ""
        ):lower()

    if object:IsA("TextButton")
        or object:IsA("TextLabel")
        or object:IsA("TextBox") then
        local ok, text =
            pcall(function()
                return object.Text
            end)

        if ok and text then
            result =
                result
                .. " "
                .. tostring(text):lower()
        end
    end

    return result
end


local function getTradeActionKind(object)
    if not object then
        return nil
    end

    local text =
        getGuiSearchText(
            object
        )

    if text:find(
            "accept",
            1,
            true
        ) then
        return "accept"
    end

    if text:find(
            "decline",
            1,
            true
        ) then
        return "decline"
    end

    if text:find(
            "confirm",
            1,
            true
        ) then
        return "confirm"
    end

    if text:find(
            "offer",
            1,
            true
        ) then
        return "offer"
    end

    if text:find(
            "cancel",
            1,
            true
        ) then
        return "cancel"
    end

    return nil
end


local function isTradeContainer(object)
    if not object then
        return false
    end

    if not (
            object:IsA("ScreenGui")
            or object:IsA("Frame")
            or object:IsA("CanvasGroup")
        ) then
        return false
    end

    return tostring(
        object.Name or ""
    ):lower():find(
        "trade",
        1,
        true
    ) ~= nil
end


local function collectTradeActions(container)
    table.clear(
        tradeActionObjects
    )

    local function check(object)
        local kind =
            getTradeActionKind(
                object
            )

        if kind then
            table.insert(
                tradeActionObjects,
                {
                    object = object,
                    kind = kind,
                }
            )
        end
    end

    check(container)

    for _, object in ipairs(
        container:GetDescendants()
    ) do
        check(object)
    end
end


local function hasTradeActions(container)
    collectTradeActions(
        container
    )

    return #tradeActionObjects > 0
end


--==============================================================
-- TRADE STATE
--==============================================================

local function setTradeActive(active, source)
    active =
        active == true

    if state.trade.active == active then
        return
    end

    state.trade.active = active
    state.trade.source =
        source or "Trade UI"

    if active then
        -- Kill current After Every Door chat session.
        state.door.chatSession += 1

        -- Pause countdown.
        if config.hop.noTradeHop then
            pauseNoTradeTimer(
                "trade active"
            )
        end

        setNoTradeStatus(
            "TRADE ACTIVE - TIMER PAUSED"
        )

        debugPrint(
            "Trade started:",
            state.trade.source
        )
    else
        -- New FULL 5 minutes after trade.
        if config.hop.noTradeHop then
            resetNoTradeTimer(
                "trade ended"
            )
        end

        debugPrint(
            "Trade ended - farm/chat resumed."
        )
    end
end


local function tradeGuiActuallyActive(container)
    if not container
        or not container.Parent then
        return false
    end

    if not guiVisible(container) then
        return false
    end

    collectTradeActions(
        container
    )

    local visibleKinds = {}

    for _, entry in ipairs(
        tradeActionObjects
    ) do
        local object =
            entry.object

        if object
            and object.Parent
            and guiVisible(object) then
            visibleKinds[
            entry.kind
            ] = true
        end
    end

    local count = 0

    for _ in pairs(
        visibleKinds
    ) do
        count += 1
    end

    -- One visible action inside a visible
    -- trade container is enough.
    return count >= 1
end


local function updateTradeState()
    local container =
        state.trade.gui

    if not container
        or not container.Parent then
        setTradeActive(
            false,
            "Trade GUI removed"
        )

        state.trade.gui = nil

        return
    end

    setTradeActive(
        tradeGuiActuallyActive(
            container
        ),
        "UI: "
        .. container:GetFullName()
    )
end


local function scheduleTradeUpdate()
    if state.trade.updateQueued then
        return
    end

    state.trade.updateQueued = true

    task.delay(0.08, function()
        state.trade.updateQueued = false

        if scriptAlive() then
            updateTradeState()
        end
    end)
end


local function disconnectTradeGui()
    disconnectConnections(
        tradeConnections
    )

    table.clear(
        tradeActionObjects
    )
end


local function bindTradeGui(container)
    if not container
        or not container.Parent then
        return
    end

    if state.trade.gui == container then
        return
    end

    disconnectTradeGui()

    state.trade.gui =
        container

    local function add(connection)
        if connection then
            table.insert(
                tradeConnections,
                connection
            )
        end
    end

    local function watchObject(object)
        if not object
            or not object:IsA(
                "GuiObject"
            ) then
            return
        end

        add(
            object
            :GetPropertyChangedSignal(
                "Visible"
            )
            :Connect(
                scheduleTradeUpdate
            )
        )

        if object:IsA("TextButton")
            or object:IsA("TextLabel")
            or object:IsA("TextBox") then
            add(
                object
                :GetPropertyChangedSignal(
                    "Text"
                )
                :Connect(
                    scheduleTradeUpdate
                )
            )
        end
    end

    if container:IsA("ScreenGui") then
        add(
            container
            :GetPropertyChangedSignal(
                "Enabled"
            )
            :Connect(
                scheduleTradeUpdate
            )
        )
    elseif container:IsA("GuiObject") then
        watchObject(container)
    end

    for _, object in ipairs(
        container:GetDescendants()
    ) do
        watchObject(object)
    end

    add(
        container.DescendantAdded
        :Connect(function(object)
            watchObject(object)

            scheduleTradeUpdate()
        end)
    )

    local ancestor =
        container.Parent

    while ancestor
        and ancestor ~= PlayerGui do
        if ancestor:IsA("ScreenGui") then
            add(
                ancestor
                :GetPropertyChangedSignal(
                    "Enabled"
                )
                :Connect(
                    scheduleTradeUpdate
                )
            )
        elseif ancestor:IsA("GuiObject") then
            add(
                ancestor
                :GetPropertyChangedSignal(
                    "Visible"
                )
                :Connect(
                    scheduleTradeUpdate
                )
            )
        end

        ancestor =
            ancestor.Parent
    end

    add(
        container.AncestryChanged
        :Connect(function(
            _,
            parent
        )
            if parent == nil then
                setTradeActive(
                    false,
                    "Trade UI removed"
                )

                state.trade.gui = nil

                disconnectTradeGui()
            end
        end)
    )

    updateTradeState()

    debugPrint(
        "Bound Trade GUI:",
        container:GetFullName()
    )
end


local function tryBindTradeGuiFrom(object)
    local current =
        object

    local bestCandidate

    while current
        and current ~= PlayerGui do
        if isTradeContainer(current)
            and hasTradeActions(
                current
            ) then
            bestCandidate =
                current
        end

        current =
            current.Parent
    end

    if bestCandidate then
        bindTradeGui(
            bestCandidate
        )

        return true
    end

    return false
end


local function initialTradeGuiScan()
    for _, object in ipairs(
        PlayerGui:GetDescendants()
    ) do
        if not scriptAlive() then
            return
        end

        if isTradeContainer(object)
            and hasTradeActions(
                object
            ) then
            bindTradeGui(object)

            return
        end
    end
end


task.defer(
    initialTradeGuiScan
)


trackConnection(
    PlayerGui.DescendantAdded
    :Connect(function(object)
        task.defer(function()
            if scriptAlive() then
                tryBindTradeGuiFrom(
                    object
                )
            end
        end)
    end)
)


-- Cheap backup check.
task.spawn(function()
    while scriptAlive() do
        if state.trade.gui then
            updateTradeState()
        end

        task.wait(0.3)
    end
end)


--==============================================================
-- TRADE AUTO ACCEPT
--==============================================================

local function resolvePlayer(value)
    if typeof(value) == "Instance"
        and value:IsA("Player") then
        return value
    end

    if typeof(value) == "number" then
        return Players:GetPlayerByUserId(
            value
        )
    end

    if typeof(value) == "string" then
        return Players:FindFirstChild(
            value
        )
    end

    return nil
end


local function parseWhitelist()
    local result = {}

    for username in string.gmatch(
        config.trade.whitelist or "",
        "[^,%s]+"
    ) do
        result[
        username:lower()
        ] = true
    end

    return result
end


local function shouldAcceptTrade(otherPlayer)
    if not otherPlayer then
        return false
    end

    if config.trade.mode == "Everyone" then
        return true
    end

    if config.trade.mode == "Friends Only" then
        local ok, result =
            pcall(function()
                return player:IsFriendsWith(
                    otherPlayer.UserId
                )
            end)

        return ok and result
    end

    if config.trade.mode == "Whitelist" then
        return parseWhitelist()[
        otherPlayer.Name:lower()
        ] == true
    end

    return false
end


local TradeRequestEvent

pcall(function()
    TradeRequestEvent =
        Router.get_event(
            "TradeAPI/TradeRequestReceived"
        )
end)


if TradeRequestEvent then
    trackConnection(
        TradeRequestEvent.OnClientEvent
        :Connect(function(...)
            if not scriptAlive()
                or not config.trade.autoAccept then
                return
            end

            local arguments = {
                ...
            }

            local otherPlayer =
                resolvePlayer(
                    arguments[1]
                )

            if not shouldAcceptTrade(
                    otherPlayer
                ) then
                return
            end

            local ok, remote =
                pcall(function()
                    return Router.get(
                        "TradeAPI/AcceptOrDeclineTradeRequest"
                    )
                end)

            if not ok
                or not remote then
                return
            end

            local accepted =
                pcall(function()
                    remote:InvokeServer(
                        otherPlayer,
                        true
                    )
                end)

            if accepted then
                state.stats.tradesAccepted += 1

                debugPrint(
                    "Accepted trade request from",
                    otherPlayer.Name
                )

                task.delay(0.25, function()
                    if state.trade.gui then
                        updateTradeState()
                    end
                end)
            end
        end)
    )
else
    warn(
        "[MagicDoor] TradeRequestReceived event not found."
    )
end


--==============================================================
-- AUTO FARM
--==============================================================

local function stopFarm(save)
    config.farm.enabled = false

    state.farm.running = false
    state.farm.session += 1

    state.door.chatSession += 1

    state.chat.independentRunning = false

    if save ~= false then
        saveConfig()
    end
end


local function startFarm()
    if state.farm.running then
        config.farm.enabled = true
        saveConfig()

        return
    end

    state.farm.session += 1

    local mySession =
        state.farm.session

    config.farm.enabled = true
    state.farm.running = true

    saveConfig()

    local function farmActive()
        return scriptAlive()
            and config.farm.enabled
            and state.farm.session == mySession
            and not state.teleport.active
    end

    task.spawn(function()
        local runOk, runError =
            pcall(function()
                local ready,
                readyReason =
                    waitForPlayerReady(
                        farmActive
                    )

                if not ready then
                    if readyReason ~= "cancelled" then
                        notify(
                            "Auto Farm",
                            readyReason,
                            4
                        )
                    end

                    return
                end

                -- Prepare once per server.
                if not setupAlreadyPrepared() then
                    notify(
                        "Auto Farm",
                        "Teleporting to saved position...",
                        2
                    )

                    local moved,
                    moveReason =
                        teleportToSavedPosition(
                            false,
                            farmActive
                        )

                    if not moved then
                        notify(
                            "Auto Farm",
                            moveReason,
                            4
                        )

                        return
                    end

                    notify(
                        "Auto Farm",
                        "Listing house for trade...",
                        2
                    )

                    local listed,
                    listReason =
                        listHouseForTrade(
                            farmActive
                        )

                    if not listed then
                        notify(
                            "Auto Farm",
                            listReason,
                            4
                        )

                        return
                    end
                end

                local preparedCharacter =
                    player.Character

                if not preparedCharacter then
                    return
                end

                local function characterActive()
                    if not farmActive() then
                        return false
                    end

                    local humanoid =
                        preparedCharacter
                        :FindFirstChildOfClass(
                            "Humanoid"
                        )

                    return player.Character
                        == preparedCharacter
                        and preparedCharacter.Parent ~= nil
                        and humanoid ~= nil
                        and humanoid.Health > 0
                end

                -- Only one independent chat worker.
                startIndependentChat(
                    characterActive
                )

                local firstPlacement = true

                while characterActive() do
                    --==================================================
                    -- TRADE PAUSE
                    --==================================================

                    while state.trade.active
                        and characterActive() do
                        task.wait(0.2)
                    end

                    if not characterActive() then
                        break
                    end

                    -- Let trade UI finish closing.
                    if not waitActive(
                            0.35,
                            characterActive
                        ) then
                        break
                    end

                    if state.trade.active then
                        continue
                    end

                    --==================================================
                    -- EXISTING DOOR
                    --==================================================

                    if state.door.instance
                        and doorStillExists(
                            state.door.instance
                        ) then
                        if not waitForDoorToDisappear(
                                characterActive
                            ) then
                            break
                        end
                    elseif not firstPlacement then
                        if not waitActive(
                                math.max(
                                    1,
                                    config.farm.placeDelay
                                ),
                                characterActive
                            ) then
                            break
                        end
                    end

                    if state.trade.active then
                        continue
                    end

                    if not characterActive() then
                        break
                    end

                    --==================================================
                    -- PLACE DOOR
                    --==================================================

                    local placed,
                    reason =
                        placeMagicDoor(
                            false,
                            characterActive
                        )

                    if reason == "trade_active" then
                        task.wait(0.2)

                        continue
                    end

                    if not characterActive() then
                        break
                    end

                    if placed then
                        firstPlacement = false

                        if not state.trade.active then
                            sendChatAfterDoor(
                                characterActive
                            )
                        end
                    else
                        if not waitActive(
                                math.max(
                                    1,
                                    config.farm.placeDelay
                                ),
                                characterActive
                            ) then
                            break
                        end
                    end
                end
            end)

        state.farm.running = false

        if not runOk then
            warn(
                "[MagicDoor] Farm error:",
                runError
            )
        end

        -- If it ended naturally and wasn't due
        -- to a teleport, setup needs preparing again.
        if config.farm.enabled
            and not state.teleport.active
            and state.farm.session == mySession then
            state.farm.preparedJobId = nil
            state.farm.houseListed = false
        end
    end)
end


--==============================================================
-- SERVER HOP
--==============================================================

local function formatServerHopCountdown(seconds)
    seconds =
        math.max(
            0,
            math.ceil(
                tonumber(seconds) or 0
            )
        )

    local minutes =
        math.floor(
            seconds / 60
        )

    local secs =
        seconds % 60

    if minutes > 0 then
        return string.format(
            "%dm %02ds",
            minutes,
            secs
        )
    end

    return string.format(
        "%ds",
        secs
    )
end


local function setServerHopStatus(text)
    if ui.serverHopStatus then
        pcall(function()
            ui.serverHopStatus:Set(
                text
            )
        end)
    end
end


local function stopServerHop()
    config.hop.autoServerHop = false

    state.serverHop.running = false
    state.serverHop.session += 1

    setServerHopStatus(
        "Status: Auto Server Hop is OFF"
    )

    saveConfig()
end


local function startServerHop()
    if state.serverHop.running then
        config.hop.autoServerHop = true
        saveConfig()

        return
    end

    state.serverHop.session += 1

    local mySession =
        state.serverHop.session

    state.serverHop.running = true
    config.hop.autoServerHop = true

    saveConfig()

    local function hopActive()
        return scriptAlive()
            and config.hop.autoServerHop
            and state.serverHop.session == mySession
    end

    task.spawn(function()
        while hopActive() do
            local remaining =
                math.max(
                    10,
                    config.hop.serverHopDelay
                )

            while remaining > 0
                and hopActive() do
                setServerHopStatus(
                    "Status: Teleporting in "
                    .. formatServerHopCountdown(
                        remaining
                    )
                )

                local step =
                    math.min(
                        1,
                        remaining
                    )

                task.wait(step)

                remaining -= step
            end

            if not hopActive() then
                break
            end

            setServerHopStatus(
                "Status: Teleporting to Trading Hub..."
            )

            local requested =
                teleportToTradingHub(
                    false,
                    hopActive
                )

            if requested then
                break
            end

            setServerHopStatus(
                "Status: Teleport failed - retrying..."
            )

            task.wait(1)
        end

        if state.serverHop.session == mySession then
            state.serverHop.running = false
        end
    end)
end


--==============================================================
-- NO TRADE SERVER HOP
--==============================================================

local function stopNoTradeHop()
    config.hop.noTradeHop = false

    state.noTrade.running = false
    state.noTrade.session += 1
    state.noTrade.paused = false

    setNoTradeGuiVisible(
        false
    )

    saveConfig()
end


local function startNoTradeHop()
    if state.noTrade.running then
        config.hop.noTradeHop = true

        setNoTradeGuiVisible(
            true
        )

        saveConfig()

        return
    end

    state.noTrade.session += 1

    local mySession =
        state.noTrade.session

    config.hop.noTradeHop = true
    state.noTrade.running = true

    resetNoTradeTimer(
        "enabled"
    )

    if state.trade.active then
        pauseNoTradeTimer(
            "already trading"
        )
    end

    setNoTradeGuiVisible(
        true
    )

    saveConfig()

    local function timerActive()
        return scriptAlive()
            and config.hop.noTradeHop
            and state.noTrade.session == mySession
    end

    task.spawn(function()
        while timerActive() do
            --==================================================
            -- TRADE ACTIVE = COMPLETELY PAUSE
            --==================================================

            if state.trade.active then
                if not state.noTrade.paused then
                    pauseNoTradeTimer(
                        "trade active"
                    )
                end

                setNoTradeStatus(
                    "TRADE ACTIVE - TIMER PAUSED"
                )

                task.wait(0.2)

                continue
            end

            -- Trade closed without transition safety.
            if state.noTrade.paused then
                resetNoTradeTimer(
                    "trade closed"
                )
            end

            local remaining =
                getNoTradeRemaining()

            if remaining > 0 then
                setNoTradeStatus(
                    "Teleporting in "
                    .. formatNoTradeCountdown(
                        remaining
                    )
                )
            else
                -- Final trade validation.
                if state.trade.gui then
                    updateTradeState()
                end

                if state.trade.active then
                    pauseNoTradeTimer(
                        "trade detected before hop"
                    )

                    task.wait(0.2)

                    continue
                end

                if not state.teleport.active then
                    setNoTradeStatus(
                        "Teleporting to Trading Hub..."
                    )

                    notify(
                        "No Trade Hop",
                        "No trade for 5 minutes. Hopping...",
                        3
                    )

                    local requested =
                        teleportToTradingHub(
                            false,
                            timerActive
                        )

                    if requested then
                        break
                    end

                    resetNoTradeTimer(
                        "hop request failed"
                    )
                end
            end

            task.wait(0.2)
        end

        if state.noTrade.session == mySession then
            state.noTrade.running = false
        end
    end)
end


--==============================================================
-- RAYFIELD WINDOW
--==============================================================

local Window =
    Rayfield:CreateWindow({
        Name = "Magic Door",

        LoadingTitle =
        "Magic Door Utility",

        ConfigurationSaving = {
            Enabled = true,

            FolderName =
            "MagicDoorConfigs",

            FileName =
            "RayfieldConfig",
        },

        KeySystem = false,
    })

ui.window = Window


local MainTab =
    Window:CreateTab(
        "🪄 Main",
        4483362458
    )


local SettingsTab =
    Window:CreateTab(
        "⚙️ Settings",
        4483362458
    )


local HouseTab =
    Window:CreateTab(
        "🏠 House Spawner",
        4483362458
    )


--==============================================================
-- TRADE TIMEOUT UI
--==============================================================

MainTab:CreateSection(
    "⏱️ Trade Timeout"
)


ui.noTradeHopToggle =
    MainTab:CreateToggle({
        Name =
        "Hop If No Trade For 5 Minutes",

        CurrentValue =
            config.hop.noTradeHop,

        Flag =
        "HopIfNoTrade5Min",

        Callback =
            function(value)
                if value then
                    startNoTradeHop()

                    notify(
                        "No Trade Hop",
                        "Enabled. Timer pauses during trades and resets to 5:00 after.",
                        4
                    )
                else
                    stopNoTradeHop()

                    notify(
                        "No Trade Hop",
                        "Disabled.",
                        2
                    )
                end
            end,
    })


MainTab:CreateLabel(
    "Trade active = timer + door + message paused."
)


MainTab:CreateLabel(
    "Trade closes = timer resets to 5:00 and farm resumes."
)


ensureNoTradeGui()

setNoTradeGuiVisible(
    config.hop.noTradeHop
)


--==============================================================
-- FARM UI
--==============================================================

MainTab:CreateSection(
    "🪄 Magic Door Farm"
)


ui.autoFarmToggle =
    MainTab:CreateToggle({
        Name =
        "Auto Farm (Door + Chat)",

        CurrentValue =
            config.farm.enabled,

        Flag =
        "AutoFarm",

        Callback =
            function(value)
                if value then
                    startFarm()

                    notify(
                        "Auto Farm",
                        "Started.",
                        2
                    )
                else
                    stopFarm()

                    notify(
                        "Auto Farm",
                        "Stopped.",
                        2
                    )
                end
            end,
    })


MainTab:CreateSlider({
    Name =
    "Place Delay",

    Range =
    { 1, 60 },

    Increment =
        1,

    Suffix =
    "s",

    CurrentValue =
        config.farm.placeDelay,

    Callback =
        function(value)
            config.farm.placeDelay =
                value

            saveConfig()
        end,
})


MainTab:CreateSlider({
    Name =
    "Placement Distance",

    Range =
    { 2, 20 },

    Increment =
        1,

    Suffix =
    " studs",

    CurrentValue =
        config.farm.placementDistance,

    Callback =
        function(value)
            config.farm.placementDistance =
                value

            saveConfig()
        end,
})


MainTab:CreateButton({
    Name =
    "Place One Door",

    Callback =
        function()
            if state.trade.active then
                notify(
                    "Door",
                    "Door placement is paused while trading.",
                    2
                )

                return
            end

            local success =
                placeMagicDoor(
                    true
                )

            if success then
                notify(
                    "Door",
                    "Door placed.",
                    2
                )

                sendChatAfterDoor()
            end
        end,
})


--==============================================================
-- CHAT UI
--==============================================================

MainTab:CreateSection(
    "💬 Auto Chat"
)


MainTab:CreateInput({
    Name =
    "Message",

    PlaceholderText =
    "Type message...",

    RemoveTextAfterFocusLost =
        false,

    CurrentValue =
        config.chat.message,

    Callback =
        function(value)
            config.chat.message =
                tostring(
                    value or ""
                )

            saveConfig()
        end,
})


MainTab:CreateDropdown({
    Name =
    "Chat Mode",

    Options = {
        "Once Per Server",
        "After Every Door",
        "Independent",
    },

    CurrentOption = {
        config.chat.mode,
    },

    MultipleOptions =
        false,

    Callback =
        function(option)
            local value =
                type(option) == "table"
                and option[1]
                or option

            if value then
                config.chat.mode =
                    value

                state.door.chatSession += 1

                saveConfig()
            end
        end,
})


MainTab:CreateSlider({
    Name =
    "Chat Delay",

    Range =
    { 1, 120 },

    Increment =
        1,

    Suffix =
    "s",

    CurrentValue =
        config.chat.delay,

    Callback =
        function(value)
            config.chat.delay =
                value

            saveConfig()
        end,
})


MainTab:CreateButton({
    Name =
    "Send Test Message",

    Callback =
        function()
            if state.trade.active then
                notify(
                    "Chat",
                    "Messages are paused while trading.",
                    2
                )

                return
            end

            local sent =
                sendMessage(
                    config.chat.message
                )

            notify(
                "Chat",
                sent
                and "Message sent."
                or "Message not sent.",
                2
            )
        end,
})


--==============================================================
-- POSITION UI
--==============================================================

MainTab:CreateSection(
    "📍 Saved Position"
)


MainTab:CreateToggle({
    Name =
    "Auto Teleport to Saved Position on Join",

    CurrentValue =
        config.position.autoTeleportOnJoin,

    Callback =
        function(value)
            config.position.autoTeleportOnJoin =
                value

            saveConfig()
        end,
})


MainTab:CreateButton({
    Name =
    "Save Current Position",

    Callback =
        function()
            local ok, reason =
                saveCurrentPosition()

            notify(
                "Position",
                ok
                and "Position saved."
                or reason,
                3
            )
        end,
})


MainTab:CreateButton({
    Name =
    "Teleport to Saved Position",

    Callback =
        function()
            local ok, reason =
                teleportToSavedPosition(
                    true
                )

            if not ok then
                notify(
                    "Position",
                    reason,
                    3
                )
            end
        end,
})


--==============================================================
-- HOUSE / TRADE UI
--==============================================================

MainTab:CreateSection(
    "🏠 House / Trade"
)


MainTab:CreateButton({
    Name =
    "List House for Trade",

    Callback =
        function()
            local ok, reason =
                listHouseForTrade()

            notify(
                "House",
                ok
                and "House listing completed."
                or tostring(reason),
                3
            )
        end,
})


MainTab:CreateButton({
    Name =
    "Unlist House for Trade",

    Callback =
        function()
            local ok =
                unlistHouse()

            notify(
                "House",
                ok
                and "House unlisted."
                or "Failed to unlist.",
                2
            )
        end,
})


MainTab:CreateToggle({
    Name =
    "Auto Accept Trades",

    CurrentValue =
        config.trade.autoAccept,

    Callback =
        function(value)
            config.trade.autoAccept =
                value

            saveConfig()
        end,
})


MainTab:CreateDropdown({
    Name =
    "Accept Trades From",

    Options = {
        "Everyone",
        "Friends Only",
        "Whitelist",
    },

    CurrentOption = {
        config.trade.mode,
    },

    MultipleOptions =
        false,

    Callback =
        function(option)
            local value =
                type(option) == "table"
                and option[1]
                or option

            if value then
                config.trade.mode =
                    value

                saveConfig()
            end
        end,
})


MainTab:CreateInput({
    Name =
    "Trade Whitelist",

    PlaceholderText =
    "user1, user2, user3",

    RemoveTextAfterFocusLost =
        false,

    CurrentValue =
        config.trade.whitelist,

    Callback =
        function(value)
            config.trade.whitelist =
                tostring(
                    value or ""
                )

            saveConfig()
        end,
})


MainTab:CreateButton({
    Name =
    "Show Trade / Timer Status",

    Callback =
        function()
            local remaining =
                getNoTradeRemaining()

            notify(
                "Trade Status",

                "Trade: "
                .. (
                    state.trade.active
                    and "ACTIVE"
                    or "NONE"
                )

                .. " | Timer: "

                .. (
                    state.noTrade.paused
                    and "PAUSED"
                    or formatNoTradeCountdown(
                        remaining
                    )
                )

                .. " | GUI: "

                .. (
                    state.trade.gui
                    and state.trade.gui.Name
                    or "NONE"
                ),

                7
            )
        end,
})


--==============================================================
-- TRADING HUB UI
--==============================================================

MainTab:CreateSection(
    "🏙️ Trading Hub"
)


MainTab:CreateButton({
    Name =
    "Teleport to Trading Hub",

    Callback =
        function()
            teleportToTradingHub(
                true
            )
        end,
})


--==============================================================
-- SERVER HOP UI
--==============================================================

MainTab:CreateSection(
    "🌍 Server Hop"
)


ui.serverHopStatus =
    MainTab:CreateLabel(
        config.hop.autoServerHop
        and (
            "Status: Teleporting in "
            .. formatServerHopCountdown(
                config.hop.serverHopDelay
            )
        )
        or "Status: Auto Server Hop is OFF"
    )


ui.autoServerHopToggle =
    MainTab:CreateToggle({
        Name =
        "Auto Server Hop",

        CurrentValue =
            config.hop.autoServerHop,

        Flag =
        "AutoServerHop",

        Callback =
            function(value)
                if value then
                    startServerHop()

                    notify(
                        "Server Hop",
                        "Enabled.",
                        2
                    )
                else
                    stopServerHop()

                    notify(
                        "Server Hop",
                        "Disabled.",
                        2
                    )
                end
            end,
    })


MainTab:CreateSlider({
    Name =
    "Hop Delay",

    Range =
    { 10, 3600 },

    Increment =
        10,

    Suffix =
    "s",

    CurrentValue =
        config.hop.serverHopDelay,

    Callback =
        function(value)
            config.hop.serverHopDelay =
                value

            saveConfig()
        end,
})


MainTab:CreateSlider({
    Name =
    "Minimum Free Slots",

    Range =
    { 1, 20 },

    Increment =
        1,

    Suffix =
    " slots",

    CurrentValue =
        config.hop.minFreeSlots,

    Callback =
        function(value)
            config.hop.minFreeSlots =
                value

            saveConfig()
        end,
})


MainTab:CreateToggle({
    Name =
    "Avoid Visited Servers",

    CurrentValue =
        config.hop.avoidVisitedServers,

    Callback =
        function(value)
            config.hop.avoidVisitedServers =
                value

            saveConfig()
        end,
})


MainTab:CreateButton({
    Name =
    "Hop Server Now",

    Callback =
        function()
            teleportToTradingHub(
                true
            )
        end,
})


--==============================================================
-- SESSION UI
--==============================================================

MainTab:CreateSection(
    "📊 Session"
)


MainTab:CreateButton({
    Name =
    "Show Session Stats",

    Callback =
        function()
            local runtime =
                math.floor(
                    os.clock()
                    - state.sessionStartedAt
                )

            notify(
                "Session Stats",

                string.format(
                    "Doors: %d | Failed: %d | Chats: %d | Hub requests: %d | Trades: %d | Runtime: %dm %ds",
                    state.stats.doorsPlaced,

                    state.stats.placementFailures,

                    state.stats.chatsSent,

                    state.stats.hubRequests,

                    state.stats.tradesAccepted,

                    math.floor(
                        runtime / 60
                    ),

                    runtime % 60
                ),

                8
            )
        end,
})


MainTab:CreateButton({
    Name =
    "Reset Session Stats",

    Callback =
        function()
            state.stats.doorsPlaced = 0
            state.stats.placementFailures = 0
            state.stats.chatsSent = 0
            state.stats.hubRequests = 0
            state.stats.tradesAccepted = 0

            state.sessionStartedAt =
                os.clock()

            notify(
                "Session",
                "Stats reset.",
                2
            )
        end,
})


--==============================================================
-- SETTINGS TAB
--==============================================================

SettingsTab:CreateSection(
    "Placement Reliability"
)


SettingsTab:CreateToggle({
    Name =
    "Retry Failed Placement",

    CurrentValue =
        config.farm.retryPlacement,

    Callback =
        function(value)
            config.farm.retryPlacement =
                value

            saveConfig()
        end,
})


SettingsTab:CreateSlider({
    Name =
    "Max Placement Retries",

    Range =
    { 0, 10 },

    Increment =
        1,

    Suffix =
    " retries",

    CurrentValue =
        config.farm.maxRetries,

    Callback =
        function(value)
            config.farm.maxRetries =
                value

            saveConfig()
        end,
})


SettingsTab:CreateSection(
    "Interface / Debug"
)


SettingsTab:CreateToggle({
    Name =
    "Notifications",

    CurrentValue =
        config.interface.notifications,

    Callback =
        function(value)
            config.interface.notifications =
                value

            saveConfig()
        end,
})


SettingsTab:CreateToggle({
    Name =
    "Debug Logging",

    CurrentValue =
        config.interface.debug,

    Callback =
        function(value)
            config.interface.debug =
                value

            saveConfig()
        end,
})


SettingsTab:CreateButton({
    Name =
    "Save Settings Now",

    Callback =
        function()
            saveConfig()

            notify(
                "Settings",
                "Settings saved.",
                2
            )
        end,
})


SettingsTab:CreateButton({
    Name =
    "Clear Visited Server History",

    Callback =
        function()
            state.visitedServers = {}

            if game.JobId
                and game.JobId ~= "" then
                state.visitedServers[
                game.JobId
                ] = true
            end

            notify(
                "Server Hop",
                "Visited history cleared.",
                2
            )
        end,
})


--==============================================================
-- HOUSE SPAWNER
--==============================================================

local selectedHouseId

local houseNames = {}
local houseMap = {}


local function refreshHouseList()
    table.clear(
        houseNames
    )

    table.clear(
        houseMap
    )

    local ok, houses =
        pcall(function()
            return ClientData.get(
                "house_manager"
            )
        end)

    if not ok
        or type(houses) ~= "table" then
        houses = {}
    end

    -- Handle table/array house manager layouts.
    for _, house in pairs(
        houses
    ) do
        if type(house) == "table"
            and house.house_id then
            local baseName =
                house.name
                or (
                    "House "
                    .. tostring(
                        house.house_id
                    )
                )

            local displayName =
                tostring(baseName)

            -- Prevent duplicate house names
            -- from overwriting another ID.
            if houseMap[displayName] then
                displayName =
                    displayName
                    .. " ["
                    .. tostring(
                        house.house_id
                    )
                    .. "]"
            end

            table.insert(
                houseNames,
                displayName
            )

            houseMap[
            displayName
            ] =
                house.house_id
        end
    end

    table.sort(
        houseNames
    )

    if ui.houseDropdown then
        ui.houseDropdown:Refresh(
            houseNames
        )
    end

    return #houseNames
end


ui.houseDropdown =
    HouseTab:CreateDropdown({
        Name =
        "Select House",

        Options =
        {},

        CurrentOption =
        {},

        MultipleOptions =
            false,

        Callback =
            function(option)
                local name =
                    type(option) == "table"
                    and option[1]
                    or option

                selectedHouseId =
                    houseMap[name]

                if name then
                    notify(
                        "House Selected",
                        tostring(name),
                        2
                    )
                end
            end,
    })


HouseTab:CreateButton({
    Name =
    "Refresh Houses",

    Callback =
        function()
            local amount =
                refreshHouseList()

            notify(
                "House Spawner",
                "Loaded "
                .. tostring(amount)
                .. " houses.",
                2
            )
        end,
})


HouseTab:CreateButton({
    Name =
    "Spawn Selected House",

    Callback =
        function()
            if not selectedHouseId then
                notify(
                    "House",
                    "Select a house first.",
                    3
                )

                return
            end

            local ok, err =
                pcall(function()
                    Router.get(
                        "HousingAPI/SpawnHouse"
                    ):FireServer(
                        selectedHouseId
                    )
                end)

            notify(
                "House",

                ok
                and "House spawned."
                or tostring(err),

                3
            )
        end,
})


refreshHouseList()


--==============================================================
-- CLEAN SHUTDOWN
--==============================================================

local function shutdown()
    if not state.running then
        return
    end

    state.running = false

    -- Stop loops but preserve saved toggle states.
    state.farm.running = false
    state.serverHop.running = false
    state.noTrade.running = false

    state.farm.session += 1
    state.serverHop.session += 1
    state.noTrade.session += 1

    state.door.chatSession += 1

    state.teleport.requestId += 1

    disconnectTradeGui()

    disconnectConnections(
        connections
    )

    if ui.noTradeGui then
        pcall(function()
            ui.noTradeGui:Destroy()
        end)

        ui.noTradeGui = nil
        ui.noTradeStatus = nil
    end

    pcall(function()
        Rayfield:Destroy()
    end)

    if GLOBAL_ENV.__MagicDoorShutdown
        == shutdown then
        GLOBAL_ENV.__MagicDoorShutdown =
            nil
    end
end


GLOBAL_ENV.__MagicDoorShutdown =
    shutdown


--==============================================================
-- RESUME SAVED AUTOMATION
--==============================================================

local resumeFarm =
    config.farm.enabled

local resumeServerHop =
    config.hop.autoServerHop

local resumeNoTradeHop =
    config.hop.noTradeHop


task.defer(function()
    task.wait(0.5)

    if not scriptAlive() then
        return
    end

    if resumeFarm
        and not state.farm.running then
        startFarm()

        if ui.autoFarmToggle then
            pcall(function()
                ui.autoFarmToggle:Set(
                    true
                )
            end)
        end
    end

    if resumeServerHop
        and not state.serverHop.running then
        startServerHop()

        if ui.autoServerHopToggle then
            pcall(function()
                ui.autoServerHopToggle:Set(
                    true
                )
            end)
        end
    end

    if resumeNoTradeHop
        and not state.noTrade.running then
        startNoTradeHop()

        if ui.noTradeHopToggle then
            pcall(function()
                ui.noTradeHopToggle:Set(
                    true
                )
            end)
        end
    end
end)


--==============================================================
-- AUTO TELEPORT ON JOIN
--==============================================================

if config.position.autoTeleportOnJoin then
    task.spawn(function()
        local function startupActive()
            return scriptAlive()
                and config.position.autoTeleportOnJoin
                and not config.farm.enabled
                and not state.teleport.active
        end

        local ready =
            waitForPlayerReady(
                startupActive
            )

        if ready
            and startupActive() then
            teleportToSavedPosition(
                true,
                startupActive
            )
        end
    end)
end


--==============================================================
-- READY
--==============================================================

notify(
    "Magic Door",
    "Ready.",
    3
)
