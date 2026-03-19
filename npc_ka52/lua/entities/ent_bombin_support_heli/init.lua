AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
-- GRED GUARD
-- ============================================================

local function HasGred()
    return gred and gred.CreateBullet and gred.CreateShell
end

-- ============================================================
-- PASS SOUNDS — KA-50 rotor + engine profile
-- ============================================================

local PASS_SOUNDS = {
    "lvs_darklord/rotors/rotor_loop_close.wav",
    "lvs_darklord/rotors/rotor_loop_dist.wav",
}

local ENGINE_START_SOUND = "lvs_darklord/mi_engine/mi24_engine_start_exterior.wav"
local ENGINE_LOOP_SOUND  = "^lvs_darklord/rotors/rotor_loop_close.wav"
local ENGINE_DIST_SOUND  = "^lvs_darklord/rotors/rotor_loop_dist.wav"
local GAU_LOOP_SOUND     = "2А42_1_LOOP"
local GAU_STOP_SOUND     = "2А42_LASTSHOT"

-- ============================================================
-- WEAPON TUNING
-- ============================================================

ENT.WeaponWindow = 8

ENT.MuzzlePoints = {
    Vector(110,    0, 93),
    Vector( 57,  -84, 40),
    Vector( 57,   84, 40),
    Vector( 87, -111, 37),
    Vector( 87,  111, 37),
}

-- [SLOT 1] 30mm 2A42 — Burst mode
ENT.GAU_BurstCount      = 10
ENT.GAU_BurstDelay      = 0.11
ENT.GAU_Caliber         = "gredwitch_30x165mm"
ENT.GAU_DamageMul       = 1.0
ENT.GAU_RadiusMul       = 0.8
ENT.GAU_SweepHalfLength = 300
ENT.GAU_JitterAmount    = 150
ENT.GAU_FirstBurstTime  = 0
ENT.GAU_SecondBurstTime = 4

-- [SLOT 2] 30mm 2A42 — Sustained mode
ENT.GAU_Spray_Delay        = 0.11
ENT.GAU_Spray_JitterAmount = 250

-- [SLOT 3] S-8 80mm rocket salvo
ENT.S8_Delay        = 0.15
ENT.S8_Count        = 8
ENT.S8_Scatter      = 500
ENT.S8_MuzzlePoints = {
    Vector(57,  -84, 40),
    Vector(57,   84, 40),
    Vector(57, -111, 40),
    Vector(57,  111, 40),
}

-- [SLOT 4] 9K121 Vikhr ATGM
ENT.VIKHR_Delay        = 3.0
ENT.VIKHR_Count        = 2
ENT.VIKHR_Scatter      = 80
ENT.VIKHR_MuzzlePoints = {
    Vector(87, -111, 37),
    Vector(87,  111, 37),
}

ENT.FadeDuration = 2.0

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
    self.CenterPos    = self:GetVar("CenterPos",    self:GetPos())
    self.CallDir      = self:GetVar("CallDir",      Vector(1,0,0))
    self.Lifetime     = self:GetVar("Lifetime",     40)
    self.Speed        = self:GetVar("Speed",        250)
    self.OrbitRadius  = self:GetVar("OrbitRadius",  2500)
    self.SkyHeightAdd = self:GetVar("SkyHeightAdd", 2500)

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    local spawnPos = self.CenterPos - self.CallDir * 2000
    spawnPos = Vector(spawnPos.x, spawnPos.y, self.sky)
    if not util.IsInWorld(spawnPos) then
        spawnPos = Vector(self.CenterPos.x, self.CenterPos.y, self.sky)
    end
    if not util.IsInWorld(spawnPos) then
        self:Debug("Spawn position out of world") self:Remove() return
    end

    self:SetModel("models/heli/rus/ka50/ka50.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    self:SetPos(spawnPos)

    self:SetBodygroup(4, 1)
    self:SetBodygroup(3, 1)
    self:SetBodygroup(5, 2)

    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))

    self:SetNWInt("HP",    100)
    self:SetNWInt("MaxHP", 100)

    local ang = self.CallDir:Angle()
    self:SetAngles(Angle(0, ang.y - 90, 0))
    self.ang = self:GetAngles()

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    sound.Play(ENGINE_START_SOUND, spawnPos, 90, 100, 1.0)

    self.RotorLoopClose = CreateSound(self, ENGINE_LOOP_SOUND)
    if self.RotorLoopClose then
        self.RotorLoopClose:SetSoundLevel(125)
        self.RotorLoopClose:ChangePitch(100, 0)
        self.RotorLoopClose:ChangeVolume(1.0, 0.5)
        self.RotorLoopClose:Play()
    end

    self.RotorLoopDist = CreateSound(self, ENGINE_DIST_SOUND)
    if self.RotorLoopDist then
        self.RotorLoopDist:SetSoundLevel(125)
        self.RotorLoopDist:ChangePitch(100, 0)
        self.RotorLoopDist:ChangeVolume(1.0, 0.5)
        self.RotorLoopDist:Play()
    end

    self.GAUSoundLoop = CreateSound(self, GAU_LOOP_SOUND)

    self.NextPassSound = CurTime() + math.Rand(5, 10)

    self.CurrentWeapon      = nil
    self.WeaponWindowEnd    = 0
    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.GAU_ActiveBursts   = {}
    self.GAU_SweepStartPos  = nil
    self.GAU_SweepEndPos    = nil
    self.GAU_SweepMuzzlePos = nil
    self.NextShotTime40     = 0
    self.NextShotTimeSpray  = 0
    self.S8_ShotsFired      = 0
    self.S8_NextShot        = 0
    self.S8_MuzzleIndex     = 1
    self.VIKHR_ShotsFired   = 0
    self.VIKHR_NextShot     = 0
    self.VIKHR_MuzzleIndex  = 1
    self.MuzzleIndexGlobal  = 1

    if not HasGred() then
        self:Debug("WARNING: Gredwitch Base not detected — weapons disabled")
    end

    self:Debug("Spawned at " .. tostring(spawnPos))
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug(msg)
    print("[Bombin Support Heli] " .. tostring(msg))
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    local ct = CurTime()

    if ct >= self.DieTime then self:Remove() return end

    if not IsValid(self.PhysObj) then
        self.PhysObj = self:GetPhysicsObject()
    end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then
        self.PhysObj:Wake()
    end

    if ct >= self.NextPassSound then
        sound.Play(
            table.Random(PASS_SOUNDS),
            self:GetPos(), 100, math.random(96,104), 1.0
        )
        self.NextPassSound = ct + math.Rand(6, 12)
    end

    local age  = ct - self.SpawnTime
    local left = self.DieTime - ct
    local alpha = 255
    if age  < self.FadeDuration then
        alpha = math.Clamp(255 * (age  / self.FadeDuration), 0, 255)
    elseif left < self.FadeDuration then
        alpha = math.Clamp(255 * (left / self.FadeDuration), 0, 255)
    end
    self:SetColor(Color(255, 255, 255, math.Round(alpha)))

    self:HandleWeaponWindow(ct)
    self:UpdateActiveGAUBursts(ct)

    self:NextThink(ct)
    return true
end

-- ============================================================
-- FLIGHT
-- ============================================================

function ENT:PhysicsUpdate(phys)
    if CurTime() >= self.DieTime then self:Remove() return end

    local pos = self:GetPos()
    self:SetPos(Vector(pos.x, pos.y, self.sky))
    self:SetAngles(self.ang)

    if IsValid(phys) then
        phys:SetVelocity(self:GetForward() * self.Speed)
    end

    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    local dist       = flatPos:Distance(flatCenter)

    if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        self.ang       = self.ang + Angle(0, 0.1, 0)
        self.TurnDelay = CurTime() + 0.02
    end

    local tr = util.QuickTrace(self:GetPos(), self:GetForward() * 3000, self)
    if tr.HitSky then
        self.ang = self.ang + Angle(0, 0.3, 0)
    end

    if not self:IsInWorld() then
        self:Debug("Out of world — removing")
        self:Remove()
    end
end

-- ============================================================
-- TARGET / MUZZLE HELPERS
-- ============================================================

function ENT:GetPrimaryTarget()
    local closest, closestDist = nil, math.huge
    for _, ply in ipairs(player.GetAll()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr(self.CenterPos)
        if d < closestDist then closestDist = d closest = ply end
    end
    return closest
end

function ENT:GetTargetGroundPos()
    local target = self:GetPrimaryTarget()
    if IsValid(target) then return target:GetPos() end
    local tr = util.QuickTrace(
        Vector(self.CenterPos.x, self.CenterPos.y, self.sky),
        Vector(0, 0, -30000), self
    )
    return tr.HitPos
end

function ENT:GetMuzzleWorldPos(localPoint)
    return self:LocalToWorld(localPoint)
end

function ENT:SpawnMuzzleFX(worldPos)
    local ed = EffectData()
    ed:SetOrigin(worldPos)
    ed:SetAngles(self:GetAngles())
    ed:SetEntity(self)
    util.Effect("gred_particle_aircraft_muzzle", ed, true, true)
end

-- ============================================================
-- WEAPON WINDOW CONTROLLER
-- ============================================================

function ENT:HandleWeaponWindow(ct)
    if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
        self:PickNewWeapon(ct)
    end

    if     self.CurrentWeapon == "30mm_burst"     then self:Update30mmBurstsSchedule(ct)
    elseif self.CurrentWeapon == "30mm_sustained" then self:Update30mmSustained(ct)
    elseif self.CurrentWeapon == "s8_salvo"       then self:UpdateS8Salvo(ct)
    elseif self.CurrentWeapon == "vikhr"          then self:UpdateVikhr(ct)
    end
end

function ENT:PickNewWeapon(ct)
    if self.CurrentWeapon == "30mm_burst" or self.CurrentWeapon == "30mm_sustained" then
        if IsValid(self.GAUSoundLoop) and self.GAUSoundLoop:IsPlaying() then
            self.GAUSoundLoop:Stop()
            sound.Play(GAU_STOP_SOUND, self:GetPos(), 100, 100, 1.0)
        end
    end

    local roll = math.random(1, 4)
    if     roll == 1 then self.CurrentWeapon = "30mm_burst"
    elseif roll == 2 then self.CurrentWeapon = "30mm_sustained"
    elseif roll == 3 then self.CurrentWeapon = "s8_salvo"
    else                  self.CurrentWeapon = "vikhr"
    end

    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug("Weapon: " .. self.CurrentWeapon)

    if self.CurrentWeapon == "30mm_burst" then
        self.GAU_BurstTimes   = { ct + self.GAU_FirstBurstTime, ct + self.GAU_SecondBurstTime }
        self.GAU_BurstsFired  = 0
        self.GAU_ActiveBursts = {}
        if IsValid(self.GAUSoundLoop) then self.GAUSoundLoop:Play() end

    elseif self.CurrentWeapon == "30mm_sustained" then
        self.NextShotTimeSpray  = ct
        local tgt = self:GetTargetGroundPos()
        local sweepDir = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
        if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
        sweepDir:Normalize()
        self.GAU_SweepStartPos  = tgt - sweepDir * self.GAU_SweepHalfLength
        self.GAU_SweepEndPos    = tgt + sweepDir * self.GAU_SweepHalfLength
        self.GAU_SweepMuzzlePos = self:GetMuzzleWorldPos(self.MuzzlePoints[1])
        if IsValid(self.GAUSoundLoop) then self.GAUSoundLoop:Play() end

    elseif self.CurrentWeapon == "s8_salvo" then
        self.S8_ShotsFired  = 0
        self.S8_NextShot    = ct + 0.2
        self.S8_MuzzleIndex = 1

    elseif self.CurrentWeapon == "vikhr" then
        self.VIKHR_ShotsFired  = 0
        self.VIKHR_NextShot    = ct + 0.5
        self.VIKHR_MuzzleIndex = 1
    end
end

-- ============================================================
-- SLOT 1 — 30mm 2A42 BURST
-- ============================================================

function ENT:Update30mmBurstsSchedule(ct)
    if not HasGred() then return end
    if not self.GAU_BurstTimes then return end

    for i, t in ipairs(self.GAU_BurstTimes) do
        if t ~= false and ct >= t and ct < self.WeaponWindowEnd then
            self:StartGAUBurst()
            self.GAU_BurstTimes[i] = false
        end
    end

    if ct >= self.WeaponWindowEnd then
        if IsValid(self.GAUSoundLoop) and self.GAUSoundLoop:IsPlaying() then
            self.GAUSoundLoop:Stop()
            sound.Play(GAU_STOP_SOUND, self:GetPos(), 100, 100, 1.0)
        end
    end
end

function ENT:StartGAUBurst()
    local targetPos = self:GetTargetGroundPos()
    local muzzlePos = self:GetMuzzleWorldPos(self.MuzzlePoints[1])

    local sweepDir = Vector(math.Rand(-1,1), math.Rand(-1,1), 0)
    if sweepDir:LengthSqr() < 0.01 then sweepDir = Vector(1,0,0) end
    sweepDir:Normalize()

    self.GAU_SweepStartPos  = targetPos - sweepDir * self.GAU_SweepHalfLength
    self.GAU_SweepEndPos    = targetPos + sweepDir * self.GAU_SweepHalfLength
    self.GAU_SweepMuzzlePos = muzzlePos

    table.insert(self.GAU_ActiveBursts, { bulletsFired = 0, nextTime = CurTime() })
    self:SpawnMuzzleFX(muzzlePos)
end

function ENT:UpdateActiveGAUBursts(ct)
    if not HasGred() then return end
    if not self.GAU_ActiveBursts then return end

    for idx = #self.GAU_ActiveBursts, 1, -1 do
        local burst = self.GAU_ActiveBursts[idx]
        if not burst then
            table.remove(self.GAU_ActiveBursts, idx)
        elseif ct >= burst.nextTime then
            burst.bulletsFired = burst.bulletsFired + 1
            burst.nextTime     = ct + self.GAU_BurstDelay
            self:Fire30mmBullet(burst.bulletsFired)
            if burst.bulletsFired >= self.GAU_BurstCount then
                table.remove(self.GAU_ActiveBursts, idx)
            end
        end
    end
end

function ENT:Fire30mmBullet(bulletIndex)
    if not HasGred() then return end
    if not self.GAU_SweepStartPos then return end

    local fraction    = math.Clamp((bulletIndex - 1) / math.max(self.GAU_BurstCount - 1, 1), 0, 1)
    local baseImpact  = LerpVector(fraction, self.GAU_SweepStartPos, self.GAU_SweepEndPos)
    local jitter      = Vector(
        math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount),
        math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount),
        0
    )
    local finalImpact = baseImpact + jitter
    local muzzlePos   = self.GAU_SweepMuzzlePos or self:GetMuzzleWorldPos(self.MuzzlePoints[1])

    local dir = finalImpact - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    gred.CreateBullet({
        Attacker  = self,
        Inflictor = self,
        Pos       = muzzlePos,
        Dir       = dir,
        Caliber   = self.GAU_Caliber,
        DamageMul = self.GAU_DamageMul,
        RadiusMul = self.GAU_RadiusMul,
    })

    self:SpawnMuzzleFX(muzzlePos)
end

-- ============================================================
-- SLOT 2 — 30mm 2A42 SUSTAINED
-- ============================================================

function ENT:Update30mmSustained(ct)
    if not HasGred() then return end
    if ct < self.NextShotTimeSpray then return end
    if ct >= self.WeaponWindowEnd then
        if IsValid(self.GAUSoundLoop) and self.GAUSoundLoop:IsPlaying() then
            self.GAUSoundLoop:Stop()
            sound.Play(GAU_STOP_SOUND, self:GetPos(), 100, 100, 1.0)
        end
        return
    end

    self.NextShotTimeSpray = ct + self.GAU_Spray_Delay

    local targetPos   = self:GetTargetGroundPos()
    local finalImpact = targetPos + Vector(
        math.Rand(-self.GAU_Spray_JitterAmount, self.GAU_Spray_JitterAmount),
        math.Rand(-self.GAU_Spray_JitterAmount, self.GAU_Spray_JitterAmount),
        0
    )
    local muzzlePos = self.GAU_SweepMuzzlePos or self:GetMuzzleWorldPos(self.MuzzlePoints[1])

    local dir = finalImpact - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    gred.CreateBullet({
        Attacker  = self,
        Inflictor = self,
        Pos       = muzzlePos,
        Dir       = dir,
        Caliber   = self.GAU_Caliber,
        DamageMul = self.GAU_DamageMul,
        RadiusMul = self.GAU_RadiusMul,
    })

    self:SpawnMuzzleFX(muzzlePos)
end

-- ============================================================
-- SLOT 3 — S-8 80mm ROCKET SALVO (gb_s8kom_rocket)
-- ============================================================

function ENT:UpdateS8Salvo(ct)
    if self.S8_ShotsFired >= self.S8_Count then return end
    if ct < self.S8_NextShot then return end

    self.S8_NextShot   = ct + self.S8_Delay
    self.S8_ShotsFired = self.S8_ShotsFired + 1

    local muzzleLocal = self.S8_MuzzlePoints[self.S8_MuzzleIndex]
    self.S8_MuzzleIndex = self.S8_MuzzleIndex + 1
    if self.S8_MuzzleIndex > #self.S8_MuzzlePoints then self.S8_MuzzleIndex = 1 end

    local muzzlePos = self:GetMuzzleWorldPos(muzzleLocal)
    local targetPos = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.S8_Scatter, self.S8_Scatter),
        math.Rand(-self.S8_Scatter, self.S8_Scatter),
        0
    )
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local rocket = ents.Create("gb_s8kom_rocket")
    if not IsValid(rocket) then self:Debug("gb_s8kom_rocket failed") return end

    rocket:SetPos(muzzlePos)
    rocket:SetAngles(dir:Angle())
    rocket:SetOwner(self)
    rocket.IsOnPlane = true
    rocket:Spawn()
    rocket:Activate()
    rocket.Armed         = true
    rocket.ShouldExplode = true
    rocket:Launch()
    rocket:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local heliPhys = self:GetPhysicsObject()
    local rPhys    = rocket:GetPhysicsObject()
    if IsValid(rPhys) and IsValid(heliPhys) then
        rPhys:AddVelocity(heliPhys:GetVelocity())
    end

    self:SpawnMuzzleFX(muzzlePos)

    constraint.NoCollide(rocket, self, 0, 0)
    local rocketRef = rocket
    timer.Simple(0.5, function()
        if IsValid(rocketRef) and IsValid(self) then
            constraint.RemoveConstraints(rocketRef, "NoCollide")
        end
    end)
end

-- ============================================================
-- SLOT 4 — 9K121 VIKHR ATGM (gb_9k121_rocket)
-- ============================================================

function ENT:UpdateVikhr(ct)
    if self.VIKHR_ShotsFired >= self.VIKHR_Count then return end
    if ct < self.VIKHR_NextShot then return end

    self.VIKHR_NextShot   = ct + self.VIKHR_Delay
    self.VIKHR_ShotsFired = self.VIKHR_ShotsFired + 1

    local muzzleLocal = self.VIKHR_MuzzlePoints[self.VIKHR_MuzzleIndex]
    self.VIKHR_MuzzleIndex = self.VIKHR_MuzzleIndex + 1
    if self.VIKHR_MuzzleIndex > #self.VIKHR_MuzzlePoints then self.VIKHR_MuzzleIndex = 1 end

    local muzzlePos = self:GetMuzzleWorldPos(muzzleLocal)
    local targetPos = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.VIKHR_Scatter, self.VIKHR_Scatter),
        math.Rand(-self.VIKHR_Scatter, self.VIKHR_Scatter),
        0
    )
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local rocket = ents.Create("gb_9k121_rocket")
    if not IsValid(rocket) then self:Debug("gb_9k121_rocket failed") return end

    rocket:SetPos(muzzlePos)
    rocket:SetAngles(dir:Angle())
    rocket:SetOwner(self)
    rocket.IsOnPlane            = true
    rocket:Spawn()
    rocket:Activate()
    rocket.Armed                = true
    rocket.ShouldExplode        = true
    rocket.ShouldExplodeOnImpact = true
    rocket:SetCollisionGroup(COLLISION_GROUP_DEBRIS)

    local startpos = self:LocalToWorld(self:OBBCenter())
    local tr = util.TraceHull({
        start  = startpos,
        endpos = startpos + dir * 500000,
        mins   = Vector(-25,-25,-25),
        maxs   = Vector( 25, 25, 25),
        filter = self,
    })

    local heliPhys = self:GetPhysicsObject()
    local rPhys    = rocket:GetPhysicsObject()
    if IsValid(rPhys) and IsValid(heliPhys) then
        rPhys:AddVelocity(heliPhys:GetVelocity())
    end

    constraint.NoCollide(rocket, self, 0, 0)
    local rocketRef = rocket
    timer.Simple(0.25, function()
        if not IsValid(rocketRef) then return end
        if tr.Hit then
            rocketRef.JDAM         = true
            rocketRef.target       = tr.Entity
            rocketRef.targetOffset = IsValid(tr.Entity) and tr.Entity:WorldToLocal(tr.HitPos) or tr.HitPos
            rocketRef.dropping     = true
        end
        rocketRef.Armed = true
        rocketRef:Launch()
        rocketRef:SetCollisionGroup(0)
    end)

    local oldExplode = rocket.OnExplode
    rocket.OnExplode = function(s, pos, normal)
        if oldExplode then oldExplode(s, pos, normal) end
        local hitPos = pos or s:GetPos()
        local ed1 = EffectData()
        ed1:SetOrigin(hitPos) ed1:SetScale(4) ed1:SetMagnitude(4) ed1:SetRadius(400)
        util.Effect("500lb_air", ed1, true, true)
        local ed2 = EffectData()
        ed2:SetOrigin(hitPos + Vector(0,0,60)) ed2:SetScale(3) ed2:SetMagnitude(3) ed2:SetRadius(300)
        util.Effect("500lb_air", ed2, true, true)
        local ed3 = EffectData()
        ed3:SetOrigin(hitPos) ed3:SetScale(4) ed3:SetMagnitude(4) ed3:SetRadius(400)
        util.Effect("HelicopterMegaBomb", ed3, true, true)
    end

    self:SpawnMuzzleFX(muzzlePos)
    sound.Play("physics/metal/weapon_impact_soft2.wav", muzzlePos, 90, 100, 1.0)
end

-- ============================================================
-- GROUND FINDER
-- ============================================================

function ENT:FindGround(centerPos)
    local startPos   = Vector(centerPos.x, centerPos.y, centerPos.z + 64)
    local endPos     = Vector(centerPos.x, centerPos.y, -16384)
    local filterList = { self }
    local maxIter    = 0

    while maxIter < 100 do
        local tr = util.TraceLine({ start = startPos, endpos = endPos, filter = filterList })
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then
            table.insert(filterList, tr.Entity)
        else
            break
        end
        maxIter = maxIter + 1
    end

    return -1
end

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
    if self.RotorLoopClose then self.RotorLoopClose:Stop() end
    if self.RotorLoopDist  then self.RotorLoopDist:Stop()  end
    if IsValid(self.GAUSoundLoop) and self.GAUSoundLoop:IsPlaying() then
        self.GAUSoundLoop:Stop()
    end
    sound.Play(
        "lvs_darklord/mi_engine/mi24_engine_stop_exterior.wav",
        self:GetPos(), 90, 100, 1.0
    )
end
