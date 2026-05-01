-- ============================================================
-- TRAIL SYSTEM  --  ent_bombin_support_heli (KA-50)
-- Always active from spawn. All emission points run at all times.
-- Tier drives color + size: white vapor -> dark black smoke.
-- Uses unique hook/function names to avoid collision with an-71.
-- ============================================================

local TRAIL_MATERIAL = Material( "trails/smoke" )

local SAMPLE_RATE = 0.025  -- seconds between position samples (40fps)

-- ============================================================
-- EMISSION POINTS  (model-local offsets for KA-50)
-- Tune X/Y/Z to match the ka50.mdl mesh if needed.
-- ============================================================
local TRAIL_POSITIONS = {
    Vector(  28, -25, 52 ),   -- right engine exhaust (top rear)
    Vector( -28, -25, 52 ),   -- left engine exhaust  (top rear)
    Vector(   0, -155, 18 ),  -- tail boom tip
    Vector(   0,   0,  28 ),  -- belly / center mass (visible from ground)
}

-- ============================================================
-- TIER CONFIG  (all 4 points share the same tier simultaneously)
-- Tier 0 = 100% HP  →  white vapor, always visible.
-- Tier 3 = dead     →  dense black smoke.
-- ============================================================
local TIER_CONFIG = {
    [0] = { r = 255, g = 255, b = 255, a = 105, startSize = 18, endSize =  3, lifetime = 4 },
    [1] = { r = 160, g = 160, b = 160, a = 145, startSize = 28, endSize =  6, lifetime = 5 },
    [2] = { r =  50, g =  50, b =  50, a = 190, startSize = 44, endSize = 12, lifetime = 6 },
    [3] = { r =  10, g =  10, b =  10, a = 220, startSize = 60, endSize = 18, lifetime = 8 },
}

-- State table keyed by entIndex
local HeliTrails = {}

-- ============================================================
-- PUBLIC: called from net.Receive in cl_init.lua
-- Different name from an-71's TrailSystem_SetTier.
-- ============================================================
function HeliTrailSystem_SetTier( entIndex, tier )
    local state = HeliTrails[entIndex]
    if not state then return end
    state.tier = tier
end

-- ============================================================
-- INTERNALS
-- ============================================================
local function EnsureRegistered( entIndex )
    if HeliTrails[entIndex] then return end
    local trails = {}
    for i = 1, #TRAIL_POSITIONS do
        trails[i] = { positions = {} }
    end
    HeliTrails[entIndex] = {
        tier       = 0,
        nextSample = 0,
        trails     = trails,
    }
end

local function DrawBeam( positions, cfg )
    local n = #positions
    if n < 2 then return end

    local Time = CurTime()
    local lt   = cfg.lifetime

    -- Prune expired positions
    for i = n, 1, -1 do
        if Time - positions[i].time > lt then
            table.remove( positions, i )
        end
    end

    n = #positions
    if n < 2 then return end

    render.SetMaterial( TRAIL_MATERIAL )
    render.StartBeam( n )
    for _, pd in ipairs( positions ) do
        local Scale = math.Clamp( (pd.time + lt - Time) / lt, 0, 1 )
        local size  = cfg.startSize * Scale + cfg.endSize * (1 - Scale)
        render.AddBeam( pd.pos, size, pd.time * 50,
            Color( cfg.r, cfg.g, cfg.b, cfg.a * Scale * Scale ) )
    end
    render.EndBeam()
end

-- ============================================================
-- THINK: sample world positions for every emission point
-- ============================================================
hook.Add( "Think", "bombin_heli_trails_update", function()
    local Time = CurTime()

    -- Auto-discover new heli entities
    for _, ent in ipairs( ents.FindByClass( "ent_bombin_support_heli" ) ) do
        EnsureRegistered( ent:EntIndex() )
    end

    for entIndex, state in pairs( HeliTrails ) do
        local ent = Entity( entIndex )
        if not IsValid( ent ) then
            HeliTrails[entIndex] = nil
            continue
        end

        if Time < state.nextSample then continue end
        state.nextSample = Time + SAMPLE_RATE

        local pos = ent:GetPos()
        local ang = ent:GetAngles()

        for i, trail in ipairs( state.trails ) do
            local wpos = LocalToWorld( TRAIL_POSITIONS[i], Angle(0,0,0), pos, ang )
            table.insert( trail.positions, { time = Time, pos = wpos } )
            table.sort( trail.positions, function( a, b ) return a.time > b.time end )
        end
    end
end )

-- ============================================================
-- DRAW: render beams using current tier config
-- ============================================================
hook.Add( "PostDrawTranslucentRenderables", "bombin_heli_trails_draw", function( bDepth, bSkybox )
    if bSkybox then return end

    for _, state in pairs( HeliTrails ) do
        local cfg = TIER_CONFIG[ state.tier ] or TIER_CONFIG[0]
        for _, trail in ipairs( state.trails ) do
            DrawBeam( trail.positions, cfg )
        end
    end
end )
