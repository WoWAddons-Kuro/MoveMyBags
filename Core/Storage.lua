-- MoveMyBags -- the database: contexts, named layouts, the per-character
-- arrangement, resets, and the per-bag position API.

local _, ns = ...

local core = ns.core
local S = ns.state

local Containers = core.Containers
local FrameKey = core.FrameKey
local Place = core.Place
local Clamp = core.Clamp
local Request = core.Request
local Option = core.Option
local COMBINED_KEY = core.COMBINED_KEY

local _G = _G
local wipe = wipe

local DB_VERSION = 2   -- 2: positions per context, named layouts, per-character arrangement

--------------------------------------------------------------------------
-- contexts and storage
--------------------------------------------------------------------------

-- Positions are kept per context: "default", "bank" (BankFrame shown) or
-- "merchant" (MerchantFrame shown). A context follows the default arrangement
-- until the first move in it, which copies the default; from then on it is
-- its own, and a reset there forgets the copy. The arrangement -- every
-- context together -- is account-wide unless this character keeps its own
-- (MoveMyBagsKuroCharDB.own), and can be snapshotted under a name and loaded back
-- (MoveMyBagsKuroDB.layouts). Why contexts, and why copy-on-first-write, is
-- DESIGN.md "Contexts, layouts and the per-character arrangement".
local CONTEXT_DEFAULT = "default"
local CONTEXT_BANK = "bank"
local CONTEXT_MERCHANT = "merchant"
core.CONTEXT_DEFAULT = CONTEXT_DEFAULT

S.context = CONTEXT_DEFAULT   -- the context the current pass is in
S.pos = nil                   -- its positions, as read; nil until ADDON_LOADED

-- Whether this character's own arrangement is the one in use. Kept here as
-- well as in MoveMyBagsKuroCharDB.own because the Settings panel writes the saved
-- flag *before* it tells us, and the switch-over has to park the windows
-- under the arrangement being left -- which by then the flag no longer names.
S.ownInUse = false

-- The contexts table in use: this character's, or the account's.
local function Contexts()
    if S.ownInUse and MoveMyBagsKuroCharDB and MoveMyBagsKuroCharDB.positions then
        return MoveMyBagsKuroCharDB.positions
    end
    return MoveMyBagsKuroDB and MoveMyBagsKuroDB.positions
end
core.Contexts = Contexts

-- Looked up by name on each call rather than captured, so a client without
-- one of these frames, or with a bag addon that replaced it, reads as "not
-- shown" rather than erroring at load.
local function FrameShown(name)
    local frame = _G[name]
    return frame ~= nil and frame.IsShown ~= nil and frame:IsShown() == true
end

local function CurrentContext()
    if not Option("contexts") then
        return CONTEXT_DEFAULT
    end
    if FrameShown("BankFrame") then
        return CONTEXT_BANK
    end
    if FrameShown("MerchantFrame") then
        return CONTEXT_MERCHANT
    end
    return CONTEXT_DEFAULT
end

-- Point `S.pos` at the positions this pass reads. False before the database
-- exists. Called at the start of anything that reads or writes a position,
-- since the context can change between two passes.
local function SelectContext()
    local contexts = Contexts()
    if not contexts then
        S.pos = nil
        return false
    end
    S.context = CurrentContext()
    S.pos = contexts[S.context] or contexts[CONTEXT_DEFAULT]
    return true
end
core.SelectContext = SelectContext

local function CopyPositions(from, into)
    for key, p in pairs(from) do
        into[key] = { x = p.x, y = p.y, h = p.h, w = p.w, s = p.s }
    end
    return into
end

local function CopyContexts(from, into)
    for ctx, flat in pairs(from) do
        into[ctx] = CopyPositions(flat, {})
    end
    into[CONTEXT_DEFAULT] = into[CONTEXT_DEFAULT] or {}
    return into
end

-- The positions this pass may write: the context's own table, created as a
-- copy of the default arrangement the first time a context is written to.
-- Every write goes through here; `S.pos` may be the default table borrowed by
-- a context that is still following it.
local function WritablePositions()
    local contexts = Contexts()
    local own = contexts[S.context]
    if not own then
        own = CopyPositions(contexts[CONTEXT_DEFAULT], {})
        contexts[S.context] = own
    end
    S.pos = own
    return own
end
core.WritablePositions = WritablePositions

function core.ContextIsOwn()
    local contexts = Contexts()
    return contexts ~= nil and contexts[S.context] ~= nil
end

-- Anything standing in for the windows elsewhere (the Edit Mode
-- placeholders) re-reads the arrangement after a change made outside it.
local function NotifyArrangement()
    if ns.OnArrangementChanged then
        ns.OnArrangementChanged()
    end
end

-- A window we stood down on never gets a saved position applied, even if one is
-- left over in the database from before Blizzard took the job over.
local function SavedFor(frame)
    if frame.moveMyBags ~= "attached" then
        return nil
    end
    return S.pos[FrameKey(frame)]
end
core.SavedFor = SavedFor

-- Put one bag back where Blizzard's last layout pass wanted it. Blizzard keeps
-- laying out moved bags in the column as though they never left, so the
-- remembered slot is the gap the bag came out of -- no restack needed, and no
-- call into Blizzard's layout code from our tainted path.
local function ResetFrame(frame)
    local key = FrameKey(frame)
    if not S.pos or not S.pos[key] then
        return false
    end
    WritablePositions()[key] = nil
    local d = S.defaults[key]
    if d and frame:IsShown() then
        Place(frame, Clamp(frame, d.x, d.y))
    end
    return true
end
core.ResetFrame = ResetFrame

-- Put every shown window that has a saved position back on Blizzard's slot
-- *without* touching the database. For switching arrangements: the flush only
-- ever moves windows that are saved in the arrangement it is reading, so a
-- window moved under the old arrangement and unsaved in the new one would
-- otherwise stay where the old one left it.
local function ParkOnDefaults()
    for _, frame in ipairs(Containers()) do
        if frame:IsShown() and SavedFor(frame) then
            local d = S.defaults[FrameKey(frame)]
            if d then
                Place(frame, Clamp(frame, d.x, d.y))
            end
        end
    end
end
core.ParkOnDefaults = ParkOnDefaults

--------------------------------------------------------------------------
-- the saved variables
--------------------------------------------------------------------------

-- Drop anything a crash or a hand-edit could have left unusable.
local function ValidatePositions(flat)
    for key, p in pairs(flat) do
        if type(p) ~= "table" or type(p.x) ~= "number" or type(p.y) ~= "number" then
            flat[key] = nil
        else
            -- The position is still good; just forget a size that is not one.
            for _, field in ipairs({ "h", "w", "s" }) do
                if p[field] ~= nil and type(p[field]) ~= "number" then
                    p[field] = nil
                end
            end
        end
    end
end

-- A contexts table: context name -> positions. The default context always
-- exists, so a read has somewhere to fall back to.
local function ValidateContexts(contexts)
    for ctx, flat in pairs(contexts) do
        if type(ctx) ~= "string" or type(flat) ~= "table" then
            contexts[ctx] = nil
        else
            ValidatePositions(flat)
        end
    end
    if type(contexts[CONTEXT_DEFAULT]) ~= "table" then
        contexts[CONTEXT_DEFAULT] = {}
    end
end

function core.InitDB()
    MoveMyBagsKuroDB = MoveMyBagsKuroDB or {}
    MoveMyBagsKuroDB.closeGaps = nil   -- the 1.0 toggle; "compact" below replaced it
    -- A real boolean, since the Settings checkbox stores one and the two must
    -- agree. Databases from before stored true-or-nil; nil reads as false.
    MoveMyBagsKuroDB.locked = MoveMyBagsKuroDB.locked == true
    -- The behaviour toggles are true, false or absent; anything else is a
    -- hand-edit and reads as the default.
    for _, key in ipairs({ "snap", "compact", "layers", "contexts", "editmode", "followlayouts" }) do
        if type(MoveMyBagsKuroDB[key]) ~= "boolean" then
            MoveMyBagsKuroDB[key] = nil
        end
    end

    -- Version 1 kept one flat table of positions. Version 2 keeps one per
    -- context, so the old table becomes the default context, unchanged.
    if type(MoveMyBagsKuroDB.positions) ~= "table" then
        MoveMyBagsKuroDB.positions = {}
    end
    if (tonumber(MoveMyBagsKuroDB.version) or 1) < 2 then
        MoveMyBagsKuroDB.positions = { [CONTEXT_DEFAULT] = MoveMyBagsKuroDB.positions }
    end
    MoveMyBagsKuroDB.version = DB_VERSION
    ValidateContexts(MoveMyBagsKuroDB.positions)

    if type(MoveMyBagsKuroDB.layouts) ~= "table" then
        MoveMyBagsKuroDB.layouts = {}
    end
    for name, layout in pairs(MoveMyBagsKuroDB.layouts) do
        if type(name) ~= "string" or type(layout) ~= "table" then
            MoveMyBagsKuroDB.layouts[name] = nil
        else
            ValidateContexts(layout)
        end
    end

    -- This character's own arrangement, used only while `own` is set. Kept
    -- while it is off, so switching back brings the arrangement back.
    MoveMyBagsKuroCharDB = MoveMyBagsKuroCharDB or {}
    MoveMyBagsKuroCharDB.own = MoveMyBagsKuroCharDB.own == true
    if type(MoveMyBagsKuroCharDB.positions) ~= "table" then
        MoveMyBagsKuroCharDB.positions = {}
    end
    ValidateContexts(MoveMyBagsKuroCharDB.positions)
    S.ownInUse = MoveMyBagsKuroCharDB.own

    SelectContext()
end

--------------------------------------------------------------------------
-- resets
--------------------------------------------------------------------------

-- Forget this context's arrangement. The frames on screen are put back where
-- Blizzard's last layout had them, and the next pass re-opens the column. In
-- the default context that clears the positions; in any other it forgets the
-- context's own copy, so it goes back to following the default.
function core.ResetContext()
    if not SelectContext() then
        return
    end
    for _, frame in ipairs(Containers()) do
        ResetFrame(frame)
    end
    local contexts = Contexts()
    if S.context == CONTEXT_DEFAULT then
        wipe(contexts[CONTEXT_DEFAULT])
    else
        contexts[S.context] = nil
    end
    SelectContext()
    NotifyArrangement()
    Request()
end

-- Forget every context's arrangement.
function core.ResetAll()
    if not SelectContext() then
        return
    end
    for _, frame in ipairs(Containers()) do
        ResetFrame(frame)
    end
    local contexts = Contexts()
    for ctx in pairs(contexts) do
        contexts[ctx] = nil
    end
    contexts[CONTEXT_DEFAULT] = {}
    SelectContext()
    NotifyArrangement()
    Request()
end

--------------------------------------------------------------------------
-- named layouts and the per-character arrangement
--------------------------------------------------------------------------

-- A layout is a snapshot of the whole arrangement, every context included,
-- under a name. Saving copies the arrangement in use out; loading copies a
-- snapshot in over it. Neither is live: a layout loaded and then changed
-- has to be saved again to keep the change.
local LAYOUT_NAME_MAX = 32
core.LAYOUT_NAME_MAX = LAYOUT_NAME_MAX

local function LayoutName(name)
    if type(name) ~= "string" then
        return nil
    end
    name = name:gsub("^%s+", ""):gsub("%s+$", "")
    if name == "" or #name > LAYOUT_NAME_MAX then
        return nil
    end
    return name
end
core.LayoutName = LayoutName

function core.SaveLayout(name)
    name = LayoutName(name)
    if not name or not MoveMyBagsKuroDB then
        return nil
    end
    MoveMyBagsKuroDB.layouts[name] = CopyContexts(Contexts(), {})
    return name
end

-- Replaces the arrangement in use with the snapshot. Windows moved under the
-- old arrangement are parked on Blizzard's slots first, so one the snapshot
-- does not mention ends up where the snapshot implies rather than where the
-- old arrangement left it.
function core.LoadLayout(name)
    name = LayoutName(name)
    local layout = name and MoveMyBagsKuroDB and MoveMyBagsKuroDB.layouts[name]
    if not layout or not SelectContext() then
        return nil
    end
    ParkOnDefaults()
    local contexts = Contexts()
    for ctx in pairs(contexts) do
        contexts[ctx] = nil
    end
    CopyContexts(layout, contexts)
    SelectContext()
    NotifyArrangement()
    Request()
    return name
end

function core.DeleteLayout(name)
    name = LayoutName(name)
    if not name or not MoveMyBagsKuroDB or not MoveMyBagsKuroDB.layouts[name] then
        return nil
    end
    MoveMyBagsKuroDB.layouts[name] = nil
    return name
end

function core.LayoutNames()
    local names = {}
    if MoveMyBagsKuroDB then
        for name in pairs(MoveMyBagsKuroDB.layouts) do
            names[#names + 1] = name
        end
    end
    table.sort(names)
    return names
end

local function HasPositions(contexts)
    for _, flat in pairs(contexts) do
        if next(flat) ~= nil then
            return true
        end
    end
    return false
end

function core.IsOwn()
    return S.ownInUse
end

-- Switch this character between the account's arrangement and its own. The
-- first time a character takes its own, it starts from a copy of the
-- account's, which is the arrangement the player is looking at. Switching
-- back keeps the character's copy for next time. Compared against the
-- arrangement in use, not the saved flag: see S.ownInUse.
function core.SetOwn(on)
    on = on == true
    if not MoveMyBagsKuroCharDB then
        return false
    end
    if on == S.ownInUse then
        MoveMyBagsKuroCharDB.own = on
        return S.ownInUse
    end
    if SelectContext() then
        ParkOnDefaults()   -- under the arrangement being left
    end
    if on and not HasPositions(MoveMyBagsKuroCharDB.positions) then
        CopyContexts(MoveMyBagsKuroDB.positions, MoveMyBagsKuroCharDB.positions)
    end
    S.ownInUse = on
    MoveMyBagsKuroCharDB.own = on
    SelectContext()
    NotifyArrangement()
    Request()
    return S.ownInUse
end

local function Locked()
    return MoveMyBagsKuroDB and MoveMyBagsKuroDB.locked == true
end
core.Locked = Locked

-- Saved positions still apply while locked; only dragging is off. The resets
-- stay available, since those take a deliberate modifier or command.
function core.SetLocked(lock)
    if not MoveMyBagsKuroDB then
        return false
    end
    MoveMyBagsKuroDB.locked = lock == true
    return Locked()
end

--------------------------------------------------------------------------
-- positions by key, for Edit Mode
--------------------------------------------------------------------------

-- The bag keys a window can carry: the backpack, the held bags, the reagent
-- bag where the client has one, the keyring where it has that (Classic, a
-- negative ID), and the combined window where it exists. Read from Blizzard's
-- constants; the fallback is four held bags.
local bagKeys = {}

function core.BagKeys()
    wipe(bagKeys)
    local last = NUM_TOTAL_BAG_FRAMES or NUM_BAG_FRAMES or 4
    for key = 0, last do
        bagKeys[#bagKeys + 1] = key
    end
    if type(KEYRING_CONTAINER) == "number" then
        bagKeys[#bagKeys + 1] = KEYRING_CONTAINER
    end
    if ContainerFrameCombinedBags then
        bagKeys[#bagKeys + 1] = COMBINED_KEY
    end
    return bagKeys
end

-- The three below act on the *default* context of the arrangement in use,
-- whatever context the player is in: Edit Mode arranges the field, not the
-- bank. They are the only way anything outside the core writes a position.
function core.GetPosition(key)
    local contexts = Contexts()
    return contexts and contexts[CONTEXT_DEFAULT][key] or nil
end

function core.SetPosition(key, x, y)
    local contexts = Contexts()
    if not contexts then
        return false
    end
    local flat = contexts[CONTEXT_DEFAULT]
    local saved = flat[key]
    if not saved then
        saved = {}
        flat[key] = saved
        -- The window's own size, from wherever it was last seen, so a restore
        -- can tell which edge the position means.
        local d = S.defaults[key]
        if d then
            saved.h, saved.w, saved.s = d.h, d.w, d.s
        end
    end
    saved.x, saved.y = x, y
    NotifyArrangement()
    Request()
    return true
end

function core.ClearPosition(key)
    local contexts = Contexts()
    if not contexts or not contexts[CONTEXT_DEFAULT][key] then
        return false
    end
    contexts[CONTEXT_DEFAULT][key] = nil
    -- The window, if open and in the default context, goes back to its slot
    -- the way a shift-right-click sends it: the flush places nothing that is
    -- no longer saved.
    if SelectContext() and S.context == CONTEXT_DEFAULT then
        local d = S.defaults[key]
        for _, frame in ipairs(Containers()) do
            if frame:IsShown() and FrameKey(frame) == key and d then
                Place(frame, Clamp(frame, d.x, d.y))
            end
        end
    end
    NotifyArrangement()
    Request()
    return true
end

function core.DefaultSlot(key)
    return S.defaults[key]
end
