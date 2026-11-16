-- MoveMyBags.Kuro -- the product surface: the Settings panel category, the
-- keybinding, and the addon-compartment entry.
--
-- Everything here is optional to the addon working. The defaults match what
-- the addon did before any of this existed, so a player who never opens the
-- panel gets the zero-config behaviour, and a client without the Settings API
-- gets the addon without a panel rather than an error.
--
-- Verified against Blizzard's 12.1.0 (build 69933) UI source:
--
--   * Settings.RegisterAddOnSetting(category, variable, variableKey,
--     variableTbl, variableType, name, defaultValue) writes straight to the
--     saved-variable table and default-initialises the key if it is nil
--     (Blizzard_Settings_Shared/Blizzard_ImplementationReadme.lua).
--   * setting:SetValueChangedCallback(fn) is how a change is applied.
--   * A button in a vertical layout is CreateSettingsButtonInitializer plus
--     layout:AddInitializer (Blizzard_SettingControls.lua).
--   * The addon compartment calls the global named by AddonCompartmentFunc
--     with (addonName, buttonName), and the OnEnter/OnLeave globals with
--     (addonName, button) (Blizzard_Minimap/Mainline/AddonCompartment.lua).
--   * A Bindings.xml entry's category attribute names a global string for its
--     header (Blizzard_PingUI/Bindings.xml).

local ADDON, ns = ...
local L = ns.L
local api = ns.api

local PREFIX = "|cff33ff99MoveMyBags.Kuro|r: "
local COMMAND = "|cffffff78%s|r"

local PROJECT_URL = "https://github.com/WoWAddons-Kuro/MoveMyBags"

-- A popup whose edit box holds the project URL, selected, so Ctrl+C copies
-- it. The text is pinned: typing over it puts the URL straight back.
if StaticPopupDialogs then
    StaticPopupDialogs["MOVEMYBAGSKURO_PROJECT_URL"] = {
        text = "MoveMyBags.Kuro -- " .. (ns.L["Press Ctrl+C to copy the project URL"]),
        button1 = CLOSE or "Close",
        hasEditBox = true,
        editBoxWidth = 360,
        OnShow = function(self)
            local box = self.editBox or self.EditBox
            box:SetText(PROJECT_URL)
            box:HighlightText()
            box:SetFocus()
        end,
        EditBoxOnTextChanged = function(box)
            if box:GetText() ~= PROJECT_URL then
                box:SetText(PROJECT_URL)
                box:HighlightText()
            end
        end,
        EditBoxOnEscapePressed = function(box) box:GetParent():Hide() end,
        EditBoxOnEnterPressed = function(box) box:GetParent():Hide() end,
        timeout = 0,
        whileDead = true,
        hideOnEscape = true,
        preferredIndex = 3,
    }
end

local function Print(msg)
    print(PREFIX .. msg)
end

--------------------------------------------------------------------------
-- keybinding
--------------------------------------------------------------------------

BINDING_HEADER_MOVEMYBAGSKURO = "MoveMyBags.Kuro"
BINDING_NAME_MoveMyBagsKuro_TOGGLE_LOCK = L["Lock or unlock bag windows"]

-- Global, because Bindings.xml and the compartment call it by name. Prints
-- the new state, since a keybind gives no other feedback.
function MoveMyBagsKuro_ToggleLock()
    if not api.IsReady() then
        return
    end
    local locked = api.SetLocked(not api.IsLocked())
    if locked then
        Print(L["bags locked. %s to move them again."]:format(COMMAND:format("/mmbk unlock")))
    else
        Print(L["bags unlocked."])
    end
end

--------------------------------------------------------------------------
-- settings panel
--------------------------------------------------------------------------

local category

-- The Settings API arrived in 10.0 and gained these signatures in 11.0.2. An
-- older client, or one where Blizzard_Settings_Shared has not loaded, simply
-- gets no panel: everything the panel controls is also a slash command.
local function HaveSettingsAPI()
    return type(Settings) == "table"
        and type(Settings.RegisterVerticalLayoutCategory) == "function"
        and type(Settings.RegisterAddOnSetting) == "function"
        and type(Settings.CreateCheckbox) == "function"
        and type(Settings.RegisterAddOnCategory) == "function"
end

local function AddCheckbox(variableKey, name, tooltip, default, onChanged)
    local setting = Settings.RegisterAddOnSetting(category, "MoveMyBagsKuro_" .. variableKey:upper(),
        variableKey, MoveMyBagsKuroDB, Settings.VarType.Boolean, name, default)
    if onChanged then
        setting:SetValueChangedCallback(function(_, value)
            onChanged(value)
        end)
    end
    Settings.CreateCheckbox(category, setting, tooltip)
    return setting
end

-- Runs once the database exists; the settings write straight into it.
local function RegisterSettings()
    if category or not HaveSettingsAPI() then
        return
    end

    local layout
    category, layout = Settings.RegisterVerticalLayoutCategory("MoveMyBags.Kuro")

    -- Kuro: the lock and Follow layouts default to on, so the bags are
    -- arranged in Edit Mode and nowhere else unless the player opts out; the
    -- behaviour toggles default to on as they always did, and only the
    -- per-character flag defaults to off. All are plain booleans, written
    -- here and read by the core on every pass: in MoveMyBagsKuroDB, except
    -- the per-character flag.
    AddCheckbox("locked", L["Lock bag windows"],
        L["Stops bag windows being dragged. Saved positions still apply, and the resets still work."],
        Settings.Default.True, function(value)
            api.SetLocked(value)
        end)
    AddCheckbox("snap", L["Connect windows while dragging"],
        L["A window you drag clicks flush against its neighbours and slides around them instead of over them. "
            .. "Off, it goes exactly where the cursor puts it."],
        Settings.Default.True, function()
            api.Request()
        end)
    AddCheckbox("compact", L["Close the hole a moved bag leaves"],
        L["The column closes up around a bag you drag out of it, and re-opens when you put it back. "
            .. "Off, Blizzard's column is left exactly as it is."],
        Settings.Default.True, function()
            api.Request()
        end)
    AddCheckbox("layers", L["Keep the window you are using in front"],
        L["Each window sits on its own layer, and the one you pick up or click comes to the front. "
            .. "Off, the windows are drawn in whatever order the client has them."],
        Settings.Default.True, function()
            api.Request()
        end)
    AddCheckbox("contexts", L["Separate arrangements at the bank and at a merchant"],
        L["Blizzard lays the bags out differently beside the bank, and both the bank and a merchant open every bag. "
            .. "On, each place remembers its own arrangement once you move a bag there, and follows your usual one "
            .. "until you do. Off, one arrangement is used everywhere."],
        Settings.Default.True, function()
            api.Request()
        end)

    AddCheckbox("editmode", L["Show the bag windows in Edit Mode"],
        L["A placeholder for each bag appears in Edit Mode, at the bag's position, and can be dragged like any other "
            .. "part of the UI. Off, Edit Mode leaves the bags alone."],
        Settings.Default.True, function()
            api.Request()
        end)
    local followDefault = false
    local follow = Settings.RegisterAddOnSetting(category, "MoveMyBagsKuro_FOLLOWLAYOUTS", "followlayouts",
        MoveMyBagsKuroDB, Settings.VarType.Boolean, L["Follow Edit Mode layouts"], followDefault)
    Settings.CreateCheckbox(category, follow,
        L["When an Edit Mode layout becomes active, including at login, a MoveMyBags.Kuro layout with the same name is "
            .. "loaded. Save one with /mmbk save <name>. Off, Edit Mode layouts and bag arrangements are "
            .. "unrelated."])

    -- Per character, so it lives in the per-character saved variables.
    local own = Settings.RegisterAddOnSetting(category, "MoveMyBagsKuro_OWN", "own", MoveMyBagsKuroCharDB,
        Settings.VarType.Boolean, L["This character keeps its own arrangement"], Settings.Default.False)
    own:SetValueChangedCallback(function(_, value)
        api.SetOwn(value)
    end)
    Settings.CreateCheckbox(category, own,
        L["Starts from a copy of the account-wide arrangement, and from then on this character's bags are arranged "
            .. "on their own. Off, the account-wide arrangement is used; this character's is kept for next time."])

    if type(CreateSettingsButtonInitializer) == "function" and layout and layout.AddInitializer then
        local addSearchTags = true
        layout:AddInitializer(CreateSettingsButtonInitializer(L["Reset positions"],
            L["Put every bag window back"], function()
                api.ResetAll()
                Print(L["all bag positions reset, in every context."])
            end,
            L["Every window returns to Blizzard's own slot, in every context and both bag modes. "
                .. "Shift-right-click a window to put just that one back."],
            addSearchTags))

        -- The project page. Settings has no link control, so the button opens
        -- a popup with the URL selected in an edit box, ready for Ctrl+C.
        layout:AddInitializer(CreateSettingsButtonInitializer(L["Project page"],
            L["Copy GitHub URL"], function()
                if StaticPopup_Show then
                    StaticPopup_Show("MOVEMYBAGSKURO_PROJECT_URL")
                else
                    Print(PROJECT_URL)
                end
            end,
            PROJECT_URL,
            addSearchTags))
    end

    Settings.RegisterAddOnCategory(category)
end

local function OpenSettings()
    if category and Settings and Settings.OpenToCategory then
        Settings.OpenToCategory(category:GetID())
        return true
    end
    Print(L["options are not available on this client."])
    return false
end

ns.OpenSettings = OpenSettings

-- The core calls this after it has built the database on ADDON_LOADED. Both
-- files are loaded by then, whichever order the events arrive in.
ns.OnDatabaseReady = RegisterSettings

--------------------------------------------------------------------------
-- addon compartment
--------------------------------------------------------------------------

function MoveMyBagsKuro_OnCompartmentClick(_, buttonName)
    if buttonName == "RightButton" then
        MoveMyBagsKuro_ToggleLock()
    else
        OpenSettings()
    end
end

function MoveMyBagsKuro_OnCompartmentEnter(_, button)
    if not GameTooltip then
        return
    end
    GameTooltip:SetOwner(button, "ANCHOR_LEFT")
    GameTooltip:SetText("MoveMyBags.Kuro")
    if api.IsReady() then
        GameTooltip:AddLine(api.IsLocked() and L["Windows are locked"] or L["Windows are unlocked"], 1, 1, 1)
    end
    GameTooltip:AddLine(L["Left-click: options. Right-click: lock or unlock."], 0.8, 0.8, 0.8, true)
    GameTooltip:AddLine(L["Drag a window by its frame to move it, or Shift-drag its title bar. "
        .. "Shift-right-click a window to put it back."], 0.8, 0.8, 0.8, true)
    GameTooltip:Show()
end

function MoveMyBagsKuro_OnCompartmentLeave()
    if GameTooltip then
        GameTooltip:Hide()
    end
end

-- Not strictly needed, but it keeps luacheck honest about what this file
-- defines and lets a test confirm the name the TOC points at exists.
ns.compartment = {
    click = MoveMyBagsKuro_OnCompartmentClick,
    enter = MoveMyBagsKuro_OnCompartmentEnter,
    leave = MoveMyBagsKuro_OnCompartmentLeave,
    addon = ADDON,
}
