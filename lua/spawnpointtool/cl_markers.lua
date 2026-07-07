if SERVER then return end

SpawnPointTool = SpawnPointTool or {}

local SPT = SpawnPointTool
local MARKER_DRAW_DIST_SQR = 9000000
local LABEL_DRAW_DIST_SQR = 2250000
local markers = {}
local markerMaterial = Material("SpawnPointTool/spawndecal", "smooth")
local markerColor = Color(120, 120, 120, 255)
local otherMarkerColor = Color(95, 135, 175, 255)
local globalMarkerColor = Color(255, 170, 45, 255)
local previewColor = Color(70, 155, 255, 125)
local globalPreviewColor = Color(255, 165, 45, 135)
local blockedPreviewColor = Color(255, 70, 70, 125)
local ownTextColor = Color(235, 235, 235, 245)
local otherTextColor = Color(140, 190, 255, 245)
local globalTextColor = Color(255, 205, 100, 245)
local hudTextColor = Color(235, 235, 235, 240)
local hudAccentColor = Color(70, 155, 255, 240)
local globalHudAccentColor = Color(255, 175, 55, 240)
local hudBackgroundColor = Color(0, 0, 0, 150)
local hadSpawnTool = false
local hadAlwaysShow = false
local hadGlobalMode = false
local lastSyncedGlobalMode

surface.CreateFont("SPT_MarkerLabel", {
    font = "DermaDefaultBold",
    size = 64,
    weight = 800,
    antialias = true
})

surface.CreateFont("SPT_Hud", {
    font = "DermaDefaultBold",
    size = 18,
    weight = 800,
    antialias = true
})

surface.CreateFont("SPT_HudCount", {
    font = "DermaDefaultBold",
    size = 16,
    weight = 700,
    antialias = true
})

net.Receive(SPT.Net.SyncMarkers, function()
    local count = net.ReadUInt(16)
    local nextMarkers = {}

    for i = 1, count do
        local pos = net.ReadVector()
        local normal = net.ReadNormal()
        local own = net.ReadBool()
        local global = net.ReadBool()
        local yaw = net.ReadInt(10)
        local index = net.ReadUInt(16)
        local ownerName = net.ReadString()

        nextMarkers[#nextMarkers + 1] = {
            pos = pos,
            normal = SPT.SanitizeNormal(normal),
            own = own,
            global = global,
            yaw = yaw,
            index = index,
            ownerName = ownerName
        }
    end

    markers = nextMarkers
end)

local function getToolPlayer()
    local ply = LocalPlayer()
    if not IsValid(ply) then return nil end

    local weapon = ply:GetActiveWeapon()
    if not IsValid(weapon) or weapon:GetClass() ~= "gmod_tool" then return nil end

    local tool = ply:GetTool()
    if not tool or tool.Mode ~= "spawnpoint" then return nil end

    return ply
end

local function requestMarkers()
    net.Start(SPT.Net.RequestMarkers)
    net.SendToServer()
end

local function shouldAlwaysShowMarkers()
    local convar = GetConVar("spawnpoint_always_show")
    return convar and convar:GetBool()
end

local function shouldDrawMarkers()
    return getToolPlayer() ~= nil or shouldAlwaysShowMarkers()
end

local function isGlobalModeEnabled(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return false end

    local stickyConvar = GetConVar("spawnpoint_global_sticky")
    if stickyConvar and stickyConvar:GetBool() then return true end

    local hotkeyConvar = GetConVar("spawnpoint_global_hotkey")
    local hotkey = hotkeyConvar and hotkeyConvar:GetInt() or SPT.ClientDefaults.GlobalHotkey
    hotkey = math.Clamp(hotkey, 0, KEY_COUNT or 107)
    return hotkey > 0 and input.IsKeyDown(hotkey)
end

local function syncGlobalMode(ply, active)
    local globalMode = active and isGlobalModeEnabled(ply) or false
    if globalMode ~= lastSyncedGlobalMode then
        RunConsoleCommand("spawnpoint_global_mode", globalMode and "1" or "0")
        lastSyncedGlobalMode = globalMode

        if active then
            timer.Simple(0.1, function()
                if getToolPlayer() then
                    requestMarkers()
                end
            end)
        end
    end

    return globalMode
end

local function getSyncedGlobalMode(ply)
    if not IsValid(ply) or not ply:IsAdmin() then return false end

    local convar = GetConVar("spawnpoint_global_mode")
    return convar and convar:GetBool()
end

local function getMarkerColor(pos, marker)
    local light = render.GetLightColor(pos)
    local level = math.Clamp(math.max(light.x, light.y, light.z), 0.1, 0.45)
    local value = math.floor(85 + level * 90)

    if marker.global then
        return Color(value, math.floor(value * 0.7), math.floor(value * 0.18), globalMarkerColor.a)
    end

    if marker.own then
        return Color(value, value, value, markerColor.a)
    end

    return Color(math.floor(value * 0.65), math.floor(value * 0.85), value, otherMarkerColor.a)
end

local function getTraceNormal(trace)
    local normal = trace and trace.HitNormal
    if not normal or normal:IsZero() then return Vector(0, 0, 1) end
    return normal:GetNormalized()
end

local function getSurfaceAxes(normal, facing)
    local up = facing - normal * facing:Dot(normal)

    if up:IsZero() then
        up = Vector(0, 0, 1) - normal * normal.z
    end

    if up:IsZero() then
        up = Vector(1, 0, 0) - normal * normal.x
    end

    up:Normalize()

    local right = up:Cross(normal)
    if right:IsZero() then
        right = normal:Cross(Vector(0, 0, 1))
    end

    right:Normalize()
    return right, up
end

local function drawFacingDecal(pos, normal, facing, size, color)
    local right, up = getSurfaceAxes(normal, facing)
    local half = size * 0.5

    render.DrawQuad(
        pos - right * half + up * half,
        pos + right * half + up * half,
        pos + right * half - up * half,
        pos - right * half - up * half,
        color
    )
end

local function getSpawnOffset()
    local convar = GetConVar("spt_spawn_offset")
    if not convar then return SPT.ServerDefaults.SpawnOffset end
    return math.Clamp(convar:GetFloat(), 0, 32)
end

local function getMaxSpawns()
    local convar = GetConVar("spt_max_spawns")
    if not convar then return SPT.ServerDefaults.MaxSpawns end
    return math.Clamp(convar:GetInt(), 1, 128)
end

local function isPreviewBlocked(ply, pos, normal)
    local convar = GetConVar("spawnpoint_hull_check")
    if not convar or not convar:GetBool() then return false end

    local spawnPos = pos + normal * getSpawnOffset()
    local tr = util.TraceHull({
        start = spawnPos,
        endpos = spawnPos,
        mins = SPT.HULL_MINS,
        maxs = SPT.HULL_MAXS,
        filter = ply,
        mask = MASK_PLAYERSOLID
    })

    return tr.StartSolid or tr.AllSolid or tr.Fraction ~= 1
end

local function drawPreview(ply)
    local trace = ply:GetEyeTrace()
    if not trace or not trace.Hit or trace.HitSky then return end

    local normal = getTraceNormal(trace)
    local pos = trace.HitPos + normal * 0.75
    local globalMode = isGlobalModeEnabled(ply)
    local color = isPreviewBlocked(ply, trace.HitPos, normal) and blockedPreviewColor or (globalMode and globalPreviewColor or previewColor)
    local size = globalMode and 40 or 32

    render.SetMaterial(markerMaterial)
    render.SetBlend(0.45)
    drawFacingDecal(pos, normal, ply:EyeAngles():Forward(), size, color)
    render.SetBlend(1)
end

local function getGlobalMarkerCount()
    local count = 0
    for i = 1, #markers do
        if markers[i].global then
            count = count + 1
        end
    end

    return count
end

local function drawMarkerLabel(ply, marker, pos)
    if ply:GetPos():DistToSqr(pos) > LABEL_DRAW_DIST_SQR then return end

    local textPos = pos + Vector(0, 0, marker.global and 28 or 22)
    local textAng = EyeAngles()
    textAng:RotateAroundAxis(textAng:Forward(), 90)
    textAng:RotateAroundAxis(textAng:Right(), 90)
    local color = marker.own and ownTextColor or otherTextColor
    local text = string.format("%s %d/%d", marker.ownerName or "Player", marker.index or 1, getMaxSpawns())

    if marker.global then
        color = globalTextColor
        text = string.format("Global %d/%d", marker.index or 1, math.max(getGlobalMarkerCount(), 1))
    end

    cam.Start3D2D(textPos, textAng, 0.05)
        draw.SimpleTextOutlined(text, "SPT_MarkerLabel", 0, 0, color, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER, 4, color_black)
    cam.End3D2D()
end

hook.Add("PostDrawTranslucentRenderables", "spt_draw_markers", function(depth, skybox)
    if depth or skybox then return end

    local ply = getToolPlayer()
    if not ply and shouldAlwaysShowMarkers() then
        ply = LocalPlayer()
    end
    if not IsValid(ply) or not shouldDrawMarkers() then return end
    if not markerMaterial or markerMaterial:IsError() then return end

    render.SetMaterial(markerMaterial)

    for i = 1, #markers do
        local marker = markers[i]
        local pos = marker.pos + marker.normal * 0.5
        if ply:GetPos():DistToSqr(pos) <= MARKER_DRAW_DIST_SQR then
            render.SetMaterial(markerMaterial)
            drawFacingDecal(pos, marker.normal, Angle(0, marker.yaw or 0, 0):Forward(), marker.global and 40 or 32, getMarkerColor(pos, marker))
            drawMarkerLabel(ply, marker, pos)
        end
    end

    if getToolPlayer() then
        drawPreview(ply)
    end
end)

hook.Add("Think", "spt_request_markers_on_tool_select", function()
    local ply = getToolPlayer()
    local active = ply ~= nil
    local alwaysShow = shouldAlwaysShowMarkers()
    local globalMode = syncGlobalMode(LocalPlayer(), active)
    if (active and not hadSpawnTool) or (alwaysShow and not hadAlwaysShow) or (active and globalMode ~= hadGlobalMode) then
        requestMarkers()
    end

    if not active and not alwaysShow and hadAlwaysShow then
        markers = {}
    end

    hadSpawnTool = active
    hadAlwaysShow = alwaysShow
    hadGlobalMode = globalMode
end)

hook.Add("HUDPaint", "spt_draw_hud_count", function()
    local ply = getToolPlayer()
    if not ply then return end

    local ownCount = 0
    for i = 1, #markers do
        if markers[i].own then
            ownCount = ownCount + 1
        end
    end

    local globalMode = getSyncedGlobalMode(ply)
    local maxCount = getMaxSpawns()
    local title = "Spawn Point Tool"
    local text = string.format("Respawn points: %d/%d", ownCount, maxCount)
    local accentColor = hudAccentColor

    if globalMode then
        text = string.format("Global respawn points: %d/%d", getGlobalMarkerCount(), maxCount)
        accentColor = globalHudAccentColor
    end

    local x = ScrW() * 0.5
    local y = ScrH() - 115
    surface.SetFont("SPT_Hud")
    local titleW = surface.GetTextSize(title)
    surface.SetFont("SPT_HudCount")
    local countW = surface.GetTextSize(text)
    local w = math.max(titleW, countW) + 64
    local h = 48

    draw.RoundedBox(6, x - w * 0.5, y - h * 0.5, w, h, hudBackgroundColor)
    draw.SimpleText(title, "SPT_Hud", x, y - 7, accentColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(text, "SPT_HudCount", x, y + 7, hudTextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)
