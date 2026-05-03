-- ent_ka52_30mm_bullet / init.lua
-- Physical bullet entity ported from CW2.0 cw_physical_bullets.lua
-- Simulates real bullet flight: gravity drop, velocity decay, tracer FX,
-- blast damage on impact. Designed for an NPC firer (no player/weapon needed).

AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
--  CONSTANTS  (ported 1:1 from CW2.0)
-- ============================================================

local MUZZLE_VELOCITY   = 10000   -- GMod units/s  (~930 m/s scaled)
local FALL_SPEED        = 1.5     -- deg/s pitch droop  (CW2.0 default)
local VELOCITY_DECAY    = 0.9     -- asymptote: 90 % of initial velocity
local VELOCITY_APPROACH = 10000   -- units/s² bleed rate
local BLAST_RADIUS      = 80
local BLAST_DAMAGE      = 40
local HEI_INTERVAL      = 90      -- every Nth bullet spawns HEI

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
    -- position + direction must be set by the spawner before Spawn()
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)

    -- bullet state  (mirrors CW2.0 struct fields)
    self.bul_position   = self:GetPos()
    self.bul_direction  = self:GetAngles():Forward()
    self.bul_velocity   = MUZZLE_VELOCITY
    self.bul_fallSpeed  = FALL_SPEED
    self.bul_dirAngle   = self.bul_direction:Angle()
    self.bul_initVel    = MUZZLE_VELOCITY
    self.bul_isTracer   = self.IsTracer   or false
    self.bul_damage     = self.BulletDmg  or BLAST_DAMAGE
    self.bul_radius     = self.BulletRad  or BLAST_RADIUS
    self.bul_index      = self.BulletIndex or 1
    self.bul_firer      = self.Firer       -- the heli ent
    self.bul_heiInterval = self.HEIInterval or HEI_INTERVAL

    -- play per-bullet fire crack at muzzle
    local muzzlePos = self.MuzzlePos or self:GetPos()
    sound.Play(table.Random(FIRE_SOUNDS), muzzlePos, 125, math.random(117, 125), 1.0)

    -- network tracer position to clients
    net.Start("ka52_bullet_tracer")
        net.WriteVector(self.bul_position)
        net.WriteVector(self.bul_direction)
        net.WriteBool(self.bul_isTracer)
        net.WriteUInt(self:EntIndex(), 16)
    net.Broadcast()

    self:NextThink(CurTime())
end

-- ============================================================
--  THINK — bullet flight loop (CW2.0 processPhysicalBullet)
-- ============================================================

function ENT:Think()
    local ct = CurTime()
    local dt = engine.TickInterval()

    -- abort if stuck inside solid  (CW2.0: util.PointContents check)
    if util.PointContents(self.bul_position) == CONTENTS_SOLID then
        self:Remove()
        return
    end

    -- ---- gravity droop on pitch  (CW2.0 exact logic) ----
    local normalized   = math.NormalizeAngle(self.bul_dirAngle.p)
    self.bul_dirAngle.p = math.Approach(normalized, 90, self.bul_fallSpeed * dt)
    self.bul_direction  = self.bul_dirAngle:Forward()

    -- ---- trace segment ----
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

    -- ---- velocity decay  (CW2.0 exact formula) ----
    self.bul_velocity = math.Approach(
        self.bul_velocity,
        self.bul_initVel * VELOCITY_DECAY,
        dt * VELOCITY_APPROACH
    )

    -- broadcast updated position to clients each tick
    net.Start("ka52_bullet_pos")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteVector(tr.HitPos)
        net.WriteVector(self.bul_direction)
    net.Broadcast()

    self.bul_position = tr.HitPos
    self:SetPos(self.bul_position)

    if tr.Hit or tr.HitSky then
        self:OnImpact(tr, traceStart)
        self:Remove()
        return
    end

    self:NextThink(ct + dt)
end

-- ============================================================
--  IMPACT  (CW2.0 bulletData callback + blast damage)
-- ============================================================

function ENT:OnImpact(tr, oldPos)
    local hitPos = tr.HitPos

    -- blast damage  (replaces old TakeDamageInfo direct hit)
    local firer = IsValid(self.bul_firer) and self.bul_firer or self
    util.BlastDamage(firer, firer, hitPos + Vector(0, 0, 36), self.bul_radius, self.bul_damage)

    -- visual impact FX
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

    -- HEI round  (every HEI_INTERVAL-th bullet)
    if self.bul_index % self.bul_heiInterval == 0 then
        self:SpawnHEI(hitPos)
    end

    -- notify clients: bullet gone
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
