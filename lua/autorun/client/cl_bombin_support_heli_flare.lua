if not CLIENT then return end

local activeFlares = {}

net.Receive("BombinSupportHeli_FlareSpawned", function()
    local flare = net.ReadEntity()
    if IsValid(flare) then
        activeFlares[flare:EntIndex()] = flare
    end
end)

hook.Add("Think", "BombinSupportHeli_FlareLight", function()
    for idx, flare in pairs(activeFlares) do
        if not IsValid(flare) then
            activeFlares[idx] = nil
            continue
        end

        local dlight = DynamicLight(flare:EntIndex())
        if dlight then
            dlight.Pos        = flare:GetPos()
            dlight.r          = 0
            dlight.g          = 80
            dlight.b          = 255
            dlight.Brightness = (math.random() > 0.4) and math.Rand(4.0, 6.0) or math.Rand(0.0, 0.2)
            dlight.Size       = 55
            dlight.Decay      = 3000
            dlight.DieTime    = CurTime() + 0.05
        end
    end
end)
