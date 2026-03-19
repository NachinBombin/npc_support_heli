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
end

function ENT:AnimRotor()
    -- Always full RPM, no throttle dependency
    local RPM = 3500

    self.RPM  = self.RPM  + RPM * RealFrameTime() * 0.5
    self.RPM2 = self.RPM2 + RPM * RealFrameTime() * 0.5

    -- Normalize to avoid float overflow over long sessions
    if self.RPM  > 360 then self.RPM  = self.RPM  - 360 end
    if self.RPM2 > 360 then self.RPM2 = self.RPM2 - 360 end

    local Rot1 = Angle(0, self.RPM,  0)
    local Rot2 = Angle(0, self.RPM2, 0)

    -- Bone 11 = lower coaxial disc (CCW), Bone 12 = upper coaxial disc (CW)
    -- Test and adjust bone indices during gameplay if needed
    self:ManipulateBoneAngles(11, -Rot1)
    self:ManipulateBoneAngles(12,  Rot2)
end
