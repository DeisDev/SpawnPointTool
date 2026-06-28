if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool
local DATA_DIR = "spawnpointtool"

local function mapScopedPath(key)
    local map = game.GetMap() or "unknown"
    return string.format("%s/%s/%s.json", DATA_DIR, map, key)
end

local function legacyPath(key)
    return string.format("%s/%s.json", DATA_DIR, key)
end

function SPT.SanitizeSpawn(data)
    if not istable(data) then return nil end

    local pos = SPT.SanitizeVector(data.pos, nil) or SPT.TblToVec(data.pos)
    if not pos then return nil end

    pos = SPT.SanitizeVector(pos, nil)
    if not pos then return nil end

    return {
        pos = pos,
        normal = SPT.SanitizeNormal(SPT.SanitizeVector(data.normal, nil) or SPT.TblToVec(data.normal) or Vector(0, 0, 1)),
        yaw = SPT.SanitizeYaw(tonumber(data.yaw))
    }
end

function SPT.SanitizeSpawnArray(list)
    local spawns = {}

    if not istable(list) then return spawns end

    for i = 1, math.min(#list, SPT.GetMaxSpawns()) do
        local spawn = SPT.SanitizeSpawn(list[i])
        if spawn then
            spawns[#spawns + 1] = spawn
        end
    end

    return spawns
end

local function sanitizeSpawnList(list)
    if not istable(list) or not istable(list.spawns) then return {} end
    return SPT.SanitizeSpawnArray(list.spawns)
end

function SPT.DeleteSpawnFromDisk(key)
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

function SPT.SaveSpawnsToDisk(key, spawns)
    if not key or not spawns then return end

    if #spawns == 0 then
        SPT.DeleteSpawnFromDisk(key)
        return
    end

    local map = game.GetMap() or "unknown"
    file.CreateDir(DATA_DIR)
    file.CreateDir(string.format("%s/%s", DATA_DIR, map))

    local encoded = {}
    for i = 1, #spawns do
        encoded[i] = {
            pos = SPT.VecToTbl(spawns[i].pos),
            normal = SPT.VecToTbl(spawns[i].normal),
            yaw = spawns[i].yaw
        }
    end

    file.Write(mapScopedPath(key), util.TableToJSON({ spawns = encoded }, false))

    local oldPath = legacyPath(key)
    if file.Exists(oldPath, "DATA") then
        file.Delete(oldPath)
    end
end

function SPT.LoadSpawnsFromDisk(key)
    if not key then return {} end

    local path = mapScopedPath(key)
    if not file.Exists(path, "DATA") then return {} end

    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return {} end

    local decoded = util.JSONToTable(raw)
    return sanitizeSpawnList(decoded)
end

function SPT.DeleteAllSpawnsFromDisk(key)
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
