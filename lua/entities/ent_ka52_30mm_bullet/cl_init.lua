-- ent_ka52_30mm_bullet / cl_init.lua
-- Model renders via ENT:Draw() at the entity's real interpolated position.
-- DynamicLight follows the entity directly -- no net lag.

include("shared.lua")

-- Still receive net messages so ka52_bullet_remove cleans up liveBullets
-- used by any future tracer work, and to stay protocol-compatible.
local liveBullets = {}

net.Receive("ka52_bullet_tracer", function()
    net.ReadVector() net.ReadVector() net.ReadBool()
    local id = net.ReadUInt(16)
    liveBullets[id] = true
end)

net.Receive("ka52_bullet_pos", function()
    net.ReadUInt(16) net.ReadVector() net.ReadVector()
end)

net.Receive("ka52_bullet_remove", function()
    liveBullets[net.ReadUInt(16)] = nil
end)

-- ============================================================
--  DRAW  -- called every frame by the engine at the entity's
--  interpolated world position. No manual position tracking needed.
-- ============================================================

function ENT:Draw()
    self:DrawModel()
end

-- ============================================================
--  DYNAMIC LIGHT  -- follows the actual entity, not a net buffer
-- ============================================================

function ENT:DrawTranslucent()
    -- DynamicLight index must be unique per entity
    local dl = DynamicLight(self:EntIndex())
    if dl then
        dl.Pos        = self:GetPos()
        dl.r          = 255
        dl.g          = 140
        dl.b          = 40
        dl.Brightness = 4
        dl.Size       = 120
        dl.Decay      = 1200
        dl.DieTime    = CurTime() + 0.05
    end
end
