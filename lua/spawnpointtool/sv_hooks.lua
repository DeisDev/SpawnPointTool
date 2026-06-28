if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool

cvars.AddChangeCallback("spt_show_all_markers", function()
    timer.Simple(0, function()
        SPT.BroadcastMarkers()
    end)
end, "spt_marker_visibility_sync")

cvars.AddChangeCallback("spt_marker_visibility", function()
    timer.Simple(0, function()
        SPT.BroadcastMarkers()
    end)
end, "spt_marker_mode_sync")

timer.Simple(0, function()
    SPT.UpdateRagModDetectionLog()
end)

hook.Add("PlayerInitialSpawn", "spt_load_saved_spawns", function(ply)
    local key, canPersist = SPT.PlayerKey(ply)

    if key and canPersist and SPT.ApplyLoadedSpawns(ply, SPT.LoadSpawnsFromDisk(key)) then
        SPT.BroadcastMarkers(nil, key)
    end
end)

hook.Add("PlayerDisconnected", "spt_forget_ephemeral_spawn", function(ply)
    local key, canPersist = SPT.PlayerKey(ply)
    if key and not canPersist then
        SPT.PlayerSpawns[key] = nil
        SPT.PlayerNamesByKey[key] = nil
        SPT.RebuildMarkersForKey(key)
        SPT.BroadcastMarkers(nil, key)
    end
end)

hook.Add("PlayerSpawn", "spt_apply_custom_spawn", function(ply, transition)
    if transition then return end
    if not SPT.ConVars.Enabled:GetBool() then return end
    if ply:GetInfoNum("spawnpoint_enabled", SPT.ClientDefaults.Enabled) ~= 1 then return end
    if SPT.ShouldIgnorePlayerSpawn(ply) then return end

    local key, canPersist = SPT.PlayerKey(ply)
    if not key then return end

    local spawns = SPT.PlayerSpawns[key]
    if (not spawns or #spawns == 0) and canPersist then
        spawns = SPT.LoadSpawnsFromDisk(key)
        if SPT.ApplyLoadedSpawns(ply, spawns) then
            SPT.BroadcastMarkers(nil, key)
        end
    end

    if not spawns or #spawns == 0 then return end

    local data = SPT.ChooseRespawnPoint(ply, spawns)
    if not data then return end

    timer.Simple(0, function()
        if not IsValid(ply) or not ply:Alive() then return end

        ply:SetPos(data.pos + data.normal * SPT.GetSpawnOffset())

        local ang = ply:EyeAngles()
        ang.y = data.yaw
        ply:SetEyeAngles(ang)
    end)
end)
