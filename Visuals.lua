return function(Lib)
    local CONFIG = Lib.CONFIG
    local State  = Lib.State
    local Bridge = Lib.Bridge

    local RunService = game:GetService("RunService")
    local UIS        = game:GetService("UserInputService")
    local Lighting   = game:GetService("Lighting")
    local Workspace  = game:GetService("Workspace")
    local Players    = game:GetService("Players")
    local PPS        = game:GetService("ProximityPromptService")
    local LP         = Players.LocalPlayer

    local function now() return os.clock() end
    local function log() end

    CONFIG.Visuals = CONFIG.Visuals or {}
    local V = CONFIG.Visuals

    local SETTINGS = {

        ViewmodelEnabled          = false,
        ViewmodelKey              = Enum.KeyCode.KeypadOne,
        ViewmodelColorEnabled     = true,
        ViewmodelColor            = Color3.fromRGB(0, 200, 255),

        ViewmodelMaterialEnabled  = true,
        ViewmodelMaterial         = Enum.Material.ForceField,
        ViewmodelTransparency     = 0,
        ViewmodelOffset           = Vector3.new(0, 0, 0),
        ViewmodelTilt             = 0,
        ViewmodelDepth            = 0,

        VmRestyleSec              = 3,
        WorldFOVEnabled           = false,
        WorldFOV                  = 70,

        GunModelEnabled           = false,
        GunModelKey               = Enum.KeyCode.KeypadTwo,
        GunModelHighlightEnabled  = true,
        GunModelFill              = Color3.fromRGB(0, 170, 255),
        GunModelOutline           = Color3.fromRGB(255, 255, 255),
        GunModelFillTransparency  = 0.5,
        GunModelOutlineTransparency = 0,

        GunModelColorEnabled      = true,
        GunModelColor             = Color3.fromRGB(0, 170, 255),
        GunModelMaterialEnabled   = true,
        GunModelMaterial          = Enum.Material.ForceField,
        GunModelTransparency      = 0,

        ThirdPersonEnabled        = false,
        ThirdPersonKey            = Enum.KeyCode.KeypadThree,
        ThirdPersonFill           = Color3.fromRGB(120, 200, 255),
        ThirdPersonOutline        = Color3.fromRGB(180, 235, 255),
        ThirdPersonFillTransparency = 0.55,
        ThirdPersonMaterial       = Enum.Material.Glass,
        ThirdPersonBodyColor      = Color3.fromRGB(120, 200, 255),
        ThirdPersonBodyTransparency = 0.35,

        ViewmodelGradientEnabled   = false,
        GunModelGradientEnabled    = false,
        GunModelHighlightGradient  = true,
        ThirdPersonGradientEnabled = false,
        GradientSpeed              = 0.35,
        GradientColorA             = Color3.fromRGB(190, 150, 255),
        GradientColorB             = Color3.fromRGB(120, 210, 255),
        GunModelGradientSpread     = 1.6,

        VehicleFlyEnabled         = false,
        VehicleFlyKey             = Enum.KeyCode.KeypadFour,
        VehicleFlySpeed           = 120,

        VehicleSpeedEnabled       = false,
        VehicleSpeedKey           = Enum.KeyCode.KeypadFive,
        VehicleSpeedMult          = 2.0,

        FreeGunEnabled            = false,
        FreeGunKey                = Enum.KeyCode.KeypadEnter,

        AmbientEnabled            = false,
        AmbientPreset             = "Custom",
        AmbientColor              = Color3.fromRGB(120, 120, 130),
        AmbientOutdoorColor       = Color3.fromRGB(140, 140, 150),
        AmbientTintTop            = Color3.fromRGB(0, 0, 0),
        AmbientTintBottom         = Color3.fromRGB(0, 0, 0),
        AmbientExposure           = 0,
        AmbientLatitude           = 45,
        AmbientDiffuse            = 1,
        AmbientSpecular           = 1,
        AmbientShadows            = true,
        AmbientFogEnabled         = false,
        AmbientFogColor           = Color3.fromRGB(150, 160, 175),
        AmbientFogStart           = 0,
        AmbientFogEnd             = 800,
        AmbientKey                = Enum.KeyCode.KeypadSix,
        AmbientClockTime          = 14,
        AmbientBrightness         = 2,

        NoFWaitEnabled            = false,
        NoFWaitKey                = Enum.KeyCode.KeypadSeven,

        LockpickBypassEnabled     = false,
        LockpickBypassKey         = Enum.KeyCode.KeypadEight,
        LockpickScanInterval      = 0.4,

        FullbrightEnabled         = false,
        FullbrightKey             = Enum.KeyCode.KeypadNine,

        NoFogEnabled              = false,
        NoFogKey                  = Enum.KeyCode.KeypadZero,
    }

    for k, val in pairs(SETTINGS) do if V[k] == nil then V[k] = val end end

    local function isCtrl(t)
        if type(t) ~= "table" then return false end
        if type(rawget(t, "MoveSpeed"))    ~= "number"  then return false end
        if type(rawget(t, "IsGrounded"))   ~= "boolean" then return false end
        if type(rawget(t, "IsSprinting"))  ~= "boolean" then return false end
        local la = rawget(t, "_localActor")
        if type(la) ~= "table" or rawget(la, "IsLocalPlayer") == false then return false end

        local backRef = rawget(la, "Controller")
        if type(backRef) == "table" and not rawequal(backRef, t)
        and type(rawget(backRef, "MoveSpeed")) == "number" then
            return false
        end
        return true
    end
    local _scanCd, _lastScan = 1.0, -999
    local _ctrl
    local _ctrlRescan = -999

    local function ctrlAlive(c)
        local la = c and rawget(c, "_localActor")
        return type(la) == "table" and rawget(la, "Alive") ~= false
    end

    local rescanCtrl = (function()
        if type(filtergc) ~= "function" then return nil end
        local ok, gc = pcall(filtergc, "table",
            { Keys = { "MoveSpeed", "VelocityGravity", "TrySprinting", "IsGrounded", "IsSprinting" } })
        if not ok then return nil end

        local firstValid
        for _, v in ipairs(gc) do
            if isCtrl(v) then
                firstValid = firstValid or v
                if ctrlAlive(v) then _ctrl = v; return v end
            end
        end
        if firstValid then _ctrl = firstValid end
        return firstValid
    end)
    local function findCtrl()

        if _ctrl and isCtrl(_ctrl) and ctrlAlive(_ctrl) then return _ctrl end

        local t = now()
        if t - _ctrlRescan < _scanCd then
            return (_ctrl and isCtrl(_ctrl)) and _ctrl or nil
        end
        _ctrlRescan = t
        local fresh = rescanCtrl()
        if fresh then return fresh end
        return (_ctrl and isCtrl(_ctrl)) and _ctrl or nil
    end

    local function getLA()
        local c = findCtrl()
        local la = c and rawget(c, "_localActor") or nil
        if type(la) == "table" and rawget(la, "Alive") ~= false then
            local ok, char = pcall(function() return la.Character end)

            if not (ok and typeof(char) == "Instance"
                    and char:IsA("Model") and char.Parent) then
                _ctrl = nil
            end
        end
        return la
    end

    local function isLockPick(t)
        return type(t) == "table"
            and type(rawget(t, "_picks")) == "number"
            and rawget(t, "_expires") ~= nil
            and type(rawget(t, "_localActor")) == "table"
            and rawget(t, "_cancelled") ~= nil
    end
    local findLockPick = (function()
        if type(filtergc) ~= "function" then return nil end
        local ok, gc = pcall(filtergc, "table",
            { Keys = { "_picks", "_speed", "_expires", "_cancelled" } })
        if not ok then return nil end
        for _, v in ipairs(gc) do
            if isLockPick(v) and not rawget(v, "_cancelled") then return v end
        end
    end)

    local function isNetObj(v)
        if type(v) ~= "table" then return false end
        local ok, fs = pcall(function() return v.FireServer end)
        return ok and type(fs) == "function"
            and type(rawget(v, "_code")) == "string"
            and type(rawget(v, "_events")) == "table"
    end
    local findNet = (function()
        if isNetObj(State.networkModule) then return State.networkModule end
        if type(filtergc) ~= "function" then return nil end
        local ok, gc = pcall(filtergc, "table",
            { Keys = { "_code", "_key", "_events", "_functions" } })
        if not ok then return nil end
        for _, v in ipairs(gc) do
            if isNetObj(v) then State.networkModule = v; return v end
        end
    end)

    local running     = false
    local vmHooked    = false
    local vmOrigRef   = nil
    local vmHookMode  = nil
    local vmHookTbl   = nil
    local vmHookFn    = nil

    local gunHighlight = nil

    local vmStyledParts  = {}
    local vmStyledVM     = nil
    local _vmStyleApplied = nil
    local _vmRestyleT     = 0

    local function restoreViewmodelStyle()
        for part, s in pairs(vmStyledParts) do

            if part then
                pcall(function()
                    part.Material    = s.M
                    part.Color       = s.C
                    part.Transparency = s.T
                    if s.tex ~= nil then part.TextureID = s.tex end
                end)
            end

            if s.sa then
                for _, rec in ipairs(s.sa) do
                    pcall(function()
                        if rec.inst and rec.parent then rec.inst.Parent = rec.parent end
                    end)
                end
            end
        end
        vmStyledParts = {}
        vmStyledVM    = nil
        _vmStyleApplied = nil
    end

    local function stylePartInto(d, store, opts)
        if not (d:IsA("BasePart") or d:IsA("MeshPart")) then return false end
        local paint = opts.colorOn or opts.matOn
        if store[d] == nil then
            local rec = { M = d.Material, C = d.Color, T = d.Transparency }

            if paint then
                if d:IsA("MeshPart") and d.TextureID ~= "" then rec.tex = d.TextureID end
                local sa = {}
                for _, ch in ipairs(d:GetChildren()) do
                    if ch:IsA("SurfaceAppearance") or ch:IsA("Decal") or ch:IsA("Texture") then
                        sa[#sa + 1] = { inst = ch, parent = ch.Parent }
                    end
                end
                if #sa > 0 then rec.sa = sa end
            end
            store[d] = rec
        end
        local rec = store[d]
        pcall(function()
            if opts.matOn   then d.Material = opts.mat   end
            if opts.colorOn then d.Color    = opts.color end
            if paint then
                if rec.tex ~= nil and d:IsA("MeshPart") and d.TextureID ~= "" then
                    d.TextureID = ""
                end
                if rec.sa then
                    for _, r in ipairs(rec.sa) do
                        if r.inst and r.inst.Parent then r.inst.Parent = nil end
                    end
                end
            end

            if (opts.transp or 0) > 0 then
                if d.Transparency < 1 then d.Transparency = opts.transp end
            elseif rec and (rec.T or 0) < 1 then
                d.Transparency = rec.T or 0
            end
        end)
        return true
    end

    local function restoreStore(store)
        for part, s in pairs(store) do

            if part then
                pcall(function()
                    part.Material     = s.M
                    part.Color        = s.C
                    part.Transparency = s.T
                    if s.tex ~= nil then part.TextureID = s.tex end
                end)
            end
            if s.sa then
                for _, rec in ipairs(s.sa) do
                    pcall(function()
                        if rec.inst and rec.parent then rec.inst.Parent = rec.parent end
                    end)
                end
            end
        end
        table.clear(store)
    end

    local function gradientColorAt(phase01)
        local a = V.GradientColorA or Color3.fromRGB(190, 150, 255)
        local b = V.GradientColorB or Color3.fromRGB(120, 210, 255)
        local p = phase01 % 1
        local t = (p < 0.5) and (p * 2) or (2 - p * 2)
        return a:Lerp(b, t)
    end

    local function _setPartColor(part, col) part.Color = col end
    local function _getPartPos(part) return part.Position end

    local function _safePos(part)
        local ok, pos = pcall(_getPartPos, part)
        return (ok and typeof(pos) == "Vector3") and pos or Vector3.zero
    end
    local function _posLess(a, b)
        local pa, pb = _safePos(a), _safePos(b)
        return (pa.Y + pa.X) < (pb.Y + pb.X)
    end
    local function tickGradientStore(store, spread, baseHue)

        local needPhase = nil
        local total = 0
        for part, rec in pairs(store) do
            if part and part.Parent then
                total = total + 1
                if rec.gp == nil then
                    needPhase = needPhase or {}
                    needPhase[part] = rec
                end
            end
        end
        if total == 0 then return end

        if needPhase then
            local arr = {}
            for part in pairs(needPhase) do arr[#arr + 1] = part end

            table.sort(arr, _posLess)
            for i, part in ipairs(arr) do
                local rec = needPhase[part]
                if rec then
                    rec.gp = ((i - 1) / math.max(1, #arr)) * (spread or 1)
                end
            end
        end

        for part, rec in pairs(store) do
            if part and part.Parent then

                pcall(_setPartColor, part, gradientColorAt(baseHue + (rec.gp or 0)))
            end
        end
    end

    local function styleOnePart(d, weapon)
        if weapon and d:IsDescendantOf(weapon) then return end
        stylePartInto(d, vmStyledParts, {

            colorOn = V.ViewmodelColorEnabled or V.ViewmodelGradientEnabled,
            color   = V.ViewmodelColor,
            matOn   = V.ViewmodelMaterialEnabled,
            mat     = V.ViewmodelMaterial,
            transp  = V.ViewmodelTransparency,
        })
    end

    local function invalidateVmStyle()
        restoreViewmodelStyle()
    end

    local function applyViewmodelStyle(vm)
        if vmStyledVM ~= nil and vmStyledVM ~= vm then
            restoreViewmodelStyle()
        end

        local nowT = now()
        if _vmStyleApplied == vm and (nowT - _vmRestyleT) < (V.VmRestyleSec or 3) then
            return
        end
        _vmRestyleT = nowT
        _vmStyleApplied = vm

        for part, s in pairs(vmStyledParts) do
            if part and not part.Parent then
                pcall(function()
                    part.Material     = s.M
                    part.Color        = s.C
                    part.Transparency = s.T
                    if s.tex ~= nil then part.TextureID = s.tex end
                end)
                if s.sa then
                    for _, rec in ipairs(s.sa) do
                        pcall(function()
                            if rec.inst and rec.parent then rec.inst.Parent = rec.parent end
                        end)
                    end
                end
                vmStyledParts[part] = nil
            end
        end
        local weapon = rawget(vm, "CurrentModel")

        for _, key in ipairs({ "_leftArm", "_rightArm" }) do
            local arm = rawget(vm, key)
            if typeof(arm) == "Instance" then
                styleOnePart(arm, weapon)
                for _, d in ipairs(arm:GetDescendants()) do styleOnePart(d, weapon) end
            end
        end

        local root = rawget(vm, "Root")
        local container = root and root.Parent
        if container then
            for _, d in ipairs(container:GetDescendants()) do styleOnePart(d, weapon) end
        end

        vmStyledVM = vm
    end

    local gunStyledParts  = {}
    local gunStyledModel  = nil
    local _gunStyleApplied = nil
    local _gunRestyleT     = 0
    local function restoreGunStyle()
        restoreStore(gunStyledParts)
        gunStyledModel = nil
        _gunStyleApplied = nil
    end
    local function invalidateGunStyle()
        restoreGunStyle()
    end

    local function applyGunStyle(vm)
        local weapon = rawget(vm, "CurrentModel")
        if not (typeof(weapon) == "Instance" and weapon.Parent) then
            if gunStyledModel then restoreGunStyle() end
            return
        end
        if gunStyledModel ~= nil and gunStyledModel ~= weapon then
            restoreGunStyle()
            _gunStyleApplied = nil
        end

        local nowG = now()
        if _gunStyleApplied == weapon and (nowG - _gunRestyleT) < (V.VmRestyleSec or 3) then
            return
        end
        _gunRestyleT = nowG
        _gunStyleApplied = weapon
        local opts = {
            colorOn = V.GunModelColorEnabled or V.GunModelGradientEnabled,
            color   = V.GunModelColor,
            matOn   = V.GunModelMaterialEnabled,
            mat     = V.GunModelMaterial,
            transp  = V.GunModelTransparency,
        }
        stylePartInto(weapon, gunStyledParts, opts)
        for _, d in ipairs(weapon:GetDescendants()) do
            stylePartInto(d, gunStyledParts, opts)
        end
        gunStyledModel = weapon
    end

    local vmHookBody = (function(self)

        do
            local root = rawget(self, "Root")
            if root and root.Parent then
                local o = V.ViewmodelOffset or Vector3.new()
                local tilt = V.ViewmodelTilt or 0
                local depth = (V.ViewmodelDepth or 0) / 100
                if o.Magnitude > 0.001 or math.abs(tilt) > 0.001
                or math.abs(depth) > 0.0001 then
                    root.CFrame = root.CFrame
                        * CFrame.new(o.X, o.Y, -o.Z + depth)
                        * CFrame.Angles(0, 0, math.rad(tilt))
                end
            end
        end
        if V.ViewmodelEnabled then

            if V.ViewmodelMaterialEnabled or V.ViewmodelColorEnabled
            or (V.ViewmodelTransparency or 0) > 0 or V.ViewmodelGradientEnabled then
                applyViewmodelStyle(self)

                if V.ViewmodelGradientEnabled then
                    tickGradientStore(vmStyledParts, 0.4, now() * (V.GradientSpeed or 0.35))
                end
            elseif vmStyledVM then
                restoreViewmodelStyle()
            end
        else
            if vmStyledVM then restoreViewmodelStyle() end
        end

        if V.GunModelEnabled then
            local root2 = rawget(self, "Root")
            local container = root2 and root2.Parent
            local weapon = rawget(self, "CurrentModel")

            if V.GunModelHighlightEnabled ~= false then
                if container and weapon and weapon.Parent then
                    if not (gunHighlight and gunHighlight.Parent) then
                        gunHighlight = Instance.new("Highlight")
                        gunHighlight.Name = "BRM5_GunHL"
                        gunHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                    end

                    if V.GunModelGradientEnabled and V.GunModelHighlightGradient ~= false then
                        local gcol = gradientColorAt(now() * (V.GradientSpeed or 0.35))
                        gunHighlight.FillColor    = gcol
                        gunHighlight.OutlineColor = gcol
                    else
                        gunHighlight.FillColor    = V.GunModelFill
                        gunHighlight.OutlineColor = V.GunModelOutline
                    end
                    gunHighlight.FillTransparency   = V.GunModelFillTransparency
                    gunHighlight.OutlineTransparency = V.GunModelOutlineTransparency
                    if gunHighlight.Adornee ~= weapon then gunHighlight.Adornee = weapon end
                    gunHighlight.Parent = container
                elseif gunHighlight then
                    gunHighlight.Adornee = nil
                end
            elseif gunHighlight then

                pcall(function() gunHighlight:Destroy() end); gunHighlight = nil
            end

            if V.GunModelColorEnabled or V.GunModelMaterialEnabled
            or (V.GunModelTransparency or 0) > 0 or V.GunModelGradientEnabled then
                applyGunStyle(self)

                if V.GunModelGradientEnabled then
                    tickGradientStore(gunStyledParts, V.GunModelGradientSpread or 1.6,
                        now() * (V.GradientSpeed or 0.35))
                end
            elseif gunStyledModel then
                restoreGunStyle()
            end
        else
            if gunHighlight then
                pcall(function() gunHighlight:Destroy() end)
                gunHighlight = nil
            end
            if gunStyledModel then restoreGunStyle() end
        end
    end)

    local _vmScanT = -999
    local function ensureViewmodelHook()
        if vmHooked then return true end
        if type(hookfunction) ~= "function" then return false end
        if type(filtergc)     ~= "function" then return false end
        local tScan = now()
        if tScan - _vmScanT < 2.0 then return false end
        _vmScanT = tScan

        local cls = (function()
            local ok, gc = pcall(filtergc, "table",
                { Keys = { "Update", "SetModel", "AddReticle", "LoadAnimation" } })
            if not ok then return nil end
            for _, v in ipairs(gc) do
                if type(rawget(v, "Update")) == "function"
                and type(rawget(v, "SetModel")) == "function"
                and type(rawget(v, "AddReticle")) == "function" then
                    return v
                end
            end
            return nil
        end)()
        if not cls then return false end

        local origFn = rawget(cls, "Update")
        if type(origFn) ~= "function" then return false end

        local newUpdate = (function(self, dt, ...)

            if not running then return vmOrigRef(self, dt, ...) end

            local r1, r2, r3, r4 = vmOrigRef(self, dt, ...)
            pcall(vmHookBody, self)
            return r1, r2, r3, r4
        end)

        local wrapped = (type(newcclosure) == "function")
            and newcclosure(newUpdate, "ViewmodelClass.Update")
            or newUpdate

        local hookOk, ret = pcall(hookfunction, origFn, wrapped)
        if hookOk and type(ret) == "function" then
            vmOrigRef  = ret
            vmHooked   = true
            vmHookMode = "hookfunction"
            vmHookFn   = origFn
            vmHookTbl  = cls
            log("Viewmodel hook OK (hookfunction)")
            return true
        end

        vmOrigRef = origFn
        local ok2 = pcall(function() cls.Update = wrapped end)
        if ok2 then
            vmHooked   = true
            vmHookMode = "field"
            vmHookFn   = origFn
            vmHookTbl  = cls
            log("Viewmodel hook OK (table replace fallback)")
            return true
        end
        log("Viewmodel hook FAILED")
        return false
    end

    local function unhookViewmodel()
        if not vmHooked then return end
        if vmHookMode == "hookfunction" and vmHookFn and vmOrigRef then
            pcall(hookfunction, vmHookFn, vmOrigRef)
        elseif vmHookMode == "field" and vmHookTbl and vmHookFn then
            pcall(function() vmHookTbl.Update = vmHookFn end)
        end
        vmHooked, vmHookMode, vmHookTbl, vmHookFn, vmOrigRef = false, nil, nil, nil, nil
    end

    local FOV_BIND = "BRM5_FOV"
    local fovBound = false
    local fovApplied = false

    local _origFov = nil

    local fovStep = (function()
        local fov = V.WorldFOV or 0
        if V.WorldFOVEnabled and fov > 0 then
            local cam = Workspace.CurrentCamera
            if cam then
                if not _origFov then _origFov = cam.FieldOfView end
                pcall(function() cam.FieldOfView = fov end)
                fovApplied = true
            end
        else
            if fovApplied then
                local cam = Workspace.CurrentCamera
                if cam then pcall(function() cam.FieldOfView = _origFov or 70 end) end
                fovApplied = false
            end
        end
    end)

    local _fovConn, _fovCamConn = nil, nil
    local _fovWriting = false

    local applyFov = (function(cam)
        local fov = V.WorldFOV or 0
        if not (V.WorldFOVEnabled and fov > 0) then return end
        cam = cam or Workspace.CurrentCamera
        if not cam then return end
        if _origFov == nil then _origFov = cam.FieldOfView end
        if math.abs(cam.FieldOfView - fov) > 0.01 then
            _fovWriting = true
            pcall(function() cam.FieldOfView = fov end)
            _fovWriting = false
        end
        fovApplied = true
    end)

    local function hookFovSignal()
        if _fovConn then _fovConn:Disconnect(); _fovConn = nil end
        local cam = Workspace.CurrentCamera
        if not cam then return end

        _fovConn = cam:GetPropertyChangedSignal("FieldOfView"):Connect((function()
            if not _fovWriting then applyFov(cam) end
        end))
    end

    local selfHighlight  = nil
    local tpOrig         = {}
    local tpStyledChar   = nil

    local function getSelfCharacter()

        local la = getLA()
        if type(la) == "table" then
            if rawget(la, "Alive") == false then return nil end
            local ok, char = pcall(function() return la.Character end)
            if ok and typeof(char) == "Instance" and char:IsA("Model") and char.Parent then
                return char
            end

            _ctrl = nil
        end
        local c = LP.Character
        if typeof(c) == "Instance" and c:IsA("Model") and c.Parent then

            local hum = c:FindFirstChildOfClass("Humanoid")
            if hum and hum.Health <= 0 then return nil end
            return c
        end
        return nil
    end

    local function applySelfHighlight(char)
        char = char or getSelfCharacter()
        if not char then return end
        if not (selfHighlight and selfHighlight.Parent) then
            selfHighlight = Instance.new("Highlight")
            selfHighlight.Name = "BRM5_SelfHL"
            selfHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
        end

        local hl = selfHighlight
        if hl.FillColor ~= V.ThirdPersonFill then hl.FillColor = V.ThirdPersonFill end
        if hl.OutlineColor ~= V.ThirdPersonOutline then hl.OutlineColor = V.ThirdPersonOutline end
        if hl.FillTransparency ~= V.ThirdPersonFillTransparency then
            hl.FillTransparency = V.ThirdPersonFillTransparency
        end
        if hl.OutlineTransparency ~= 0 then hl.OutlineTransparency = 0 end
        if hl.Adornee ~= char then hl.Adornee = char end
        if hl.Parent ~= char then hl.Parent = char end
    end

    local function clearSelfHighlight()
        if selfHighlight then
            pcall(function() selfHighlight:Destroy() end)
            selfHighlight = nil
        end
    end

    local function restoreSelfBody()
        for part, s in pairs(tpOrig) do

            if part then
                pcall(function() part.Material     = s.M end)
                pcall(function() part.Color        = s.C end)
                pcall(function() part.Transparency = s.T end)
            end
        end
        tpOrig = {}
        tpStyledChar = nil
    end

    local TP_NEVER_SHOW = {
        Head = true, HumanoidRootPart = true,
        Handle = true, RootPart = true,
    }
    local function tpShouldSkip(d)
        if TP_NEVER_SHOW[d.Name] then return true end

        if d.Transparency >= 1 and d.CanCollide == false then return true end

        local par = d.Parent
        if par and (par:IsA("Accessory") or par:IsA("Tool")) then return true end
        return false
    end

    local function styleSelfBody(char)
        restoreSelfBody()
        local bodyTranp = V.ThirdPersonBodyTransparency or 0
        local styled = 0
        for _, d in ipairs(char:GetDescendants()) do
            if (d:IsA("BasePart") or d:IsA("MeshPart")) and not tpShouldSkip(d) then
                local origT = d.Transparency

                local isHidden = origT >= 1
                tpOrig[d] = { M = d.Material, C = d.Color, T = origT }
                if V.ThirdPersonMaterial then
                    pcall(function() d.Material = V.ThirdPersonMaterial end)
                end
                pcall(function() d.Color = V.ThirdPersonBodyColor end)
                if not isHidden then
                    pcall(function() d.Transparency = bodyTranp end)
                end
                styled += 1
            end
        end
        tpStyledChar = char
        State._tpStyledCount = styled
    end

    local _tpRestyeT = 0

    local function tpForceRestyle()
        _tpRestyeT = 0
    end
    local function thirdPersonStep()
        if not V.ThirdPersonEnabled then
            if tpStyledChar then restoreSelfBody() end
            clearSelfHighlight()
            return
        end
        local char = getSelfCharacter()
        if not char then

            if tpStyledChar then restoreSelfBody() end
            clearSelfHighlight()
            return
        end
        applySelfHighlight(char)

        local t = now()
        if tpStyledChar ~= char or (t - _tpRestyeT) > 3 then
            _tpRestyeT = t
            styleSelfBody(char)
        end

        if V.ThirdPersonGradientEnabled then
            tickGradientStore(tpOrig, 0.5, now() * (V.GradientSpeed or 0.35))
        end
    end

    local function isVehicleController(t)
        if type(t) ~= "table" then return false end
        if type(rawget(t, "_solver")) ~= "table" then return false end
        if type(rawget(t, "_tune"))   ~= "table" then return false end
        local veh = rawget(t, "_vehicle")
        if type(veh) ~= "table" then return false end
        if rawget(veh, "Controlling") == false then return false end
        return true
    end
    local _vehCtrl
    local function findVehicleController()

        if isVehicleController(_vehCtrl) then
            local laChk = getLA()
            local cur = type(laChk) == "table" and rawget(laChk, "Controller") or nil
            if isVehicleController(cur) and not rawequal(cur, _vehCtrl) then
                _vehCtrl = nil
            else
                local veh   = rawget(_vehCtrl, "_vehicle")
                local vmain = type(veh) == "table" and rawget(veh, "VehicleMain") or nil
                if typeof(vmain) == "Instance" and vmain.Parent == nil then
                    _vehCtrl = nil
                else
                    return _vehCtrl
                end
            end
        end
        _vehCtrl = nil

        local la = getLA()
        if type(la) == "table" then
            local c = rawget(la, "Controller")
            if isVehicleController(c) then _vehCtrl = c; return c end
        end

        local t = now()
        if t - _lastScan < _scanCd then return nil end
        _lastScan = t
        if type(filtergc) ~= "function" then return nil end

        _vehCtrl = (function()
            local ok, gc = pcall(filtergc, "table",
                { Keys = { "_solver", "_tune", "_vehicle", "_throttle" } })
            if not ok then return nil end
            for _, v in ipairs(gc) do
                if isVehicleController(v) then return v end
            end
            return nil
        end)()
        return _vehCtrl
    end

    local _spdTune, _spdOrig, _spdSolver = nil, nil, nil
    local function restoreVehicleSpeed()
        if _spdTune and type(_spdOrig) == "table" then
            pcall(function()
                if _spdOrig.Accel ~= nil then _spdTune.AccelerationFactor = _spdOrig.Accel end
                if _spdOrig.Mass  ~= nil then _spdTune.Mass = _spdOrig.Mass end
                local fw, rw = rawget(_spdTune, "FrontWheels"), rawget(_spdTune, "RearWheels")
                if type(fw) == "table" and _spdOrig.FGrip ~= nil then fw.Grip = _spdOrig.FGrip end
                if type(rw) == "table" and _spdOrig.RGrip ~= nil then rw.Grip = _spdOrig.RGrip end
                if _spdSolver then _spdSolver:NewTune() end
            end)
        end
        _spdTune, _spdOrig, _spdSolver = nil, nil, nil
    end

    local function vehicleStep(dt)
        local wantAny = V.VehicleFlyEnabled or V.VehicleSpeedEnabled
        local ctrl = wantAny and findVehicleController() or nil

        if _spdTune and not (V.VehicleSpeedEnabled and ctrl and rawequal(rawget(ctrl, "_tune"), _spdTune)) then
            restoreVehicleSpeed()
        end
        if not ctrl then return end

        dt = (type(dt) == "number" and dt > 0) and dt or (1 / 60)
        local solver  = rawget(ctrl, "_solver")
        local vehicle = rawget(ctrl, "_vehicle")
        local tune    = rawget(ctrl, "_tune")

        if V.VehicleSpeedEnabled and type(tune) == "table" then
            local mult = V.VehicleSpeedMult or 2
            if mult < 1 then mult = 1 end
            if not rawequal(_spdTune, tune) then
                restoreVehicleSpeed()
                _spdTune, _spdSolver = tune, solver
                local fw, rw = rawget(tune, "FrontWheels"), rawget(tune, "RearWheels")
                _spdOrig = {
                    Accel = rawget(tune, "AccelerationFactor"),
                    Mass  = rawget(tune, "Mass"),
                    FGrip = type(fw) == "table" and rawget(fw, "Grip") or nil,
                    RGrip = type(rw) == "table" and rawget(rw, "Grip") or nil,
                }
            end
            local o = _spdOrig

            local wantMass  = (type(o.Mass) == "number") and (o.Mass / mult) or nil
            local wantAccel = (type(o.Accel) == "number") and math.min(o.Accel * mult, 1) or nil
            local wantFGrip = (type(o.FGrip) == "number") and (o.FGrip * math.min(mult, 3)) or nil
            local wantRGrip = (type(o.RGrip) == "number") and (o.RGrip * math.min(mult, 3)) or nil
            local dirty = false
            pcall(function()
                if wantMass and rawget(tune, "Mass") ~= wantMass then tune.Mass = wantMass; dirty = true end
                if wantAccel and rawget(tune, "AccelerationFactor") ~= wantAccel then tune.AccelerationFactor = wantAccel; dirty = true end
                local fw, rw = rawget(tune, "FrontWheels"), rawget(tune, "RearWheels")
                if type(fw) == "table" and wantFGrip and rawget(fw, "Grip") ~= wantFGrip then fw.Grip = wantFGrip; dirty = true end
                if type(rw) == "table" and wantRGrip and rawget(rw, "Grip") ~= wantRGrip then rw.Grip = wantRGrip; dirty = true end
                if dirty then solver:NewTune() end
            end)
        end

        if V.VehicleFlyEnabled then
            local cam = Workspace.CurrentCamera
            if not cam then return end
            local baseCF = rawget(vehicle, "CFrame")
            if typeof(baseCF) ~= "CFrame" then
                local st = rawget(solver, "_state")
                if type(st) == "table" and typeof(st.CFrame) == "CFrame" then
                    baseCF = st.CFrame
                end
            end
            if typeof(baseCF) ~= "CFrame" then return end
            local dir = Vector3.zero
            if UIS:IsKeyDown(Enum.KeyCode.W)           then dir += cam.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.S)           then dir -= cam.CFrame.LookVector end
            if UIS:IsKeyDown(Enum.KeyCode.A)           then dir -= cam.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.D)           then dir += cam.CFrame.RightVector end
            if UIS:IsKeyDown(Enum.KeyCode.Space)       then dir += Vector3.yAxis end
            if UIS:IsKeyDown(Enum.KeyCode.LeftControl) then dir -= Vector3.yAxis end
            local step = (dir.Magnitude > 0.001)
                and (dir.Unit * (V.VehicleFlySpeed or 120) * dt)
                or  Vector3.zero
            local newCF = baseCF.Rotation + (baseCF.Position + step)
            local compRep = rawget(vehicle, "ComponentReplicates")
            pcall(function()
                solver:SetState(newCF, Vector3.zero, Vector3.zero, compRep)
            end)

            local vm = rawget(vehicle, "VehicleMain")
            if typeof(vm) == "Instance" then
                pcall(function()
                    local p = vm:IsA("BasePart") and vm or vm.PrimaryPart
                    if p then p.CFrame = newCF end
                end)
            end
        end
    end

    local _canEquipHooked = false
    local _canEquipCallOrig = nil
    local _fgScanCd = 0

    local _fgTbl, _fgMode, _fgRawFn = nil, nil, nil

    local _fgSeatOrig = nil
    local function installFreeGunHook()
        if _canEquipHooked then return true end
        local t = now()
        if t - _fgScanCd < 2.0 then return false end
        _fgScanCd = t
        if type(filtergc) ~= "function" then return false end

        local res = (function()
            local ok, r = pcall(filtergc, "table",
                { Keys = { "_canEquip", "_cycle", "_sync" } })
            if not ok or type(r) ~= "table" then return nil end
            return r
        end)()
        if type(res) ~= "table" then return false end
        for _, tbl in ipairs(res) do
            local fn = rawget(tbl, "_canEquip")
            if type(fn) == "function" then
                _canEquipCallOrig = fn

                local wrapper = (function(self, la)
                    if V.FreeGunEnabled and la and la.Alive
                        and la.Controller and not la.Downed then
                        return true
                    end
                    return _canEquipCallOrig(self, la)
                end)

                local setOk = pcall(function() tbl._canEquip = wrapper end)
                if setOk and rawget(tbl, "_canEquip") == wrapper then
                    _canEquipHooked = true
                    _fgTbl, _fgMode, _fgRawFn = tbl, "field", fn
                    log("FreeGun: _canEquip перехвачен (field)")
                    return true
                end

                if type(hookfunction) == "function" then
                    local hookOk, origRef = pcall(hookfunction, fn, wrapper)
                    if hookOk then
                        _canEquipCallOrig = (type(origRef) == "function") and origRef or fn
                        _canEquipHooked = true
                        _fgTbl, _fgMode, _fgRawFn = tbl, "hookfunction", fn
                        log("FreeGun: _canEquip перехвачен (hookfunction)")
                        return true
                    end
                end
            end
        end
        return false
    end

    local function restoreFreeGunSeat()
        if _fgSeatOrig ~= nil then
            pcall(function()
                local la = getLA()
                if type(la) == "table" then la.SeatCanEquip = _fgSeatOrig end
            end)
            _fgSeatOrig = nil
        end
    end

    local function restoreFreeGunHook()
        restoreFreeGunSeat()
        if not _canEquipHooked then return end
        if _fgMode == "field" and _fgTbl and _canEquipCallOrig then
            pcall(function() _fgTbl._canEquip = _canEquipCallOrig end)
        elseif _fgMode == "hookfunction" and _fgRawFn and _canEquipCallOrig then
            pcall(hookfunction, _fgRawFn, _canEquipCallOrig)
        end
        _canEquipHooked = false
        _fgTbl, _fgMode, _fgRawFn = nil, nil, nil
    end

    local function freeGunStep()
        if not V.FreeGunEnabled then return end
        if not _canEquipHooked then installFreeGunHook() end

        local la = getLA()

        if type(la) == "table" and rawget(la, "Alive") ~= false
        and rawget(la, "SeatCanEquip") ~= true then

            if _fgSeatOrig == nil then _fgSeatOrig = rawget(la, "SeatCanEquip") or false end
            pcall(function() la.SeatCanEquip = true end)
        end
    end

    local lightSaved, lightSavedOK = {}, false
    local function saveLighting()
        if lightSavedOK then return end
        lightSaved = {
            ClockTime    = Lighting.ClockTime,
            Brightness   = Lighting.Brightness,
            Ambient      = Lighting.Ambient,
            OutdoorAmbient = Lighting.OutdoorAmbient,
            FogEnd       = Lighting.FogEnd,
            FogStart     = Lighting.FogStart,
            GlobalShadows = Lighting.GlobalShadows,

            FogColor        = Lighting.FogColor,
            ColorShift_Top  = Lighting.ColorShift_Top,
            ColorShift_Bottom = Lighting.ColorShift_Bottom,
            ExposureCompensation = Lighting.ExposureCompensation,
            GeographicLatitude = Lighting.GeographicLatitude,
            EnvironmentDiffuseScale  = Lighting.EnvironmentDiffuseScale,
            EnvironmentSpecularScale = Lighting.EnvironmentSpecularScale,
        }
        lightSavedOK = true
    end
    local function restoreLighting()
        if not lightSavedOK then return end
        pcall(function()
            Lighting.ClockTime     = lightSaved.ClockTime
            Lighting.Brightness    = lightSaved.Brightness
            Lighting.Ambient       = lightSaved.Ambient
            Lighting.OutdoorAmbient = lightSaved.OutdoorAmbient
            Lighting.FogEnd        = lightSaved.FogEnd
            Lighting.FogStart      = lightSaved.FogStart
            Lighting.GlobalShadows  = lightSaved.GlobalShadows
            Lighting.FogColor       = lightSaved.FogColor
            Lighting.ColorShift_Top = lightSaved.ColorShift_Top
            Lighting.ColorShift_Bottom = lightSaved.ColorShift_Bottom
            Lighting.ExposureCompensation = lightSaved.ExposureCompensation
            Lighting.GeographicLatitude   = lightSaved.GeographicLatitude
            Lighting.EnvironmentDiffuseScale  = lightSaved.EnvironmentDiffuseScale
            Lighting.EnvironmentSpecularScale = lightSaved.EnvironmentSpecularScale
        end)
    end

    local FULLBRIGHT_COL = Color3.fromRGB(178, 178, 178)

    local _lightConns   = {}
    local _lightWriting = false
    local _ctAttrConn   = nil
    local _ctAttrOrig   = nil
    local _ctAttrSet    = false

    local function liftToFullbright(c)
        if typeof(c) ~= "Color3" then return FULLBRIGHT_COL end
        local peak = math.max(c.R, c.G, c.B)
        if peak < 0.02 then return FULLBRIGHT_COL end
        local k = math.max(1, FULLBRIGHT_COL.R / peak)
        return Color3.new(
            math.min(c.R * k, 1),
            math.min(c.G * k, 1),
            math.min(c.B * k, 1))
    end

    local function contestedTarget(prop)
        local amb = V.AmbientEnabled
        local fb  = V.FullbrightEnabled

        if prop == "Ambient" then

            if fb then
                if amb then return liftToFullbright(V.AmbientColor) end
                return FULLBRIGHT_COL
            end
            if amb then return V.AmbientColor end
            return nil

        elseif prop == "OutdoorAmbient" then

            if fb then
                if amb then return liftToFullbright(V.AmbientOutdoorColor) end
                return FULLBRIGHT_COL
            end
            if amb then return V.AmbientOutdoorColor end
            return nil

        elseif prop == "Brightness" then

            local base
            if amb then base = V.AmbientBrightness end
            if type(base) ~= "number" then
                base = (lightSavedOK and type(lightSaved.Brightness) == "number")
                       and lightSaved.Brightness or 2
            end
            if fb then return math.max(base, 2) end
            if amb then return base end
            return nil

        elseif prop == "ExposureCompensation" then
            if amb then return V.AmbientExposure or 0 end
            return nil
        end

        if not amb then return nil end
        if prop == "GeographicLatitude" then
            return V.AmbientLatitude or 45
        elseif prop == "ColorShift_Top" then
            return V.AmbientTintTop
        end
        return nil
    end

    local CONTESTED = {

        "GeographicLatitude", "ColorShift_Top", "OutdoorAmbient",

        "Ambient", "Brightness", "ExposureCompensation",
    }

    local function reassertLightProp(prop)
        if _lightWriting then return end
        local want = contestedTarget(prop)
        if want == nil then return end
        local cur = Lighting[prop]
        if cur == want then return end
        _lightWriting = true
        pcall(function() Lighting[prop] = want end)
        _lightWriting = false
    end

    local function hookLightingSignals()
        for _, prop in ipairs(CONTESTED) do
            if not _lightConns[prop] then
                local ok, conn = pcall(function()
                    return Lighting:GetPropertyChangedSignal(prop):Connect(
                        (function() reassertLightProp(prop) end))
                end)
                if ok then _lightConns[prop] = conn end
            end
        end

        if not _ctAttrConn then
            local ok, conn = pcall(function()
                return Lighting:GetAttributeChangedSignal("ClockTime"):Connect(
                    (function()
                        if _lightWriting or not V.AmbientEnabled then return end
                        local want = V.AmbientClockTime
                        if type(want) ~= "number" then return end
                        if Lighting:GetAttribute("ClockTime") == want then return end
                        _lightWriting = true
                        pcall(function() Lighting:SetAttribute("ClockTime", want) end)
                        _lightWriting = false
                    end))
            end)
            if ok then _ctAttrConn = conn end
        end
    end

    local function unhookLightingSignals()
        for prop, conn in pairs(_lightConns) do
            pcall(function() conn:Disconnect() end)
            _lightConns[prop] = nil
        end
        if _ctAttrConn then pcall(function() _ctAttrConn:Disconnect() end); _ctAttrConn = nil end

        if _ctAttrSet then
            _lightWriting = true
            pcall(function() Lighting:SetAttribute("ClockTime", _ctAttrOrig) end)
            _lightWriting = false
            _ctAttrSet, _ctAttrOrig = false, nil
        end
    end

    local _gameAtmo, _gameAtmoParent = nil, nil
    local function parkGameAtmosphere()
        if _gameAtmo then return end
        local ok, atmo = pcall(function()
            return Lighting:FindFirstChildOfClass("Atmosphere")
        end)
        if not ok or not atmo then return end
        _gameAtmo, _gameAtmoParent = atmo, atmo.Parent
        pcall(function() atmo.Parent = nil end)
    end
    local function restoreGameAtmosphere()
        if not _gameAtmo then return end
        pcall(function() _gameAtmo.Parent = _gameAtmoParent end)
        _gameAtmo, _gameAtmoParent = nil, nil
    end

    local function applyClockTimeViaAttribute()
        local want = V.AmbientClockTime
        if type(want) ~= "number" then return false end
        local okRead, cur = pcall(function() return Lighting:GetAttribute("ClockTime") end)
        if not okRead then return false end
        if cur == nil then return false end
        if not _ctAttrSet then
            _ctAttrOrig = cur
            _ctAttrSet = true
        end
        if cur ~= want then
            _lightWriting = true
            pcall(function() Lighting:SetAttribute("ClockTime", want) end)
            _lightWriting = false
        end
        return true
    end

    local AMBIENT_PRESETS = {
        Midnight = {
            ClockTime = 0, Brightness = 1.2, Exposure = 0.15,
            Ambient = Color3.fromRGB(38, 44, 70),
            Outdoor = Color3.fromRGB(48, 56, 88),
            TintTop = Color3.fromRGB(20, 28, 60), TintBottom = Color3.fromRGB(0, 0, 0),
            Fog = true, FogColor = Color3.fromRGB(18, 22, 40), FogStart = 0, FogEnd = 420,
            Shadows = true, Latitude = 20,
        },
        Sunset = {
            ClockTime = 17.6, Brightness = 2.4, Exposure = 0.2,
            Ambient = Color3.fromRGB(120, 78, 62),
            Outdoor = Color3.fromRGB(178, 108, 70),
            TintTop = Color3.fromRGB(255, 150, 70), TintBottom = Color3.fromRGB(40, 20, 30),
            Fog = true, FogColor = Color3.fromRGB(220, 130, 85), FogStart = 40, FogEnd = 1400,
            Shadows = true, Latitude = 60,
        },
        Overcast = {
            ClockTime = 11, Brightness = 1.8, Exposure = -0.1,
            Ambient = Color3.fromRGB(120, 124, 132),
            Outdoor = Color3.fromRGB(150, 155, 165),
            TintTop = Color3.fromRGB(180, 190, 200), TintBottom = Color3.fromRGB(0, 0, 0),
            Fog = true, FogColor = Color3.fromRGB(168, 175, 185), FogStart = 20, FogEnd = 700,
            Shadows = false, Latitude = 45,
        },
        Toxic = {
            ClockTime = 14, Brightness = 2.2, Exposure = 0.35,
            Ambient = Color3.fromRGB(70, 105, 55),
            Outdoor = Color3.fromRGB(120, 165, 70),
            TintTop = Color3.fromRGB(150, 255, 90), TintBottom = Color3.fromRGB(20, 40, 10),
            Fog = true, FogColor = Color3.fromRGB(110, 160, 70), FogStart = 0, FogEnd = 520,
            Shadows = true, Latitude = 45,
        },
        Nightvision = {
            ClockTime = 12, Brightness = 4.5, Exposure = 0.6,
            Ambient = Color3.fromRGB(90, 190, 90),
            Outdoor = Color3.fromRGB(110, 220, 110),
            TintTop = Color3.fromRGB(120, 255, 120), TintBottom = Color3.fromRGB(0, 30, 0),
            Fog = false, FogColor = Color3.fromRGB(40, 90, 40), FogStart = 0, FogEnd = 2000,
            Shadows = false, Latitude = 45,
        },
        Clear = {
            ClockTime = 13, Brightness = 2.6, Exposure = 0,
            Ambient = Color3.fromRGB(130, 135, 145),
            Outdoor = Color3.fromRGB(160, 168, 180),
            TintTop = Color3.fromRGB(0, 0, 0), TintBottom = Color3.fromRGB(0, 0, 0),
            Fog = false, FogColor = Color3.fromRGB(180, 190, 200), FogStart = 0, FogEnd = 5000,
            Shadows = true, Latitude = 45,
        },
    }
    local AMBIENT_PRESET_ORDER = {
        "Custom", "Clear", "Midnight", "Sunset", "Overcast", "Toxic", "Nightvision",
    }

    local function applyAmbientPreset(name)
        local pr = AMBIENT_PRESETS[name]
        if not pr then return false end
        V.AmbientClockTime      = pr.ClockTime
        V.AmbientBrightness     = pr.Brightness
        V.AmbientExposure       = pr.Exposure
        V.AmbientColor          = pr.Ambient
        V.AmbientOutdoorColor   = pr.Outdoor
        V.AmbientTintTop        = pr.TintTop
        V.AmbientTintBottom     = pr.TintBottom
        V.AmbientFogEnabled     = pr.Fog
        V.AmbientFogColor       = pr.FogColor
        V.AmbientFogStart       = pr.FogStart
        V.AmbientFogEnd         = pr.FogEnd
        V.AmbientShadows        = pr.Shadows
        V.AmbientLatitude       = pr.Latitude
        V.AmbientPreset         = name
        return true
    end

    local _lightT = -999
    local function lightingStep()
        local amb, fb, nofog = V.AmbientEnabled, V.FullbrightEnabled, V.NoFogEnabled
        if not (amb or fb or nofog) then return end

        if not lightSavedOK then
            local laL = getLA()
            if type(laL) == "table" and rawget(laL, "Alive") == false then return end
        end
        saveLighting()

        if amb or fb then
            hookLightingSignals()
        end
        if amb then

            if not applyClockTimeViaAttribute() then
                pcall(function()
                    if Lighting.ClockTime ~= V.AmbientClockTime then
                        Lighting.ClockTime = V.AmbientClockTime
                    end
                end)
            end
        end
        local tL = now()
        if tL - _lightT < 0.25 then return end
        _lightT = tL

        if amb then
            pcall(function()

                for _, p in ipairs(CONTESTED) do
                    local want = contestedTarget(p)
                    if want ~= nil and Lighting[p] ~= want then
                        Lighting[p] = want
                    end
                end

                Lighting.ColorShift_Bottom = V.AmbientTintBottom
                Lighting.EnvironmentDiffuseScale  = V.AmbientDiffuse  or 1
                Lighting.EnvironmentSpecularScale = V.AmbientSpecular or 1
                Lighting.GlobalShadows = V.AmbientShadows ~= false
                if V.AmbientFogEnabled then
                    Lighting.FogColor = V.AmbientFogColor
                    Lighting.FogStart = V.AmbientFogStart or 0
                    Lighting.FogEnd   = V.AmbientFogEnd or 800
                end
            end)
        end

        if fb then
            pcall(function()
                for _, p in ipairs(CONTESTED) do
                    local want = contestedTarget(p)
                    if want ~= nil and Lighting[p] ~= want then
                        Lighting[p] = want
                    end
                end
                Lighting.GlobalShadows = false
            end)
        end
        if nofog then
            pcall(function()
                Lighting.FogEnd   = 1e9
                Lighting.FogStart = 1e9
            end)
        end

        if (amb and V.AmbientFogEnabled) or nofog then
            parkGameAtmosphere()
        else
            restoreGameAtmosphere()
        end
    end

    local function lightingOff()

        unhookLightingSignals()
        restoreGameAtmosphere()
        restoreLighting()
        lightSavedOK = false
        _lightT = -999
    end

    local promptConn = nil
    local promptAttrConn = {}
    local function zeroPrompt(p)
        if not (p and p:IsA("ProximityPrompt")) then return end
        pcall(function()
            local t = p:GetAttribute("Timer")
            if type(t) == "number" and t > 0 and p:GetAttribute("BRM5_timer") == nil then
                p:SetAttribute("BRM5_timer", t)
            end
            if p:GetAttribute("BRM5_hold") == nil then
                p:SetAttribute("BRM5_hold", p.HoldDuration)
            end
            if p:GetAttribute("Timer") ~= nil then p:SetAttribute("Timer", 0) end
            p.HoldDuration = 0
        end)

        if not promptAttrConn[p] then
            local attrC = p:GetAttributeChangedSignal("Timer"):Connect(function()
                if V.NoFWaitEnabled and p:GetAttribute("Timer") and p:GetAttribute("Timer") ~= 0 then
                    pcall(function() p:SetAttribute("Timer", 0) end)
                end
            end)

            local dstC = p.Destroying:Connect(function()
                local rec = promptAttrConn[p]
                promptAttrConn[p] = nil
                if rec then
                    pcall(function() rec[1]:Disconnect() end)
                    pcall(function() rec[2]:Disconnect() end)
                end
            end)
            promptAttrConn[p] = { attrC, dstC }
        end
    end
    local function enableNoFWait()
        if promptConn then return end
        for _, d in ipairs(Workspace:GetDescendants()) do zeroPrompt(d) end
        promptConn = PPS.PromptShown:Connect(function(p)
            if V.NoFWaitEnabled then zeroPrompt(p) end
        end)
    end
    local function disableNoFWait()
        if promptConn then promptConn:Disconnect(); promptConn = nil end
        for p, rec in pairs(promptAttrConn) do
            pcall(function() rec[1]:Disconnect() end)
            pcall(function() rec[2]:Disconnect() end)
            promptAttrConn[p] = nil
        end
        for _, d in ipairs(Workspace:GetDescendants()) do
            if d:IsA("ProximityPrompt") then
                local st = d:GetAttribute("BRM5_timer")
                if st ~= nil then pcall(function() d:SetAttribute("Timer", st) end) end
                local s = d:GetAttribute("BRM5_hold")
                if s ~= nil then pcall(function() d.HoldDuration = s end) end

                pcall(function()
                    d:SetAttribute("BRM5_timer", nil)
                    d:SetAttribute("BRM5_hold", nil)
                end)
            end
        end
    end

    local lpLastScan = -999
    local function lockpickActive()
        local la = getLA()
        if type(la) ~= "table" then return false end

        if rawget(la, "Alive") == false then return false end
        local cs = rawget(la, "CurrentState")
        return type(cs) == "table" and cs.LockPick and true or false
    end
    local function lockpickStep()
        if not V.LockpickBypassEnabled then return end

        if not lockpickActive() then return end
        local t = now()
        if t - lpLastScan < (V.LockpickScanInterval or 0.4) then return end
        lpLastScan = t
        local lp = findLockPick()
        if not lp then return end
        local net = findNet()
        if net then
            pcall(function() lp._cancelled = true end)
            pcall(function() net:FireServer("ActivateInteract", "Picked") end)
        end
    end

    local hbConn  = nil

    local _stepWarnT = {}
    local runStep = (function(name, fn, dt)
        local ok, err = pcall(fn, dt)
        if not ok then
            local t = now()
            if t - (_stepWarnT[name] or -999) >= 1 then
                _stepWarnT[name] = t
                warn("[VIS] шаг", name, "упал:", err)
            end
        end
    end)
    local function vmHookStep()
        if V.ViewmodelEnabled or V.GunModelEnabled then ensureViewmodelHook() end
    end

    local heartbeat = (function(dt)
        if not running then return end
        runStep("vmhook",   vmHookStep)
        runStep("tps",      thirdPersonStep)
        runStep("vehicle",  vehicleStep, dt)
        runStep("freegun",  freeGunStep)
        runStep("lighting", lightingStep)
        runStep("lockpick", lockpickStep)
    end)

    local inputConn = nil

    local HOTKEY_UI_FLAGS = {
        ViewmodelEnabled      = "VM",
        GunModelEnabled       = "GM",
        ThirdPersonEnabled    = "TP",
        VehicleFlyEnabled     = "VehFly",
        VehicleSpeedEnabled   = "VehSpeed",
        FreeGunEnabled        = "FreeGun",
        AmbientEnabled        = "Ambient",
        NoFWaitEnabled        = "NoFWait",
        LockpickBypassEnabled = "Lockpick",
        FullbrightEnabled     = "Fullbright",
        NoFogEnabled          = "NoFog",
    }
    local _uiKitRef, _uiFlagFn = nil, nil
    local function toggle(name, label)
        V[name] = not V[name]
        log(label, V[name] and "ВКЛ" or "выкл")
        local fl = HOTKEY_UI_FLAGS[name]
        if _uiKitRef and _uiFlagFn and fl then
            pcall(_uiKitRef.syncToggle, _uiFlagFn(fl), V[name])
        end
        return V[name]
    end

    local function onInput(input, gpe)
        if gpe then return end
        if input.UserInputType ~= Enum.UserInputType.Keyboard then return end
        local kc = input.KeyCode
        if kc == V.ViewmodelKey then
            if not toggle("ViewmodelEnabled", "Viewmodel") then restoreViewmodelStyle() end
        elseif kc == V.GunModelKey then
            if not toggle("GunModelEnabled", "GunModel") then
                if gunHighlight then pcall(function() gunHighlight:Destroy() end); gunHighlight = nil end
            end
        elseif kc == V.ThirdPersonKey then
            if not toggle("ThirdPersonEnabled", "ThirdPersonSkin") then
                clearSelfHighlight(); restoreSelfBody()
            end
        elseif kc == V.VehicleFlyKey   then toggle("VehicleFlyEnabled",    "VehicleFly")
        elseif kc == V.VehicleSpeedKey then toggle("VehicleSpeedEnabled",   "VehicleSpeed")
        elseif kc == V.FreeGunKey then

            if toggle("FreeGunEnabled", "FreeGun") then installFreeGunHook() else restoreFreeGunSeat() end
        elseif kc == V.AmbientKey then
            if not toggle("AmbientEnabled", "Ambient") then lightingOff() end
        elseif kc == V.NoFWaitKey then
            if toggle("NoFWaitEnabled", "NoFWait") then enableNoFWait() else disableNoFWait() end
        elseif kc == V.LockpickBypassKey then
            toggle("LockpickBypassEnabled", "LockpickBypass")
        elseif kc == V.FullbrightKey then
            if not toggle("FullbrightEnabled", "Fullbright") then lightingOff() end
        elseif kc == V.NoFogKey then
            if not toggle("NoFogEnabled", "NoFog") then lightingOff() end
        end
    end

    local M = {}

    function M.start()
        if running then return end
        running = true
        hbConn = RunService.Heartbeat:Connect(heartbeat)

        pcall(function() RunService:UnbindFromRenderStep(FOV_BIND) end)
        local bindOk, bindErr = pcall(function()
            RunService:BindToRenderStep(FOV_BIND,
                Enum.RenderPriority.Camera.Value + 1, fovStep)
            fovBound = true
        end)
        if not bindOk then warn("[VIS] FOV: BindToRenderStep не встал:", bindErr) end

        hookFovSignal()
        _fovCamConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(function()
            _origFov = nil
            hookFovSignal()
        end)
        inputConn = UIS.InputBegan:Connect(onInput)
        log("Visuals/World v3 запущен | Numpad1..0 = ту��блеры | CONFIG.Visuals для настройки")
    end

    function M.stop()
        running = false
        if hbConn    then hbConn:Disconnect();    hbConn    = nil end
        if inputConn then inputConn:Disconnect(); inputConn = nil end
        if fovBound  then
            pcall(function() RunService:UnbindFromRenderStep(FOV_BIND) end)
            fovBound = false
        end

        if _fovConn    then _fovConn:Disconnect();    _fovConn    = nil end
        if _fovCamConn then _fovCamConn:Disconnect(); _fovCamConn = nil end

        unhookViewmodel()
        restoreViewmodelStyle()
        restoreGunStyle()
        restoreVehicleSpeed()
        if gunHighlight then pcall(function() gunHighlight:Destroy() end); gunHighlight = nil end
        clearSelfHighlight()
        restoreSelfBody()
        restoreFreeGunHook()
        disableNoFWait()
        lightingOff()

        if fovApplied or _origFov then
            pcall(function()
                local cam = Workspace.CurrentCamera

                if cam then cam.FieldOfView = _origFov or 70 end
            end)
            fovApplied = false
            _origFov = nil
        end
        log("Visuals/World остановлен")
    end

    local MATERIALS = { "ForceField", "Neon", "Glass", "SmoothPlastic", "Plastic", "Metal", "Marble" }
    local function matName(m) return (typeof(m) == "EnumItem") and m.Name or tostring(m or "ForceField") end
    local function matFromName(n) return Enum.Material[n] or Enum.Material.ForceField end

    function M.buildUI(ui)
        local tabV    = ui.tabs and ui.tabs.Visuals
        local tabMov  = ui.tabs and ui.tabs.Movement
        local tabGM   = ui.tabs and ui.tabs.GunMods
        local tabMisc = ui.tabs and ui.tabs.Misc
        local tabDbg  = ui.tabs and ui.tabs.Debug
        local K = Bridge.makeUiKit(ui)

        local uiFlag = ui.flag or function(s) return "BRM5_" .. tostring(s) end
        _uiKitRef, _uiFlagFn = K, uiFlag

        if tabV then

            local S = tabV:Section({ Side = "Left" })

            K.feature(S, {
                Title = "Viewmodel", Flag = "VM",
                get = function() return V.ViewmodelEnabled end,
                set = function(v) V.ViewmodelEnabled = v end,
                Desc = "restyles ur first person arms",
            })
            K.toggle(S, { Name = "Recolor", Flag = "VMColorOn", Title = "VM Recolor",
                get = function() return V.ViewmodelColorEnabled end,
                set = function(v) V.ViewmodelColorEnabled = v end,
                after = invalidateVmStyle })
            K.color(S, { Name = "Color", Flag = "VMColor",
                Default = V.ViewmodelColor,
                Callback = function(c) V.ViewmodelColor = c; invalidateVmStyle() end })
            K.toggle(S, { Name = "Change Material", Flag = "VMMatOn",
                Title = "VM Material",
                get = function() return V.ViewmodelMaterialEnabled end,
                set = function(v) V.ViewmodelMaterialEnabled = v end,
                after = invalidateVmStyle })
            K.dropdown(S, { Name = "Material", Flag = "VMMat",
                Options = MATERIALS, Default = matName(V.ViewmodelMaterial),

                Callback = function(n) V.ViewmodelMaterial = matFromName(n); invalidateVmStyle() end })
            K.slider(S, { Name = "Transparency", Flag = "VMTransp",
                Default = math.floor((V.ViewmodelTransparency or 0) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v)
                    V.ViewmodelTransparency = v / 100
                    invalidateVmStyle()
                end })
            K.toggle(S, { Name = "Gradient", Flag = "VMGrad", Title = "VM Gradient",
                get = function() return V.ViewmodelGradientEnabled end,
                set = function(v) V.ViewmodelGradientEnabled = v end,
                after = invalidateVmStyle,
                Desc = "colors set in Gradient on the right" })

            K.group(S, "Placement")
            K.slider(S, { Name = "Hand Zoom", Flag = "VMDepth",
                Default = math.floor(V.ViewmodelDepth or 0) + 100, Min = 0, Max = 200,
                Callback = function(v) V.ViewmodelDepth = v - 100 end,
                Desc = "100 = stock. pulls the arms closer or pushes em away\nthis is NOT camera fov, that one lives in Misc" })

            local _vmo = (typeof(V.ViewmodelOffset) == "Vector3") and V.ViewmodelOffset or Vector3.zero
            K.slider(S, { Name = "Hand Right", Flag = "VMOffX",
                Default = math.floor(_vmo.X * 100) + 100, Min = 0, Max = 200,
                Callback = function(v)
                    local o = (typeof(V.ViewmodelOffset) == "Vector3") and V.ViewmodelOffset or Vector3.zero
                    V.ViewmodelOffset = Vector3.new((v - 100) / 100, o.Y, o.Z)
                end,
                Desc = "100 = stock. slides the arms sideways" })
            K.slider(S, { Name = "Hand Up", Flag = "VMOffY",
                Default = math.floor(_vmo.Y * 100) + 100, Min = 0, Max = 200,
                Callback = function(v)
                    local o = (typeof(V.ViewmodelOffset) == "Vector3") and V.ViewmodelOffset or Vector3.zero
                    V.ViewmodelOffset = Vector3.new(o.X, (v - 100) / 100, o.Z)
                end,
                Desc = "100 = stock. raises or drops em" })
            K.slider(S, { Name = "Hand Tilt", Flag = "VMTilt",
                Default = math.floor(V.ViewmodelTilt or 0) + 45, Min = 0, Max = 90, Suffix = "°",
                Callback = function(v) V.ViewmodelTilt = v - 45 end,
                Desc = "45 = stock. rolls the arms" })

            local G = tabV:Section({ Side = "Left" })
            K.feature(G, {
                Title = "Gun Model", Flag = "GM",
                get = function() return V.GunModelEnabled end,
                set = function(v) V.GunModelEnabled = v end,
                Desc = "same styling but for the gun in ur hands",
            })
            K.toggle(G, { Name = "Recolor", Flag = "GMColorOn", Title = "Gun Recolor",
                get = function() return V.GunModelColorEnabled end,
                set = function(v) V.GunModelColorEnabled = v end,
                after = invalidateGunStyle })
            K.color(G, { Name = "Color", Flag = "GMColor",
                Default = V.GunModelColor,
                Callback = function(c) V.GunModelColor = c; invalidateGunStyle() end })
            K.toggle(G, { Name = "Change Material", Flag = "GMMatOn",
                Title = "Gun Material",
                get = function() return V.GunModelMaterialEnabled end,
                set = function(v) V.GunModelMaterialEnabled = v end,
                after = invalidateGunStyle })
            K.dropdown(G, { Name = "Material", Flag = "GMMat",
                Options = MATERIALS, Default = matName(V.GunModelMaterial),
                Callback = function(n) V.GunModelMaterial = matFromName(n); invalidateGunStyle() end })
            K.slider(G, { Name = "Transparency", Flag = "GMTransp",
                Default = math.floor((V.GunModelTransparency or 0) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v)
                    V.GunModelTransparency = v / 100
                    invalidateGunStyle()
                end })
            K.toggle(G, { Name = "Gradient", Flag = "GMGrad", Title = "Gun Gradient",
                get = function() return V.GunModelGradientEnabled end,
                set = function(v) V.GunModelGradientEnabled = v end,
                after = invalidateGunStyle,
                Desc = "wave runs part to part, see Wave Spread" })

            K.group(G, "Highlight")
            K.toggle(G, { Name = "Enabled", Flag = "GMHighlight",
                Title = "Gun Highlight",
                get = function() return V.GunModelHighlightEnabled ~= false end,
                set = function(v)
                    V.GunModelHighlightEnabled = v
                    if not v and gunHighlight then
                        pcall(function() gunHighlight:Destroy() end); gunHighlight = nil
                    end
                end,
                Desc = "glowing outline around the gun" })
            K.color(G, { Name = "Fill", Flag = "GMFill",
                Default = V.GunModelFill,
                Callback = function(c) V.GunModelFill = c end })
            K.color(G, { Name = "Outline", Flag = "GMOutline",
                Default = V.GunModelOutline,
                Callback = function(c) V.GunModelOutline = c end })
            K.slider(G, { Name = "Fill Transparency", Flag = "GMFillT",
                Default = math.floor((V.GunModelFillTransparency or 0.5) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v) V.GunModelFillTransparency = v / 100 end })
            K.toggle(G, { Name = "Follow Gradient", Flag = "GMHlGrad",
                Title = "Highlight Gradient",
                get = function() return V.GunModelHighlightGradient ~= false end,
                set = function(v) V.GunModelHighlightGradient = v end,
                Desc = "outline rides the same wave as the gun\noff = keeps the fixed colors above" })

            local S2 = tabV:Section({ Side = "Right" })

            K.feature(S2, {
                Title = "Self Skin", Flag = "TP",
                get = function() return V.ThirdPersonEnabled end,
                set = function(v) V.ThirdPersonEnabled = v end,
                Desc = "recolors ur own body\nu see it in third person or spectate",
            })

            K.color(S2, { Name = "Body Color", Flag = "TPColor",
                Default = V.ThirdPersonBodyColor,
                Callback = function(c) V.ThirdPersonBodyColor = c; tpForceRestyle() end,
                Desc = "color of ur own body parts" })
            K.slider(S2, { Name = "Transparency", Flag = "TPTransp",
                Default = math.floor((V.ThirdPersonBodyTransparency or 0) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v)
                    V.ThirdPersonBodyTransparency = v / 100
                    tpForceRestyle()
                end })
            K.dropdown(S2, { Name = "Material", Flag = "TPMat",
                Options = MATERIALS, Default = matName(V.ThirdPersonMaterial),
                Callback = function(n) V.ThirdPersonMaterial = matFromName(n); tpForceRestyle() end })

            K.group(S2, "Highlight")
            K.color(S2, { Name = "Highlight Fill", Flag = "TPFill",
                Default = V.ThirdPersonFill,
                Callback = function(c) V.ThirdPersonFill = c end,
                Desc = "silhouette fill — applies instantly" })
            K.color(S2, { Name = "Highlight Outline", Flag = "TPOutline",
                Default = V.ThirdPersonOutline,
                Callback = function(c) V.ThirdPersonOutline = c end })
            K.slider(S2, { Name = "Highlight Opacity", Flag = "TPFillTransp",
                Default = math.floor((1 - (V.ThirdPersonFillTransparency or 0.55)) * 100),
                Min = 0, Max = 100, Suffix = "%",
                Callback = function(v)

                    V.ThirdPersonFillTransparency = 1 - (v / 100)
                end,
                Desc = "0% = outline only" })
            K.toggle(S2, { Name = "Gradient", Flag = "TPGrad", Title = "TP Gradient",
                get = function() return V.ThirdPersonGradientEnabled end,
                set = function(v) V.ThirdPersonGradientEnabled = v end })

            local GC = tabV:Section({ Side = "Right" })
            GC:Header({ Name = "Gradient" })
            GC:SubLabel({ Text = "blends A into B n back, its not a rainbow" })
            K.color(GC, { Name = "Color A", Flag = "GradA", Default = V.GradientColorA,
                Callback = function(c) V.GradientColorA = c end })
            K.color(GC, { Name = "Color B", Flag = "GradB", Default = V.GradientColorB,
                Callback = function(c) V.GradientColorB = c end })
            K.slider(GC, { Name = "Speed", Flag = "GradSpeed",
                Default = math.floor((V.GradientSpeed or 0.5) * 100),
                Min = 5, Max = 200, Suffix = "%",
                Callback = function(v) V.GradientSpeed = v / 100 end })
            K.slider(GC, { Name = "Wave Spread", Flag = "GradSpread",
                Default = math.floor((V.GunModelGradientSpread or 1.6) * 10),
                Min = 0, Max = 50,
                Callback = function(v)
                    V.GunModelGradientSpread = v / 10

                    for _, rec in pairs(gunStyledParts) do rec.gp = nil end
                end,
                Desc = "0 = whole gun changes color at once" })
        end

        if tabMov then

            local S = tabMov:Section({ Side = "Right" })
            K.feature(S, {
                Title = "Vehicle Fly", Flag = "VehFly",
                get = function() return V.VehicleFlyEnabled end,
                set = function(v) V.VehicleFlyEnabled = v end,
                Desc = "flies whatever ur driving",
            })
            K.slider(S, { Name = "Fly Speed", Flag = "VehFlySpeed",
                Default = V.VehicleFlySpeed, Min = 20, Max = 400, Suffix = " st/s",
                Callback = function(v) V.VehicleFlySpeed = v end })

            K.group(S, "Vehicle Speed")
            K.toggle(S, { Name = "Enabled", Flag = "VehSpeed", Title = "Vehicle Speed",
                get = function() return V.VehicleSpeedEnabled end,
                set = function(v) V.VehicleSpeedEnabled = v end })
            if ui.keybind then

                ui.keybind(S, { Name = "Keybind", Flag = uiFlag("VehSpeed_KB"),
                    Toggle = function()
                        V.VehicleSpeedEnabled = not V.VehicleSpeedEnabled
                        K.syncToggle(uiFlag("VehSpeed"), V.VehicleSpeedEnabled)
                        K.notify("Vehicle Speed", V.VehicleSpeedEnabled and "Enabled" or "Disabled")
                    end })
            end
            K.slider(S, { Name = "Multiplier", Flag = "VehSpeedMult",
                Default = math.floor((V.VehicleSpeedMult or 1) * 10), Min = 10, Max = 60,
                Callback = function(v) V.VehicleSpeedMult = v / 10 end,
                Desc = "10 = stock, 60 = 6x" })
        end

        if tabGM then
            local S = tabGM:Section({ Side = "Left" })
            K.feature(S, {
                Title = "Free Gun", Flag = "FreeGun",
                get = function() return V.FreeGunEnabled end,

                set = function(v)
                    V.FreeGunEnabled = v
                    if not v then restoreFreeGunSeat() end
                end,
                Desc = "lets u draw a weapon where the game blocks it\nlike inside a vehicle",
            })
        end

        if tabMisc then
            local SL = tabMisc:Section({ Side = "Left" })

            K.feature(SL, {
                Title = "Fullbright", Flag = "Fullbright",
                get = function() return V.FullbrightEnabled end,
                set = function(v)
                    V.FullbrightEnabled = v
                    if not v then lightingOff() end
                end,
                Desc = "flat max light, no shadows anywhere\nfor mood lighting use Atmosphere instead",
            })

            K.group(SL, "No Fog")
            K.toggle(SL, { Name = "Enabled", Flag = "NoFog", Title = "No Fog",
                get = function() return V.NoFogEnabled end,
                set = function(v)
                    V.NoFogEnabled = v
                    if not v then lightingOff() end
                end,
                Desc = "strips fog entirely — see the whole map" })

            K.group(SL, "Camera FOV")
            K.toggle(SL, { Name = "Enabled", Flag = "WorldFOVOn", Title = "Camera FOV",
                get = function() return V.WorldFOVEnabled end,
                set = function(v) V.WorldFOVEnabled = v end,
                Desc = "real field of view — wider = see more but aim feels faster" })
            K.slider(SL, { Name = "FOV", Flag = "WorldFOV",
                Default = V.WorldFOV or 70, Min = 40, Max = 120, Suffix = "°",
                Callback = function(v) V.WorldFOV = v end,
                Desc = "70 = game default" })

            local SA = tabMisc:Section({ Side = "Left" })
            K.feature(SA, {
                Title = "Atmosphere", Flag = "Ambient",
                get = function() return V.AmbientEnabled end,
                set = function(v)
                    V.AmbientEnabled = v
                    if not v then lightingOff() end
                end,
                Desc = "ur own time of day n mood\noverrides whatever the map sets",
            })

            local ambRefresh
            local _ambSync = false
            local elPreset

            elPreset = K.dropdown(SA, { Name = "Preset", Flag = "AmbPreset",
                Options = AMBIENT_PRESET_ORDER,
                Default = V.AmbientPreset or "Custom",
                Callback = function(v)
                    if _ambSync then return end
                    if v ~= "Custom" and applyAmbientPreset(v) then
                        if ambRefresh then ambRefresh() end
                    else
                        V.AmbientPreset = "Custom"
                    end
                end,
                Desc = "ready-made vibes\ntweak anything below n it flips to Custom" })

            local function manual()
                if _ambSync then return end
                if V.AmbientPreset == "Custom" then return end
                V.AmbientPreset = "Custom"
                if elPreset then
                    _ambSync = true
                    pcall(function() elPreset:UpdateSelection("Custom") end)
                    _ambSync = false
                end
            end

            local elTime = K.slider(SA, { Name = "Time of Day", Flag = "ClockTime",
                Default = V.AmbientClockTime or 12, Min = 0, Max = 24,
                Precision = 1, Suffix = "h",
                Callback = function(v) V.AmbientClockTime = v; manual() end,
                Desc = "0 = midnight · 6 = dawn · 12 = noon · 18 = sunset" })
            local elBright = K.slider(SA, { Name = "Brightness", Flag = "AmbBright2",
                Default = V.AmbientBrightness or 2, Min = 0, Max = 6,
                Precision = 1,
                Callback = function(v) V.AmbientBrightness = v; manual() end,
                Desc = "2 = game default · 4+ = washed out" })
            local elExp = K.slider(SA, { Name = "Exposure", Flag = "AmbExp2",
                Default = V.AmbientExposure or 0, Min = -2, Max = 2,
                Precision = 2,
                Callback = function(v) V.AmbientExposure = v; manual() end,
                Desc = "0 = neutral · minus = darker · plus = blown out" })

            K.group(SA, "Colors")
            local elAmb = K.color(SA, { Name = "Shadow Tint", Flag = "AmbColor",
                Default = V.AmbientColor,
                Callback = function(c) V.AmbientColor = c; manual() end,
                Desc = "color of everything in shade — the main mood dial" })
            local elOut = K.color(SA, { Name = "Outdoor Tint", Flag = "AmbOutColor",
                Default = V.AmbientOutdoorColor,
                Callback = function(c) V.AmbientOutdoorColor = c; manual() end,
                Desc = "color of open-sky lighting" })
            local elTintT = K.color(SA, { Name = "Highlight Tint", Flag = "AmbTintTop",
                Default = V.AmbientTintTop,
                Callback = function(c) V.AmbientTintTop = c; manual() end,
                Desc = "tints lit surfaces — keep it subtle, black = off" })
            local elTintB = K.color(SA, { Name = "Shade Tint", Flag = "AmbTintBottom",
                Default = V.AmbientTintBottom,
                Callback = function(c) V.AmbientTintBottom = c; manual() end,
                Desc = "tints unlit surfaces, black = off" })

            K.group(SA, "Sun & Shadows")
            local elLat = K.slider(SA, { Name = "Sun Angle", Flag = "AmbSunAngle",
                Default = V.AmbientLatitude or 45, Min = -90, Max = 90,
                Precision = 0, Suffix = "°",
                Callback = function(v) V.AmbientLatitude = v; manual() end,
                Desc = "where the sun sits · 0 = overhead track" })

            local elShadows = K.toggle(SA, { Name = "Shadows", Flag = "AmbShadows", Title = "Shadows",
                get = function() return V.AmbientShadows ~= false end,
                set = function(v) V.AmbientShadows = v; manual() end,
                Desc = "off = flat lighting, slightly better fps" })

            K.group(SA, "Fog")
            local elFogOn = K.toggle(SA, { Name = "Custom Fog", Flag = "AmbFogOn", Title = "Custom Fog",
                get = function() return V.AmbientFogEnabled end,
                set = function(v) V.AmbientFogEnabled = v; manual() end,
                Desc = "haze n distance mood\nuse No Fog instead if u just want it gone" })
            local elFogCol = K.color(SA, { Name = "Fog Color", Flag = "AmbFogColor",
                Default = V.AmbientFogColor,
                Callback = function(c) V.AmbientFogColor = c; manual() end })
            local elFogStart = K.slider(SA, { Name = "Fog Start", Flag = "AmbFogStart",
                Default = V.AmbientFogStart or 0, Min = 0, Max = 2000, Suffix = " st",
                Callback = function(v) V.AmbientFogStart = v; manual() end,
                Desc = "distance where fog begins" })
            local elFogEnd = K.slider(SA, { Name = "Fog End", Flag = "AmbFogEnd",
                Default = V.AmbientFogEnd or 800, Min = 50, Max = 5000, Suffix = " st",
                Callback = function(v) V.AmbientFogEnd = v; manual() end,
                Desc = "distance where fog is solid" })

            ambRefresh = function()
                _ambSync = true
                local function setV(el, val)
                    if el and val then pcall(function() el:UpdateValue(val, true) end) end
                end
                local function setC(el, col)
                    if el and col then pcall(function() el:SetColor(col) end) end
                end

                setV(elTime,     V.AmbientClockTime or 12)
                setV(elBright,   V.AmbientBrightness or 2)
                setV(elExp,      V.AmbientExposure or 0)
                setV(elLat,      V.AmbientLatitude or 45)
                setV(elFogStart, V.AmbientFogStart or 0)
                setV(elFogEnd,   V.AmbientFogEnd or 800)
                setC(elAmb,      V.AmbientColor)
                setC(elOut,      V.AmbientOutdoorColor)
                setC(elTintT,    V.AmbientTintTop)
                setC(elTintB,    V.AmbientTintBottom)
                setC(elFogCol,   V.AmbientFogColor)
                if elShadows then pcall(function() elShadows:UpdateState(V.AmbientShadows ~= false) end) end
                if elFogOn   then pcall(function() elFogOn:UpdateState(V.AmbientFogEnabled == true) end) end

                if elPreset and V.AmbientPreset then
                    pcall(function() elPreset:UpdateSelection(V.AmbientPreset) end)
                end
                _ambSync = false
            end

            K.button(SA, { Name = "Reset Atmosphere", Title = "Atmosphere",
                Callback = function()
                    applyAmbientPreset("Clear")
                    ambRefresh()
                    return "reset to Clear"
                end })

            local SIN = tabMisc:Section({ Side = "Right" })
            SIN:Header({ Name = "Interactions" })

            K.toggle(SIN, { Name = "No Prompt Hold", Flag = "NoFWait", Title = "No Prompt Hold",
                get = function() return V.NoFWaitEnabled end,
                set = function(v)
                    V.NoFWaitEnabled = v
                    if v then enableNoFWait() else disableNoFWait() end
                end,
                Desc = "prompts fire instantly instead of holding F" })
            K.toggle(SIN, { Name = "Lockpick Bypass", Flag = "Lockpick", Title = "Lockpick Bypass",
                get = function() return V.LockpickBypassEnabled end,
                set = function(v) V.LockpickBypassEnabled = v end,
                Desc = "solves the lockpick minigame for u" })
        end

        if tabDbg then
            local D = tabDbg:Section({ Side = "Left" })
            D:Header({ Name = "Visuals" })
            K.slider(D, { Name = "Lockpick Scan", Flag = "DbgLockpick",
                Default = math.floor((V.LockpickScanInterval or 0.4) * 1000),
                Min = 100, Max = 2000, Suffix = " ms",
                Callback = function(v) V.LockpickScanInterval = v / 1000 end })
            K.slider(D, { Name = "Restyle Period", Flag = "DbgVmRestyle",
                Default = math.floor((V.VmRestyleSec or 3) * 1000),
                Min = 500, Max = 10000, Suffix = " ms",
                Callback = function(v) V.VmRestyleSec = v / 1000 end,
                Desc = "how often late arm/gun parts get repainted" })
        end

        K.ready()
    end

    do
        local g = (type(getgenv) == "function" and getgenv()) or _G
        local prev = g.BRM5_VIS_MODULE
        if type(prev) == "table" and type(prev.stop) == "function" and prev ~= M then
            pcall(prev.stop)
        end
        g.BRM5_VIS_MODULE = M
    end
    if Bridge.registerModule then Bridge.registerModule("visuals", M) end

    return M
end
