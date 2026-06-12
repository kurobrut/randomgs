-- // Services and modules
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")
local VirtualUser = game:GetService("VirtualUser")

local router = require(ReplicatedStorage.ClientModules.Core.RouterClient.RouterClient)
local cd = require(ReplicatedStorage.ClientModules.Core.ClientData)
local furnituresdb = require(ReplicatedStorage.ClientDB.Housing.FurnitureDB)
local texturesdb = require(ReplicatedStorage.ClientDB.Housing.TexturesDB)
local housedb = require(ReplicatedStorage.ClientDB.Housing.HouseDB)

local Fsys = require(ReplicatedStorage:WaitForChild("Fsys")).load
local HouseDB = Fsys("HouseDB")
local ClientData = Fsys("ClientData")
local Router = Fsys("RouterClient")

local plr = Players.LocalPlayer

--==================================================
-- JSON Helpers
--==================================================
local function lEncode(t)
	return HttpService:JSONEncode(t)
end
local function lDecode(s)
	return HttpService:JSONDecode(s)
end

local function loadMain()
	local Rayfield = loadstring(game:HttpGet("https://sirius.menu/rayfield"))()

	local Window = Rayfield:CreateWindow({
		Name = "Cubix . House Cloner ",
		LoadingTitle = "Cubix",
		LoadingSubtitle = "House Cloner",
		Theme = "Amethyst",
		Discord = {
			Enabled = true,
			Invite = "https://discord.gg/VVsxaBNakm",
			RememberJoins = false,
		},
	})

	local savedhouse = nil
	local stopFlag = false  -- single declaration

	-- Forward-declare paste functions so Auto Paste tab can reference them
	local pastehousefast
	local pastehouseslow
	local IgnoreTypeCheck

	local afkEnabled = false
	plr.Idled:Connect(function()
		VirtualUser:CaptureController()
		VirtualUser:ClickButton2(Vector2.new(0, 0))
		if not afkEnabled then
			afkEnabled = true
			Rayfield:Notify({
				Title = "AFK",
				Content = "Anti-AFK is now active",
				Duration = 3
			})
		end
	end)

	local Manager = Window:CreateTab("Manager", "trending-up")
	local Tab = Window:CreateTab("Main", "home")
	local BuyerTab = Window:CreateTab("House Buyer", "shopping-bag")
	local TradeTab = Window:CreateTab("Trading", "repeat")

	-- ==================== MANAGER TAB ====================
	Manager:CreateSection("Scan Information")
	local furniture_label = Manager:CreateLabel("House Furniture: 0 ($0)", "armchair")
	local textures_label = Manager:CreateLabel("House Textures: 0 ($0)", "grid-2x2")
	local ambiance_label = Manager:CreateLabel("House Ambiance: No", "sun")
	local type_label = Manager:CreateLabel("House Type: -", "home")

	Manager:CreateSection("Process Status")
	local status_label = Manager:CreateLabel("Building Status: Idle", "activity")
	local prog_label = Manager:CreateLabel("Building Prog: -", "trending-up")
	local item_label = Manager:CreateLabel("Items: -", "box")

	local function setscaninfo(f_count, f_cost, t_count, t_cost, amb, typ)
		pcall(function()
			furniture_label:Set("House Furniture: " .. f_count .. " ($" .. f_cost .. ")")
			textures_label:Set("House Textures: " .. t_count .. " ($" .. t_cost .. ")")
			ambiance_label:Set("House Ambiance: " .. amb)
			type_label:Set("House Type: " .. typ)
		end)
	end

	local function updatestatus(s)
		pcall(function()
			status_label:Set("Building Status: " .. s)
		end)
	end
	local function updateprog(p)
		pcall(function()
			prog_label:Set("Building Prog: " .. p)
		end)
	end
	local function updateitem(i)
		pcall(function()
			item_label:Set("Items: " .. i)
		end)
	end

	updatestatus("Idle")
	updateprog("-")
	updateitem("-")

	-- ==================== SHARED OWNED HOUSES SYSTEM ====================
	local ownedHouseList = {}
	local ownedHouseMap = {} -- name → house_id
	local ownedHouseTypeMap = {} -- house_id → resolved house type
	local ownedDropdown
	local tradeDropdown
	local autoPasteDropdown

	local function resolveHouseType(typeValue)
		if not typeValue or typeValue == "-" or typeValue == "Unknown" or typeValue == "" then
			return nil
		end

		local low = string.lower(tostring(typeValue))
		for kind, data in pairs(housedb) do
			if string.lower(tostring(kind)) == low then
				return string.lower(tostring(kind))
			end
			if data.name and string.lower(data.name) == low then
				return string.lower(tostring(kind))
			end
			if data.building_type and string.lower(tostring(data.building_type)) == low then
				return string.lower(tostring(kind))
			end
			if data.type and string.lower(tostring(data.type)) == low then
				return string.lower(tostring(kind))
			end
		end

		return low
	end

	local function resolveExactHouseType(typeValue)
		if not typeValue or typeValue == "-" or typeValue == "Unknown" then return nil end
		for kind, data in pairs(housedb) do
			if kind == typeValue then return kind end
			if data.name and string.lower(data.name) == string.lower(tostring(typeValue)) then return kind end
			if data.building_type and data.building_type == typeValue then return kind end
			if data.type and data.type == typeValue then return kind end
		end
		return typeValue
	end

	local function getExactHouseDisplayName(kind)
		for k, data in pairs(housedb) do
			if k == kind then return data.name or kind end
		end
		return kind
	end

	local function isExactSameHouseType(a, b)
		if a == b then return true end
		local function getName(val)
			for kind, data in pairs(housedb) do
				if kind == val then return data.name end
				if data.name and string.lower(data.name) == string.lower(tostring(val)) then return data.name end
			end
			return tostring(val)
		end
		return string.lower(getName(a)) == string.lower(getName(b))
	end

	local function getSavedHouseExactType(houseData)
		local savedType = "-"
		local savedKind = nil
		local savedName = nil
		pcall(function()
			savedType = houseData.building_type or "-"
			savedKind = houseData.kind
			savedName = houseData.name
		end)

		local resolvedSaved = resolveExactHouseType(savedType)
		if not resolvedSaved and savedKind then resolvedSaved = resolveExactHouseType(savedKind) end
		if not resolvedSaved and savedName then resolvedSaved = resolveExactHouseType(savedName) end
		return resolvedSaved
	end

	local function getInteriorExactType(houseInterior)
		local currentType = "-"
		pcall(function()
			currentType = houseInterior.building_type or "-"
		end)
		return resolveExactHouseType(currentType)
	end

	local function refreshOwnedHouses()
		table.clear(ownedHouseList)
		table.clear(ownedHouseMap)
		table.clear(ownedHouseTypeMap)

		for _, house in pairs(ClientData.get("house_manager") or {}) do
			table.insert(ownedHouseList, house.name)
			ownedHouseMap[house.name] = house.house_id
			local houseType = house.building_type or house.kind or house.type or "unknown"
			ownedHouseTypeMap[house.house_id] = resolveExactHouseType(houseType) or resolveHouseType(houseType) or tostring(houseType)
		end

		table.sort(ownedHouseList)

		if ownedDropdown then
			pcall(function() ownedDropdown:Refresh(ownedHouseList, true) end)
		end
		if tradeDropdown then
			pcall(function() tradeDropdown:Refresh(ownedHouseList, true) end)
		end
		if autoPasteDropdown then
			pcall(function() autoPasteDropdown:Refresh(ownedHouseList, true) end)
		end
	end

	-- ==================== AUTO PASTE TAB ====================
	local AutoPasteTab = Window:CreateTab("Auto Paste", "copy")

	local autoPasteSelections = {}  -- { [house_id] = display_name }
	local autoPasteRunning = false
	local autoPasteMode = "fast"
	local autoPasteSource = "loaded"
	local autoPasteSingleFile = false
	local fileQueue = {}
	local fqAllFiles = {}
	local fqSearchQuery = ""
	local fqFileDropdown
	local fqQueueListLabel
	local autoPasteFileInfo
	local autoPastePastebinValue = ""
	local autoPasteQueueCopies = 1
	local autoPasteSourceDropdown

	local function deserializeFileValue(value)
		if type(value) ~= "table" then return value end
		if #value > 0 then
			if #value == 3 and type(value[1]) == "number" then return Color3.new(unpack(value)) end
			if #value == 12 and type(value[1]) == "number" then return CFrame.new(unpack(value)) end
		end
		if value.r and value.g and value.b and type(value.r) == "number" then return Color3.new(value.r, value.g, value.b) end
		if value.R and value.G and value.B and type(value.R) == "number" then return Color3.new(value.R, value.G, value.B) end
		if value.__type == "CFrame" then return CFrame.new(unpack(value.components))
		elseif value.__type == "Vector3" then return Vector3.new(value.x or value.X, value.y or value.Y, value.z or value.Z)
		elseif value.__type == "Color3" then return Color3.new(value.r or value.R, value.g or value.G, value.b or value.B) end
		for k, v in pairs(value) do value[k] = deserializeFileValue(v) end
		return value
	end

	local function convertFileToInternalFormat(decoded)
		if decoded.f and type(decoded.f) == "table" and #decoded.f > 0 and decoded.t and decoded.b then
			local furniture = {}
			for i, f in ipairs(decoded.f) do
				local colors = {}
				for ck, cv in pairs(f.cl or {}) do colors[tonumber(ck)] = cv end
				furniture[tostring(i)] = { id = f.i, cframe = f.c, colors = colors, scale = f.s }
			end
			decoded.furniture = furniture
			decoded.f = nil

			local textures = {}
			for _, t in pairs(decoded.t or {}) do
				local room = t.r
				if not textures[room] then textures[room] = {} end
				if t.k == "walls" then textures[room].walls = t.i
				elseif t.k == "floors" then textures[room].floors = t.i end
			end
			decoded.textures = textures
			decoded.building_type = decoded.b
			decoded.ambiance = decoded.a
		elseif decoded.Furniture then
			decoded.furnitures = decoded.Furniture
			decoded.Furniture = nil
		end

		if decoded.Floors or decoded.Walls then
			decoded.textures = {}
			if decoded.Floors then
				for _, f in ipairs(decoded.Floors) do
					table.insert(decoded.textures, { type = f.typeOfTexture, id = f.id, room = f.room })
				end
			end
			if decoded.Walls then
				for _, w in ipairs(decoded.Walls) do
					table.insert(decoded.textures, { type = w.typeOfTexture, id = w.id, room = w.room })
				end
			end
		end

		if decoded.BuildType then decoded.building_type = decoded.BuildType decoded.BuildType = nil end

		if decoded.furnitures and #decoded.furnitures > 0 then
			local function convertColors(obj)
				if type(obj) ~= "table" then return obj end
				if obj.__isColor then return { __type = "Color3", r = obj.r, g = obj.g, b = obj.b } end
				for k, v in pairs(obj) do obj[k] = convertColors(v) end
				return obj
			end

			local furniture = {}
			for i, f in ipairs(decoded.furnitures) do
				local colors = {}
				for ck, cv in pairs(f.colors or {}) do colors[ck] = cv end
				furniture[tostring(i)] = { id = f.id, cframe = f.cframe, colors = colors, scale = f.scale }
			end
			decoded.furniture = furniture
			decoded.furnitures = nil

			local textures = {}
			for _, t in ipairs(decoded.textures or {}) do
				if not textures[t.room] then textures[t.room] = {} end
				if t.type == "walls" then textures[t.room].walls = t.id
				elseif t.type == "floors" then textures[t.room].floors = t.id end
			end
			decoded.textures = textures
			if decoded.ambiance then decoded.ambiance = convertColors(decoded.ambiance) end
		elseif type(decoded.furniture) == "table" then
			for _, item in pairs(decoded.furniture) do
				local new_colors = {}
				for i, col in ipairs(item.colors or {}) do new_colors[i] = col end
				item.colors = new_colors
				if type(item.cframe) == "table" and item.cframe.components then
					item.cframe = item.cframe.components
				end
			end
		end

		decoded.building_type = decoded.building_type or decoded.buildingType or "Unknown"
		decoded.buildingType = nil
		return decoded
	end

	local function loadHouseDataFromFile(filename)
		local filePath = "HouseFS/" .. filename
		local success, content = pcall(readfile, filePath)
		if not success or not content then
			return nil, "Failed to read file"
		end

		local decoded
		local ok = pcall(function()
			decoded = HttpService:JSONDecode(content)
		end)

		if not ok then
			local env = {
				Vector3 = { new = function(x, y, z) return { __type = "Vector3", X = x, Y = y, Z = z } end },
				Color3 = { new = function(r, g, b) return { __type = "Color3", R = r, G = g, B = b } end },
				CFrame = { new = function(...) return { __type = "CFrame", components = { ... } } end },
			}
			local func, loaderr = loadstring(content)
			if not func then return nil, "Loadstring error: " .. tostring(loaderr) end
			setfenv(func, env)
			local runok, data = pcall(func)
			if not runok then return nil, "Run error: " .. tostring(data) end
			decoded = data
		end

		if type(decoded) ~= "table" then
			return nil, "Invalid data in file"
		end

		return deserializeFileValue(convertFileToInternalFormat(decoded)), nil
	end

	local function loadHouseDataFromPastebin(pasteValue)
		local input = tostring(pasteValue or ""):gsub("%s+", "")
		if input == "" then
			return nil, "Please enter a Pastebin link or ID"
		end

		local pasteId = input:match("pastebin%.com/(.+)")
		if pasteId then
			pasteId = pasteId:gsub("raw/", "")
			pasteId = pasteId:match("([^/?#]+)") or pasteId
		else
			pasteId = input
		end

		local response
		local success = pcall(function()
			response = HttpService:RequestAsync({
				Url = "https://pastebin.com/raw/" .. pasteId,
				Method = "GET",
			})
		end)

		if not success or not response or not response.Body or response.Body == "" then
			return nil, "Failed to fetch Pastebin data"
		end

		local decoded
		local ok = pcall(function()
			decoded = HttpService:JSONDecode(response.Body)
		end)

		if not ok or type(decoded) ~= "table" then
			return nil, "Invalid Pastebin JSON"
		end

		return deserializeFileValue(convertFileToInternalFormat(decoded)), pasteId
	end

	local function getFileHouseType(houseData)
		return getSavedHouseExactType(houseData) or "Unknown"
	end

	local function findMatchingHouse(fileType, candidateIds, usedIds)
		local fallbackId = nil
		for _, houseId in ipairs(candidateIds) do
			if not usedIds[houseId] then
				local ownedType = ownedHouseTypeMap[houseId]
				if ownedType and isExactSameHouseType(fileType, ownedType) then
					return houseId
				end
				if not fallbackId and (not ownedType or ownedType == "unknown" or ownedType == "Unknown") then
					fallbackId = houseId
				end
			end
		end
		return fallbackId
	end

	local function setAPFileInfo()
		if autoPasteFileInfo then
			pcall(function()
				autoPasteFileInfo:Set("File Queue: " .. #fileQueue .. " file(s)")
			end)
		end
	end

	local function setAutoPasteSource(source)
		autoPasteSource = source
		if autoPasteSourceDropdown then
			pcall(function()
				autoPasteSourceDropdown:Set(source == "filequeue" and "File Queue" or "Loaded House")
			end)
		end
	end

	local function rebuildQueueLabel()
		if not fqQueueListLabel then return end
		if #fileQueue == 0 then
			pcall(function() fqQueueListLabel:Set("Queue: (empty)") end)
			return
		end

		local lines = {}
		for i, entry in ipairs(fileQueue) do
			table.insert(lines, i .. ". " .. entry.filename .. " [" .. getFileHouseType(entry.houseData) .. "]")
		end
		pcall(function() fqQueueListLabel:Set("Queue:\n" .. table.concat(lines, "\n")) end)
	end

	local function refreshFQFileList()
		table.clear(fqAllFiles)
		if not isfolder("HouseFS") then makefolder("HouseFS") end
		for _, filePath in ipairs(listfiles("HouseFS")) do
			local fileName = filePath:match("^.+/(.+)$") or filePath
			if fileName:sub(-5) == ".json" or fileName:sub(-4) == ".txt" or fileName:sub(-4) == ".lua" then
				table.insert(fqAllFiles, fileName)
			end
		end
		table.sort(fqAllFiles)

		local filtered = {}
		for _, name in ipairs(fqAllFiles) do
			if fqSearchQuery == "" or string.find(string.lower(name), string.lower(fqSearchQuery), 1, true) then
				table.insert(filtered, name)
			end
		end

		if fqFileDropdown then
			pcall(function() fqFileDropdown:Refresh(filtered) end)
		end
	end

	AutoPasteTab:CreateLabel("Use the current loaded house, or queue files from the same HouseFS folder used by Create File.", "info")

	AutoPasteTab:CreateSection("Source")
	autoPasteSourceDropdown = AutoPasteTab:CreateDropdown({
		Name = "Paste Source",
		Options = { "Loaded House", "File Queue" },
		CurrentOption = { "Loaded House" },
		MultipleOptions = false,
		Callback = function(opt)
			local v = (typeof(opt) == "table") and opt[1] or opt
			setAutoPasteSource(v == "File Queue" and "filequeue" or "loaded")
		end,
	})

	AutoPasteTab:CreateToggle({
		Name = "Single File Mode",
		CurrentValue = false,
		Callback = function(v)
			autoPasteSingleFile = v
		end,
	})

	AutoPasteTab:CreateSection("File Queue")
	AutoPasteTab:CreateInput({
		Name = "Copies To Queue",
		PlaceholderText = "1",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			local n = tonumber(value)
			if n and n > 0 then
				autoPasteQueueCopies = math.clamp(math.floor(n), 1, 50)
				Rayfield:Notify({
					Title = "File Queue",
					Content = "Copies set to " .. autoPasteQueueCopies,
					Duration = 2,
				})
			end
		end,
	})

	AutoPasteTab:CreateInput({
		Name = "Search Files",
		PlaceholderText = "Type to filter files...",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			fqSearchQuery = tostring(value or "")
			refreshFQFileList()
		end,
	})

	fqFileDropdown = AutoPasteTab:CreateDropdown({
		Name = "Select File(s) to Queue",
		Options = {},
		CurrentOption = {},
		MultipleOptions = true,
		Callback = function(_) end,
	})

	AutoPasteTab:CreateButton({
		Name = "Refresh File List",
		Callback = function()
			refreshFQFileList()
			Rayfield:Notify({ Title = "File Queue", Content = "File list refreshed", Duration = 2 })
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Add Selected File(s) to Queue",
		Callback = function()
			local selected = fqFileDropdown.CurrentOption
			if type(selected) == "string" then selected = { selected } end
			if not selected or #selected == 0 then
				return Rayfield:Notify({ Title = "File Queue", Content = "No file selected", Duration = 3 })
			end

			local added = 0
			for _, filename in ipairs(selected) do
				local houseData, err = loadHouseDataFromFile(filename)
				if houseData then
					setAutoPasteSource("filequeue")
					for copyIndex = 1, autoPasteQueueCopies do
						local displayName = filename
						if autoPasteQueueCopies > 1 then
							displayName = filename .. " #" .. copyIndex
						end
						table.insert(fileQueue, { filename = displayName, sourceName = filename, houseData = houseData })
						added += 1
					end
					Rayfield:Notify({
						Title = "File Queue",
						Content = "Added " .. autoPasteQueueCopies .. "x " .. filename .. " [" .. getFileHouseType(houseData) .. "]",
						Duration = 2,
					})
				else
					Rayfield:Notify({ Title = "File Queue", Content = tostring(err), Duration = 4 })
				end
			end

			rebuildQueueLabel()
			setAPFileInfo()
			if added > 0 then
				Rayfield:Notify({ Title = "File Queue", Content = added .. " file(s) added", Duration = 3 })
			end
		end,
	})

	fqQueueListLabel = AutoPasteTab:CreateLabel("Queue: (empty)", "list")

	AutoPasteTab:CreateInput({
		Name = "Pastebin Link / ID",
		PlaceholderText = "https://pastebin.com/xxxxxx or xxxxxx",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			autoPastePastebinValue = tostring(value or "")
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Add Pastebin to Queue",
		Callback = function()
			local houseData, pasteIdOrErr = loadHouseDataFromPastebin(autoPastePastebinValue)
			if not houseData then
				return Rayfield:Notify({
					Title = "Pastebin Queue",
					Content = tostring(pasteIdOrErr),
					Duration = 4,
				})
			end

			local pasteId = tostring(pasteIdOrErr)
			local baseName = "Pastebin_" .. pasteId
			setAutoPasteSource("filequeue")
			for copyIndex = 1, autoPasteQueueCopies do
				local displayName = baseName
				if autoPasteQueueCopies > 1 then
					displayName = baseName .. " #" .. copyIndex
				end
				table.insert(fileQueue, {
					filename = displayName,
					sourceName = baseName,
					houseData = houseData,
				})
			end
			rebuildQueueLabel()
			setAPFileInfo()

			Rayfield:Notify({
				Title = "Pastebin Queue",
				Content = "Added " .. autoPasteQueueCopies .. "x " .. baseName .. " [" .. getFileHouseType(houseData) .. "]",
				Duration = 3,
			})
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Remove First Queue Item",
		Callback = function()
			if #fileQueue == 0 then
				return Rayfield:Notify({ Title = "File Queue", Content = "Queue is empty", Duration = 2 })
			end
			local removed = table.remove(fileQueue, 1)
			rebuildQueueLabel()
			setAPFileInfo()
			Rayfield:Notify({ Title = "File Queue", Content = "Removed " .. removed.filename, Duration = 2 })
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Clear File Queue",
		Callback = function()
			autoPasteRunning = false
			stopFlag = true
			table.clear(fileQueue)
			rebuildQueueLabel()
			setAPFileInfo()
			if autoPasteStatus then
				pcall(function() autoPasteStatus:Set("Status: Idle") end)
			end
			if autoPasteProgress then
				pcall(function() autoPasteProgress:Set("Progress: -") end)
			end
			Rayfield:Notify({ Title = "File Queue", Content = "Queue cleared", Duration = 2 })
		end,
	})

	AutoPasteTab:CreateSection("Target Houses")

	autoPasteDropdown = AutoPasteTab:CreateDropdown({
		Name = "Select Houses to Paste Into",
		Options = {},
		CurrentOption = {},
		MultipleOptions = true,
		Callback = function(opts)
			table.clear(autoPasteSelections)
			for _, name in ipairs(opts or {}) do
				local id = ownedHouseMap[name]
				if id then
					autoPasteSelections[id] = name
				end
			end
			local count = 0
			for _ in pairs(autoPasteSelections) do count += 1 end
			Rayfield:Notify({
				Title = "Auto Paste",
				Content = count .. " house(s) selected",
				Duration = 2,
			})
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Refresh House List",
		Callback = function()
			refreshOwnedHouses()
			table.clear(autoPasteSelections)
			Rayfield:Notify({
				Title = "Auto Paste",
				Content = "House list refreshed (" .. #ownedHouseList .. " houses)\nPlease re-select your targets.",
				Duration = 4,
			})
		end,
	})

	AutoPasteTab:CreateSection("Paste Mode")

	AutoPasteTab:CreateDropdown({
		Name = "Paste Mode",
		Options = { "Fast", "Slow" },
		CurrentOption = { "Fast" },
		MultipleOptions = false,
		Callback = function(opt)
			local v = (typeof(opt) == "table") and opt[1] or opt
			autoPasteMode = v == "Slow" and "slow" or "fast"
		end,
	})

	AutoPasteTab:CreateSection("Controls")

	local autoPasteStatus = AutoPasteTab:CreateLabel("Status: Idle", "activity")
	local autoPasteProgress = AutoPasteTab:CreateLabel("Progress: -", "trending-up")
	autoPasteFileInfo = AutoPasteTab:CreateLabel("File Queue: 0 file(s)", "list")

	local function setAPStatus(s) pcall(function() autoPasteStatus:Set("Status: " .. s) end) end
	local function setAPProg(s)   pcall(function() autoPasteProgress:Set("Progress: " .. s) end) end

	local function waitUntilInsideHouse(targetId, timeout)
		timeout = timeout or 30
		local start = tick()
		while tick() - start < timeout do
			local ok, interior = pcall(function() return cd.get("house_interior") end)
			if ok and interior then
				if interior.house_id == targetId then
					return true
				end
				local houseOk, manager = pcall(function() return ClientData.get("house_manager") end)
				if houseOk and manager then
					for _, house in pairs(manager) do
						if house.house_id == targetId and interior.player == Players.LocalPlayer then
							return true
						end
					end
				end
			end
			task.wait(1)
		end
		return false
	end

	local function teleportToHouse(houseId)
		pcall(function()
			local load = require(game:GetService("ReplicatedStorage").Fsys).load
			local interiors = load("InteriorsM")
			local ownerPlayer = nil
			for _, house in pairs(ClientData.get("house_manager") or {}) do
				if house.house_id == houseId then
					ownerPlayer = Players.LocalPlayer
					break
				end
			end
			if ownerPlayer then
				interiors.enter("housing", "MainDoor", { house_owner = ownerPlayer })
			else
				interiors.enter("housing", "MainDoor", { house_id = houseId })
			end
		end)
	end

	local function exitCurrentHouse()
		pcall(function()
			local load = require(game:GetService("ReplicatedStorage").Fsys).load
			local RouterClient = load("RouterClient")
			local ClientData = load("ClientData")
			local interior = ClientData.get("house_interior")

			if interior then
				RouterClient
					.get("HousingAPI/UnsubscribeFromHouse")
					:InvokeServer(interior.house_owner or Players.LocalPlayer, true)
			end
		end)
	end

	local function clearCurrentHouseFurniture()
		local ok, interior = pcall(function() return cd.get("house_interior") end)
		if ok and interior and interior.furniture then
			local ids = {}
			for fi, _ in pairs(interior.furniture) do
				table.insert(ids, fi)
			end
			if #ids > 0 then
				pcall(function()
					router.get("HousingAPI/SellFurniture"):FireServer(false, ids, "sell")
				end)
				task.wait(4)
			end
		end

		local clearTimeout = tick()
		repeat
			task.wait(1)
			local cok, cint = pcall(function() return cd.get("house_interior") end)
			if cok and cint then
				local remaining = 0
				for _ in pairs(cint.furniture or {}) do remaining += 1 end
				if remaining == 0 then break end
			end
		until tick() - clearTimeout > 10
	end

	local function getCurrentHouseType()
		local ok, interior = pcall(function() return cd.get("house_interior") end)
		if not ok or not interior then
			return nil
		end

		return getInteriorExactType(interior)
	end

	local function pasteIntoHouse(houseId, houseName, houseData, mode, expectedType)
		savedhouse = houseData

		pcall(function()
			router.get("HousingAPI/SpawnHouse"):FireServer(houseId)
		end)
		task.wait(2)

		Rayfield:Notify({ Title = "Auto Paste", Content = "Entering: " .. houseName, Duration = 3 })
		teleportToHouse(houseId)
		task.wait(4)

		local inside = waitUntilInsideHouse(houseId, 20)
		if not inside then
			Rayfield:Notify({ Title = "Auto Paste", Content = "Couldn't enter " .. houseName .. ", skipping", Duration = 4 })
			return false
		end

		local actualType = getCurrentHouseType()
		if actualType then
			ownedHouseTypeMap[houseId] = actualType
		end

		if expectedType and not actualType then
			Rayfield:Notify({
				Title = "Auto Paste",
				Content = "Could not verify house type for " .. houseName .. ", skipped",
				Duration = 5,
			})
			exitCurrentHouse()
			task.wait(2)
			return "type_mismatch"
		end

		if expectedType and not isExactSameHouseType(expectedType, actualType) then
			Rayfield:Notify({
				Title = "Auto Paste",
				Content = "House types do not match!\nSaved: "
					.. tostring(getExactHouseDisplayName(expectedType))
					.. "\nCurrent: "
					.. tostring(getExactHouseDisplayName(actualType))
					.. "\nSkipped: "
					.. houseName,
				Duration = 6,
			})
			exitCurrentHouse()
			task.wait(2)
			return "type_mismatch"
		end

		clearCurrentHouseFurniture()
		if stopFlag or not autoPasteRunning then return false end

		if mode == "slow" then
			pastehouseslow()
		else
			pastehousefast()
		end

		task.wait(5)
		if stopFlag or not autoPasteRunning then return false end

		exitCurrentHouse()
		task.wait(3)
		return true
	end

	AutoPasteTab:CreateButton({
		Name = "Start Auto Paste Queue",
		Callback = function()
			if autoPasteRunning then
				return Rayfield:Notify({ Title = "Auto Paste", Content = "Already running!", Duration = 3 })
			end

			if type(pastehousefast) ~= "function" or type(pastehouseslow) ~= "function" then
				return Rayfield:Notify({
					Title = "Auto Paste",
					Content = "Script not fully loaded yet.\nPlease wait a moment and try again.",
					Duration = 5,
				})
			end

			if autoPasteSource == "loaded" and not savedhouse then
				return Rayfield:Notify({
					Title = "Auto Paste",
					Content = "No house loaded.\nPlease scan or load a house first.",
					Duration = 4,
				})
			end

			if autoPasteSource == "filequeue" and #fileQueue == 0 then
				return Rayfield:Notify({
					Title = "Auto Paste",
					Content = "File Queue is empty.\nAdd files first.",
					Duration = 4,
				})
			end

			local candidateIds = {}
			for id, _ in pairs(autoPasteSelections) do
				table.insert(candidateIds, id)
			end

			if #candidateIds == 0 then
				return Rayfield:Notify({
					Title = "Auto Paste",
					Content = "No houses selected.\nUse Refresh then select houses from dropdown.",
					Duration = 5,
				})
			end

			autoPasteRunning = true
			stopFlag = false

			task.spawn(function()
				setAPStatus("Running")

				if autoPasteSource == "loaded" then
					local total = #candidateIds
					for i, houseId in ipairs(candidateIds) do
						if stopFlag or not autoPasteRunning then break end
						local houseName = autoPasteSelections[houseId] or tostring(houseId)
						local expectedType = nil
						if not (IgnoreTypeCheck and IgnoreTypeCheck.CurrentValue) then
							expectedType = getSavedHouseExactType(savedhouse)
						end
						setAPProg(i .. "/" .. total .. " - " .. houseName)
						if pasteIntoHouse(houseId, houseName, savedhouse, autoPasteMode, expectedType) == true then
							Rayfield:Notify({ Title = "Auto Paste", Content = houseName .. " done", Duration = 2 })
						end
						task.wait(1)
					end
				elseif autoPasteSource == "filequeue" then
					local usedHouseIds = {}

					if autoPasteSingleFile then
						local fileEntry = fileQueue[1]
						if fileEntry then
							local fileType = getFileHouseType(fileEntry.houseData)
							local matchingHouses = {}

							for _, houseId in ipairs(candidateIds) do
								local ownedType = ownedHouseTypeMap[houseId]
								if (ownedType and isExactSameHouseType(fileType, ownedType))
									or not ownedType
									or ownedType == "unknown"
									or ownedType == "Unknown"
								then
									table.insert(matchingHouses, houseId)
								end
							end

							if #matchingHouses == 0 then
								Rayfield:Notify({
									Title = "Auto Paste",
									Content = "No matching houses for " .. fileEntry.filename .. " [" .. fileType .. "]",
									Duration = 5,
								})
							else
								for i, houseId in ipairs(matchingHouses) do
									if stopFlag or not autoPasteRunning then break end
									local houseName = autoPasteSelections[houseId] or tostring(houseId)
									setAPProg(i .. "/" .. #matchingHouses .. " - " .. fileEntry.filename .. " -> " .. houseName)
									if pasteIntoHouse(houseId, houseName, fileEntry.houseData, autoPasteMode, fileType) == true then
										Rayfield:Notify({ Title = "Auto Paste", Content = houseName .. " done", Duration = 2 })
									end
									task.wait(1)
								end
							end

							table.remove(fileQueue, 1)
							rebuildQueueLabel()
							setAPFileInfo()
						end
					else
						local totalFiles = #fileQueue
						local fileIndex = 1

						while fileIndex <= #fileQueue and autoPasteRunning and not stopFlag do
							local fileEntry = fileQueue[fileIndex]
							local fileType = getFileHouseType(fileEntry.houseData)
							local matchedId = findMatchingHouse(fileType, candidateIds, usedHouseIds)

							if not matchedId then
								Rayfield:Notify({
									Title = "Auto Paste",
									Content = "No matching house for " .. fileEntry.filename .. " [" .. fileType .. "], skipping",
									Duration = 5,
								})
								fileIndex += 1
								continue
							end

							local houseName = autoPasteSelections[matchedId] or tostring(matchedId)
							setAPProg(fileIndex .. "/" .. totalFiles .. " - " .. fileEntry.filename .. " -> " .. houseName)

							local pasteResult = pasteIntoHouse(matchedId, houseName, fileEntry.houseData, autoPasteMode, fileType)
							if pasteResult == true then
								usedHouseIds[matchedId] = true
								table.remove(fileQueue, fileIndex)
								rebuildQueueLabel()
								setAPFileInfo()
								Rayfield:Notify({
									Title = "Auto Paste",
									Content = fileEntry.filename .. " -> " .. houseName .. " done",
									Duration = 3,
								})
							elseif pasteResult == "type_mismatch" then
								usedHouseIds[matchedId] = true
							else
								fileIndex += 1
							end

							task.wait(1)
						end
					end
				end

				autoPasteRunning = false
				setAPStatus("Idle")
				setAPProg("-")
				Rayfield:Notify({ Title = "Auto Paste", Content = "Auto paste finished", Duration = 5 })
			end)
		end,
	})

	AutoPasteTab:CreateButton({
		Name = "Stop",
		Callback = function()
			autoPasteRunning = false
			stopFlag = true
			setAPStatus("Stopped")
			setAPProg("-")
			Rayfield:Notify({ Title = "Auto Paste", Content = "Stopped", Duration = 3 })
		end,
	})

	refreshFQFileList()

	-- ==================== HOUSE BUYER TAB ====================
	local selectedHouseKinds = {}
	local selectedHouseId = nil
	local autoBuy = false
	local buyAmount = 1

	local houseList = {}
	local houseMap = {}

	for _, data in pairs(HouseDB) do
		if data.is_for_sale then
			table.insert(houseList, data.name)
			houseMap[data.name] = data.kind
		end
	end

	table.sort(houseList)

	BuyerTab:CreateDropdown({
		Name = "Select House To Buy",
		Options = houseList,
		MultipleOptions = true,
		Callback = function(opt)
			table.clear(selectedHouseKinds)
			if typeof(opt) == "table" then
				for _, v in ipairs(opt) do
					if houseMap[v] then
						table.insert(selectedHouseKinds, houseMap[v])
					end
				end
			else
				if houseMap[opt] then
					table.insert(selectedHouseKinds, houseMap[opt])
				end
			end
		end,
	})

	BuyerTab:CreateInput({
		Name = "Amount of Houses to Buy",
		PlaceholderText = "Enter number...",
		RemoveTextAfterFocusLost = false,
		Callback = function(t)
			local n = tonumber(t)
			if n and n > 0 then
				buyAmount = math.floor(n)
				Rayfield:Notify({ Title = "Auto Buy", Content = "Set to " .. n, Duration = 3 })
			end
		end,
	})

	local function autoRenameNewHouse(before)
		local current = ClientData.get("house_manager") or {}
		local map = {}
		for _, h in pairs(current) do
			map[h.house_id] = h
		end
		for id, house in pairs(map) do
			if not before[id] then
				local max = 0
				for _, h in pairs(map) do
					local num = tonumber(string.match(h.name or "", "Kalirem (%d+)")) or 0
					if num > max then max = num end
				end
				local newName = "Kalirem " .. (max + 1)
				pcall(function()
					Router.get("HousingAPI/RenameHouse"):FireServer(id, newName)
				end)
				Rayfield:Notify({ Title = "Rename", Content = newName, Duration = 2 })
			end
		end
	end

	local function buyHouse()
		if #selectedHouseKinds == 0 then
			Rayfield:Notify({ Title = "Auto Buy", Content = "No house selected ❌", Duration = 3 })
			return false
		end
		for _, kind in ipairs(selectedHouseKinds) do
			local before = {}
			for _, h in pairs(ClientData.get("house_manager") or {}) do
				before[h.house_id] = true
			end
			local success = pcall(function()
				Router.get("HousingAPI/BuyHouseWithAddons")
					:InvokeServer(kind, {}, Color3.fromRGB(255, 182, 193))
			end)
			if success then
				Rayfield:Notify({ Title = "Auto Buy", Content = "Buying " .. tostring(kind) .. " 🏠", Duration = 2 })
				task.wait(1)
				autoRenameNewHouse(before)
			else
				Rayfield:Notify({ Title = "Auto Buy", Content = "Failed " .. tostring(kind) .. " ❌", Duration = 2 })
			end
			task.wait(0.5)
		end
		refreshOwnedHouses()
		return true
	end

	ownedDropdown = BuyerTab:CreateDropdown({
		Name = "Select Owned House to Sell",
		Options = ownedHouseList,
		CurrentOption = {},
		MultipleOptions = false,
		Callback = function(opt)
			local name = (typeof(opt) == "table") and opt[1] or opt
			selectedHouseId = ownedHouseMap[name] or nil
		end,
	})

	BuyerTab:CreateButton({
		Name = "Sell Selected House",
		Callback = function()
			if not selectedHouseId then
				Rayfield:Notify({ Title = "Sell", Content = "No house selected ❌", Duration = 3 })
				return
			end
			pcall(function()
				Router.get("HousingAPI/SellHouse"):InvokeServer(selectedHouseId)
			end)
			Rayfield:Notify({ Title = "Sell", Content = "House sold ✔", Duration = 3 })
			task.wait(1)
			refreshOwnedHouses()
		end,
	})

	BuyerTab:CreateButton({
		Name = "Buy Selected House (One-Time)",
		Callback = function()
			buyHouse()
		end,
	})

	BuyerTab:CreateToggle({
		Name = "Auto Buy",
		Callback = function(v)
			autoBuy = v
			if v then
				task.spawn(function()
					local c = 0
					while autoBuy and c < buyAmount do
						if buyHouse() then c += 1 end
						task.wait(0.5)
					end
					autoBuy = false
				end)
			end
		end,
	})

	-- ==================== TRADING TAB ====================
	local tradingRunning = false
	local tradeSelections = {}
	local lastTradeCount = -1

	tradeDropdown = TradeTab:CreateDropdown({
		Name = "Select Houses To Trade",
		Options = ownedHouseList,
		CurrentOption = {},
		MultipleOptions = true,
		Callback = function(opts)
			table.clear(tradeSelections)
			for _, name in ipairs(opts or {}) do
				local id = ownedHouseMap[name]
				if id then tradeSelections[id] = name end
			end
			local selectedCount = 0
			for _ in pairs(tradeSelections) do selectedCount += 1 end
			if selectedCount ~= lastTradeCount then
				lastTradeCount = selectedCount
				Rayfield:Notify({ Title = "Trading", Content = selectedCount .. " houses selected" })
			end
		end,
	})

	local function waitUntilHouseGone(id, timeout)
		timeout = timeout or 300
		local start = tick()
		while tick() - start < timeout do
			local found = false
			for _, h in pairs(ClientData.get("house_manager") or {}) do
				if h.house_id == id then
					found = true
					break
				end
			end
			if not found then return true end
			task.wait(1)
		end
		return false
	end

	local function processTrade()
		if tradingRunning then return end
		tradingRunning = true
		Rayfield:Notify({ Title = "Trading", Content = "Started dynamic queue", Duration = 3 })
		task.spawn(function()
			while tradingRunning do
				refreshOwnedHouses()
				local currentQueue = {}
				for id, _ in pairs(tradeSelections) do
					table.insert(currentQueue, id)
				end
				if #currentQueue == 0 then
					Rayfield:Notify({ Title = "Trading", Content = "Queue finished ✅", Duration = 3 })
					break
				end
				local id = currentQueue[1]
				local name = tradeSelections[id]
				Rayfield:Notify({ Title = "Trading", Content = "Processing " .. name })
				pcall(function() Router.get("HousingAPI/SpawnHouse"):FireServer(id) end)
				task.wait(2)
				pcall(function() Router.get("HousingAPI/ListHouse"):InvokeServer(id) end)
				if waitUntilHouseGone(id) then
					Rayfield:Notify({ Title = "Trading", Content = name .. " traded ✔", Duration = 3 })
					tradeSelections[id] = nil
				else
					Rayfield:Notify({ Title = "Trading", Content = name .. " timeout ❌", Duration = 3 })
				end
				task.wait(1)
			end
			tradingRunning = false
		end)
	end

	TradeTab:CreateButton({ Name = "Start Trading Queue", Callback = processTrade })

	TradeTab:CreateButton({
		Name = "Clear Queue",
		Callback = function()
			tradingRunning = false
			table.clear(tradeSelections)
			lastTradeCount = 0
			pcall(function()
				if tradeDropdown then tradeDropdown:Set({}) end
			end)
			Rayfield:Notify({ Title = "Trading", Content = "Queue cleared & stopped 🛑" })
		end,
	})

	-- ==================== HELPER FUNCTIONS ====================
	local function countfurnitures(t)
		local c = 0
		for _ in pairs(t or {}) do c += 1 end
		return c
	end

	local function counttextures(textures)
		local c = 0
		for _, v in pairs(textures or {}) do
			if v.walls then c += 1 end
			if v.floors then c += 1 end
		end
		return c
	end

	local function getCurrentInteriorModel()
		for _, v in pairs(workspace:GetChildren()) do
			if v.Name:lower():find("interior") and v:IsA("Model") and v.PrimaryPart then
				return v
			end
		end
		return nil
	end

	local function toRelativeCFrame(worldCf)
		local interior = getCurrentInteriorModel()
		if interior and interior.PrimaryPart then
			return interior.PrimaryPart.CFrame:ToObjectSpace(worldCf)
		end
		return worldCf
	end

	local function toWorldCFrame(relativeCf)
		local interior = getCurrentInteriorModel()
		if interior and interior.PrimaryPart then
			return interior.PrimaryPart.CFrame:ToWorldSpace(relativeCf)
		end
		return relativeCf
	end

	local function deepCopy(tbl)
		if type(tbl) ~= "table" then return tbl end
		local t = {}
		for k, v in pairs(tbl) do t[k] = deepCopy(v) end
		return t
	end

	-- ==================== MAIN TAB ====================
	Tab:CreateLabel(
		"If you are using glitch houses, use the slow paste. And if you are using normal houses, use the fast paste. If you use it on higher builds expect lagging or crashing.",
		"info"
	)
	Tab:CreateLabel("Do not Touch", "info")

	local Pastetextures = Tab:CreateToggle({
		Name = "Paste textures",
		CurrentValue = true,
		Flag = "Pastetextures",
		Callback = function(_) end,
	})
	IgnoreTypeCheck = Tab:CreateToggle({
		Name = "Ignore House Type",
		CurrentValue = false,
		Flag = "IgnoreType",
		Callback = function(_) end,
	})

	Tab:CreateSection("Slow Paste Settings")
	local batch_size = 10
	local delay_seconds = 1

	Tab:CreateInput({
		Name = "Batch Size (items per batch)",
		PlaceholderText = "10",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			batch_size = tonumber(value) or 10
		end,
	})

	Tab:CreateInput({
		Name = "Delay (seconds between batches)",
		PlaceholderText = "1",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			delay_seconds = tonumber(value) or 1
		end,
	})

	Tab:CreateSection("Main Function")

	-- Furniture/texture helpers
	local function canbuyfurniture(kind)
		local db_entry = furnituresdb[kind]
		if not db_entry or not db_entry.cost or db_entry.off_sale then
			return false, false
		end
		local success, player_data = pcall(function()
			return cd.get_data()[plr.Name]
		end)
		if not success or not player_data then
			return false, false
		end
		return db_entry.cost < (player_data.money or 0), true
	end

	local function textureexists(room, texturetype, texture)
		if texture == "tile" then return true end
		local success, textures = pcall(function()
			return cd.get("house_interior").textures
		end)
		if not success or not textures then return false end
		for i, v in pairs(textures) do
			if i == room and v[texturetype] == texture then return true end
		end
		return false
	end

	local function buytexturewithretry(room, texturetype, texture, tries)
		tries = tries or 0
		if tries > 10 then warn("Failed to buy texture:", texture) return end
		if stopFlag then return end
		pcall(function()
			router.get("HousingAPI/BuyTexture"):FireServer(room, texturetype, texture)
		end)
		task.wait(0.1)
		if not textureexists(room, texturetype, texture) then
			buytexturewithretry(room, texturetype, texture, tries + 1)
		end
	end

	local max_retries = 3

	local function placeFurnitures(furnList, isFix)
		local totalfurnitures = #furnList
		if totalfurnitures == 0 then return end
		updateprog("0/" .. totalfurnitures)

		local batches = {}
		local current_batch = {}
		for _, item in ipairs(furnList) do
			table.insert(current_batch, item)
			if #current_batch == batch_size then
				table.insert(batches, current_batch)
				current_batch = {}
			end
		end
		if #current_batch > 0 then
			table.insert(batches, current_batch)
		end

		local placed = 0
		updatestatus(isFix and "Fixing Missing Items" or "Pasting Furniture (Slow)")

		for batch_idx, batch in ipairs(batches) do
			if stopFlag then
				updatestatus("Stopped")
				break
			end

			for _, item in ipairs(batch) do
				if stopFlag then break end
				updateitem((isFix and "Fixing: " or "Placing: ") .. (item.kind or "Unknown"))
				task.wait(0.03)
			end

			local retries = 0
			local success = false
			while retries < max_retries do
				if stopFlag then
					updatestatus("Stopped")
					break
				end
				local before_count_success, before_count = pcall(function()
					return countfurnitures(cd.get("house_interior").furniture)
				end)
				if not before_count_success then
					retries += 1
					task.wait(1)
					continue
				end
				for _, batchItem in ipairs(batch) do
					local normalized = {}
					for ci, col in pairs(batchItem.properties.colors or {}) do
						if typeof(col) == "Color3" then
							normalized[ci] = col
						elseif type(col) == "table" then
							normalized[ci] = Color3.new(
								col[1] or col.R or col.r or 1,
								col[2] or col.G or col.g or 1,
								col[3] or col.B or col.b or 1
							)
						end
					end
					batchItem.properties.colors = normalized
				end
				local invoke_success = pcall(function()
					router.get("HousingAPI/BuyFurnitures"):InvokeServer(batch)
				end)
				if not invoke_success then
					retries += 1
					task.wait(1)
					continue
				end
				task.wait(delay_seconds)
				local after_count_success, after_count = pcall(function()
					return countfurnitures(cd.get("house_interior").furniture)
				end)
				if not after_count_success then
					retries += 1
					task.wait(1)
					continue
				end
				if after_count - before_count >= #batch then
					success = true
					break
				end
				retries += 1
				task.wait(1)
			end

			if success then
				placed += #batch
			else
				Rayfield:Notify({
					Title = "Warning",
					Content = "Batch " .. batch_idx .. " failed after " .. max_retries .. " retries.",
					Duration = 5,
					Image = "circle-alert",
				})
			end
			updateprog(placed .. "/" .. totalfurnitures)
		end
	end

	Tab:CreateButton({
		Name = "Scan house",
		Callback = function()
			local success, house = pcall(function()
				return cd.get("house_interior")
			end)
			if not success or not house or house.player == nil then
				Rayfield:Notify({
					Title = "Error",
					Content = "You need to enter a house to copy",
					Duration = 3,
					Image = "circle-alert",
				})
				return
			end
			updatestatus("Scanning")
			savedhouse = deepCopy(house)
			if savedhouse.furniture then
				for _, v in pairs(savedhouse.furniture) do
					if v.creator then v.creator = nil end
				end
			end
			local furniturecost = 0
			for _, v in pairs(savedhouse.furniture or {}) do
				local db_entry = furnituresdb[v.id]
				if db_entry and db_entry.cost then furniturecost += db_entry.cost end
			end
			local texturecost = 0
			for _, v in pairs(savedhouse.textures or {}) do
				if v.walls and texturesdb.walls[v.walls] and texturesdb.walls[v.walls].cost then
					texturecost += texturesdb.walls[v.walls].cost
				end
				if v.floors and texturesdb.floors[v.floors] and texturesdb.floors[v.floors].cost then
					texturecost += texturesdb.floors[v.floors].cost
				end
			end
			local t_count = counttextures(savedhouse.textures)
			local amb = savedhouse.ambiance and "Yes" or "No"
			local typ = "-"
			pcall(function() typ = savedhouse.building_type or "-" end)
			task.spawn(setscaninfo, countfurnitures(savedhouse.furniture), furniturecost, t_count, texturecost, amb, typ)
			Rayfield:Notify({ Title = "Success", Content = "Scanned house", Duration = 3, Image = "circle-check" })
			updatestatus("Idle")
		end,
	})

	Tab:CreateButton({
		Name = "Sell All Furnitures",
		Callback = function()
			updatestatus("Clearing House")
			local success, furniture = pcall(function()
				return cd.get("house_interior").furniture
			end)
			if not success or not furniture then
				Rayfield:Notify({ Title = "Error", Content = "Failed to access house furniture", Duration = 3, Image = "circle-alert" })
				updatestatus("Idle")
				return
			end
			local t = {}
			for i, _ in pairs(furniture) do table.insert(t, i) end
			pcall(function()
				router.get("HousingAPI/SellFurniture"):FireServer(false, t, "sell")
			end)
			Rayfield:Notify({ Title = "Success", Content = "House cleared successfully!", Duration = 3, Image = "circle-check" })
			updatestatus("Idle")
		end,
	})

	Tab:CreateSection("Paste Functions")

	-- ==================== PASTE FAST (assigned to upvalue) ====================
	pastehousefast = function()
		if not savedhouse or not savedhouse.furniture then
			return Rayfield:Notify({ Title = "Error", Content = "No house has been saved", Duration = 3, Image = "circle-alert" })
		end
		Rayfield:Notify({ Title = "Loading", Content = "Pasting furnitures...", Duration = 3, Image = "loader" })
		updatestatus("Pasting Furniture")

		local validFurniture = {}
		local totalfurnitures = 0
		for i, v in pairs(savedhouse.furniture) do
			if v.id == "lures_2023_cozy_home_lure" then
				warn("[SKIP] Skipping lure item:", v.id)
				continue
			end
			if type(v.cframe) == "table" then
				local ok, cf = pcall(function() return CFrame.new(table.unpack(v.cframe)) end)
				if ok and cf then v.cframe = cf
				else warn("[SKIP] Could not convert cframe for:", v.id) continue end
			end
			if typeof(v.cframe) == "CFrame" then
				validFurniture[i] = v
				totalfurnitures += 1
			else
				warn("[SKIP] Missing or invalid cframe for:", v.id)
			end
		end

		updateprog("0/" .. totalfurnitures)
		updateitem("-")

		local processedCount = 0
		local furniturest = {}

		for i, v in pairs(validFurniture) do
			if stopFlag then break end
			local canbuy, exists = canbuyfurniture(v.id)
			if not canbuy and exists == true then
				updatestatus("Idle") updateprog("-") updateitem("-")
				return Rayfield:Notify({ Title = "Error", Content = "Insufficient funds for furniture: " .. v.id, Duration = 3, Image = "circle-alert" })
			elseif not canbuy and exists == false then
				processedCount += 1
				updateprog(processedCount .. "/" .. totalfurnitures)
				continue
			end
			local normalizedColors = {}
			for ci, col in pairs(v.colors or {}) do
				if typeof(col) == "Color3" then
					normalizedColors[ci] = col
				elseif type(col) == "table" then
					normalizedColors[ci] = Color3.new(
						col[1] or col.R or col.r or 1,
						col[2] or col.G or col.g or 1,
						col[3] or col.B or col.b or 1
					)
				end
			end
			table.insert(furniturest, {
				kind = v.id,
				properties = {
					colors = normalizedColors,
					cframe = v.cframe,
					scale = v.scale,
				},
			})
			processedCount += 1
			updateprog(processedCount .. "/" .. totalfurnitures)
			updateitem(v.id)
		end

		if stopFlag then
			updatestatus("Stopped") updateprog("-") updateitem("-")
			return
		end

		if #furniturest > 0 then
			pcall(function()
				router.get("HousingAPI/BuyFurnitures"):InvokeServer(furniturest)
			end)
		end

		-- Activate furniture
		local success, interior = pcall(function() return cd.get("house_interior") end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then break end
				if v.text then
					pcall(function()
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				elseif v.outfit_name then
					pcall(function()
						router.get("AvatarAPI/StartEditingMannequin"):InvokeServer(v.outfit)
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", { save_outfit = true, outfit_name = "Outfit" }, plr.Character)
					end)
				end
			end
		end

		-- Apply textures
		if savedhouse.textures and Pastetextures.CurrentValue then
			updatestatus("Pasting Textures")
			updateprog("-")
			for roomId, textureData in pairs(savedhouse.textures) do
				if stopFlag then break end
				if textureData.floors and not textureexists(roomId, "floors", textureData.floors) then
					updateitem(roomId .. " floors: " .. textureData.floors)
					buytexturewithretry(roomId, "floors", textureData.floors)
				end
				if stopFlag then break end
				if textureData.walls and not textureexists(roomId, "walls", textureData.walls) then
					updateitem(roomId .. " walls: " .. textureData.walls)
					buytexturewithretry(roomId, "walls", textureData.walls)
				end
				task.wait()
			end
		end

		if savedhouse.ambiance then
			pcall(function() router.get("AmbianceAPI/UpdateAmbiance"):FireServer(savedhouse.ambiance) end)
		end
		if savedhouse.music then
			pcall(function()
				router.get("RadioAPI/Play"):FireServer(savedhouse.music.name, savedhouse.music.id)
				if not savedhouse.music.playing then
					router.get("RadioAPI/Pause"):InvokeServer()
				end
			end)
		end

		Rayfield:Notify({ Title = "Success", Content = "House Placed successfully!", Duration = 3, Image = "circle-check" })
		updatestatus("Idle")
		updateprog("-")
		updateitem("-")
	end

	-- ==================== PASTE SLOW (assigned to upvalue) ====================
	pastehouseslow = function()
		if not savedhouse or not savedhouse.furniture then
			return Rayfield:Notify({ Title = "Error", Content = "No house has been saved", Duration = 3, Image = "circle-alert" })
		end
		Rayfield:Notify({ Title = "Loading", Content = "Pasting furnitures slowly...", Duration = 3, Image = "loader" })
		updatestatus("Pasting Furniture (Slow)")

		local validFurniture = {}
		local totalfurnitures = 0
		for i, v in pairs(savedhouse.furniture) do
			if v.id == "lures_2023_cozy_home_lure" then
				warn("[SKIP] Skipping lure item:", v.id)
				continue
			end
			if type(v.cframe) == "table" then
				local ok, cf = pcall(function() return CFrame.new(table.unpack(v.cframe)) end)
				if ok and cf then v.cframe = cf
				else warn("[SKIP] Could not convert cframe for:", v.id) continue end
			end
			if typeof(v.cframe) == "CFrame" then
				validFurniture[i] = v
				totalfurnitures += 1
			else
				warn("[SKIP] Missing or invalid cframe for:", v.id)
			end
		end

		updateprog("0/" .. totalfurnitures)
		updateitem("-")

		local processedCount = 0
		local furniturest = {}

		for i, v in pairs(validFurniture) do
			if stopFlag then break end
			local canbuy, exists = canbuyfurniture(v.id)
			if not canbuy and exists == true then
				updatestatus("Idle") updateprog("-") updateitem("-")
				return Rayfield:Notify({ Title = "Error", Content = "Insufficient funds for furniture: " .. v.id, Duration = 3, Image = "circle-alert" })
			elseif not canbuy and exists == false then
				processedCount += 1
				updateprog(processedCount .. "/" .. totalfurnitures)
				continue
			end
			local normalizedColors = {}
			for ci, col in pairs(v.colors or {}) do
				if typeof(col) == "Color3" then
					normalizedColors[ci] = col
				elseif type(col) == "table" then
					normalizedColors[ci] = Color3.new(
						col[1] or col.R or col.r or 1,
						col[2] or col.G or col.g or 1,
						col[3] or col.B or col.b or 1
					)
				end
			end
			table.insert(furniturest, {
				kind = v.id,
				properties = {
					colors = normalizedColors,
					cframe = v.cframe,
					scale = v.scale,
				},
			})
			processedCount += 1
			updateprog(processedCount .. "/" .. totalfurnitures)
			updateitem(v.id)
		end

		if stopFlag then
			updatestatus("Stopped") updateprog("-") updateitem("-")
			return
		end

		if #furniturest > 0 then
			placeFurnitures(furniturest, false)
		end

		if stopFlag then
			updatestatus("Stopped") updateprog("-") updateitem("-")
			return
		end

		-- Activate furniture
		local success, interior = pcall(function() return cd.get("house_interior") end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then break end
				if v.text then
					pcall(function()
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				elseif v.outfit_name then
					pcall(function()
						router.get("AvatarAPI/StartEditingMannequin"):InvokeServer(v.outfit)
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", { save_outfit = true, outfit_name = "Outfit" }, plr.Character)
					end)
				end
			end
		end

		-- Apply textures
		if savedhouse.textures and Pastetextures.CurrentValue then
			updatestatus("Pasting Textures")
			updateprog("-")
			for roomId, textureData in pairs(savedhouse.textures) do
				if stopFlag then break end
				if textureData.floors and not textureexists(roomId, "floors", textureData.floors) then
					updateitem(roomId .. " floors: " .. textureData.floors)
					buytexturewithretry(roomId, "floors", textureData.floors)
				end
				if stopFlag then break end
				if textureData.walls and not textureexists(roomId, "walls", textureData.walls) then
					updateitem(roomId .. " walls: " .. textureData.walls)
					buytexturewithretry(roomId, "walls", textureData.walls)
				end
				task.wait()
			end
		end

		if savedhouse.ambiance then
			pcall(function() router.get("AmbianceAPI/UpdateAmbiance"):FireServer(savedhouse.ambiance) end)
		end
		if savedhouse.music then
			pcall(function()
				router.get("RadioAPI/Play"):FireServer(savedhouse.music.name, savedhouse.music.id)
				if not savedhouse.music.playing then
					router.get("RadioAPI/Pause"):InvokeServer()
				end
			end)
		end

		Rayfield:Notify({ Title = "Success", Content = "House Placed successfully! (Slow mode)", Duration = 3, Image = "circle-check" })
		updatestatus("Idle")
		updateprog("-")
		updateitem("-")
	end

	-- ==================== FIX MISSING ====================
	local function fixMissing()
		stopFlag = false
		if not savedhouse then
			return Rayfield:Notify({ Title = "Error", Content = "No house has been saved", Duration = 3, Image = "circle-alert" })
		end
		local house_success, houseInterior = pcall(function() return cd.get("house_interior") end)
		if not house_success or not houseInterior or houseInterior.player ~= plr then
			return Rayfield:Notify({ Title = "Error", Content = "Please enter your house", Duration = 3, Image = "circle-alert" })
		end
		updatestatus("Checking Missing Items")
		local currentFurn = houseInterior.furniture or {}
		local missing = {}
		local skipped = 0
		for _, savedItem in pairs(savedhouse.furniture or {}) do
			if stopFlag then break end
			local found = false
			for _, currItem in pairs(currentFurn) do
				if currItem.id == savedItem.id
					and currItem.cframe == savedItem.cframe
					and (currItem.scale == savedItem.scale or (not currItem.scale and not savedItem.scale))
				then
					local colorsMatch = true
					if #currItem.colors == #savedItem.colors then
						for i = 1, #currItem.colors do
							if currItem.colors[i] ~= savedItem.colors[i] then
								colorsMatch = false
								break
							end
						end
					else
						colorsMatch = false
					end
					if colorsMatch then found = true break end
				end
			end
			if not found then
				local canbuy, exists = canbuyfurniture(savedItem.id)
				if canbuy then
					table.insert(missing, {
						kind = savedItem.id,
						properties = { colors = savedItem.colors, cframe = savedItem.cframe, scale = savedItem.scale },
					})
				else
					skipped += 1
					if exists then
						Rayfield:Notify({ Title = "Warning", Content = "Insufficient funds for: " .. savedItem.id, Duration = 3, Image = "circle-alert" })
					else
						Rayfield:Notify({ Title = "Warning", Content = savedItem.id .. " is off-sale or invalid", Duration = 3, Image = "circle-alert" })
					end
				end
			end
		end
		if #missing == 0 then
			Rayfield:Notify({ Title = "Info", Content = "No missing items found (or all skipped). Skipped: " .. skipped, Duration = 5, Image = "info" })
			updatestatus("Idle") updateprog("-") updateitem("-")
			return
		end
		Rayfield:Notify({ Title = "Fixing", Content = "Attempting to place " .. #missing .. " missing items...", Duration = 5, Image = "loader" })
		placeFurnitures(missing, true)
		if stopFlag then
			updatestatus("Stopped") updateprog("-") updateitem("-")
			return
		end
		local success, interior = pcall(function() return cd.get("house_interior") end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then break end
				if v.text then
					pcall(function()
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				elseif v.outfit_name then
					pcall(function()
						router.get("AvatarAPI/StartEditingMannequin"):InvokeServer(v.outfit)
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", { save_outfit = true, outfit_name = "Outfit" }, plr.Character)
					end)
				end
			end
		end
		Rayfield:Notify({ Title = "Success", Content = "Fix attempt completed!", Duration = 3, Image = "circle-check" })
		updatestatus("Idle") updateprog("-") updateitem("-")
	end

	-- ==================== PASTE INIT ====================
	local function pastehouseinit(mode)
		stopFlag = false
		if not savedhouse then
			return Rayfield:Notify({ Title = "Error", Content = "No house has been saved", Duration = 3, Image = "circle-alert" })
		end
		local success, houseInterior = pcall(function() return cd.get("house_interior") end)
		if not success or not houseInterior or not houseInterior.player or houseInterior.player ~= plr then
			return Rayfield:Notify({ Title = "Error", Content = "Please enter your house to paste the house", Duration = 3, Image = "circle-alert" })
		end

		local resolvedSaved = getSavedHouseExactType(savedhouse)
		local resolvedCurrent = getInteriorExactType(houseInterior)

		if not IgnoreTypeCheck.CurrentValue then
			if not isExactSameHouseType(resolvedSaved, resolvedCurrent) then
				return Rayfield:Notify({
					Title = "Error",
					Content = "House types do not match!\nSaved: "
						.. tostring(getExactHouseDisplayName(resolvedSaved))
						.. "\nCurrent: "
						.. tostring(getExactHouseDisplayName(resolvedCurrent))
						.. "\n\nEnable 'Ignore House Type' to force paste.",
					Duration = 6,
					Image = "circle-alert",
				})
			end
		end

		Rayfield:Notify({ Title = "Loading", Content = "Clearing house", Duration = 3, Image = "loader" })
		updatestatus("Clearing House")

		for i, _ in pairs(houseInterior.furniture or {}) do
			if stopFlag then break end
			pcall(function()
				router.get("HousingAPI/SellFurniture"):FireServer(true, { i }, "sell")
			end)
		end

		task.wait(0.1)
		if stopFlag then updatestatus("Stopped") updateprog("-") updateitem("-") return end

		if mode == "slow" then
			task.spawn(pastehouseslow)
		else
			task.spawn(pastehousefast)
		end
	end

	Tab:CreateButton({ Name = "Place House Fast", Callback = function() pastehouseinit("fast") end })
	Tab:CreateButton({ Name = "Place House Slow", Callback = function() pastehouseinit("slow") end })
	Tab:CreateButton({ Name = "Fix Missing Items", Callback = fixMissing })

	Tab:CreateButton({
		Name = "Stop All",
		Callback = function()
			stopFlag = true
			autoPasteRunning = false
			updatestatus("Stopped") updateprog("-") updateitem("-")
			Rayfield:Notify({ Title = "Stopped", Content = "All processes stopped", Duration = 3, Image = "circle-check" })
		end,
	})

	Tab:CreateSection("Trade Functions")

	Tab:CreateButton({
		Name = "List House for Trade",
		Callback = function()
			local success, house = pcall(function() return cd.get("house_interior") end)
			if not success then
				Rayfield:Notify({ Title = "Error", Content = "Failed to access house data", Duration = 3, Image = "circle-alert" })
				return
			end
			pcall(function() router.get("HousingAPI/ListHouse"):InvokeServer() end)
			Rayfield:Notify({ Title = "Success", Content = "House listed for trade.", Duration = 3, Image = "circle-check" })
		end,
	})

	Tab:CreateButton({
		Name = "Unlist House for Trade",
		Callback = function()
			local success, house = pcall(function() return cd.get("house_interior") end)
			if not success then
				Rayfield:Notify({ Title = "Error", Content = "Failed to access house data", Duration = 3, Image = "circle-alert" })
				return
			end
			pcall(function() router.get("HousingAPI/UnlistHouse"):InvokeServer() end)
			Rayfield:Notify({ Title = "Success", Content = "House unlisted from trade.", Duration = 3, Image = "circle-check" })
		end,
	})

	local tradeSection = Tab:CreateSection("Auto Accept Trade Requests")
	local autoTradeEnabled = false
	local selectedPlayer = nil
	local TradeRequestEvent = router.get_event("TradeAPI/TradeRequestReceived")

	local function resolvePlayer(obj)
		if typeof(obj) == "Instance" and obj:IsA("Player") then return obj
		elseif typeof(obj) == "number" then return Players:GetPlayerByUserId(obj)
		elseif typeof(obj) == "string" then return Players:FindFirstChild(obj) end
		return nil
	end

	local function getPlayers()
		local t = { "None" }
		for _, p in ipairs(Players:GetPlayers()) do
			if p ~= Players.LocalPlayer then table.insert(t, p.Name) end
		end
		if #t == 1 then table.insert(t, "No Players Online") end
		return t
	end

	local PlayerDropdown = Tab:CreateDropdown({
		Name = "Select Player",
		Options = getPlayers(),
		CurrentOption = "None",
		MultipleOptions = false,
		Callback = function(option)
			local value = (typeof(option) == "table") and option[1] or option
			if value == "None" or value == "No Players Online" then
				selectedPlayer = nil
			else
				selectedPlayer = value
			end
		end,
	})

	local function refreshPlayers()
		local players = getPlayers()
		pcall(function() PlayerDropdown:Refresh(players) end)
		if not selectedPlayer or not table.find(players, selectedPlayer) then
			selectedPlayer = nil
			PlayerDropdown:Set("None")
		end
	end

	Tab:CreateInput({
		Name = "Type Player Name",
		PlaceholderText = "Enter username...",
		RemoveTextAfterFocusLost = false,
		Callback = function(text)
			if text ~= "" then
				selectedPlayer = text
				Rayfield:Notify({ Title = "Player Set", Content = "Now accepting: " .. text, Duration = 3 })
			else
				selectedPlayer = nil
				PlayerDropdown:Set("None")
			end
		end,
	})

	Tab:CreateButton({
		Name = "Refresh Players",
		Callback = function()
			refreshPlayers()
			Rayfield:Notify({ Title = "Players Refreshed", Content = "List updated", Duration = 3 })
		end,
	})

	TradeRequestEvent.OnClientEvent:Connect(function(...)
		if not autoTradeEnabled then return end
		if not selectedPlayer then return end
		local args = { ... }
		local player = resolvePlayer(args[1])
		if player and string.lower(player.Name) == string.lower(selectedPlayer) then
			local remote = router.get("TradeAPI/AcceptOrDeclineTradeRequest")
			if remote then
				pcall(function() remote:FireServer(player, true) end)
				pcall(function() remote:InvokeServer(player, true) end)
				pcall(function() remote:FireServer(true) end)
			end
		end
	end)

	task.spawn(function()
		while true do
			task.wait(0.5)
			if autoTradeEnabled and selectedPlayer then
				pcall(function() router.get("TradeAPI/AcceptNegotiation"):FireServer() end)
				task.wait(0.5)
				pcall(function() router.get("TradeAPI/ConfirmTrade"):FireServer() end)
			end
		end
	end)

	Tab:CreateToggle({
		Name = "Auto Accept Player",
		CurrentValue = false,
		Callback = function(val)
			autoTradeEnabled = val
			Rayfield:Notify({ Title = "Auto Trade", Content = val and ("Enabled for: " .. (selectedPlayer or "None")) or "Disabled", Duration = 3 })
		end,
	})

	Players.PlayerAdded:Connect(function() task.wait(0.3) refreshPlayers() end)
	Players.PlayerRemoving:Connect(function() task.wait(0.3) refreshPlayers() end)

	-- ==================== PASTEBIN TAB ====================
	local PastebinTab = Window:CreateTab("Pastebin", "clipboard")
	local userPastebinDevKey = ""
	local userPastebinUsername = ""
	local userPastebinPassword = ""

	local function serialize(value)
		local t = typeof(value)
		if t == "CFrame" then return { value:GetComponents() }
		elseif t == "Vector3" then return { value.X, value.Y, value.Z }
		elseif t == "Color3" then return { value.R, value.G, value.B }
		elseif t == "Instance" then return nil
		elseif t == "table" then
			local out = {}
			for k, v in pairs(value) do
				local sv = serialize(v)
				if sv ~= nil then out[k] = sv end
			end
			return out
		end
		return value
	end

	local function deserialize(value)
		if type(value) ~= "table" then return value end
		if #value > 0 then
			if #value == 3 and type(value[1]) == "number" then return Color3.new(unpack(value)) end
			if #value == 12 and type(value[1]) == "number" then return CFrame.new(unpack(value)) end
		end
		if value.r and value.g and value.b and type(value.r) == "number" then return Color3.new(value.r, value.g, value.b) end
		if value.R and value.G and value.B and type(value.R) == "number" then return Color3.new(value.R, value.G, value.B) end
		if value.__type == "CFrame" then return CFrame.new(unpack(value.components))
		elseif value.__type == "Vector3" then return Vector3.new(value.x, value.y, value.z)
		elseif value.__type == "Color3" then return Color3.new(value.r, value.g, value.b) end
		for k, v in pairs(value) do value[k] = deserialize(v) end
		return value
	end

	local function getUserKey(devKey, username, password)
		if not devKey or not username or not password then return nil end
		local data = { api_dev_key = devKey, api_user_name = username, api_user_password = password }
		local encoded = ""
		for k, v in pairs(data) do encoded ..= k .. "=" .. HttpService:UrlEncode(tostring(v)) .. "&" end
		encoded = encoded:sub(1, -2)
		local response = HttpService:RequestAsync({
			Url = "https://pastebin.com/api/api_login.php",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
			Body = encoded,
		})
		if response and response.StatusCode == 200 and not response.Body:find("Bad API request") then
			return response.Body
		end
		return nil
	end

	local function createPaste(content, name, devKey, userKey)
		if not devKey or devKey == "" then return nil, "NO_DEV_KEY" end
		local data = {
			api_dev_key = devKey,
			api_option = "paste",
			api_paste_code = content,
			api_paste_name = name or "CubixHouse",
			api_paste_private = "1",
			api_paste_format = "text",
			api_paste_expire_date = "N",
		}
		if userKey then data.api_user_key = userKey end
		local encoded = ""
		for k, v in pairs(data) do encoded ..= k .. "=" .. HttpService:UrlEncode(tostring(v)) .. "&" end
		encoded = encoded:sub(1, -2)
		local response = HttpService:RequestAsync({
			Url = "https://pastebin.com/api/api_post.php",
			Method = "POST",
			Headers = { ["Content-Type"] = "application/x-www-form-urlencoded" },
			Body = encoded,
		})
		return response and response.Body
	end

	local function convertToInternalFormat(decoded)
		if decoded.f and type(decoded.f) == "table" and #decoded.f > 0 and decoded.t and decoded.b then
			local furniture = {}
			for i, f in ipairs(decoded.f) do
				local colors = {}
				for ck, cv in pairs(f.cl or {}) do colors[tonumber(ck)] = cv end
				furniture[tostring(i)] = { id = f.i, cframe = f.c, colors = colors, scale = f.s }
			end
			decoded.furniture = furniture
			decoded.f = nil
			local textures = {}
			for _, t in pairs(decoded.t or {}) do
				local room = t.r
				if not textures[room] then textures[room] = {} end
				if t.k == "walls" then textures[room].walls = t.i
				elseif t.k == "floors" then textures[room].floors = t.i end
			end
			decoded.textures = textures
			decoded.building_type = decoded.b
			decoded.ambiance = decoded.a
		elseif decoded.Furniture then
			decoded.furnitures = decoded.Furniture
			decoded.Furniture = nil
		end
		if decoded.Floors or decoded.Walls then
			decoded.textures = {}
			if decoded.Floors then
				for _, f in ipairs(decoded.Floors) do
					table.insert(decoded.textures, { type = f.typeOfTexture, id = f.id, room = f.room })
				end
			end
			if decoded.Walls then
				for _, w in ipairs(decoded.Walls) do
					table.insert(decoded.textures, { type = w.typeOfTexture, id = w.id, room = w.room })
				end
			end
		end
		if decoded.BuildType then decoded.building_type = decoded.BuildType decoded.BuildType = nil end
		if decoded.furnitures and #decoded.furnitures > 0 then
			local function convertColors(obj)
				if type(obj) ~= "table" then return obj end
				if obj.__isColor then return { __type = "Color3", r = obj.r, g = obj.g, b = obj.b } end
				for k, v in pairs(obj) do obj[k] = convertColors(v) end
				return obj
			end
			local furniture = {}
			for i, f in ipairs(decoded.furnitures) do
				local colors = {}
				for ck, cv in pairs(f.colors or {}) do colors[ck] = cv end
				furniture[tostring(i)] = { id = f.id, cframe = f.cframe, colors = colors, scale = f.scale }
			end
			decoded.furniture = furniture
			decoded.furnitures = nil
			local textures = {}
			for _, t in ipairs(decoded.textures or {}) do
				if not textures[t.room] then textures[t.room] = {} end
				if t.type == "walls" then textures[t.room].walls = t.id
				elseif t.type == "floors" then textures[t.room].floors = t.id end
			end
			decoded.textures = textures
			if decoded.ambiance then decoded.ambiance = convertColors(decoded.ambiance) end
		elseif type(decoded.furniture) == "table" then
			for key, item in pairs(decoded.furniture) do
				local new_colors = {}
				for i, col in ipairs(item.colors or {}) do new_colors[i] = col end
				item.colors = new_colors
				if type(item.cframe) == "table" and item.cframe.components then
					item.cframe = item.cframe.components
				end
			end
		end
		decoded.building_type = decoded.building_type or decoded.buildingType or "Unknown"
		decoded.buildingType = nil
		return decoded
	end

	PastebinTab:CreateLabel(
		"TO GET DEV API KEY YOU NEED TO MAKE ACCOUNT ON PASTEBIN AFTER THAT GO TO https://pastebin.com/doc_api AND COPY YOUR DEV API KEY",
		"info"
	)
	PastebinTab:CreateDivider()

	PastebinTab:CreateInput({
		Name = "Pastebin Dev API Key (Required)",
		PlaceholderText = "Paste ONLY the API key (not a link)",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			value = tostring(value):gsub("%s+", ""):gsub("YouruniquedeveloperAPIkey:", ""):gsub("Your%w+developer%w+API%w+key:", "")
			userPastebinDevKey = value
		end,
	})
	PastebinTab:CreateInput({
		Name = "Pastebin Username",
		PlaceholderText = "Your Pastebin username",
		RemoveTextAfterFocusLost = false,
		Callback = function(value) userPastebinUsername = value end,
	})
	PastebinTab:CreateInput({
		Name = "Pastebin Password",
		PlaceholderText = "Your Pastebin password",
		RemoveTextAfterFocusLost = false,
		Callback = function(value) userPastebinPassword = value end,
	})

	local pasteNameInput = PastebinTab:CreateInput({
		Name = "House Name for Pastebin",
		PlaceholderText = "Enter house name (optional)",
		RemoveTextAfterFocusLost = false,
		Callback = function() end,
	})

	local function LoadHouseFromPastebin(pasteValue)
		local input = tostring(pasteValue or ""):gsub("%s+", "")
		if input == "" then
			return Rayfield:Notify({ Title = "Error", Content = "Please enter a Pastebin link or ID", Duration = 3 })
		end
		local pasteId = input:match("pastebin%.com/(.+)")
		if pasteId then pasteId = pasteId:gsub("raw/", "") else pasteId = input end
		local response
		local success = pcall(function()
			response = HttpService:RequestAsync({ Url = "https://pastebin.com/raw/" .. pasteId, Method = "GET" })
			if response then response.Body = response.Body or "" end
		end)
		if not success or not response or not response.Body then
			return Rayfield:Notify({ Title = "Error", Content = "Failed to fetch Pastebin data", Duration = 3 })
		end
		local ok, decoded = pcall(function() return HttpService:JSONDecode(response.Body) end)
		if not ok or type(decoded) ~= "table" then
			return Rayfield:Notify({ Title = "Error", Content = "Invalid Pastebin JSON", Duration = 3 })
		end
		decoded = convertToInternalFormat(decoded)
		savedhouse = deserialize(decoded)
		local furniturecost = 0
		for _, v in pairs(savedhouse.furniture or {}) do
			if furnituresdb[v.id] then furniturecost += furnituresdb[v.id].cost or 0 end
		end
		local texturecost = 0
		for _, v in pairs(savedhouse.textures or {}) do
			if texturesdb.walls[v.walls] then texturecost += texturesdb.walls[v.walls].cost or 0 end
			if texturesdb.floors[v.floors] then texturecost += texturesdb.floors[v.floors].cost or 0 end
		end
		local t_count = counttextures(savedhouse.textures)
		local amb = savedhouse.ambiance and "Yes" or "No"
		local typ = savedhouse.building_type or "-"
		task.spawn(setscaninfo, countfurnitures(savedhouse.furniture), furniturecost, t_count, texturecost, amb, typ)
		Rayfield:Notify({ Title = "Success", Content = "House loaded from Pastebin", Duration = 3, Image = "circle-check" })
	end

	PastebinTab:CreateInput({
		Name = "Pastebin Link / ID",
		PlaceholderText = "https://pastebin.com/xxxxxx or xxxxxx",
		RemoveTextAfterFocusLost = true,
		WaitTime = 2,
		Callback = function(value) LoadHouseFromPastebin(value) end,
	})

	PastebinTab:CreateButton({
		Name = "Save House to Pastebin",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({ Title = "Error", Content = "No house has been scanned or loaded", Duration = 3 })
			end
			if #userPastebinDevKey < 20 or not userPastebinDevKey:match("^[%w]+$") then
				return Rayfield:Notify({ Title = "Invalid API Key", Content = "Paste ONLY the Pastebin Dev API key.\nDo not paste a URL.", Duration = 5 })
			end
			local clean_house = deepCopy(savedhouse)
			local furniturecost = 0
			for _, v in pairs(clean_house.furniture or {}) do
				if furnituresdb[v.id] then furniturecost += furnituresdb[v.id].cost or 0 end
				v.hash = nil v.was_free = nil v.no_value = nil v.was_default = nil
				v.item_category = nil v.item_kind = nil v.occupied = v.occupied or nil
				v.door_position = nil v.last_position = nil v.on = nil
				local new_colors = {}
				for i, col in ipairs(v.colors or {}) do new_colors[i] = { col.R, col.G, col.B } end
				v.colors = new_colors
				if typeof(v.cframe) == "CFrame" then v.cframe = { v.cframe:GetComponents() } end
			end
			local texturecost = 0
			for _, v in pairs(clean_house.textures or {}) do
				if texturesdb.walls[v.walls] then texturecost += texturesdb.walls[v.walls].cost or 0 end
				if texturesdb.floors[v.floors] then texturecost += texturesdb.floors[v.floors].cost or 0 end
			end
			clean_house.total_cost = furniturecost + texturecost
			clean_house.furniture_quantity = countfurnitures(clean_house.furniture)
			if clean_house.building_type == "micro_2023" then clean_house.building_type = "Tiny Home" end
			clean_house.saved_by = "Cubix-HouseCloner"
			clean_house.properties = nil clean_house.house_id = nil clean_house.listed_for_trade = nil
			clean_house.unique = nil clean_house.active_addons = nil clean_house.allows_coop_building = nil
			clean_house.house_pos = nil clean_house.textures_hash = nil clean_house.player = nil clean_house.music = nil
			local function convert_colors_recursive(tbl)
				if type(tbl) ~= "table" then return tbl end
				for k, v in pairs(tbl) do
					if typeof(v) == "Color3" then tbl[k] = { v.R, v.G, v.B }
					elseif typeof(v) == "CFrame" then tbl[k] = { v:GetComponents() }
					elseif type(v) == "table" then tbl[k] = convert_colors_recursive(v) end
				end
				return tbl
			end
			if clean_house.ambiance then clean_house.ambiance = convert_colors_recursive(clean_house.ambiance) end
			local ok, encoded = pcall(function() return HttpService:JSONEncode(clean_house) end)
			if not ok then return Rayfield:Notify({ Title = "Error", Content = "Failed to encode house data", Duration = 3 }) end
			local apiUserKey = getUserKey(userPastebinDevKey, userPastebinUsername, userPastebinPassword)
			if not apiUserKey then
				Rayfield:Notify({ Title = "Warning", Content = "Failed to login to Pastebin, posting as guest", Duration = 3 })
			end
			local inputtedName = pasteNameInput.CurrentValue or ""
			local pasteName = "CubixHouse" .. (inputtedName ~= "" and "_" .. inputtedName or "")
			local result, err = createPaste(encoded, pasteName, userPastebinDevKey, apiUserKey)
			if err == "NO_DEV_KEY" or not result or result:find("Bad API request") then
				return Rayfield:Notify({ Title = "Pastebin Error", Content = tostring(result), Duration = 6 })
			end
			if setclipboard then setclipboard(result) end
			Rayfield:Notify({ Title = "Success", Content = "House saved to Pastebin\nLink copied to clipboard", Duration = 8 })
		end,
	})

	-- ==================== CREATE FILE TAB ====================
	local CreateFileTab = Window:CreateTab("Create File", "folder")

	if not isfolder("HouseFS") then makefolder("HouseFS") end

	CreateFileTab:CreateSection("Saved Houses")

	local fileDropdown = CreateFileTab:CreateDropdown({
		Name = "Select Saved House",
		Options = {},
		CurrentOption = nil,
		MultipleOptions = false,
		Flag = "FileDropdown",
		Callback = function(_) end,
	})

	local saveInput = CreateFileTab:CreateInput({
		Name = "Save As",
		PlaceholderText = "Enter File Name",
		RemoveTextAfterFocusLost = false,
		Callback = function(_) end,
	})

	local pendingDelete = nil
	local fileSearchQuery = ""
	local allFilesCache = {}

	local function naturalSort(a, b)
		local function pad(n) return ("%010d"):format(tonumber(n) or 0) end
		local na = a:lower():gsub("%d+", pad)
		local nb = b:lower():gsub("%d+", pad)
		return na < nb
	end

	local function refreshFileDropdown()
		local files = listfiles("HouseFS")
		local validFiles = {}
		for _, filePath in ipairs(files) do
			local fileName = filePath:match("^.+/(.+)$") or filePath
			if fileName:sub(-5) == ".json" or fileName:sub(-4) == ".txt" or fileName:sub(-4) == ".lua" then
				table.insert(validFiles, fileName)
			end
		end
		table.sort(validFiles, naturalSort)
		allFilesCache = validFiles
		local filtered = {}
		for _, name in ipairs(allFilesCache) do
			if fileSearchQuery == "" or string.find(string.lower(name), string.lower(fileSearchQuery), 1, true) then
				table.insert(filtered, name)
			end
		end
		local currentlySelected = fileDropdown.CurrentOption
		if type(currentlySelected) == "table" then currentlySelected = currentlySelected[1] end
		fileDropdown:Refresh(filtered)
		if currentlySelected and table.find(filtered, currentlySelected) then
			fileDropdown:Set(currentlySelected)
		elseif #filtered > 0 then
			fileDropdown:Set(filtered[1])
		else
			fileDropdown:Set(nil)
		end
		refreshFQFileList()
	end

	refreshFileDropdown()

	CreateFileTab:CreateInput({
		Name = "Search Files",
		PlaceholderText = "Type to search house files...",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			fileSearchQuery = tostring(value or "")
			refreshFileDropdown()
		end,
	})

	CreateFileTab:CreateButton({
		Name = "Save House to File",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({ Title = "Error", Content = "No house has been scanned or loaded", Duration = 3, Image = "circle-alert" })
			end
			local filename = saveInput.CurrentValue
			if not filename or filename == "" then
				return Rayfield:Notify({ Title = "Error", Content = "Please enter a valid filename", Duration = 3, Image = "circle-alert" })
			end
			local clean_house = deepCopy(savedhouse)
			local furniturecost = 0
			for _, v in pairs(clean_house.furniture or {}) do
				if furnituresdb[v.id] then furniturecost += furnituresdb[v.id].cost or 0 end
				v.hash = nil v.was_free = nil v.no_value = nil v.was_default = nil
				v.item_category = nil v.item_kind = nil v.occupied = v.occupied or nil
				v.door_position = nil v.last_position = nil v.on = nil
				local new_colors = {}
				for i, col in ipairs(v.colors or {}) do new_colors[i] = { col.R, col.G, col.B } end
				v.colors = new_colors
				if typeof(v.cframe) == "CFrame" then v.cframe = { v.cframe:GetComponents() } end
			end
			local texturecost = 0
			for _, v in pairs(clean_house.textures or {}) do
				if texturesdb.walls[v.walls] then texturecost += texturesdb.walls[v.walls].cost or 0 end
				if texturesdb.floors[v.floors] then texturecost += texturesdb.floors[v.floors].cost or 0 end
			end
			clean_house.total_cost = furniturecost + texturecost
			clean_house.furniture_quantity = countfurnitures(clean_house.furniture)
			if clean_house.building_type == "micro_2023" then clean_house.building_type = "Tiny Home" end
			clean_house.saved_by = "Cubix-HouseCloner"
			clean_house.properties = nil clean_house.house_id = nil clean_house.listed_for_trade = nil
			clean_house.unique = nil clean_house.active_addons = nil clean_house.allows_coop_building = nil
			clean_house.house_pos = nil clean_house.textures_hash = nil clean_house.player = nil clean_house.music = nil
			local function convert_colors_recursive(tbl)
				if type(tbl) ~= "table" then return tbl end
				for k, v in pairs(tbl) do
					if typeof(v) == "Color3" then tbl[k] = { v.R, v.G, v.B }
					elseif typeof(v) == "CFrame" then tbl[k] = { v:GetComponents() }
					elseif type(v) == "table" then tbl[k] = convert_colors_recursive(v) end
				end
				return tbl
			end
			if clean_house.ambiance then clean_house.ambiance = convert_colors_recursive(clean_house.ambiance) end
			local success, encoded = pcall(function() return HttpService:JSONEncode(clean_house) end)
			if not success then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to encode house data", Duration = 3, Image = "circle-alert" })
			end
			writefile("HouseFS/" .. filename .. ".json", encoded)
			refreshFileDropdown()
			Rayfield:Notify({ Title = "Success", Content = "House saved: " .. filename .. ".json", Duration = 3, Image = "circle-check" })
		end,
	})

	-- File tab convertToInternalFormat (local scope)
	local function convertToInternalFormatFile(decoded)
		if decoded.Furniture then decoded.furnitures = decoded.Furniture decoded.Furniture = nil end
		if decoded.Floors or decoded.Walls then
			decoded.textures = {}
			if decoded.Floors then
				for _, f in ipairs(decoded.Floors) do
					table.insert(decoded.textures, { type = f.typeOfTexture, id = f.id, room = f.room })
				end
			end
			if decoded.Walls then
				for _, w in ipairs(decoded.Walls) do
					table.insert(decoded.textures, { type = w.typeOfTexture, id = w.id, room = w.room })
				end
			end
		end
		if decoded.BuildType then decoded.building_type = decoded.BuildType decoded.BuildType = nil end
		if decoded.furnitures and #decoded.furnitures > 0 then
			local function convertColors(obj)
				if type(obj) ~= "table" then return obj end
				if obj.__isColor then return { __type = "Color3", r = obj.r, g = obj.g, b = obj.b } end
				for k, v in pairs(obj) do obj[k] = convertColors(v) end
				return obj
			end
			local furniture = {}
			for i, f in ipairs(decoded.furnitures) do
				local colors = {}
				for ck, cv in pairs(f.colors or {}) do colors[ck] = cv end
				furniture[tostring(i)] = { id = f.id, cframe = f.cframe, colors = colors, scale = f.scale }
			end
			decoded.furniture = furniture
			decoded.furnitures = nil
			local textures = {}
			for _, t in ipairs(decoded.textures or {}) do
				if not textures[t.room] then textures[t.room] = {} end
				if t.type == "walls" then textures[t.room].walls = t.id
				elseif t.type == "floors" then textures[t.room].floors = t.id end
			end
			decoded.textures = textures
			if decoded.ambiance then decoded.ambiance = convertColors(decoded.ambiance) end
		elseif type(decoded.furniture) == "table" then
			for key, item in pairs(decoded.furniture) do
				local new_colors = {}
				for i, col in ipairs(item.colors or {}) do new_colors[i] = col end
				item.colors = new_colors
				if type(item.cframe) == "table" and item.cframe.components then
					item.cframe = item.cframe.components
				end
			end
		end
		decoded.building_type = decoded.building_type or decoded.buildingType or "Unknown"
		decoded.buildingType = nil
		return decoded
	end

	CreateFileTab:CreateButton({
		Name = "Load House from File",
		Callback = function()
			local selected = fileDropdown.CurrentOption
			if type(selected) == "table" then selected = selected[1] end
			if not selected or selected == "" then
				return Rayfield:Notify({ Title = "Error", Content = "No file selected to load", Duration = 3 })
			end
			local houseData, err = loadHouseDataFromFile(selected)
			if not houseData then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to load " .. selected .. ": " .. tostring(err), Duration = 3 })
			end
			savedhouse = houseData
			local furniturecost = 0
			for _, v in pairs(savedhouse.furniture or {}) do
				if furnituresdb[v.id] then furniturecost += furnituresdb[v.id].cost or 0 end
			end
			local texturecost = 0
			for _, v in pairs(savedhouse.textures or {}) do
				if texturesdb.walls[v.walls] then texturecost += texturesdb.walls[v.walls].cost or 0 end
				if texturesdb.floors[v.floors] then texturecost += texturesdb.floors[v.floors].cost or 0 end
			end
			local t_count = counttextures(savedhouse.textures)
			local amb = savedhouse.ambiance and "Yes" or "No"
			local typ = savedhouse.building_type or "-"
			task.spawn(setscaninfo, countfurnitures(savedhouse.furniture), furniturecost, t_count, texturecost, amb, typ)
			Rayfield:Notify({ Title = "Success", Content = "House loaded from file: " .. selected, Duration = 3 })
			refreshFileDropdown()
		end,
	})

	CreateFileTab:CreateButton({
		Name = "Delete Selected House",
		Callback = function()
			local selected = fileDropdown.CurrentOption
			if type(selected) == "table" then selected = selected[1] end
			if not selected or selected == "" then
				return Rayfield:Notify({ Title = "Error", Content = "No house selected to delete.", Duration = 3 })
			end
			if pendingDelete == selected then
				local filePath = "HouseFS/" .. selected
				if isfile(filePath) then
					delfile(filePath)
					Rayfield:Notify({ Title = "Deleted", Content = selected .. " has been deleted.", Duration = 3, Image = "circle-check" })
					pendingDelete = nil
					refreshFileDropdown()
				else
					Rayfield:Notify({ Title = "Error", Content = "File not found: " .. selected, Duration = 3 })
				end
			else
				pendingDelete = selected
				Rayfield:Notify({
					Title = "Confirm Delete",
					Content = "Are you sure you want to delete **" .. selected .. "**?\n\nClick the Delete button again to confirm.",
					Duration = 10,
					Image = "circle-alert",
				})
			end
		end,
	})

	CreateFileTab:CreateButton({
		Name = "Refresh List",
		Callback = function()
			refreshFileDropdown()
			Rayfield:Notify({ Title = "Refreshed", Content = "File list updated and sorted", Duration = 2 })
		end,
	})

	-- ==================== TELEPORT TAB ====================
	local Teleport = Window:CreateTab("Teleport", "map-pin")
	Teleport:CreateSection("House Teleports")

	local function loadinterior(interiortype, name)
		local load = require(game:GetService("ReplicatedStorage").Fsys).load
		local interiors = load("InteriorsM")
		local enter = interiors.enter
		if interiortype == "interior" then enter(name, "", {}) return end
		if interiortype == "house" then enter("housing", "MainDoor", { house_owner = name }) end
	end

	local function getplayernames()
		local players = Players:GetPlayers()
		local names = table.create(#players)
		for i, player in ipairs(players) do names[i] = player.Name end
		return names
	end

	local selectedplayer = Teleport:CreateDropdown({
		Name = "Select Player",
		Options = getplayernames(),
		CurrentOption = { getplayernames()[1] },
		MultipleOptions = false,
		Flag = "Dropdown1",
		Callback = function(_) end,
	})

	Players.PlayerAdded:Connect(function() selectedplayer:Refresh(getplayernames()) end)
	Players.PlayerRemoving:Connect(function() selectedplayer:Refresh(getplayernames()) end)

	Teleport:CreateButton({
		Name = "Enter House",
		Callback = function()
			local target = Players:FindFirstChild(selectedplayer.CurrentOption[1])
			if target then loadinterior("house", target) end
		end,
	})

	Teleport:CreateButton({
		Name = "Teleport to My House",
		Callback = function()
			local lp = Players.LocalPlayer
			if lp then loadinterior("house", lp) end
		end,
	})

	-- ==================== AUTO REFRESH ====================
	task.spawn(function()
		task.wait(2)
		refreshOwnedHouses()
	end)

	task.spawn(function()
		while true do
			task.wait(2)
			refreshOwnedHouses()
		end
	end)

	ClientData.register_callback_plus_existing("house_manager", function()
		refreshOwnedHouses()
	end)

	Rayfield:Notify({ Title = "Cubix", Content = "Loaded successfully!", Duration = 5 })
end

loadMain()
