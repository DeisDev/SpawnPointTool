if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool
local lastRagModDetected

local function log(message)
    local developer = GetConVar("developer")
    if not developer or developer:GetInt() < 1 then return end
    print("[Spawn Point Tool] " .. message)
end

local function isRagModDetected()
    if istable(ragmod) and isfunction(ragmod.IsRagdoll) and isfunction(ragmod.UnPossessRagdoll) then
        return true
    end

    local hooks = hook.GetTable()
    local spawnHooks = hooks and hooks.PlayerSpawn
    return istable(spawnHooks) and (spawnHooks.ragmod_PlayerSpawn or spawnHooks.ragmod_PlayerSpawnLoadout) ~= nil
end

function SPT.UpdateRagModDetectionLog()
    local detected = isRagModDetected()
    if lastRagModDetected == detected then return detected end

    lastRagModDetected = detected
    if detected then
        log("RagMod detected. Compatibility guard enabled.")
    else
        log("RagMod not detected. Compatibility guard disabled.")
    end

    return detected
end

function SPT.ApplyLoadedSpawns(ply, spawns)
    local key = SPT.PlayerKey(ply)
    if not key or not spawns or #spawns == 0 then return false end

    SPT.PlayerNamesByKey[key] = ply:Nick()
    SPT.PlayerSpawns[key] = SPT.SanitizeSpawnArray(spawns)
    SPT.RebuildMarkersForKey(key)
    return #SPT.PlayerSpawns[key] > 0
end

local function shouldValidateHull(ply)
    return ply:GetInfoNum("spawnpoint_hull_check", SPT.ClientDefaults.HullCheck) == 1
end

function SPT.IsGlobalModeEnabled(ply)
    if not IsValid(ply) or not ply:IsPlayer() or not ply:IsAdmin() then return false end
    return ply:GetInfoNum("spawnpoint_global_mode", SPT.ClientDefaults.GlobalMode) == 1
end

function SPT.IsSpawnHullClear(ply, pos, normal)
    local startPos = pos + normal * SPT.GetSpawnOffset()
    local tr = util.TraceHull({
        start = startPos,
        endpos = startPos,
        mins = SPT.HULL_MINS,
        maxs = SPT.HULL_MAXS,
        filter = ply,
        mask = MASK_PLAYERSOLID
    })

    return not tr.StartSolid and not tr.AllSolid and tr.Fraction == 1
end

local function isRespawnPointClear(ply, spawn)
    if not SPT.ConVars.RespawnHullCheck:GetBool() then return true end
    return SPT.IsSpawnHullClear(ply, spawn.pos, spawn.normal)
end

local function isDangerEntity(ent)
    if not IsValid(ent) then return false end
    if ent:IsNPC() then return true end
    if ent.IsNextBot and ent:IsNextBot() then return true end
    return false
end

local function isSpawnDangerous(pos)
    local radius = SPT.GetDangerRadius()
    local entsInRange = ents.FindInSphere(pos, radius)

    for i = 1, #entsInRange do
        if isDangerEntity(entsInRange[i]) then
            return true
        end
    end

    return false
end

function SPT.ChooseRespawnPoint(ply, spawns)
    local usableSpawns = {}
    for i = 1, #spawns do
        if isRespawnPointClear(ply, spawns[i]) then
            usableSpawns[#usableSpawns + 1] = spawns[i]
        end
    end

    if #usableSpawns == 0 then return nil end

    if #usableSpawns <= 1 or not SPT.ConVars.DangerCheck:GetBool() then
        return SPT.CopySpawn(usableSpawns[math.random(#usableSpawns)])
    end

    local safeSpawns = {}
    for i = 1, #usableSpawns do
        if not isSpawnDangerous(usableSpawns[i].pos + usableSpawns[i].normal * SPT.GetSpawnOffset()) then
            safeSpawns[#safeSpawns + 1] = usableSpawns[i]
        end
    end

    if #safeSpawns > 0 then
        return SPT.CopySpawn(safeSpawns[math.random(#safeSpawns)])
    end

    return SPT.CopySpawn(usableSpawns[math.random(#usableSpawns)])
end

function SPT.ShouldIgnorePlayerSpawn(ply)
    if not SPT.UpdateRagModDetectionLog() then return false end

    if ply.Ragmod_RestoreInventory then
        log("RagMod compatibility blocked custom respawn during get-up for " .. ply:Nick() .. ".")
        return true
    end

    if ply.Ragmod_PropagateDeath then
        log("RagMod compatibility skipped internal propagated-death spawn for " .. ply:Nick() .. ".")
        return true
    end

    return false
end

local function persistIfNeeded(ply, key)
    local _, canPersist = SPT.PlayerKey(ply)
    if canPersist and ply:GetInfoNum("spawnpoint_persist", SPT.ClientDefaults.Persist) == 1 then
        SPT.SaveSpawnsToDisk(key, SPT.PlayerSpawns[key] or {})
    else
        SPT.DeleteSpawnFromDisk(key)
    end
end

local function makeSpawnData(ply, pos, normal, eyeAng)
    pos = SPT.SanitizeVector(pos, nil)
    if not pos then return nil, "Invalid spawn position." end

    normal = SPT.SanitizeNormal(normal)

    if shouldValidateHull(ply) and not SPT.IsSpawnHullClear(ply, pos, normal) then
        return nil, "Spawn point blocked.", "blocked"
    end

    local yaw = ply:EyeAngles().y
    if eyeAng and SPT.IsFiniteNumber(eyeAng.y) then
        yaw = eyeAng.y
    end

    return {
        pos = pos,
        normal = normal,
        yaw = SPT.SanitizeYaw(yaw)
    }
end

local function findNearestSpawnIndex(spawns, pos)
    local bestIndex
    local bestDist = SPT.GetDeleteRadiusSqr()

    if SPT.SanitizeVector(pos, nil) then
        for i = 1, #spawns do
            local dist = spawns[i].pos:DistToSqr(pos)
            if dist <= bestDist then
                bestDist = dist
                bestIndex = i
            end
        end
    end

    if not bestIndex and #spawns == 1 then
        bestIndex = 1
    end

    return bestIndex
end

function SPT.SetPersistenceMode(ply, enabled)
    local key, canPersist = SPT.PlayerKey(ply)
    if not key or not canPersist then return false end

    if enabled then
        SPT.SaveSpawnsToDisk(key, SPT.PlayerSpawns[key] or {})
    else
        SPT.DeleteSpawnFromDisk(key)
    end

    return true
end

function SPT.SetSpawn(ply, pos, normal, eyeAng)
    local key = SPT.PlayerKey(ply)
    if not key then return false, "Invalid player." end
    SPT.PlayerNamesByKey[key] = ply:Nick()

    local spawn, message, reason = makeSpawnData(ply, pos, normal, eyeAng)
    if not spawn then return false, message, reason end

    local spawns = SPT.PlayerSpawns[key] or {}
    local limit = SPT.GetMaxSpawns()
    if #spawns >= limit then
        return false, string.format("Spawn point limit reached (%d).", limit), "limit"
    end

    spawns[#spawns + 1] = {
        pos = spawn.pos,
        normal = spawn.normal,
        yaw = spawn.yaw
    }

    SPT.PlayerSpawns[key] = spawns
    SPT.RebuildMarkersForKey(key)
    persistIfNeeded(ply, key)
    SPT.SyncOwnerChange(ply, key)

    return true, string.format("Spawn point added (%d/%d).", #spawns, limit)
end

function SPT.RemoveNearestSpawn(ply, pos)
    local key = SPT.PlayerKey(ply)
    if not key then return false, "Invalid player." end

    local spawns = SPT.PlayerSpawns[key]
    if not spawns or #spawns == 0 then return false, "No respawn points to remove." end

    local bestIndex = findNearestSpawnIndex(spawns, pos)
    if not bestIndex then
        return false, "Aim closer to one of your respawn points to remove it."
    end

    table.remove(spawns, bestIndex)

    if #spawns == 0 then
        SPT.PlayerSpawns[key] = nil
        SPT.PlayerNamesByKey[key] = nil
    end

    SPT.RebuildMarkersForKey(key)
    persistIfNeeded(ply, key)
    SPT.SyncOwnerChange(ply, key)

    return true, string.format("Spawn point removed (%d remaining).", #spawns)
end

function SPT.ClearSpawn(ply)
    local key = SPT.PlayerKey(ply)
    if not key then return false, "Invalid player." end

    SPT.PlayerSpawns[key] = nil
    SPT.PlayerNamesByKey[key] = nil
    SPT.RebuildMarkersForKey(key)
    SPT.DeleteSpawnFromDisk(key)
    SPT.SyncOwnerChange(ply, key)

    return true, "All respawn points removed for this gamemode and map."
end

function SPT.ClearAllSpawns(ply)
    local key = SPT.PlayerKey(ply)
    if not key then return false, "Invalid player." end

    SPT.ClearSpawn(ply)
    SPT.DeleteAllSpawnsFromDisk(key)

    return true, "All saved respawn points removed across every gamemode and map."
end

local function canManageGlobalSpawns(ply)
    return IsValid(ply) and ply:IsPlayer() and ply:IsAdmin()
end

function SPT.SetGlobalSpawn(ply, pos, normal, eyeAng)
    if not canManageGlobalSpawns(ply) then
        return false, "Only admins can manage global respawn points."
    end

    local spawn, message, reason = makeSpawnData(ply, pos, normal, eyeAng)
    if not spawn then return false, message, reason end

    local spawns = SPT.GlobalSpawns or {}
    local limit = SPT.GetMaxSpawns()
    if #spawns >= limit then
        return false, string.format("Global respawn point limit reached (%d).", limit), "limit"
    end

    spawns[#spawns + 1] = spawn
    SPT.GlobalSpawns = spawns
    SPT.RebuildGlobalMarkers()
    SPT.SaveGlobalSpawnsToDisk(spawns)
    SPT.SyncGlobalChange()

    return true, string.format("Global respawn point added (%d/%d).", #spawns, limit)
end

function SPT.RemoveNearestGlobalSpawn(ply, pos)
    if not canManageGlobalSpawns(ply) then
        return false, "Only admins can manage global respawn points."
    end

    local spawns = SPT.GlobalSpawns
    if not spawns or #spawns == 0 then return false, "No global respawn points to remove." end

    local bestIndex = findNearestSpawnIndex(spawns, pos)
    if not bestIndex then
        return false, "Aim closer to a global respawn point to remove it."
    end

    table.remove(spawns, bestIndex)
    SPT.GlobalSpawns = spawns
    SPT.RebuildGlobalMarkers()
    SPT.SaveGlobalSpawnsToDisk(spawns)
    SPT.SyncGlobalChange()

    return true, string.format("Global respawn point removed (%d remaining).", #spawns)
end

function SPT.ClearGlobalSpawns(ply)
    if not canManageGlobalSpawns(ply) then
        return false, "Only admins can manage global respawn points."
    end

    SPT.GlobalSpawns = {}
    SPT.RebuildGlobalMarkers()
    SPT.DeleteGlobalSpawnsFromDisk()
    SPT.SyncGlobalChange()

    return true, "All global respawn points removed for this gamemode and map."
end
