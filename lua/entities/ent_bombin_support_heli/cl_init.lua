include("shared.lua")

function ENT:Initialize()
    self.RPM  = 0
    self.RPM2 = 0
end

function ENT:Draw()
    self:DrawModel()
end

function ENT:Think()
    self:AnimRotor()
    self:DamageFX()
end

function ENT:AnimRotor()
    local RPM = 3500

    self.RPM  = self.RPM  + RPM * RealFrameTime() * 0.5
    self.RPM2 = self.RPM2 + RPM * RealFrameTime() * 0.5

    if self.RPM  > 360 then self.RPM  = self.RPM  - 360 end
    if self.RPM2 > 360 then self.RPM2 = self.RPM2 - 360 end

    local Rot1 = Angle(0, self.RPM,  0)
    local Rot2 = Angle(0, self.RPM2, 0)

    self:ManipulateBoneAngles(11, -Rot1)
    self:ManipulateBoneAngles(12,  Rot2)
end

function ENT:DamageFX()
    self.nextDFX  = self.nextDFX  or 0
    self.nextDFX2 = self.nextDFX2 or 0

    if self.nextDFX < CurTime() then
        self.nextDFX = CurTime() + 0.05
        local HP    = self:GetNWInt("HP", 100)
        local MaxHP = self:GetNWInt("MaxHP", 100)
        if HP > MaxHP * 0.25 then return end

        local effectdata = EffectData()
        effectdata:SetOrigin(self:LocalToWorld(Vector(-22, 47, 82)))
        effectdata:SetNormal(self:GetUp())
        effectdata:SetMagnitude(math.Rand(0.5, 1.5))
        effectdata:SetEntity(self)
        util.Effect("lvs_exhaust_fire", effectdata)
    end

    if self.nextDFX2 < CurTime() then
        self.nextDFX2 = CurTime() + 0.05
        local HP    = self:GetNWInt("HP", 100)
        local MaxHP = self:GetNWInt("MaxHP", 100)
        if HP > MaxHP * 0.45 then return end

        local effectdata = EffectData()
        effectdata:SetOrigin(self:LocalToWorld(Vector(-22, -47, 82)))
        effectdata:SetNormal(self:GetUp())
        effectdata:SetMagnitude(math.Rand(0.5, 1.5))
        effectdata:SetEntity(self)
        util.Effect("lvs_exhaust_fire", effectdata)
    end
end
