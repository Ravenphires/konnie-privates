return function(Lib)
local Bridge = Lib.Bridge
local CONFIG  = Lib.CONFIG
local State   = Lib.State

local ESP_CONFIG = {
	ESP                   = false,
	EspBox                = true,
	EspSkeleton           = true,
	EspChams              = false,
	EspHpBar              = true,
	EspWeaponInfo         = true,
	EspActorStatus        = true,
	EspShowSecondary      = true,
	EspShowStance         = true,
	EspShowInventory      = true,
	EspSmooth             = false,
	EspSmoothAlpha        = 1.0,
	EspRenderInterval     = 0.0167,
	EspFullRescanInterval = 30.0,
	EspVisibleCheck       = true,
	EspVisibleStrict      = true,
	EspVisibleInterval    = 0.35,
	EspVisibleCheckNpc    = false,
	EspShowDistance       = true,
	EspShowName           = true,
	EspNpcNameOnly        = true,
	EspSkeletonMaxActors  = 24,
	EspSkeletonMaxDist    = 800,

	ActorSyncBatchSize    = 8,
	EspChamsMaxActors     = 10,

	EspBoxMode            = "Box",
	EspCornerLen          = 0.22,

	EspZombieCluster      = true,
	EspZombieClusterDist  = 8,
	EspZombieClusterMin   = 2,
	EspWeaponPlayersOnly  = false,
	EspIgnoreTeam         = true,
	EspShowPlayers        = true,
	EspShowPlayersInPve   = true,
	ForceShowAllPlayers   = true,
	EspShowFriendly       = true,
	EspShowHostile        = true,
	EspShowZombie         = true,
	EspShowNpc            = true,
	EspShowDead           = true,
	EspNpcStatus          = true,
	EspVisibleBones       = { "Head", "UpperTorso", "LowerTorso" },
	EspBatchSize          = 6,
	ActorEnrichBatchSize  = 4,
	DrawingHighTransparencyMeansVisible = true,
}

for k,v in pairs(ESP_CONFIG) do if CONFIG[k] == nil then CONFIG[k] = v end end

local SKELETON_R15 = {
	{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
	{"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
	{"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
	{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
	{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
}
local SKELETON_R6 = {
	{"Head","Torso"},{"Torso","Right Arm"},{"Torso","Left Arm"},
	{"Torso","Right Leg"},{"Torso","Left Leg"},
}
local ESP_COLORS = {
	team     = Color3.fromRGB(100, 200, 255),
	visible  = Color3.fromRGB(70,  255,  90),
	hidden   = Color3.fromRGB(255,  55,  55),
	teammate = Color3.fromRGB(170, 255, 170),
	dead     = Color3.fromRGB(220,  45,  45),
	self     = Color3.fromRGB(80,  220, 255),
	npc      = Color3.fromRGB(255, 200,  60),
	zombie   = Color3.fromRGB(180, 255,  80),

	hostile  = Color3.fromRGB(255,  50,  50),
	friendly = Color3.fromRGB(80,  220,  80),
	unknown  = Color3.fromRGB(180, 180, 180),
}

State.drawings        = State.drawings        or {}
State.espHighlights   = State.espHighlights   or {}
State.espVisibleCache = State.espVisibleCache or {}
State.espRanked       = nil

State.lastEspUpdate   = 0
State.espRankedTime   = 0
State.espLastActorCount = -1

local espConn = nil

local espWasOn = false

local uiKit = nil
local espFeature = nil

local diagRespawn = nil
local tableField     = Bridge._tableField
local ESP_BOX_PARTS  = {
	"Head", "UpperTorso", "LowerTorso",
	"LeftFoot", "RightFoot",
	"LeftHand", "RightHand",
}

local espPartCache = setmetatable({}, { __mode = "k" })

local HP_OUTLINE_COL = Color3.fromRGB(8, 8, 8)
local HP_BG_COL      = Color3.fromRGB(22, 22, 22)
local function getBodyPart(model, name)
	if not model then return nil end
	local bucket = espPartCache[model]
	if not bucket then
		bucket = { hit = {}, miss = {}, rig = nil }
		espPartCache[model] = bucket
	end
	local hit = bucket.hit[name]
	if hit and hit.Parent == model then return hit end
	local clk = os.clock()
	local mt = bucket.miss[name]
	if mt and clk < mt then return nil end
	local found = model:FindFirstChild(name)
	if found and found:IsA("BasePart") then
		bucket.hit[name] = found
		bucket.miss[name] = nil
		return found
	end
	bucket.miss[name] = clk + 1.0
	return nil
end
Bridge.getEspBodyPart = getBodyPart
local ESP_WEAPON_TEXT = Color3.fromRGB(255, 255, 230)
local ESP_SECONDARY_TEXT = Color3.fromRGB(255, 110, 110)
local ESP_STANCE_CROUCH = Color3.fromRGB(255, 210, 100)
local ESP_STANCE_LYING = Color3.fromRGB(255, 165, 80)
local ESP_INVENTORY_TEXT = Color3.fromRGB(210, 220, 240)
local ESP_STATUS_TEXT = Color3.fromRGB(235, 235, 245)
local ESP_LABEL_SIZE = 14
local ESP_LINE_STEP = 0.52
local ESP_STACK_GAP = 3
local ESP_STATUS_CHIP_MAX = 6
local ESP_STATUS_CHIP_GAP = 2
local ESP_STATUS_KIND_COLORS = {
	weapon = Color3.fromRGB(255, 70, 70),
	combat = Color3.fromRGB(255, 70, 70),
	reload = Color3.fromRGB(255, 160, 45),
	move = Color3.fromRGB(90, 200, 255),
	stance = Color3.fromRGB(190, 170, 255),
	interact = Color3.fromRGB(255, 210, 90),
	gear = Color3.fromRGB(170, 255, 150),
}
local ESP_STATUS_ABBR = {
	Sprinting = "Sprint",
	Aiming = "Aim",
	ADS = "Aim",
	Firing = "Fire",
	Reloading = "Reload",
	Sliding = "Slide",
	Swimming = "Swim",
	Looting = "Loot",
	Dragging = "Drag",
	Dragged = "Dragged",
	Climbing = "Climb",
	Downed = "Down",
	Medical = "Med",
	Lockpick = "Lock",
	Hostage = "Host",
	Takedown = "Take",
	CQB = "CQB",
	Crouching = "Crouch",
	Prone = "Prone",
	Lying = "Lie",
}

function Bridge.shouldEspShowActor(data)
	if not data or data.class == "self" then return false end

	if data.class == "dead" then
		return CONFIG.EspShowDead ~= false and data.player ~= nil
	end
	if data.class == "player" then
		return CONFIG.EspShowPlayers ~= false
	end

	if data.class == "npc_friendly" or data.class == "npc_hostile"
		or data.class == "npc_zombie" or data.class == "npc" then
		local root = data.root
		if root and root.Parent then
			local cam = workspace and workspace.CurrentCamera
			local camPos = cam and cam.CFrame.Position
			if camPos then
				local p = root.Position
				local distSq = (p.X-camPos.X)^2 + (p.Y-camPos.Y)^2 + (p.Z-camPos.Z)^2
				local maxSq = (data.class == "npc_zombie") and (200*200) or (1000*1000)
				if distSq > maxSq then return false end
			end
		end
		if data.class == "npc_friendly" then return CONFIG.EspShowFriendly ~= false end
		if data.class == "npc_hostile" then return CONFIG.EspShowHostile ~= false end
		if data.class == "npc_zombie" then return CONFIG.EspShowZombie ~= false end
		if data.class == "npc" then return CONFIG.EspShowNpc ~= false end
	end
	return true
end

function Bridge.shouldEspHideAsTeammate(data)
	if not CONFIG.EspIgnoreTeam then return false end
	if not data or data.class == "self" or data.class == "dead" then return false end
	if Bridge.isEnemyActor(data) then return false end
	if CONFIG.IgnoreTeammates ~= false then return true end
	if CONFIG.TeamCheck and State.localSquad == nil then return false end
	return Bridge.isTeammateActor(data)
end

function Bridge.getEspColor(data, visible)
	if Bridge.isActorDead(data) or data.class == "dead" then
		return ESP_COLORS.dead
	end
	if data.class == "self" then
		return ESP_COLORS.self
	end
	if Bridge.isTeammateActor(data) then
		return ESP_COLORS.teammate
	end

	if data.class == "npc_hostile" then
		return ESP_COLORS.hostile
	end
	if data.class == "npc_zombie" then
		return ESP_COLORS.zombie
	end
	if data.class == "npc_friendly" then
		return ESP_COLORS.friendly
	end
	if data.class == "npc" then
		return ESP_COLORS.npc
	end

	if CONFIG.EspVisibleCheck then
		return visible and ESP_COLORS.visible or ESP_COLORS.hidden
	end
	if data.class == "player" then
		return ESP_COLORS.hidden
	end
	return ESP_COLORS.unknown
end

function Bridge.resolveActorHealth(data)
	if not data then return nil, nil end

	local now = os.clock()
	if data._healthCache and now - (data._healthCacheT or 0) < 0.2 then
		return data._healthCache[1], data._healthCache[2]
	end
	local actorData = data.actorData
	if not actorData and data.uid then
		actorData = Bridge.getReplicatorActorData(data.uid)
		if actorData then
			data.actorData = actorData
		end
	end
	local function cacheAndReturn(hp, maxHp)
		data._healthCache = {hp, maxHp or 100}
		data._healthCacheT = now
		return hp, maxHp or 100
	end
	if type(actorData) == "table" then
		local hp = tableField(actorData, "Health")
		local maxHp = tableField(actorData, "MaxHealth") or tableField(actorData, "MaxHP")
		if type(hp) == "number" then
			return cacheAndReturn(hp, (type(maxHp) == "number" and maxHp > 0) and maxHp or 100)
		end
	end
	if type(data.health) == "number" then
		local maxHp = data.maxHealth
		if data.class == "npc_zombie" and (type(maxHp) ~= "number" or maxHp <= 0) then
			maxHp = 100
		end
		return cacheAndReturn(data.health, maxHp or 100)
	end
	local model = data.model
	if model then

		local bucket = espPartCache[model]
		local hum = bucket and bucket.hum
		if not (hum and hum.Parent == model) then
			hum = model:FindFirstChildOfClass("Humanoid")
			if hum then
				if not bucket then bucket = { hit = {}, miss = {} }; espPartCache[model] = bucket end
				bucket.hum = hum
			end
		end
		if hum then
			return cacheAndReturn(hum.Health, hum.MaxHealth)
		end
	end
	return nil, nil
end

function Bridge.parseWeaponFromCharacterModel(model)
	if not model or not model.Parent then return nil end
	local wm = model:FindFirstChild("WorldModel")
	local roots = wm and wm:GetChildren() or model:GetChildren()
	for _, child in ipairs(roots) do
		if child:IsA("Model") then
			local n = child.Name
			if type(n) == "string" and string.match(n, "^Firearm") then
				local display = string.gsub(n, "^FirearmPrimary", ""):gsub("^FirearmSecondary", "")
				return { name = display, cur = nil, max = nil }
			end
		end
	end
	return nil
end

function Bridge.getSkeletonPairs(model)
	if not model then return SKELETON_R15 end

	local bucket = espPartCache[model]
	if bucket and bucket.rig then return bucket.rig end
	local pairs
	if getBodyPart(model, "UpperTorso") then pairs = SKELETON_R15
	elseif getBodyPart(model, "Torso") then pairs = SKELETON_R6
	else pairs = SKELETON_R15 end
	bucket = espPartCache[model]
	if bucket then bucket.rig = pairs end
	return pairs
end

function Bridge.hideEspEntry(entry, reason, detail)
	if not entry then return end

	if entry._hidden then return end
	Bridge.logVizHide("ESP", reason or "entry", detail)
	if entry.boxLines then
		for _, line in ipairs(entry.boxLines) do line.Visible = false end
	end
	if entry.skelLines then
		for _, line in ipairs(entry.skelLines) do line.Visible = false end
	end
	if entry.skelShoulderLine then entry.skelShoulderLine.Visible = false end
	if entry.skelHeadCircle then entry.skelHeadCircle.Visible = false end
	if entry.hpBg     then entry.hpBg.Visible      = false end
	if entry.hpFill   then entry.hpFill.Visible     = false end
	if entry.hpOutline then entry.hpOutline.Visible = false end
	if entry.weaponText then entry.weaponText.Visible = false end
	if entry.weaponBg then entry.weaponBg.Visible = false end
	Bridge.hideEspExtraTexts(entry)
	if entry.statusText then entry.statusText.Visible = false end
	if entry.statusBg then entry.statusBg.Visible = false end
	if entry.statusChips then
		for _, chip in ipairs(entry.statusChips) do
			chip.Visible = false
		end
	end
	if entry.text      then entry.text.Visible       = false end

	entry._boxRect = nil

	entry._hidden = true
end

function Bridge.ensureEspDrawing(uid)
	local entry = State.drawings[uid]
	if entry then
		if not entry.hpOutline then
			entry.hpOutline = Drawing.new("Square")
			entry.hpOutline.Filled = false
			entry.hpOutline.Thickness = 1
			entry.hpOutline.Visible = false
			entry.hpOutline.ZIndex = 17
		end
		if not entry.weaponText then
			entry.weaponText = Drawing.new("Text")
			entry.weaponText.Size = ESP_LABEL_SIZE
			entry.weaponText.Outline = true
			entry.weaponText.Center = true
			entry.weaponText.Visible = false
			entry.weaponText.ZIndex = 24
		end
		if not entry.weaponBg then
			entry.weaponBg = Drawing.new("Square")
			entry.weaponBg.Filled = true
			entry.weaponBg.Visible = false
			entry.weaponBg.ZIndex = 22
		end
		if not entry.statusText then
			entry.statusText = Drawing.new("Text")
			entry.statusText.Size = ESP_LABEL_SIZE
			entry.statusText.Outline = true
			entry.statusText.Center = true
			entry.statusText.Visible = false
			entry.statusText.ZIndex = 24
		end
		if not entry.statusBg then
			entry.statusBg = Drawing.new("Square")
			entry.statusBg.Filled = true
			entry.statusBg.Visible = false
			entry.statusBg.ZIndex = 22
		end
		if not entry.skelHeadCircle then
			entry.skelHeadCircle = Drawing.new("Circle")
			entry.skelHeadCircle.Filled = false
			entry.skelHeadCircle.Thickness = 1.4
			entry.skelHeadCircle.NumSides = 16
			entry.skelHeadCircle.Visible = false
			entry.skelHeadCircle.ZIndex = 19
		end
		if not entry.skelShoulderLine then
			entry.skelShoulderLine = Drawing.new("Line")
			entry.skelShoulderLine.Thickness = 1.35
			entry.skelShoulderLine.Visible = false
			entry.skelShoulderLine.ZIndex = 19
		end
		return entry
	end
	entry = {
		boxLines = {},
		skelLines = {},
		skelShoulderLine = Drawing.new("Line"),
		skelHeadCircle = Drawing.new("Circle"),
		text = Drawing.new("Text"),
		statusText = Drawing.new("Text"),
		weaponText = Drawing.new("Text"),
		weaponBg = Drawing.new("Square"),
		statusBg = Drawing.new("Square"),
		hpBg = Drawing.new("Square"),
		hpFill = Drawing.new("Square"),
		hpOutline = Drawing.new("Square"),
	}

	for i = 1, 12 do
		local line = Drawing.new("Line")
		line.Thickness = 1.8
		line.Visible = false
		line.ZIndex = 20
		entry.boxLines[i] = line
	end
	for i = 1, #SKELETON_R15 do
		local line = Drawing.new("Line")
		line.Thickness = 1.4
		line.Visible = false
		line.ZIndex = 19
		entry.skelLines[i] = line
	end
	entry.skelHeadCircle.Filled = false
	entry.skelHeadCircle.Thickness = 1.4
	entry.skelHeadCircle.NumSides = 16
	entry.skelHeadCircle.Visible = false
	entry.skelHeadCircle.ZIndex = 19
	entry.skelShoulderLine.Thickness = 1.35
	entry.skelShoulderLine.Visible = false
	entry.skelShoulderLine.ZIndex = 19
	entry.text.Size = ESP_LABEL_SIZE + 1
	entry.text.Outline = true
	entry.text.Center = true
	entry.text.Visible = false
	entry.text.ZIndex = 22
	entry.statusText.Size = ESP_LABEL_SIZE
	entry.statusText.Outline = true
	entry.statusText.Center = true
	entry.statusText.Visible = false
	entry.statusText.ZIndex = 23
	entry.weaponText.Size = ESP_LABEL_SIZE
	entry.weaponText.Outline = true
	entry.weaponText.Center = true
	entry.weaponText.Visible = false
	entry.weaponText.ZIndex = 23
	entry.hpBg.Filled = true
	entry.hpBg.Visible = false
	entry.hpBg.ZIndex = 18
	entry.hpFill.Filled = true
	entry.hpFill.Visible = false
	entry.hpFill.ZIndex = 19
	entry.hpOutline.Filled = false
	entry.hpOutline.Thickness = 1
	entry.hpOutline.Visible = false
	entry.hpOutline.ZIndex = 17
	State.drawings[uid] = entry
	return entry
end

local function espStripFirearmName(name)
	if type(name) ~= "string" then return "?" end
	name = string.gsub(name, "^FirearmPrimary", "")
	name = string.gsub(name, "^FirearmSecondary", "")
	name = string.gsub(name, "^Melee", "")
	if #name > 18 then
		name = string.sub(name, 1, 16) .. ".."
	end
	return name
end

local function espGetEquippedUid(actor)
	if type(actor) ~= "table" then return nil end
	local eq = tableField(actor, "_equipped")
	if type(eq) ~= "string" or eq == "" then
		local state = tableField(actor, "CurrentState")
		eq = state and tableField(state, "Equip")
	end
	if type(eq) == "string" and eq ~= "" then return eq end
	return nil
end

local function espFindHandlerForUid(actor, uid)
	if type(actor) ~= "table" or type(uid) ~= "string" or uid == "" then return nil end
	local inv = tableField(actor, "_inventory")
	if type(inv) == "table" and type(inv[uid]) == "table" then
		return inv[uid]
	end
	if Bridge.findFirearmHandler then
		return Bridge.findFirearmHandler(actor, uid)
	end
	return nil
end

local function espCollectHotbarWeapons(actor, uid)
	local now = os.clock()
	local cache = State._espHotbarCache
	if uid and cache and cache.uid == uid and cache.t and now - cache.t < 2.0 then
		return cache.rows, cache.eqUid
	end
	local eqUid = espGetEquippedUid(actor)
	local rows = {}
	local mods = State.sharedModules
	if not mods and Bridge.loadSharedModules then
		mods = Bridge.loadSharedModules()
	end

	if Bridge.readSlotsFromActorState then
		local slots = Bridge.readSlotsFromActorState(actor, mods) or {}
		for _, slot in ipairs({ "Primary", "Secondary", "Melee" }) do
			local item = slots[slot]
			if type(item) == "table" then
				local uid = Bridge.itemUid(item)
				local name = Bridge.firearmDisplayName and Bridge.firearmDisplayName(item) or rawget(item, "Name")
				rows[#rows + 1] = {
					slot = slot,
					uid = uid,
					name = espStripFirearmName(name or "?"),
					item = item,
					handler = espFindHandlerForUid(actor, uid),
					equipped = (uid and uid == eqUid) or false,
				}
			end
		end
	end

	if #rows == 0 then
		local inv = tableField(actor, "_inventory")
		if type(inv) == "table" then
			for invUid, handler in pairs(inv) do
				if type(handler) ~= "table" then continue end
				local item = rawget(handler, "_item")
				local name = type(item) == "table" and rawget(item, "Name") or nil
				if type(name) ~= "string" or not string.match(name, "^Firearm") then continue end
				local slot = Bridge.slotLabelFromItem and Bridge.slotLabelFromItem(item, mods) or "Primary"
				rows[#rows + 1] = {
					slot = slot,
					uid = invUid,
					name = espStripFirearmName(name),
					item = item,
					handler = handler,
					equipped = (invUid == eqUid) or rawget(handler, "_equipped") == true,
				}
			end
		end
	end

	if uid then
		State._espHotbarCache = { uid = uid, rows = rows, eqUid = eqUid, t = now }
	end
	return rows, eqUid
end

local function espResolveMagMax(handler, item)
	local mods = State.sharedModules
	if not mods and Bridge.loadSharedModules then
		mods = Bridge.loadSharedModules()
	end
	if type(handler) == "table" then
		local mag = rawget(handler, "_mag")
		if type(mag) == "table" then
			local maxC = rawget(mag, "Max") or rawget(mag, "MaxCapacity") or rawget(mag, "Capacity")
			if type(maxC) == "number" and maxC > 0 then return maxC end
		end
	end
	if Bridge.resolveMagMax then
		local maxMag = Bridge.resolveMagMax(handler, item, mods)
		if type(maxMag) == "number" and maxMag > 0 then return maxMag end
	end
	if type(item) == "table" then
		local meta = rawget(item, "MetaData")
		if type(meta) == "table" then
			local magMeta = rawget(meta, "Mag")
			if type(magMeta) == "table" and type(rawget(magMeta, "Capacity")) == "number" then
				return magMeta.Capacity
			end
		end
		local firearm = rawget(item, "File")
		local tune = type(firearm) == "table" and rawget(firearm, "Tune")
		if type(tune) == "table" and type(tune.Ammo) == "number" then
			return tune.Ammo
		end
	end
	return nil
end

local function espParseActorWeaponInfo(data)
	if not data or data.dead then return nil end
	if not data.actorData and data.uid then
		data.actorData = Bridge.getReplicatorActorData(data.uid)
	end
	local actor = data.actorData
	if type(actor) ~= "table" then return nil end

	local rows, eqUid = espCollectHotbarWeapons(actor, data.uid)
	local primary, secondaryRow
	for _, row in ipairs(rows) do
		if row.equipped then
			primary = row
		elseif row.slot == "Secondary" and not secondaryRow then
			secondaryRow = row
		end
	end
	if not primary then
		for _, row in ipairs(rows) do
			if row.slot == "Primary" then
				primary = row
				break
			end
		end
	end
	if not primary and rows[1] then
		primary = rows[1]
	end
	if not primary then return nil end

	if secondaryRow and (secondaryRow.uid == primary.uid or secondaryRow.name == primary.name) then
		secondaryRow = nil
	end
	if secondaryRow and secondaryRow.equipped then
		secondaryRow = nil
	end

	data.espSecondaryName = secondaryRow and secondaryRow.name or nil
	data.espSecondarySlot = secondaryRow and secondaryRow.slot or nil

	local invNames = {}
	if CONFIG.EspShowInventory then
		local seen = { [primary.name] = true }
		if secondaryRow then seen[secondaryRow.name] = true end
		local stateInv = Bridge.actorCurrentInventory and Bridge.actorCurrentInventory(actor)
		if type(stateInv) == "table" then
			for uid, entry in pairs(stateInv) do
				if type(uid) ~= "string" or uid == eqUid then continue end
				if type(entry) ~= "table" then continue end
				local n = rawget(entry, "Name")
				if type(n) ~= "string" then continue end
				if string.match(n, "^Firearm") then continue end
				local dn = espStripFirearmName(n)
				if not seen[dn] then
					invNames[#invNames + 1] = dn
					seen[dn] = true
				end
			end
		end
	end
	data.espInventoryNames = invNames

	local handler = primary.handler or espFindHandlerForUid(actor, primary.uid)
	local item = primary.item or (handler and rawget(handler, "_item"))
	local maxMag = espResolveMagMax(handler, item)

	return {
		name = primary.name,
		max = maxMag,
	}
end

function Bridge.refreshActorWeaponInfo(data)
	if not data or data.dead then return end
	if Bridge.isNpcActorClass(data.class) then return end
	local now = os.clock()
	local ttl = CONFIG.EspWeaponInfoTtl or 2.5
	if data.weaponInfo and now - (data._weaponInfoT or 0) < ttl then return end
	local info = espParseActorWeaponInfo(data)
	if info then
		data.weaponInfo = info
		data._weaponInfoT = now
	end
end

local function espGetStanceChip(actor)
	if type(actor) ~= "table" then return nil end
	local hs = tableField(actor, "HeightState")
	if type(hs) ~= "number" then return nil end
	if hs == 2 then
		return { text = "Lying", color = ESP_STANCE_LYING }
	end
	if hs == 1 then
		return { text = "Crouching", color = ESP_STANCE_CROUCH }
	end
	return nil
end

local function espAdaptiveLabelSize(lineCount)
	lineCount = lineCount or 1
	if lineCount >= 5 then return ESP_LABEL_SIZE - 2 end
	if lineCount >= 3 then return ESP_LABEL_SIZE - 1 end
	return ESP_LABEL_SIZE
end

function Bridge.ensureEspLayoutRect(entry, cam, model, vpCache)
	if not model or not cam then
		entry._boxRect = nil
		return nil
	end
	local raw = Bridge.computeEspHeadFeetBox(model, cam, vpCache)
	if not raw then
		entry._boxRect = nil
		return nil
	end
	local rect = Bridge.smoothEspRect(entry, raw)
	entry._boxRect = rect
	return rect
end

function Bridge.ensureEspStatusChips(entry)
	entry.statusChips = entry.statusChips or {}
	for i = 1, ESP_STATUS_CHIP_MAX do
		if not entry.statusChips[i] then
			local chip = Drawing.new("Text")
			chip.Size = ESP_LABEL_SIZE
			chip.Outline = true
			chip.Center = true
			chip.Visible = false
			chip.ZIndex = 23
			entry.statusChips[i] = chip
		end
	end
	return entry.statusChips
end

local function espStatusColor(entry)
	return ESP_STATUS_KIND_COLORS[entry.kind] or ESP_STATUS_TEXT
end

local function espStatusLabel(text)
	return ESP_STATUS_ABBR[text] or text
end

local function espMeasureChipWidth(text, size)
	size = size or ESP_LABEL_SIZE
	return math.max(12, #tostring(text) * size * 0.5 + 2)
end

function Bridge.formatEspStatusLine(entries)
	if type(entries) ~= "table" then return nil end
	local parts = {}
	for _, e in ipairs(entries) do
		if e.text and e.text ~= "Armed" then
			parts[#parts + 1] = espStatusLabel(e.text)
		end
	end
	if #parts == 0 then return nil end
	return table.concat(parts, "·")
end

function Bridge.drawEspPlainText(textObj, cx, y, line, color, textSize)
	if not textObj or not line or line == "" then
		if textObj then textObj.Visible = false end
		return y
	end
	textSize = textSize or ESP_LABEL_SIZE
	textObj.Text = line
	textObj.Size = textSize
	textObj.Center = true
	textObj.Outline = true
	textObj.Color = color
	textObj.Position = Vector2.new(cx, y)
	Bridge.setDrawingAlpha(textObj, 1)
	textObj.Visible = true
	return y + textSize * ESP_LINE_STEP + ESP_STACK_GAP
end

function Bridge.hideEspStatusBar(entry)
	if not entry then return end
	if entry.statusText then entry.statusText.Visible = false end
	if entry.statusBg then entry.statusBg.Visible = false end
	if entry.statusChips then
		for _, chip in ipairs(entry.statusChips) do
			chip.Visible = false
		end
	end
end

function Bridge.removeEspChams(uid)
	local hl = State.espHighlights[uid]
	if hl then
		pcall(function() hl:Destroy() end)
		State.espHighlights[uid] = nil
	end
end

function Bridge.updateEspChams(uid, model, color)
	if not CONFIG.EspChams or not model or not model.Parent then
		Bridge.removeEspChams(uid)
		return
	end
	local hl = State.espHighlights[uid]
	if not hl or not hl.Parent then
		hl = Instance.new("Highlight")
		hl.Name = "BRM5_ESP"
		hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
		hl.FillTransparency = 0.72
		hl.OutlineTransparency = 0.15
		hl.Parent = model
		State.espHighlights[uid] = hl
	end
	hl.Adornee = model
	hl.FillColor = color
	hl.OutlineColor = color
	if hl.Enabled ~= true then
		hl.Enabled = true
	end
end

function Bridge.computeEspBoundsBox(model, cam, vpCache)
	if not model or not cam then return nil end
	local minX, maxX, minY, maxY = math.huge, -math.huge, math.huge, -math.huge
	local footY, any = nil, false
	local headTopY = nil
	for _, name in ipairs(ESP_BOX_PARTS) do
		local p = getBodyPart(model, name)
		if p then
			local sp, on
			if vpCache then
				local cached = vpCache[p]
				if cached then
					sp, on = cached[1], cached[2]
				else
					sp, on = cam:WorldToViewportPoint(p.Position)
					vpCache[p] = { sp, on }
				end
			else
				sp, on = cam:WorldToViewportPoint(p.Position)
			end
			if on and sp.Z > 0.01 then
				any = true

				minX = math.min(minX, sp.X)
				maxX = math.max(maxX, sp.X)
				minY = math.min(minY, sp.Y)
				maxY = math.max(maxY, sp.Y)
				if name == "LeftFoot" or name == "RightFoot" then
					footY = math.max(footY or sp.Y, sp.Y)
				end

				if name == "Head" then
					local topWP = p.Position + Vector3.new(0, p.Size.Y * 0.5, 0)
					local tsp, ton = cam:WorldToViewportPoint(topWP)
					if ton and tsp.Z > 0.01 then
						headTopY = tsp.Y
						minY = math.min(minY, tsp.Y)
					end
				end
			end
		end
	end
	if not any or minX == math.huge then

		local hrp = getBodyPart(model, "HumanoidRootPart")
			or getBodyPart(model, "UpperTorso")
			or getBodyPart(model, "Head")
			or model:FindFirstChildWhichIsA("BasePart")
		local tryPos = nil
		if hrp then
			local sp, on = cam:WorldToViewportPoint(hrp.Position)
			if on and sp.Z > 0.01 then
				tryPos = hrp.Position
			end
		end

		if not tryPos then
			local rawUid = model:GetAttribute("ActorUID")
			local suid = rawUid and tostring(rawUid)
			local actorEntry = suid and State.actors and State.actors[suid]
			if actorEntry then
				local adPos = actorEntry.adPos
				if not adPos then
					local ad = actorEntry.actorData
					if type(ad) == "table" then
						local p = rawget(ad, "SimulatedPosition") or rawget(ad, "ServerPosition") or rawget(ad, "Position")
						if typeof(p) == "Vector3" then adPos = p end
					end
				end
				if typeof(adPos) == "Vector3" then tryPos = adPos end
			end
		end
		if tryPos then
			local sp, on = cam:WorldToViewportPoint(tryPos)
			if on and sp.Z > 0.01 then
				local pad = 28
				return {
					minX = sp.X - pad, maxX = sp.X + pad,
					minY = sp.Y - pad * 2, maxY = sp.Y + pad,
					topY = sp.Y - pad * 2,
					footY = sp.Y + pad,
					centerX = sp.X,
				}
			end
		end
		return nil
	end

	local height = math.max(maxY - minY, 10)
	local rawWidth = maxX - minX

	local minWidth = math.max(height * (CONFIG.EspBoxAspect or 0.42), 2)
	local width = math.max(rawWidth, minWidth)
	local centerX = (minX + maxX) * 0.5
	minX = centerX - width * 0.5
	maxX = centerX + width * 0.5
	return {
		minX = minX, maxX = maxX,
		minY = minY, maxY = maxY,
		topY = minY,
		headTopY = headTopY or minY,
		footY = footY or maxY,
		centerX = centerX,
	}
end

function Bridge.computeEspHeadFeetBox(model, cam, vpCache)
	return Bridge.computeEspBoundsBox(model, cam, vpCache)
end

function Bridge.smoothEspRect(entry, rect)
	if not rect then return nil end
	if CONFIG.EspSmooth == false or (CONFIG.EspSmoothAlpha or 1) >= 0.99 then

		local sr = entry.smoothRect
		if not sr then
			sr = {}
			entry.smoothRect = sr
		end
		sr.minX = rect.minX; sr.maxX = rect.maxX
		sr.minY = rect.minY; sr.maxY = rect.maxY
		sr.footY = rect.footY or rect.maxY
		sr.centerX = rect.centerX or (rect.minX + rect.maxX) * 0.5
		return sr
	end
	local alpha = CONFIG.EspSmoothAlpha or 0.42
	local s = entry.smoothRect
	if not s then
		entry.smoothRect = {
			minX = rect.minX, maxX = rect.maxX,
			minY = rect.minY, maxY = rect.maxY,
			footY = rect.footY or rect.maxY,
			centerX = rect.centerX or (rect.minX + rect.maxX) * 0.5,
		}
		return entry.smoothRect
	end
	s.minX += (rect.minX - s.minX) * alpha
	s.maxX += (rect.maxX - s.maxX) * alpha
	s.minY += (rect.minY - s.minY) * alpha
	s.maxY += (rect.maxY - s.maxY) * alpha
	if rect.footY then
		s.footY = (s.footY or rect.footY) + (rect.footY - (s.footY or rect.footY)) * alpha
	end
	if rect.centerX then
		s.centerX = (s.centerX or rect.centerX) + (rect.centerX - (s.centerX or rect.centerX)) * alpha
	end
	return s
end

function Bridge.drawEspBox(entry, cam, model, color, vpCache)

	if entry then entry._hidden = false end
	if not CONFIG.EspBox then
		for _, line in ipairs(entry.boxLines) do line.Visible = false end
		return Bridge.ensureEspLayoutRect(entry, cam, model, vpCache)
	end
	local raw = Bridge.computeEspHeadFeetBox(model, cam, vpCache)
	if not raw then
		for _, line in ipairs(entry.boxLines) do line.Visible = false end
		entry._boxRect = nil
		entry.smoothRect = nil
		return
	end
	local rect = Bridge.smoothEspRect(entry, raw)
	entry._boxRect = rect
	local mode = CONFIG.EspBoxMode or "Box"

	if mode == "3D" then mode = "Box" end

	for _, line in ipairs(entry.boxLines) do line.Visible = false end

	local function setLine(i, a, b)
		local line = entry.boxLines[i]
		if not line then return end
		line.From = a; line.To = b
		line.Color = color
		Bridge.showDrawing(line, 1)
	end

	local tl = Vector2.new(rect.minX, rect.minY)
	local tr = Vector2.new(rect.maxX, rect.minY)
	local br = Vector2.new(rect.maxX, rect.maxY)
	local bl = Vector2.new(rect.minX, rect.maxY)

	if mode == "Corner" then

		local cLen = CONFIG.EspCornerLen or 0.22
		local w = rect.maxX - rect.minX
		local h = rect.maxY - rect.minY
		local cxMax = math.max(w * 0.45, 1)
		local cyMax = math.max(h * 0.45, 1)
		local cx = math.clamp(w * cLen, math.min(4, cxMax), cxMax)
		local cy = math.clamp(h * cLen, math.min(4, cyMax), cyMax)

		setLine(1, tl, Vector2.new(tl.X + cx, tl.Y))
		setLine(2, tl, Vector2.new(tl.X, tl.Y + cy))

		setLine(3, tr, Vector2.new(tr.X - cx, tr.Y))
		setLine(4, tr, Vector2.new(tr.X, tr.Y + cy))

		setLine(5, br, Vector2.new(br.X - cx, br.Y))
		setLine(6, br, Vector2.new(br.X, br.Y - cy))

		setLine(7, bl, Vector2.new(bl.X + cx, bl.Y))
		setLine(8, bl, Vector2.new(bl.X, bl.Y - cy))

	else
		setLine(1, tl, tr); setLine(2, tr, br)
		setLine(3, br, bl); setLine(4, bl, tl)
	end

	entry._boxTop = Vector2.new((rect.minX + rect.maxX) * 0.5, rect.minY)
end

function Bridge.drawEspHpBar(entry, rect, hp, maxHp, color)
	if not CONFIG.EspHpBar or not entry.hpBg or not entry.hpFill or not rect then
		if entry.hpBg then entry.hpBg.Visible = false end
		if entry.hpFill then entry.hpFill.Visible = false end
		if entry.hpOutline then entry.hpOutline.Visible = false end
		return
	end
	local pct = 1
	if type(hp) == "number" and type(maxHp) == "number" and maxHp > 0 then
		pct = math.clamp(hp / maxHp, 0, 1)
	elseif type(hp) == "number" then
		pct = math.clamp(hp / 100, 0, 1)
	end
	local boxH = math.max(rect.maxY - rect.minY, 8)
	local barW = 4
	local x = rect.minX - barW - 3
	local y = rect.minY
	if entry.hpOutline then
		entry.hpOutline.Size = Vector2.new(barW + 2, boxH + 2)
		entry.hpOutline.Position = Vector2.new(x - 1, y - 1)

		if entry._hpOutlineCol ~= HP_OUTLINE_COL then
			entry.hpOutline.Color = HP_OUTLINE_COL
			entry._hpOutlineCol = HP_OUTLINE_COL
		end
		Bridge.showDrawing(entry.hpOutline, 0.85)
	end
	entry.hpBg.Size = Vector2.new(barW, boxH)
	entry.hpBg.Position = Vector2.new(x, y)
	if entry._hpBgCol ~= HP_BG_COL then
		entry.hpBg.Color = HP_BG_COL
		entry._hpBgCol = HP_BG_COL
	end
	Bridge.showDrawing(entry.hpBg, 0.7)
	local fillH = math.max(boxH * pct, 1)
	entry.hpFill.Size = Vector2.new(barW, fillH)
	entry.hpFill.Position = Vector2.new(x, y + boxH - fillH)
	entry.hpFill.Color = Color3.fromRGB(
		math.floor(255 * (1 - pct) + 55 * pct),
		math.floor(70 + 185 * pct),
		50
	)
	Bridge.showDrawing(entry.hpFill, 0.98)
end

function Bridge.formatEspWeaponLine(weaponInfo)
	if not weaponInfo then return nil end

	local key = tostring(weaponInfo.name) .. "|" .. tostring(weaponInfo.max)
	if weaponInfo._lineKey == key and weaponInfo._line ~= nil then
		return weaponInfo._line
	end
	local name = espStripFirearmName(weaponInfo.name or "?")
	local out
	if type(weaponInfo.max) == "number" then
		out = string.format("[%s] %d", name, weaponInfo.max)
	else
		out = "[" .. name .. "]"
	end
	weaponInfo._lineKey = key
	weaponInfo._line = out
	return out
end

function Bridge.ensureEspExtraTexts(entry)
	entry.extraTexts = entry.extraTexts or {}
	for i = 1, 3 do
		if not entry.extraTexts[i] then
			local t = Drawing.new("Text")
			t.Size = ESP_LABEL_SIZE
			t.Outline = true
			t.Center = true
			t.Visible = false
			t.ZIndex = 23
			entry.extraTexts[i] = t
		end
	end
	return entry.extraTexts
end

function Bridge.hideEspExtraTexts(entry)
	if not entry or not entry.extraTexts then return end
	for _, t in ipairs(entry.extraTexts) do
		t.Visible = false
	end
end

local _extraLinesScratch  = {}
local _extraColorsScratch = {}
local _statusScratch      = {}

function Bridge.drawEspExtraLines(entry, rect, data, startY, labelSize)
	if not entry or not rect then return startY end
	local texts = Bridge.ensureEspExtraTexts(entry)
	local lines = _extraLinesScratch
	local colors = _extraColorsScratch
	table.clear(lines)
	table.clear(colors)
	labelSize = labelSize or ESP_LABEL_SIZE

	if CONFIG.EspShowSecondary and data and data.espSecondaryName then
		lines[#lines + 1] = data.espSecondaryName
		colors[#colors + 1] = ESP_SECONDARY_TEXT
	end
	if CONFIG.EspShowInventory and data and type(data.espInventoryNames) == "table" and #data.espInventoryNames > 0 then
		local invLine = table.concat(data.espInventoryNames, ", ")
		if #invLine > 42 then invLine = string.sub(invLine, 1, 40) .. ".." end
		lines[#lines + 1] = invLine
		colors[#colors + 1] = ESP_INVENTORY_TEXT
	end

	local y = startY
	for i = 1, #texts do
		local t = texts[i]
		local line = lines[i]
		if line and line ~= "" then
			y = Bridge.drawEspPlainText(t, rect.centerX or (rect.minX + rect.maxX) * 0.5, y, line, colors[i], labelSize)
		else
			t.Visible = false
		end
	end
	return y
end

function Bridge.drawEspWeaponText(entry, rect, weaponInfo, labelSize)
	if not CONFIG.EspWeaponInfo or not entry.weaponText or not rect then
		if entry.weaponText then entry.weaponText.Visible = false end
		if entry.weaponBg then entry.weaponBg.Visible = false end
		return rect and (rect.maxY + ESP_STACK_GAP) or 0
	end
	local line = Bridge.formatEspWeaponLine(weaponInfo)
	if not line then
		entry.weaponText.Visible = false
		if entry.weaponBg then entry.weaponBg.Visible = false end
		return rect.maxY + ESP_STACK_GAP
	end
	local cx = rect.centerX or (rect.minX + rect.maxX) * 0.5
	if entry.weaponBg then entry.weaponBg.Visible = false end
	return Bridge.drawEspPlainText(entry.weaponText, cx, rect.maxY + ESP_STACK_GAP, line, ESP_WEAPON_TEXT, labelSize or ESP_LABEL_SIZE)
end

function Bridge.drawEspStatusBar(entry, rect, data, afterY, labelSize)
	if not CONFIG.EspActorStatus or not rect then
		Bridge.hideEspStatusBar(entry)
		return
	end
	local isNpc = Bridge.isNpcActorClass(data and data.class)
	if isNpc and CONFIG.EspNpcStatus == false then
		Bridge.hideEspStatusBar(entry)
		return
	end
	local getEntries = Bridge.getActorStatusEntriesCached or Bridge.getActorStatusEntries

	local entries = _statusScratch
	table.clear(entries)
	for _, e in ipairs(getEntries(data)) do
		if not e.text or e.text == "Armed" then continue end
		if e.kind == "stance" and CONFIG.EspShowStance == false then
			continue
		end
		entries[#entries + 1] = e
	end
	if #entries == 0 then
		Bridge.hideEspStatusBar(entry)
		return
	end

	local chips = Bridge.ensureEspStatusChips(entry)
	local shown = math.min(#entries, ESP_STATUS_CHIP_MAX)
	local x = rect.maxX + 6
	local chipSize = labelSize or ESP_LABEL_SIZE
	local vGap = chipSize + ESP_STATUS_CHIP_GAP

	local bottomY = rect.maxY

	for i = 1, shown do
		local chip = chips[i]
		local e = entries[i]
		chip.Text = espStatusLabel(e.text)
		chip.Color = espStatusColor(e)
		chip.Size = chipSize
		chip.Center = false
		chip.Outline = true
		chip.Position = Vector2.new(x, bottomY - chipSize - (i - 1) * vGap)
		Bridge.setDrawingAlpha(chip, 1)
		chip.Visible = true
	end
	for i = shown + 1, #chips do
		chips[i].Visible = false
	end
	if entry.statusText then entry.statusText.Visible = false end
	if entry.statusBg then entry.statusBg.Visible = false end
end

local function skelShoulderWorldPos(torso, sign)
	if not torso or not torso:IsA("BasePart") then return nil end
	return torso.CFrame:PointToWorldSpace(
		Vector3.new(sign * torso.Size.X * 0.42, torso.Size.Y * 0.46, 0)
	)
end

local function skelBoneWorldPos(part, fromName, toName, torsoPart)
	if not part or not part:IsA("BasePart") then return nil end
	if torsoPart and fromName == "UpperTorso" and (toName == "RightUpperArm" or toName == "LeftUpperArm") then
		local sign = toName == "RightUpperArm" and 1 or -1
		return skelShoulderWorldPos(torsoPart, sign)
	end
	return part.Position
end

local function espHeadScreenRadius(head, cam)
	if not head or not cam then return 4 end
	local camPos = cam.CFrame.Position
	local dist = (head.Position - camPos).Magnitude
	if dist < 1 then dist = 1 end
	local worldR = math.max(head.Size.X, head.Size.Z) * 0.38
	local fovRad = math.rad(cam.FieldOfView)
	local viewScale = (cam.ViewportSize.Y * 0.5) / math.tan(fovRad * 0.5)
	local radius = worldR * viewScale / dist
	if dist > 80 then
		radius *= 1 - math.min((dist - 80) / 400, 0.12)
	end
	return math.clamp(radius, 2, 11)
end

function Bridge.drawEspSkeleton(entry, cam, model, color, vpCache)
	if not CONFIG.EspSkeleton then
		for _, line in ipairs(entry.skelLines) do
			line.Visible = false
		end
		if entry.skelHeadCircle then entry.skelHeadCircle.Visible = false end
		if entry.skelShoulderLine then entry.skelShoulderLine.Visible = false end
		return
	end
	local pairs = Bridge.getSkeletonPairs(model)
	local idx = 0
	local torso = getBodyPart(model, "UpperTorso") or getBodyPart(model, "Torso")
	for _, pair in ipairs(pairs) do
		idx += 1
		local line = entry.skelLines[idx]
		if not line then break end
		local a = getBodyPart(model, pair[1])
		local b = getBodyPart(model, pair[2])
		if a and b then
			local wp1 = skelBoneWorldPos(a, pair[1], pair[2], torso) or a.Position
			local wp2 = b.Position
			local sp1, on1, sp2, on2
			if vpCache then
				local c1 = vpCache[a]
				if c1 and pair[1] ~= "UpperTorso" then sp1, on1 = c1[1], c1[2] else
					sp1, on1 = cam:WorldToViewportPoint(wp1)
					if pair[1] ~= "UpperTorso" then vpCache[a] = { sp1, on1 } end
				end
				local c2 = vpCache[b]
				if c2 then sp2, on2 = c2[1], c2[2] else
					sp2, on2 = cam:WorldToViewportPoint(wp2)
					vpCache[b] = { sp2, on2 }
				end
			else
				sp1, on1 = cam:WorldToViewportPoint(wp1)
				sp2, on2 = cam:WorldToViewportPoint(wp2)
			end
			if (on1 or on2) and sp1.Z > 0.01 and sp2.Z > 0.01 then
				line.From = Vector2.new(sp1.X, sp1.Y)
				line.To = Vector2.new(sp2.X, sp2.Y)
				line.Color = color
				line.Visible = true
			else
				line.Visible = false
			end
		else
			line.Visible = false
		end
	end
	for i = idx + 1, #entry.skelLines do
		entry.skelLines[i].Visible = false
	end
	local sl = entry.skelShoulderLine
	if sl and torso and torso:IsA("BasePart") then
		local wpL = skelShoulderWorldPos(torso, -1)
		local wpR = skelShoulderWorldPos(torso, 1)
		if wpL and wpR then
			local spL, onL = cam:WorldToViewportPoint(wpL)
			local spR, onR = cam:WorldToViewportPoint(wpR)
			if onL and onR and spL.Z > 0.01 and spR.Z > 0.01 then
				sl.From = Vector2.new(spL.X, spL.Y)
				sl.To = Vector2.new(spR.X, spR.Y)
				sl.Color = color
				sl.Thickness = 1.35
				Bridge.setDrawingAlpha(sl, 1)
				sl.Visible = true
			else
				sl.Visible = false
			end
		else
			sl.Visible = false
		end
	elseif sl then
		sl.Visible = false
	end
	local head = getBodyPart(model, "Head")
	local hc = entry.skelHeadCircle
	if hc and head then
		local sp, onScreen
		if vpCache then
			local cached = vpCache[head]
			if cached then sp, onScreen = cached[1], cached[2] else
				sp, onScreen = cam:WorldToViewportPoint(head.Position)
				vpCache[head] = { sp, onScreen }
			end
		else
			sp, onScreen = cam:WorldToViewportPoint(head.Position)
		end
		if onScreen and sp.Z > 0.01 then
			hc.Position = Vector2.new(sp.X, sp.Y)
			local hRad = espHeadScreenRadius(head, cam)
			hc.Radius = hRad

			if entry then entry._headScreenRadius = hRad end
			hc.Color = color
			Bridge.setDrawingAlpha(hc, 1)
			hc.Visible = true
		else
			hc.Visible = false
		end
	elseif hc then
		hc.Visible = false
	end
end

local ESP_ENTRY_SINGLE = {
	"skelShoulderLine", "skelHeadCircle", "text",
	"statusText", "weaponText", "weaponBg", "statusBg",
	"hpBg", "hpFill", "hpOutline",
}
local ESP_ENTRY_LISTS = {
	"boxLines", "skelLines", "statusChips", "extraTexts",
}

function Bridge.destroyEspEntry(entry)
	if not entry then return end

	entry._hidden = false
	pcall(Bridge.hideEspEntry, entry, "destroy")
	entry._hidden = false
	for _, key in ipairs(ESP_ENTRY_SINGLE) do
		Bridge.destroyDrawing(entry[key])
		entry[key] = nil
	end
	for _, key in ipairs(ESP_ENTRY_LISTS) do
		Bridge.destroyDrawingList(entry[key])
		entry[key] = nil
	end
end

function Bridge.clearESP()
	for _, entry in pairs(State.drawings) do
		Bridge.destroyEspEntry(entry)
	end
	table.clear(State.drawings)
	for uid in pairs(State.espHighlights) do
		Bridge.removeEspChams(uid)
	end
end

function Bridge.cleanupEspCache()
	if not State.drawings then return end
	local actors = State.actors

	local toRemove = {}
	for uid in pairs(State.drawings) do

		local isCluster = type(uid) == "string"
			and (uid:sub(1, 3) == "zc:" or uid:sub(1, 9) == "zcluster_")
		if isCluster then
			if not (State._espLiveClusters and State._espLiveClusters[uid]) then
				toRemove[#toRemove + 1] = uid
			end
		elseif not actors or not actors[uid] then
			toRemove[#toRemove + 1] = uid
		end
	end
	for _, uid in ipairs(toRemove) do
		local entry = State.drawings[uid]
		if entry then
			Bridge.hideEspEntry(entry, "cleanup_not_in_actors", uid)
			Bridge.destroyEspEntry(entry)
		end
		Bridge.removeEspChams(uid)
		State.drawings[uid] = nil
	end

	if State.espVisibleCache and actors then
		for uid in pairs(State.espVisibleCache) do
			if not actors[uid] then State.espVisibleCache[uid] = nil end
		end
	end

	if actors then
		for uid, data in pairs(actors) do
			if data and (not data.root or not data.root.Parent) then
				data._healthCache  = nil
				data._healthCacheT = nil
				data._weaponInfoT  = nil
				data.weaponInfo    = nil
				data.actorData     = nil
			end
		end
	end

	if State.espRanked then
		local clean = {}
		for _, row in ipairs(State.espRanked) do
			if row.data and row.data.root and row.data.root.Parent then
				clean[#clean + 1] = row
			end
		end
		State.espRanked = clean
	end

	if State._espHotbarCache and os.clock() - (State._espHotbarCache.t or 0) > 10 then
		State._espHotbarCache = nil
	end
end

function Bridge.clearAllEspDrawings()
	if not State.drawings then return end

	local oldDrawings = State.drawings
	State.drawings     = {}

	State.espRanked    = nil
	State.espLastActorCount = -1
	State.espRankedTime = 0
	State.espVisibleCache = {}

	State.espVisibleCursor = 1

	for _, entry in pairs(oldDrawings) do
		entry._hidden = false
		pcall(Bridge.hideEspEntry, entry, "clear_all")
	end
	task.defer(function()
		for uid, entry in pairs(oldDrawings) do
			pcall(Bridge.destroyEspEntry, entry)
			pcall(Bridge.removeEspChams, uid)
		end
	end)
end

function Bridge.hideAllEspDrawings(reason)
	for uid, entry in pairs(State.drawings) do
		Bridge.hideEspEntry(entry, reason or "hide_all", uid)
		Bridge.removeEspChams(uid)
	end
end

function Bridge.computeNpcLabelPoint(model, cam, data)
	if not model or not cam then return nil end

	local anchor = getBodyPart(model, "Head") or
		getBodyPart(model, "UpperTorso") or
		model:FindFirstChildWhichIsA("BasePart")
	local worldPos
	if anchor and anchor:IsA("BasePart") then
		worldPos = anchor.Position
	elseif data and data.adPos and typeof(data.adPos) == "Vector3" then
		worldPos = data.adPos
	else
		return nil
	end
	local sp, on = cam:WorldToViewportPoint(worldPos)
	if not on or sp.Z <= 0.01 then return nil end
	return { sp = sp, worldPos = worldPos }
end

local _zombieClusterCache = nil
local _zombieClusterT = -999

function Bridge._espResetClusterCache()
	_zombieClusterCache = nil
	_zombieClusterT = -999
end
function Bridge.buildZombieCluster(ranked, cam, now)
	local ttl = 0.5
	if _zombieClusterCache and now - _zombieClusterT < ttl then
		return _zombieClusterCache
	end
	local clusterDist = CONFIG.EspZombieClusterDist or 8
	local clusterMin  = CONFIG.EspZombieClusterMin  or 2

	local zombies = {}
	for _, row in ipairs(ranked) do
		if row.data and row.data.class == "npc_zombie" and row.data.root and row.data.root.Parent then
			local dead = row.data.dead == true or row.data.alive == false
			if not dead then
				zombies[#zombies + 1] = row
			end
		end
	end

	local assigned = {}
	local clusters = {}
	for i, a in ipairs(zombies) do
		if assigned[a.uid] then continue end
		local members = { a }
		local posA = a.data.root.Position
		for j = i + 1, #zombies do
			local b = zombies[j]
			if assigned[b.uid] then continue end
			if (posA - b.data.root.Position).Magnitude <= clusterDist then
				members[#members + 1] = b
			end
		end
		if #members >= clusterMin then

			local cx, cy, cz = 0, 0, 0
			for _, m in ipairs(members) do
				local p = m.data.root.Position
				cx += p.X; cy += p.Y; cz += p.Z
				assigned[m.uid] = true
			end
			local n = #members
			local center = Vector3.new(cx/n, cy/n + 1.5, cz/n)
			local sp, on = cam:WorldToViewportPoint(center)
			if on and sp.Z > 0.01 then

				local cw = "zc:" .. math.floor(center.X / 16)
					.. "_" .. math.floor(center.Z / 16)
				clusters[#clusters + 1] = {
					sp    = sp,
					count = n,
					uid   = cw,
				}
			end
		end
	end

	local liveClusters = {}
	for _, cl in ipairs(clusters) do
		liveClusters[cl.uid] = true
	end
	State._espLiveClusters = liveClusters

	_zombieClusterCache = { clusters = clusters, clustered = assigned }
	_zombieClusterT = now
	return _zombieClusterCache
end

local function cachedNpcCount()
	local now = os.clock()
	if State._espNpcCount ~= nil and now - (State._espNpcCountT or 0) < 1.0 then
		return State._espNpcCount
	end
	local n = 0
	for _, data in pairs(State.actors or {}) do
		if data and Bridge.isNpcActorClass(data.class) then
			n += 1
		end
	end
	State._espNpcCount = n
	State._espNpcCountT = now
	return n
end

Bridge.updateESP = (function(dt)
	if not CONFIG.ESP then
		Bridge.hideAllEspDrawings("esp_disabled")
		return
	end
	if not Drawing then return end
	if not State.actors then
		Bridge.hideAllEspDrawings("no_actors_table")
		return
	end
	local now = os.clock()
	local actorCount = State.trackedActorCount or 0
	if actorCount <= 0 then
		for _ in pairs(State.actors) do actorCount += 1 end
		State.trackedActorCount = actorCount
	end
	local npcCount = cachedNpcCount()
	local renderInterval = CONFIG.EspRenderInterval or 0.0167

	local adaptive = 0
	if npcCount >= 15 or actorCount > 200 then
		adaptive = 0.033
	elseif npcCount >= 8 or actorCount > 100 then
		adaptive = 0.025
	elseif npcCount >= 4 then
		adaptive = 0.02
	end
	renderInterval = math.max(renderInterval, adaptive)
	if now - (State.lastEspUpdate or 0) < renderInterval then return end
	State.lastEspUpdate = now

	local cam = workspace.CurrentCamera
	if not cam then

		Bridge.hideAllEspDrawings("no_camera")
		return
	end
	local camPos = cam.CFrame.Position

	local vpSize = cam.ViewportSize
	local vpX, vpY = vpSize.X, vpSize.Y

	if actorCount == 0 then
		local real = 0
		for _ in pairs(State.actors) do real += 1 end
		actorCount = real
		State.trackedActorCount = real
		if actorCount == 0 then

			Bridge.hideAllEspDrawings("no_actors")
			return
		end
	end

	if ((actorCount ~= (State.espLastActorCount or -1)) or (now - (State.espRankedTime or 0) > 1.5))
		and not State.espRankBusy then
		State.espRankedTime     = now
		State.espLastActorCount = actorCount
		local capturedActors = State.actors
		local capturedCamPos = camPos
		State.espRankBusy = true

		task.delay(3, function()
			if State.espRankBusy then State.espRankBusy = false end
		end)
		task.defer(function()
			local rankT = Bridge.perfBegin and Bridge.perfBegin() or nil
			local players = {}
			local npcs    = {}
			for uid, data in pairs(capturedActors) do
				if data.class == "self" then continue end
				if Bridge.shouldSkipActorCollect(
					data.class, data.player, data.squad, data.teamKey, data.uid
				) then continue end
				if not Bridge.shouldEspShowActor(data) then continue end
				if CONFIG.EspIgnoreTeam and Bridge.shouldEspHideAsTeammate(data) then continue end
				local root = data.root
				if not root or not root.Parent then continue end

				local distPos
				if data.inInactiveWorld and data.adPos and typeof(data.adPos) == "Vector3" then
					distPos = data.adPos
				else
					distPos = root.Position
				end
				local row = { uid = uid, data = data, dist = (distPos - capturedCamPos).Magnitude }
				if Bridge.isNpcActorClass(data.class) then
					npcs[#npcs + 1] = row
				else
					players[#players + 1] = row
				end
			end

			table.sort(players, function(a, b) return a.dist < b.dist end)
			table.sort(npcs,    function(a, b) return a.dist < b.dist end)

			local playerNear = 0
			for _, row in ipairs(players) do
				if row.dist < (CONFIG.EspVisiblePlayerDist or 500) then
					playerNear += 1
				end
			end
			State.espRankedPlayerNear = playerNear
			local ranked = players
			for i = 1, #npcs do ranked[#ranked + 1] = npcs[i] end

			State.espRanked = ranked
			State.espRankBusy = false
			if Bridge.perfEnd then
				Bridge.perfEnd("esp.rank", rankT, "p=" .. #players .. " n=" .. #npcs)
			end
		end)
	end

	local ranked = State.espRanked
	if not ranked or #ranked == 0 then

		if actorCount == 0 then
			for uid, entry in pairs(State.drawings) do
				Bridge.hideEspEntry(entry, "no_actors", uid)
			end
		else
			Bridge.logVizHide("ESP", "ranked_rebuilding", "tracked=" .. tostring(actorCount))
		end
		return
	end

	if CONFIG.EspVisibleCheck then
		local visT = Bridge.perfBegin and Bridge.perfBegin() or nil
		local visN = 0
		local batchSize = CONFIG.EspBatchSize or 4
		local n = #ranked

		local playerNear = State.espRankedPlayerNear or 0
		if playerNear >= 8 then
			batchSize = 1
		elseif playerNear >= 4 then
			batchSize = math.max(1, math.floor(batchSize * 0.5))
		end
		if CONFIG.EspVisibleFast ~= false then
			batchSize = math.min(batchSize, CONFIG.EspVisibleMaxRaysPerFrame or 8)
		else
			batchSize = math.min(batchSize, math.max(1, math.floor((CONFIG.EspVisibleMaxRaysPerFrame or 8) / 6)))
		end
		if n > 0 then
			State.espVisibleCursor = State.espVisibleCursor or 1
			local cursor = State.espVisibleCursor
			local baseInterval = CONFIG.EspVisibleInterval or 0.35
			for i = 0, batchSize - 1 do
				local idx = (cursor - 1 + i) % n + 1
				local row = ranked[idx]
				if row and row.data then
					if Bridge.isNpcActorClass(row.data.class) then
						visN += 1
						local uid = row.uid
						if uid and uid ~= "" then
							State.espVisibleCache = State.espVisibleCache or {}

							local vc = State.espVisibleCache[uid]
							if vc then
								vc.v = true
								vc.t = now
							else
								State.espVisibleCache[uid] = { v = true, t = now }
							end
						end
					else
						local dist = row.dist or 0
						local interval = baseInterval
						if dist > 400 then
							interval = interval * 2.0
						elseif dist > 250 then
							interval = interval * 1.5
						end
						visN += 1
						Bridge.isActorVisibleForEsp(row.data, cam, interval)
					end
				end
			end
			State.espVisibleCursor = (cursor - 1 + batchSize) % n + 1
		end
		if Bridge.perfEnd then
			Bridge.perfEnd("esp.visibleBatch", visT, "n=" .. tostring(visN))
		end
	end

	local live = {}
	local vpCache = {}
	local drawT = Bridge.perfBegin and Bridge.perfBegin() or nil
	local drawnN = 0

	local clusterData = nil
	local clusteredUids = {}
	if CONFIG.EspZombieCluster and CONFIG.EspShowZombie ~= false and CONFIG.EspShowName ~= false then
		clusterData = Bridge.buildZombieCluster(ranked, cam, now)
		if clusterData then
			clusteredUids = clusterData.clustered or {}

			for _, cl in ipairs(clusterData.clusters) do
				local clEntry = Bridge.ensureEspDrawing(cl.uid)

				clEntry._hidden = false
				live[cl.uid] = true
				clEntry.text.Text     = tostring(cl.count) .. "x Zombies"
				clEntry.text.Color    = ESP_COLORS.zombie
				clEntry.text.Size     = ESP_LABEL_SIZE + 1
				clEntry.text.Center   = true
				clEntry.text.Outline  = true
				clEntry.text.Position = Vector2.new(cl.sp.X, cl.sp.Y - ESP_LABEL_SIZE - 2)
				Bridge.setDrawingAlpha(clEntry.text, 1)
				clEntry.text.Visible  = true
				for _, bl in ipairs(clEntry.boxLines) do bl.Visible = false end
				if clEntry.skelLines then
					for _, sl in ipairs(clEntry.skelLines) do sl.Visible = false end
				end
				if clEntry.hpBg     then clEntry.hpBg.Visible     = false end
				if clEntry.hpFill   then clEntry.hpFill.Visible   = false end
				if clEntry.hpOutline then clEntry.hpOutline.Visible = false end
				if clEntry.weaponText then clEntry.weaponText.Visible = false end
				Bridge.hideEspStatusBar(clEntry)
			end
		end
	elseif _zombieClusterCache then

		_zombieClusterCache = nil
		State._espLiveClusters = nil
	end

	for i, row in ipairs(ranked) do

		if row.data and row.data.class == "npc_zombie" and clusteredUids[row.uid] then
			continue
		end
		local uid  = row.uid
		local data = row.data

		if not data or not data.root or not data.root.Parent then
			local stale = State.drawings[uid]
			if stale then Bridge.hideEspEntry(stale, "root_gone", uid) end
			Bridge.removeEspChams(uid)
			continue
		end
		if not Bridge.shouldEspShowActor(data) then
			local hidden = State.drawings[uid]
			if hidden then Bridge.hideEspEntry(hidden, "npc_filter", uid) end
			Bridge.removeEspChams(uid)
			continue
		end
		if CONFIG.EspIgnoreTeam and Bridge.shouldEspHideAsTeammate(data) then
			local entry = State.drawings[uid]
			if entry then Bridge.hideEspEntry(entry, "teammate", uid) end
			Bridge.removeEspChams(uid)
			continue
		end

		local entry = Bridge.ensureEspDrawing(uid)
		live[uid] = true
		drawnN += 1

		if data.class == "dead" then
			if CONFIG.EspShowDead == false or data.player == nil then
				Bridge.hideEspEntry(entry, "dead_hidden")
				Bridge.removeEspChams(uid)
				continue
			end
			local model = data.model
			Bridge.drawEspBox(entry, cam, model, ESP_COLORS.dead, nil)
			local dRect = entry._boxRect
			if dRect then
				entry.text.Text     = "Dead"
				entry.text.Color    = ESP_COLORS.dead
				entry.text.Position = Vector2.new(
					dRect.minX + (dRect.maxX - dRect.minX) * 0.5,
					dRect.minY - 14
				)
				entry.text.Visible  = true
			else
				Bridge.hideEspEntry(entry, "dead_no_rect")
			end

			if entry.skelLines then for _, ln in ipairs(entry.skelLines) do ln.Visible = false end end
			if entry.skelHeadCircle then entry.skelHeadCircle.Visible = false end
			if entry.skelShoulderLine then entry.skelShoulderLine.Visible = false end
			Bridge.hideEspExtraTexts(entry)
			if entry.hpBg      then entry.hpBg.Visible      = false end
			if entry.hpFill    then entry.hpFill.Visible    = false end
			if entry.hpOutline then entry.hpOutline.Visible = false end
			if entry.weaponText then entry.weaponText.Visible = false end
			if entry.weaponBg then entry.weaponBg.Visible = false end
			Bridge.hideEspStatusBar(entry)
			Bridge.removeEspChams(uid)
			live[uid] = true
			continue
		end

		local dead = data.dead == true or data.alive == false
		if dead then
			Bridge.removeEspChams(uid)
			if CONFIG.EspShowDead ~= false and data.player ~= nil then
				local model = data.model
				local shown = false
				if model and model.Parent then
					Bridge.drawEspBox(entry, cam, model, ESP_COLORS.dead, nil)
					local dRect = entry._boxRect
					if dRect then
						entry.text.Text     = "Dead"
						entry.text.Color    = ESP_COLORS.dead
						entry.text.Size     = ESP_LABEL_SIZE + 1
						entry.text.Position = Vector2.new(
							dRect.minX + (dRect.maxX - dRect.minX) * 0.5,
							(dRect.headTopY or dRect.minY) - 14
						)
						Bridge.showDrawing(entry.text, 1)
						shown = true
					end
				end

				if entry.skelLines then for _, ln in ipairs(entry.skelLines) do ln.Visible = false end end
				if entry.skelHeadCircle then entry.skelHeadCircle.Visible = false end

				if entry.skelShoulderLine then entry.skelShoulderLine.Visible = false end
				if entry.hpBg      then entry.hpBg.Visible      = false end
				if entry.hpFill    then entry.hpFill.Visible    = false end
				if entry.hpOutline then entry.hpOutline.Visible = false end
				if entry.weaponText then entry.weaponText.Visible = false end
				if entry.weaponBg then entry.weaponBg.Visible = false end
				Bridge.hideEspStatusBar(entry)
				Bridge.hideEspExtraTexts(entry)
				if not shown then Bridge.hideEspEntry(entry, "dead_no_rect") end
				live[uid] = true
				continue
			end
			Bridge.hideEspEntry(entry, "dead_flag")
			continue
		end

		local model = data.model
		if not model or not model.Parent then
			Bridge.hideEspEntry(entry, "no_model")
			continue
		end

		local npcNameOnly = Bridge.isNpcActorClass(data.class) and CONFIG.EspNpcNameOnly == true
		if npcNameOnly then

			if CONFIG.EspShowName == false then
				Bridge.hideEspEntry(entry, "names_off")
				Bridge.removeEspChams(uid)
				continue
			end

			if entry._mode ~= "label" then
				entry._mode = "label"
				for _, line in ipairs(entry.boxLines) do line.Visible = false end
				if entry.skelLines then
					for _, ln in ipairs(entry.skelLines) do ln.Visible = false end
				end
				if entry.skelHeadCircle then entry.skelHeadCircle.Visible = false end
				if entry.hpBg then entry.hpBg.Visible = false end
				if entry.hpFill then entry.hpFill.Visible = false end
				if entry.hpOutline then entry.hpOutline.Visible = false end
				Bridge.hideEspStatusBar(entry)
				if entry.weaponText then entry.weaponText.Visible = false end
				Bridge.hideEspExtraTexts(entry)
				Bridge.removeEspChams(uid)
			end
			local nPt = Bridge.computeNpcLabelPoint(model, cam, data)
			if not nPt then
				Bridge.hideEspEntry(entry, "offscreen")
				Bridge.removeEspChams(uid)
				local nRect = nil
				entry._boxRect = nil
				continue
			end
			entry._hidden = false
			local boxColor = Bridge.getEspColor(data, Bridge.getEspActorVisible(uid))
			local label = Bridge.formatEspLabelWithDistance(data, camPos)

			if label == nil or label == "" then
				entry.text.Visible = false
			else
				entry.text.Text = label
				entry.text.Color = boxColor
				entry.text.Size = ESP_LABEL_SIZE + 1
				Bridge.showDrawing(entry.text, 1)

				entry.text.Position = Vector2.new(nPt.sp.X, nPt.sp.Y - (ESP_LABEL_SIZE + 3))
			end
			continue
		end

		local visible  = Bridge.getEspActorVisible(uid)

		entry._hidden = false
		entry._mode = "full"
		local boxColor = Bridge.getEspColor(data, visible)

		local boxT = Bridge.perfBegin and Bridge.perfBegin() or nil
		if CONFIG.EspBox then
			Bridge.drawEspBox(entry, cam, model, boxColor, vpCache)
		else
			for _, line in ipairs(entry.boxLines) do
				line.Visible = false
			end
			Bridge.ensureEspLayoutRect(entry, cam, model, vpCache)
		end
		if Bridge.perfEnd then Bridge.perfEnd("esp.box", boxT) end

		local rect = entry._boxRect

		if not rect or rect.maxX < 0 or rect.minX > vpX
			or rect.maxY < 0 or rect.minY > vpY then
			Bridge.hideEspEntry(entry, "offscreen")
			Bridge.removeEspChams(uid)
			continue
		end

		local hpT = Bridge.perfBegin and Bridge.perfBegin() or nil
		if CONFIG.EspHpBar and rect and not npcNameOnly then
			local hp, maxHp = Bridge.resolveActorHealth(data)
			Bridge.drawEspHpBar(entry, rect, hp, maxHp, boxColor)
		else
			if entry.hpBg      then entry.hpBg.Visible      = false end
			if entry.hpFill    then entry.hpFill.Visible    = false end
			if entry.hpOutline then entry.hpOutline.Visible = false end
		end
		if Bridge.perfEnd then Bridge.perfEnd("esp.hp", hpT) end

		local skelMaxDist = CONFIG.EspSkeletonMaxDist or 800
		local skelT = Bridge.perfBegin and Bridge.perfBegin() or nil
		if CONFIG.EspSkeleton and not Bridge.isNpcActorClass(data.class)
			and i <= (CONFIG.EspSkeletonMaxActors or 24) and row.dist <= skelMaxDist then
			Bridge.drawEspSkeleton(entry, cam, model, boxColor, vpCache)
		elseif entry.skelLines then
			for _, ln in ipairs(entry.skelLines) do ln.Visible = false end
			if entry.skelHeadCircle then entry.skelHeadCircle.Visible = false end
		end
		if Bridge.perfEnd then Bridge.perfEnd("esp.skel", skelT) end

		local chamsT = Bridge.perfBegin and Bridge.perfBegin() or nil
		if CONFIG.EspChams and not Bridge.isNpcActorClass(data.class)
			and i <= (CONFIG.EspChamsMaxActors or 14) then
			if Bridge.perfCount then Bridge.perfCount("chamsUpdate") end
			Bridge.updateEspChams(uid, model, boxColor)
		else
			Bridge.removeEspChams(uid)
		end
		if Bridge.perfEnd then Bridge.perfEnd("esp.chams", chamsT) end

		local metaT = Bridge.perfBegin and Bridge.perfBegin() or nil
		local stackY = rect.maxY + ESP_STACK_GAP
		local lineCount = 1
		local showPlayerMeta = CONFIG.EspWeaponInfo and not Bridge.isNpcActorClass(data.class)
		if showPlayerMeta then
			if data.weaponInfo then lineCount += 1 end
			if CONFIG.EspShowStance and espGetStanceChip(data.actorData) then lineCount += 1 end
			if CONFIG.EspShowSecondary and data.espSecondaryName then lineCount += 1 end
			if CONFIG.EspShowInventory and data.espInventoryNames and #data.espInventoryNames > 0 then
				lineCount += 1
			end
		end
		local labelSize = espAdaptiveLabelSize(lineCount)

		if showPlayerMeta then
			stackY = Bridge.drawEspWeaponText(entry, rect, data.weaponInfo, labelSize)
			stackY = Bridge.drawEspExtraLines(entry, rect, data, stackY, labelSize)
		else
			if entry.weaponText then entry.weaponText.Visible = false end
			if entry.weaponBg then entry.weaponBg.Visible = false end
			Bridge.hideEspExtraTexts(entry)
		end

		local label = Bridge.formatEspLabelWithDistance(data, camPos)

		if label == nil or label == "" then
			entry.text.Visible = false
		else
			entry.text.Text = label
			entry.text.Color = boxColor
			entry.text.Size = labelSize + 1
			Bridge.showDrawing(entry.text, 1)

			local topAnchor = rect.headTopY or rect.minY
			local labelAboveOffset = labelSize + 4
			entry.text.Position = Vector2.new(
				rect.minX + (rect.maxX - rect.minX) * 0.5,
				topAnchor - labelAboveOffset
			)
		end
		if CONFIG.EspActorStatus then
			Bridge.drawEspStatusBar(entry, rect, data, stackY, labelSize)
		else
			Bridge.hideEspStatusBar(entry)
		end
		if Bridge.perfEnd then Bridge.perfEnd("esp.meta", metaT) end
	end

	local hiddenN = 0
	for uid, entry in pairs(State.drawings) do
		if not live[uid] then
			hiddenN += 1
			Bridge.hideEspEntry(entry)
			Bridge.removeEspChams(uid)
		end
	end
	if Bridge.perfSet then
		Bridge.perfSet("drawActors", drawnN)
		Bridge.perfSet("hiddenActors", hiddenN)
	end
	if Bridge.perfEnd then
		Bridge.perfEnd("esp.drawLoop", drawT, "draw=" .. tostring(drawnN))
	end
end)

local _M = {}

_M.start = function()
	if espConn then return end

	for k,v in pairs(ESP_CONFIG) do
		if CONFIG[k] == nil then CONFIG[k] = v end
	end
	if type(Bridge.tickRepSyncBatch) == "function" then
		task.defer(function()
			Bridge.tickRepSyncBatch(16)
		end)
	end

	local t0 = os.clock()
	local tFull = t0; local tGc = t0; local tEnrich = t0; local tSquad = t0

	espConn = game:GetService("RunService").Heartbeat:Connect((function(dt)
		local t = os.clock()

		local actorN = State.trackedActorCount or 0
		local npcN = cachedNpcCount()
		local enrichInterval = 0.15
		if npcN >= 15 or actorN > 200 then
			enrichInterval = 0.35
		elseif npcN >= 8 or actorN > 100 then
			enrichInterval = 0.28
		elseif npcN >= 4 then
			enrichInterval = 0.22
		end
		if t - tEnrich >= enrichInterval and type(Bridge._refreshActorsForEsp) == "function" then
			tEnrich = t
			local refreshT = Bridge.perfBegin and Bridge.perfBegin() or nil
			Bridge._refreshActorsForEsp()
			if Bridge.perfEnd then Bridge.perfEnd("esp.refresh.call", refreshT) end
		end

		if t - tFull >= (CONFIG.EspFullRescanInterval or 60) then
			tFull = t

			State.espLastActorCount = -1
			Bridge.invalidateReplicatorCache()
			Bridge.cleanupEspCache()
		end

		if t - tSquad >= (CONFIG.SquadRefreshInterval or 3) then
			tSquad = t
			if type(Bridge.refreshActorSquads) == "function" then
				pcall(Bridge.refreshActorSquads)
			end
		end

		if not CONFIG.ESP then
			if espWasOn then
				espWasOn = false
				Bridge.hideAllEspDrawings("esp_disabled")
			end

			if t - tGc >= 5 then
				tGc = t
				Bridge.cleanupEspCache()
			end
			return
		end
		espWasOn = true
		local updateT = Bridge.perfBegin and Bridge.perfBegin() or nil
		Bridge.updateESP(dt)
		if Bridge.perfEnd then Bridge.perfEnd("esp.update", updateT) end
		if Bridge.updatePerfHud then Bridge.updatePerfHud(dt) end
		if t - tGc >= 5 then
			tGc = t
			Bridge.cleanupEspCache()
		end
	end))

	_M._uiAlive = true
	if diagRespawn then diagRespawn() end
end

_M.stop = function()
	if espConn then espConn:Disconnect(); espConn = nil end
	espWasOn = false

	_M._uiAlive = false

	Bridge.clearAllEspDrawings()

	State._espLiveClusters = nil
	if Bridge._espResetClusterCache then pcall(Bridge._espResetClusterCache) end
end

_M.toggle = function()

	if espConn then
		CONFIG.ESP = false
		_M.stop()
	else
		CONFIG.ESP = true
		_M.start()
	end
	if uiKit and espFeature then
		uiKit.syncToggle(espFeature.flag, CONFIG.ESP)
	end
end

_M.isRunning = function() return espConn ~= nil end

function _M.buildUI(ui)

	local tab = ui.tabs and ui.tabs.Visuals
	if not tab then return end

	local K = Bridge.makeUiKit(ui)
	uiKit = K

	local L = tab:Section({ Side = "Left" })

	espFeature = K.feature(L, {
		Title = "ESP", Flag = "ESP",
		get = function() return CONFIG.ESP end,
		set = function(v) CONFIG.ESP = v; if v then _M.start() else _M.stop() end end,
		Desc = "boxes n info over players n npcs\nbind works on PC + mobile",
	})

	K.group(L, "Elements")

	local boxEls = {}
	local function boxVis() K.setVisible(boxEls, CONFIG.EspBox ~= false) end
	K.toggle(L, { Name = "Boxes", Flag = "Box", Title = "Boxes",
		get = function() return CONFIG.EspBox end,
		set = function(v) CONFIG.EspBox = v end,
		after = boxVis })
	local cornerEl
	boxEls[#boxEls + 1] = K.dropdown(L, {
		Name = "Box Style", Flag = "BoxMode",
		Options = { "Box", "Corner" }, Default = CONFIG.EspBoxMode or "Box",
		Callback = function(v) CONFIG.EspBoxMode = v end,
		after = function(v)

			if cornerEl then pcall(function() cornerEl:SetVisibility(v == "Corner") end) end
		end,
	})
	cornerEl = K.slider(L, { Name = "Corner Length", Flag = "CornerLen",
		Default = math.floor((CONFIG.EspCornerLen or 0.22) * 100),
		Min = 5, Max = 50, Suffix = "%",
		Callback = function(v) CONFIG.EspCornerLen = v / 100 end })
	boxEls[#boxEls + 1] = cornerEl
	K.toggle(L, { Name = "Skeleton", Flag = "Skeleton", Title = "Skeleton",
		get = function() return CONFIG.EspSkeleton end,
		set = function(v) CONFIG.EspSkeleton = v end })
	K.toggle(L, { Name = "Chams", Flag = "Chams", Title = "Chams",
		get = function() return CONFIG.EspChams end,
		set = function(v) CONFIG.EspChams = v end,
		Desc = "fills bodies so u see them thru walls" })
	K.toggle(L, { Name = "HP Bar", Flag = "HpBar", Title = "HP Bar",
		get = function() return CONFIG.EspHpBar end,
		set = function(v) CONFIG.EspHpBar = v end })
	boxVis()
	if CONFIG.EspBoxMode ~= "Corner" and cornerEl then
		pcall(function() cornerEl:SetVisibility(false) end)
	end

	K.group(L, "Text")

	K.toggle(L, { Name = "Names", Flag = "ShowName", Title = "Names",
		get = function() return CONFIG.EspShowName ~= false end,
		set = function(v) CONFIG.EspShowName = v end })

	K.toggle(L, { Name = "Distance", Flag = "Distance", Title = "Distance",
		get = function() return CONFIG.EspShowDistance end,
		set = function(v) CONFIG.EspShowDistance = v end })
	K.toggle(L, { Name = "Weapon Info", Flag = "WeaponInfo", Title = "Weapon Info",
		get = function() return CONFIG.EspWeaponInfo end,
		set = function(v) CONFIG.EspWeaponInfo = v end,
		Desc = "what theyre holding + ammo" })
	K.toggle(L, { Name = "Secondary Weapon", Flag = "Secondary", Title = "Secondary Weapon",
		get = function() return CONFIG.EspShowSecondary end,
		set = function(v) CONFIG.EspShowSecondary = v end })
	K.toggle(L, { Name = "Inventory", Flag = "Inventory", Title = "Inventory",
		get = function() return CONFIG.EspShowInventory end,
		set = function(v) CONFIG.EspShowInventory = v end })
	K.toggle(L, { Name = "Actor Status", Flag = "Status", Title = "Actor Status",
		get = function() return CONFIG.EspActorStatus end,
		set = function(v) CONFIG.EspActorStatus = v end,
		Desc = "downed, reloading, in a vehicle n so on" })
	K.toggle(L, { Name = "Stance", Flag = "Stance", Title = "Stance",
		get = function() return CONFIG.EspShowStance end,
		set = function(v) CONFIG.EspShowStance = v end })

	K.group(L, "Smoothing")
	local smoothEls = {}
	local function smoothVis() K.setVisible(smoothEls, CONFIG.EspSmooth ~= false) end
	K.toggle(L, { Name = "Smooth Boxes", Flag = "Smooth", Title = "Smooth Boxes",
		get = function() return CONFIG.EspSmooth end,
		set = function(v) CONFIG.EspSmooth = v end,
		after = smoothVis })
	smoothEls[#smoothEls + 1] = K.slider(L, { Name = "Smooth Amount", Flag = "SmoothA",
		Default = math.floor((1 - (CONFIG.EspSmoothAlpha or 1)) * 100),
		Min = 0, Max = 90, Suffix = "%",
		Callback = function(v) CONFIG.EspSmoothAlpha = 1 - (v / 100) end,
		Desc = "higher = smoother but boxes lag behind" })
	smoothVis()

	local C = tab:Section({ Side = "Right" })
	C:Header({ Name = "Colors" })
	local function colorPick(name, key)
		K.color(C, { Name = name, Flag = "Col_" .. key, Default = ESP_COLORS[key],
			Callback = function(c) ESP_COLORS[key] = c end })
	end
	colorPick("Visible",   "visible")
	colorPick("Hidden",    "hidden")
	colorPick("Hostile",   "hostile")
	colorPick("Friendly",  "friendly")
	colorPick("NPC",       "npc")
	colorPick("Zombie",    "zombie")
	colorPick("Team",      "team")
	colorPick("Teammate",  "teammate")
	colorPick("Dead",      "dead")

	local R = tab:Section({ Side = "Right" })
	R:Header({ Name = "Filters" })
	K.toggle(R, { Name = "Players", Flag = "ShowPlayers", Title = "Players",
		get = function() return CONFIG.EspShowPlayers end,
		set = function(v) CONFIG.EspShowPlayers = v end })
	K.toggle(R, { Name = "Hostile NPCs", Flag = "ShowHostile", Title = "Hostile NPCs",
		get = function() return CONFIG.EspShowHostile end,
		set = function(v) CONFIG.EspShowHostile = v end })
	K.toggle(R, { Name = "Friendly NPCs", Flag = "ShowFriendly", Title = "Friendly NPCs",
		get = function() return CONFIG.EspShowFriendly end,
		set = function(v) CONFIG.EspShowFriendly = v end })
	K.toggle(R, { Name = "Zombies", Flag = "ShowZombie", Title = "Zombies",
		get = function() return CONFIG.EspShowZombie end,
		set = function(v) CONFIG.EspShowZombie = v end })
	K.toggle(R, { Name = "Generic NPCs", Flag = "ShowNpc", Title = "Generic NPCs",
		get = function() return CONFIG.EspShowNpc end,
		set = function(v) CONFIG.EspShowNpc = v end })
	K.toggle(R, { Name = "Dead Players", Flag = "ShowDead", Title = "Dead Players",
		get = function() return CONFIG.EspShowDead end,
		set = function(v) CONFIG.EspShowDead = v end })
	K.toggle(R, { Name = "Players in PVE", Flag = "ShowPvePlayers", Title = "PVE Players",
		get = function() return CONFIG.EspShowPlayersInPve end,
		set = function(v) CONFIG.EspShowPlayersInPve = v end })

	K.group(R, "Visibility")
	local losEls = {}
	local function losVis() K.setVisible(losEls, CONFIG.EspVisibleCheck ~= false) end
	K.toggle(R, { Name = "Visible Check", Flag = "VisibleCheck", Title = "Visible Check",
		get = function() return CONFIG.EspVisibleCheck end,
		set = function(v) CONFIG.EspVisibleCheck = v end,
		after = losVis,
		Desc = "colors targets by line of sight" })
	losEls[#losEls + 1] = K.toggle(R, { Name = "Strict LOS", Flag = "VisibleStrict",
		Title = "Strict LOS",
		get = function() return CONFIG.EspVisibleStrict end,
		set = function(v) CONFIG.EspVisibleStrict = v end,
		Desc = "checks more bones — accurate but heavier" })
	losVis()

	local dtab = ui.tabs and ui.tabs.Debug
	if dtab then
		local D = dtab:Section({ Side = "Right" })
		D:Header({ Name = "ESP" })
		K.slider(D, { Name = "Render Interval", Flag = "DbgRender",
			Default = math.floor((CONFIG.EspRenderInterval or 0.0167) * 1000),
			Min = 8, Max = 200, Suffix = " ms",
			Callback = function(v) CONFIG.EspRenderInterval = v / 1000 end,
			Desc = "higher = less cpu, choppier boxes" })

		K.slider(D, { Name = "Squad Refresh", Flag = "DbgSquad",
			Default = math.floor((CONFIG.SquadRefreshInterval or 3) * 1000),
			Min = 500, Max = 15000, Suffix = " ms",
			Callback = function(v) CONFIG.SquadRefreshInterval = v / 1000 end,
			Desc = "how fast we re-check whos on ur team\nlower = teammates stop showing red sooner" })
		K.slider(D, { Name = "Full Rescan", Flag = "DbgFullRescan",
			Default = CONFIG.EspFullRescanInterval or 30,
			Min = 5, Max = 120, Suffix = " s",
			Callback = function(v) CONFIG.EspFullRescanInterval = v end })
		K.slider(D, { Name = "Visible Check Interval", Flag = "DbgVisIv",
			Default = math.floor((CONFIG.EspVisibleInterval or 0.35) * 1000),
			Min = 100, Max = 2000, Suffix = " ms",
			Callback = function(v) CONFIG.EspVisibleInterval = v / 1000 end })

		K.group(D, "Diagnostics")
		local stat = D:Label({ Text = "Tracked actors: -" })

		local diagRunning = false
		diagRespawn = function()
			if diagRunning then return end
			diagRunning = true
			task.spawn(function()
				while stat and stat._frame and stat._frame.Parent and _M._uiAlive do
					local n = 0
					pcall(function() if type(State.espRanked) == "table" then n = #State.espRanked end end)
					local drawn = 0
					pcall(function() for _ in pairs(State.drawings or {}) do drawn += 1 end end)
					pcall(function() stat:UpdateName(("Ranked: %d | Drawings: %d | Running: %s")
						:format(n, drawn, tostring(espConn ~= nil))) end)
					task.wait(0.5)
				end
				diagRunning = false
			end)
		end
		if _M._uiAlive == nil then _M._uiAlive = true end
		diagRespawn()
	end

	K.ready()
end

do
	local g = (type(getgenv) == "function" and getgenv()) or _G
	local prev = g.BRM5_ESP_MODULE
	if type(prev) == "table" and type(prev.stop) == "function" and prev ~= _M then
		pcall(prev.stop)
	end
	g.BRM5_ESP_MODULE = _M
end

if Bridge.registerModule then Bridge.registerModule("esp", _M) end
Bridge._espModule = _M
return _M
end
