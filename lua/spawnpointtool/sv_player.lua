if CLIENT then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool

function SPT.PlayerKey(ply)
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

function SPT.CanRunAdminCommand(ply)
    return not IsValid(ply) or ply:IsAdmin()
end

function SPT.AdminPrint(ply, message)
    if IsValid(ply) then
        ply:ChatPrint(message)
    else
        print("[Spawn Point Tool] " .. message)
    end
end

function SPT.FindPlayerByText(text)
    if not text or text == "" then return nil end
    local needle = string.lower(text)

    for _, ply in ipairs(player.GetAll()) do
        if string.lower(ply:Nick()):find(needle, 1, true) or ply:SteamID() == text or ply:SteamID64() == text then
            return ply
        end
    end
end
