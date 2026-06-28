SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool

function SPT.IsFiniteNumber(n)
    return isnumber(n) and n == n and n ~= math.huge and n ~= -math.huge
end

function SPT.SanitizeVector(v, fallback)
    if not isvector(v) then return fallback end
    if not SPT.IsFiniteNumber(v.x) or not SPT.IsFiniteNumber(v.y) or not SPT.IsFiniteNumber(v.z) then return fallback end
    return v
end

function SPT.SanitizeNormal(normal)
    normal = SPT.SanitizeVector(normal, Vector(0, 0, 1))
    if normal:IsZero() then return Vector(0, 0, 1) end
    return normal:GetNormalized()
end

function SPT.SanitizeYaw(yaw)
    if not SPT.IsFiniteNumber(yaw) then return 0 end
    return math.NormalizeAngle(yaw)
end

function SPT.CopySpawn(data)
    return {
        pos = data.pos,
        normal = data.normal,
        yaw = data.yaw
    }
end

function SPT.VecToTbl(v)
    return { x = v.x, y = v.y, z = v.z }
end

function SPT.TblToVec(t)
    if not istable(t) then return nil end

    local x = tonumber(t.x)
    local y = tonumber(t.y)
    local z = tonumber(t.z)
    if not x or not y or not z then return nil end

    return Vector(x, y, z)
end
