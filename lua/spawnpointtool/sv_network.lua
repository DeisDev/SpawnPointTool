if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool
local cooldowns = {}

util.AddNetworkString(SPT.Net.SyncMarkers)
util.AddNetworkString(SPT.Net.RequestMarkers)
util.AddNetworkString(SPT.Net.ClearCurrentRequest)
util.AddNetworkString(SPT.Net.ClearAllRequest)
util.AddNetworkString(SPT.Net.AdminSetting)
util.AddNetworkString(SPT.Net.PersistChanged)

local function consumeCooldown(ply, name, delay)
    local key = SPT.PlayerKey(ply)
    if not key then return false end

    cooldowns[key] = cooldowns[key] or {}

    local now = CurTime()
    if cooldowns[key][name] and cooldowns[key][name] > now then return false end

    cooldowns[key][name] = now + delay
    return true
end

local function boolString(value)
    return value >= 1 and "1" or "0"
end

local function intString(value, minValue, maxValue)
    return tostring(math.Clamp(math.floor(value), minValue, maxValue))
end

local function numberString(value, minValue, maxValue)
    return tostring(math.Clamp(value, minValue, maxValue))
end

local function applyAdminSetting(id, value)
    local setting = SPT.AdminSetting

    if id == setting.Enabled then
        RunConsoleCommand("spt_enabled", boolString(value))
    elseif id == setting.MarkerVisibility then
        RunConsoleCommand("spt_marker_visibility", intString(value, SPT.MarkerVisibility.OwnOnly, SPT.MarkerVisibility.Everyone))
        RunConsoleCommand("spt_show_all_markers", "0")
        SPT.BroadcastMarkers()
    elseif id == setting.MaxSpawns then
        RunConsoleCommand("spt_max_spawns", intString(value, 1, 128))
    elseif id == setting.DeleteRadius then
        RunConsoleCommand("spt_delete_radius", numberString(value, 16, 256))
    elseif id == setting.SpawnOffset then
        RunConsoleCommand("spt_spawn_offset", numberString(value, 0, 32))
    elseif id == setting.DangerCheck then
        RunConsoleCommand("spt_danger_check", boolString(value))
    elseif id == setting.DangerRadius then
        RunConsoleCommand("spt_danger_radius", intString(value, 128, 2048))
    elseif id == setting.RespawnHullCheck then
        RunConsoleCommand("spt_respawn_hull_check", boolString(value))
    elseif id == setting.ResetDefaults then
        SPT.ResetServerConVars()
        SPT.BroadcastMarkers()
    end
end

net.Receive(SPT.Net.ClearCurrentRequest, function(_, ply)
    if not consumeCooldown(ply, "clear_current", 2) then return end

    local ok, message = SPT.ClearSpawn(ply)
    if ok and message then
        ply:ChatPrint(message)
    end
end)

net.Receive(SPT.Net.ClearAllRequest, function(_, ply)
    if not consumeCooldown(ply, "clear_all", 2) then return end

    local ok, message = SPT.ClearAllSpawns(ply)
    if ok and message then
        ply:ChatPrint(message)
    end
end)

net.Receive(SPT.Net.RequestMarkers, function(_, ply)
    if not consumeCooldown(ply, "request_markers", 0.25) then return end
    if not SPT.WantsMarkers(ply) then return end
    SPT.WriteMarkersForPlayer(ply)
end)

net.Receive(SPT.Net.PersistChanged, function(len, ply)
    if len > 8 then return end
    if not IsValid(ply) then return end
    SPT.SetPersistenceMode(ply, net.ReadBool())
end)

net.Receive(SPT.Net.AdminSetting, function(len, ply)
    if len > 64 then return end
    if not IsValid(ply) or not ply:IsAdmin() then return end
    if not consumeCooldown(ply, "admin_setting", 0.05) then return end

    local id = net.ReadUInt(5)
    local value = net.ReadFloat()
    if not SPT.IsFiniteNumber(value) then return end

    applyAdminSetting(id, value)
end)

hook.Add("PlayerDisconnected", "spt_clear_net_cooldowns", function(ply)
    local key = SPT.PlayerKey(ply)
    if key then
        cooldowns[key] = nil
    end
end)
