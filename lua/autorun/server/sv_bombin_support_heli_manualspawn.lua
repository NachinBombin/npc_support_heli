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

    heli:SetPos(centerPos)
    heli:SetAngles(callDir:Angle())
    heli:SetVar("CenterPos",    centerPos)
    heli:SetVar("CallDir",      callDir)
    heli:SetVar("Lifetime",     GetConVar("npc_bombinheli_lifetime"):GetFloat())
    heli:SetVar("Speed",        GetConVar("npc_bombinheli_speed"):GetFloat())
    heli:SetVar("OrbitRadius",  GetConVar("npc_bombinheli_radius"):GetFloat())
    heli:SetVar("SkyHeightAdd", GetConVar("npc_bombinheli_height"):GetFloat())
    heli:Spawn()
    heli:Activate()

    ply:PrintMessage(HUD_PRINTCENTER, "[Bombin Heli] Support helicopter inbound!")
end)
