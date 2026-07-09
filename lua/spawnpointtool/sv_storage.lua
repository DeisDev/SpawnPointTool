if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool
local DATA_DIR = "spawnpointtool"
local SANDBOX_DIR = DATA_DIR .. "/sandbox"
local GAMEMODE_MIGRATION_MARKER = DATA_DIR .. "/gamemode_scope_migrated.txt"

local function activeGamemode()
    local mode = engine.ActiveGamemode() or "unknown"
    mode = mode:gsub("[^%w_%-]", "_")
    mode = string.lower(mode)
    if mode == "" then return "unknown" end
    return mode
end

local function currentMap()
    local map = game.GetMap() or "unknown"
    if map == "" then return "unknown" end
    return string.lower(map)
end

local function gamemodeScopedDir()
    return string.format("%s/%s", DATA_DIR, activeGamemode())
end

local function scopedDir()
    return string.format("%s/%s", gamemodeScopedDir(), currentMap())
end

local function scopedPath(key)
    return string.format("%s/%s.json", scopedDir(), key)
end

local function legacyPath(key)
    return string.format("%s/%s.json", DATA_DIR, key)
end

local function ensureScopedDir()
    file.CreateDir(DATA_DIR)
    file.CreateDir(gamemodeScopedDir())
    file.CreateDir(scopedDir())
end

local function deleteIfExists(path)
    if file.Exists(path, "DATA") then
        file.Delete(path)
    end
end

local function migrateMapScopedStorageToSandbox()
    if file.Exists(GAMEMODE_MIGRATION_MARKER, "DATA") then return end

    file.CreateDir(DATA_DIR)

    local migrationComplete = true
    local _, folders = file.Find(DATA_DIR .. "/*", "DATA")

    for _, folder in ipairs(folders or {}) do
        local sourceDir = string.format("%s/%s", DATA_DIR, folder)
        local files = file.Find(sourceDir .. "/*.json", "DATA")

        if files and #files > 0 then
            local targetDir = string.format("%s/%s", SANDBOX_DIR, folder)
            file.CreateDir(targetDir)

            for _, name in ipairs(files) do
                local sourcePath = string.format("%s/%s", sourceDir, name)
                local targetPath = string.format("%s/%s", targetDir, name)

                if file.Exists(targetPath, "DATA") then
                    -- New Sandbox data wins; keep the legacy file as an untouched backup.
                    print(string.format(
                        "[Spawn Point Tool] Kept legacy save %s because Sandbox data already exists.",
                        sourcePath
                    ))
                elseif not file.Rename(sourcePath, targetPath) then
                    migrationComplete = false
                    print("[Spawn Point Tool] Could not migrate legacy save " .. sourcePath .. ".")
                end
            end
        end
    end

    if migrationComplete and not file.Write(GAMEMODE_MIGRATION_MARKER, "1") then
        print("[Spawn Point Tool] Could not record the storage migration.")
    end
end

local function encodeSpawnArray(spawns)
    local encoded = {}

    for i = 1, #spawns do
        encoded[i] = {
            pos = SPT.VecToTbl(spawns[i].pos),
            normal = SPT.VecToTbl(spawns[i].normal),
            yaw = spawns[i].yaw
        }
    end

    return encoded
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

    deleteIfExists(scopedPath(key))
    deleteIfExists(legacyPath(key))
end

function SPT.SaveSpawnsToDisk(key, spawns)
    if not key or not spawns then return end

    if #spawns == 0 then
        SPT.DeleteSpawnFromDisk(key)
        return
    end

    ensureScopedDir()

    file.Write(scopedPath(key), util.TableToJSON({ spawns = encodeSpawnArray(spawns) }, false))
    deleteIfExists(legacyPath(key))
end

function SPT.LoadSpawnsFromDisk(key)
    if not key then return {} end

    local path = scopedPath(key)
    if not file.Exists(path, "DATA") then return {} end

    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return {} end

    local decoded = util.JSONToTable(raw)
    return sanitizeSpawnList(decoded)
end

function SPT.DeleteAllSpawnsFromDisk(key)
    if not key then return end

    file.CreateDir(DATA_DIR)

    local _, firstLevelFolders = file.Find(DATA_DIR .. "/*", "DATA")
    for _, folder in ipairs(firstLevelFolders or {}) do
        deleteIfExists(string.format("%s/%s/%s.json", DATA_DIR, folder, key))

        local _, mapFolders = file.Find(string.format("%s/%s/*", DATA_DIR, folder), "DATA")
        for _, mapFolder in ipairs(mapFolders or {}) do
            deleteIfExists(string.format("%s/%s/%s/%s.json", DATA_DIR, folder, mapFolder, key))
        end
    end

    deleteIfExists(legacyPath(key))
end

function SPT.DeleteGlobalSpawnsFromDisk()
    deleteIfExists(scopedPath(SPT.GlobalSpawnKey))
end

function SPT.SaveGlobalSpawnsToDisk(spawns)
    if not spawns then return end

    if #spawns == 0 then
        SPT.DeleteGlobalSpawnsFromDisk()
        return
    end

    ensureScopedDir()
    file.Write(scopedPath(SPT.GlobalSpawnKey), util.TableToJSON({ spawns = encodeSpawnArray(spawns) }, false))
end

function SPT.LoadGlobalSpawnsFromDisk()
    local path = scopedPath(SPT.GlobalSpawnKey)
    if not file.Exists(path, "DATA") then return {} end

    local raw = file.Read(path, "DATA")
    if not raw or raw == "" then return {} end

    local decoded = util.JSONToTable(raw)
    return sanitizeSpawnList(decoded)
end

migrateMapScopedStorageToSandbox()
SPT.GlobalSpawns = SPT.LoadGlobalSpawnsFromDisk()
