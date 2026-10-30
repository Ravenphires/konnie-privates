return function(Lib)
local Bridge = Lib.Bridge
local CONFIG  = Lib.CONFIG
local State   = Lib.State

if not Bridge._kaIsActorDeadPatched then
    Bridge._kaIsActorDeadPatched = true
    local _origDead = Bridge.isActorDead
    Bridge.isActorDead = function(data)
        if type(data) ~= "table" then
            return _origDead and _origDead(data) or false
        end

        local fluxAlive  = rawget(data, "Alive")
        local fluxHealth = rawget(data, "Health")
        if fluxAlive == false then return true end
        if type(fluxHealth) == "number" and fluxHealth <= 0 then return true end

        local ad = rawget(data, "actorData") or rawget(data, "_actorData")
        if type(ad) == "table" then
            if rawget(ad, "Alive") == false    then return true end
            if rawget(ad, "Dead")  == true     then return true end
            local hp = rawget(ad, "Health")
            if type(hp) == "number" and hp <= 0 then return true end
        end

        return _origDead and _origDead(data) or false
    end
end

local UIS       = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local Players   = game:GetService("Players")
local RunService  = Bridge._RunService
local getCamera   = Bridge._getCamera
local log         = Bridge._log

local newcclosure = newcclosure
local hookfunction = hookfunction
local _kaEnsureUseSpeedHook
local _kaSpawnPacketShock
local getgc = getgc

local KA_CONFIG = {

    KillAura            = false,
    KillAuraDistance    = 25,
    KillAuraFOV         = 360,
    KillAuraPredictMs   = 290,

    KillAuraReach       = 999,
    KillAuraSwingCd     = 0.35,
    KillAuraNoWallCheck = true,
    KillAuraForceBone   = "Head",
    KillAuraTickInterval  = 0.2,
    KillAuraPickInterval  = 0.25,
    KillAuraCtxCacheSec   = 1.5,

    KillAuraSwitchMargin  = 2.0,

    KillAuraMode     = "Hook",

    KillAuraDebugKey = nil,

    MeleeAnimSpeed  = 1,

    MeleeReachBoost = 0,

    MeleeSwingSpeed     = false,
    MeleeSwingSpeedMult = 2.0,
    MeleeSwingScaleDelay = false,

    KillAuraViz          = true,
    KillAuraVizSegments  = 24,
    KillAuraVizRadius    = 1.8,
    KillAuraVizThickMin  = 1.3,
    KillAuraVizThickMax  = 1.8,
    KillAuraVizTiltAmp   = 0.3,
    KillAuraVizWarpAmp   = 0.16,
    KillAuraVizBreathAmp = 0.10,
    KillAuraVizBreathFq  = 0.9,
    KillAuraVizSpin      = true,
    KillAuraVizSpinSpeed = 1.2,
    KillAuraVizTransparency = 0,
    KillAuraVizColorA    = Color3.fromRGB(200, 140, 255),
    KillAuraVizColorB    = Color3.fromRGB(90,  205, 255),

    KillAuraPacketViz        = true,
    KillAuraPacketVizColor   = Color3.fromRGB(120, 210, 255),
    KillAuraPacketVizFlash   = Color3.fromRGB(255, 255, 255),
    KillAuraPacketVizThick   = 2.0,
    KillAuraPacketVizSegments= 32,
    KillAuraPacketVizShock   = true,
    KillAuraPacketVizShockN  = 3,
}
for k, v in pairs(KA_CONFIG) do CONFIG[k] = v end

local KA_CHAR_GRACE = 0.3
local kaConn, kaVizConn, kaInputConn, kaCharConn
local kaCharGraceUntil = 0
local kaLastPickT, kaLastDiagT, kaLastPrepT, kaLastFullCtxT = 0, 0, 0, 0
local kaActionTypeInv

local kaVizLines  = {}
local kaVizActive = false

local kaVizShown  = false
local kaPvShown   = false

local kaPacketPulse = -999

local kaVizWarpAmpCur = 0.0
local kaVizBreathCur  = 0.0

local kaVizFlash      = 0.0

local kaVizSpinAngle  = 0.0

local kaVizAngleCacheN   = 0
local kaVizCosCache      = {}
local kaVizSinCache      = {}

local kaVizScrX  = {}
local kaVizScrY  = {}
local kaVizVis   = {}
local kaVizColR  = {}
local kaVizColG  = {}
local kaVizColB  = {}

local _fluxActorCache      = nil
local _fluxActorCacheTime  = 0
local FLUX_ACTOR_CACHE_TTL = 0.5

local function now() return os.clock() end

local function setPhase(phase, skip)
    State.kaLastPhase = phase
    if skip ~= nil then State.kaLastSkip = skip end
end

local function clearKaTarget()
    State.kaTarget     = nil
    State.kaTargetUid  = nil
    State.kaAimPart    = nil
    State.kaAimPoint   = nil
    State.kaTargetTime = 0
end

local function releaseSwingState()
    State.kaSwingBusy   = false
    State.kaImpactSteer = false
    State.kaImpactPart  = nil
    State.kaImpactUid   = nil
end

local function clearMeleeBoot()
    State.kaCtx            = nil
    State.kaCtxEq          = nil
    State.kaCtxTime        = 0
    State.kaMeleeSvc       = nil
    State.kaBootEq         = nil
    State.kaUseEnv         = nil
    State.kaSvcSrc         = nil
    State.kaWarmupDone     = false
    State.kaWarmupEq       = nil
    State.kaWarmupBusy     = false
    State.kaModsAppliedEq  = nil

    State.kaMeleeRep       = nil

    State.kaMeleeRayParams = nil
    State.kaGcScanEq       = nil
    State.kaUseThreadActive = false
    State.kaUseThreadSince  = 0

    _fluxActorCache     = nil
    _fluxActorCacheTime = 0
end

local function getHandlerMethod(handler, name)
    if type(handler) ~= "table" or type(name) ~= "string" then return nil end
    local direct = rawget(handler, name)
    if type(direct) == "function" then return direct end
    local mt = getmetatable(handler)
    if type(mt) == "table" then
        local fn = rawget(mt, name)
        if type(fn) == "function" then return fn end
        local idx = rawget(mt, "__index")
        if type(idx) == "table" then
            local fn2 = rawget(idx, name)
            if type(fn2) == "function" then return fn2 end
        end
    end
    local ok, fn = pcall(function() return handler[name] end)
    if ok and type(fn) == "function" then return fn end
    return nil
end

local function normalizeEqUid(eq)
    if eq == nil then return nil end
    return tostring(eq)
end

local function getFluxLocalActor()
    local t = now()
    if _fluxActorCache ~= nil and t - _fluxActorCacheTime < FLUX_ACTOR_CACHE_TTL then
        return _fluxActorCache
    end

    local found = nil

    if Bridge.resolveLocalActor then
        local ok, _, a = pcall(Bridge.resolveLocalActor, false)
        if ok and type(a) == "table" and rawget(a, "Alive") ~= nil then
            found = a
        end
    end

    if not found then
        local client = State.localClient
        if client and Bridge.getActorTable then
            local a = Bridge.getActorTable(client)
            if type(a) == "table" and rawget(a, "Alive") ~= nil then
                found = a
            end
        end
    end

    _fluxActorCache     = found
    _fluxActorCacheTime = t
    return found
end

local function isLocalAlive()
    if now() < kaCharGraceUntil then return true end

    local fluxActor = getFluxLocalActor()
    if fluxActor ~= nil then
        local alive  = rawget(fluxActor, "Alive")
        local health = rawget(fluxActor, "Health")

        if alive == false then return false end

        if type(health) == "number" and health <= 0 then return false end

        if alive == true then return true end

    end

    local lp   = Players.LocalPlayer
    local char = lp and lp.Character
    if not char or not char.Parent then return false end
    local hum  = char:FindFirstChildOfClass("Humanoid")
    if hum then return hum.Health > 0 end
    return true
end

local function onLifeState()
    if not isLocalAlive() then
        if not State.kaWasDead then
            State.kaWasDead = true
            clearKaTarget()
            releaseSwingState()
            clearMeleeBoot()
        end
        return false
    end
    if State.kaWasDead then
        State.kaWasDead = false
        clearMeleeBoot()
        releaseSwingState()
        pcall(function()
            if Bridge.resolveLocalActor then Bridge.resolveLocalActor(true) end
        end)
    end
    return true
end

local function kaLosOrigin(actor)
    if type(actor) == "table" then
        local cf = rawget(actor, "CFrame")
        if typeof(cf) == "CFrame" then return cf.Position end
    end
    local cam = getCamera()
    if cam then return cam.CFrame.Position end
    if Bridge.getAimLosOrigin then return Bridge.getAimLosOrigin() end
    return Vector3.zero
end

local function kaDist()
    local d = CONFIG.KillAuraDistance
    return (type(d) == "number" and d > 0) and d or 30
end

local function isMeleeRep(v)
    if type(v) ~= "table" then return false end
    if getHandlerMethod(v, "Slash")  == nil then return false end
    if getHandlerMethod(v, "Breach") == nil then return false end

    if getHandlerMethod(v, "Discharge") ~= nil then return false end
    if getHandlerMethod(v, "ADS")       ~= nil then return false end
    return true
end

local function getEquippedRep(actor)
    if type(actor) ~= "table" then return nil end
    local eq  = rawget(actor, "_equipped")
    local inv = rawget(actor, "_inventory")
    if not eq or type(inv) ~= "table" then return nil end

    local h = inv[eq] or inv[tonumber(eq)]
    if isMeleeRep(h) then return h end
    return nil
end

local function peekLocalActorLight()
    if not isLocalAlive() then return nil, nil end
    local client = State.localClient
    if client and Bridge.getActorTable then
        local actor = Bridge.getActorTable(client)
        if type(actor) == "table" then return client, actor end
    end
    if Bridge.resolveLocalActor then return Bridge.resolveLocalActor(false) end
    return nil, nil
end

local function resolveActor(ctx)
    if ctx and type(ctx.actor) == "table" and getEquippedRep(ctx.actor) then
        return ctx.actor
    end
    local _, a = peekLocalActorLight()
    if a and getEquippedRep(a) then return a end
    if Bridge.resolveLocalActor then
        local _, a2 = Bridge.resolveLocalActor(false)
        if a2 then return a2 end
    end
    return ctx and ctx.actor or nil
end

local function refreshTeamAndRep(force)
    local t = now()
    if not force and t - kaLastPrepT < 0.35 then return end
    kaLastPrepT = t
    if Bridge.refreshLocalTeamKey then pcall(Bridge.refreshLocalTeamKey) end
    if Bridge.tickRepSyncBatch then pcall(Bridge.tickRepSyncBatch, force and 18 or 10) end
end

local function kaRefPos(data)
    if not data then return nil end
    if data.inInactiveWorld and typeof(data.adPos) == "Vector3" then return data.adPos end
    local ad = data.actorData
    if type(ad) == "table" then
        local p = rawget(ad, "SimulatedPosition") or rawget(ad, "ServerPosition") or rawget(ad, "Position")
        if typeof(p) == "Vector3" then return p end
    end

    local sp = rawget(data, "SimulatedPosition") or rawget(data, "ServerPosition") or rawget(data, "Position")
    if typeof(sp) == "Vector3" then return sp end
    local root = data.root
    if root and root.Parent and root:IsA("BasePart") then return root.Position end
    if data.model and data.model.Parent then
        local p = data.model:FindFirstChild("HumanoidRootPart")
            or data.model:FindFirstChild("UpperTorso")
            or data.model:FindFirstChild("Head")
        if p and p:IsA("BasePart") then return p.Position end
    end
    return nil
end

local function resolveAim(data)
    if not data then return nil, nil end
    local point = kaRefPos(data)
    local part  = (Bridge.getSilentAimPart and Bridge.getSilentAimPart(data)) or data.root
    if part and part:IsA("BasePart") and part.Parent and typeof(point) == "Vector3" then
        return part, point
    end
    if typeof(point) == "Vector3" and data.model and data.model.Parent then
        local p = data.model:FindFirstChild("Head")
            or data.model:FindFirstChild("UpperTorso")
            or data.model:FindFirstChild("HumanoidRootPart")
            or data.root
        if p and p:IsA("BasePart") then return p, point end
    end
    if typeof(point) == "Vector3" then return part, point end
    return nil, nil
end

local KA_HIT_PARTS = { "HumanoidRootPart", "Head", "UpperTorso", "LowerTorso" }
local function hasHittablePart(data)
    if type(data) ~= "table" then return false end
    local root = data.root
    if root and typeof(root) == "Instance" and root:IsA("BasePart") and root.Parent then
        return true
    end
    local model = data.model
    if model and typeof(model) == "Instance" and model.Parent then
        for i = 1, #KA_HIT_PARTS do
            local ch = model:FindFirstChild(KA_HIT_PARTS[i])
            if ch and ch:IsA("BasePart") then return true end
        end
    end
    return false
end

local function buildTargetPool(actor)
    local losOrigin = kaLosOrigin(actor)
    local maxDist   = kaDist()
    local pool = {}
    if Bridge.collectAimActorCandidates and getCamera() then
        local ok, result = pcall(Bridge.collectAimActorCandidates, getCamera(), losOrigin, maxDist,
            math.min((CONFIG.KillAuraFOV or 360) * 0.5, 179))
        if ok and type(result) == "table" and #result > 0 then

            local filtered = {}
            for _, d in ipairs(result) do
                if hasHittablePart(d) then filtered[#filtered + 1] = d end
            end
            if #filtered > 0 then return filtered, "ka.aim" end
        end
    end
    for _, data in pairs(State.actors or {}) do
        if Bridge.isEnemyActor and not Bridge.isEnemyActor(data) then continue end
        if Bridge.isActorDead   and Bridge.isActorDead(data)     then continue end
        if not hasHittablePart(data) then continue end
        local pos = kaRefPos(data)
        if typeof(pos) ~= "Vector3" then continue end
        if (pos - losOrigin).Magnitude <= maxDist then
            pool[#pool + 1] = data
        end
    end
    return pool, (#pool > 0 and "ka.state" or "ka.empty")
end

local function commitPick(best, part, point, source)
    State.kaTarget       = best
    State.kaTargetUid    = best and best.uid or nil
    State.kaAimPart      = part
    State.kaAimPoint     = point
    State.kaTargetTime   = now()
    State.kaLastPickSource = source
    kaLastPickT = now()
    return best, part, point
end

local function pickTarget(force, actor)
    local iv = CONFIG.KillAuraPickInterval or 0.25
    if not force and State.kaTarget and typeof(State.kaAimPoint) == "Vector3"
        and now() - kaLastPickT < iv then
        return State.kaTarget, State.kaAimPart, State.kaAimPoint
    end

    local prevUid = State.kaTargetUid

    refreshTeamAndRep(false)
    clearKaTarget()
    local pool, source = buildTargetPool(actor)
    if #pool == 0 then
        State.kaLastPickSource = source
        return nil, nil, nil
    end
    local losOrigin = kaLosOrigin(actor)
    local best, bestPart, bestPoint, bestDist
    local prevData, prevPart, prevPoint, prevD
    for _, data in ipairs(pool) do
        local part, point = resolveAim(data)
        if typeof(point) ~= "Vector3" then continue end
        local d = (point - losOrigin).Magnitude

        local inRange = d <= kaDist()
        if inRange and (best == nil or d < bestDist) then
            best, bestPart, bestPoint, bestDist = data, part, point, d
        end

        if inRange and prevUid ~= nil and data.uid == prevUid then
            prevData, prevPart, prevPoint, prevD = data, part, point, d
        end
    end
    if not best then
        State.kaLastPickSource = source .. ":filtered"
        return nil, nil, nil
    end

    if prevData and best ~= prevData then
        local margin = CONFIG.KillAuraSwitchMargin or 2.0
        if prevD - bestDist < margin then
            best, bestPart, bestPoint = prevData, prevPart, prevPoint
        end
    end
    return commitPick(best, bestPart, bestPoint, source)
end

local function validateTarget(actor)
    local target = State.kaTarget
    if not target then return false end
    if Bridge.isEnemyActor and not Bridge.isEnemyActor(target) then clearKaTarget() return false end
    if Bridge.isActorDead   and Bridge.isActorDead(target)     then clearKaTarget() return false end
    if not hasHittablePart(target) then clearKaTarget() return false end
    local pos = kaRefPos(target) or (State.kaAimPart and State.kaAimPart.Position) or State.kaAimPoint
    if typeof(pos) ~= "Vector3" then clearKaTarget() return false end
    if (pos - kaLosOrigin(actor)).Magnitude > kaDist() + 1 then
        clearKaTarget() return false
    end
    local part, point = resolveAim(target)
    State.kaAimPart  = part  or State.kaAimPart
    State.kaAimPoint = point or pos
    return true
end

local function resolveMeleeContext(force)
    if not isLocalAlive() and force ~= true then return nil end
    local _, actor
    if force and Bridge.resolveLocalActor then
        _, actor = Bridge.resolveLocalActor(true)
    else
        _, actor = peekLocalActorLight()
    end
    if not actor then
        clearMeleeBoot()
        return nil
    end
    local eqStr = normalizeEqUid(rawget(actor, "_equipped")) or ""
    if not force and State.kaCtx and State.kaCtxEq == eqStr
        and now() - (State.kaCtxTime or 0) < (CONFIG.KillAuraCtxCacheSec or 1.5) then
        return State.kaCtx
    end
    local rep = getEquippedRep(actor)
    if not rep then
        if State.kaCtxEq ~= eqStr then clearMeleeBoot() end

        State.kaCtx     = nil
        State.kaTarget  = nil
        State.kaCtxEq   = eqStr
        State.kaCtxTime = now()
        return nil
    end
    local item = (Bridge.itemFromActorInventory
        and Bridge.itemFromActorInventory(actor, rawget(actor, "_equipped")))
        or rawget(rep, "_item")
    local ctx = {
        actor   = actor,
        handler = rep,
        item    = item,
        isMelee = true,
        info = {
            caliber = "melee",
            name    = rawget(rep, "_build") or "melee",
            slot    = "Melee",
        },
    }
    if force and Bridge.loadSharedModules and Bridge.buildWeaponContext and item then
        local ok, mods = pcall(Bridge.loadSharedModules)
        if ok then
            local ok2, built = pcall(Bridge.buildWeaponContext, actor, item, "Melee", mods)
            if ok2 and type(built) == "table" then
                built.isMelee = true
                built.handler = rep
                ctx = built
            end
        end
    end
    State.kaCtx    = ctx
    State.kaCtxEq  = eqStr
    State.kaCtxTime = now()
    State.kaMeleeRep = rep

    if type(rep) == "table" then
        local prm = rawget(rep, "_params")
        if typeof(prm) == "RaycastParams" then
            State.kaMeleeRayParams = prm
        end
    end
    return ctx
end

local function isMeleeSvcTable(obj)
    if type(obj) ~= "table" then return false end
    if getHandlerMethod(obj, "_use")    == nil then return false end
    if getHandlerMethod(obj, "Impact") ~= nil  then return false end
    return true
end

local function searchInvSvcHandlers(invSvc, eqUid)
    local inventories = rawget(invSvc, "_inventories")
    if type(inventories) ~= "table" then return nil end

    for _, group in pairs(inventories) do
        if type(group) ~= "table" then continue end
        for _, slot in ipairs(group) do
            if type(slot) ~= "table" then continue end
            local h = rawget(slot, "Handler")
            if isMeleeSvcTable(h) then
                local uid = normalizeEqUid(rawget(slot, "UID"))
                if eqUid == nil or uid == eqUid then
                    return h, "uid"
                end
            end
        end
    end

    local equipped = rawget(invSvc, "Equipped")
    local equippedUid = equipped and normalizeEqUid(rawget(equipped, "UID"))
    for _, group in pairs(inventories) do
        if type(group) ~= "table" then continue end
        for _, slot in ipairs(group) do
            local h = type(slot) == "table" and rawget(slot, "Handler") or nil
            if isMeleeSvcTable(h) then
                local slotUid = normalizeEqUid(rawget(slot, "UID"))

                if equippedUid and slotUid == equippedUid then
                    return h, "equipped"
                end
            end
        end
    end

    for _, group in pairs(inventories) do
        if type(group) ~= "table" then continue end
        for _, slot in ipairs(group) do
            local h = type(slot) == "table" and rawget(slot, "Handler") or nil
            if isMeleeSvcTable(h) then return h, "any" end
        end
    end
    return nil
end

local kaInvSvcFailT = 0
local function resolveInvSvc()
    if now() - kaInvSvcFailT < 3 then return nil, nil end

    if type(getnilinstances) == "function" then
        local ok0, nils = pcall(getnilinstances)
        if ok0 and type(nils) == "table" then
            for _, inst in ipairs(nils) do
                local okC, cls = pcall(function() return inst.ClassName end)
                if not okC or cls ~= "ModuleScript" then continue end
                local okN, nm  = pcall(function() return inst.Name end)
                if not okN or nm ~= "InventoryService" then continue end
                local okR, svc = pcall(require, inst)
                if okR and type(svc) == "table" and rawget(svc, "_inventories") ~= nil then
                    return svc, "getnilinstances.require"
                end
            end
        end
        warn("[KA] resolveInvSvc: getnilinstances не нашёл InventoryService ModuleScript.")
    else
        warn("[KA] resolveInvSvc: getnilinstances недоступен в этом экзекуторе.")
    end
    kaInvSvcFailT = now()
    return nil, nil
end

local kaSvcScanFailT = 0
local function scanMeleeSvc(actor, rep, eqUid)
    if now() - kaSvcScanFailT < 3 then return nil end

    local invSvc, invSrc = resolveInvSvc()
    if type(invSvc) == "table" then
        local h, hSrc = searchInvSvcHandlers(invSvc, eqUid)
        if h then
            State.kaSvcSrc = "invSvc." .. (hSrc or "?") .. "/" .. (invSrc or "?")
            return h
        end
        warn("[KA] scanMeleeSvc: InventoryService найден (", invSrc, ") но MeleeInventory handler не найден.",
             "eqUid=", tostring(eqUid), "_inventories keys=",
             (function() local s=""; for k,_ in pairs(rawget(invSvc,"_inventories") or {}) do s=s..tostring(k).."," end return s end)())
    else
        warn("[KA] scanMeleeSvc: InventoryService не найден ни одним из 6 путей.")
    end

    if type(rep) == "table" then
        for _, key in ipairs({"_inventoryService", "_service", "_svc", "_parent", "_handler"}) do
            local v = rawget(rep, key)
            if isMeleeSvcTable(v) then
                State.kaSvcSrc = "rep." .. key
                return v
            end
        end

        local repActor = rawget(rep, "_actor")
        if type(repActor) == "table" then
            for _, key in ipairs({"_inventoryService", "InventoryService", "_invSvc"}) do
                local v = rawget(repActor, key)
                if type(v) == "table" then
                    local h2 = searchInvSvcHandlers(v, eqUid)
                    if h2 then
                        State.kaSvcSrc = "rep._actor." .. key
                        return h2
                    end
                end
            end
        end
    end
    warn("[KA] scanMeleeSvc: svc не найден. rep=", tostring(rep), "actor=", tostring(actor))
    kaSvcScanFailT = now()
    return nil
end

local extractUseEnv = (function(svc)
    if not svc then return nil end
    if State.kaUseEnv and State.kaUseEnv.svc == svc then return State.kaUseEnv end
    local env = {
        svc      = svc,
        delay    = rawget(svc, "_delay"),
        distance = rawget(svc, "_distance"),
        v3       = Bridge.vector3ToTable,
    }
    local useFn = getHandlerMethod(svc, "_use")
    if type(useFn) == "function" and type(debug) == "table" and type(debug.getupvalue) == "function" then
        for i = 1, 32 do
            local ok, _, val = pcall(debug.getupvalue, useFn, i)
            if not ok then break end
            if not env.net and type(val) == "table"
                and type(rawget(val, "FireServer")) == "function" then
                env.net = val
            elseif type(val) == "table" and rawget(val, "ActionType") then
                env.enum = val
            end
        end
    end
    if type(shared) == "table" and type(shared.import) == "function" then
        local ok, v3 = pcall(shared.import, "vector3toTable")
        if ok and type(v3) == "function" then env.v3 = v3 end
    end
    State.kaUseEnv = env
    return env
end)

local function getActionTypeInv()
    if kaActionTypeInv then return kaActionTypeInv end
    if State.kaUseEnv and State.kaUseEnv.enum and State.kaUseEnv.enum.ActionType then
        kaActionTypeInv = State.kaUseEnv.enum.ActionType.Inventory
        return kaActionTypeInv
    end
    if type(shared) == "table" and type(shared.import) == "function" then
        local ok, e = pcall(shared.import, "Enum")
        if ok and type(e) == "table" and e.ActionType then
            kaActionTypeInv = e.ActionType.Inventory
            return kaActionTypeInv
        end
    end
    return nil
end

local KA_REACH_MULT = 1.6
local function getKaReach()
    local svc = State.kaMeleeSvc

    local base
    if svc and State.kaDistOrig and type(State.kaDistOrig[svc]) == "number" then
        base = State.kaDistOrig[svc]
    else
        base = svc and rawget(svc, "_distance")
    end
    if type(base) ~= "number" or base <= 0 then base = 8 end
    local cap = base * KA_REACH_MULT
    local r = CONFIG.KillAuraReach
    if type(r) == "number" and r > 0 then
        return math.min(r, cap)
    end
    return cap
end

local KA_PACKET_REACH_MARGIN = 1.0
local function packetImpactReach()
    local svc = State.kaMeleeSvc
    local base

    if svc and State.kaDistOrig and type(State.kaDistOrig[svc]) == "number" then
        base = State.kaDistOrig[svc]
    elseif svc then
        base = rawget(svc, "_distance")
    end
    if type(base) ~= "number" or base <= 0 then base = 5 end

    if base > 7 then base = 7 end
    return base + KA_PACKET_REACH_MARGIN
end

local function getKaTimings()
    local cd = CONFIG.KillAuraSwingCd or 0.35
    return getKaReach(), cd
end

local function meleeSvcReady(eqUid)
    return State.kaMeleeSvc ~= nil
        and State.kaBootEq == eqUid
        and State.kaWarmupDone == true
end

local function applyMeleeMods(svc)
    if not svc then return end

    if State.kaModsAppliedEq == State.kaBootEq then return end
    State.kaModsAppliedEq = State.kaBootEq
    local animSpeed  = CONFIG.MeleeAnimSpeed  or 1.0
    local reachBoost = CONFIG.MeleeReachBoost or 0

    if type(animSpeed) == "number" and animSpeed > 0 then
        for _, field in ipairs({"_slash", "_equip", "_idle"}) do
            local track = rawget(svc, field)
            if track and type(track.AdjustSpeed) == "function" then
                pcall(track.AdjustSpeed, track, animSpeed)
            end
        end
        local tp = rawget(svc, "_slashTP")
        if tp and type(tp.AdjustSpeed) == "function" then
            pcall(tp.AdjustSpeed, tp, 1)
        end
    end

    State.kaDistOrig = State.kaDistOrig or setmetatable({}, { __mode = "k" })
    local base = State.kaDistOrig[svc]
    if base == nil then base = rawget(svc, "_distance") end
    if type(base) == "number" then
        if reachBoost ~= 0 then
            State.kaDistOrig[svc] = base
            rawset(svc, "_distance", base + reachBoost)
        elseif State.kaDistOrig[svc] ~= nil then

            rawset(svc, "_distance", base)
        end
    end
end

local function finishSvcBootstrap(actor, rep, eqUid, ctx)
    local env = extractUseEnv(State.kaMeleeSvc)
    State.kaUseEnv     = env
    State.kaWarmupDone = true
    State.kaWarmupEq   = eqUid

    pcall(applyMeleeMods, State.kaMeleeSvc)

    if _kaEnsureUseSpeedHook then pcall(_kaEnsureUseSpeedHook, State.kaMeleeSvc) end
end

local function ensureMeleeSvc(actor, ctx)
    if not actor or not ctx then return nil, nil end
    local rep   = ctx.handler or getEquippedRep(actor)
    local eqUid = normalizeEqUid(rawget(actor, "_equipped"))
    if rep == nil or eqUid == nil then return nil, nil end
    if meleeSvcReady(eqUid) then
        finishSvcBootstrap(actor, rep, eqUid, ctx)
        return State.kaMeleeSvc, State.kaUseEnv
    end
    local svc = scanMeleeSvc(actor, rep, eqUid)
    if svc then
        State.kaMeleeSvc = svc
        State.kaBootEq   = eqUid
        finishSvcBootstrap(actor, rep, eqUid, ctx)
        return svc, State.kaUseEnv
    end
    State.kaWarmupDone = false
    State.kaWarmupEq   = nil
    return nil, nil
end

local function getRepHandler(actor, ctx)
    return getEquippedRep(actor) or (ctx and ctx.handler) or nil
end

local KA_ORIGIN_MAX_DRIFT = 8
local function kaImpactOrigin(actor)
    if type(actor) ~= "table" then return nil end
    if rawget(actor, "Alive") ~= true then return nil end
    local cf = rawget(actor, "CFrame")
    if typeof(cf) ~= "CFrame" then return nil end

    local sp = rawget(actor, "SimulatedPosition") or rawget(actor, "Position")
    if typeof(sp) == "Vector3" and (cf.Position - sp).Magnitude >= KA_ORIGIN_MAX_DRIFT then
        return nil
    end
    return cf:PointToWorldSpace(Vector3.new(0, 2.5, 0))
end

local function impactDir(actor, aimPart, reach)
    local aimPoint = State.kaAimPoint
    if typeof(aimPoint) ~= "Vector3" and aimPart and aimPart.Parent then
        aimPoint = aimPart.Position
    end
    local cam  = Workspace.CurrentCamera
    local look = (cam and cam.CFrame.LookVector) or Vector3.new(0, 0, -1)
    if typeof(aimPoint) ~= "Vector3" then return look * reach end

    local origin = kaImpactOrigin(actor)
    if typeof(origin) ~= "Vector3" then return look * reach end
    local to  = aimPoint - origin
    local dir = (to.Magnitude > 0.05) and to.Unit or look
    return dir * reach
end

local function resolveHitUid(targetUid, aimPart)
    if targetUid ~= nil then
        return Bridge.normalizeActorUid and Bridge.normalizeActorUid(targetUid) or tostring(targetUid)
    end
    if aimPart and aimPart.GetAttribute then
        local a = aimPart:GetAttribute("ActorUID")
        if a ~= nil then return tostring(a) end
    end
    return nil
end

local function resolveHitPart(aimPart, targetData)
    local forceBone = CONFIG.KillAuraForceBone
    if forceBone and type(targetData) == "table" and targetData.model and targetData.model.Parent then
        local forced = targetData.model:FindFirstChild(forceBone)
        if forced and forced:IsA("BasePart") then return forced end
    end

    if aimPart and aimPart:IsA("BasePart") and aimPart.Parent then return aimPart end
    local fb = CONFIG.KillAuraForceBone or "Head"
    warn("[KA] resolveHitPart: кость '", tostring(fb), "' не найдена в model. aimPart=", tostring(aimPart),
         "model=", type(targetData) == "table" and tostring(targetData.model) or "nil")
    return nil
end

local function syntheticImpact(aimPart, targetUid, targetData)
    local hitPos = State.kaAimPoint
    if typeof(hitPos) ~= "Vector3" then hitPos = aimPart and aimPart.Position end
    if typeof(hitPos) ~= "Vector3" then return nil end
    local part = resolveHitPart(aimPart, targetData)
    local uid  = resolveHitUid(targetUid, part or aimPart)
    if uid == nil then return nil end

    local boneName = (CONFIG.KillAuraForceBone)
        or (part and part.Name)
        or "Head"
    return hitPos, uid, boneName
end

local function findImpactFn(actor, ctx)
    local rep = getRepHandler(actor, ctx)
    return rep and getHandlerMethod(rep, "Impact") or nil
end

local function steeredImpact(self, dir, origImpact)
    if type(origImpact) ~= "function" then return nil end
    local aimPart   = State.kaImpactPart
    local targetUid = State.kaImpactUid
    local targetData = State.kaTarget
    if not aimPart and typeof(State.kaAimPoint) ~= "Vector3" then
        return origImpact(self, dir)
    end
    local reach = typeof(dir) == "Vector3" and dir.Magnitude or rawget(self, "_distance") or 5
    if type(reach) ~= "number" or reach <= 0 then reach = 5 end
    local actor = type(self) == "table" and rawget(self, "_actor")
    local steerDir = impactDir(actor, aimPart, reach)
    local ok, hitPos, uid, bone = pcall(function() return origImpact(self, steerDir) end)
    if ok and typeof(hitPos) == "Vector3" and uid ~= nil and bone then
        local fb = CONFIG.KillAuraForceBone
        return hitPos, uid, fb or bone
    end

    local sPos, sUid, sBone = syntheticImpact(aimPart, targetUid, targetData)
    if sPos then return sPos, sUid, sBone end
    warn("[KA] steeredImpact: origImpact промахнулся и synthetic не разрешил uid. aimPart=",
        tostring(aimPart), "targetUid=", tostring(targetUid))
    return nil
end

local function ensureRepImpactHook(actor, ctx)
    if type(hookfunction) ~= "function" then return false end
    local impactFn = findImpactFn(actor, ctx)
    if type(impactFn) ~= "function" then return false end
    State.kaImpactHookedFns = State.kaImpactHookedFns or {}
    if State.kaImpactHookedFns[impactFn] then return true end
    local origImpact
    local wrap = (type(newcclosure) == "function" and newcclosure or function(f) return f end)

    origImpact = hookfunction(impactFn, wrap((function(self, dir, ...)
        if State.kaImpactSteer and (State.kaImpactPart or typeof(State.kaAimPoint) == "Vector3") then
            return steeredImpact(self, dir, origImpact)
        end
        return origImpact(self, dir, ...)
    end)))
    State.kaImpactHookedFns[impactFn] = origImpact
    State.kaImpactFnHooked = true
    return true
end

local function ensureUseSpeedHook(svc)
    if not CONFIG.MeleeSwingSpeed then return false end
    if type(hookfunction) ~= "function" then return false end
    if type(svc) ~= "table" then return false end
    local useFn = getHandlerMethod(svc, "_use")
    if type(useFn) ~= "function" then return false end
    State.kaUseHookedFns = State.kaUseHookedFns or {}
    if State.kaUseHookedFns[useFn] then return true end

    local wrap = (type(newcclosure) == "function" and newcclosure or function(f) return f end)
    local origUse

    origUse = hookfunction(useFn, wrap((function(self, swinging, ...)

        if type(self) == "table" then
            State.kaTimerOrig = State.kaTimerOrig or setmetatable({}, {__mode = "k"})
            local orig = State.kaTimerOrig[self]
            if not orig then
                orig = { t = rawget(self, "_timer"), d = rawget(self, "_delay") }
                State.kaTimerOrig[self] = orig
            end
            if swinging and CONFIG.MeleeSwingSpeed then
                local mult = CONFIG.MeleeSwingSpeedMult or 1.0

                local isSelf = State.kaUseThreadActive == true
                if (not isSelf) and mult > 0 and type(orig.t) == "number" then
                    rawset(self, "_timer", orig.t / mult)
                    if CONFIG.MeleeSwingScaleDelay and type(orig.d) == "number" then
                        rawset(self, "_delay", orig.d / mult)
                    end
                else

                    if type(orig.t) == "number" then rawset(self, "_timer", orig.t) end
                    if type(orig.d) == "number" then rawset(self, "_delay", orig.d) end
                end
            end
        end
        return origUse(self, swinging, ...)
    end)))
    State.kaUseHookedFns[useFn] = origUse
    State.kaUseSpeedHooked = true
    return true
end
_kaEnsureUseSpeedHook = ensureUseSpeedHook

local function triggerGameMeleeUse(svc, actor, ctx, aimPart, targetData)

    local useFn = getHandlerMethod(svc, "_use")
    if type(useFn) ~= "function" then
        warn("[KA] triggerGameMeleeUse: нет _use в svc —", tostring(svc))
        return false, "no_use"
    end
    if State.kaUseThreadActive then
        local since = State.kaUseThreadSince or 0
        if since > 0 and now() - since < 0.5 then return false, "use_busy" end
        State.kaUseThreadActive = false
    end
    local _, cd  = getKaTimings()
    local kaMode = CONFIG.KillAuraMode or "LegitAuto"
    local isPA   = (kaMode == "PacketAuto")

    local weaponDelay = isPA and (rawget(svc, "_delay") or 0.2) or 0

    State.kaUseThreadActive = true
    State.kaUseThreadSince  = now()

    if not isPA then
        task.spawn(function()
            local ok, err = pcall(useFn, svc, true)
            if not ok then
                State.kaUseThreadActive = false
                warn("[KA] _use(true) error:", tostring(err))
            end
        end)
    end

    local net    = State.kaUseEnv and State.kaUseEnv.net
    local v3fn   = Bridge.vector3ToTable
    local at     = getActionTypeInv()
    local actFn  = actor and getHandlerMethod(actor, "Action")
    local slashN = math.random(1, 3)

    local netFire = (net and net.FireServer and function(...) pcall(net.FireServer, net, ...) end)
        or Bridge.networkFireServer

    if isPA then
        if netFire then
            netFire("InventoryAction", "Slash", slashN)
        else
            warn("[KA] PacketAuto: нет netFire для Slash")
        end
    end

    local function sendImpact()
        local reach     = getKaReach()
        local dir       = impactDir(actor, aimPart, reach)
        local predictMs = CONFIG.KillAuraPredictMs or 0
        local aimPt     = State.kaAimPoint
        if predictMs > 0 and type(targetData) == "table" and targetData.model then
            local root = targetData.model:FindFirstChild("HumanoidRootPart") or targetData.root
            if root and root:IsA("BasePart") then
                local vel = root.AssemblyLinearVelocity
                if vel.Magnitude > 0.5 then
                    local dt = predictMs / 1000
                    aimPt = (typeof(aimPt) == "Vector3" and aimPt or root.Position) + vel * dt
                end
            end
        end
        local hitPos, uid, bone

        if isPA or CONFIG.KillAuraNoWallCheck then
            local part = resolveHitPart(aimPart, targetData)
            uid    = resolveHitUid(targetData and targetData.uid, part or aimPart)
            bone   = (CONFIG.KillAuraForceBone) or
                     (part and part.Name) or "Head"
            hitPos = typeof(aimPt) == "Vector3" and aimPt or (part and part.Position)
            if not hitPos or uid == nil then
                warn("[KA] synthetic impact: нет hitPos или uid — part:", tostring(part), "uid:", tostring(uid))
                return
            end

            do
                local origin = kaImpactOrigin(actor)

                if typeof(origin) ~= "Vector3" then
                    return
                end
                do
                    local pReach = packetImpactReach()
                    local to     = hitPos - origin
                    local along  = to.Magnitude
                    if along > pReach and along > 0.01 then
                        hitPos = origin + to.Unit * pReach
                    end
                end
            end
        else
            if at and actFn then
                State.kaImpactSteer = true
                State.kaImpactPart  = aimPart
                State.kaImpactUid   = targetData and targetData.uid or nil
                local ok2, hp, u, b = pcall(actFn, actor, at, "Impact", dir)
                State.kaImpactSteer = false
                State.kaImpactPart  = nil
                State.kaImpactUid   = nil
                if ok2 then hitPos, uid, bone = hp, u, b end
                local fb = CONFIG.KillAuraForceBone
                if fb then bone = fb end
            end
        end
        if typeof(hitPos) == "Vector3" and uid ~= nil and bone and v3fn then
            local t = v3fn(hitPos)
            if t then
                if netFire then
                    netFire("InventoryAction", "Impact", t, uid, bone)
                else
                    warn("[KA] Impact: нет netFire — Bridge.networkFireServer=", tostring(Bridge.networkFireServer))
                end
            else
                warn("[KA] Impact: vector3ToTable вернул nil для", tostring(hitPos))
            end
        else
            warn("[KA] Impact пакет не отправлен: hitPos=", tostring(hitPos),
                "uid=", tostring(uid), "bone=", tostring(bone), "v3fn=", tostring(v3fn))
        end
    end

    if isPA then

        if weaponDelay > 0.01 then
            task.delay(weaponDelay, sendImpact)
        else
            sendImpact()
        end

        task.delay(weaponDelay + 0.06, function()
            State.kaUseThreadActive = false
            State.kaUseThreadSince  = 0
        end)
    else

        task.delay(math.max(0.05, cd - 0.05), function()
            pcall(useFn, svc, false)
            State.kaUseThreadActive = false
            State.kaUseThreadSince  = 0
        end)
    end
    return true, isPA and weaponDelay or cd
end

local function kaHasValidAim(aimPart, aimPoint, targetData)
    if typeof(aimPoint) == "Vector3" then return true end
    if aimPart and aimPart.Parent then return true end
    if type(targetData) == "table" and targetData.inInactiveWorld then return true end
    return false
end

local function beginSwingState(aimPart, aimPoint, targetData)
    State.kaImpactSteer = true
    State.kaImpactPart  = aimPart
    State.kaImpactUid   = targetData and targetData.uid or nil
    State.kaSwingBusy   = true
end

local function endSwingState(cd)
    task.delay(cd or 0.55, function()
        State.kaSwingBusy   = false
        State.kaImpactSteer = false
        State.kaImpactPart  = nil
        State.kaImpactUid   = nil
    end)
end

local function markSwingSuccess()
    State.kaLastSwing  = now()
    State.kaSwingCount = (State.kaSwingCount or 0) + 1
end

local function clearSwingBusyIfStale()
    if not State.kaSwingBusy then return end
    if (State.kaLastSwing or 0) > 0 and now() - (State.kaLastSwing or 0) > 1.25 then
        releaseSwingState()
    end
end

local kaNetScanFailT = 0
local scanNetworkModule = (function()
    if type(State.networkModule) == "table" and rawget(State.networkModule, "_code") ~= nil then
        return State.networkModule
    end
    if now() - kaNetScanFailT < 3 then return nil end

    if type(filtergc) == "function" then
        local ok0, gc = pcall(filtergc, "table", {
            Keys = {"_code", "_key", "_events", "_functions"}
        })
        if ok0 and type(gc) == "table" then
            for _, v in ipairs(gc) do
                if type(rawget(v, "_code")) == "string"
                   and type(rawget(v, "_key")) == "table"
                   and type(rawget(v, "_events")) == "table" then
                    State.networkModule = v
                    return v
                end
            end
        end
    end

    if type(getnilinstances) ~= "function" then kaNetScanFailT = now() return nil end
    local ok1, nils = pcall(getnilinstances)
    if not ok1 or type(nils) ~= "table" then kaNetScanFailT = now() return nil end

    for _, inst in ipairs(nils) do
        local okC, cls = pcall(function() return inst.ClassName end)
        if not okC or cls ~= "LocalScript" then continue end
        local okN, nm  = pcall(function() return inst.Name end)
        if not okN or nm ~= "client" then continue end

        if type(getscriptclosure) ~= "function" then continue end
        local okF, fn = pcall(getscriptclosure, inst)
        if not okF or type(fn) ~= "function" then continue end

        for i = 1, 512 do
            local okU, uname, uval = pcall(debug.getupvalue, fn, i)
            if not okU or uname == nil then break end
            if type(uval) ~= "table" then continue end

            local code  = rawget(uval, "_code")
            local key   = rawget(uval, "_key")
            local evts  = rawget(uval, "_events")
            local funcs = rawget(uval, "_functions")
            if type(code) == "string" and #code > 4
               and type(key) == "table" and #key == 5
               and type(evts) == "table"
               and type(funcs) == "table" then

                local okFs, fs = pcall(function() return uval.FireServer end)
                if okFs and type(fs) == "function" then
                    State.networkModule = uval
                    return uval
                end
            end
        end
    end
    kaNetScanFailT = now()
    return nil
end)

local function triggerPacketAutoFire(actor, aimPart, targetData)

    local net = (State.kaUseEnv and State.kaUseEnv.net)
             or scanNetworkModule()

    local netFire
    if type(net) == "table" then
        local okFs, fs = pcall(function() return net.FireServer end)
        if okFs and type(fs) == "function" then
            netFire = function(...) pcall(net.FireServer, net, ...) end
        end
    end
    if not netFire and Bridge.networkFireServer then
        netFire = Bridge.networkFireServer
    end
    if not netFire then
        warn("[KA] PacketAuto: netFire не найден (net=", tostring(net),
             " Bridge.networkFireServer=", tostring(Bridge.networkFireServer), ")")
        return false, "no_net"
    end

    local v3fn = Bridge.vector3ToTable
    if not v3fn then
        warn("[KA] PacketAuto: vector3ToTable недоступен")
        return false, "no_v3fn"
    end

    local part   = resolveHitPart(aimPart, targetData)
    local uid    = resolveHitUid(targetData and targetData.uid, part or aimPart)
    local bone   = (CONFIG.KillAuraForceBone)
               or (part and part.Name)
               or "Head"
    local hitPos = State.kaAimPoint
    if typeof(hitPos) ~= "Vector3" then
        hitPos = part and part.Parent and part.Position
    end

    local predictMs = CONFIG.KillAuraPredictMs or 0
    if predictMs > 0 and type(targetData) == "table" and targetData.model then
        local root = targetData.model:FindFirstChild("HumanoidRootPart") or targetData.root
        if root and root:IsA("BasePart") then
            local vel = root.AssemblyLinearVelocity
            if vel.Magnitude > 0.5 then
                local dt = predictMs / 1000
                hitPos = (typeof(hitPos) == "Vector3" and hitPos or root.Position) + vel * dt
            end
        end
    end
    if typeof(hitPos) ~= "Vector3" then
        warn("[KA] PacketAuto: hitPos не разрешён. aimPart=", tostring(aimPart))
        return false, "no_hitpos"
    end

    do
        local origin = kaImpactOrigin(actor)

        if typeof(origin) ~= "Vector3" then
            return false, "no_origin"
        end
        do
            local reach = packetImpactReach()
            local to    = hitPos - origin
            local along = to.Magnitude
            if along > reach and along > 0.01 then
                hitPos = origin + to.Unit * reach
            end
        end
    end
    if uid == nil then
        warn("[KA] PacketAuto: uid не разрешён. targetData=", tostring(targetData))
        return false, "no_uid"
    end
    local t = v3fn(hitPos)
    if not t then
        warn("[KA] PacketAuto: vector3ToTable вернул nil")
        return false, "v3fn_nil"
    end

    netFire("InventoryAction", "Slash", math.random(1, 3))

    local svc = State.kaMeleeSvc
    local d = (type(svc) == "table" and rawget(svc, "_delay")) or 0.2
    if type(d) ~= "number" or d < 0 then d = 0.2 end
    if d > 0.01 then
        task.delay(d, function()
            netFire("InventoryAction", "Impact", t, uid, bone)
        end)
    else
        netFire("InventoryAction", "Impact", t, uid, bone)
    end
    return true
end

local function performSwing(actor, ctx, aimPart, aimPoint, targetData, resetCd)
    if State.kaSwingBusy then return false, "busy" end
    if type(actor) ~= "table" then return false, "no_actor" end

    if rawget(actor, "Alive") ~= true then return false, "actor_not_alive" end
    if rawget(actor, "_equipped") == nil then return false, "no_equip" end
    if not kaHasValidAim(aimPart, aimPoint, targetData) then return false, "no_aim" end
    local _, cd = getKaTimings()
    if not resetCd and now() - (State.kaLastSwing or 0) < cd then return false, "cooldown" end

    if not resetCd and now() - (State.kaLastAttempt or 0) < cd * 0.5 then return false, "backoff" end
    State.kaLastAttempt = now()
    local tpos = kaRefPos(targetData) or (aimPart and aimPart.Position) or aimPoint
    if typeof(tpos) == "Vector3"
        and (tpos - kaLosOrigin(actor)).Magnitude > kaDist() + 1 then
        return false, "out_of_reach"
    end

    local kaMode = CONFIG.KillAuraMode or "LegitAuto"

    if kaMode == "PacketAuto" then

        do
            local origin = kaImpactOrigin(actor)
            local tp = kaRefPos(targetData) or (aimPart and aimPart.Position) or aimPoint
            if typeof(tp) == "Vector3" and typeof(origin) == "Vector3"
                and (tp - origin).Magnitude > packetImpactReach() then
                return false, "packet_out_of_reach"
            end
        end
        pcall(ensureMeleeSvc, actor, ctx)
        beginSwingState(aimPart, aimPoint, targetData)
        local ok, reason = triggerPacketAutoFire(actor, aimPart, targetData)
        if ok then
            markSwingSuccess()
            kaPacketPulse = now()
            if _kaSpawnPacketShock then _kaSpawnPacketShock() end
            State.kaLastImpactMode = "packet_auto"
            State.kaLastImpactNet  = "packet_auto"
            endSwingState(cd)
            return true, "packet_auto"
        end
        releaseSwingState()
        return false, reason or "pa_fail"
    end

    local eqUid = normalizeEqUid(rawget(actor, "_equipped"))
    local svc   = select(1, ensureMeleeSvc(actor, ctx))
    pcall(ensureRepImpactHook, actor, ctx)
    beginSwingState(aimPart, aimPoint, targetData)
    if svc and meleeSvcReady(eqUid) then
        local act = rawget(svc, "_actor")
        if type(act) == "table" and rawget(act, "Locked") then
            releaseSwingState()
            return false, "actor_locked"
        end
        local okUse, useInfo = triggerGameMeleeUse(svc, actor, ctx, aimPart, targetData)
        if okUse then
            markSwingSuccess()
            State.kaLastSlashNet   = "game._use"
            State.kaLastImpactMode = "game._use"
            State.kaLastImpactNet  = "game._use"
            endSwingState(type(useInfo) == "number" and useInfo or cd)
            return true, "game._use"
        end
        releaseSwingState()
    end
    warn("[KA] performSwing: svc=nil после ensureMeleeSvc. equipped=",
        tostring(rawget(actor, "_equipped")), "actor=", tostring(actor))
    releaseSwingState()
    return false, "no_svc"
end

local function countEnemies()
    local n, e = 0, 0
    for _, d in pairs(State.actors or {}) do
        n = n + 1
        if not Bridge.isEnemyActor or Bridge.isEnemyActor(d) then e = e + 1 end
    end
    return n, e
end

local function ensureViz()
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return end
    local segN = CONFIG.KillAuraVizSegments or 24
    local have = #kaVizLines
    if have == segN then return end
    if have < segN then
        for i = have + 1, segN do
            local seg = Drawing.new("Line")

            seg.Transparency = 1
            seg.Visible = false
            kaVizLines[i] = seg
        end
    else
        for i = have, segN + 1, -1 do
            Bridge.destroyDrawing(kaVizLines[i])
            kaVizLines[i] = nil
        end
    end

    kaVizAngleCacheN = 0
end

local function ensureAngleCache(segN)
    if kaVizAngleCacheN == segN then return end
    local pi2 = math.pi * 2
    for i = 0, segN - 1 do
        local a = (i / segN) * pi2
        kaVizCosCache[i] = math.cos(a)
        kaVizSinCache[i] = math.sin(a)

        kaVizScrX[i] = 0; kaVizScrY[i] = 0
        kaVizVis[i]  = false
        kaVizColR[i] = 0; kaVizColG[i] = 0; kaVizColB[i] = 0
    end

    local i = segN
    while kaVizCosCache[i] ~= nil do
        kaVizCosCache[i] = nil; kaVizSinCache[i] = nil
        kaVizScrX[i] = nil; kaVizScrY[i] = nil; kaVizVis[i] = nil
        kaVizColR[i] = nil; kaVizColG[i] = nil; kaVizColB[i] = nil
        i = i + 1
    end
    kaVizAngleCacheN = segN
end

local function hideViz()
    kaVizActive = false
    if not kaVizShown then return end
    kaVizShown = false
    for i = 1, #kaVizLines do
        kaVizLines[i].Visible = false
    end
end

local kaVizSpringY      = nil
local kaVizSpringVel    = 0
local kaVizGoingToHead  = true
local kaVizLastFrameT   = 0
local kaVizTargetKey    = nil
local KA_VIZ_SPRING_K    = 48
local KA_VIZ_SPRING_DAMP = 6
local KA_VIZ_EDGE_EPS    = 0.1

local function lerpColor(a, b, t)
    t = math.clamp(t, 0, 1)
    return Color3.new(
        a.R + (b.R - a.R) * t,
        a.G + (b.G - a.G) * t,
        a.B + (b.B - a.B) * t
    )
end

local function getLiveTargetPos(target)

    if type(target) ~= "table" then return nil end
    local model = target.model
    if model and model.Parent then
        local hrp = model:FindFirstChild("HumanoidRootPart")
        if hrp and hrp:IsA("BasePart") then return hrp.Position end
    end
    local root = target.root
    if root and root.Parent and root:IsA("BasePart") then return root.Position end
    return kaRefPos(target)
end

local KA_PV_SEG   = tonumber(CONFIG.KillAuraPacketVizSegments) or 32
local KA_PV_SHOCK = tonumber(CONFIG.KillAuraPacketVizShockN) or 3
local kaPvRing    = {}
local kaPvBase    = {}
local kaPvShock   = {}
local kaPvShockT  = {}
local kaPvShockHead = 1
local kaPvBuilt   = false

local kaPvCos, kaPvSin = {}, {}

local function ensurePacketViz()
    if kaPvBuilt then return end
    if type(Drawing) ~= "table" or type(Drawing.new) ~= "function" then return end
    local function mkLine(z)
        local l = Drawing.new("Line"); l.Visible = false; l.Thickness = 2
        l.ZIndex = z or 20; return l
    end
    for i = 1, KA_PV_SEG do
        kaPvRing[i] = mkLine(21)
        kaPvBase[i] = mkLine(19)
        local ang = (i - 1) / KA_PV_SEG * math.pi * 2
        kaPvCos[i] = math.cos(ang); kaPvSin[i] = math.sin(ang)
    end
    for w = 1, KA_PV_SHOCK do
        local ring = {}
        for i = 1, KA_PV_SEG do ring[i] = mkLine(20) end
        kaPvShock[w]  = ring
        kaPvShockT[w] = -999
    end
    kaPvBuilt = true
end

local function hidePacketViz()
    if not kaPvBuilt or not kaPvShown then return end
    kaPvShown = false
    for i = 1, KA_PV_SEG do kaPvRing[i].Visible = false; kaPvBase[i].Visible = false end
    for w = 1, KA_PV_SHOCK do
        local ring = kaPvShock[w]
        for i = 1, KA_PV_SEG do ring[i].Visible = false end
    end
end

local function kaDestroyVizPools()
    for i = #kaVizLines, 1, -1 do
        Bridge.destroyDrawing(kaVizLines[i])
        kaVizLines[i] = nil
    end
    kaVizAngleCacheN = 0
    kaVizShown  = false
    kaVizActive = false
    if kaPvBuilt then
        for i = 1, KA_PV_SEG do
            Bridge.destroyDrawing(kaPvRing[i]); kaPvRing[i] = nil
            Bridge.destroyDrawing(kaPvBase[i]); kaPvBase[i] = nil
        end
        for w = 1, KA_PV_SHOCK do
            local ring = kaPvShock[w]
            if ring then
                for i = 1, KA_PV_SEG do Bridge.destroyDrawing(ring[i]); ring[i] = nil end
            end
            kaPvShock[w]  = nil
            kaPvShockT[w] = -999
        end
        kaPvShockHead = 1
        kaPvBuilt = false
        kaPvShown = false
    end
end

local function spawnPacketShock()
    if not kaPvBuilt or CONFIG.KillAuraPacketVizShock == false then return end
    kaPvShockT[kaPvShockHead] = now()
    kaPvShockHead = (kaPvShockHead % KA_PV_SHOCK) + 1
end
_kaSpawnPacketShock = spawnPacketShock

local function drawRing(pool, cx, cy, r, col, thick, alpha)
    for i = 1, KA_PV_SEG do
        local j  = (i % KA_PV_SEG) + 1
        local ln = pool[i]
        ln.From = Vector2.new(cx + kaPvCos[i] * r, cy + kaPvSin[i] * r)
        ln.To   = Vector2.new(cx + kaPvCos[j] * r, cy + kaPvSin[j] * r)
        ln.Color = col; ln.Thickness = thick
        ln.Transparency = alpha or 1
        ln.Visible = true
    end
end

local function updatePacketViz(target, cam)
    if CONFIG.KillAuraPacketViz == false then hidePacketViz() return end
    ensurePacketViz()
    if not kaPvBuilt then return end

    local model = target.model
    local headPos, feetPos
    if model and model.Parent then
        local head = model:FindFirstChild("Head")
        local hrp  = model:FindFirstChild("HumanoidRootPart") or target.root
        if head and head:IsA("BasePart") then headPos = head.Position + Vector3.new(0, head.Size.Y * 0.5, 0) end
        if hrp  and hrp:IsA("BasePart")  then feetPos = hrp.Position - Vector3.new(0, 3.0, 0) end
    end
    local live = getLiveTargetPos(target) or State.kaAimPoint
    if not headPos or not feetPos then
        if typeof(live) ~= "Vector3" then hidePacketViz() return end
        headPos = live + Vector3.new(0, 1.6, 0)
        feetPos = live - Vector3.new(0, 3.0, 0)
    end

    local topS, onT = cam:WorldToViewportPoint(headPos)
    local botS, onB = cam:WorldToViewportPoint(feetPos)
    if not (onT and onB) or topS.Z <= 0.01 or botS.Z <= 0.01 then hidePacketViz() return end
    kaPvShown = true

    local minY  = math.min(topS.Y, botS.Y)
    local maxY  = math.max(topS.Y, botS.Y)
    local cX    = (topS.X + botS.X) * 0.5
    local cY    = (minY + maxY) * 0.5
    local boxH  = maxY - minY
    local ringR = math.max(boxH * 0.34, 10)

    local t     = now()
    local pulse = math.clamp(1 - (t - kaPacketPulse) / 0.28, 0, 1)
    local thick = (CONFIG.KillAuraPacketVizThick or 2.0)
    local baseC = CONFIG.KillAuraPacketVizColor or Color3.fromRGB(120, 210, 255)
    local flashC= CONFIG.KillAuraPacketVizFlash or Color3.fromRGB(255, 255, 255)
    local col   = lerpColor(baseC, flashC, pulse)

    local baseR   = ringR * (1 + pulse * 0.10)
    local baseA   = CONFIG.KillAuraPacketVizBaseAlpha or 0.45
    for i = 1, KA_PV_SEG do
        local j  = (i % KA_PV_SEG) + 1
        local ln = kaPvBase[i]
        ln.From = Vector2.new(cX + kaPvCos[i] * baseR, cY + kaPvSin[i] * baseR)
        ln.To   = Vector2.new(cX + kaPvCos[j] * baseR, cY + kaPvSin[j] * baseR)
        ln.Color = col; ln.Thickness = math.max(thick - 0.6, 1)
        ln.Transparency = baseA
        ln.Visible = true
    end

    local rr = ringR * (1 + pulse * 0.12)
    for i = 1, KA_PV_SEG do
        local ln = kaPvRing[i]
        local j  = (i % KA_PV_SEG) + 1
        ln.From = Vector2.new(cX + kaPvCos[i] * rr, cY + kaPvSin[i] * rr)
        ln.To   = Vector2.new(cX + kaPvCos[j] * rr, cY + kaPvSin[j] * rr)
        ln.Color = col; ln.Thickness = thick + pulse * 1.2
        ln.Transparency = 1
        ln.Visible = true
    end

    if CONFIG.KillAuraPacketVizShock ~= false then
        for w = 1, KA_PV_SHOCK do
            local age = t - kaPvShockT[w]
            local ring = kaPvShock[w]
            if age >= 0 and age < 0.45 then
                local k = age / 0.45
                local r = ringR * (0.5 + k * 1.6)
                local a = 1 - k
                drawRing(ring, cX, cY, r, col, math.max(thick * (1 - k), 0.5), a)
            else
                for i = 1, KA_PV_SEG do ring[i].Visible = false end
            end
        end
    end
end

local function updateViz(actor)
    local target = State.kaTarget
    if not CONFIG.KillAura or CONFIG.KillAuraViz == false
       or not (State.kaCtx and State.kaCtx.isMelee)
       or not target then
        hideViz()
        hidePacketViz()
            return
    end
    local cam = getCamera()
    if not cam then hideViz(); hidePacketViz() return end

    if (CONFIG.KillAuraMode or "LegitAuto") == "PacketAuto" then
        hideViz()
        updatePacketViz(target, cam)
        return
    else
        hidePacketViz()
    end

    local livePos = getLiveTargetPos(target) or State.kaAimPoint
    if typeof(livePos) ~= "Vector3" then hideViz() return end

    local model  = target.model
    local headY, feetY
    if model and model.Parent then
        local head = model:FindFirstChild("Head")
        local hrp  = model:FindFirstChild("HumanoidRootPart") or target.root
        if head and head:IsA("BasePart") then headY = head.Position.Y + 0.25 end
        if hrp  and hrp:IsA("BasePart")  then feetY = hrp.Position.Y - 3.0  end
    end
    if not headY or not feetY then
        headY = livePos.Y + 1.4
        feetY = livePos.Y - 2.4
    end
    if headY < feetY then headY, feetY = feetY, headY end

    local segN = CONFIG.KillAuraVizSegments or 24
    ensureViz()
    if #kaVizLines == 0 then return end
    ensureAngleCache(segN)

    local key = target.uid or target
    if kaVizTargetKey ~= key then
        kaVizTargetKey = key
        if kaVizSpringY == nil then
            kaVizSpringY = headY; kaVizSpringVel = 0; kaVizGoingToHead = false
        end
    end
    if kaVizSpringY == nil then
        kaVizSpringY = headY; kaVizSpringVel = 0
        kaVizGoingToHead = false
    end

    local t  = now()
    local dt = math.clamp(t - kaVizLastFrameT, 0, 0.1)
    kaVizLastFrameT = t

    local goal  = kaVizGoingToHead and headY or feetY
    local accel = (goal - kaVizSpringY) * KA_VIZ_SPRING_K - kaVizSpringVel * KA_VIZ_SPRING_DAMP
    kaVizSpringVel = kaVizSpringVel + accel * dt
    kaVizSpringY   = kaVizSpringY   + kaVizSpringVel * dt
    if math.abs(kaVizSpringY - goal) < KA_VIZ_EDGE_EPS and math.abs(kaVizSpringVel) < 2.0 then
        kaVizGoingToHead = not kaVizGoingToHead
    end

    local span  = math.max(headY - feetY, 0.01)
    local edgeP = 1 - math.clamp(
        math.min(math.abs(kaVizSpringY-headY), math.abs(kaVizSpringY-feetY)) / (span*0.5), 0, 1)
    local velSoft = kaVizSpringVel / (math.abs(kaVizSpringVel) + 0.8)
    local squish  = edgeP * 0.13 * velSoft

    local baseRadius = CONFIG.KillAuraVizRadius    or 1.8
    local warpAmpTgt = CONFIG.KillAuraVizWarpAmp   or 0.16
    local breathAmpT = CONFIG.KillAuraVizBreathAmp or 0.10
    local breathFq   = CONFIG.KillAuraVizBreathFq  or 0.9
    local thickMin   = CONFIG.KillAuraVizThickMin  or 1.3
    local thickMax   = CONFIG.KillAuraVizThickMax  or 1.8
    local tiltAmp    = CONFIG.KillAuraVizTiltAmp   or 0.3
    local spinSpeed  = CONFIG.KillAuraVizSpinSpeed or 1.2
    local doSpin     = CONFIG.KillAuraVizSpin ~= false
    local colA       = CONFIG.KillAuraVizColorA or Color3.fromRGB(200, 140, 255)
    local colB       = CONFIG.KillAuraVizColorB or Color3.fromRGB(90,  205, 255)

    local lerpK = math.clamp(dt * 8, 0, 1)
    kaVizWarpAmpCur = kaVizWarpAmpCur + (warpAmpTgt - kaVizWarpAmpCur) * lerpK
    kaVizBreathCur  = kaVizBreathCur  + (breathAmpT - kaVizBreathCur)  * lerpK

    if doSpin then

        kaVizSpinAngle = (kaVizSpinAngle + spinSpeed * dt) % (math.pi * 20)
    end

    local radiusX  = baseRadius * (1 + squish)
    local radiusZ  = baseRadius * (1 - squish * 0.6)
    local center   = Vector3.new(livePos.X, kaVizSpringY, livePos.Z)
    local breathPh = t * breathFq * math.pi * 2
    local breath   = 1 + math.sin(breathPh) * kaVizBreathCur
    local gradPh   = t * 0.50
    local rotPh    = t * 0.80
    local tiltY    = tiltAmp * math.sin(t * 0.23)
    local tiltRot  = t * 0.17

    local sinceSwing = t - (State.kaLastSwing or -999)
    local flashRaw   = math.clamp(1 - sinceSwing / 0.35, 0, 1)
    local flash      = flashRaw * flashRaw
    kaVizFlash       = kaVizFlash + (flash - kaVizFlash) * math.clamp(dt * 22, 0, 1)

    local thickness = (thickMin + (thickMax - thickMin) * (0.5 + 0.5 * math.sin(breathPh)))
                      * (1 + kaVizFlash * 1.05)

    local ringAlpha = 1 - math.clamp(CONFIG.KillAuraVizTransparency or 0, 0, 0.95)

    local spin     = kaVizSpinAngle
    local wA       = kaVizWarpAmpCur
    local rX, rZ   = radiusX * breath, radiusZ * breath
    local colAR, colAG, colAB = colA.R, colA.G, colA.B
    local colBR, colBG, colBB = colB.R, colB.G, colB.B
    local cx, cy, cz = center.X, center.Y, center.Z

    for i = 0, segN - 1 do

        local baseAng = (i / segN) * math.pi * 2
        local ang     = baseAng + rotPh

        local warp = 1
            + math.sin(ang * 4 + spin)         * wA
            + math.sin(ang * 2 - spin * 0.7)   * (wA * 0.55)
            + math.sin(ang     + spin * 0.4)   * (wA * 0.30)

        local rx   = rX * warp
        local rz   = rZ * warp
        local cosA = math.cos(ang)
        local sinA = math.sin(ang)

        local sinB = math.sin(ang + tiltRot)
        local wx = cx + cosA * rx
        local wy = cy + sinB * tiltY
        local wz = cz + sinA * rz

        local scr, vis = cam:WorldToViewportPoint(Vector3.new(wx, wy, wz))
        kaVizScrX[i] = scr.X
        kaVizScrY[i] = scr.Y
        kaVizVis[i]  = vis

        local g = 0.5 + 0.5 * math.sin(baseAng + gradPh)
        local r = colAR + (colBR - colAR) * g
        local gg = colAG + (colBG - colAG) * g
        local b = colAB + (colBB - colAB) * g

        if kaVizFlash > 0.001 then
            local fb = kaVizFlash * 0.85
            r  = r  + (1 - r)  * fb
            gg = gg + (1 - gg) * fb
            b  = b  + (1 - b)  * fb
        end
        kaVizColR[i] = r
        kaVizColG[i] = gg
        kaVizColB[i] = b
    end

    local anyVis = false
    for i = 0, segN - 1 do
        local j   = (i + 1) % segN
        local seg = kaVizLines[i + 1]
        seg.Thickness = thickness
        if kaVizVis[i] and kaVizVis[j] then
            seg.From    = Vector2.new(kaVizScrX[i], kaVizScrY[i])
            seg.To      = Vector2.new(kaVizScrX[j], kaVizScrY[j])
            seg.Color   = Color3.new(kaVizColR[i], kaVizColG[i], kaVizColB[i])
            seg.Transparency = ringAlpha
            seg.Visible = true
            anyVis      = true
        else
            seg.Visible = false
        end
    end

    kaVizShown  = anyVis
    kaVizActive = anyVis
    if not anyVis then hideViz() end
end
local function kaTickCombat(actor, ctx, autoSwing)
    clearSwingBusyIfStale()

    if not validateTarget(actor) or now() - kaLastPickT >= (CONFIG.KillAuraPickInterval or 0.25) then
        pickTarget(true, actor)
    end
    local target, aimPart, aimPoint = State.kaTarget, State.kaAimPart, State.kaAimPoint

    if not target or typeof(aimPoint) ~= "Vector3" then
        setPhase("no_target")

        if (CONFIG.KillAuraMode or "LegitAuto") == "Hook" then
            State.kaImpactSteer = false
            State.kaImpactPart  = nil
            State.kaImpactUid   = nil
        end
        return
    end
    local kaMode = CONFIG.KillAuraMode or "LegitAuto"
    setPhase(autoSwing and "active" or "manual", target.label or target.uid)
    if autoSwing and now() - kaLastDiagT >= 4 then
        kaLastDiagT = now()
        local _, en = countEnemies()
        log("KA", "auto [" .. kaMode .. "]", State.kaLastPhase, State.kaLastPickSource or "-",
            State.kaLastSkip or "-", "actors", State.trackedActorCount or 0,
            "enemies", en, "svc", State.kaMeleeSvc ~= nil, "tgt", target.label or target.uid)
    end

    if kaMode == "Hook" then

        if rawget(actor, "Alive") ~= true or rawget(actor, "_equipped") == nil then
            State.kaImpactSteer = false
            State.kaImpactPart  = nil
            State.kaImpactUid   = nil
            return
        end
        pcall(ensureRepImpactHook, actor, ctx)
        State.kaImpactSteer = true
        State.kaImpactPart  = aimPart
        State.kaImpactUid   = target and target.uid or nil
        return
    end

    if autoSwing and not State.kaSwingBusy then
        local ok, reason = performSwing(actor, ctx, aimPart, aimPoint, target, false)
        if not ok then setPhase("skip", reason) end
    end
end

local function tickManualAssist()
    if not onLifeState() then setPhase("dead") return end
    local ctx = resolveMeleeContext(false)
    if not ctx then setPhase("no_melee") return end
    local actor = resolveActor(ctx)
    if not actor then setPhase("no_actor") return end
    ctx.actor = actor
    ensureMeleeSvc(actor, ctx)
    kaTickCombat(actor, ctx, false)
end

local function tick()

    if not CONFIG.KillAura then clearKaTarget() releaseSwingState() return end
    if not onLifeState() then setPhase("dead") return end

    if (CONFIG.KillAuraMode or "LegitAuto") == "Hook" then return tickManualAssist() end
    local ctx
    if now() - kaLastFullCtxT >= 0.8 then
        kaLastFullCtxT = now()
        ctx = resolveMeleeContext(true)
    else
        ctx = resolveMeleeContext(false)
    end

    if not ctx and now() - (State.kaCtxTime or 0) > 1.0 then
        ctx = resolveMeleeContext(true)
    end
    if not ctx then
        clearKaTarget()
        setPhase("no_melee")
        return
    end
    local actor = resolveActor(ctx)
    if not actor then setPhase("no_actor") return end
    ctx.actor = actor
    ensureMeleeSvc(actor, ctx)
    kaTickCombat(actor, ctx, true)
end

local kaVizErrWarnT = 0
local kaTickErrWarnT = 0
local function kaVizFrame()

    local ctx = State.kaCtx
    local actor = ctx and resolveActor(ctx) or nil
    if ctx and actor then
        local curEq = normalizeEqUid(rawget(actor, "_equipped")) or ""
        if curEq ~= (State.kaCtxEq or "") then

            State.kaCtx     = nil
            State.kaCtxTime = 0
            hideViz()
            hidePacketViz()
            return
        end
    end
    updateViz(actor)
end

local function dumpDebug(testSwing)
    refreshTeamAndRep(true)

    local fluxActor = getFluxLocalActor()
    print("====== KillAura v3 DEBUG (H) ======")
    if fluxActor then
        print(string.format("[FluxActor] Alive=%s Health=%s Downed=%s",
            tostring(rawget(fluxActor, "Alive")),
            tostring(rawget(fluxActor, "Health")),
            tostring(rawget(fluxActor, "Downed"))))
    else
        print("[FluxActor] NOT FOUND — getFluxLocalActor() returned nil")
    end
    print("isLocalAlive():", isLocalAlive())
    local ctx   = resolveMeleeContext(true)
    local actor = ctx and resolveActor(ctx) or nil
    local rep   = actor and getRepHandler(actor, ctx) or nil
    local eq    = actor and rawget(actor, "_equipped") or nil
    local svc   = State.kaMeleeSvc
    print("melee:", ctx ~= nil, "equipped:", tostring(eq), "rep:", rep ~= nil,
        "build:", rep and rawget(rep, "_build"))
    print("svc:", svc ~= nil,
        "useFn:", svc and getHandlerMethod(svc, "_use") ~= nil,
        "svcSrc:", State.kaSvcSrc or "nil",
        "bootEq:", tostring(State.kaBootEq),
        "ctxEq:", tostring(State.kaCtxEq))
    print("warmup:", State.kaWarmupDone == true,
        "swingBusy:", State.kaSwingBusy == true,
        "useThread:", State.kaUseThreadActive == true)
    local t, p, pt = pickTarget(true, actor)
    print("picked:", t and (t.label or t.uid) or "NONE",
        "part:", p and p.Name or "nil",
        "point:", pt)
    if testSwing and actor and typeof(pt) == "Vector3" then
        State.kaLastSwing = 0
        releaseSwingState()
        print("test swing:", performSwing(actor, ctx, p, pt, t, true))
    end
    print("===================================")
end

local _M = {}
_M.CONFIG = KA_CONFIG

function _M.start()
    if kaConn then return end

    for k, v in pairs(KA_CONFIG) do
        if CONFIG[k] == nil then CONFIG[k] = v end
    end

    if Bridge.markModuleRunning then Bridge.markModuleRunning("killaura", true)
    else State.running = true end
    pcall(function()
        if type(shared) == "table" and type(shared.import) == "function" then
            local ok, net = pcall(shared.import, "network")

            if ok and type(net) == "table" then
                State.networkModule       = net
                State.networkModuleSource = "shared.import"
            end
        end
    end)
    if kaInputConn then kaInputConn:Disconnect() end
    kaInputConn = UIS.InputBegan:Connect(function(input, processed)
        if processed or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local key = input.KeyCode
        if CONFIG.KillAuraDebugKey and key == CONFIG.KillAuraDebugKey then
            task.spawn(function() dumpDebug(true) end)
        end
    end)
    local lp = Players.LocalPlayer
    if kaCharConn then kaCharConn:Disconnect() end
    if lp then
        kaCharConn = lp.CharacterAdded:Connect(function()
            kaCharGraceUntil    = now() + KA_CHAR_GRACE
            State.kaWasDead     = false
            _fluxActorCache     = nil
            _fluxActorCacheTime = 0
            clearKaTarget()
            releaseSwingState()
            clearMeleeBoot()
            task.defer(function()
                pcall(function()
                    if Bridge.resolveLocalActor then Bridge.resolveLocalActor(true) end
                end)
            end)
        end)
    end
    local acc = 0

    kaConn = RunService.Heartbeat:Connect((function(dt)
        if not State.running or not CONFIG.KillAura then

            if State.kaImpactSteer or State.kaSwingBusy or State.kaTarget then
                clearKaTarget()
                releaseSwingState()
            end
            return
        end
        acc = acc + dt
        if acc < (CONFIG.KillAuraTickInterval or 0.2) then return end
        acc = 0

        local ok, err = pcall(tick)
        if not ok and now() - kaTickErrWarnT > 3 then
            kaTickErrWarnT = now()
            warn("[KA] tick упал:", tostring(err))
        end
    end))

    kaVizConn = RunService.Heartbeat:Connect((function()
        if not State.running or not CONFIG.KillAura then hideViz(); hidePacketViz() return end
        local ok, err = pcall(kaVizFrame)
        if not ok and now() - kaVizErrWarnT > 3 then
            kaVizErrWarnT = now()
            warn("[KA] viz frame error:", tostring(err))
        end
    end))
    task.defer(function()
        if not State.running or not CONFIG.KillAura then return end
        refreshTeamAndRep(true)
        local ctx   = resolveMeleeContext(true)
        local actor = ctx and resolveActor(ctx) or nil
        if actor and ctx then ensureMeleeSvc(actor, ctx) end
    end)
    log("KA", "v3 started | dist=", kaDist())
end

local function kaRestoreSvcMods(svc)
    if type(svc) ~= "table" then return end
    for _, field in ipairs({ "_slash", "_slashTP", "_equip", "_idle" }) do
        local track = rawget(svc, field)
        if track and type(track.AdjustSpeed) == "function" then
            pcall(track.AdjustSpeed, track, 1)
        end
    end
    local dOrig = State.kaDistOrig
    local base  = type(dOrig) == "table" and dOrig[svc] or nil
    if type(base) == "number" then pcall(rawset, svc, "_distance", base) end
    local tOrig = State.kaTimerOrig
    local orig  = type(tOrig) == "table" and tOrig[svc] or nil
    if type(orig) == "table" then
        if type(orig.t) == "number" then pcall(rawset, svc, "_timer", orig.t) end
        if type(orig.d) == "number" then pcall(rawset, svc, "_delay", orig.d) end
    end
end

function _M.stop()

    if Bridge.markModuleRunning then Bridge.markModuleRunning("killaura", false) end
    if kaConn     then kaConn:Disconnect()     kaConn     = nil end
    if kaVizConn  then kaVizConn:Disconnect()  kaVizConn  = nil end
    if kaInputConn then kaInputConn:Disconnect() kaInputConn = nil end
    if kaCharConn  then kaCharConn:Disconnect() kaCharConn  = nil end
    hideViz()
    hidePacketViz()

    kaDestroyVizPools()
    clearKaTarget()
    releaseSwingState()

    State.kaImpactSteer = false
    State.kaImpactPart  = nil
    State.kaImpactUid   = nil

    if type(hookfunction) == "function" then
        for fn, orig in pairs(State.kaImpactHookedFns or {}) do
            pcall(hookfunction, fn, orig)
        end
        for fn, orig in pairs(State.kaUseHookedFns or {}) do
            pcall(hookfunction, fn, orig)
        end
    end
    State.kaImpactHookedFns = nil
    State.kaImpactFnHooked  = nil
    State.kaUseHookedFns    = nil
    State.kaUseSpeedHooked  = nil

    local restored = {}
    local function restoreOnce(svc)
        if type(svc) == "table" and not restored[svc] then
            restored[svc] = true
            pcall(kaRestoreSvcMods, svc)
        end
    end
    restoreOnce(State.kaMeleeSvc)
    if type(State.kaDistOrig) == "table" then
        for svc in pairs(State.kaDistOrig) do restoreOnce(svc) end
    end
    if type(State.kaTimerOrig) == "table" then
        for svc in pairs(State.kaTimerOrig) do restoreOnce(svc) end
    end
    State.kaDistOrig  = nil
    State.kaTimerOrig = nil

    clearMeleeBoot()
end

function _M.toggle()
    CONFIG.KillAura = not CONFIG.KillAura
    if CONFIG.KillAura and not kaConn then _M.start() end
    if not CONFIG.KillAura then clearKaTarget() releaseSwingState() end
    return CONFIG.KillAura
end

function _M.dumpStatus()  dumpDebug(false) end
function _M.debugDump()   dumpDebug(true)  end

function _M.swingOnce()

    if not isLocalAlive() then return false, "dead" end
    local ctx   = resolveMeleeContext(true)
    local actor = ctx and resolveActor(ctx) or nil
    local target, part, pt = pickTarget(true, actor)
    if not actor or typeof(pt) ~= "Vector3" then return false, "no_target" end
    State.kaLastSwing = 0
    releaseSwingState()
    return performSwing(actor, ctx, part, pt, target, true)
end

function _M.buildUI(ui)
    local flag = ui.flag or function(s) return "KA_" .. s end
    local tab = ui.tabs and ui.tabs.KillAura
    if not tab then return end

    local gmtab = ui.tabs and ui.tabs.GunMods
    local dtab = ui.tabs and ui.tabs.Debug

    local K = Bridge.makeUiKit(ui)

    local L = tab:Section({ Side = "Left" })

    K.feature(L, {
        Title = "Kill Aura", Flag = "KillAura",
        get = function() return CONFIG.KillAura end,
        set = function(v)
            CONFIG.KillAura = v

            if not v then clearKaTarget() releaseSwingState() end
        end,
        Desc = "hits whoever is in range for u\nbind works on PC + mobile",
    })

    K.dropdown(L, {
        Name = "Mode", Flag = "KAMode",
        Options = { "Hook", "PacketAuto", "LegitAuto" },
        Default = CONFIG.KillAuraMode or "Hook",
        Callback = function(v) CONFIG.KillAuraMode = v end,
        Desc = "Hook = redirects ur own swings, quietest\nPacketAuto = swings by itself, fastest n most obvious",
    })

    K.group(L, "Targeting")
    K.slider(L, { Name = "Distance", Flag = "KADistance", Default = CONFIG.KillAuraDistance,
        Min = 5, Max = 60, Suffix = " st",
        Callback = function(v) CONFIG.KillAuraDistance = v end,
        Desc = "how far we look for someone to hit" })
    K.slider(L, { Name = "FOV", Flag = "KAFOV", Default = CONFIG.KillAuraFOV,
        Min = 30, Max = 360, Suffix = "°",
        Callback = function(v) CONFIG.KillAuraFOV = v end,
        Desc = "360 = all around u" })
    K.dropdown(L, {
        Name = "Force Bone", Flag = "ForceBone",
        Options = { "Auto", "Head", "UpperTorso", "LowerTorso" },
        Default = CONFIG.KillAuraForceBone or "Head",
        Callback = function(v) CONFIG.KillAuraForceBone = (v == "Auto") and nil or v end,
    })
    K.slider(L, { Name = "Switch Margin", Flag = "SwitchMargin", Default = CONFIG.KillAuraSwitchMargin,
        Min = 0, Max = 10, Precision = 1, Suffix = " st",
        Callback = function(v) CONFIG.KillAuraSwitchMargin = v end,
        Desc = "how much closer a new guy must be before we ditch the current one\n0 = swaps constantly in a crowd" })
    K.toggle(L, { Name = "No Wall Check", Flag = "NoWall", Title = "No Wall Check",
        get = function() return CONFIG.KillAuraNoWallCheck end,
        set = function(v) CONFIG.KillAuraNoWallCheck = v end,
        Desc = "hits thru walls (client sided, obvious)" })

    K.group(L, "Timing")
    K.slider(L, { Name = "Prediction", Flag = "PredictMs", Default = CONFIG.KillAuraPredictMs,
        Min = 0, Max = 600, Suffix = " ms",
        Callback = function(v) CONFIG.KillAuraPredictMs = v end,
        Desc = "leads moving targets\nstart ~120 n tune from there" })
    K.slider(L, { Name = "Swing Cooldown", Flag = "SwingCd", Default = CONFIG.KillAuraSwingCd,
        Min = 0.1, Max = 1.5, Precision = 2, Suffix = " s",
        Callback = function(v) CONFIG.KillAuraSwingCd = v end,
        Desc = "lower = faster swings but way easier to spot" })
    K.slider(L, { Name = "Reach", Flag = "Reach", Default = CONFIG.KillAuraReach,
        Min = 5, Max = 999, Suffix = " st",
        Callback = function(v) CONFIG.KillAuraReach = v end })

    K.group(L, "Manual")
    K.button(L, { Name = "Swing Once", Flag = "SwingOnce", Title = "Kill Aura",
        Callback = function() _M.swingOnce(); return "swung" end })

    local R = (gmtab or tab):Section({ Side = "Right" })
    R:Header({ Name = "Melee Mods" })
    R:SubLabel({ Text = "client only — server packets stay untouched" })

    local function kaReapplyMods()
        State.kaModsAppliedEq = nil
        if State.kaMeleeSvc then pcall(applyMeleeMods, State.kaMeleeSvc) end
    end
    K.slider(R, { Name = "Anim Speed", Flag = "AnimSpeed", Default = CONFIG.MeleeAnimSpeed,
        Min = 1, Max = 5, Precision = 1, Suffix = "x",
        Callback = function(v) CONFIG.MeleeAnimSpeed = v; kaReapplyMods() end })
    K.slider(R, { Name = "Reach Boost", Flag = "ReachBoost", Default = CONFIG.MeleeReachBoost,
        Min = 0, Max = 15, Precision = 1, Suffix = " st",
        Callback = function(v) CONFIG.MeleeReachBoost = v; kaReapplyMods() end })

    local swingEls = {}
    local function swingVis()
        K.setVisible(swingEls, CONFIG.MeleeSwingSpeed == true)
    end
    K.toggle(R, { Name = "Manual Swing Speed", Flag = "SwingSpeedOn", Title = "Manual Swing Speed",
        get = function() return CONFIG.MeleeSwingSpeed end,
        set = function(v) CONFIG.MeleeSwingSpeed = v end,
        after = swingVis })
    swingEls[#swingEls + 1] = K.slider(R, { Name = "Swing Speed", Flag = "SwingSpeedMult",
        Default = CONFIG.MeleeSwingSpeedMult, Min = 1, Max = 5, Precision = 1, Suffix = "x",
        Callback = function(v) CONFIG.MeleeSwingSpeedMult = v end })
    swingEls[#swingEls + 1] = K.toggle(R, { Name = "Scale Hit Delay", Flag = "SwingScaleDelay",
        Title = "Scale Hit Delay",
        get = function() return CONFIG.MeleeSwingScaleDelay end,
        set = function(v) CONFIG.MeleeSwingScaleDelay = v end,
        Desc = "shrinks the slash→impact gap along with the anim" })
    swingVis()

    local V = tab:Section({ Side = "Right" })

    local ringEls = {}
    local function ringVis() K.setVisible(ringEls, CONFIG.KillAuraViz ~= false) end
    K.feature(V, {
        Title = "Target Ring", Flag = "Viz", NoKeybind = true,
        get = function() return CONFIG.KillAuraViz end,
        set = function(v) CONFIG.KillAuraViz = v; ringVis() end,
        Desc = "ring that orbits whoever ur locked on",
    })
    ringEls[#ringEls + 1] = K.color(V, { Name = "Color A", Flag = "VizColorA",
        Default = CONFIG.KillAuraVizColorA,
        Callback = function(c) CONFIG.KillAuraVizColorA = c end })
    ringEls[#ringEls + 1] = K.color(V, { Name = "Color B", Flag = "VizColorB",
        Default = CONFIG.KillAuraVizColorB,
        Callback = function(c) CONFIG.KillAuraVizColorB = c end })
    ringEls[#ringEls + 1] = K.slider(V, { Name = "Radius", Flag = "VizRadius",
        Default = CONFIG.KillAuraVizRadius, Min = 0.5, Max = 5, Precision = 1,
        Callback = function(v) CONFIG.KillAuraVizRadius = v end })
    ringEls[#ringEls + 1] = K.slider(V, { Name = "Segments", Flag = "VizSeg",
        Default = CONFIG.KillAuraVizSegments, Min = 8, Max = 48,
        Callback = function(v) CONFIG.KillAuraVizSegments = v end,
        Desc = "more = smoother ring, costs a bit of fps" })
    ringEls[#ringEls + 1] = K.toggle(V, { Name = "Spin", Flag = "VizSpin", Title = "Ring Spin",
        get = function() return CONFIG.KillAuraVizSpin end,
        set = function(v) CONFIG.KillAuraVizSpin = v end })
    ringEls[#ringEls + 1] = K.slider(V, { Name = "Spin Speed", Flag = "VizSpinSpeed",
        Default = CONFIG.KillAuraVizSpinSpeed, Min = 0, Max = 6, Precision = 1,
        Callback = function(v) CONFIG.KillAuraVizSpinSpeed = v end })
    ringEls[#ringEls + 1] = K.slider(V, { Name = "Transparency", Flag = "VizTransp",
        Default = math.floor((CONFIG.KillAuraVizTransparency or 0) * 100),
        Min = 0, Max = 95, Suffix = "%",
        Callback = function(v) CONFIG.KillAuraVizTransparency = v / 100 end })
    ringVis()

    K.group(V, "Lock-on HUD")
    local hudEls = {}
    local function hudVis() K.setVisible(hudEls, CONFIG.KillAuraPacketViz ~= false) end
    K.toggle(V, { Name = "Enabled", Flag = "PacketViz", Title = "Lock-on HUD",
        get = function() return CONFIG.KillAuraPacketViz end,
        set = function(v) CONFIG.KillAuraPacketViz = v; hudVis() end,
        Desc = "brackets on ur target, only in PacketAuto" })
    hudEls[#hudEls + 1] = K.color(V, { Name = "HUD Color", Flag = "PVizColor",
        Default = CONFIG.KillAuraPacketVizColor,
        Callback = function(c) CONFIG.KillAuraPacketVizColor = c end })
    hudEls[#hudEls + 1] = K.color(V, { Name = "Hit Flash", Flag = "PVizFlash",
        Default = CONFIG.KillAuraPacketVizFlash,
        Callback = function(c) CONFIG.KillAuraPacketVizFlash = c end })
    hudEls[#hudEls + 1] = K.slider(V, { Name = "Thickness", Flag = "PVizThick",
        Default = CONFIG.KillAuraPacketVizThick, Min = 1, Max = 5, Precision = 1,
        Callback = function(v) CONFIG.KillAuraPacketVizThick = v end })
    hudEls[#hudEls + 1] = K.toggle(V, { Name = "Shockwave on Hit", Flag = "PVizShock",
        Title = "Shockwave",
        get = function() return CONFIG.KillAuraPacketVizShock end,
        set = function(v) CONFIG.KillAuraPacketVizShock = v end })
    hudVis()

    if dtab then
        local D = dtab:Section({ Side = "Left" })
        D:Header({ Name = "Kill Aura" })
        K.slider(D, { Name = "Tick Interval", Flag = "DbgTick",
            Default = math.floor((CONFIG.KillAuraTickInterval or 0.2) * 1000),
            Min = 50, Max = 1000, Suffix = " ms",
            Callback = function(v) CONFIG.KillAuraTickInterval = v / 1000 end,
            Desc = "how often we look for a target" })
        K.slider(D, { Name = "Pick Interval", Flag = "DbgPick",
            Default = math.floor((CONFIG.KillAuraPickInterval or 0.25) * 1000),
            Min = 50, Max = 1000, Suffix = " ms",
            Callback = function(v) CONFIG.KillAuraPickInterval = v / 1000 end })
        K.slider(D, { Name = "Context Cache", Flag = "DbgCtx",
            Default = math.floor((CONFIG.KillAuraCtxCacheSec or 1.5) * 1000),
            Min = 500, Max = 5000, Suffix = " ms",
            Callback = function(v) CONFIG.KillAuraCtxCacheSec = v / 1000 end })

        K.group(D, "Diagnostics")
        K.button(D, { Name = "Dump State", Flag = "DbgDump", Title = "Kill Aura",
            Callback = function()
                task.spawn(function() dumpDebug(false) end)
                return "dumped to console"
            end })
        K.button(D, { Name = "Dump + Test Swing", Flag = "DbgDumpSwing", Title = "Kill Aura",
            Callback = function()
                task.spawn(function() dumpDebug(true) end)
                return "dumped to console"
            end })
    end

    K.ready()
end

do
    local g = (type(getgenv) == "function" and getgenv()) or _G
    local prev = g.BRM5_KA_MODULE
    if type(prev) == "table" and type(prev.stop) == "function" and prev ~= _M then
        pcall(prev.stop)
    end
    g.BRM5_KA_MODULE = _M
end

_M.Bridge            = Bridge
if Bridge.registerModule then Bridge.registerModule("killaura", _M) end
Bridge._killAuraModule = _M
return _M
end
