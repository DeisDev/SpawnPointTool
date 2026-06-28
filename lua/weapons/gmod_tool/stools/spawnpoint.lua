if SERVER then
    AddCSLuaFile()
end

include("autorun/spt_core.lua")

TOOL.Tab = "Main"
TOOL.Category = "SpawnPointTool"
TOOL.Name = "#tool.spawnpoint.name"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.spawnpoint.name", "Spawn Point Tool")
    language.Add("tool.spawnpoint.desc", "Create personal respawn points.")
    language.Add("tool.spawnpoint.0", "Left-click: add respawn point. Right-click: remove aimed respawn point. Reload: clear your map respawn points.")
end

local function getHitNormal(trace)
    local normal = trace and trace.HitNormal
    if not normal or normal:IsZero() then return Vector(0, 0, 1) end
    return normal:GetNormalized()
end

local function chatResult(ply, message)
    if not message or message == "" then return end
    ply:ChatPrint(message)
end

function TOOL:LeftClick(trace)
    if CLIENT then return true end
    if not trace or not trace.Hit or trace.HitSky then return false end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    if not SpawnPointTool or not SpawnPointTool.SetSpawn then return false end

    local eyeAng = ply:EyeAngles()
    local ok, message, reason = SpawnPointTool.SetSpawn(ply, trace.HitPos, getHitNormal(trace), Angle(0, eyeAng.y, 0))
    if not ok and reason == "blocked" then
        ply:EmitSound("buttons/button10.wav", 65, 100, 1, CHAN_ITEM)
    end

    chatResult(ply, message)

    return ok == true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    if not SpawnPointTool or not SpawnPointTool.RemoveNearestSpawn then return false end

    local pos = trace and trace.Hit and trace.HitPos or nil
    local ok, message = SpawnPointTool.RemoveNearestSpawn(ply, pos)
    chatResult(ply, message)

    return ok == true
end

function TOOL:Reload()
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    if not SpawnPointTool or not SpawnPointTool.ClearSpawn then return false end

    local ok, message = SpawnPointTool.ClearSpawn(ply)
    chatResult(ply, message)

    return ok == true
end

function TOOL.BuildCPanel(panel)
    if CLIENT and not SpawnPointTool.BuildCPanel then
        include("spawnpointtool/cl_menu.lua")
    end

    if SpawnPointTool and SpawnPointTool.BuildCPanel then
        SpawnPointTool.BuildCPanel(panel)
    end
end
