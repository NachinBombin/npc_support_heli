include("shared.lua")

local MAT_GLOW = Material("sprites/light_glow02_add")

--[[
    Bullet smoothness fix:
    The server moves the entity at tick-rate (~66hz), which looks choppy.
    Instead, we record the bullet's spawn state (position, direction, velocity,
    spawn time) from the tracer net message, then extrapolate its position
    client-side every single rendered frame using CurTime().
    This makes the glow sprite move at the full render framerate.
--]]

-- per-entindex spawn data: { pos, dir, vel, t0 }
local _bulletData = {}

-- ============================================================
-- NET
-- ============================================================
net.Receive("ka52_bullet_tracer", function()
    local mpos  = net.ReadVector()
    local dir   = net.ReadVector()
    local isTracer = net.ReadBool()
    local entIdx   = net.ReadUInt(16)

    dir:Normalize()
    _bulletData[entIdx] = {
        pos  = mpos,
        dir  = dir,
        vel  = 25000,   -- must match MUZZLE_VELOCITY in init.lua
        t0   = CurTime(),
    }
end)

net.Receive("ka52_bullet_pos",    function() net.ReadUInt(16) net.ReadVector() net.ReadVector() end)
net.Receive("ka52_bullet_remove", function()
    local idx = net.ReadUInt(16)
    _bulletData[idx] = nil
end)

-- ============================================================
-- RENDER
-- ============================================================
function ENT:Draw()
    -- model not drawn; glow sprite is the full visual
end

function ENT:DrawTranslucent()
    local idx  = self:EntIndex()
    local data = _bulletData[idx]

    local pos
    if data then
        -- extrapolate bullet position this exact frame
        local dt  = CurTime() - data.t0
        -- simple forward travel; gravity droop: ~0.5 * 600 * dt^2 downward
        pos = data.pos
            + data.dir * (data.vel * dt)
            - Vector(0, 0, 0.5 * 600 * dt * dt)
    else
        -- fallback: use networked entity position (tick-rate, but better than nothing)
        pos = self:GetPos()
    end

    render.SetMaterial(MAT_GLOW)
    render.DrawSprite(pos, 120, 120, Color(255, 140, 20, 180))
    render.DrawSprite(pos, 30,  30,  Color(255, 240, 180, 255))
end
