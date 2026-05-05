AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

local BULLET_MODEL    = "models/weapons/bt_762.mdl"
local MUZZLE_VELOCITY = 25000
local BLAST_RADIUS    = 80
local BLAST_DAMAGE    = 40
local HEI_INTERVAL    = 90
local GAU_CAL_ID      = 3
local MAX_RANGE       = 32768   -- max travel distance per bullet
local STEP_SIZE       = 2048    -- trace in chunks to avoid engine limits

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

    local origin = self:GetPos()
    local fwd    = self:GetAngles():Forward()

    self.bul_firer       = self.Firer
    self.bul_damage      = self.BulletDmg   or BLAST_DAMAGE
    self.bul_radius      = self.BulletRad   or BLAST_RADIUS
    self.bul_index       = self.BulletIndex or 1
    self.bul_heiInterval = self.HEIInterval or HEI_INTERVAL

    -- Per-bullet fire sound
    sound.Play(table.Random(FIRE_SOUNDS), self.MuzzlePos or origin, 125, math.random(117, 125), 1.0)

    -- Net: muzzle flash position for client
    local mpos = self.MuzzlePos or origin
    net.Start("ka52_bullet_tracer")
        net.WriteVector(mpos)
        net.WriteVector(fwd)
        net.WriteBool(true)
        net.WriteUInt(self:EntIndex(), 16)
    net.Broadcast()

    -- Trace the full bullet path right now, in chunks
    local filter = { self }
    if IsValid(self.bul_firer) then table.insert(filter, self.bul_firer) end

    local pos      = origin
    local traveled = 0
    local hitTr    = nil

    while traveled < MAX_RANGE do
        local step    = math.min(STEP_SIZE, MAX_RANGE - traveled)
        local endpos  = pos + fwd * step
        local tr      = util.TraceLine({ start=pos, endpos=endpos, filter=filter, mask=MASK_SHOT })

        if tr.Hit then
            hitTr    = tr
            traveled = traveled + pos:Distance(tr.HitPos)
            pos      = tr.HitPos
            break
        end

        pos      = endpos
        traveled = traveled + step
    end

    -- Place the entity at the final position so the trail starts there visually
    local finalPos = hitTr and hitTr.HitPos or pos
    self:SetPos(finalPos)

    -- Attach a SpriteTrail from muzzle origin to impact point.
    -- We position the entity at muzzle, let the trail grow as it moves to impact.
    -- Actually: place entity at muzzle, move to impact in Think so trail renders.
    self:SetPos(mpos)
    self.bul_targetPos = finalPos
    self.bul_hitTr     = hitTr
    self.bul_startPos  = mpos
    self.bul_startTime = CurTime()
    -- How long the visual travel takes (purely cosmetic, fast but visible)
    self.bul_travelTime = mpos:Distance(finalPos) / MUZZLE_VELOCITY

    util.SpriteTrail(self, 0, Color(255, 200, 80, 255), true, 18, 0, 1.2, 1, "trails/laser")

    self:NextThink(CurTime())
end

function ENT:Think()
    local ct      = CurTime()
    local elapsed = ct - self.bul_startTime
    local frac    = math.Clamp(elapsed / math.max(self.bul_travelTime, 0.001), 0, 1)

    -- Move entity smoothly from muzzle to impact for trail rendering
    local pos = LerpVector(frac, self.bul_startPos, self.bul_targetPos)
    self:SetPos(pos)

    if frac >= 1 then
        -- Bullet has visually arrived — apply damage and effects
        if self.bul_hitTr then
            self:OnImpact(self.bul_hitTr)
        end
        self:Remove()
        return
    end

    self:NextThink(ct + engine.TickInterval())
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
