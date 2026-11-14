-- MoveMyBags -- the bag windows in Edit Mode.
--
-- A placeholder per bag the addon has seen, through LibEditMode: a plain
-- frame the size the bag's window was last seen at, at its saved position or
-- Blizzard's slot. Dragging one writes the bag's position through the core's
-- API exactly as dragging the window would; "Put back" clears it. Nothing
-- here touches a bag window directly. Why the library and not Blizzard's
-- manager, and why placeholders, is DESIGN.md "Edit Mode". If the library is
-- missing, or an older copy is what LibStub resolves to, this file does
-- nothing and /movemybags status says so.
--
-- The library calls this file relies on, as of the vendored copy (see
-- Libs/LibEditMode/VENDORED.txt):
--
--   * lib:AddFrame(frame, callback, default, name): the frame must be parented
--     to UIParent and movable by StartMoving. The callback is called as
--     (frame, layoutName, point, x, y) after the library has SetPoint-ed the
--     frame, so GetLeft/GetBottom are the truth.
--   * `default` is a table {point, x, y} the library keeps by reference for
--     its own Reset Position button, so it can be updated in place.
--   * lib:RegisterCallback('enter'|'exit'|'layout', fn); 'layout' also fires
--     at login, with the layout's name.
--   * lib:AddFrameSettingsButtons(frame, {{text, click}}).

local _, ns = ...
local L = ns.L
local api = ns.api

local lib                   -- LibEditMode, once found
local placeholders = {}     -- bag key -> placeholder frame
local defaultsByKey = {}    -- bag key -> the {point, x, y} table the library holds
local shown = false         -- placeholders are on screen

-- Separate bags are CONTAINER_WIDTH wide; a placeholder for a bag never seen
-- at any size falls back to this and one row of slots.
local FALLBACK_WIDTH = 178
local FALLBACK_HEIGHT = 110

local function Enabled()
    return lib ~= nil and api.Option("editmode")
end

local function Label(key)
    if key == "combined" then
        return L["Combined bags"]
    end
    if key == 0 then
        return L["Backpack"]
    end
    if key < 0 then
        return L["Keyring"]   -- Classic's KEYRING_CONTAINER is a negative ID
    end
    local reagentFrom = (NUM_BAG_FRAMES or 4) + 1
    if key >= reagentFrom then
        return L["Reagent bag"]
    end
    return L["Bag %d"]:format(key)
end

-- Where a placeholder goes and how big it is: the saved position if there is
-- one, otherwise Blizzard's slot as last seen. Sizes come with whichever is
-- used, scaled the way the window was. Nil when the bag has been seen nowhere.
local function Geometry(key)
    local saved = api.GetPosition(key)
    local slot = api.DefaultSlot(key)
    local source = saved or slot
    if not source then
        return nil
    end
    local sizeFrom = (saved and saved.w and saved) or slot or saved
    local scale = sizeFrom and sizeFrom.s or 1
    local w = (sizeFrom and sizeFrom.w or FALLBACK_WIDTH) * scale
    local h = (sizeFrom and sizeFrom.h or FALLBACK_HEIGHT) * scale
    return source.x, source.y, w, h, slot
end

local function OnMoved(frame)
    -- The library has anchored the frame already; its parent is UIParent at
    -- scale 1, so these are UIParent units, the core's own.
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if left and bottom then
        api.SetPosition(frame.bagKey, left, bottom)
    end
end

local Refresh

local function PutBack(frame)
    api.ClearPosition(frame.bagKey)
    Refresh()
end

local function Placeholder(key)
    local frame = placeholders[key]
    if frame then
        return frame
    end

    local name = "MoveMyBagsKuroEditMode" .. tostring(key)
    frame = CreateFrame("Frame", name, UIParent)
    frame.bagKey = key
    frame:SetFrameStrata("MEDIUM")
    frame:SetClampedToScreen(true)
    frame:SetSize(FALLBACK_WIDTH, FALLBACK_HEIGHT)
    frame:Hide()

    local background = frame:CreateTexture(nil, "BACKGROUND")
    background:SetAllPoints()
    background:SetColorTexture(0, 0, 0, 0.55)

    local label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("CENTER")
    label:SetText(Label(key))
    frame.label = label

    local default = { point = "BOTTOMLEFT", x = 0, y = 0 }
    defaultsByKey[key] = default
    lib:AddFrame(frame, OnMoved, default, "MoveMyBags: " .. Label(key))
    lib:AddFrameSettingsButtons(frame, {
        { text = L["Put back"], click = function() PutBack(frame) end },
    })

    placeholders[key] = frame
    return frame
end

-- Lay every placeholder out from the arrangement as it is now. Called on
-- entering Edit Mode and after a change made from inside it.
Refresh = function()
    if not shown then
        return
    end
    for _, key in ipairs(api.BagKeys()) do
        local x, y, w, h, slot = Geometry(key)
        if x then
            local frame = Placeholder(key)
            local default = defaultsByKey[key]
            if slot then
                default.x, default.y = slot.x, slot.y
            else
                default.x, default.y = x, y
            end
            frame:SetSize(w, h)
            frame:ClearAllPoints()
            frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x, y)
            frame:Show()
        elseif placeholders[key] then
            placeholders[key]:Hide()
        end
    end
end

local function OnEnter()
    if not Enabled() then
        return
    end
    shown = true
    Refresh()
end

local function OnExit()
    shown = false
    for _, frame in pairs(placeholders) do
        frame:Hide()
    end
end

-- An Edit Mode layout with the same name as one of ours brings ours in with
-- it. Opt-in, because the library fires this at login too: a player who names
-- a layout after an Edit Mode layout is asking for the bags to be reset to
-- that snapshot every time it becomes active, which is the feature, and a
-- surprise to anyone who did not ask for it.
local function OnLayout(layoutName)
    if not Enabled() or not api.Flag("followlayouts") or type(layoutName) ~= "string" then
        return
    end
    for _, name in ipairs(api.LayoutNames()) do
        if name == layoutName then
            api.LoadLayout(name)
            return
        end
    end
end

local function Setup()
    if lib then
        return
    end
    local stub = LibStub
    local found = stub and stub("LibEditMode", true)
    if not found or type(found.AddFrame) ~= "function" or type(found.RegisterCallback) ~= "function" then
        return
    end
    lib = found
    lib:RegisterCallback("enter", OnEnter)
    lib:RegisterCallback("exit", OnExit)
    lib:RegisterCallback("layout", OnLayout)
end

-- For /movemybags status.
ns.EditModeStatus = function()
    if not lib then
        return "library not found; the bag windows are not in Edit Mode"
    end
    if not api.Option("editmode") then
        return "off"
    end
    return "integrated via LibEditMode" .. (lib.hookVersion and (" (minor " .. tostring(lib.hookVersion) .. ")") or "")
        .. (shown and "; editing now" or "")
end

-- A change made elsewhere while Edit Mode is open -- a layout load from the
-- slash command, a reset -- re-lays the placeholders out.
ns.OnArrangementChanged = function()
    if shown then
        Refresh()
    end
end

-- After the database, since Setup reads nothing from it but the callbacks
-- the library may fire immediately ('layout' at login) do.
local previous = ns.OnDatabaseReady
ns.OnDatabaseReady = function()
    if previous then
        previous()
    end
    Setup()
end
