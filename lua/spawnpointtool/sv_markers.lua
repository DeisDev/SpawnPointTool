if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool

SPT.PlayerSpawns = SPT.PlayerSpawns or {}
SPT.GlobalSpawns = SPT.GlobalSpawns or {}
SPT.MarkersByKey = SPT.MarkersByKey or {}
SPT.PlayerNamesByKey = SPT.PlayerNamesByKey or {}

local function rebuildMarkersForSpawns(key, spawns, global)
    if not spawns or #spawns == 0 then
        SPT.MarkersByKey[key] = nil
        return
    end

    local markers = {}
    for i = 1, #spawns do
        markers[i] = {
            pos = spawns[i].pos,
            normal = spawns[i].normal,
            yaw = spawns[i].yaw,
            index = i,
            global = global == true
        }
    end

    SPT.MarkersByKey[key] = markers
end

function SPT.RebuildMarkersForKey(key)
    rebuildMarkersForSpawns(key, SPT.PlayerSpawns[key], false)
end

function SPT.RebuildGlobalMarkers()
    rebuildMarkersForSpawns(SPT.GlobalSpawnKey, SPT.GlobalSpawns, true)
end

function SPT.GetMarkerCountForKey(key)
    local markers = SPT.MarkersByKey[key]
    return markers and #markers or 0
end

function SPT.GetAllMarkerCount()
    local count = 0

    for _, markers in pairs(SPT.MarkersByKey) do
        count = count + #markers
    end

    return count
end

local function writeSafeString(text, maxLen)
    net.WriteString(string.sub(tostring(text or ""), 1, maxLen))
end

local function writeMarker(marker, own, ownerName)
    net.WriteVector(marker.pos)
    net.WriteNormal(SPT.SanitizeNormal(marker.normal))
    net.WriteBool(own)
    net.WriteBool(marker.global == true)
    net.WriteInt(math.Clamp(math.Round(SPT.SanitizeYaw(marker.yaw)), -180, 180), 10)
    net.WriteUInt(math.Clamp(marker.index or 1, 1, 65535), 16)
    writeSafeString(marker.global and "Global" or ownerName or "Player", 64)
end

function SPT.WriteMarkersForPlayer(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return end

    local key = SPT.PlayerKey(ply)
    local visibility = SPT.GetMarkerVisibility()
    local includeAll = visibility == SPT.MarkerVisibility.Everyone or (visibility == SPT.MarkerVisibility.Admins and ply:IsAdmin())
    local includeGlobal = includeAll or (ply:IsAdmin() and SPT.IsGlobalModeEnabled and SPT.IsGlobalModeEnabled(ply))
    local count = includeAll and SPT.GetAllMarkerCount() or SPT.GetMarkerCountForKey(key)

    if includeGlobal and not includeAll then
        count = count + SPT.GetMarkerCountForKey(SPT.GlobalSpawnKey)
    end

    net.Start(SPT.Net.SyncMarkers)
    net.WriteUInt(math.min(count, 65535), 16)

    local written = 0
    if includeAll then
        for markerKey, markers in pairs(SPT.MarkersByKey) do
            local own = markerKey == key
            local ownerName = SPT.PlayerNamesByKey[markerKey] or "Player"

            for i = 1, #markers do
                written = written + 1
                if written > 65535 then break end
                writeMarker(markers[i], own, ownerName)
            end

            if written > 65535 then break end
        end
    else
        local markers = SPT.MarkersByKey[key]
        for i = 1, #(markers or {}) do
            written = written + 1
            if written > 65535 then break end
            writeMarker(markers[i], true, SPT.PlayerNamesByKey[key] or ply:Nick())
        end

        if includeGlobal then
            local globalMarkers = SPT.MarkersByKey[SPT.GlobalSpawnKey]
            for i = 1, #(globalMarkers or {}) do
                written = written + 1
                if written > 65535 then break end
                writeMarker(globalMarkers[i], false, "Global")
            end
        end
    end

    net.Send(ply)
end

function SPT.IsUsingSpawnTool(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "gmod_tool" then return false end

    return ply:GetInfo("gmod_toolmode") == "spawnpoint"
end

function SPT.WantsMarkers(ply)
    return SPT.IsUsingSpawnTool(ply) or ply:GetInfoNum("spawnpoint_always_show", 0) == 1
end

function SPT.BroadcastMarkers(toPly, changedKey)
    if IsValid(toPly) then
        SPT.WriteMarkersForPlayer(toPly)
        return
    end

    if SPT.GetMarkerVisibility() == SPT.MarkerVisibility.OwnOnly and changedKey then
        for _, ply in ipairs(player.GetHumans()) do
            if SPT.PlayerKey(ply) == changedKey and SPT.WantsMarkers(ply) then
                SPT.WriteMarkersForPlayer(ply)
                return
            end
        end

        return
    end

    for _, target in ipairs(player.GetHumans()) do
        if SPT.WantsMarkers(target) then
            SPT.WriteMarkersForPlayer(target)
        end
    end
end

function SPT.SyncOwnerChange(ply, key)
    if SPT.GetMarkerVisibility() > SPT.MarkerVisibility.OwnOnly then
        SPT.BroadcastMarkers(nil, key)
    else
        SPT.BroadcastMarkers(ply)
    end
end

function SPT.SyncGlobalChange()
    SPT.BroadcastMarkers()
end

SPT.RebuildGlobalMarkers()
