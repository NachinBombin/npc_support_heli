AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Permanent yaw correction so the KA-50 mesh faces the direction of travel.
local MODEL_YAW_OFFSET = 70

local function HasGred()
    return gred and gred.CreateBullet and gred.CreateShell
end

-- ============================================================
-- SOUNDS
-- ============================================================

local ENGINE_LOOP_SOUND = "lyutyy/engine_high.wav"

local SOUNDS_30MM = { "30mm.wav", "30mm2.wav", "30mm3.wav" }
local SOUNDS_S8_IGNITE   = { "S8.wav",   "S82.wav",   "S83.wav",   "S84.wav"   }
local SOUNDS_ATGM_IGNITE = { "ATGM.wav", "ATGM2.wav", "ATGM3.wav", "ATGM4.wav" }
local SOUNDS_LAUNCH      = { "launch1.wav", "launch2.wav" }
local SOUND_ROCKET_IDLE  = "rocket_idle.wav"

local GAU_IMPACT_SOUNDS = {
    "gredwitch/impacts/bullet_impact_dirt_01.wav",
    "gredwitch/impacts/bullet_impact_dirt_02.wav",
    "gredwitch/impacts/bullet_impact_dirt_03.wav",
    "gredwitch/impacts/bullet_impact_concrete_01.wav",
    "gredwitch/impacts/bullet_impact_concrete_02.wav",
}

local GAU_CAL_ID = 3

-- ============================================================
-- TUNING
-- ============================================================

local CFG_WeaponWindow = 8

local CFG_MuzzlePoints = {
    Vector(110,   0, 93),
    Vector( 57, -84, 40),
    Vector( 57,  84, 40),
    Vector( 87,-111, 37),
    Vector( 87, 111, 37),
}

local CFG_GAU_BurstCount      = 10
local CFG_GAU_BurstDelay      = 0.1
local CFG_GAU_BulletDamage    = 40
local CFG_GAU_BlastRadius     = 80
local CFG_GAU_SweepHalfLength = 300
local CFG_GAU_JitterAmount    = 400
local CFG_GAU_FirstBurstTime  = 0
local CFG_GAU_SecondBurstTime = 4
local CFG_GAU_HEI_Interval    = 20
local CFG_GAU_Spray_Delay     = 0.1

local CFG_S8_Delay   = 0.15
local CFG_S8_Count   = 22
local CFG_S8_Scatter = 1200
local CFG_S8_MuzzlePoints = {
    Vector(57, -84,  40),
    Vector(57,  84,  40),
    Vector(57,-111, 40),
    Vector(57, 111, 40),
}

local CFG_VIKHR_Delay   = 3.0
local CFG_VIKHR_Count   = 2
local CFG_VIKHR_Scatter = 80
local CFG_VIKHR_MuzzlePoints = {
    Vector(87,-111, 37),
    Vector(87, 111, 37),
}

local CFG_FadeDuration = 2.0
local CFG_MaxHP        = 3100

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

    self.MaxHP        = CFG_MaxHP
    self.FadeDuration = CFG_FadeDuration
    self.WeaponWindow = CFG_WeaponWindow
    self.MuzzlePoints = CFG_MuzzlePoints

    self.GAU_BurstCount      = CFG_GAU_BurstCount
    self.GAU_BurstDelay      = CFG_GAU_BurstDelay
    self.GAU_BulletDamage    = CFG_GAU_BulletDamage
    self.GAU_BlastRadius     = CFG_GAU_BlastRadius
    self.GAU_SweepHalfLength = CFG_GAU_SweepHalfLength
    self.GAU_JitterAmount    = CFG_GAU_JitterAmount
    self.GAU_FirstBurstTime  = CFG_GAU_FirstBurstTime
    self.GAU_SecondBurstTime = CFG_GAU_SecondBurstTime
    self.GAU_HEI_Interval    = CFG_GAU_HEI_Interval
    self.GAU_Spray_Delay     = CFG_GAU_Spray_Delay

    self.S8_Delay        = CFG_S8_Delay
    self.S8_Count        = CFG_S8_Count
    self.S8_Scatter      = CFG_S8_Scatter
    self.S8_MuzzlePoints = CFG_S8_MuzzlePoints

    self.VIKHR_Delay        = CFG_VIKHR_Delay
    self.VIKHR_Count        = CFG_VIKHR_Count
    self.VIKHR_Scatter      = CFG_VIKHR_Scatter
    self.VIKHR_MuzzlePoints = CFG_VIKHR_MuzzlePoints

    if self.CallDir:LengthSqr() <= 1 then self.CallDir = Vector(1,0,0) end
    self.CallDir.z = 0
    self.CallDir:Normalize()

    local ground = self:FindGround(self.CenterPos)
    if ground == -1 then self:Debug("FindGround failed") self:Remove() return end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    self.OrbitDirection = (math.random(2) == 1) and 1 or -1

    local outward = VectorRand()
    outward.z = math.Rand(-0.08, 0.08)
    outward:Normalize()
    local tangent = Vector(0,0,1):Cross(outward)
    tangent.z = 0
    if tangent:LengthSqr() < 0.001 then tangent = Vector(1,0,0) end
    tangent:Normalize()
    if tangent:Dot(self.CallDir) < 0 then tangent = -tangent end
    self.OrbitTangent = tangent * self.OrbitDirection

    self.RadialGain   = 0.42
    self.SkyAvoidGain = 0.65
    self.MaxTurnRate  = 32

    local spawnOffset = self.OrbitTangent * (-self.OrbitRadius * math.Rand(0.55, 0.95))
    local spawnPos    = self.CenterPos + spawnOffset
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

    self.flightYaw = self.OrbitTangent:Angle().y
    self.PrevYaw   = self.flightYaw
    self.ang       = Angle(0, self.flightYaw + MODEL_YAW_OFFSET, 0)
    self:SetAngles(self.ang)

    self.JitterPhase     = math.Rand(0, math.pi * 2)
    self.JitterAmplitude = 12

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand(8, 20)
    self.AltDriftRange    = 700
    self.AltDriftLerp     = 0.003

    self.SmoothedRoll  = 0
    self.SmoothedPitch = 0

    self.IsTumbling        = false
    self.TumbleStartTime   = 0
    self.TumbleGroundZ     = ground
    self.TumbleCrashed     = false
    self.TumbleVelocity    = Vector(0,0,0)
    self.TumbleAngVelocity = Vector(0,0,0)

    self.IsDestroyed = false
    self.DamageTier  = 0

    self.PhysObj = self:GetPhysicsObject()
    if IsValid(self.PhysObj) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity(false)
    end

    -- Single engine loop
    self.EngineLoop = CreateSound(self, ENGINE_LOOP_SOUND)
    if self.EngineLoop then
        self.EngineLoop:SetSoundLevel(125)
        self.EngineLoop:ChangePitch(100, 0)
        self.EngineLoop:ChangeVolume(1.0, 0.5)
        self.EngineLoop:Play()
    end

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

    if not HasGred() then
        self:Debug("WARNING: Gredwitch Base not detected — HEI rounds disabled")
    end

    self:Debug("Spawned at " .. tostring(spawnPos) .. " OrbitDirection=" .. self.OrbitDirection)
end

-- ============================================================
-- SOUND STOP HELPER
-- ============================================================

function ENT:StopEngineSound()
    if not self.EngineLoop then return end
    local snd = self.EngineLoop
    self.EngineLoop = nil  -- nil first so OnRemove won't double-stop
    local FADE = 1.5
    snd:ChangeVolume(0, FADE)
    snd:ChangePitch(55, FADE + 0.5)
    timer.Simple(FADE + 0.2, function()
        if snd then snd:Stop() end
    end)
end

-- ============================================================
-- DAMAGE HANDLING
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType(DMG_CRUSH) then return end

    local hp = self:GetNWInt("HP", self.MaxHP)
    hp = hp - dmginfo:GetDamage()
    self:SetNWInt("HP", hp)
    self:Debug("Hit! HP remaining: " .. tostring(hp))

    local tier = CalcTier(hp, self.MaxHP)
    if tier ~= self.DamageTier then
        self.DamageTier = tier
        BroadcastTier(self, tier)
    end

    if hp <= 0 then self:Debug("Shot down!") self:DestroyHeli() end
end

-- [... file content omitted for brevity in this transcript ...]
