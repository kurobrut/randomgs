-- // Services and modules
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

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
local function lEncode(t) return HttpService:JSONEncode(t) end
local function lDecode(s) return HttpService:JSONDecode(s) end

local function loadMain()
    local Rayfield = loadstring(game:HttpGet("https://raw.githubusercontent.com/SiriusSoftwareLtd/Rayfield/main/source.lua"))()

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

    local function updatestatus(s) pcall(function() status_label:Set("Building Status: " .. s) end) end
    local function updateprog(p) pcall(function() prog_label:Set("Building Prog: " .. p) end) end
    local function updateitem(i) pcall(function() item_label:Set("Items: " .. i) end) end

    updatestatus("Idle")
    updateprog("-")
    updateitem("-")

    -- ==================== SHARED OWNED HOUSES SYSTEM ====================
    local ownedHouseList = {}
    local ownedHouseMap = {} -- name → house_id

    local ownedDropdown  -- Sell dropdown
    local tradeDropdown  -- Trade dropdown

    local function refreshOwnedHouses()
        table.clear(ownedHouseList)
        table.clear(ownedHouseMap)

        for _, house in pairs(ClientData.get("house_manager") or {}) do
            table.insert(ownedHouseList, house.name)
            ownedHouseMap[house.name] = house.house_id
        end

        table.sort(ownedHouseList)

        -- Refresh Sell Dropdown
        if ownedDropdown then
            pcall(function() ownedDropdown:Refresh(ownedHouseList, true) end)
        end

        -- Refresh Trade Dropdown
        if tradeDropdown then
            pcall(function() tradeDropdown:Refresh(ownedHouseList, true) end)
        end
    end

    -- ==================== HOUSE BUYER TAB ====================
    local selectedHouseKind = nil
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
        Callback = function(opt)
            local v = typeof(opt) == "table" and opt[1] or opt
            selectedHouseKind = houseMap[v]
        end,
    })

    ownedDropdown = BuyerTab:CreateDropdown({
        Name = "Select Owned House To Sell",
        Options = ownedHouseList,
        Callback = function(opt)
            local v = typeof(opt) == "table" and opt[1] or opt
            selectedHouseId = ownedHouseMap[v]
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

    local function buyHouse()
        if not selectedHouseKind then
            Rayfield:Notify({ Title = "Auto Buy", Content = "No house selected ❌", Duration = 3 })
            return false
        end

        local before = {}
        for _, h in pairs(ClientData.get("house_manager") or {}) do
            before[h.house_id] = true
        end

        local success = pcall(function()
            Router.get("HousingAPI/BuyHouseWithAddons"):InvokeServer(selectedHouseKind, {}, Color3.fromRGB(255, 182, 193))
        end)

        if success then
            Rayfield:Notify({ Title = "Auto Buy", Content = "Buying house... 🏠", Duration = 3 })
            task.wait(1)

            -- Auto rename
            local current = ClientData.get("house_manager") or {}
            local map = {}
            for _, h in pairs(current) do map[h.house_id] = h end

            for id, house in pairs(map) do
                if not before[id] then
                    local max = 0
                    for _, h in pairs(map) do
                        local num = tonumber(string.match(h.name or "", "Kalirem (%d+)")) or 0
                        if num > max then max = num end
                    end
                    local newName = "Kalirem " .. (max + 1)
                    pcall(function() Router.get("HousingAPI/RenameHouse"):FireServer(id, newName) end)
                    Rayfield:Notify({ Title = "Rename", Content = newName, Duration = 3 })
                end
            end

            refreshOwnedHouses()
            Rayfield:Notify({ Title = "Auto Buy", Content = "House bought ✔", Duration = 3 })
            return true
        else
            Rayfield:Notify({ Title = "Auto Buy", Content = "Buy failed ❌", Duration = 3 })
        end
        return false
    end

    BuyerTab:CreateButton({
        Name = "Sell Selected House",
        Callback = function()
            if not selectedHouseId then
                Rayfield:Notify({ Title = "Sell", Content = "No house selected ❌", Duration = 3 })
                return
            end
            pcall(function() Router.get("HousingAPI/SellHouse"):InvokeServer(selectedHouseId) end)
            Rayfield:Notify({ Title = "Sell", Content = "House sold ✔", Duration = 3 })
            task.wait(1)
            refreshOwnedHouses()
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

            -- Correct way to loop through Rayfield multiple selections
            for _, name in ipairs(opts or {}) do
                local id = ownedHouseMap[name]
                if id then
                    tradeSelections[id] = name
                end
            end

            -- Properly count how many houses are selected
            local selectedCount = 0
            for _ in pairs(tradeSelections) do
                selectedCount = selectedCount + 1
            end

            -- Notify only when the count actually changes
            if selectedCount ~= lastTradeCount then
                lastTradeCount = selectedCount
                Rayfield:Notify({ Title = "Trading", Content = selectedCount .. " houses selected" })   -- Uses your notify function
            end
        end,
    })

    local function waitUntilHouseGone(id, timeout)
        timeout = timeout or 300
        local start = tick()
        while tick() - start < timeout do
            local found = false
            for _, h in pairs(ClientData.get("house_manager") or {}) do
                if h.house_id == id then found = true break end
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
            lastTradeCount = 0   -- Reset counter

            pcall(function()
                if tradeDropdown then
                    tradeDropdown:Set({})
                end
            end)

            Rayfield:Notify({ Title = "Trading", Content = "Queue cleared & stopped 🛑" })
        end,
    })

	local function countfurnitures(t)
		local c = 0
		for _ in pairs(t or {}) do
			c += 1
		end
		return c
	end
	local function counttextures(textures)
		local c = 0
		for _, v in pairs(textures or {}) do
			if v.walls then
				c += 1
			end
			if v.floors then
				c += 1
			end
		end
		return c
	end
	local savedhouse
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
	local IgnoreTypeCheck = Tab:CreateToggle({
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
	local function deepCopy(tbl)
		if type(tbl) ~= "table" then
			return tbl
		end
		local t = {}
		for k, v in pairs(tbl) do
			t[k] = deepCopy(v)
		end
		return t
	end
	-- // Scan house (from current interior)
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
					if v.creator then
						v.creator = nil
					end
				end
			end
			local furniturecost = 0
			for _, v in pairs(savedhouse.furniture or {}) do
				local db_entry = furnituresdb[v.id]
				if db_entry and db_entry.cost then
					furniturecost += db_entry.cost
				end
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
			pcall(function()
				typ = savedhouse.building_type or "-"
			end)
			task.spawn(
				setscaninfo,
				countfurnitures(savedhouse.furniture),
				furniturecost,
				t_count,
				texturecost,
				amb,
				typ
			)
			Rayfield:Notify({
				Title = "Success",
				Content = "Scanned house",
				Duration = 3,
				Image = "circle-check",
			})
			updatestatus("Idle")
		end,
	})
	-- // Clear house
	Tab:CreateButton({
		Name = "Sell All Furnitures",
		Callback = function()
			updatestatus("Clearing House")
			local success, furniture = pcall(function()
				return cd.get("house_interior").furniture
			end)
			if not success or not furniture then
				Rayfield:Notify({
					Title = "Error",
					Content = "Failed to access house furniture",
					Duration = 3,
					Image = "circle-alert",
				})
				updatestatus("Idle")
				return
			end
			local t = {}
			for i, _ in pairs(furniture) do
				table.insert(t, i)
			end
			local args = {
				false,
				t,
				"sell",
			}
			pcall(function()
				router.get("HousingAPI/SellFurniture"):FireServer(unpack(args))
			end)
			Rayfield:Notify({
				Title = "Success",
				Content = "House cleared successfully!",
				Duration = 3,
				Image = "circle-check",
			})
			updatestatus("Idle")
		end,
	})
	-- // Furniture and texture helpers
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
		if texture == "tile" then
			return true
		end
		local success, textures = pcall(function()
			return cd.get("house_interior").textures
		end)
		if not success or not textures then
			return false
		end
		for i, v in pairs(textures) do
			if i == room and v[texturetype] == texture then
				return true
			end
		end
		return false
	end
	local function buytexturewithretry(room, texturetype, texture, tries)
		tries = tries or 0
		if tries > 10 then
			warn("Failed to buy texture:", texture)
			return
		end
		if stopFlag then
			return
		end
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
		if totalfurnitures == 0 then
			return
		end
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

			-- 🔥 Show items in this batch
			for _, item in ipairs(batch) do
				if stopFlag then
					break
				end

				updateitem((isFix and "Fixing: " or "Placing: ") .. (item.kind or "Unknown"))
				task.wait(0.03) -- smooth UI update
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

	Tab:CreateSection("Paste Functions")
	-- // Paste house (fast)
	local function pastehousefast()
		if not savedhouse or not savedhouse.furniture then
			return Rayfield:Notify({
				Title = "Error",
				Content = "No house has been saved",
				Duration = 3,
				Image = "circle-alert",
			})
		end
		Rayfield:Notify({
			Title = "Loading",
			Content = "Pasting furnitures...",
			Duration = 3,
			Image = "loader",
		})
		updatestatus("Pasting Furniture")
		local validFurniture = {}
		local totalfurnitures = 0
		for i, v in pairs(savedhouse.furniture) do
			if v.id ~= "lures_2023_cozy_home_lure" and v.cframe and typeof(v.cframe) == "CFrame" then
				validFurniture[i] = v
				totalfurnitures += 1
			else
				warn("[SKIP] Skipping invalid furniture or CFrame:", v.id)
			end
		end
		updateprog("0/" .. totalfurnitures)
		updateitem("-")
		local processedCount = 0
		local furniturest = {}
		for i, v in pairs(validFurniture) do
			if stopFlag then
				break
			end
			local canbuy, exists = canbuyfurniture(v.id)
			if not canbuy and exists == true then
				updatestatus("Idle")
				updateprog("-")
				updateitem("-")
				return Rayfield:Notify({
					Title = "Error",
					Content = "Insufficient funds for furniture: " .. v.id,
					Duration = 3,
					Image = "circle-alert",
				})
			elseif not canbuy and exists == false then
				processedCount += 1
				updateprog(processedCount .. "/" .. totalfurnitures)
				continue
			end
			table.insert(furniturest, {
				kind = v.id,
				properties = {
					colors = v.colors,
					cframe = v.cframe,
					scale = v.scale,
				},
			})
			processedCount += 1
			updateprog(processedCount .. "/" .. totalfurnitures)
			updateitem(v.id)
		end
		if stopFlag then
			updatestatus("Stopped")
			updateprog("-")
			updateitem("-")
			return
		end
		if #furniturest > 0 then
			pcall(function()
				router.get("HousingAPI/BuyFurnitures"):InvokeServer(furniturest)
			end)
		end
		-- Activate furniture after buying
		local success, interior = pcall(function()
			return cd.get("house_interior")
		end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then
					break
				end
				if v.text then
					pcall(function()
						router
							.get("HousingAPI/ActivateFurniture")
							:InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				elseif v.outfit_name then
					pcall(function()
						router.get("AvatarAPI/StartEditingMannequin"):InvokeServer(v.outfit)
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", {
							save_outfit = true,
							outfit_name = "Outfit",
						}, plr.Character)
					end)
				end
			end
		end
		-- Apply textures
		if savedhouse.textures and Pastetextures.CurrentValue then
			updatestatus("Pasting Textures")
			updateprog("-")
			for roomId, textureData in pairs(savedhouse.textures) do
				if stopFlag then
					break
				end
				if textureData.floors and not textureexists(roomId, "floors", textureData.floors) then
					updateitem(roomId .. " floors: " .. textureData.floors)
					buytexturewithretry(roomId, "floors", textureData.floors)
				end
				if stopFlag then
					break
				end
				if textureData.walls and not textureexists(roomId, "walls", textureData.walls) then
					updateitem(roomId .. " walls: " .. textureData.walls)
					buytexturewithretry(roomId, "walls", textureData.walls)
				end
				task.wait()
			end
		end
		-- Apply ambiance and music
		if savedhouse.ambiance then
			pcall(function()
				router.get("AmbianceAPI/UpdateAmbiance"):FireServer(savedhouse.ambiance)
			end)
		end
		if savedhouse.music then
			pcall(function()
				router.get("RadioAPI/Play"):FireServer(savedhouse.music.name, savedhouse.music.id)
				if not savedhouse.music.playing then
					router.get("RadioAPI/Pause"):InvokeServer()
				end
			end)
		end

		Rayfield:Notify({
			Title = "Success",
			Content = "House Placed successfully!",
			Duration = 3,
			Image = "circle-check",
		})
		updatestatus("Idle")
		updateprog("-")
		updateitem("-")
	end

	-- // Paste house (slow)
	local function pastehouseslow()
		if not savedhouse or not savedhouse.furniture then
			return Rayfield:Notify({
				Title = "Error",
				Content = "No house has been saved",
				Duration = 3,
				Image = "circle-alert",
			})
		end
		Rayfield:Notify({
			Title = "Loading",
			Content = "Pasting furnitures slowly...",
			Duration = 3,
			Image = "loader",
		})
		updatestatus("Pasting Furniture (Slow)")
		local validFurniture = {}
		local totalfurnitures = 0
		for i, v in pairs(savedhouse.furniture) do
			if v.id ~= "lures_2023_cozy_home_lure" and v.cframe and typeof(v.cframe) == "CFrame" then
				validFurniture[i] = v
				totalfurnitures += 1
			else
				warn("[SKIP] Skipping invalid furniture or CFrame:", v.id)
			end
		end
		updateprog("0/" .. totalfurnitures)
		updateitem("-")
		local processedCount = 0
		local furniturest = {}
		for i, v in pairs(validFurniture) do
			if stopFlag then
				break
			end
			local canbuy, exists = canbuyfurniture(v.id)
			if not canbuy and exists == true then
				updatestatus("Idle")
				updateprog("-")
				updateitem("-")
				return Rayfield:Notify({
					Title = "Error",
					Content = "Insufficient funds for furniture: " .. v.id,
					Duration = 3,
					Image = "circle-alert",
				})
			elseif not canbuy and exists == false then
				processedCount += 1
				updateprog(processedCount .. "/" .. totalfurnitures)
				continue
			end
			table.insert(furniturest, {
				kind = v.id,
				properties = {
					colors = v.colors,
					cframe = v.cframe,
					scale = v.scale,
				},
			})
			processedCount += 1
			updateprog(processedCount .. "/" .. totalfurnitures)
			updateitem(v.id)
		end
		if stopFlag then
			updatestatus("Stopped")
			updateprog("-")
			updateitem("-")
			return
		end
		if #furniturest > 0 then
			placeFurnitures(furniturest, false)
		end
		if stopFlag then
			updatestatus("Stopped")
			updateprog("-")
			updateitem("-")
			return
		end
		-- Activate furniture after buying
		local success, interior = pcall(function()
			return cd.get("house_interior")
		end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then
					break
				end
				if v.text then
					pcall(function()
						router
							.get("HousingAPI/ActivateFurniture")
							:InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				elseif v.outfit_name then
					pcall(function()
						router.get("AvatarAPI/StartEditingMannequin"):InvokeServer(v.outfit)
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", {
							save_outfit = true,
							outfit_name = "Outfit",
						}, plr.Character)
					end)
				end
			end
		end
		-- Apply textures
		if savedhouse.textures and Pastetextures.CurrentValue then
			updatestatus("Pasting Textures")
			updateprog("-")
			for roomId, textureData in pairs(savedhouse.textures) do
				if stopFlag then
					break
				end
				if textureData.floors and not textureexists(roomId, "floors", textureData.floors) then
					updateitem(roomId .. " floors: " .. textureData.floors)
					buytexturewithretry(roomId, "floors", textureData.floors)
				end
				if stopFlag then
					break
				end
				if textureData.walls and not textureexists(roomId, "walls", textureData.walls) then
					updateitem(roomId .. " walls: " .. textureData.walls)
					buytexturewithretry(roomId, "walls", textureData.walls)
				end
				task.wait()
			end
		end
		-- Apply ambiance and music
		if savedhouse.ambiance then
			pcall(function()
				router.get("AmbianceAPI/UpdateAmbiance"):FireServer(savedhouse.ambiance)
			end)
		end
		if savedhouse.music then
			pcall(function()
				router.get("RadioAPI/Play"):FireServer(savedhouse.music.name, savedhouse.music.id)
				if not savedhouse.music.playing then
					router.get("RadioAPI/Pause"):InvokeServer()
				end
			end)
		end
		Rayfield:Notify({
			Title = "Success",
			Content = "House Placed successfully! (Slow mode)",
			Duration = 3,
			Image = "circle-check",
		})
		updatestatus("Idle")
		updateprog("-")
		updateitem("-")
	end

	local stopFlag = false

	local function fixMissing()
		stopFlag = false

		if not savedhouse then
			return Rayfield:Notify({
				Title = "Error",
				Content = "No house has been saved",
				Duration = 3,
				Image = "circle-alert",
			})
		end
		local house_success, houseInterior = pcall(function()
			return cd.get("house_interior")
		end)
		if not house_success or not houseInterior or houseInterior.player ~= plr then
			return Rayfield:Notify({
				Title = "Error",
				Content = "Please enter your house",
				Duration = 3,
				Image = "circle-alert",
			})
		end
		updatestatus("Checking Missing Items")
		local currentFurn = houseInterior.furniture or {}
		local missing = {}
		local skipped = 0
		for _, savedItem in pairs(savedhouse.furniture or {}) do
			if stopFlag then
				break
			end
			local found = false
			for _, currItem in pairs(currentFurn) do
				if
					currItem.id == savedItem.id
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
					if colorsMatch then
						found = true
						break
					end
				end
			end
			if not found then
				local canbuy, exists = canbuyfurniture(savedItem.id)
				if canbuy then
					table.insert(missing, {
						kind = savedItem.id,
						properties = {
							colors = savedItem.colors,
							cframe = savedItem.cframe,
							scale = savedItem.scale,
						},
					})
				else
					skipped += 1
					if exists then
						Rayfield:Notify({
							Title = "Warning",
							Content = "Insufficient funds for: " .. savedItem.id,
							Duration = 3,
							Image = "circle-alert",
						})
					else
						Rayfield:Notify({
							Title = "Warning",
							Content = savedItem.id .. " is off-sale or invalid",
							Duration = 3,
							Image = "circle-alert",
						})
					end
				end
			end
		end
		if #missing == 0 then
			Rayfield:Notify({
				Title = "Info",
				Content = "No missing items found (or all skipped). Skipped: " .. skipped,
				Duration = 5,
				Image = "info",
			})
			updatestatus("Idle")
			updateprog("-")
			updateitem("-")

			return
		end
		Rayfield:Notify({
			Title = "Fixing",
			Content = "Attempting to place " .. #missing .. " missing items...",
			Duration = 5,
			Image = "loader",
		})
		if #missing > 0 then
			placeFurnitures(missing, true)
		end
		if stopFlag then
			updatestatus("Stopped")
			updateprog("-")
			updateitem("-")
			return
		end
		-- Activate furniture
		local success, interior = pcall(function()
			return cd.get("house_interior")
		end)
		if success and interior and interior.furniture then
			for i, v in pairs(interior.furniture) do
				if stopFlag then
					break
				end
				if v.text then
					pcall(function()
						router
							.get("HousingAPI/ActivateFurniture")
							:InvokeServer(plr, i, "UseBlock", v.text, plr.Character)
					end)
				elseif v.outfit_name then
					pcall(function()
						router.get("AvatarAPI/StartEditingMannequin"):InvokeServer(v.outfit)
						router.get("HousingAPI/ActivateFurniture"):InvokeServer(plr, i, "UseBlock", {
							save_outfit = true,
							outfit_name = "Outfit",
						}, plr.Character)
					end)
				end
			end
		end
		Rayfield:Notify({
			Title = "Success",
			Content = "Fix attempt completed!",
			Duration = 3,
			Image = "circle-check",
		})
		updatestatus("Idle")
		updateprog("-")
		updateitem("-")
	end

	-- // Paste init
	local function pastehouseinit(mode)
		stopFlag = false

		if not savedhouse then
			return Rayfield:Notify({
				Title = "Error",
				Content = "No house has been saved",
				Duration = 3,
				Image = "circle-alert",
			})
		end

		local success, houseInterior = pcall(function()
			return cd.get("house_interior")
		end)

		if not success or not houseInterior or not houseInterior.player or houseInterior.player ~= plr then
			return Rayfield:Notify({
				Title = "Error",
				Content = "Please enter your house to paste the house",
				Duration = 3,
				Image = "circle-alert",
			})
		end

		-- 🔧 Resolve any house type to canonical kind
		local function resolveType(typeValue)
			if not typeValue or typeValue == "-" or typeValue == "Unknown" then
				return nil
			end

			for kind, data in pairs(housedb) do
				if kind == typeValue then
					return kind
				end

				if data.name and string.lower(data.name) == string.lower(typeValue) then
					return kind
				end

				if data.building_type and data.building_type == typeValue then
					return kind
				end

				if data.type and data.type == typeValue then
					return kind
				end
			end

			return typeValue
		end

		-- 🧠 Get display name
		local function getDisplayName(kind)
			for k, data in pairs(housedb) do
				if k == kind then
					return data.name or kind
				end
			end
			return kind
		end

		-- ✅ SMART COMPARISON (fixes your bug)
		local function isSameHouseType(a, b)
			if a == b then
				return true
			end

			local function getName(val)
				for kind, data in pairs(housedb) do
					if kind == val then
						return data.name
					end
					if data.name and string.lower(data.name) == string.lower(val) then
						return data.name
					end
				end
				return tostring(val)
			end

			local nameA = getName(a)
			local nameB = getName(b)

			return string.lower(nameA) == string.lower(nameB)
		end

		-- 📦 Get types
		local savedType = "-"
		local currentType = "-"
		local savedKind = nil
		local savedName = nil

		pcall(function()
			savedType = savedhouse.building_type or "-"
			savedKind = savedhouse.kind
			savedName = savedhouse.name
		end)

		pcall(function()
			currentType = houseInterior.building_type or "-"
		end)

		-- 🔁 Resolve saved type
		local resolvedSaved = resolveType(savedType)

		if not resolvedSaved then
			if savedKind then
				resolvedSaved = resolveType(savedKind)
			end
			if not resolvedSaved and savedName then
				resolvedSaved = resolveType(savedName)
			end
		end

		-- 🔁 Resolve current type
		local resolvedCurrent = resolveType(currentType)

		-- ✅ FINAL CHECK (FIXED)
		if not IgnoreTypeCheck.CurrentValue then
			if not isSameHouseType(resolvedSaved, resolvedCurrent) then
				return Rayfield:Notify({
					Title = "Error",
					Content = "House types do not match!\nSaved: "
						.. tostring(getDisplayName(resolvedSaved))
						.. "\nCurrent: "
						.. tostring(getDisplayName(resolvedCurrent))
						.. "\n\nEnable 'Ignore House Type' to force paste.",
					Duration = 6,
					Image = "circle-alert",
				})
			end
		end

		-- 🚀 Continue
		Rayfield:Notify({
			Title = "Loading",
			Content = "Clearing house",
			Duration = 3,
			Image = "loader",
		})

		updatestatus("Clearing House")

		-- 🧹 Clear house
		for i, _ in pairs(houseInterior.furniture or {}) do
			if stopFlag then
				break
			end

			local args = {
				true,
				{ i },
				"sell",
			}

			pcall(function()
				router.get("HousingAPI/SellFurniture"):FireServer(unpack(args))
			end)
		end

		task.wait(0.1)

		if stopFlag then
			updatestatus("Stopped")
			updateprog("-")
			updateitem("-")
			return
		end

		-- 🏗 Paste
		if mode == "slow" then
			task.spawn(pastehouseslow)
		else
			task.spawn(pastehousefast)
		end
	end

	Tab:CreateButton({
		Name = "Place House Fast",
		Callback = function()
			pastehouseinit("fast")
		end,
	})
	Tab:CreateButton({
		Name = "Place House Slow",
		Callback = function()
			pastehouseinit("slow")
		end,
	})
	Tab:CreateButton({
		Name = "Fix Missing Items",
		Callback = fixMissing,
	})

	Tab:CreateButton({
		Name = "Stop All",
		Callback = function()
			stopFlag = true
			updatestatus("Stopped")
			updateprog("-")
			updateitem("-")
			Rayfield:Notify({
				Title = "Stopped",
				Content = "All processes stopped",
				Duration = 3,
				Image = "circle-check",
			})
		end,
	})

	Tab:CreateSection("Trade Functions")
	Tab:CreateButton({
		Name = "List House for Trade",
		Callback = function()
			local success, house = pcall(function()
				return cd.get("house_interior")
			end)
			if not success then
				Rayfield:Notify({
					Title = "Error",
					Content = "Failed to access house data",
					Duration = 3,
					Image = "circle-alert",
				})
				return
			end
			pcall(function()
				router.get("HousingAPI/ListHouse"):InvokeServer()
			end)
			Rayfield:Notify({
				Title = "Success",
				Content = "House listed for trade.",
				Duration = 3,
				Image = "circle-check",
			})
		end,
	})
	Tab:CreateButton({
		Name = "Unlist House for Trade",
		Callback = function()
			local success, house = pcall(function()
				return cd.get("house_interior")
			end)
			if not success then
				Rayfield:Notify({
					Title = "Error",
					Content = "Failed to access house data",
					Duration = 3,
					Image = "circle-alert",
				})
				return
			end
			-- Removed the strict check for being inside the house; now it works even outside
			pcall(function()
				router.get("HousingAPI/UnlistHouse"):InvokeServer()
			end)
			Rayfield:Notify({
				Title = "Success",
				Content = "House unlisted from trade.",
				Duration = 3,
				Image = "circle-check",
			})
		end,
	})

	local tradeSection = Tab:CreateSection("Auto Accept Trade Requests")

	local autoTradeEnabled = false
	local selectedPlayer = nil

	local TradeRequestEvent = router.get_event("TradeAPI/TradeRequestReceived")

	--// SAFE PLAYER RESOLVER
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

	--// GET PLAYERS (None always first)
	local function getPlayers()
		local t = { "None" }

		for _, plr in ipairs(Players:GetPlayers()) do
			if plr ~= Players.LocalPlayer then
				table.insert(t, plr.Name)
			end
		end

		if #t == 1 then
			table.insert(t, "No Players Online")
		end

		return t
	end

	--// DROPDOWN
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

	--// REFRESH FUNCTION
	local function refreshPlayers()
		local players = getPlayers()

		pcall(function()
			PlayerDropdown:Refresh(players)
		end)

		-- Keep current selection if still valid, otherwise stay on None
		if not selectedPlayer or not table.find(players, selectedPlayer) then
			selectedPlayer = nil
			PlayerDropdown:Set("None")
		end
	end

	--// INPUT - FIXED (no longer forces dropdown to show typed name)
	Tab:CreateInput({
		Name = "Type Player Name",
		PlaceholderText = "Enter username...",
		RemoveTextAfterFocusLost = false,
		Callback = function(text)
			if text ~= "" then
				selectedPlayer = text
				Rayfield:Notify({
					Title = "Player Set",
					Content = "Now accepting: " .. text,
					Duration = 3,
				})
				-- Removed PlayerDropdown:Set(text) ← this was causing "None" to appear
			else
				selectedPlayer = nil
				PlayerDropdown:Set("None")
			end
		end,
	})

	--// REFRESH BUTTON
	Tab:CreateButton({
		Name = "Refresh Players",
		Callback = function()
			refreshPlayers()
			Rayfield:Notify({
				Title = "Players Refreshed",
				Content = "List updated",
				Duration = 3,
			})
		end,
	})

	--// EVENT LISTENER
	TradeRequestEvent.OnClientEvent:Connect(function(...)
		if not autoTradeEnabled then
			return
		end
		if not selectedPlayer then
			return
		end

		local args = { ... }
		local player = resolvePlayer(args[1])

		if player and string.lower(player.Name) == string.lower(selectedPlayer) then
			local remote = router.get("TradeAPI/AcceptOrDeclineTradeRequest")
			if remote then
				pcall(function()
					remote:FireServer(player, true)
				end)
				pcall(function()
					remote:InvokeServer(player, true)
				end)
				pcall(function()
					remote:FireServer(true)
				end)
			end
		end
	end)

	--// AUTO NEGOTIATE LOOP
	task.spawn(function()
		while true do
			task.wait(0.5)
			if autoTradeEnabled and selectedPlayer then
				pcall(function()
					router.get("TradeAPI/AcceptNegotiation"):FireServer()
				end)
				task.wait(0.5)
				pcall(function()
					router.get("TradeAPI/ConfirmTrade"):FireServer()
				end)
			end
		end
	end)

	--// TOGGLE
	Tab:CreateToggle({
		Name = "Auto Accept Player",
		CurrentValue = false,
		Callback = function(val)
			autoTradeEnabled = val
			Rayfield:Notify({
				Title = "Auto Trade",
				Content = val and ("Enabled for: " .. (selectedPlayer or "None")) or "Disabled",
				Duration = 3,
			})
		end,
	})

	--// AUTO UPDATE
	Players.PlayerAdded:Connect(function()
		task.wait(0.3)
		refreshPlayers()
	end)

	Players.PlayerRemoving:Connect(function()
		task.wait(0.3)
		refreshPlayers()
	end)

	local PastebinTab = Window:CreateTab("Pastebin", "clipboard")
	local userPastebinDevKey = ""
	local userPastebinUsername = ""
	local userPastebinPassword = ""
	local function serialize(value)
		local t = typeof(value)
		if t == "CFrame" then
			return { value:GetComponents() }
		elseif t == "Vector3" then
			return { value.X, value.Y, value.Z }
		elseif t == "Color3" then
			return { value.R, value.G, value.B }
		elseif t == "Instance" then
			return nil
		elseif t == "table" then
			local out = {}
			for k, v in pairs(value) do
				local sv = serialize(v)
				if sv ~= nil then
					out[k] = sv
				end
			end
			return out
		end
		return value
	end
	local function deserialize(value)
		if type(value) ~= "table" then
			return value
		end
		if #value > 0 then
			if #value == 3 and type(value[1]) == "number" then
				return Color3.new(unpack(value))
			elseif #value == 12 and type(value[1]) == "number" then
				return CFrame.new(unpack(value))
			end
		end
		-- Added handling for object-style color tables {r=..., g=..., b=...} or {R=..., G=..., B=...}
		if
			value.r
			and value.g
			and value.b
			and type(value.r) == "number"
			and type(value.g) == "number"
			and type(value.b) == "number"
		then
			return Color3.new(value.r, value.g, value.b)
		end
		if
			value.R
			and value.G
			and value.B
			and type(value.R) == "number"
			and type(value.G) == "number"
			and type(value.B) == "number"
		then
			return Color3.new(value.R, value.G, value.B)
		end
		if value.__type == "CFrame" then
			return CFrame.new(unpack(value.components))
		elseif value.__type == "Vector3" then
			return Vector3.new(value.x, value.y, value.z)
		elseif value.__type == "Color3" then
			return Color3.new(value.r, value.g, value.b)
		end
		for k, v in pairs(value) do
			value[k] = deserialize(v)
		end
		return value
	end
	--==================================================
	-- PASTEBIN LOGIN
	--==================================================
	local function getUserKey(devKey, username, password)
		if not devKey or not username or not password then
			return nil
		end
		local data = {
			api_dev_key = devKey,
			api_user_name = username,
			api_user_password = password,
		}
		local encoded = ""
		for k, v in pairs(data) do
			encoded ..= k .. "=" .. HttpService:UrlEncode(tostring(v)) .. "&"
		end
		encoded = encoded:sub(1, -2)
		local response = HttpService:RequestAsync({
			Url = "https://pastebin.com/api/api_login.php",
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/x-www-form-urlencoded",
			},
			Body = encoded,
		})
		if response and response.StatusCode == 200 and not response.Body:find("Bad API request") then
			return response.Body
		end
		return nil
	end
	--==================================================
	-- PASTEBIN API (USER DEV KEY ONLY)
	--==================================================
	local function createPaste(content, name, devKey, userKey)
		if not devKey or devKey == "" then
			return nil, "NO_DEV_KEY"
		end
		local data = {
			api_dev_key = devKey,
			api_option = "paste",
			api_paste_code = content,
			api_paste_name = name or "CubixHouse",
			api_paste_private = "1",
			api_paste_format = "text",
			api_paste_expire_date = "N",
		}
		if userKey then
			data.api_user_key = userKey
		end
		local encoded = ""
		for k, v in pairs(data) do
			encoded ..= k .. "=" .. HttpService:UrlEncode(tostring(v)) .. "&"
		end
		encoded = encoded:sub(1, -2)
		local response = HttpService:RequestAsync({
			Url = "https://pastebin.com/api/api_post.php",
			Method = "POST",
			Headers = {
				["Content-Type"] = "application/x-www-form-urlencoded",
			},
			Body = encoded,
		})
		return response and response.Body
	end
	-- Function to convert other cloner JSON format to internal savedhouse format
	local function convertToInternalFormat(decoded)
		if decoded.f and type(decoded.f) == "table" and #decoded.f > 0 and decoded.t and decoded.b then
			-- New format support
			local furniture = {}
			for i, f in ipairs(decoded.f) do
				local colors = {}
				for ck, cv in pairs(f.cl or {}) do
					colors[tonumber(ck)] = cv -- cv is [r,g,b]
				end
				furniture[tostring(i)] = {
					id = f.i,
					cframe = f.c,
					colors = colors,
					scale = f.s,
				}
			end
			decoded.furniture = furniture
			decoded.f = nil
			local textures = {}
			for _, t in pairs(decoded.t or {}) do
				local room = t.r
				if not textures[room] then
					textures[room] = {}
				end
				if t.k == "walls" then
					textures[room].walls = t.i
				elseif t.k == "floors" then
					textures[room].floors = t.i
				end
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
		if decoded.BuildType then
			decoded.building_type = decoded.BuildType
			decoded.BuildType = nil
		end
		-- Ignore ExData as costs are recalculated internally
		if decoded.furnitures and #decoded.furnitures > 0 then
			local function convertColors(obj)
				if type(obj) ~= "table" then
					return obj
				end
				if obj.__isColor then
					return { __type = "Color3", r = obj.r, g = obj.g, b = obj.b }
				end
				for k, v in pairs(obj) do
					obj[k] = convertColors(v)
				end
				return obj
			end
			local furniture = {}
			for i, f in ipairs(decoded.furnitures) do
				local colors = {}
				for ck, cv in pairs(f.colors or {}) do
					colors[ck] = cv
				end
				furniture[tostring(i)] = {
					id = f.id,
					cframe = f.cframe,
					colors = colors,
					scale = f.scale,
				}
			end
			decoded.furniture = furniture
			decoded.furnitures = nil
			local textures = {}
			for _, t in ipairs(decoded.textures or {}) do
				if not textures[t.room] then
					textures[t.room] = {}
				end
				if t.type == "walls" then
					textures[t.room].walls = t.id
				elseif t.type == "floors" then
					textures[t.room].floors = t.id
				end
			end
			decoded.textures = textures
			if decoded.ambiance then
				decoded.ambiance = convertColors(decoded.ambiance)
			end
		elseif type(decoded.furniture) == "table" then
			for key, item in pairs(decoded.furniture) do
				local new_colors = {}
				for i, col in ipairs(item.colors or {}) do
					new_colors[i] = col
				end
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
	local informationLabel = PastebinTab:CreateLabel(
		"TO GET DEV API KEY YOU NEED TO MAKE ACCOUNT ON PASTEBIN AFTER THAT GO TO https://pastebin.com/doc_api AND COPY YOUR DEV API KEY",
		"info"
	)
	local divider = PastebinTab:CreateDivider()
	PastebinTab:CreateInput({
		Name = "Pastebin Dev API Key (Required)",
		PlaceholderText = "Paste ONLY the API key (not a link)",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			-- sanitize common copy-paste mistakes
			value = tostring(value)
				:gsub("%s+", "")
				:gsub("YouruniquedeveloperAPIkey:", "")
				:gsub("Your%w+developer%w+API%w+key:", "")
			userPastebinDevKey = value
		end,
	})
	PastebinTab:CreateInput({
		Name = "Pastebin Username",
		PlaceholderText = "Your Pastebin username",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			userPastebinUsername = value
		end,
	})
	PastebinTab:CreateInput({
		Name = "Pastebin Password",
		PlaceholderText = "Your Pastebin password",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			userPastebinPassword = value
		end,
	})
	local pasteNameInput = PastebinTab:CreateInput({
		Name = "House Name for Pastebin",
		PlaceholderText = "Enter house name (optional)",
		RemoveTextAfterFocusLost = false,
		Callback = function() end,
	})
	--==================================================
	-- LOAD HOUSE FROM PASTEBIN (NOW AUTO-LOADED ON ENTER)
	--==================================================
	local function LoadHouseFromPastebin(pasteValue)
		local input = tostring(pasteValue or ""):gsub("%s+", "") -- clean whitespace
		if input == "" then
			return Rayfield:Notify({
				Title = "Error",
				Content = "Please enter a Pastebin link or ID",
				Duration = 3,
			})
		end

		local pasteId = input:match("pastebin%.com/(.+)")
		if pasteId then
			pasteId = pasteId:gsub("raw/", "")
		else
			pasteId = input
		end

		local response
		local success = pcall(function()
			response = HttpService:RequestAsync({
				Url = "https://pastebin.com/raw/" .. pasteId,
				Method = "GET",
			})
			if response then
				response.Body = response.Body or ""
			end
		end)

		if not success or not response or not response.Body then
			return Rayfield:Notify({
				Title = "Error",
				Content = "Failed to fetch Pastebin data",
				Duration = 3,
			})
		end

		local ok, decoded = pcall(function()
			return HttpService:JSONDecode(response.Body)
		end)
		if not ok or type(decoded) ~= "table" then
			return Rayfield:Notify({
				Title = "Error",
				Content = "Invalid Pastebin JSON",
				Duration = 3,
			})
		end

		-- Convert if it's the other cloner format
		decoded = convertToInternalFormat(decoded)
		savedhouse = deserialize(decoded)

		local furniturecost = 0
		for _, v in pairs(savedhouse.furniture or {}) do
			if furnituresdb[v.id] then
				furniturecost += furnituresdb[v.id].cost or 0
			end
		end
		local texturecost = 0
		for _, v in pairs(savedhouse.textures or {}) do
			if texturesdb.walls[v.walls] then
				texturecost += texturesdb.walls[v.walls].cost or 0
			end
			if texturesdb.floors[v.floors] then
				texturecost += texturesdb.floors[v.floors].cost or 0
			end
		end
		local t_count = counttextures(savedhouse.textures)
		local amb = savedhouse.ambiance and "Yes" or "No"
		local typ = savedhouse.building_type or "-"
		task.spawn(setscaninfo, countfurnitures(savedhouse.furniture), furniturecost, t_count, texturecost, amb, typ)

		Rayfield:Notify({
			Title = "Success",
			Content = "House loaded from Pastebin",
			Duration = 3,
			Image = "circle-check",
		})
	end

	PastebinTab:CreateInput({
		Name = "Pastebin Link / ID",
		PlaceholderText = "https://pastebin.com/xxxxxx or xxxxxx",
		RemoveTextAfterFocusLost = true,
		WaitTime = 2, -- wait for user to finish pasting
		Callback = function(value)
			LoadHouseFromPastebin(value)
		end,
	})

	--==================================================
	-- SAVE HOUSE TO PASTEBIN (unchanged)
	--==================================================
	PastebinTab:CreateButton({
		Name = "Save House to Pastebin",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({
					Title = "Error",
					Content = "No house has been scanned or loaded",
					Duration = 3,
				})
			end
			-- hard format validation
			if #userPastebinDevKey < 20 or not userPastebinDevKey:match("^[%w]+$") then
				return Rayfield:Notify({
					Title = "Invalid API Key",
					Content = "Paste ONLY the Pastebin Dev API key.\nDo not paste a URL.",
					Duration = 5,
				})
			end
			local clean_house = deepCopy(savedhouse)
			local furniturecost = 0
			for _, v in pairs(clean_house.furniture or {}) do
				if furnituresdb[v.id] then
					furniturecost += furnituresdb[v.id].cost or 0
				end
				v.hash = nil
				v.was_free = nil
				v.no_value = nil
				v.was_default = nil
				v.item_category = nil
				v.item_kind = nil
				v.occupied = v.occupied or nil
				v.door_position = nil
				v.last_position = nil
				v.on = nil
				local new_colors = {}
				for i, col in ipairs(v.colors or {}) do
					new_colors[i] = { col.R, col.G, col.B }
				end
				v.colors = new_colors
				if typeof(v.cframe) == "CFrame" then
					v.cframe = { v.cframe:GetComponents() }
				end
			end
			local texturecost = 0
			for _, v in pairs(clean_house.textures or {}) do
				if texturesdb.walls[v.walls] then
					texturecost += texturesdb.walls[v.walls].cost or 0
				end
				if texturesdb.floors[v.floors] then
					texturecost += texturesdb.floors[v.floors].cost or 0
				end
			end
			clean_house.total_cost = furniturecost + texturecost
			clean_house.furniture_quantity = countfurnitures(clean_house.furniture)
			if clean_house.building_type == "micro_2023" then
				clean_house.building_type = "Tiny Home"
			end
			clean_house.saved_by = "Cubix-HouseCloner"
			clean_house.properties = nil
			clean_house.house_id = nil
			clean_house.listed_for_trade = nil
			clean_house.unique = nil
			clean_house.active_addons = nil
			clean_house.allows_coop_building = nil
			clean_house.house_pos = nil
			clean_house.textures_hash = nil
			clean_house.player = nil
			clean_house.music = nil
			local function convert_colors_recursive(tbl)
				if type(tbl) ~= "table" then
					return tbl
				end
				for k, v in pairs(tbl) do
					if typeof(v) == "Color3" then
						tbl[k] = { v.R, v.G, v.B }
					elseif typeof(v) == "CFrame" then
						tbl[k] = { v:GetComponents() }
					elseif type(v) == "table" then
						tbl[k] = convert_colors_recursive(v)
					end
				end
				return tbl
			end
			if clean_house.ambiance then
				clean_house.ambiance = convert_colors_recursive(clean_house.ambiance)
			end
			local ok, encoded = pcall(function()
				return HttpService:JSONEncode(clean_house)
			end)
			if not ok then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Failed to encode house data",
					Duration = 3,
				})
			end
			local apiUserKey = getUserKey(userPastebinDevKey, userPastebinUsername, userPastebinPassword)
			if not apiUserKey then
				Rayfield:Notify({
					Title = "Warning",
					Content = "Failed to login to Pastebin, posting as guest",
					Duration = 3,
				})
			end
			local inputtedName = pasteNameInput.CurrentValue or ""
			local pasteName = "CubixHouse" .. (inputtedName ~= "" and "_" .. inputtedName or "")
			local result, err = createPaste(encoded, pasteName, userPastebinDevKey, apiUserKey)
			if err == "NO_DEV_KEY" or not result or result:find("Bad API request") then
				return Rayfield:Notify({
					Title = "Pastebin Error",
					Content = tostring(result),
					Duration = 6,
				})
			end
			if setclipboard then
				setclipboard(result)
			end
			Rayfield:Notify({
				Title = "Success",
				Content = "House saved to Pastebin\nLink copied to clipboard",
				Duration = 8,
			})
		end,
	})

	local CreateFileTab = Window:CreateTab("Create File", "folder")

	-- Ensure folder exists
	if not isfolder("HouseFS") then
		makefolder("HouseFS")
	end

	-- UI Section
	local FileSection = CreateFileTab:CreateSection("Saved Houses")

	-- Dropdown for saved houses
	local fileDropdown = CreateFileTab:CreateDropdown({
		Name = "Select Saved House",
		Options = {},
		CurrentOption = nil,
		MultipleOptions = false,
		Flag = "FileDropdown",
		Callback = function(_) end,
	})

	-- Input for new save
	local saveInput = CreateFileTab:CreateInput({
		Name = "Save As",
		PlaceholderText = "Enter File Name",
		RemoveTextAfterFocusLost = false,
		Callback = function(_) end,
	})

	-- Variable to remember what file is currently selected
	local pendingDelete = nil
	local fileSearchQuery = ""
	local allFilesCache = {}

	-- ==================== IMPROVED NATURAL SORT (CASE-INSENSITIVE A-Z) ====================
	-- Now sorts A-Z regardless of uppercase/lowercase (House, house, HOUSE all treated the same)
	local function naturalSort(a, b)
		local function pad(n)
			return ("%010d"):format(tonumber(n) or 0)
		end
		-- Convert both to lowercase for true A-Z sorting
		local la = a:lower()
		local lb = b:lower()
		local na = la:gsub("%d+", pad)
		local nb = lb:gsub("%d+", pad)
		return na < nb
	end

	-- Utility: refresh dropdown (sorted naturally + case-insensitive + keeps selection)
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

		-- cache ALL files for search
		allFilesCache = validFiles

		-- apply search filter
		local filtered = {}
		for _, name in ipairs(allFilesCache) do
			if fileSearchQuery == "" or string.find(string.lower(name), string.lower(fileSearchQuery), 1, true) then
				table.insert(filtered, name)
			end
		end

		local currentlySelected = fileDropdown.CurrentOption
		if type(currentlySelected) == "table" then
			currentlySelected = currentlySelected[1]
		end

		fileDropdown:Refresh(filtered)

		if currentlySelected and table.find(filtered, currentlySelected) then
			fileDropdown:Set(currentlySelected)
		elseif #filtered > 0 then
			fileDropdown:Set(filtered[1])
		else
			fileDropdown:Set(nil)
		end
	end

	-- Initial refresh
	refreshFileDropdown()

	local searchInput = CreateFileTab:CreateInput({
		Name = "Search Files",
		PlaceholderText = "Type to search house files...",
		RemoveTextAfterFocusLost = false,
		Callback = function(value)
			fileSearchQuery = tostring(value or "")
			refreshFileDropdown()
		end,
	})

	-- Button: Save House
	CreateFileTab:CreateButton({
		Name = "Save House to File",
		Callback = function()
			if not savedhouse then
				return Rayfield:Notify({
					Title = "Error",
					Content = "No house has been scanned or loaded",
					Duration = 3,
					Image = "circle-alert",
				})
			end
			local filename = saveInput.CurrentValue
			if not filename or filename == "" then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Please enter a valid filename",
					Duration = 3,
					Image = "circle-alert",
				})
			end

			local clean_house = deepCopy(savedhouse)
			local furniturecost = 0
			for _, v in pairs(clean_house.furniture or {}) do
				if furnituresdb[v.id] then
					furniturecost += furnituresdb[v.id].cost or 0
				end
				v.hash = nil
				v.was_free = nil
				v.no_value = nil
				v.was_default = nil
				v.item_category = nil
				v.item_kind = nil
				v.occupied = v.occupied or nil
				v.door_position = nil
				v.last_position = nil
				v.on = nil
				local new_colors = {}
				for i, col in ipairs(v.colors or {}) do
					new_colors[i] = { col.R, col.G, col.B }
				end
				v.colors = new_colors
				if typeof(v.cframe) == "CFrame" then
					v.cframe = { v.cframe:GetComponents() }
				end
			end
			local texturecost = 0
			for _, v in pairs(clean_house.textures or {}) do
				if texturesdb.walls[v.walls] then
					texturecost += texturesdb.walls[v.walls].cost or 0
				end
				if texturesdb.floors[v.floors] then
					texturecost += texturesdb.floors[v.floors].cost or 0
				end
			end
			clean_house.total_cost = furniturecost + texturecost
			clean_house.furniture_quantity = countfurnitures(clean_house.furniture)
			if clean_house.building_type == "micro_2023" then
				clean_house.building_type = "Tiny Home"
			end
			clean_house.saved_by = "Cubix-HouseCloner"
			clean_house.properties = nil
			clean_house.house_id = nil
			clean_house.listed_for_trade = nil
			clean_house.unique = nil
			clean_house.active_addons = nil
			clean_house.allows_coop_building = nil
			clean_house.house_pos = nil
			clean_house.textures_hash = nil
			clean_house.player = nil
			clean_house.music = nil

			local function convert_colors_recursive(tbl)
				if type(tbl) ~= "table" then
					return tbl
				end
				for k, v in pairs(tbl) do
					if typeof(v) == "Color3" then
						tbl[k] = { v.R, v.G, v.B }
					elseif typeof(v) == "CFrame" then
						tbl[k] = { v:GetComponents() }
					elseif type(v) == "table" then
						tbl[k] = convert_colors_recursive(v)
					end
				end
				return tbl
			end
			if clean_house.ambiance then
				clean_house.ambiance = convert_colors_recursive(clean_house.ambiance)
			end

			local success, encoded = pcall(function()
				return HttpService:JSONEncode(clean_house)
			end)
			if not success then
				return Rayfield:Notify({
					Title = "Error",
					Content = "Failed to encode house data",
					Duration = 3,
					Image = "circle-alert",
				})
			end

			writefile("HouseFS/" .. filename .. ".json", encoded)
			refreshFileDropdown()
			Rayfield:Notify({
				Title = "Success",
				Content = "House saved: " .. filename .. ".json",
				Duration = 3,
				Image = "circle-check",
			})
		end,
	})

	-- Convert function (unchanged)
	local function convertToInternalFormat(decoded)
		if decoded.Furniture then
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
		if decoded.BuildType then
			decoded.building_type = decoded.BuildType
			decoded.BuildType = nil
		end

		if decoded.furnitures and #decoded.furnitures > 0 then
			local function convertColors(obj)
				if type(obj) ~= "table" then
					return obj
				end
				if obj.__isColor then
					return { __type = "Color3", r = obj.r, g = obj.g, b = obj.b }
				end
				for k, v in pairs(obj) do
					obj[k] = convertColors(v)
				end
				return obj
			end
			local furniture = {}
			for i, f in ipairs(decoded.furnitures) do
				local colors = {}
				for ck, cv in pairs(f.colors or {}) do
					colors[ck] = cv
				end
				furniture[tostring(i)] = { id = f.id, cframe = f.cframe, colors = colors, scale = f.scale }
			end
			decoded.furniture = furniture
			decoded.furnitures = nil
			local textures = {}
			for _, t in ipairs(decoded.textures or {}) do
				if not textures[t.room] then
					textures[t.room] = {}
				end
				if t.type == "walls" then
					textures[t.room].walls = t.id
				elseif t.type == "floors" then
					textures[t.room].floors = t.id
				end
			end
			decoded.textures = textures
			if decoded.ambiance then
				decoded.ambiance = convertColors(decoded.ambiance)
			end
		elseif type(decoded.furniture) == "table" then
			for key, item in pairs(decoded.furniture) do
				local new_colors = {}
				for i, col in ipairs(item.colors or {}) do
					new_colors[i] = col
				end
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

	-- Button: Load House (keeps selection)
	CreateFileTab:CreateButton({
		Name = "Load House from File",
		Callback = function()
			local selected = fileDropdown.CurrentOption
			if type(selected) == "table" then
				selected = selected[1]
			end
			if not selected or selected == "" then
				return Rayfield:Notify({ Title = "Error", Content = "No file selected to load", Duration = 3 })
			end

			local filePath = "HouseFS/" .. selected
			local success, content = pcall(readfile, filePath)
			if not success or not content then
				return Rayfield:Notify({ Title = "Error", Content = "Failed to read file: " .. selected, Duration = 3 })
			end

			local decoded
			local ok, err = pcall(function()
				decoded = HttpService:JSONDecode(content)
			end)
			if not ok then
				local env = {
					Vector3 = {
						new = function(x, y, z)
							return { __type = "Vector3", X = x, Y = y, Z = z }
						end,
					},
					Color3 = {
						new = function(r, g, b)
							return { __type = "Color3", R = r, G = g, B = b }
						end,
					},
					CFrame = {
						new = function(...)
							return { __type = "CFrame", components = { ... } }
						end,
					},
				}
				local func, loaderr = loadstring(content)
				if not func then
					return Rayfield:Notify({
						Title = "Error",
						Content = "Loadstring error: " .. tostring(loaderr),
						Duration = 3,
					})
				end
				setfenv(func, env)
				local runok, data = pcall(func)
				if not runok then
					return Rayfield:Notify({ Title = "Error", Content = "Run error: " .. tostring(data), Duration = 3 })
				end
				decoded = data
			end

			if type(decoded) ~= "table" then
				return Rayfield:Notify({ Title = "Error", Content = "Invalid data in file: " .. selected, Duration = 3 })
			end

			decoded = convertToInternalFormat(decoded)
			savedhouse = deserialize(decoded)

			local furniturecost = 0
			for _, v in pairs(savedhouse.furniture or {}) do
				if furnituresdb[v.id] then
					furniturecost += furnituresdb[v.id].cost or 0
				end
			end
			local texturecost = 0
			for _, v in pairs(savedhouse.textures or {}) do
				if texturesdb.walls[v.walls] then
					texturecost += texturesdb.walls[v.walls].cost or 0
				end
				if texturesdb.floors[v.floors] then
					texturecost += texturesdb.floors[v.floors].cost or 0
				end
			end
			local t_count = counttextures(savedhouse.textures)
			local amb = savedhouse.ambiance and "Yes" or "No"
			local typ = savedhouse.building_type or "-"
			task.spawn(
				setscaninfo,
				countfurnitures(savedhouse.furniture),
				furniturecost,
				t_count,
				texturecost,
				amb,
				typ
			)

			Rayfield:Notify({ Title = "Success", Content = "House loaded from file: " .. selected, Duration = 3 })
			refreshFileDropdown()
		end,
	})

	-- Button: Delete House (with confirmation)
	CreateFileTab:CreateButton({
		Name = "Delete Selected House",
		Callback = function()
			local selected = fileDropdown.CurrentOption
			if type(selected) == "table" then
				selected = selected[1]
			end
			if not selected or selected == "" then
				return Rayfield:Notify({ Title = "Error", Content = "No house selected to delete.", Duration = 3 })
			end

			if pendingDelete == selected then
				local filePath = "HouseFS/" .. selected
				if isfile(filePath) then
					delfile(filePath)
					Rayfield:Notify({
						Title = "Deleted",
						Content = selected .. " has been deleted.",
						Duration = 3,
						Image = "circle-check",
					})
					pendingDelete = nil
					refreshFileDropdown()
				else
					Rayfield:Notify({ Title = "Error", Content = "File not found: " .. selected, Duration = 3 })
				end
			else
				pendingDelete = selected
				Rayfield:Notify({
					Title = "Confirm Delete",
					Content = "Are you sure you want to delete **"
						.. selected
						.. "**?\n\nClick the Delete button again to confirm.",
					Duration = 10,
					Image = "circle-alert",
				})
			end
		end,
	})

	-- Extra refresh button
	CreateFileTab:CreateButton({
		Name = "Refresh List",
		Callback = function()
			refreshFileDropdown()
			Rayfield:Notify({
				Title = "Refreshed",
				Content = "File list updated and sorted (numbers first)",
				Duration = 2,
			})
		end,
	})

	local Teleport = Window:CreateTab("Teleport", "map-pin")

	-- New section added above the teleport options
	Teleport:CreateSection("House Teleports")

	local function loadinterior(interiortype, name)
		local load = require(game:GetService("ReplicatedStorage").Fsys).load
		local interiors = load("InteriorsM")
		local enter = interiors.enter
		if interiortype == "interior" then
			enter(name, "", {})
			return
		end
		if interiortype == "house" then
			enter("housing", "MainDoor", { house_owner = name })
		end
	end

	local function getplayernames()
		local players = Players:GetPlayers()
		local names = table.create(#players)
		for i, player in ipairs(players) do
			names[i] = player.Name
		end
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

	Players.PlayerAdded:Connect(function()
		selectedplayer:Refresh(getplayernames())
	end)
	Players.PlayerRemoving:Connect(function()
		selectedplayer:Refresh(getplayernames())
	end)

	Teleport:CreateButton({
		Name = "Enter House",
		Callback = function()
			local target = Players:FindFirstChild(selectedplayer.CurrentOption[1])
			if target then
				loadinterior("house", target)
			end
		end,
	})

	Teleport:CreateButton({
		Name = "Teleport to My House",
		Callback = function()
			local lp = Players.LocalPlayer
			if lp then
				loadinterior("house", lp)
			end
		end,
	})
	-- ==================== AUTO REFRESH (Critical Fix) ====================
	task.spawn(function()
		task.wait(2)  -- Give ClientData time to load
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
end

loadMain()

Rayfield:Notify({ Title = "Cubix", Content = "Loaded successfully! Owned houses should now show immediately.", Duration = 5 })
