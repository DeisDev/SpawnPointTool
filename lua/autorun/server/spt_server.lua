if CLIENT then return end

include("autorun/spt_core.lua")

SpawnPointTool = SpawnPointTool or {}

util.AddNetworkString("spt_sync_markers")
util.AddNetworkString("spt_request_markers")
util.AddNetworkString("spt_clear_all_request")
util.AddNetworkString("spt_admin_settings")
util.AddNetworkString("spt_persist_changed")

local DATA_DIR = "spawnpointtool"
local HULL_MINS = Vector(-16, -16, 0)
local HULL_MAXS = Vector(16, 16, 72)
local playerSpawns = {}
local markersByKey = {}
local playerNamesByKey = {}
local clearAllCooldowns = {}
local lastRagModDetected

local addonEnabled = CreateConVar("spt_enabled", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Enable custom respawns from Spawn Point Tool.")
local showAllMarkers = CreateConVar("spt_show_all_markers", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Show every player's respawn point markers while using the tool.")
local markerVisibility = CreateConVar("spt_marker_visibility", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Marker visibility: 0 = own only, 1 = admins see all, 2 = everyone sees all.", 0, 2)
local maxSpawns = CreateConVar("spt_max_spawns", "32", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Maximum respawn points each player can place.", 1, 128)
local deleteRadius = CreateConVar("spt_delete_radius", "64", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Aimed removal radius for respawn points.", 16, 256)
local spawnOffset = CreateConVar("spt_spawn_offset", "8", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Distance to move players away from the saved surface normal.", 0, 32)
local dangerCheck = CreateConVar("spt_danger_check", "1", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Prefer respawn points without nearby NPCs or NextBots.")
local dangerRadius = CreateConVar("spt_danger_radius", "256", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Radius used for respawn point danger checks.", 128, 2048)
local respawnHullCheck = CreateConVar("spt_respawn_hull_check", "0", { FCVAR_ARCHIVE, FCVAR_REPLICATED }, "Check player hull again before using a respawn point.")

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

local function updateRagModDetectionLog()
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

local function isFiniteNumber(n)
    return isnumber(n) and n == n and n ~= math.huge and n ~= -math.huge
end

local function sanitizeVector(v, fallback)
    if not isvector(v) then return fallback end
    if not isFiniteNumber(v.x) or not isFiniteNumber(v.y) or not isFiniteNumber(v.z) then return fallback end
    return v
end

local function sanitizeNormal(normal)
    normal = sanitizeVector(normal, Vector(0, 0, 1))
    if normal:IsZero() then return Vector(0, 0, 1) end
    return normal:GetNormalized()
end

local function sanitizeYaw(yaw)
    if not isFiniteNumber(yaw) then return 0 end
    return math.NormalizeAngle(yaw)
end

local function getMaxSpawns()
    return math.Clamp(maxSpawns:GetInt(), 1, 128)
end

local function getDeleteRadiusSqr()
    return math.Clamp(deleteRadius:GetFloat(), 16, 256) ^ 2
end

local function getSpawnOffset()
    return math.Clamp(spawnOffset:GetFloat(), 0, 32)
end

local function getDangerRadius()
    return math.Clamp(dangerRadius:GetFloat(), 128, 2048)
end

local function getMarkerVisibility()
    if showAllMarkers:GetBool() then return 2 end
    return math.Clamp(markerVisibility:GetInt(), 0, 2)
end

local function playerKey(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return nil end

    local sid64 = ply:SteamID64()
    if isstring(sid64) and sid64 ~= "" and sid64 ~= "0" then
        return sid64, true
    end

    local sid = ply:SteamID()
    if isstring(sid) and sid ~= "" and sid ~= "BOT" and sid ~= "NULL" then
        return sid:gsub("[^%w_%-]", "_"), true
    end

    return "ent_" .. ply:EntIndex(), false
end

local function vecToTbl(v)
    return { x = v.x, y = v.y, z = v.z }
end

local function tblToVec(t)
    if not istable(t) then return nil end

    local x = tonumber(t.x)
    local y = tonumber(t.y)
    local z = tonumber(t.z)
    if not x or not y or not z then return nil end

    return Vector(x, y, z)
end

local function mapScopedPath(key)
    local map = game.GetMap() or "unknown"
    return string.format("%s/%s/%s.json", DATA_DIR, map, key)
end

local function legacyPath(key)
    return string.format("%s/%s.json", DATA_DIR, key)
end

local function copySpawn(data)
    return {
        pos = data.pos,
        normal = data.normal,
        yaw = data.yaw
    }
end

local function sanitizeSpawn(data)
    if not istable(data) then return nil end

    local pos = sanitizeVector(data.pos, nil) or tblToVec(data.pos)
    if not pos then return nil end

    pos = sanitizeVector(pos, nil)
    if not pos then return nil end

    return {
        pos = pos,
        normal = sanitizeNormal(sanitizeVector(data.normal, nil) or tblToVec(data.normal) or Vector(0, 0, 1)),
        yaw = sanitizeYaw(tonumber(data.yaw))
    }
end

local function sanitizeSpawnArray(list)
    local spawns = {}

    if not istable(list) then return spawns end

    for i = 1, math.min(#list, getMaxSpawns()) do
        local spawn = sanitizeSpawn(list[i])
        if spawn then
            spawns[#spawns + 1] = spawn
        end
    end

    return spawns
end

local function sanitizeSpawnList(list)
    if not istable(list) or not istable(list.spawns) then return {} end
    return sanitizeSpawnArray(list.spawns)
end

local function deleteSpawnFromDisk(key)
    if not key then return end

    local path = mapScopedPath(key)
    if file.Exists(path, "DATA") then
        file.Delete(path)
    end

    local oldPath = legacyPath(key)
    if file.Exists(oldPath, "DATA") then
        file.Delete(oldPath)
    end
end

local function saveSpawnsToDisk(key, spawns)
    if not key or not spawns then return end

    if #spawns == 0 then
        deleteSpawnFromDisk(key)
        return
    end

    local map = game.GetMap() or "unknown"
    file.CreateDir(DATA_DIR)
    file.CreateDir(string.format("%s/%s", DATA_DIR, map))

    local encoded = {}
    for i = 1, #spawns do
        encoded[i] = {
            pos = vecToTbl(spawns[i].pos),
            normal = vecToTbl(spawns[i].normal),
            yaw = spawns[i].yaw
        }
    end

    file.Write(mapScopedPath(key), util.TableToJSON({ spawns = encoded }, false))

    local oldPath = legacyPath(key)
    if file.Exists(oldPath, "DATA") then
        file.Delete(oldPath)
    end
end

local function loadSpawnsFromDisk(key)
    if not key then return {} end

    local path = mapScopedPath(key)
    if not file.Exists(path, "DATA") then return {} end

    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return {} end

    local decoded = util.JSONToTable(raw)
    return sanitizeSpawnList(decoded)
end

local function deleteAllSpawnsFromDisk(key)
    if not key then return end

    file.CreateDir(DATA_DIR)

    local _, folders = file.Find(DATA_DIR .. "/*", "DATA")
    for _, folder in ipairs(folders or {}) do
        local path = string.format("%s/%s/%s.json", DATA_DIR, folder, key)
        if file.Exists(path, "DATA") then
            file.Delete(path)
        end
    end

    local oldPath = legacyPath(key)
    if file.Exists(oldPath, "DATA") then
        file.Delete(oldPath)
    end
end

local function rebuildMarkersForKey(key)
    local spawns = playerSpawns[key]
    if not spawns or #spawns == 0 then
        markersByKey[key] = nil
        return
    end

    local markers = {}
    for i = 1, #(spawns or {}) do
        markers[i] = {
            pos = spawns[i].pos,
            normal = spawns[i].normal,
            yaw = spawns[i].yaw,
            index = i
        }
    end

    markersByKey[key] = markers
end

local function getMarkerCountForKey(key)
    local markers = markersByKey[key]
    return markers and #markers or 0
end

local function getAllMarkerCount()
    local count = 0

    for _, markers in pairs(markersByKey) do
        count = count + #markers
    end

    return count
end

local function writeMarker(marker, own, ownerName)
    net.WriteVector(marker.pos)
    net.WriteVector(marker.normal)
    net.WriteBool(own)
    net.WriteFloat(marker.yaw or 0)
    net.WriteUInt(math.Clamp(marker.index or 1, 1, 65535), 16)
    net.WriteString(ownerName or "Player")
end

local function writeMarkersForPlayer(ply)
    local key = playerKey(ply)
    local visibility = getMarkerVisibility()
    local includeAll = visibility == 2 or (visibility == 1 and IsValid(ply) and ply:IsAdmin())
    local count = includeAll and getAllMarkerCount() or getMarkerCountForKey(key)

    net.Start("spt_sync_markers")
    net.WriteUInt(math.min(count, 65535), 16)

    local written = 0
    if includeAll then
        for markerKey, markers in pairs(markersByKey) do
            local own = markerKey == key
            local ownerName = playerNamesByKey[markerKey] or "Player"
            for i = 1, #markers do
                written = written + 1
                if written > 65535 then break end
                writeMarker(markers[i], own, ownerName)
            end

            if written > 65535 then break end
        end
    else
        local markers = markersByKey[key]
        for i = 1, #(markers or {}) do
            written = written + 1
            if written > 65535 then break end
            writeMarker(markers[i], true, playerNamesByKey[key] or ply:Nick())
        end
    end

    net.Send(ply)
end

local function isUsingSpawnTool(ply)
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "gmod_tool" then return false end

    return ply:GetInfo("gmod_toolmode") == "spawnpoint"
end

local function wantsMarkers(ply)
    return isUsingSpawnTool(ply) or ply:GetInfoNum("spawnpoint_always_show", 0) == 1
end

local function broadcastMarkers(toPly, changedKey)
    if IsValid(toPly) then
        writeMarkersForPlayer(toPly)
        return
    end

    if getMarkerVisibility() == 0 and changedKey then
        for _, ply in ipairs(player.GetHumans()) do
            if playerKey(ply) == changedKey and wantsMarkers(ply) then
                writeMarkersForPlayer(ply)
                return
            end
        end

        return
    end

    for _, target in ipairs(player.GetHumans()) do
        if wantsMarkers(target) then
            writeMarkersForPlayer(target)
        end
    end
end

local function syncOwnerChange(ply, key)
    if getMarkerVisibility() > 0 then
        broadcastMarkers(nil, key)
    else
        broadcastMarkers(ply)
    end
end

local function applyLoadedSpawns(ply, spawns)
    local key = playerKey(ply)
    if not key or not spawns or #spawns == 0 then return false end

    playerNamesByKey[key] = ply:Nick()
    playerSpawns[key] = sanitizeSpawnArray(spawns)
    rebuildMarkersForKey(key)
    return #playerSpawns[key] > 0
end

local function shouldValidateHull(ply)
    return ply:GetInfoNum("spawnpoint_hull_check", 1) == 1
end

local function isSpawnHullClear(ply, pos, normal)
    local startPos = pos + normal * getSpawnOffset()
    local tr = util.TraceHull({
        start = startPos,
        endpos = startPos,
        mins = HULL_MINS,
        maxs = HULL_MAXS,
        filter = ply,
        mask = MASK_PLAYERSOLID
    })

    return not tr.StartSolid and not tr.AllSolid and tr.Fraction == 1
end

local function isRespawnPointClear(ply, spawn)
    if not respawnHullCheck:GetBool() then return true end
    return isSpawnHullClear(ply, spawn.pos, spawn.normal)
end

local function isDangerEntity(ent)
    if not IsValid(ent) then return false end
    if ent:IsNPC() then return true end
    if ent.IsNextBot and ent:IsNextBot() then return true end
    return false
end

local function isSpawnDangerous(pos)
    local radius = getDangerRadius()
    local entsInRange = ents.FindInSphere(pos, radius)

    for i = 1, #entsInRange do
        if isDangerEntity(entsInRange[i]) then
            return true
        end
    end

    return false
end

local function chooseRespawnPoint(ply, spawns)
    local usableSpawns = {}
    for i = 1, #spawns do
        if isRespawnPointClear(ply, spawns[i]) then
            usableSpawns[#usableSpawns + 1] = spawns[i]
        end
    end

    if #usableSpawns == 0 then return nil end

    if #usableSpawns <= 1 or not dangerCheck:GetBool() then
        return copySpawn(usableSpawns[math.random(#usableSpawns)])
    end

    local safeSpawns = {}
    for i = 1, #usableSpawns do
        if not isSpawnDangerous(usableSpawns[i].pos + usableSpawns[i].normal * getSpawnOffset()) then
            safeSpawns[#safeSpawns + 1] = usableSpawns[i]
        end
    end

    if #safeSpawns > 0 then
        return copySpawn(safeSpawns[math.random(#safeSpawns)])
    end

    return copySpawn(usableSpawns[math.random(#usableSpawns)])
end

local function shouldIgnorePlayerSpawn(ply)
    if not updateRagModDetectionLog() then return false end

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
    local _, canPersist = playerKey(ply)
    if canPersist and ply:GetInfoNum("spawnpoint_persist", 0) == 1 then
        saveSpawnsToDisk(key, playerSpawns[key] or {})
    else
        deleteSpawnFromDisk(key)
    end
end

local function setPersistenceMode(ply, enabled)
    local key, canPersist = playerKey(ply)
    if not key or not canPersist then return false end

    if enabled then
        saveSpawnsToDisk(key, playerSpawns[key] or {})
    else
        deleteSpawnFromDisk(key)
    end

    return true
end

function SpawnPointTool.SetSpawn(ply, pos, normal, eyeAng)
    local key = playerKey(ply)
    if not key then return false, "Invalid player." end
    playerNamesByKey[key] = ply:Nick()

    pos = sanitizeVector(pos, nil)
    if not pos then return false, "Invalid spawn position." end

    normal = sanitizeNormal(normal)

    if shouldValidateHull(ply) and not isSpawnHullClear(ply, pos, normal) then
        return false, "Spawn point blocked.", "blocked"
    end

    local yaw = ply:EyeAngles().y
    if eyeAng and isFiniteNumber(eyeAng.y) then
        yaw = eyeAng.y
    end

    local spawns = playerSpawns[key] or {}
    local limit = getMaxSpawns()
    if #spawns >= limit then
        return false, string.format("Spawn point limit reached (%d).", limit), "limit"
    end

    spawns[#spawns + 1] = {
        pos = pos,
        normal = normal,
        yaw = sanitizeYaw(yaw)
    }

    playerSpawns[key] = spawns
    rebuildMarkersForKey(key)
    persistIfNeeded(ply, key)
    syncOwnerChange(ply, key)

    return true, string.format("Spawn point added (%d/%d).", #spawns, limit)
end

function SpawnPointTool.RemoveNearestSpawn(ply, pos)
    local key = playerKey(ply)
    if not key then return false, "Invalid player." end

    local spawns = playerSpawns[key]
    if not spawns or #spawns == 0 then return false, "No respawn points to remove." end

    local bestIndex
    local bestDist = getDeleteRadiusSqr()

    if sanitizeVector(pos, nil) then
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

    if not bestIndex then
        return false, "Aim closer to one of your respawn points to remove it."
    end

    table.remove(spawns, bestIndex)

    if #spawns == 0 then
        playerSpawns[key] = nil
        playerNamesByKey[key] = nil
    end

    rebuildMarkersForKey(key)
    persistIfNeeded(ply, key)
    syncOwnerChange(ply, key)

    return true, string.format("Spawn point removed (%d remaining).", #spawns)
end

function SpawnPointTool.ClearSpawn(ply)
    local key = playerKey(ply)
    if not key then return false, "Invalid player." end

    playerSpawns[key] = nil
    playerNamesByKey[key] = nil
    rebuildMarkersForKey(key)
    deleteSpawnFromDisk(key)
    syncOwnerChange(ply, key)

    return true, "All respawn points removed for this map."
end

function SpawnPointTool.ClearAllSpawns(ply)
    local key = playerKey(ply)
    if not key then return false, "Invalid player." end

    SpawnPointTool.ClearSpawn(ply)
    deleteAllSpawnsFromDisk(key)

    return true, "All saved respawn points removed across all maps."
end

local function findPlayerByText(text)
    if not text or text == "" then return nil end
    local needle = string.lower(text)

    for _, ply in ipairs(player.GetAll()) do
        if string.lower(ply:Nick()):find(needle, 1, true) or ply:SteamID() == text or ply:SteamID64() == text then
            return ply
        end
    end
end

local function canRunAdminCommand(ply)
    return not IsValid(ply) or ply:IsAdmin()
end

local function adminPrint(ply, message)
    if IsValid(ply) then
        ply:ChatPrint(message)
    else
        print("[Spawn Point Tool] " .. message)
    end
end

local function clearPlayerSpawnsByKey(key)
    playerSpawns[key] = nil
    playerNamesByKey[key] = nil
    rebuildMarkersForKey(key)
    deleteSpawnFromDisk(key)
    broadcastMarkers(nil, key)
end

concommand.Add("spt_list_counts", function(ply)
    if not canRunAdminCommand(ply) then return end

    local rows = {}
    for key, spawns in pairs(playerSpawns) do
        rows[#rows + 1] = string.format("%s: %d", playerNamesByKey[key] or key, #(spawns or {}))
    end

    if #rows == 0 then
        adminPrint(ply, "No loaded respawn points.")
        return
    end

    adminPrint(ply, "Loaded respawn points: " .. table.concat(rows, ", "))
end, nil, "List loaded Spawn Point Tool respawn point counts.")

concommand.Add("spt_clear_player", function(ply, _, args)
    if not canRunAdminCommand(ply) then return end

    local targetText = table.concat(args or {}, " ")
    local target = findPlayerByText(targetText)
    if not IsValid(target) then
        adminPrint(ply, "Player not found.")
        return
    end

    local key = playerKey(target)
    if not key then
        adminPrint(ply, "Could not identify player.")
        return
    end

    clearPlayerSpawnsByKey(key)
    adminPrint(ply, "Cleared respawn points for " .. target:Nick() .. ".")
end, nil, "Clear a player's Spawn Point Tool respawn points on this map.")

net.Receive("spt_clear_all_request", function(len, ply)
    local key = playerKey(ply)
    if not key then return end

    local now = CurTime()
    if clearAllCooldowns[key] and clearAllCooldowns[key] > now then return end
    clearAllCooldowns[key] = now + 2

    local ok, message = SpawnPointTool.ClearAllSpawns(ply)
    if ok and message then
        ply:ChatPrint(message)
    end
end)

net.Receive("spt_request_markers", function(len, ply)
    if not wantsMarkers(ply) then return end
    writeMarkersForPlayer(ply)
end)

net.Receive("spt_persist_changed", function(len, ply)
    if not IsValid(ply) then return end
    setPersistenceMode(ply, net.ReadBool())
end)

net.Receive("spt_admin_settings", function(len, ply)
    if not IsValid(ply) or not ply:IsAdmin() then return end

    local setting = net.ReadString()
    local value = net.ReadString()

    if setting == "show_all_markers" then
        RunConsoleCommand("spt_show_all_markers", value == "1" and "1" or "0")
        broadcastMarkers()
    elseif setting == "enabled" then
        RunConsoleCommand("spt_enabled", value == "1" and "1" or "0")
    elseif setting == "marker_visibility" then
        RunConsoleCommand("spt_marker_visibility", tostring(math.Clamp(math.floor(tonumber(value) or markerVisibility:GetInt()), 0, 2)))
        RunConsoleCommand("spt_show_all_markers", "0")
        broadcastMarkers()
    elseif setting == "max_spawns" then
        RunConsoleCommand("spt_max_spawns", tostring(math.Clamp(math.floor(tonumber(value) or maxSpawns:GetInt()), 1, 128)))
    elseif setting == "delete_radius" then
        RunConsoleCommand("spt_delete_radius", tostring(math.Clamp(tonumber(value) or deleteRadius:GetFloat(), 16, 256)))
    elseif setting == "spawn_offset" then
        RunConsoleCommand("spt_spawn_offset", tostring(math.Clamp(tonumber(value) or spawnOffset:GetFloat(), 0, 32)))
    elseif setting == "danger_check" then
        RunConsoleCommand("spt_danger_check", value == "1" and "1" or "0")
    elseif setting == "danger_radius" then
        RunConsoleCommand("spt_danger_radius", tostring(math.Clamp(tonumber(value) or dangerRadius:GetFloat(), 128, 2048)))
    elseif setting == "respawn_hull_check" then
        RunConsoleCommand("spt_respawn_hull_check", value == "1" and "1" or "0")
    elseif setting == "reset_defaults" then
        RunConsoleCommand("spt_enabled", "1")
        RunConsoleCommand("spt_show_all_markers", "0")
        RunConsoleCommand("spt_marker_visibility", "0")
        RunConsoleCommand("spt_max_spawns", "32")
        RunConsoleCommand("spt_delete_radius", "64")
        RunConsoleCommand("spt_spawn_offset", "8")
        RunConsoleCommand("spt_danger_check", "1")
        RunConsoleCommand("spt_danger_radius", "256")
        RunConsoleCommand("spt_respawn_hull_check", "0")
        broadcastMarkers()
    end
end)

cvars.AddChangeCallback("spt_show_all_markers", function()
    timer.Simple(0, function()
        broadcastMarkers()
    end)
end, "spt_marker_visibility_sync")

cvars.AddChangeCallback("spt_marker_visibility", function()
    timer.Simple(0, function()
        broadcastMarkers()
    end)
end, "spt_marker_mode_sync")

timer.Simple(0, function()
    updateRagModDetectionLog()
end)

hook.Add("PlayerInitialSpawn", "spt_send_markers_on_join", function(ply)
    local key, canPersist = playerKey(ply)

    if key and canPersist then
        if applyLoadedSpawns(ply, loadSpawnsFromDisk(key)) then
            broadcastMarkers(nil, key)
        end
    end
end)

hook.Add("PlayerDisconnected", "spt_forget_ephemeral_spawn", function(ply)
    local key, canPersist = playerKey(ply)
    if key and not canPersist then
        playerSpawns[key] = nil
        playerNamesByKey[key] = nil
        rebuildMarkersForKey(key)
        broadcastMarkers(nil, key)
    end

    if key then
        clearAllCooldowns[key] = nil
    end
end)

hook.Add("PlayerSpawn", "spt_apply_custom_spawn", function(ply, transition)
    if transition then return end
    if not addonEnabled:GetBool() then return end
    if ply:GetInfoNum("spawnpoint_enabled", 1) ~= 1 then return end
    if shouldIgnorePlayerSpawn(ply) then return end

    local key, canPersist = playerKey(ply)
    if not key then return end

    local spawns = playerSpawns[key]
    if (not spawns or #spawns == 0) and canPersist then
        spawns = loadSpawnsFromDisk(key)
        if applyLoadedSpawns(ply, spawns) then
            broadcastMarkers(nil, key)
        end
    end

    if not spawns or #spawns == 0 then return end

    local data = chooseRespawnPoint(ply, spawns)
    if not data then return end

    timer.Simple(0, function()
        if not IsValid(ply) then return end

        ply:SetPos(data.pos + data.normal * getSpawnOffset())

        local ang = ply:EyeAngles()
        ang.y = data.yaw
        ply:SetEyeAngles(ang)
    end)
end)
