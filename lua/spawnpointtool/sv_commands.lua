if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool

local function clearPlayerSpawnsByKey(key)
    SPT.PlayerSpawns[key] = nil
    SPT.PlayerNamesByKey[key] = nil
    SPT.RebuildMarkersForKey(key)
    SPT.DeleteSpawnFromDisk(key)
    SPT.BroadcastMarkers(nil, key)
end

concommand.Add("spt_list_counts", function(ply)
    if not SPT.CanRunAdminCommand(ply) then return end

    local rows = {}
    for key, spawns in pairs(SPT.PlayerSpawns) do
        rows[#rows + 1] = string.format("%s: %d", SPT.PlayerNamesByKey[key] or key, #(spawns or {}))
    end

    if #rows == 0 then
        SPT.AdminPrint(ply, "No loaded respawn points.")
        return
    end

    SPT.AdminPrint(ply, "Loaded respawn points: " .. table.concat(rows, ", "))
end, nil, "List loaded Spawn Point Tool respawn point counts.")

concommand.Add("spt_clear_player", function(ply, _, args)
    if not SPT.CanRunAdminCommand(ply) then return end

    local targetText = table.concat(args or {}, " ")
    local target = SPT.FindPlayerByText(targetText)
    if not IsValid(target) then
        SPT.AdminPrint(ply, "Player not found.")
        return
    end

    local key = SPT.PlayerKey(target)
    if not key then
        SPT.AdminPrint(ply, "Could not identify player.")
        return
    end

    clearPlayerSpawnsByKey(key)
    SPT.AdminPrint(ply, "Cleared respawn points for " .. target:Nick() .. ".")
end, nil, "Clear a player's Spawn Point Tool respawn points on this map.")
