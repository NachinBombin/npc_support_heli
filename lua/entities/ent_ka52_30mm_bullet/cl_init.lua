-- ent_ka52_30mm_bullet / cl_init.lua
-- Client side: tracer beam rendering ported from CW2.0 renderTracerBullets

include("shared.lua")

-- ============================================================
--  TRACER MATERIAL  (CW2.0 exact material definition)
-- ============================================================

local tracerMat = CreateMaterial("ka52_bullet_tracer", "UnlitGeneric", {
    ["$basetexture"] = "sprites/glow03",
    ["$additive"]    = "1",
    ["$vertexcolor"] = "1",
    ["$vertexalpha"] = "1",
})
local TRACER_COLOR = Color(255, 167, 112, 255)  -- CW2.0 warm orange

-- ============================================================
--  LOCAL BULLET TABLE
--  key = server EntIndex, value = { pos, dir, isTracer }
-- ============================================================

local liveBullets = {}

net.Receive("ka52_bullet_tracer", function()
    local pos      = net.ReadVector()
    local dir      = net.ReadVector()
    local isTracer = net.ReadBool()
    local id       = net.ReadUInt(16)
    liveBullets[id] = { pos = pos, dir = dir, isTracer = isTracer }
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
--  RENDER  (CW2.0 renderTracerBullets, ported verbatim)
-- ============================================================

hook.Add("PostDrawOpaqueRenderables", "ka52_bullet_tracers", function()
    local eyePos    = EyePos()
    local eyeFwd    = EyeAngles():Forward():GetNormalized()

    for id, bul in pairs(liveBullets) do
        local pos  = bul.pos
        local norm = bul.dir:GetNormal()

        if bul.isTracer then
            render.SetMaterial(tracerMat)
            render.DrawSprite(pos + norm * 128, 8, 8, TRACER_COLOR)
            render.DrawBeam(pos + norm * 256, pos, 4, 0, 1, TRACER_COLOR)
        end
    end
end)
