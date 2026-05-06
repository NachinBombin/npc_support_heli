-- Standalone passby sound registration for the KA-52 30mm cannon.
-- Owns all sound.Add aliases and the KA52EmitSound spatial helper.
-- Zero dependency on the RBO addon.
-- Sound files live at sound/rbo/passbys/... (same path as source)

-- ─── Spatial emit helper ─────────────────────────────────────────────────────
-- Plays the sound at EyePos + dir*32 so it is always audible regardless
-- of Source engine attenuation cutoffs, while remaining directional.

function KA52EmitSound(name, pos, level, pitch, volume)
    local view = GetViewEntity()
    if not IsValid(view) then return end
    local eye = view:EyePos()
    local dir = pos - eye
    dir:Normalize()
    sound.Play(
        name,
        eye + dir * 32,
        level  or 80,
        pitch  or 100,
        volume or 1
    )
end

-- ─── sound.Add alias helper ─────────────────────────────────────────────────

local function FastList(name, ext, num)
    local list = {}
    for i = 1, num do
        list[i] = name .. (i < 10 and "0" .. i or i) .. "." .. ext
    end
    return list
end

-- ─── .50 cal passby aliases (best acoustic match for 30mm) ───────────────────
-- Prefixed ka52_ to avoid collisions if multiple addons are loaded.

sound.Add({
    name    = "ka52_passby_50_close",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_close_", "ogg", 12)
})

sound.Add({
    name    = "ka52_passby_50_medium",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_mid_", "ogg", 12)
})

sound.Add({
    name    = "ka52_passby_50_medium_2",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_mid_new_", "ogg", 17)
})

sound.Add({
    name    = "ka52_passby_50_far",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_far_", "ogg", 8)
})

sound.Add({
    name    = "ka52_passby_50_far_2",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/50cal/crack_50cal_far_new_", "ogg", 19)
})

sound.Add({
    name    = "ka52_passby_hiss_far",
    channel = CHAN_STATIC,
    volume  = 1,
    level   = 80,
    pitch   = 100,
    sound   = FastList("rbo/passbys/squad/hiss/passby_crack_hiss_far_", "ogg", 29)
})
