if SERVER then return end

hook.Add("AddToolMenuCategories", "spt_add_category", function()
    if not spawnmenu then return end
    spawnmenu.AddToolCategory("Main", "RespawnTool", "Respawn Point Tool")
end)

local HULL_MINS = Vector(-16, -16, 0)
local HULL_MAXS = Vector(16, 16, 72)
local MARKER_DRAW_DIST_SQR = 9000000
local LABEL_DRAW_DIST_SQR = 2250000
local markers = {}
local markerMaterial = Material("SpawnPointTool/spawndecal", "smooth")
local markerColor = Color(120, 120, 120, 255)
local otherMarkerColor = Color(95, 135, 175, 255)
local previewColor = Color(70, 155, 255, 125)
local blockedPreviewColor = Color(255, 70, 70, 125)
local ownTextColor = Color(235, 235, 235, 245)
local otherTextColor = Color(140, 190, 255, 245)
local hudTextColor = Color(235, 235, 235, 240)
local hudAccentColor = Color(70, 155, 255, 240)
local hudBackgroundColor = Color(0, 0, 0, 150)
local hadSpawnTool = false
local hadAlwaysShow = false

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

net.Receive("spt_sync_markers", function()
    local count = net.ReadUInt(16)
    local nextMarkers = {}

    for i = 1, count do
        local pos = net.ReadVector()
        local normal = net.ReadVector()
        local own = net.ReadBool()
        local yaw = net.ReadFloat()
        local index = net.ReadUInt(16)
        local ownerName = net.ReadString()

        if normal:IsZero() then
            normal = Vector(0, 0, 1)
        else
            normal:Normalize()
        end

        nextMarkers[#nextMarkers + 1] = {
            pos = pos,
            normal = normal,
            own = own,
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
    net.Start("spt_request_markers")
    net.SendToServer()
end

local function shouldAlwaysShowMarkers()
    local convar = GetConVar("spawnpoint_always_show")
    return convar and convar:GetBool()
end

local function shouldDrawMarkers()
    return getToolPlayer() ~= nil or shouldAlwaysShowMarkers()
end

local function getMarkerColor(pos, own)
    local light = render.GetLightColor(pos)
    local level = math.Clamp(math.max(light.x, light.y, light.z), 0.1, 0.45)
    local value = math.floor(85 + level * 90)
    local color = own and markerColor or otherMarkerColor

    color.r = own and value or math.floor(value * 0.65)
    color.g = own and value or math.floor(value * 0.85)
    color.b = own and value or value
    return color
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
    if not convar then return 8 end
    return math.Clamp(convar:GetFloat(), 0, 32)
end

local function getMaxSpawns()
    local convar = GetConVar("spt_max_spawns")
    if not convar then return 32 end
    return math.Clamp(convar:GetInt(), 1, 128)
end

local function isPreviewBlocked(ply, pos, normal)
    if not GetConVar("spawnpoint_hull_check") or not GetConVar("spawnpoint_hull_check"):GetBool() then return false end

    local spawnPos = pos + normal * getSpawnOffset()
    local tr = util.TraceHull({
        start = spawnPos,
        endpos = spawnPos,
        mins = HULL_MINS,
        maxs = HULL_MAXS,
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
    local color = isPreviewBlocked(ply, trace.HitPos, normal) and blockedPreviewColor or previewColor

    render.SetMaterial(markerMaterial)
    render.SetBlend(0.45)
    drawFacingDecal(pos, normal, ply:EyeAngles():Forward(), 32, color)
    render.SetBlend(1)
end

local function drawMarkerLabel(ply, marker, pos)
    if ply:GetPos():DistToSqr(pos) > LABEL_DRAW_DIST_SQR then return end

    local textPos = pos + Vector(0, 0, 22)
    local textAng = EyeAngles()
    textAng:RotateAroundAxis(textAng:Forward(), 90)
    textAng:RotateAroundAxis(textAng:Right(), 90)
    local color = marker.own and ownTextColor or otherTextColor
    local text = string.format("%s %d/%d", marker.ownerName or "Player", marker.index or 1, getMaxSpawns())

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
            drawFacingDecal(pos, marker.normal, Angle(0, marker.yaw or 0, 0):Forward(), 32, getMarkerColor(pos, marker.own))
            drawMarkerLabel(ply, marker, pos)
        end
    end

    if getToolPlayer() then
        drawPreview(ply)
    end
end)

hook.Add("Think", "spt_request_markers_on_tool_select", function()
    local active = getToolPlayer() ~= nil
    local alwaysShow = shouldAlwaysShowMarkers()
    if (active and not hadSpawnTool) or (alwaysShow and not hadAlwaysShow) then
        requestMarkers()
    end

    if not active and not alwaysShow and hadAlwaysShow then
        markers = {}
    end

    hadSpawnTool = active
    hadAlwaysShow = alwaysShow
end)

hook.Add("HUDPaint", "spt_draw_hud_count", function()
    if not getToolPlayer() then return end

    local ownCount = 0
    for i = 1, #markers do
        if markers[i].own then
            ownCount = ownCount + 1
        end
    end

    local maxCount = getMaxSpawns()
    local title = "Respawn Point Tool"
    local text = string.format("Respawn points: %d/%d", ownCount, maxCount)
    local x = ScrW() * 0.5
    local y = ScrH() - 115
    surface.SetFont("SPT_Hud")
    local titleW = surface.GetTextSize(title)
    surface.SetFont("SPT_HudCount")
    local countW = surface.GetTextSize(text)
    local w = math.max(titleW, countW) + 64
    local h = 48

    draw.RoundedBox(6, x - w * 0.5, y - h * 0.5, w, h, hudBackgroundColor)
    draw.SimpleText(title, "SPT_Hud", x, y - 7, hudAccentColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_BOTTOM)
    draw.SimpleText(text, "SPT_HudCount", x, y + 7, hudTextColor, TEXT_ALIGN_CENTER, TEXT_ALIGN_TOP)
end)
