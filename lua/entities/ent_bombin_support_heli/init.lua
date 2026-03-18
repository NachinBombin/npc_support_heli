AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
include("shared.lua")

-- ============================================================
-- SOUNDS — KA-50 profile
-- ============================================================

local ENGINE_START_SOUND = "WAC/KA-50/start.wav"
local ENGINE_LOOP_SOUND  = "^WAC/KA-50/external.wav"
local ENGINE_DIST_SOUND  = "^WAC/KA-50/external.wav"
local GAU_LOOP_SOUND     = "WAC/KA-50/2A42.wav"
local GAU_STOP_SOUND     = "WAC/KA-50/2A42_stop.wav"

-- ============================================================
-- WEAPON TUNING
-- ============================================================

ENT.WeaponWindow = 8

ENT.MuzzlePoints = {
    Vector(140, -35, 43),
    Vector( 20, -80, 46),
    Vector( 20,  80, 46),
    Vector( 20, -80, 46),
    Vector( 20,  80, 46),
}

-- [SLOT 1] 30mm 2A42 — Burst mode
ENT.GAU_BurstCount      = 10
ENT.GAU_BurstDelay      = 0.075
ENT.GAU_SweepHalfLength = 300
ENT.GAU_JitterAmount    = 150
ENT.GAU_SecondBurstTime = 4
ENT.GAU_Speed           = 1000
ENT.GAU_Damage          = 40
ENT.GAU_Radius          = 70

-- [SLOT 2] 30mm 2A42 — Sustained spray
ENT.GAU_Spray_Delay        = 0.075
ENT.GAU_Spray_JitterAmount = 250

-- [SLOT 3] S-8 80mm rocket salvo
ENT.S8_Delay        = 0.15
ENT.S8_Count        = 8
ENT.S8_Scatter      = 500
ENT.S8_MuzzlePoints = {
    Vector(20, -80, 46),
    Vector(20,  80, 46),
    Vector(20, -80, 46),
    Vector(20,  80, 46),
}

-- [SLOT 4] 9K121 Vikhr ATGM
ENT.VIKHR_Delay        = 3.0
ENT.VIKHR_Count        = 2
ENT.VIKHR_Scatter      = 80
ENT.VIKHR_MuzzlePoints = {
    Vector(20, -80, 46),
    Vector(20,  80, 46),
}

-- ============================================================
-- INITIALIZE
-- NWVars are set by the spawner BEFORE Spawn()/Initialize(),
-- so they are always available here.
-- ============================================================

function ENT:Initialize()
    self.CenterPos    = self:GetNWVector("BH_CenterPos",    self:GetPos())
    self.CallDir      = self:GetNWVector("BH_CallDir",      Vector(1,0,0))
    self.Lifetime     = self:GetNWFloat( "BH_Lifetime",     40)
    self.Speed        = self:GetNWFloat( "BH_Speed",        250)
    self.OrbitRadius  = self:GetNWFloat( "BH_OrbitRadius",  2500)
    self.SkyHeightAdd = self:GetNWFloat( "BH_SkyHeightAdd", 2500)

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

    self:SetModel("models/sentry/ka-50.mdl")
    self:PhysicsInit(SOLID_VPHYSICS)
    self:SetMoveType(MOVETYPE_VPHYSICS)
    self:SetSolid(SOLID_VPHYSICS)
    self:SetCollisionGroup(COLLISION_GROUP_DEBRIS)
    self:SetPos(spawnPos)

    self:SetBodygroup(4, 1)
    self:SetBodygroup(3, 1)
    self:SetBodygroup(5, 2)

    self:SetRenderMode(RENDERMODE_NORMAL)
    self:SetColor(Color(255, 255, 255, 255))

    self:SetNWInt("HP",    100)
    self:SetNWInt("MaxHP", 100)

    local ang = self.CallDir:Angle()
    self:SetAngles(Angle(0, ang.y - 90, 0))

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
        self.RotorLoopClose:ChangeVolume(1.0, 0)
        self.RotorLoopClose:Play()
    end

    self.RotorLoopDist = CreateSound(self, ENGINE_DIST_SOUND)
    if self.RotorLoopDist then
        self.RotorLoopDist:SetSoundLevel(140)
        self.RotorLoopDist:ChangePitch(95, 0)
        self.RotorLoopDist:ChangeVolume(0.6, 0)
        self.RotorLoopDist:Play()
    end

    self.WeaponSlot = 1
    self.nextShot   = CurTime() + 3.0
    self.BurstShots = 0
    self.GAUFiring  = false
end

-- ============================================================
-- HELPERS
-- ============================================================

function ENT:FindGround(pos)
    local tr = util.TraceLine({
        start  = pos + Vector(0,0,50),
        endpos = pos - Vector(0,0,99999),
    })
    if tr.Hit then return tr.HitPos.z end
    return -1
end

function ENT:Debug(msg)
    if GetConVar("npc_bombinheli_announce") and GetConVar("npc_bombinheli_announce"):GetBool() then
        print("[Bombin Support Heli ENT] " .. tostring(msg))
    end
end

function ENT:SetHP(hp)
    self.HP = math.max(0, hp)
    self:SetNWInt("HP", self.HP)
end

function ENT:GetHP() return self.HP or 100 end

-- ============================================================
-- DAMAGE
-- ============================================================

function ENT:OnTakeDamage(dmginfo)
    local dmg = dmginfo:GetDamage()
    self:SetHP(self:GetHP() - dmg)
    if self:GetHP() <= 0 then
        self:Explode()
    end
end

function ENT:Explode()
    local pos = self:GetPos()
    local eff = EffectData()
    eff:SetOrigin(pos)
    eff:SetScale(3)
    util.Effect("Explosion", eff, true, true)
    util.BlastDamage(self, self, pos, 400, 300)
    if self.RotorLoopClose then self.RotorLoopClose:Stop() end
    if self.RotorLoopDist  then self.RotorLoopDist:Stop()  end
    self:Remove()
end

-- ============================================================
-- THINK
-- ============================================================

function ENT:Think()
    local now = CurTime()
    if now > self.DieTime then self:Remove() return end
    self:UpdateFlight(now)
    self:UpdateWeapons(now)
    self:NextThink(now)
    return true
end

-- ============================================================
-- FLIGHT
-- ============================================================

function ENT:UpdateFlight(now)
    local pos        = self:GetPos()
    local orbitAngle = (now - self.SpawnTime) * (self.Speed / self.OrbitRadius)
    local orbitX     = self.CenterPos.x + math.cos(orbitAngle) * self.OrbitRadius
    local orbitY     = self.CenterPos.y + math.sin(orbitAngle) * self.OrbitRadius
    local orbitPos   = Vector(orbitX, orbitY, self.sky)

    local moveDir = orbitPos - pos
    if moveDir:LengthSqr() > 1 then moveDir:Normalize() end

    local newPos = pos + moveDir * self.Speed * FrameTime()
    newPos.z = self.sky

    self:SetPos(newPos)

    local faceAng = moveDir:Angle()
    faceAng.p = 0
    faceAng.r = 0
    self:SetAngles(faceAng)

    if IsValid(self.PhysObj) then
        self.PhysObj:SetPos(newPos)
        self.PhysObj:SetAngles(faceAng)
    end
end

-- ============================================================
-- WEAPONS
-- ============================================================

function ENT:UpdateWeapons(now)
    if now < self.nextShot then return end

    local bestPly, bestDist = nil, math.huge
    for _, ply in ipairs(player.GetHumans()) do
        if not IsValid(ply) or not ply:Alive() then continue end
        local d = self:GetPos():Distance(ply:GetPos())
        if d < bestDist then bestDist = d bestPly = ply end
    end

    if not IsValid(bestPly) then self.nextShot = now + 2.0 return end

    local targetPos = bestPly:GetPos() + Vector(0, 0, 40)
    local dist      = self:GetPos():Distance(targetPos)

    if dist > 1500 and self.WeaponSlot ~= 4 then
        self.WeaponSlot = 4
    elseif dist > 600 and dist <= 1500 then
        self.WeaponSlot = 3
    else
        if self.WeaponSlot == 4 or self.WeaponSlot == 3 then
            self.WeaponSlot = 1
        end
    end

    if     self.WeaponSlot == 1 then self:FireGAU_Burst(targetPos, now)
    elseif self.WeaponSlot == 2 then self:FireGAU_Spray(targetPos, now)
    elseif self.WeaponSlot == 3 then self:FireS8(targetPos, now)
    elseif self.WeaponSlot == 4 then self:FireVikhr(targetPos, now)
    end
end

-- ============================================================
-- HELPER: spawn a wac_base_30mm bullet entity
-- ============================================================

function ENT:Spawn30mm(muzzle, aimPos)
    local b = ents.Create("wac_base_30mm")
    if not IsValid(b) then return end
    local ang = (aimPos - muzzle):Angle()
    ang = ang + Angle(math.Rand(-3,3), math.Rand(-3,3), math.Rand(-3,3))
    b:SetPos(muzzle)
    b:SetAngles(ang)
    b.Speed  = self.GAU_Speed
    b.Damage = self.GAU_Damage
    b.Radius = self.GAU_Radius
    b.Size   = 0
    b.Width  = 0
    b.col    = Color(0, 255, 0)
    b.Owner  = self
    b:Spawn()
    util.SpriteTrail(b, 0, Color(0,255,0), false, 5, 5, 0.05, 1/16*0.5, "trails/laser.vmt")
end

-- ============================================================
-- 2A42 Burst
-- ============================================================

function ENT:FireGAU_Burst(targetPos, now)
    if self.BurstShots >= self.GAU_BurstCount then
        self.BurstShots = 0
        self.GAUFiring  = false
        if self.GAUSound then self.GAUSound:Stop() self.GAUSound = nil end
        sound.Play(GAU_STOP_SOUND, self:GetPos(), 80, 100, 0.9)
        self.nextShot   = now + self.GAU_SecondBurstTime
        self.WeaponSlot = 2
        return
    end

    if not self.GAUFiring then
        self.GAUFiring = true
        self.GAUSound  = CreateSound(self, GAU_LOOP_SOUND)
        if self.GAUSound then self.GAUSound:SetSoundLevel(100) self.GAUSound:Play() end
    end

    local muzzle      = self:LocalToWorld(self.MuzzlePoints[1])
    local jitter      = Vector(math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount), math.Rand(-self.GAU_JitterAmount, self.GAU_JitterAmount), 0)
    local sweepOffset = math.sin(self.BurstShots / self.GAU_BurstCount * math.pi) * self.GAU_SweepHalfLength
    local aimPos      = targetPos + jitter + self:GetRight() * sweepOffset

    self:Spawn30mm(muzzle, aimPos)
    self.BurstShots = self.BurstShots + 1
    self.nextShot   = now + self.GAU_BurstDelay
end

-- ============================================================
-- 2A42 Spray
-- ============================================================

function ENT:FireGAU_Spray(targetPos, now)
    if not self.SprayCount then self.SprayCount = 0 end

    if self.SprayCount >= 20 then
        self.SprayCount = 0
        if self.GAUSound then self.GAUSound:Stop() self.GAUSound = nil end
        sound.Play(GAU_STOP_SOUND, self:GetPos(), 80, 100, 0.9)
        self.nextShot   = now + 3.0
        self.WeaponSlot = 1
        self.BurstShots = 0
        return
    end

    if not self.GAUFiring then
        self.GAUFiring = true
        self.GAUSound  = CreateSound(self, GAU_LOOP_SOUND)
        if self.GAUSound then self.GAUSound:SetSoundLevel(100) self.GAUSound:Play() end
    end

    local muzzle = self:LocalToWorld(self.MuzzlePoints[1])
    local jitter = Vector(math.Rand(-self.GAU_Spray_JitterAmount, self.GAU_Spray_JitterAmount), math.Rand(-self.GAU_Spray_JitterAmount, self.GAU_Spray_JitterAmount), math.Rand(-50,50))
    self:Spawn30mm(muzzle, targetPos + jitter)
    self.SprayCount = self.SprayCount + 1
    self.nextShot   = now + self.GAU_Spray_Delay
end

-- ============================================================
-- S-8 Rockets
-- ============================================================

function ENT:FireS8(targetPos, now)
    if not self.S8Fired then self.S8Fired = 0 end

    if self.S8Fired >= self.S8_Count then
        self.S8Fired    = 0
        self.nextShot   = now + 6.0
        self.WeaponSlot = 1
        self.BurstShots = 0
        return
    end

    local muzzleIdx = (self.S8Fired % #self.S8_MuzzlePoints) + 1
    local muzzle    = self:LocalToWorld(self.S8_MuzzlePoints[muzzleIdx])
    local spread    = Vector(math.Rand(-self.S8_Scatter, self.S8_Scatter), math.Rand(-self.S8_Scatter, self.S8_Scatter), 0)
    local dir       = (targetPos + spread - muzzle):GetNormalized()

    local rocket = ents.Create("gb_s8kom_rocket")
    if IsValid(rocket) then
        rocket:SetPos(muzzle)
        rocket:SetAngles(dir:Angle())
        rocket:SetOwner(self)
        rocket:Spawn()
        rocket:Activate()
        local phys = rocket:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 1200) phys:Wake() end
    end

    self.S8Fired  = self.S8Fired + 1
    self.nextShot = now + self.S8_Delay
end

-- ============================================================
-- 9K121 Vikhr ATGM
-- ============================================================

function ENT:FireVikhr(targetPos, now)
    if not self.VikhrFired then self.VikhrFired = 0 end

    if self.VikhrFired >= self.VIKHR_Count then
        self.VikhrFired = 0
        self.nextShot   = now + 8.0
        self.WeaponSlot = 3
        return
    end

    local muzzleIdx = (self.VikhrFired % #self.VIKHR_MuzzlePoints) + 1
    local muzzle    = self:LocalToWorld(self.VIKHR_MuzzlePoints[muzzleIdx])
    local dir       = (targetPos - muzzle):GetNormalized()

    local missile = ents.Create("gb_9k121_rocket")
    if IsValid(missile) then
        missile:SetPos(muzzle)
        missile:SetAngles(dir:Angle())
        missile:SetOwner(self)
        missile:Spawn()
        missile:Activate()
        missile:SetVar("TargetPos", targetPos)
        local phys = missile:GetPhysicsObject()
        if IsValid(phys) then phys:SetVelocity(dir * 600) phys:Wake() end
    end

    self.VikhrFired = self.VikhrFired + 1
    self.nextShot   = now + self.VIKHR_Delay
end

-- ============================================================
-- CLEANUP
-- ============================================================

function ENT:OnRemove()
    if self.RotorLoopClose then self.RotorLoopClose:Stop() end
    if self.RotorLoopDist  then self.RotorLoopDist:Stop()  end
    if self.GAUSound       then self.GAUSound:Stop()        end
end
