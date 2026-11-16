-- MoveMyBags.Kuro -- make the open bag windows draggable.
--
-- This file is the addon's lifecycle: it builds the database on load, installs
-- the hooks at login, and reacts to the events that change the arrangement in
-- use. The work is in Core/, one module per concern, loaded ahead of this
-- file in the order the TOC lists them:
--
--   Core/Util.lua      shared state, the failure guard, the frame helpers
--   Core/Storage.lua   the database: contexts, layouts, the per-character
--                      arrangement, resets, the per-bag position API
--   Core/Layers.lua    one window per layer, the active one on top
--   Core/Layout.lua    the flush: snapshot, compaction, settling, override
--   Core/Drag.lua      the drag, the gestures, the hooks on Blizzard's windows
--   Core/Commands.lua  the slash commands and the status report
--
-- Everything the design rests on, and every fact about Blizzard's code it was
-- checked against, is in DESIGN.md; tools/check-api-contract.sh asserts those
-- facts against the live UI source for each flavour, so this comment does not
-- repeat them. The three rules that carry the addon are short enough to keep
-- here: never replace a Blizzard global, never call back into one, never do
-- layout work inside Blizzard's call stack.

local ADDON, ns = ...

local core = ns.core
local S = ns.state

local Guarded = core.Guarded
local Request = core.Request
local SelectContext = core.SelectContext
local ParkOnDefaults = core.ParkOnDefaults
local AttachAll = core.AttachAll
local HookLayout = core.HookLayout

--------------------------------------------------------------------------
-- api for the other files
--------------------------------------------------------------------------

-- What Options.lua and EditMode.lua build on. Small on purpose: the panel,
-- the keybinding, the compartment entry and the Edit Mode placeholders are
-- conveniences over these, never a second way of doing anything.
ns.api = {
    IsReady = function() return S.pos ~= nil end,
    IsLocked = core.Locked,
    SetLocked = core.SetLocked,
    ResetAll = core.ResetAll,
    ResetContext = core.ResetContext,
    Request = Request,
    Option = core.Option,
    Flag = core.Flag,
    IsOwn = core.IsOwn,
    SetOwn = core.SetOwn,
    SaveLayout = core.SaveLayout,
    LoadLayout = core.LoadLayout,
    DeleteLayout = core.DeleteLayout,
    LayoutNames = core.LayoutNames,
    Context = function() return S.context end,
    BagKeys = core.BagKeys,
    GetPosition = core.GetPosition,
    SetPosition = core.SetPosition,
    ClearPosition = core.ClearPosition,
    DefaultSlot = core.DefaultSlot,
}

--------------------------------------------------------------------------
-- lifecycle
--------------------------------------------------------------------------

-- The bank and the merchant both open the bags on show, which runs the
-- layout pass and so the flush, and close them on hide. These cover the case
-- where the bags were already open and the pass did not fire: the context
-- has still changed, and the arrangement has to follow it.
local CONTEXT_EVENTS = {
    BANKFRAME_OPENED = true,
    BANKFRAME_CLOSED = true,
    MERCHANT_SHOW = true,
    MERCHANT_CLOSED = true,
}

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:RegisterEvent("PLAYER_LOGIN")
loader:RegisterEvent("PLAYER_REGEN_ENABLED")
loader:RegisterEvent("UI_SCALE_CHANGED")
loader:RegisterEvent("DISPLAY_SIZE_CHANGED")
for event in pairs(CONTEXT_EVENTS) do
    loader:RegisterEvent(event)
end
loader:SetScript("OnEvent", Guarded(function(self, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON then
            return
        end
        core.InitDB()
        self:UnregisterEvent("ADDON_LOADED")
        -- Options.lua registers its Settings against the database, so it
        -- waits for this rather than for the event itself.
        if ns.OnDatabaseReady then
            ns.OnDatabaseReady()
        end
    elseif event == "PLAYER_LOGIN" then
        if HookLayout() then
            S.gapsUnavailable = false   -- was only ever set for want of the hook
        end
        AttachAll()
    elseif CONTEXT_EVENTS[event] then
        -- A context change, not a layout change: the geometry still holds.
        -- The flush parks nothing itself, so windows moved in the context we
        -- are leaving go back to Blizzard's slots here, the way a layout load
        -- does, and the flush then places whatever the new context saves.
        -- Parked *before* the context is re-selected: `S.pos` still reads the
        -- arrangement being left, which is the one that says what moved.
        if S.pos then
            ParkOnDefaults()
        end
        SelectContext()
        Request()
    else
        -- Scale and resolution changes invalidate clamping; regen flushes
        -- anything queued while the layout was in flux.
        if event ~= "PLAYER_REGEN_ENABLED" then
            -- They also invalidate the column geometry, which is measured in
            -- UIParent units: geoSpacing is the spacing constant at the *old*
            -- scale and geoFreeHeight derives from the old GetScreenHeight(), so
            -- re-flowing from either now would misplace the column. The flush
            -- re-opens it instead, and Blizzard's next layout pass re-measures.
            S.geoValid = false
        end
        AttachAll()
        Request()
    end
end))
