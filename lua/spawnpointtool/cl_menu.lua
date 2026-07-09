if SERVER then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool
local defaults = SPT.ClientDefaults
local suppressAdminCallbacks = false

if not SPT.ClientConVarsCreated then
    CreateClientConVar("spawnpoint_enabled", tostring(defaults.Enabled), true, true, "Use your Spawn Point Tool respawn points")
    CreateClientConVar("spawnpoint_persist", tostring(defaults.Persist), true, true, "Persist your respawn points across sessions")
    CreateClientConVar("spawnpoint_hull_check", tostring(defaults.HullCheck), true, true, "Check player hull before placing respawn points")
    CreateClientConVar("spawnpoint_always_show", tostring(defaults.AlwaysShow), true, true, "Always show synced respawn point markers")
    CreateClientConVar("spawnpoint_global_mode", tostring(defaults.GlobalMode), false, true, "Use the tool on global respawn points")
    CreateClientConVar("spawnpoint_global_sticky", tostring(defaults.GlobalSticky), true, false, "Keep global respawn point placement enabled")
    CreateClientConVar("spawnpoint_global_hotkey", tostring(defaults.GlobalHotkey), true, false, "Hold key for global respawn point placement", 0, KEY_COUNT or 107)
    SPT.ClientConVarsCreated = true
end

hook.Add("AddToolMenuCategories", "spt_add_category", function()
    if not spawnmenu then return end
    spawnmenu.AddToolCategory("Main", "SpawnPointTool", "Spawn Point Tool")
end)

local function addForm(panel, name)
    local form = vgui.Create("DForm", panel)
    form:SetName(name)
    panel:AddItem(form)
    return form
end

local function sendAdminSetting(id, value)
    net.Start(SPT.Net.AdminSetting)
    net.WriteUInt(id, 5)
    net.WriteFloat(tonumber(value) or 0)
    net.SendToServer()
end

local function queueAdminSetting(name, id, value)
    timer.Remove("spt_admin_setting_" .. name)
    timer.Create("spt_admin_setting_" .. name, 0.25, 1, function()
        sendAdminSetting(id, value)
    end)
end

local function setSliderValue(slider, value)
    if slider and slider.SetValue then
        slider:SetValue(value)
    end
end

local function addBinder(form, label, convarName, defaultValue)
    local row = vgui.Create("DPanel", form)
    row:SetTall(52)
    row:SetPaintBackground(false)
    row:DockPadding(0, 2, 0, 0)

    local text = vgui.Create("DLabel", row)
    text:Dock(TOP)
    text:DockMargin(0, 0, 0, 4)
    text:SetText(label)
    text:SizeToContentsY()

    local binder = vgui.Create("DBinder", row)
    binder:Dock(FILL)
    local convar = GetConVar(convarName)
    binder:SetValue(convar and convar:GetInt() or defaultValue)
    binder.OnChange = function(_, keyCode)
        RunConsoleCommand(convarName, tostring(math.Clamp(keyCode, 0, KEY_COUNT or 107)))
    end

    form:AddItem(row)
    return binder
end

local function sendPersistenceMode(enabled)
    RunConsoleCommand("spawnpoint_persist", enabled and "1" or "0")
    net.Start(SPT.Net.PersistChanged)
    net.WriteBool(enabled)
    net.SendToServer()
end

local function addConfirmButton(form, label, tooltip, message, netName)
    local button = form:Button(label)
    button:SetTooltip(tooltip)
    button.DoClick = function()
        Derma_Query(
            message,
            "Confirm deletion",
            "Delete",
            function()
                net.Start(netName)
                net.SendToServer()
            end,
            "Cancel"
        )
    end
end

local function addLinkButton(form, label, url)
    local button = form:Button(label)
    button:SetTooltip(url)
    button.DoClick = function()
        gui.OpenURL(url)
    end
end

local function addPlayerSettings(panel)
    local playerForm = addForm(panel, "Player")
    playerForm:Help("Choose when your saved points are used and shown.")

    local enabledToggle = playerForm:CheckBox("Use my respawn points", "spawnpoint_enabled")
    local persistToggle = playerForm:CheckBox("Persist across sessions", "spawnpoint_persist")
    persistToggle.OnChange = function(_, checked)
        sendPersistenceMode(checked)
    end
    local alwaysShowToggle = playerForm:CheckBox("Always show synced markers", "spawnpoint_always_show")
    playerForm:Help("Saved points are separate for each gamemode and map.")

    local placementForm = addForm(panel, "Placement")
    placementForm:Help("Left-click adds a point, right-click removes the aimed point, and reload clears points for this gamemode and map.")
    local hullToggle = placementForm:CheckBox("Check player hull before placement", "spawnpoint_hull_check")
    placementForm:Help("The placement preview turns red when this check thinks the spot is blocked.")

    local resetClientBtn = playerForm:Button("Reset player settings")
    resetClientBtn:SetTooltip("Restores your respawn, persistence, placement, and marker display settings.")
    resetClientBtn.DoClick = function()
        enabledToggle:SetValue(defaults.Enabled)
        persistToggle:SetValue(defaults.Persist)
        alwaysShowToggle:SetValue(defaults.AlwaysShow)
        hullToggle:SetValue(defaults.HullCheck)

        RunConsoleCommand("spawnpoint_enabled", tostring(defaults.Enabled))
        sendPersistenceMode(defaults.Persist == 1)
        RunConsoleCommand("spawnpoint_always_show", tostring(defaults.AlwaysShow))
        RunConsoleCommand("spawnpoint_hull_check", tostring(defaults.HullCheck))
        RunConsoleCommand("spawnpoint_global_mode", tostring(defaults.GlobalMode))
        RunConsoleCommand("spawnpoint_global_sticky", tostring(defaults.GlobalSticky))
        RunConsoleCommand("spawnpoint_global_hotkey", tostring(defaults.GlobalHotkey))

        if SPT.GlobalStickyToggle then
            SPT.GlobalStickyToggle:SetValue(defaults.GlobalSticky)
        end

        if SPT.GlobalHotkeyBinder then
            SPT.GlobalHotkeyBinder:SetValue(defaults.GlobalHotkey)
        end
    end
end

local function addAdminSettings(panel)
    local ply = LocalPlayer()
    if not IsValid(ply) or not ply:IsAdmin() then
        local lockedForm = addForm(panel, "Server")
        lockedForm:Help("Server settings are available to admins.")
        return
    end

    local setting = SPT.AdminSetting
    local placementForm = addForm(panel, "Admin Placement")
    placementForm:Help("Hold the key or use sticky mode.")

    SPT.GlobalStickyToggle = placementForm:CheckBox("Sticky global placement", "spawnpoint_global_sticky")
    SPT.GlobalHotkeyBinder = addBinder(placementForm, "Global hold key", "spawnpoint_global_hotkey", defaults.GlobalHotkey)

    local serverForm = addForm(panel, "Server")
    serverForm:Help("Server-wide limits and behavior for custom respawns.")

    local enabledServerToggle = serverForm:CheckBox("Enable custom respawns", "spt_enabled")
    enabledServerToggle.OnChange = function(_, checked)
        if suppressAdminCallbacks then return end
        sendAdminSetting(setting.Enabled, checked and 1 or 0)
    end

    local maxSlider = serverForm:NumSlider("Max respawn points", "spt_max_spawns", 1, 128, 0)
    maxSlider.OnValueChanged = function(_, value)
        if suppressAdminCallbacks then return end
        queueAdminSetting("max_spawns", setting.MaxSpawns, math.Round(value))
    end

    local offsetSlider = serverForm:NumSlider("Spawn surface offset", "spt_spawn_offset", 0, 32, 0)
    offsetSlider.OnValueChanged = function(_, value)
        if suppressAdminCallbacks then return end
        queueAdminSetting("spawn_offset", setting.SpawnOffset, math.Round(value))
    end

    local radiusSlider = serverForm:NumSlider("Remove radius", "spt_delete_radius", 16, 256, 0)
    radiusSlider.OnValueChanged = function(_, value)
        if suppressAdminCallbacks then return end
        queueAdminSetting("delete_radius", setting.DeleteRadius, math.Round(value))
    end

    local markerForm = addForm(panel, "Server Marker Sharing")
    markerForm:Help("Controls which synced markers players can see while holding the tool or using Always Show.")

    local markerCombo = markerForm:ComboBox("Shared marker visibility", "spt_marker_visibility")
    markerCombo:AddChoice("Own markers only", SPT.MarkerVisibility.OwnOnly)
    markerCombo:AddChoice("Admins see all", SPT.MarkerVisibility.Admins)
    markerCombo:AddChoice("Everyone sees all", SPT.MarkerVisibility.Everyone)
    markerCombo.OnSelect = function(_, _, _, data)
        if suppressAdminCallbacks then return end
        sendAdminSetting(setting.MarkerVisibility, data or SPT.MarkerVisibility.OwnOnly)
    end

    local visibility = GetConVar("spt_marker_visibility")
    if visibility then
        local labels = {
            [SPT.MarkerVisibility.OwnOnly] = "Own markers only",
            [SPT.MarkerVisibility.Admins] = "Admins see all",
            [SPT.MarkerVisibility.Everyone] = "Everyone sees all"
        }
        markerCombo:SetValue(labels[visibility:GetInt()] or labels[SPT.MarkerVisibility.OwnOnly])
    end

    local safetyForm = addForm(panel, "Respawn Safety")
    safetyForm:Help("Danger checks prefer safer points. Respawn hull checks are stricter and off by default.")

    local dangerToggle = safetyForm:CheckBox("Avoid dangerous respawn points", "spt_danger_check")
    dangerToggle.OnChange = function(_, checked)
        if suppressAdminCallbacks then return end
        sendAdminSetting(setting.DangerCheck, checked and 1 or 0)
    end

    local dangerSlider = safetyForm:NumSlider("Danger check radius", "spt_danger_radius", 128, 2048, 0)
    dangerSlider.OnValueChanged = function(_, value)
        if suppressAdminCallbacks then return end
        queueAdminSetting("danger_radius", setting.DangerRadius, math.Round(value))
    end

    local respawnHullToggle = safetyForm:CheckBox("Check hull before respawning", "spt_respawn_hull_check")
    respawnHullToggle.OnChange = function(_, checked)
        if suppressAdminCallbacks then return end
        sendAdminSetting(setting.RespawnHullCheck, checked and 1 or 0)
    end

    local resetBtn = serverForm:Button("Reset server settings")
    resetBtn:SetTooltip("Restores server limits, marker sharing, offsets, and safety checks to defaults.")
    resetBtn.DoClick = function()
        local serverDefaults = SPT.ServerDefaults
        suppressAdminCallbacks = true
        enabledServerToggle:SetValue(serverDefaults.Enabled)
        markerCombo:SetValue("Own markers only")
        setSliderValue(maxSlider, serverDefaults.MaxSpawns)
        setSliderValue(offsetSlider, serverDefaults.SpawnOffset)
        setSliderValue(radiusSlider, serverDefaults.DeleteRadius)
        dangerToggle:SetValue(serverDefaults.DangerCheck)
        setSliderValue(dangerSlider, serverDefaults.DangerRadius)
        respawnHullToggle:SetValue(serverDefaults.RespawnHullCheck)
        suppressAdminCallbacks = false
        sendAdminSetting(setting.ResetDefaults, 0)
    end
end

local function addMaintenance(panel)
    local maintenanceForm = addForm(panel, "Maintenance")
    maintenanceForm:Help("Delete your own respawn points. These actions cannot be undone.")

    addConfirmButton(
        maintenanceForm,
        "Delete current respawn points...",
        "Removes your saved and loaded respawn points for the current gamemode and map.",
        "Delete all of your respawn points for this gamemode and map?",
        SPT.Net.ClearCurrentRequest
    )

    addConfirmButton(
        maintenanceForm,
        "Delete all saved respawn points...",
        "Removes your saved respawn points across every gamemode and map.",
        "Delete all of your saved respawn points across every gamemode and map?",
        SPT.Net.ClearAllRequest
    )
end

local function addAbout(panel)
    local aboutForm = addForm(panel, "About")

    local summary = vgui.Create("DPanel", aboutForm)
    summary:SetTall(76)
    summary:SetPaintBackground(false)
    aboutForm:AddItem(summary)

    local avatar = vgui.Create("AvatarImage", summary)
    avatar:SetSize(64, 64)
    avatar:Dock(LEFT)
    avatar:DockMargin(0, 6, 10, 6)
    avatar:SetSteamID(SPT.AUTHOR_STEAM_ID64, 64)

    local details = vgui.Create("DPanel", summary)
    details:SetPaintBackground(false)
    details:Dock(FILL)
    details:DockMargin(0, 6, 0, 6)

    local title = vgui.Create("DLabel", details)
    title:Dock(TOP)
    title:SetText("Spawn Point Tool")
    title:SetFont("DermaDefaultBold")
    title:SizeToContentsY()

    local version = vgui.Create("DLabel", details)
    version:Dock(TOP)
    version:DockMargin(0, 4, 0, 0)
    version:SetText("Version " .. SPT.VERSION_LABEL)
    version:SizeToContentsY()

    local author = vgui.Create("DLabel", details)
    author:Dock(TOP)
    author:DockMargin(0, 2, 0, 0)
    author:SetText("Created by " .. SPT.AUTHOR)
    author:SizeToContentsY()

    aboutForm:Help("If you like this tool, please consider rating it!")

    addLinkButton(aboutForm, "Workshop Page", SPT.Links.Workshop)
    addLinkButton(aboutForm, "Steam Profile", SPT.Links.SteamProfile)
    addLinkButton(aboutForm, "GitHub Repository", SPT.Links.GitHub)
    addLinkButton(aboutForm, "GitHub Issues", SPT.Links.Issues)
end

function SPT.BuildCPanel(panel)
    addPlayerSettings(panel)
    addAdminSettings(panel)
    addMaintenance(panel)
    addAbout(panel)
end
