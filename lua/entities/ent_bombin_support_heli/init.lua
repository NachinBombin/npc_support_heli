AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local function HasGred()
    return gred and gred.CreateBullet and gred.CreateShell
end

local PASS_SOUNDS = {
    "lvs_darklord/rotors/rotor_loop_close.wav",
    "lvs_darklord/rotors/rotor_loop_dist.wav",
}

local ENGINE_START_SOUND = "lvs_darklord/mi_engine/mi24_engine_start_exterior.wav"
local ENGINE_LOOP_SOUND  = "^lvs_darklord/rotors/rotor_loop_close.wav"
local ENGINE_DIST_SOUND  = "^lvs_darklord/rotors/rotor_loop_dist.wav"

local SOUNDS_30MM = {
    "30mm.wav",
    "30mm2.wav",
    "30mm3.wav"
}

local SOUNDS_S8_IGNITE = {
    "S8.wav",
    "S82.wav",
    "S83.wav",
    "S84.wav"
}

local SOUNDS_ATGM_IGNITE = {
    "ATGM.wav",
    "ATGM2.wav",
    "ATGM3.wav",
    "ATGM4.wav"
}

local SOUNDS_LAUNCH = {
    "launch1.wav",
    "launch2.wav"
}

local SOUND_ROCKET_IDLE = "rocket_idle.wav"

local GAU_IMPACT_SOUNDS = {
    "gredwitch/impacts/bullet_impact_dirt_01.wav",
    "gredwitch/impacts/bullet_impact_dirt_02.wav",
    "gredwitch/impacts/bullet_impact_dirt_03.wav",
    "gredwitch/impacts/bullet_impact_concrete_01.wav",
    "gredwitch/impacts/bullet_impact_concrete_02.wav",
}

local GAU_CAL_ID = 3

ENT.WeaponWindow = 8

ENT.MuzzlePoints = {
    Vector(110, 0, 93),
    Vector( 57, -84, 40),
    Vector( 57,  84, 40),
    Vector( 87, -111, 37),
    Vector( 87,  111, 37),
}

ENT.GAU_BurstCount      = 10
ENT.GAU_BurstDelay      = 0.1
ENT.GAU_BulletDamage    = 40
ENT.GAU_SweepHalfLength = 300
ENT.GAU_JitterAmount    = 400
ENT.GAU_FirstBurstTime  = 0
ENT.GAU_SecondBurstTime = 4
ENT.GAU_HEI_Interval    = 20

ENT.GAU_Spray_Delay = 0.1

ENT.S8_Delay   = 0.15
ENT.S8_Count   = 22
ENT.S8_Scatter = 1200
ENT.S8_MuzzlePoints = {
    Vector(57, -84,  40),
    Vector(57,  84,  40),
    Vector(57, -111, 40),
    Vector(57,  111, 40),
}

ENT.VIKHR_Delay   = 3.0
ENT.VIKHR_Count   = 2
ENT.VIKHR_Scatter = 80
ENT.VIKHR_MuzzlePoints = {
    Vector(87, -111, 37),
    Vector(87,  111, 37),
}

ENT.FadeDuration = 2.0
ENT.MaxHP = 3100

-- ============================================================
-- NET STRING
-- ============================================================
util.AddNetworkString("bombin_plane_damage_tier")

-- ============================================================
-- DAMAGE TIER HELPERS
-- ============================================================

local function CalcTier(hp, maxHP)
    local frac = hp / maxHP
    if frac > 0.66 then return 0
    elseif frac > 0.33 then return 1
    elseif frac > 0 then return 2
    else return 3
    end
end

local function BroadcastTier(ent, tier)
    net.Start("bombin_plane_damage_tier")
        net.WriteUInt(ent:EntIndex(), 16)
        net.WriteUInt(tier, 2)
    net.Broadcast()
end

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

    self.MaxHP = self.MaxHP or ENT.MaxHP or 3100

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
    self:SetCollisionGroup(COLLISION_GROUP_INTERACTIVE_DEBRIS)
    self:SetPos(spawnPos)

    self:SetBodygroup(4, 1)
    self:SetBodygroup(3, 1)
    self:SetBodygroup(5, 2)

    self:SetRenderMode(RENDERMODE_TRANSALPHA)
    self:SetColor(Color(255, 255, 255, 0))

    self:SetNWInt("HP",    self.MaxHP)
    self:SetNWInt("MaxHP", self.MaxHP)

    local ang = self.CallDir:Angle()
    self:SetAngles(Angle(0, ang.y + 70, 0))
    self.ang = self:GetAngles()

    self.JitterPhase     = math.Rand(0, math.pi * 2)
    self.JitterAmplitude = 12

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
    self.AltDriftRange    = 700
    self.AltDriftLerp     = 0.003

    self.SmoothedRoll  = 0
    self.SmoothedPitch = 0
    self.PrevYaw       = self:GetAngles().y
    self.LastPos       = spawnPos

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

    self.NextPassSound      = CurTime() + math.Rand(5, 10)
    self.CurrentWeapon      = nil
    self.WeaponWindowEnd    = 0
    self.GAU_BurstTimes     = {}
    self.GAU_BurstsFired    = 0
    self.GAU_ActiveBursts   = {}
    self.GAU_SweepStartPos  = nil
    self.GAU_SweepEndPos    = nil
    self.GAU_SweepMuzzlePos = nil
    self.NextShotTimeSpray  = 0
    self.SprayBulletCount   = 0
    self.S8_ShotsFired      = 0
    self.S8_NextShot        = 0
    self.S8_MuzzleIndex     = 1
    self.VIKHR_ShotsFired   = 0
    self.VIKHR_NextShot     = 0
    self.VIKHR_MuzzleIndex  = 1
    self.MuzzleIndexGlobal  = 1
    self.IsDestroyed        = false
    self.DamageTier         = 0

    if not HasGred() then
        self:Debug("WARNING: Gredwitch Base not detected — HEI rounds disabled")
    end

    self:Debug("Spawned at " .. tostring(spawnPos))
end

-- ============================================================
-- DAMAGE HANDLING
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end

    local hp = self:GetNWInt("HP", self.MaxHP or 3100)
    hp = hp - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)
    self:Debug("Hit! HP remaining: " .. tostring(hp))

    local tier = CalcTier(hp, self.MaxHP or 3100)
    if tier ~= self.DamageTier then
        self.DamageTier = tier
        BroadcastTier(self, tier)
    end

    if hp <= 0 then
        self:Debug("Shot down!")
        self:DestroyHeli()
    end
end

function ENT:DestroyHeli()
    if self.IsDestroyed then return end
    self.IsDestroyed = true

    local pos = self:GetPos()
    self.LastPos = pos

    if self.RotorLoopClose then self.RotorLoopClose:Stop() end
    if self.RotorLoopDist  then self.RotorLoopDist:Stop()  end

    local ed1 = EffectData()
    ed1:SetOrigin(pos)
    ed1:SetScale(5) ed1:SetMagnitude(5) ed1:SetRadius(500)
    util.Effect("HelicopterMegaBomb", ed1, true, true)

    local ed2 = EffectData()
    ed2:SetOrigin(pos)
    ed2:SetScale(4) ed2:SetMagnitude(4) ed2:SetRadius(400)
    util.Effect("500lb_air", ed2, true, true)

    local ed3 = EffectData()
    ed3:SetOrigin(pos + Vector(0, 0, 60))
    ed3:SetScale(3) ed3:SetMagnitude(3) ed3:SetRadius(300)
    util.Effect("500lb_air", ed3, true, true)

    sound.Play("ambient/explosions/explode_8.wav", pos, 140, 90, 1.0)
    sound.Play("weapon_AWP.Single",               pos, 145, 60, 1.0)
    sound.Play("lvs_darklord/mi_engine/mi24_engine_stop_exterior.wav", pos, 90, 100, 1.0)

    util.BlastDamage(self, self, pos, 300, 120)
    self:Remove()
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug(msg)
    print("[Npc KA-50] " .. tostring(msg))
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink(CurTime() + 0.1)
        return true
    end

    local ct = CurTime()
    self.LastPos = self:GetPos()
    if ct >= self.DieTime then self:Remove() return end

    if not IsValid(self.PhysObj) then
        self.PhysObj = self:GetPhysicsObject()
    end
    if IsValid(self.PhysObj) and self.PhysObj:IsAsleep() then
        self.PhysObj:Wake()
    end

    if self.NextPassSound and ct >= self.NextPassSound then
        sound.Play(table.Random(PASS_SOUNDS), self:GetPos(), 100, math.random(96, 104), 1.0)
        self.NextPassSound = ct + math.Rand(6, 12)
    end

    local age  = ct - self.SpawnTime
    local left = self.DieTime - ct
    local alpha = 255
    if age < self.FadeDuration then
        alpha = math.Clamp(255 * (age / self.FadeDuration), 0, 255)
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
    if not self.DieTime or not self.sky then return end
    if CurTime() >= self.DieTime then self:Remove() return end

    local pos = self:GetPos()
    self.LastPos = pos

    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand(-self.AltDriftRange, self.AltDriftRange)
        self.AltDriftNextPick = CurTime() + math.Rand(10, 25)
    end
    self.AltDriftCurrent = Lerp(self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget)

    self.JitterPhase = self.JitterPhase + 0.04
    local jitter     = math.sin(self.JitterPhase) * self.JitterAmplitude
    local liveAlt    = self.AltDriftCurrent + jitter

    local dist = Vector(pos.x, pos.y, 0):Distance(Vector(self.CenterPos.x, self.CenterPos.y, 0))

    local orbitYaw = 0
    if dist > self.OrbitRadius and (self.TurnDelay or 0) < CurTime() then
        orbitYaw       = 0.1
        self.TurnDelay = CurTime() + 0.02
    end

    local skyYaw = 0
    if util.QuickTrace(self:GetPos(), self:GetForward() * 3000, self).HitSky then
        skyYaw = 0.3
    end

    self.ang = self.ang + Angle(0, orbitYaw + skyYaw, 0)

    local currentYaw  = self.ang.y
    local rawYawDelta = math.NormalizeAngle(currentYaw - (self.PrevYaw or currentYaw))
    self.PrevYaw      = currentYaw

    local targetRoll  = math.Clamp(rawYawDelta * -20, -20, 20)
    self.SmoothedRoll = Lerp(rawYawDelta ~= 0 and 0.12 or 0.04, self.SmoothedRoll, targetRoll)

    local vel          = IsValid(phys) and phys:GetVelocity() or Vector(0,0,0)
    local forwardSpeed = vel:Dot(self:GetForward())
    local speedRatio   = math.Clamp(forwardSpeed / self.Speed, 0, 1)
    self.SmoothedPitch = Lerp(0.04, self.SmoothedPitch, math.Clamp(speedRatio * 12, -15, 15))

    self.ang.p = self.SmoothedPitch
    self.ang.r = self.SmoothedRoll

    self:SetPos(Vector(pos.x, pos.y, liveAlt))
    self:SetAngles(self.ang)

    if IsValid(phys) then
        phys:SetVelocity(self:GetForward() * self.Speed)
    end

    local flatPos    = Vector(pos.x, pos.y, 0)
    local flatCenter = Vector(self.CenterPos.x, self.CenterPos.y, 0)
    if not self:IsInWorld() then
        self:Debug("Out of world — removing")
        self:Remove()
    end
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
