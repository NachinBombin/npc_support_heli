if SERVER then
    AddCSLuaFile()

    util.AddNetworkString("BombinSupportHeli_FlareSpawned")

    -- ============================================================
    -- ConVars
    -- ============================================================

    local SHARED_FLAGS = bit.bor(FCVAR_ARCHIVE, FCVAR_REPLICATED, FCVAR_NOTIFY)

    local cv_enabled  = CreateConVar("npc_bombinheli_enabled",   "1",    SHARED_FLAGS, "Enable/disable support heli calls")
    local cv_chance   = CreateConVar("npc_bombinheli_chance",    "0.12", SHARED_FLAGS, "Probability per check")
    local cv_interval = CreateConVar("npc_bombinheli_interval",  "12",   SHARED_FLAGS, "Seconds between NPC checks")
    local cv_cooldown = CreateConVar("npc_bombinheli_cooldown",  "50",   SHARED_FLAGS, "Cooldown per NPC")
    local cv_max_dist = CreateConVar("npc_bombinheli_max_dist",  "3000", SHARED_FLAGS, "Max call distance")
    local cv_min_dist = CreateConVar("npc_bombinheli_min_dist",  "400",  SHARED_FLAGS, "Min call distance")
    local cv_delay    = CreateConVar("npc_bombinheli_delay",     "5",    SHARED_FLAGS, "Flare -> heli arrival delay")
    local cv_life     = CreateConVar("npc_bombinheli_lifetime",  "40",   SHARED_FLAGS, "Heli lifetime seconds")
    local cv_speed    = CreateConVar("npc_bombinheli_speed",     "250",  SHARED_FLAGS, "Heli forward speed HU/s")
    local cv_radius   = CreateConVar("npc_bombinheli_radius",    "2500", SHARED_FLAGS, "Orbit radius HU")
    local cv_height   = CreateConVar("npc_bombinheli_height",    "2500", SHARED_FLAGS, "Altitude above ground HU")
    local cv_announce = CreateConVar("npc_bombinheli_announce",  "0",    SHARED_FLAGS, "Debug prints")

    -- ============================================================
    -- NPC classes that can call the heli
    -- ============================================================

    local CALLERS = {
        ["npc_combine_s"]      = true,
        ["npc_metropolice"]    = true,
        ["npc_combine_elite"]  = true,
    }

    -- ============================================================
    -- HELPERS
    -- ============================================================

    local function BSP_Debug(msg)
        if not cv_announce:GetBool() then return end
        local full = "[Bombin Support Heli] " .. tostring(msg)
        print(full)
        for _, ply in ipairs(player.GetHumans()) do
            if IsValid(ply) then ply:PrintMessage(HUD_PRINTCONSOLE, full) end
        end
    end

    local function CheckSkyAbove(pos)
        local tr = util.TraceLine({
            start  = pos + Vector(0,0,50),
            endpos = pos + Vector(0,0,1050),
        })
        if tr.Hit and not tr.HitSky then
            tr = util.TraceLine({
                start  = tr.HitPos + Vector(0,0,50),
                endpos = tr.HitPos + Vector(0,0,1000),
            })
        end
        return not (tr.Hit and not tr.HitSky)
    end

    -- Returns a random flat unit vector that is NOT within `minDot` of `exclude`.
    -- minDot = cos(angle) of the exclusion cone, e.g. 0.7 excludes ±45 degrees.
    -- This ensures the heli never arrives from the same direction as the NPC-target
    -- bearing, preventing a predictable, memorisable approach angle every call.
    local function RandomApproachDir(exclude, minDot)
        minDot = minDot or 0.7
        for _ = 1, 32 do
            local yaw = math.Rand(0, 360)
            local dir = Angle(0, yaw, 0):Forward()
            dir.z = 0
            dir:Normalize()
            if dir:Dot(exclude) < minDot then
                return dir
            end
        end
        -- Fallback: perpendicular to the excluded direction
        return Vector(-exclude.y, exclude.x, 0):GetNormalized()
    end

    local function ThrowSupportFlare(npc, targetPos)
        local npcEyePos = npc:EyePos()
        local toTarget  = (targetPos - npcEyePos):GetNormalized()

        local flare = ents.Create("ent_bombin_flare_blue")
        if not IsValid(flare) then
            BSP_Debug("Flare spawn failed")
            return nil
        end

        flare:SetPos(npcEyePos + toTarget * 52)
        flare:SetAngles(npc:GetAngles())
        flare:Spawn()
        flare:Activate()

        local dir  = targetPos - flare:GetPos()
        local dist = dir:Length()
        dir:Normalize()

        timer.Simple(0, function()
            if not IsValid(flare) then return end
            local phys = flare:GetPhysicsObject()
            if not IsValid(phys) then return end
            phys:SetVelocity(dir * 700 + Vector(0,0,dist * 0.25))
            phys:Wake()
        end)

        net.Start("BombinSupportHeli_FlareSpawned")
        net.WriteEntity(flare)
        net.Broadcast()

        BSP_Debug("Flare thrown")
        return flare
    end

    local function SpawnSupportHeliAtPos(centerPos, callDir)
        if not scripted_ents.GetStored("ent_bombin_support_heli") then
            BSP_Debug("ent_bombin_support_heli not registered")
            return false
        end

        local heli = ents.Create("ent_bombin_support_heli")
        if not IsValid(heli) then
            BSP_Debug("ents.Create returned invalid entity")
            return false
        end

        heli:SetPos(centerPos)
        heli:SetAngles(callDir:Angle())
        heli:SetVar("CenterPos",    centerPos)
        heli:SetVar("CallDir",      callDir)
        heli:SetVar("Lifetime",     cv_life:GetFloat())
        heli:SetVar("Speed",        cv_speed:GetFloat())
        heli:SetVar("OrbitRadius",  cv_radius:GetFloat())
        heli:SetVar("SkyHeightAdd", cv_height:GetFloat())
        heli:Spawn()
        heli:Activate()

        if not IsValid(heli) then
            BSP_Debug("Entity invalid after Spawn()")
            return false
        end

        BSP_Debug("Heli spawned at " .. tostring(centerPos) .. " callDir " .. tostring(callDir:Angle().y) .. "deg")
        return true
    end

    local function FireBombinSupportHeli(npc, target)
        if not IsValid(npc) then BSP_Debug("NPC invalid") return false end
        if not IsValid(target) or not target:IsPlayer() or not target:Alive() then
            BSP_Debug("Target invalid") return false
        end

        local targetPos = target:GetPos() + Vector(0,0,36)
        if not CheckSkyAbove(targetPos) then
            BSP_Debug("No open sky above target") return false
        end

        -- Compute the direct NPC-to-target bearing so we can exclude it.
        local directDir = targetPos - npc:GetPos()
        directDir.z = 0
        if directDir:LengthSqr() <= 1 then directDir = npc:GetForward() directDir.z = 0 end
        if directDir:LengthSqr() <= 1 then directDir = Vector(1,0,0) end
        directDir:Normalize()

        -- Pick a randomised approach direction that avoids the direct bearing.
        -- The heli will NOT always arrive from the same angle as the NPC is facing
        -- or the same side of the fight every time.
        local callDir = RandomApproachDir(directDir, 0.7)

        local flare = ThrowSupportFlare(npc, targetPos)
        if not IsValid(flare) then BSP_Debug("Flare failed") return false end

        local fallbackPos = Vector(targetPos.x, targetPos.y, targetPos.z)
        local storedDir   = Vector(callDir.x, callDir.y, callDir.z)

        timer.Simple(cv_delay:GetFloat(), function()
            local centerPos = IsValid(flare) and flare:GetPos() or fallbackPos
            SpawnSupportHeliAtPos(centerPos, storedDir)
        end)

        return true
    end

    -- ============================================================
    -- MAIN POLL TIMER
    -- ============================================================

    timer.Create("BombinSupportHeli_Think", 0.5, 0, function()
        if not cv_enabled:GetBool() then return end

        local now      = CurTime()
        local interval = math.max(1, cv_interval:GetFloat())

        for _, npc in ipairs(ents.GetAll()) do
            if not IsValid(npc) or not CALLERS[npc:GetClass()] then continue end

            if not npc.__bombinheli_hooked then
                npc.__bombinheli_hooked    = true
                npc.__bombinheli_nextCheck = now + math.Rand(1, interval)
                npc.__bombinheli_lastCall  = 0
            end

            if now < npc.__bombinheli_nextCheck then continue end

            local jitter = math.min(2, interval * 0.5)
            npc.__bombinheli_nextCheck = now + interval + math.Rand(-jitter, jitter)

            if now - npc.__bombinheli_lastCall < cv_cooldown:GetFloat() then continue end
            if npc:Health() <= 0 then continue end

            local enemy = npc:GetEnemy()
            if not IsValid(enemy) or not enemy:IsPlayer() or not enemy:Alive() then continue end

            local dist = npc:GetPos():Distance(enemy:GetPos())
            if dist > cv_max_dist:GetFloat() or dist < cv_min_dist:GetFloat() then continue end

            if math.random() > cv_chance:GetFloat() then continue end

            if FireBombinSupportHeli(npc, enemy) then
                npc.__bombinheli_lastCall = now
                BSP_Debug("Call accepted targeting " .. tostring(enemy))
            end
        end
    end)

end -- SERVER

-- ============================================================
-- CLIENT — flare blue dynamic light
-- ============================================================

if CLIENT then
    local activeFlares = {}

    net.Receive("BombinSupportHeli_FlareSpawned", function()
        local flare = net.ReadEntity()
        if IsValid(flare) then
            activeFlares[flare:EntIndex()] = flare
        end
    end)

    hook.Add("Think", "BombinSupportHeli_FlareLight", function()
        for idx, flare in pairs(activeFlares) do
            if not IsValid(flare) then
                activeFlares[idx] = nil
                continue
            end

            local dlight = DynamicLight(flare:EntIndex())
            if dlight then
                dlight.Pos        = flare:GetPos()
                dlight.r          = 0
                dlight.g          = 80
                dlight.b          = 255
                dlight.Brightness = (math.random() > 0.4) and math.Rand(4.0,6.0) or math.Rand(0.0,0.2)
                dlight.Size       = 55
                dlight.Decay      = 3000
                dlight.DieTime    = CurTime() + 0.05
            end
        end
    end)
end
