AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- Permanent yaw correction so the KA-50 mesh faces the direction of travel.
-- This offset is ALWAYS added on top of flightYaw and must never be removed
-- or overridden by flight steering logic.
local MODEL_YAW_OFFSET = 70

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

-- ============================================================
-- TUNING
-- ============================================================

local CFG_WeaponWindow = 8

local CFG_MuzzlePoints = {
    Vector(110, 0, 93),
    Vector( 57, -84, 40),
    Vector( 57,  84, 40),
    Vector( 87, -111, 37),
    Vector( 87,  111, 37),
}

local CFG_GAU_BurstCount      = 10
local CFG_GAU_BurstDelay      = 0.1
local CFG_GAU_BulletDamage    = 40
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
    Vector(57, -111, 40),
    Vector(57,  111, 40),
}

local CFG_VIKHR_Delay   = 3.0
local CFG_VIKHR_Count   = 2
local CFG_VIKHR_Scatter = 80
local CFG_VIKHR_MuzzlePoints = {
    Vector(87, -111, 37),
    Vector(87,  111, 37),
}

local CFG_FadeDuration = 2.0
local CFG_MaxHP        = 3100

-- ============================================================
-- NET STRING
-- ============================================================
util.AddNetworkString( "bombin_plane_damage_tier" )

-- ============================================================
-- DAMAGE TIER HELPERS
-- ============================================================

local function CalcTier( hp, maxHP )
    local frac = hp / maxHP
    if frac > 0.66 then return 0
    elseif frac > 0.33 then return 1
    elseif frac > 0 then return 2
    else return 3
    end
end

local function BroadcastTier( ent, tier )
    net.Start( "bombin_plane_damage_tier" )
        net.WriteUInt( ent:EntIndex(), 16 )
        net.WriteUInt( tier, 2 )
    net.Broadcast()
end

-- ============================================================
-- INITIALIZE
-- ============================================================

function ENT:Initialize()
    self.CenterPos    = self:GetVar( "CenterPos",    self:GetPos() )
    self.CallDir      = self:GetVar( "CallDir",      Vector(1,0,0) )
    self.Lifetime     = self:GetVar( "Lifetime",     40 )
    self.Speed        = self:GetVar( "Speed",        250 )
    self.OrbitRadius  = self:GetVar( "OrbitRadius",  2500 )
    self.SkyHeightAdd = self:GetVar( "SkyHeightAdd", 2500 )

    self.MaxHP        = CFG_MaxHP
    self.FadeDuration = CFG_FadeDuration
    self.WeaponWindow = CFG_WeaponWindow

    self.MuzzlePoints = CFG_MuzzlePoints

    self.GAU_BurstCount      = CFG_GAU_BurstCount
    self.GAU_BurstDelay      = CFG_GAU_BurstDelay
    self.GAU_BulletDamage    = CFG_GAU_BulletDamage
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

    local ground = self:FindGround( self.CenterPos )
    if ground == -1 then self:Debug( "FindGround failed" ) self:Remove() return end

    self.sky       = ground + self.SkyHeightAdd
    self.DieTime   = CurTime() + self.Lifetime
    self.SpawnTime = CurTime()

    local spawnPos = self.CenterPos - self.CallDir * 2000
    spawnPos = Vector( spawnPos.x, spawnPos.y, self.sky )
    if not util.IsInWorld( spawnPos ) then
        spawnPos = Vector( self.CenterPos.x, self.CenterPos.y, self.sky )
    end
    if not util.IsInWorld( spawnPos ) then
        self:Debug( "Spawn position out of world" ) self:Remove() return
    end

    self:SetModel( "models/heli/rus/ka50/ka50.mdl" )
    self:PhysicsInit( SOLID_VPHYSICS )
    self:SetMoveType( MOVETYPE_VPHYSICS )
    self:SetSolid( SOLID_VPHYSICS )
    self:SetCollisionGroup( COLLISION_GROUP_INTERACTIVE_DEBRIS )
    self:SetPos( spawnPos )

    self:SetBodygroup( 4, 1 )
    self:SetBodygroup( 3, 1 )
    self:SetBodygroup( 5, 2 )

    self:SetRenderMode( RENDERMODE_TRANSALPHA )
    self:SetColor( Color(255, 255, 255, 0) )

    self:SetNWInt( "HP",    self.MaxHP )
    self:SetNWInt( "MaxHP", self.MaxHP )

    -- flightYaw is the pure travel direction.
    -- self.ang.y is always flightYaw + MODEL_YAW_OFFSET so the mesh faces forward.
    local initAng  = self.CallDir:Angle()
    self.flightYaw = initAng.y
    self.PrevYaw   = self.flightYaw
    self.ang       = Angle( 0, self.flightYaw + MODEL_YAW_OFFSET, 0 )
    self:SetAngles( self.ang )

    self.JitterPhase     = math.Rand( 0, math.pi * 2 )
    self.JitterAmplitude = 12

    self.AltDriftCurrent  = self.sky
    self.AltDriftTarget   = self.sky
    self.AltDriftNextPick = CurTime() + math.Rand( 8, 20 )
    self.AltDriftRange    = 700
    self.AltDriftLerp     = 0.003

    self.SmoothedRoll  = 0
    self.SmoothedPitch = 0

    -- Tumble state
    self.IsTumbling        = false
    self.TumbleStartTime   = 0
    self.TumbleGroundZ     = ground
    self.TumbleCrashed     = false
    self.TumbleVelocity    = Vector(0, 0, 0)
    self.TumbleAngVelocity = Vector(0, 0, 0)

    self.LastPos       = spawnPos
    self.IsDestroyed   = false
    self.DamageTier    = 0

    self.PhysObj = self:GetPhysicsObject()
    if IsValid( self.PhysObj ) then
        self.PhysObj:Wake()
        self.PhysObj:EnableGravity( false )
    end

    sound.Play( ENGINE_START_SOUND, spawnPos, 90, 100, 1.0 )

    self.RotorLoopClose = CreateSound( self, ENGINE_LOOP_SOUND )
    if self.RotorLoopClose then
        self.RotorLoopClose:SetSoundLevel( 125 )
        self.RotorLoopClose:ChangePitch( 100, 0 )
        self.RotorLoopClose:ChangeVolume( 1.0, 0.5 )
        self.RotorLoopClose:Play()
    end

    self.RotorLoopDist = CreateSound( self, ENGINE_DIST_SOUND )
    if self.RotorLoopDist then
        self.RotorLoopDist:SetSoundLevel( 125 )
        self.RotorLoopDist:ChangePitch( 100, 0 )
        self.RotorLoopDist:ChangeVolume( 1.0, 0.5 )
        self.RotorLoopDist:Play()
    end

    self.NextPassSound      = CurTime() + math.Rand( 5, 10 )
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
        self:Debug( "WARNING: Gredwitch Base not detected — HEI rounds disabled" )
    end

    self:Debug( "Spawned at " .. tostring(spawnPos) )
end

-- ============================================================
-- DAMAGE HANDLING
-- ============================================================

function ENT:OnTakeDamage( dmginfo )
    if self.IsDestroyed then return end
    if dmginfo:IsDamageType( DMG_CRUSH ) then return end

    local hp = self:GetNWInt( "HP", self.MaxHP )
    hp = hp - dmginfo:GetDamage()
    self:SetNWInt( "HP", hp )
    self:Debug( "Hit! HP remaining: " .. tostring(hp) )

    local tier = CalcTier( hp, self.MaxHP )
    if tier ~= self.DamageTier then
        self.DamageTier = tier
        BroadcastTier( self, tier )
    end

    if hp <= 0 then
        self:Debug( "Shot down!" )
        self:DestroyHeli()
    end
end

-- ============================================================
-- TUMBLE SYSTEM (straight copy from AN-71)
-- ============================================================

function ENT:StartTumble()
    self.IsTumbling      = true
    self.TumbleStartTime = CurTime()
    self.TumbleCrashed   = false

    local gnd = self:FindGround( self:GetPos() )
    if gnd ~= -1 then self.TumbleGroundZ = gnd end

    local travelFwd = Angle(0, self.flightYaw, 0):Forward()
    local speed     = self.Speed or 250

    self.TumbleVelocity = Vector(
        travelFwd.x * speed,
        travelFwd.y * speed,
        -200
    )

    local sign = function() return (math.random(2) == 1) and 1 or -1 end
    self.TumbleAngVelocity = Vector(
        math.Rand(80,  200) * sign(),
        math.Rand(20,  80)  * sign(),
        math.Rand(150, 400) * sign()
    )

    local pos = self:GetPos()
    local ed = EffectData()
    ed:SetOrigin( pos )
    ed:SetScale(4) ed:SetMagnitude(4) ed:SetRadius(400)
    util.Effect( "500lb_air", ed, true, true )
    sound.Play( "ambient/explosions/explode_4.wav", pos, 135, 95, 1.0 )
end

function ENT:CrashExplode()
    if self.TumbleCrashed then return end
    self.TumbleCrashed = true

    local pos = self:GetPos()

    local ed1 = EffectData()
    ed1:SetOrigin( pos )
    ed1:SetScale(6) ed1:SetMagnitude(6) ed1:SetRadius(600)
    util.Effect( "HelicopterMegaBomb", ed1, true, true )

    local ed2 = EffectData()
    ed2:SetOrigin( pos )
    ed2:SetScale(5) ed2:SetMagnitude(5) ed2:SetRadius(500)
    util.Effect( "500lb_air", ed2, true, true )

    local ed3 = EffectData()
    ed3:SetOrigin( pos + Vector(0, 0, 80) )
    ed3:SetScale(4) ed3:SetMagnitude(4) ed3:SetRadius(400)
    util.Effect( "500lb_air", ed3, true, true )

    local ed4 = EffectData()
    ed4:SetOrigin( pos + Vector(0, 0, 180) )
    ed4:SetScale(3) ed4:SetMagnitude(3) ed4:SetRadius(300)
    util.Effect( "500lb_air", ed4, true, true )

    sound.Play( "ambient/explosions/explode_8.wav", pos, 140, 90, 1.0 )
    sound.Play( "weapon_AWP.Single",               pos, 145, 60, 1.0 )

    util.BlastDamage( self, self, pos, 400, 200 )

    self:Remove()
end

function ENT:DestroyHeli()
    if self.IsDestroyed then return end
    self.IsDestroyed = true

    if self.RotorLoopClose then self.RotorLoopClose:Stop() end
    if self.RotorLoopDist  then self.RotorLoopDist:Stop()  end

    self:StartTumble()

    timer.Simple( 12, function()
        if IsValid(self) then self:CrashExplode() end
    end)
end

-- ============================================================
-- DEBUG
-- ============================================================

function ENT:Debug( msg )
    print( "[Npc KA-50] " .. tostring(msg) )
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    if not self.DieTime or not self.SpawnTime then
        self:NextThink( CurTime() + 0.1 )
        return true
    end

    local ct = CurTime()
    self.LastPos = self:GetPos()

    if self.IsTumbling and not self.TumbleCrashed then
        local pos     = self:GetPos()
        local groundZ = self.TumbleGroundZ or -16384

        if pos.z <= groundZ + 150 then
            self:CrashExplode()
            return
        end

        local tr = util.TraceLine({
            start  = pos,
            endpos = pos + Vector(0, 0, -200),
            filter = self,
        })
        if tr.HitWorld then
            self:CrashExplode()
            return
        end

        self:NextThink( ct + 0.05 )
        return true
    end

    if ct >= self.DieTime then self:Remove() return end

    if not IsValid( self.PhysObj ) then
        self.PhysObj = self:GetPhysicsObject()
    end
    if IsValid( self.PhysObj ) and self.PhysObj:IsAsleep() then
        self.PhysObj:Wake()
    end

    if self.NextPassSound and ct >= self.NextPassSound then
        sound.Play( table.Random(PASS_SOUNDS), self:GetPos(), 100, math.random(96, 104), 1.0 )
        self.NextPassSound = ct + math.Rand( 6, 12 )
    end

    local age  = ct - self.SpawnTime
    local left = self.DieTime - ct
    local alpha = 255
    if age < self.FadeDuration then
        alpha = math.Clamp( 255 * (age / self.FadeDuration), 0, 255 )
    elseif left < self.FadeDuration then
        alpha = math.Clamp( 255 * (left / self.FadeDuration), 0, 255 )
    end
    self:SetColor( Color(255, 255, 255, math.Round(alpha)) )

    self:HandleWeaponWindow( ct )
    self:UpdateActiveGAUBursts( ct )

    self:NextThink( ct )
    return true
end

-- ============================================================
-- FLIGHT / TUMBLE PHYSICS
-- ============================================================

function ENT:PhysicsUpdate( phys )
    if not self.DieTime or not self.sky then return end

    -- ---- TUMBLE PATH (straight copy from AN-71) ----
    if self.IsTumbling then
        if self.TumbleCrashed then return end

        local dt      = engine.TickInterval()
        local gravity = physenv.GetGravity().z

        self.TumbleVelocity.z = self.TumbleVelocity.z + gravity * dt

        local pos    = self:GetPos()
        local newPos = pos + self.TumbleVelocity * dt

        local av   = self.TumbleAngVelocity
        local newP = self.ang.p + av.x * dt
        local newY = self.ang.y + av.y * dt
        local newR = self.ang.r + av.z * dt
        self.ang = Angle(newP, newY, newR)

        self:SetPos( newPos )
        self:SetAngles( self.ang )
        if IsValid(phys) then
            phys:SetPos( newPos )
            phys:SetAngles( self.ang )
        end
        return
    end

    if CurTime() >= self.DieTime then self:Remove() return end

    -- ---- NORMAL FLIGHT PATH ----

    local pos = self:GetPos()
    self.LastPos = pos

    -- Altitude drift
    if CurTime() >= self.AltDriftNextPick then
        self.AltDriftTarget   = self.sky + math.Rand( -self.AltDriftRange, self.AltDriftRange )
        self.AltDriftNextPick = CurTime() + math.Rand( 10, 25 )
    end
    self.AltDriftCurrent = Lerp( self.AltDriftLerp, self.AltDriftCurrent, self.AltDriftTarget )

    self.JitterPhase = self.JitterPhase + 0.04
    local jitter     = math.sin( self.JitterPhase ) * self.JitterAmplitude
    local liveAlt    = self.AltDriftCurrent + jitter

    -- Orbit steering — only ever modifies flightYaw, never self.ang.y directly
    if Vector(pos.x,pos.y,0):Distance(Vector(self.CenterPos.x,self.CenterPos.y,0)) > self.OrbitRadius
        and (self.TurnDelay or 0) < CurTime() then
        self.flightYaw = self.flightYaw + 0.1
        self.TurnDelay = CurTime() + 0.02
    end

    -- Sky-wall avoidance: trace along the real travel direction, NOT GetForward().
    -- GetForward() is offset by MODEL_YAW_OFFSET so it would always bias the yaw
    -- the same direction, causing the predetermined-left orbit.
    local travelFwd = Angle(0, self.flightYaw, 0):Forward()
    if util.QuickTrace( self:GetPos(), travelFwd * 3000, self ).HitSky then
        self.flightYaw = self.flightYaw + 0.3
        travelFwd = Angle(0, self.flightYaw, 0):Forward()
    end

    -- Roll / pitch smoothing
    local rawYawDelta  = math.NormalizeAngle( self.flightYaw - (self.PrevYaw or self.flightYaw) )
    self.PrevYaw       = self.flightYaw

    local targetRoll   = math.Clamp( rawYawDelta * -20, -20, 20 )
    self.SmoothedRoll  = Lerp( rawYawDelta ~= 0 and 0.12 or 0.04, self.SmoothedRoll, targetRoll )

    local vel          = IsValid(phys) and phys:GetVelocity() or Vector(0,0,0)
    local forwardSpeed = vel:Dot( travelFwd )
    local speedRatio   = math.Clamp( forwardSpeed / self.Speed, 0, 1 )
    self.SmoothedPitch = Lerp( 0.04, self.SmoothedPitch, math.Clamp(speedRatio * 12, -15, 15) )

    -- MODEL_YAW_OFFSET applied here unconditionally — cannot be overridden by steering
    self.ang = Angle( self.SmoothedPitch, self.flightYaw + MODEL_YAW_OFFSET, self.SmoothedRoll )

    self:SetPos( Vector(pos.x, pos.y, liveAlt) )
    self:SetAngles( self.ang )
    if IsValid(phys) then phys:SetVelocity( travelFwd * self.Speed ) end

    if not self:IsInWorld() then
        self:Debug( "Out of world — rescue warp" )
        self:SetPos( Vector(self.CenterPos.x, self.CenterPos.y, self.sky) )
        self.flightYaw = self.CallDir:Angle().y
        self.ang       = Angle( 0, self.flightYaw + MODEL_YAW_OFFSET, 0 )
    end
end

-- ============================================================
-- TARGET / MUZZLE HELPERS
-- ============================================================

function ENT:GetPrimaryTarget()
    local closest, closestDist = nil, math.huge
    for _, ply in ipairs( player.GetAll() ) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = ply:GetPos():DistToSqr( self.CenterPos )
        if d < closestDist then closestDist = d closest = ply end
    end
    return closest
end

function ENT:GetTargetGroundPos()
    local target = self:GetPrimaryTarget()
    if IsValid(target) then return target:GetPos() end
    local tr = util.QuickTrace(
        Vector( self.CenterPos.x, self.CenterPos.y, self.sky ),
        Vector(0, 0, -30000), self
    )
    return tr.HitPos
end

function ENT:GetMuzzleWorldPos( localPoint )
    return self:LocalToWorld( localPoint )
end

function ENT:SpawnMuzzleFX( worldPos )
    local ed = EffectData()
    ed:SetOrigin( worldPos )
    ed:SetAngles( self:GetAngles() )
    ed:SetEntity( self )
    util.Effect( "gred_particle_aircraft_muzzle", ed, true, true )
end

-- ============================================================
-- WEAPON WINDOW CONTROLLER
-- ============================================================

function ENT:HandleWeaponWindow( ct )
    if not self.CurrentWeapon or ct >= self.WeaponWindowEnd then
        self:PickNewWeapon( ct )
    end

    if     self.CurrentWeapon == "30mm_burst"     then self:Update30mmBurstsSchedule( ct )
    elseif self.CurrentWeapon == "30mm_sustained" then self:Update30mmSustained( ct )
    elseif self.CurrentWeapon == "s8_salvo"       then self:UpdateS8Salvo( ct )
    elseif self.CurrentWeapon == "vikhr"          then self:UpdateVikhr( ct )
    end
end

function ENT:PickNewWeapon( ct )
    local roll = math.random( 1, 4 )
    if     roll == 1 then self.CurrentWeapon = "30mm_burst"
    elseif roll == 2 then self.CurrentWeapon = "30mm_sustained"
    elseif roll == 3 then self.CurrentWeapon = "s8_salvo"
    else                   self.CurrentWeapon = "vikhr"
    end

    self.WeaponWindowEnd = ct + self.WeaponWindow
    self:Debug( "Weapon: " .. self.CurrentWeapon )

    if self.CurrentWeapon == "30mm_burst" then
        self.GAU_BurstTimes   = { ct + self.GAU_FirstBurstTime, ct + self.GAU_SecondBurstTime }
        self.GAU_BurstsFired  = 0
        self.GAU_ActiveBursts = {}
    elseif self.CurrentWeapon == "30mm_sustained" then
        self.NextShotTimeSpray  = ct
        self.SprayBulletCount   = 0
        self.GAU_SweepMuzzlePos = self:GetMuzzleWorldPos( self.MuzzlePoints[1] )
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
-- SHARED 30mm HITSCAN FIRE
-- ============================================================

function ENT:Fire30mmBulletAt( impactPos, bulletIndex )
    local muzzlePos = self.GAU_SweepMuzzlePos or self:GetMuzzleWorldPos( self.MuzzlePoints[1] )

    local traceStart = Vector( impactPos.x, impactPos.y, self.sky + 200 )
    local traceEnd   = Vector( impactPos.x, impactPos.y, -16384 )

    local tr = util.TraceLine({
        start  = traceStart,
        endpos = traceEnd,
        filter = self,
        mask   = MASK_SHOT,
    })

    local hitPos = tr.Hit and tr.HitPos or impactPos

    sound.Play( table.Random(SOUNDS_30MM), muzzlePos, 110, math.random(95, 105), 1.0 )

    local ed1 = EffectData()
    ed1:SetOrigin( hitPos )
    ed1:SetScale(1.5) ed1:SetMagnitude(1.5) ed1:SetRadius(40)
    util.Effect( "gred_ground_impact", ed1, true, true )

    local ed2 = EffectData()
    ed2:SetOrigin( hitPos )
    ed2:SetScale(1) ed2:SetMagnitude(1) ed2:SetRadius(30)
    util.Effect( "Sparks", ed2, true, true )

    net.Start( "gred_net_createimpact" )
        net.WriteVector( hitPos )
        net.WriteAngle( Angle(0,0,0) )
        net.WriteUInt( 0, 5 )
        net.WriteUInt( GAU_CAL_ID, 4 )
    net.Broadcast()

    sound.Play( table.Random(GAU_IMPACT_SOUNDS), hitPos, 75, math.random(95, 105), 0.8 )

    if tr.Hit and IsValid(tr.Entity) and tr.Entity ~= self then
        local ent = tr.Entity
        if ent:IsPlayer() or ent:IsNPC() or ent:GetClass() == "nextbot" then
            local dmginfo = DamageInfo()
            dmginfo:SetAttacker( self )
            dmginfo:SetDamage( self.GAU_BulletDamage )
            dmginfo:SetDamagePosition( hitPos )
            dmginfo:SetDamageType( DMG_BULLET )
            ent:TakeDamageInfo( dmginfo )
        end
    end

    if bulletIndex % self.GAU_HEI_Interval == 0 and HasGred() then
        local shell = gred.CreateShell(
            hitPos + Vector(0, 0, 30),
            Angle(90, 0, 0),
            self, { self },
            20, "HE", 80, 0.1, nil,
            60, nil, 0.005
        )
        if IsValid(shell) then
            if shell.Arm      then shell:Arm()          end
            if shell.SetArmed then shell:SetArmed(true) end
            shell.Armed         = true
            shell.ShouldExplode = true
            local phys = shell:GetPhysicsObject()
            if IsValid(phys) then
                phys:EnableGravity( true )
                phys:SetVelocity( Vector(0, 0, -8000) )
            end
        end
    end

    self:SpawnMuzzleFX( muzzlePos )
end

-- ============================================================
-- SLOT 1 — 30mm BURST
-- ============================================================

function ENT:Update30mmBurstsSchedule( ct )
    if not self.GAU_BurstTimes then return end
    for i, t in ipairs( self.GAU_BurstTimes ) do
        if t ~= false and ct >= t and ct < self.WeaponWindowEnd then
            self:StartGAUBurst()
            self.GAU_BurstTimes[i] = false
        end
    end
end

function ENT:StartGAUBurst()
    local muzzlePos = self:GetMuzzleWorldPos( self.MuzzlePoints[1] )
    self.GAU_SweepMuzzlePos = muzzlePos
    table.insert( self.GAU_ActiveBursts, { bulletsFired = 0, nextTime = CurTime() } )
    self:SpawnMuzzleFX( muzzlePos )
end

function ENT:UpdateActiveGAUBursts( ct )
    if not self.GAU_ActiveBursts then return end
    for idx = #self.GAU_ActiveBursts, 1, -1 do
        local burst = self.GAU_ActiveBursts[idx]
        if not burst then
            table.remove( self.GAU_ActiveBursts, idx )
        elseif ct >= burst.nextTime then
            burst.bulletsFired = burst.bulletsFired + 1
            burst.nextTime     = ct + self.GAU_BurstDelay
            self:Fire30mmBulletFromBurst( burst.bulletsFired )
            if burst.bulletsFired >= self.GAU_BurstCount then
                table.remove( self.GAU_ActiveBursts, idx )
            end
        end
    end
end

function ENT:Fire30mmBulletFromBurst( bulletIndex )
    local finalImpact = self:GetTargetGroundPos() + Vector(
        math.Rand(-300, 300),
        math.Rand(-300, 300),
        0
    )
    self:Fire30mmBulletAt( finalImpact, bulletIndex )
end

-- ============================================================
-- SLOT 2 — 30mm SUSTAINED
-- ============================================================

function ENT:Update30mmSustained( ct )
    if ct < self.NextShotTimeSpray then return end
    if ct >= self.WeaponWindowEnd  then return end

    self.GAU_SweepMuzzlePos = self:GetMuzzleWorldPos( self.MuzzlePoints[1] )
    self.NextShotTimeSpray  = ct + self.GAU_Spray_Delay
    self.SprayBulletCount   = self.SprayBulletCount + 1

    local finalImpact = self:GetTargetGroundPos() + Vector(
        math.Rand(-300, 300),
        math.Rand(-300, 300),
        0
    )
    self:Fire30mmBulletAt( finalImpact, self.SprayBulletCount )
end

-- ============================================================
-- SLOT 3 — S-8 80mm ROCKET SALVO
-- ============================================================

function ENT:UpdateS8Salvo( ct )
    if self.S8_ShotsFired >= self.S8_Count then return end
    if ct < self.S8_NextShot then return end

    self.S8_NextShot   = ct + self.S8_Delay
    self.S8_ShotsFired = self.S8_ShotsFired + 1

    local muzzleLocal = self.S8_MuzzlePoints[self.S8_MuzzleIndex]
    self.S8_MuzzleIndex = self.S8_MuzzleIndex + 1
    if self.S8_MuzzleIndex > #self.S8_MuzzlePoints then self.S8_MuzzleIndex = 1 end

    local muzzlePos = self:GetMuzzleWorldPos( muzzleLocal )
    local targetPos = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.S8_Scatter, self.S8_Scatter),
        math.Rand(-self.S8_Scatter, self.S8_Scatter),
        0
    )
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local rocket = ents.Create( "gb_s8kom_rocket" )
    if not IsValid(rocket) then self:Debug( "gb_s8kom_rocket failed" ) return end

    rocket:SetPos( muzzlePos )
    rocket:SetAngles( dir:Angle() )
    rocket:SetOwner( self )
    rocket.IsOnPlane     = true
    rocket:Spawn()
    rocket:Activate()
    rocket.Armed         = true
    rocket.ShouldExplode = true
    rocket:Launch()
    rocket:SetCollisionGroup( COLLISION_GROUP_DEBRIS )

    local heliPhys = self:GetPhysicsObject()
    local rPhys    = rocket:GetPhysicsObject()
    if IsValid(rPhys) and IsValid(heliPhys) then
        rPhys:AddVelocity( heliPhys:GetVelocity() )
    end

    self:SpawnMuzzleFX( muzzlePos )
    sound.Play( table.Random(SOUNDS_S8_IGNITE), muzzlePos, 110, math.random(95, 105), 1.0 )

    timer.Simple( 0.1, function()
        if IsValid(rocket) then
            sound.Play( table.Random(SOUNDS_LAUNCH), rocket:GetPos(), 105, math.random(95, 105), 1.0 )
        end
    end)

    rocket.IdleSound = CreateSound( rocket, SOUND_ROCKET_IDLE )
    if rocket.IdleSound then
        rocket.IdleSound:Play()
        rocket.IdleSound:ChangePitch( math.random(90, 115), 0 )
        rocket.IdleSound:ChangeVolume( 0.8, 0 )
    end

    rocket.OnRemove = function(s)
        if s.IdleSound then s.IdleSound:Stop() end
    end
    rocket.OnExplode = function(s, pos, normal)
        if s.IdleSound then s.IdleSound:Stop() end
    end

    constraint.NoCollide( rocket, self, 0, 0 )
    local rocketRef = rocket
    timer.Simple( 0.5, function()
        if IsValid(rocketRef) and IsValid(self) then
            constraint.RemoveConstraints( rocketRef, "NoCollide" )
        end
    end)
end

-- ============================================================
-- SLOT 4 — 9K121 VIKHR ATGM
-- ============================================================

function ENT:UpdateVikhr( ct )
    if self.VIKHR_ShotsFired >= self.VIKHR_Count then return end
    if ct < self.VIKHR_NextShot then return end

    self.VIKHR_NextShot    = ct + self.VIKHR_Delay
    self.VIKHR_ShotsFired  = self.VIKHR_ShotsFired + 1

    local muzzleLocal = self.VIKHR_MuzzlePoints[self.VIKHR_MuzzleIndex]
    self.VIKHR_MuzzleIndex = self.VIKHR_MuzzleIndex + 1
    if self.VIKHR_MuzzleIndex > #self.VIKHR_MuzzlePoints then self.VIKHR_MuzzleIndex = 1 end

    local muzzlePos = self:GetMuzzleWorldPos( muzzleLocal )
    local targetPos = self:GetTargetGroundPos() + Vector(
        math.Rand(-self.VIKHR_Scatter, self.VIKHR_Scatter),
        math.Rand(-self.VIKHR_Scatter, self.VIKHR_Scatter),
        0
    )
    local dir = targetPos - muzzlePos
    if dir:LengthSqr() < 1 then return end
    dir:Normalize()

    local rocket = ents.Create( "gb_9k121_rocket" )
    if not IsValid(rocket) then self:Debug( "gb_9k121_rocket failed" ) return end

    rocket:SetPos( muzzlePos )
    rocket:SetAngles( dir:Angle() )
    rocket:SetOwner( self )
    rocket.IsOnPlane             = true
    rocket:Spawn()
    rocket:Activate()
    rocket.Armed                 = true
    rocket.ShouldExplode         = true
    rocket.ShouldExplodeOnImpact = true
    rocket:SetCollisionGroup( COLLISION_GROUP_DEBRIS )

    local startpos = self:LocalToWorld( self:OBBCenter() )
    local tr = util.TraceHull({
        start  = startpos,
        endpos = startpos + dir * 500000,
        mins   = Vector(-25, -25, -25),
        maxs   = Vector( 25,  25,  25),
        filter = self,
    })

    local heliPhys = self:GetPhysicsObject()
    local rPhys    = rocket:GetPhysicsObject()
    if IsValid(rPhys) and IsValid(heliPhys) then
        rPhys:AddVelocity( heliPhys:GetVelocity() )
    end

    constraint.NoCollide( rocket, self, 0, 0 )
    local rocketRef = rocket
    timer.Simple( 0.25, function()
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

    self:SpawnMuzzleFX( muzzlePos )
    sound.Play( table.Random(SOUNDS_ATGM_IGNITE), muzzlePos, 0, 100, 1.0 )

    timer.Simple( 0.1, function()
        if IsValid(rocket) then
            sound.Play( table.Random(SOUNDS_LAUNCH), rocket:GetPos(), 105, math.random(95, 105), 1.0 )
        end
    end)

    rocket.IdleSound = CreateSound( rocket, SOUND_ROCKET_IDLE )
    if rocket.IdleSound then
        rocket.IdleSound:Play()
        rocket.IdleSound:ChangePitch( math.random(85, 110), 0 )
        rocket.IdleSound:ChangeVolume( 0.9, 0 )
    end

    rocket.OnRemove = function(s)
        if s.IdleSound then s.IdleSound:Stop() end
    end
    rocket.OnExplode = function(s, pos, normal)
        if s.IdleSound then s.IdleSound:Stop() end
        local hitPos = pos or s:GetPos()
        local ed1 = EffectData()
        ed1:SetOrigin(hitPos) ed1:SetScale(4) ed1:SetMagnitude(4) ed1:SetRadius(400)
        util.Effect( "500lb_air", ed1, true, true )
        local ed2 = EffectData()
        ed2:SetOrigin(hitPos + Vector(0,0,60)) ed2:SetScale(3) ed2:SetMagnitude(3) ed2:SetRadius(300)
        util.Effect( "500lb_air", ed2, true, true )
        local ed3 = EffectData()
        ed3:SetOrigin(hitPos) ed3:SetScale(4) ed3:SetMagnitude(4) ed3:SetRadius(400)
        util.Effect( "HelicopterMegaBomb", ed3, true, true )
    end
end

-- ============================================================
-- GROUND FINDER
-- ============================================================

function ENT:FindGround( centerPos )
    local startPos   = Vector( centerPos.x, centerPos.y, centerPos.z + 64 )
    local endPos     = Vector( centerPos.x, centerPos.y, -16384 )
    local filterList = { self }
    local maxIter    = 0

    while maxIter < 100 do
        local tr = util.TraceLine({ start = startPos, endpos = endPos, filter = filterList })
        if tr.HitWorld then return tr.HitPos.z end
        if IsValid(tr.Entity) then
            table.insert( filterList, tr.Entity )
        else break end
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
    sound.Play( "lvs_darklord/mi_engine/mi24_engine_stop_exterior.wav", self:GetPos(), 90, 100, 1.0 )
end
