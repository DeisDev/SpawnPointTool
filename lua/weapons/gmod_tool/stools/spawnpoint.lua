if SERVER then
    AddCSLuaFile()
end

TOOL.Tab = "Main"
TOOL.Category = "RespawnTool"
TOOL.Name = "#tool.spawnpoint.name"
TOOL.Command = nil
TOOL.ConfigName = ""

if CLIENT then
    language.Add("tool.spawnpoint.name", "Respawn Point Tool")
    language.Add("tool.spawnpoint.desc", "Create personal respawn points.")
    language.Add("tool.spawnpoint.0", "Left-click: add respawn point. Right-click: remove aimed respawn point. Reload: clear your map respawn points.")
    CreateClientConVar("spawnpoint_persist", "0", true, true, "Persist your respawn points across sessions")
    CreateClientConVar("spawnpoint_hull_check", "1", true, true, "Check player hull before placing respawn points")
    CreateClientConVar("spawnpoint_always_show", "0", true, true, "Always show known respawn point markers")
end

local function getHitNormal(trace)
    local normal = trace and trace.HitNormal
    if not normal or normal:IsZero() then return Vector(0, 0, 1) end
    return normal:GetNormalized()
end

local function chatResult(ply, ok, message)
    if not message or message == "" then return end
    ply:ChatPrint(message)
end

local function sendAdminSetting(name, value)
    net.Start("spt_admin_settings")
    net.WriteString(name)
    net.WriteString(tostring(value))
    net.SendToServer()
end

local function queueAdminSetting(name, value)
    timer.Remove("spt_admin_setting_" .. name)
    timer.Create("spt_admin_setting_" .. name, 0.25, 1, function()
        sendAdminSetting(name, value)
    end)
end

local function setSliderValue(slider, value)
    if slider and slider.SetValue then
        slider:SetValue(value)
    end
end

local function sendPersistenceMode(enabled)
    RunConsoleCommand("spawnpoint_persist", enabled and "1" or "0")
    net.Start("spt_persist_changed")
    net.WriteBool(enabled)
    net.SendToServer()
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

    chatResult(ply, ok, message)

    return ok == true
end

function TOOL:RightClick(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    if not SpawnPointTool or not SpawnPointTool.RemoveNearestSpawn then return false end

    local pos = trace and trace.Hit and trace.HitPos or nil
    local ok, message = SpawnPointTool.RemoveNearestSpawn(ply, pos)
    chatResult(ply, ok, message)

    return ok == true
end

function TOOL:Reload(trace)
    if CLIENT then return true end

    local ply = self:GetOwner()
    if not IsValid(ply) or not ply:IsPlayer() then return false end

    if not SpawnPointTool or not SpawnPointTool.ClearSpawn then return false end

    local ok, message = SpawnPointTool.ClearSpawn(ply)
    chatResult(ply, ok, message)

    return ok == true
end

function TOOL.BuildCPanel(panel)
    panel:Help("Left-click adds a respawn point. Right-click removes the aimed respawn point. Reload clears your respawn points on this map. Respawns choose randomly from your placed points.")
    panel:Help("Blue preview: valid placement. Red preview: blocked by the player hull check.")

    local persistToggle = panel:CheckBox("Persist across sessions", "spawnpoint_persist")
    persistToggle.OnChange = function(_, checked)
        sendPersistenceMode(checked)
    end

    panel:CheckBox("Check player hull before placement", "spawnpoint_hull_check")
    panel:CheckBox("Always show known markers", "spawnpoint_always_show")

    local ply = LocalPlayer()
    if IsValid(ply) and ply:IsAdmin() then
        panel:Help("Server Settings")

        local adminToggle = panel:CheckBox("Show all players' markers", "spt_show_all_markers")
        adminToggle.OnChange = function(_, checked)
            sendAdminSetting("show_all_markers", checked and "1" or "0")
        end

        local maxSlider = panel:NumSlider("Max respawn points", "spt_max_spawns", 1, 128, 0)
        maxSlider.OnValueChanged = function(_, value)
            queueAdminSetting("max_spawns", math.Round(value))
        end

        local radiusSlider = panel:NumSlider("Remove radius", "spt_delete_radius", 16, 256, 0)
        radiusSlider.OnValueChanged = function(_, value)
            queueAdminSetting("delete_radius", math.Round(value))
        end

        local offsetSlider = panel:NumSlider("Spawn surface offset", "spt_spawn_offset", 0, 32, 0)
        offsetSlider.OnValueChanged = function(_, value)
            queueAdminSetting("spawn_offset", math.Round(value))
        end

        local dangerToggle = panel:CheckBox("Avoid dangerous respawn points", "spt_danger_check")
        dangerToggle.OnChange = function(_, checked)
            sendAdminSetting("danger_check", checked and "1" or "0")
        end

        local dangerSlider = panel:NumSlider("Danger check radius", "spt_danger_radius", 128, 2048, 0)
        dangerSlider.OnValueChanged = function(_, value)
            queueAdminSetting("danger_radius", math.Round(value))
        end

        local resetBtn = panel:Button("Reset server settings")
        resetBtn:SetTooltip("Restores marker visibility, max respawn points, remove radius, spawn offset, and danger check settings to defaults.")
        resetBtn.DoClick = function()
            adminToggle:SetValue(0)
            setSliderValue(maxSlider, 32)
            setSliderValue(radiusSlider, 64)
            setSliderValue(offsetSlider, 8)
            dangerToggle:SetValue(1)
            setSliderValue(dangerSlider, 512)
            sendAdminSetting("reset_defaults", "1")
        end
    end

    local btn = panel:Button("Delete all saved respawn points...")
    btn:SetTooltip("Removes your saved respawn points on all maps. This cannot be undone.")
    btn.DoClick = function()
        Derma_Query(
            "This will delete your saved respawn points on ALL maps. Are you sure?",
            "Confirm deletion",
            "Yes, delete",
            function()
                net.Start("spt_clear_all_request")
                net.SendToServer()
            end,
            "Cancel"
        )
    end

    panel:Help("About")
    panel:Help("Respawn Point Tool v2.0.0")

    local workshopBtn = panel:Button("Open Steam Workshop Page")
    workshopBtn.DoClick = function()
        gui.OpenURL("https://steamcommunity.com/sharedfiles/filedetails/?id=3596484181")
    end

    local githubBtn = panel:Button("Open GitHub Repository")
    githubBtn.DoClick = function()
        gui.OpenURL("https://github.com/DeisDev/SpawnPointTool")
    end
end
