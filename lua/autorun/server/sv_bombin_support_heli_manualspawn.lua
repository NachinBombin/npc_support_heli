if not SERVER then return end

net.Receive("BombinSupportHeli_ManualSpawn", function(len, ply)
    if not IsValid(ply) then return end

    local tr = util.TraceLine({
        start  = ply:EyePos(),
        endpos = ply:EyePos() + ply:EyeAngles():Forward() * 3000,
        filter = ply,
    })

    local centerPos = tr.Hit and tr.HitPos or (ply:GetPos() + Vector(0, 0, 100))
    local callDir   = ply:EyeAngles():Forward()
    callDir.z = 0
    if callDir:LengthSqr() <= 1 then callDir = Vector(1, 0, 0) end
    callDir:Normalize()

    if not scripted_ents.GetStored("ent_bombin_support_heli") then
        ply:PrintMessage(HUD_PRINTCENTER, "[Bombin Heli] Entity not registered!")
        return
    end

    local heli = ents.Create("ent_bombin_support_heli")
    if not IsValid(heli) then
        ply:PrintMessage(HUD_PRINTCENTER, "[Bombin Heli] Spawn failed!")
        return
    end

    -- NWVars must be set BEFORE Spawn() so Initialize() can read them
    heli:SetNWVector("BH_CenterPos",    centerPos)
    heli:SetNWVector("BH_CallDir",      callDir)
    heli:SetNWFloat( "BH_Lifetime",     GetConVar("npc_bombinheli_lifetime"):GetFloat())
    heli:SetNWFloat( "BH_Speed",        GetConVar("npc_bombinheli_speed"):GetFloat())
    heli:SetNWFloat( "BH_OrbitRadius",  GetConVar("npc_bombinheli_radius"):GetFloat())
    heli:SetNWFloat( "BH_SkyHeightAdd", GetConVar("npc_bombinheli_height"):GetFloat())

    heli:SetPos(centerPos)
    heli:SetAngles(callDir:Angle())
    heli:Spawn()
    heli:Activate()

    ply:PrintMessage(HUD_PRINTCENTER, "[Bombin Heli] Support helicopter inbound!")
end)
