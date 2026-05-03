-- ent_ka52_30mm_bullet / init.lua
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local MUZZLE_VELOCITY   = 25000
local FALL_SPEED        = 1.5
local VELOCITY_DECAY    = 0.9
local VELOCITY_APPROACH = 50000
local BLAST_RADIUS      = 80
local BLAST_DAMAGE      = 40
local HEI_INTERVAL      = 90

local IMPACT_SOUNDS = {
    "physics/concrete/impact_bullet1.wav",
    "physics/concrete/impact_bullet2.wav",
    "physics/concrete/impact_bullet3.wav",
    "physics/dirt/impact_bullet1.wav",
    "physics/dirt/impact_bullet2.wav",
    "physics/dirt/impact_bullet3.wav",
    "physics/metal/metal_solid_impact_bullet1.wav",
    "physics/metal/metal_solid_impact_bullet2.wav",
    "physics/metal/metal_solid_impact_bullet3.wav",
}

local FIRE_SOUNDS = {
    "npc_ka52/weapons/30mm.wav",
    "npc_ka52/weapons/30mm2.wav",
    "npc_ka52/weapons/30mm3.wav",
}
for _, s in ipairs(FIRE_SOUNDS) do util.PrecacheSound(s) end

local GAU_CAL_ID = 3

-- ============================================================
--  SPAWN
-- ============================================================

function ENT:Initialize()
    -- ENT.Model in shared.lua tells the engine which model to load.
    -- DO NOT call self:Spawn() here -- it is called externally by the heli
    -- and calling it again inside Initialize() causes a recursive crash.
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)
    self:SetModelScale(3, 0)

    self.bul_position    = self:GetPos()
    self.bul_direction   = self:GetAngles():Forward()
    self.bul_velocity    = MUZZLE_VELOCITY
    self.bul_fallSpeed   = FALL_SPEED
    self.bul_dirAngle    = self.bul_direction:Angle()
    self.bul_initVel     = MUZZLE_VELOCITY
    self.bul_isTracer    = true
    self.bul_damage      = self.BulletDmg    or BLAST_DAMAGE
    self.bul_radius      = self.BulletRad    or BLAST_RADIUS
    self.bul_index       = self.BulletIndex  or 1
    self.bul_firer       = self.Firer
    self.bul_heiInterval = self.HEIInterval  or HEI_INTERVAL

    local muzzlePos = self.MuzzlePos or self:GetPos()
    sound.Play(table.Random(FIRE_SOUNDS), muzzlePos, 125, math.random(117, 125), 1.0)

    net.Start("ka52_bullet_tracer")
        net.WriteVector(self.bul_position)
        net.WriteVector(self.bul_direction)
        net.WriteBool(true)
        net.WriteUInt(self:EntIndex(), 16)
    net.Broadcast()

    self:NextThink(CurTime())
end

-- ============================================================
--  THINK
-- ============================================================

function ENT:Think()
    local ct = CurTime()
    local dt = engine.TickInterval()

    if util.PointContents(self.bul_position) == CONTENTS_SOLID then
        self:Remove()
        return
    end

    local normalized    = math.NormalizeAngle(self.bul_dirAngle.p)
    self.bul_dirAngle.p = math.Approach(normalized, 90, self.bul_fallSpeed * dt)
    self.bul_direction  = self.bul_dirAngle:Forward()

    local traceStart = self.bul_position
    local traceEnd   = traceStart + self.bul_direction * self.bul_velocity * dt

    local filter = { self }
    if IsValid(self.bul_firer) then table.insert(filter, self.bul_firer) end

    local tr = util.TraceLine({
        start  = traceStart,
        endpos = traceEnd,
        filter = filter,
        mask   = MASK_SHOT,
    })

    self.bul_velocity = math.Approach(
        self.bul_velocity,
        self.bul_initVel * VELOCITY_DECAY,
        dt * VELOCITY_APPROACH
    )

    self.bul_position = tr.HitPos
    self:SetPos(self.bul_position)
    self:SetAngles(self.bul_dirAngle)

    net.Start("ka52_bullet_pos")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteVector(tr.HitPos)
        net.WriteVector(self.bul_direction)
    net.Broadcast()

    if tr.Hit or tr.HitSky then
        self:OnImpact(tr, traceStart)
        self:Remove()
        return
    end

    self:NextThink(ct + dt)
end

-- ============================================================
--  IMPACT
-- ============================================================

function ENT:OnImpact(tr, oldPos)
    local hitPos = tr.HitPos

    local firer = IsValid(self.bul_firer) and self.bul_firer or self
    util.BlastDamage(firer, firer, hitPos + Vector(0, 0, 36), self.bul_radius, self.bul_damage)

    local ed1 = EffectData()
    ed1:SetOrigin(hitPos) ed1:SetScale(1.5) ed1:SetMagnitude(1.5) ed1:SetRadius(40)
    util.Effect("gred_ground_impact", ed1, true, true)

    local ed2 = EffectData()
    ed2:SetOrigin(hitPos) ed2:SetScale(0.5) ed2:SetMagnitude(0.5) ed2:SetRadius(4)
    util.Effect("Sparks", ed2, true, true)

    net.Start("gred_net_createimpact")
        net.WriteVector(hitPos)
        net.WriteAngle(Angle(0, 0, 0))
        net.WriteUInt(0, 5)
        net.WriteUInt(GAU_CAL_ID, 4)
    net.Broadcast()

    sound.Play(table.Random(IMPACT_SOUNDS), hitPos, 75, math.random(95, 105), 0.8)

    if self.bul_index % self.bul_heiInterval == 0 then
        self:SpawnHEI(hitPos)
    end

    net.Start("ka52_bullet_remove")
        net.WriteUInt(self:EntIndex(), 16)
    net.Broadcast()
end

function ENT:SpawnHEI(groundPos)
    if not (gred and gred.CreateShell) then return end
    local firer = IsValid(self.bul_firer) and self.bul_firer or self
    local shell = gred.CreateShell(
        groundPos + Vector(0, 0, 30), Angle(90, 0, 0),
        firer, { firer }, 20, "HE", 80, 0.1, nil, 60, nil, 0.005
    )
    if not IsValid(shell) then return end
    if shell.Arm      then shell:Arm()          end
    if shell.SetArmed then shell:SetArmed(true) end
    shell.Armed = true shell.ShouldExplode = true
    local sp = shell:GetPhysicsObject()
    if IsValid(sp) then sp:EnableGravity(true) sp:SetVelocity(Vector(0, 0, -8000)) end
end
