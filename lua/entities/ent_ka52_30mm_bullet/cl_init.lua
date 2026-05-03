-- ent_ka52_30mm_bullet / cl_init.lua
-- DEBUG: tracers removed. Shows bullet via model + bright orange dynamic light.

include("shared.lua")

local liveBullets = {}

net.Receive("ka52_bullet_tracer", function()
    local pos = net.ReadVector()
    local dir = net.ReadVector()
    net.ReadBool()  -- isTracer flag kept for protocol compat, ignored
    local id  = net.ReadUInt(16)
    liveBullets[id] = { pos = pos, dir = dir }
end)

net.Receive("ka52_bullet_pos", function()
    local id  = net.ReadUInt(16)
    local pos = net.ReadVector()
    local dir = net.ReadVector()
    if liveBullets[id] then
        liveBullets[id].pos = pos
        liveBullets[id].dir = dir
    end
end)

net.Receive("ka52_bullet_remove", function()
    local id = net.ReadUInt(16)
    liveBullets[id] = nil
end)

-- ============================================================
--  DYNAMIC LIGHT  — bright light-orange attached to each bullet
-- ============================================================

hook.Add("PreDrawOpaqueRenderables", "ka52_bullet_dlights", function()
    for id, bul in pairs(liveBullets) do
        local dl = DynamicLight(id)
        if dl then
            dl.Pos        = bul.pos
            dl.r          = 255
            dl.g          = 140
            dl.b          = 40
            dl.Brightness = 4
            dl.Size       = 120
            dl.Decay      = 800
            dl.DieTime    = CurTime() + 0.05
        end
    end
end)
