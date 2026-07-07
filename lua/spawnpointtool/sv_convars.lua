if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool
local defaults = SPT.ServerDefaults

SPT.ConVars = {
    Enabled = CreateConVar("spt_enabled", tostring(defaults.Enabled), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Enable custom respawns from Spawn Point Tool."),
    ShowAllMarkers = CreateConVar("spt_show_all_markers", tostring(defaults.ShowAllMarkers), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Legacy marker visibility override. Prefer spt_marker_visibility."),
    MarkerVisibility = CreateConVar("spt_marker_visibility", tostring(defaults.MarkerVisibility), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Marker visibility: 0 = own only, 1 = admins see all, 2 = everyone sees all.", 0, 2),
    MaxSpawns = CreateConVar("spt_max_spawns", tostring(defaults.MaxSpawns), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Maximum respawn points per player or global set.", 1, 128),
    DeleteRadius = CreateConVar("spt_delete_radius", tostring(defaults.DeleteRadius), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Aimed removal radius for respawn points.", 16, 256),
    SpawnOffset = CreateConVar("spt_spawn_offset", tostring(defaults.SpawnOffset), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Distance to move players away from the saved surface normal.", 0, 32),
    DangerCheck = CreateConVar("spt_danger_check", tostring(defaults.DangerCheck), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Prefer respawn points without nearby NPCs or NextBots."),
    DangerRadius = CreateConVar("spt_danger_radius", tostring(defaults.DangerRadius), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Radius used for respawn point danger checks.", 128, 2048),
    RespawnHullCheck = CreateConVar("spt_respawn_hull_check", tostring(defaults.RespawnHullCheck), { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Check player hull again before using a respawn point.")
}

function SPT.GetMaxSpawns()
    return math.Clamp(SPT.ConVars.MaxSpawns:GetInt(), 1, 128)
end

function SPT.GetDeleteRadiusSqr()
    return math.Clamp(SPT.ConVars.DeleteRadius:GetFloat(), 16, 256) ^ 2
end

function SPT.GetSpawnOffset()
    return math.Clamp(SPT.ConVars.SpawnOffset:GetFloat(), 0, 32)
end

function SPT.GetDangerRadius()
    return math.Clamp(SPT.ConVars.DangerRadius:GetFloat(), 128, 2048)
end

function SPT.GetMarkerVisibility()
    if SPT.ConVars.ShowAllMarkers:GetBool() then return SPT.MarkerVisibility.Everyone end
    return math.Clamp(SPT.ConVars.MarkerVisibility:GetInt(), SPT.MarkerVisibility.OwnOnly, SPT.MarkerVisibility.Everyone)
end

function SPT.ResetServerConVars()
    RunConsoleCommand("spt_enabled", tostring(defaults.Enabled))
    RunConsoleCommand("spt_show_all_markers", tostring(defaults.ShowAllMarkers))
    RunConsoleCommand("spt_marker_visibility", tostring(defaults.MarkerVisibility))
    RunConsoleCommand("spt_max_spawns", tostring(defaults.MaxSpawns))
    RunConsoleCommand("spt_delete_radius", tostring(defaults.DeleteRadius))
    RunConsoleCommand("spt_spawn_offset", tostring(defaults.SpawnOffset))
    RunConsoleCommand("spt_danger_check", tostring(defaults.DangerCheck))
    RunConsoleCommand("spt_danger_radius", tostring(defaults.DangerRadius))
    RunConsoleCommand("spt_respawn_hull_check", tostring(defaults.RespawnHullCheck))
end
