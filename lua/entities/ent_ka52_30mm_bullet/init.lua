AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local BULLET_MODEL      = "models/weapons/bt_762.mdl"
local MUZZLE_VELOCITY   = 25000
local FALL_SPEED        = 1.5
local VELOCITY_DECAY    = 0.9
local VELOCITY_APPROACH = 50000
local BLAST_RADIUS      = 80
local BLAST_DAMAGE      = 40
local HEI_INTERVAL      = 90
local GAU_CAL_ID        = 3

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
util.PrecacheModel(BULLET_MODEL)

function ENT:Initialize()
    self:SetModel(BULLET_MODEL)
    self:SetModelScale(3, 0)
    self:SetMoveType(MOVETYPE_NONE)
    self:SetSolid(SOLID_NONE)
    self:SetCollisionGroup(COLLISION_GROUP_NONE)
    self:DrawShadow(false)

    self.bul_position    = self:GetPos()
    self.bul_direction   = self:GetAngles():Forward()
    self.bul_velocity    = MUZZLE_VELOCITY
    self.bul_fallSpeed   = FALL_SPEED
    self.bul_dirAngle    = self.bul_direction:Angle()
    self.bul_initVel     = MUZZLE_VELOCITY
    self.bul_damage      = self.BulletDmg   or BLAST_DAMAGE
    self.bul_radius      = self.BulletRad   or BLAST_RADIUS
    self.bul_index       = self.BulletIndex or 1
    self.bul_firer       = self.Firer
    self.bul_heiInterval = self.HEIInterval or HEI_INTERVAL

    -- Per-bullet fire sound (not a loop)
    sound.Play(table.Random(FIRE_SOUNDS), self.MuzzlePos or self:GetPos(), 125, math.random(117, 125), 1.0)

    -- Orange glowing sprite trail
    self:SetNWBool("ka52_trail", true)   -- flag for cl_init if needed
    util.SpriteTrail(self, 0, Color(255, 160, 40, 200), false, 6, 1, 0.18, 1 / (6 + 1) * 0.5, "effects/softglow")

    -- Muzzle flash at spawn origin — vanilla GMod effect
    local mpos = self.MuzzlePos or self:GetPos()
    local med = EffectData()
    med:SetOrigin(mpos)
    med:SetAngles(self:GetAngles())
    med:SetScale(2.5)
    med:SetMagnitude(2.5)
    util.Effect("MuzzleEffect", med, true, true)

    -- Muzzle light flash — brief bright light at the gun barrel
    local mld = DynamicLight(self:EntIndex() + 4096)
    if mld then
        mld.Pos        = mpos
        mld.r          = 255
        mld.g          = 200
        mld.b          = 80
        mld.Brightness = 10
        mld.Size       = 200
        mld.Decay      = 8000   -- fades in ~0.025s
        mld.DieTime    = CurTime() + 0.025
    end

    net.Start("ka52_bullet_tracer")
        net.WriteVector(self.bul_position)
        net.WriteVector(self.bul_direction)
        net.WriteBool(true)
        net.WriteUInt(self:EntIndex(), 16)
    net.Broadcast()

    self:NextThink(CurTime())
end

function ENT:Think()
    local ct = CurTime()
    local dt = engine.TickInterval()

    if util.PointContents(self.bul_position) == CONTENTS_SOLID then
        self:Remove() return
    end

    self.bul_dirAngle.p = math.Approach(
        math.NormalizeAngle(self.bul_dirAngle.p), 90, self.bul_fallSpeed * dt)
    self.bul_direction = self.bul_dirAngle:Forward()

    local traceStart = self.bul_position
    local traceEnd   = traceStart + self.bul_direction * self.bul_velocity * dt

    local filter = { self }
    if IsValid(self.bul_firer) then table.insert(filter, self.bul_firer) end

    local tr = util.TraceLine({ start=traceStart, endpos=traceEnd, filter=filter, mask=MASK_SHOT })

    self.bul_velocity = math.Approach(self.bul_velocity, self.bul_initVel * VELOCITY_DECAY, dt * VELOCITY_APPROACH)

    self.bul_position = tr.HitPos
    self:SetPos(self.bul_position)
    self:SetAngles(self.bul_dirAngle)

    net.Start("ka52_bullet_pos")
        net.WriteUInt(self:EntIndex(), 16)
        net.WriteVector(tr.HitPos)
        net.WriteVector(self.bul_direction)
    net.Broadcast()

    if tr.Hit or tr.HitSky then
        self:OnImpact(tr) self:Remove() return
    end

    self:NextThink(ct + dt)
end

function ENT:OnImpact(tr)
    local hitPos = tr.HitPos
    local firer  = IsValid(self.bul_firer) and self.bul_firer or self

    util.BlastDamage(firer, firer, hitPos + Vector(0,0,36), self.bul_radius, self.bul_damage)

    local ed1 = EffectData()
    ed1:SetOrigin(hitPos) ed1:SetScale(1.5) ed1:SetMagnitude(1.5) ed1:SetRadius(40)
    util.Effect("gred_ground_impact", ed1, true, true)

    local ed2 = EffectData()
    ed2:SetOrigin(hitPos) ed2:SetScale(0.5) ed2:SetMagnitude(0.5) ed2:SetRadius(4)
    util.Effect("Sparks", ed2, true, true)

    net.Start("gred_net_createimpact")
        net.WriteVector(hitPos)
        net.WriteAngle(Angle(0,0,0))
        net.WriteUInt(0, 5)
        net.WriteUInt(GAU_CAL_ID, 4)
    net.Broadcast()

    sound.Play(table.Random(IMPACT_SOUNDS), hitPos, 75, math.random(95,105), 0.8)

    if self.bul_index % self.bul_heiInterval == 0 then self:SpawnHEI(hitPos) end

    net.Start("ka52_bullet_remove")
        net.WriteUInt(self:EntIndex(), 16)
    net.Broadcast()
end

function ENT:SpawnHEI(groundPos)
    if not (gred and gred.CreateShell) then return end
    local firer = IsValid(self.bul_firer) and self.bul_firer or self
    local shell = gred.CreateShell(
        groundPos + Vector(0,0,30), Angle(90,0,0),
        firer, {firer}, 20, "HE", 80, 0.1, nil, 60, nil, 0.005
    )
    if not IsValid(shell) then return end
    shell.Armed = true shell.ShouldExplode = true
    if shell.Arm then shell:Arm() end
    local sp = shell:GetPhysicsObject()
    if IsValid(sp) then sp:EnableGravity(true) sp:SetVelocity(Vector(0,0,-8000)) end
end
