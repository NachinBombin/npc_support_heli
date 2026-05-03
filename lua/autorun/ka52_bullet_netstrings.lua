-- ka52_bullet_netstrings.lua
-- Register net strings for ent_ka52_30mm_bullet on both realms.

if SERVER then
    util.AddNetworkString("ka52_bullet_tracer")
    util.AddNetworkString("ka52_bullet_pos")
    util.AddNetworkString("ka52_bullet_remove")
end
