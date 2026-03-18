if not CLIENT then return end

-- ============================================================
-- SPAWNLIST
-- ============================================================

hook.Add("PopulateContent", "BombinSupportHeli_SpawnMenu", function(pnlContent, tree, node)
    local node = tree:AddNode("Bombin Support", "icon16/bomb.png")

    node:MakePopulator(function(pnlContent)
        local helisection = vgui.Create("ContentIcon", pnlContent)
        helisection:SetContentType("entity")
        helisection:SetSpawnName("ent_bombin_support_heli")
        helisection:SetName("Support Helicopter")
        helisection:SetMaterial("entities/ent_bombin_support_heli.png")
        helisection:SetToolTip("Autonomous KA-50 support helicopter.\nOrbits the target area and engages with 30mm cannon, S-8 rockets and Vikhr ATGMs.")
        pnlContent:Add(helisection)
    end)
end)

-- ============================================================
-- CONSOLE COMMAND — manual test spawn
-- ============================================================

concommand.Add("bombin_spawnheli", function(ply, cmd, args)
    if not IsValid(LocalPlayer()) then return end
    net.Start("BombinSupportHeli_ManualSpawn")
    net.SendToServer()
end)

-- ============================================================
-- TOOL TAB
-- ============================================================

hook.Add("AddToolMenuTabs", "BombinSupportHeli_Tab", function()
    spawnmenu.AddToolTab("Bombin Support", "Bombin Support", "icon16/bomb.png")
end)

hook.Add("AddToolMenuCategories", "BombinSupportHeli_Categories", function()
    spawnmenu.AddToolCategory("Bombin Support", "Support Helicopter", "Support Helicopter")
end)

hook.Add("PopulateToolMenu", "BombinSupportHeli_ToolMenu", function()
    spawnmenu.AddToolMenuOption("Bombin Support", "Support Helicopter", "bombin_support_heli_settings", "KA-50 Settings", "", "", function(panel)
        panel:ClearControls()
        panel:Help("NPC Call Settings")

        panel:CheckBox("Enable NPC calls", "npc_bombinheli_enabled")

        panel:NumSlider("Call chance (per check)",     "npc_bombinheli_chance",   0, 1,    2)
        panel:NumSlider("Check interval (seconds)",   "npc_bombinheli_interval", 1, 60,   0)
        panel:NumSlider("NPC cooldown (seconds)",     "npc_bombinheli_cooldown", 10, 300, 0)
        panel:NumSlider("Min call distance (HU)",     "npc_bombinheli_min_dist", 100, 1000, 0)
        panel:NumSlider("Max call distance (HU)",     "npc_bombinheli_max_dist", 500, 8000, 0)
        panel:NumSlider("Flare to arrival delay (s)", "npc_bombinheli_delay",    1,  30,   0)

        panel:Help("Helicopter Behaviour")
        panel:NumSlider("Lifetime (seconds)",         "npc_bombinheli_lifetime", 10, 120,  0)
        panel:NumSlider("Forward speed (HU/s)",       "npc_bombinheli_speed",    50, 800,  0)
        panel:NumSlider("Orbit radius (HU)",          "npc_bombinheli_radius",   500, 6000, 0)
        panel:NumSlider("Altitude above ground (HU)", "npc_bombinheli_height",   500, 8000, 0)

        panel:Help("Debug")
        panel:CheckBox("Enable debug prints", "npc_bombinheli_announce")

        panel:Help("Manual spawn (for testing)")
        panel:Button("Spawn support helicopter now", "bombin_spawnheli")
    end)
end)
