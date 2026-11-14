-- MoveMyBags -- layers: one window per layer, the active one on top, and
-- every window's item buttons kept above the window they belong to.

local _, ns = ...

local core = ns.core
local S = ns.state

local Containers = core.Containers
local FrameKey = core.FrameKey
local Option = core.Option

local wipe = wipe

-- Each managed window gets a frame-level layer of its own; picking one up or
-- clicking it moves it to the top and pushes the rest back one. Why the
-- client's own layering is not enough, and where the numbers come from, is
-- DESIGN.md "Layers". The invariants the code rests on:
--
--   * A window's title bar and close button sit 510 levels above the window
--     (PortraitFrameFlatTemplate), so a step narrower than 511 lets one
--     window's chrome draw over the window in front of it.
--   * The band stays under the ceiling so the top window's chrome has room
--     below the client's limit, and so Blizzard raising every window on each
--     open -- which lifts the group above the band and makes the next pass
--     re-hang it from there -- cannot walk the band up the strata.
local LEVEL_STEP = 520
local LEVEL_CEILING = 9000

-- A window's item buttons belong 10 levels above it (ContainerFrameItemButtonTemplate
-- declares frameLevel="10"), and the client cannot hold a level above
-- MAX_FRAME_LEVEL. Why the addon puts them back there is DESIGN.md "Item buttons".
local ITEM_LEVEL_OFFSET = 10
local MAX_FRAME_LEVEL = 10000

-- The bags we manage, by key (see FrameKey), most recently raised first. Keyed
-- by bag, not by window, because the windows are pooled (DESIGN.md "Pooled
-- windows"). Closed bags stay in the list -- the order is the player's
-- arrangement -- but only shown ones are given a layer, so closing a window
-- closes up the band. A window we stood down on is never in the list.
local stack = {}

-- Nothing is layered until the player first picks a window up or clicks one,
-- or a window on screen has a saved position; until then the bags are in
-- Blizzard's own column, where nothing overlaps. Once engaged it stays
-- engaged for the session.
S.layered = nil

-- Reused, for the same reason the snapshot tables are: Raise runs inside the
-- client's mouse path, and allocating there is enough to taint the click the
-- client still has to handle (DESIGN.md "Layers", the no-allocation rule).
local shownStack = {}   -- the shown frames, in stack order, this pass
local frameByKey = {}   -- key -> shown attached frame, this pass

local function EngageLayers()
    S.layered = true
end
core.EngageLayers = EngageLayers

local function IndexInStack(key)
    for i = 1, #stack do
        if stack[i] == key then
            return i
        end
    end
    return nil
end

-- A bag seen for the first time since the layers engaged takes the place its
-- current level puts it in, among the bags already on screen. On the first pass
-- that is every bag, and the order that falls out is the one the player is
-- looking at -- the order the client's own raise-on-generate left behind --
-- rather than the order the windows happened to be attached in, which would
-- reverse the draw order of every window the player had not touched. Later it
-- is one bag the client has just raised above the rest, which lands in front.
local function AdmitToStack(key, frame)
    local level = frame:GetFrameLevel() or 0
    for i = 1, #stack do
        local other = frameByKey[stack[i]]
        if other and (other:GetFrameLevel() or 0) < level then
            table.insert(stack, i, key)
            return
        end
    end
    stack[#stack + 1] = key
end

-- Find the shown windows we own and admit any bag not yet in the order. Done
-- before a raise moves anything, so a bag being admitted is placed among the
-- others by the level the client gave it, never in front of the one the player
-- just picked up.
local function AdmitShown()
    wipe(frameByKey)
    for _, frame in ipairs(Containers()) do
        if frame.moveMyBags == "attached" and frame:IsShown() then
            frameByKey[FrameKey(frame)] = frame
        end
    end
    for key, frame in pairs(frameByKey) do
        if not IndexInStack(key) then
            AdmitToStack(key, frame)
        end
    end
end

-- Hang the band from the shown windows in stack order. AdmitShown must have
-- run first on this pass, since this reads the map it builds.
local function ApplyBand()
    wipe(shownStack)
    local floorLevel, topLevel
    for i = 1, #stack do
        local frame = frameByKey[stack[i]]
        if frame then
            shownStack[#shownStack + 1] = frame
            local level = frame:GetFrameLevel() or 0
            if not floorLevel or level < floorLevel then
                floorLevel = level
            end
            if not topLevel or level > topLevel then
                topLevel = level
            end
        end
    end

    -- One window has nothing to be layered against, and giving it a level of
    -- our choosing could only ever move it relative to the rest of the UI.
    -- This is also the whole of combined-bags mode, where the one window on
    -- screen is `toplevel` and the client already raises it on a click.
    local count = #shownStack
    if count < 2 then
        return
    end

    local step = LEVEL_STEP
    local span = (count - 1) * step

    -- More windows than a band of full-width layers can hold below the ceiling.
    -- Unreachable on a live client -- that is 19 bag windows -- and the narrower
    -- layers it falls back to no longer clear a window's own chrome, so it is a
    -- floor under the damage rather than a fix.
    if span > LEVEL_CEILING then
        step = math.floor(LEVEL_CEILING / (count - 1))
        span = (count - 1) * step
    end

    -- The band is hung from the lowest level the windows already occupy, so it
    -- can only ever draw a window in front of something the group as a whole was
    -- in front of -- never behind something one of them was ahead of. The top
    -- rises above the group where the layers need the room, which is the
    -- direction that costs nothing: the active window ending up in front of the
    -- rest of the UI is the point.
    --
    -- The exception is the ceiling. Once the group has been raised near it --
    -- see LEVEL_CEILING -- the band cannot be hung that high, and the windows
    -- come back down to where the band sits. Nothing foreign is normally up
    -- there to be hidden behind, since only a raise puts a frame there at all.
    local top = floorLevel + span
    if top < topLevel then
        top = topLevel
    end
    if top > LEVEL_CEILING then
        top = LEVEL_CEILING
    end

    for i = 1, count do
        local frame = shownStack[i]
        local level = top - (i - 1) * step
        if frame:GetFrameLevel() ~= level then
            frame:SetFrameLevel(level)
        end
    end
end

function core.ApplyLevels()
    AdmitShown()
    ApplyBand()
end

-- Put one window's item buttons back ITEM_LEVEL_OFFSET above it. Only their
-- level is touched: nothing is hooked or written on them. Classic has no
-- `Items` -- its buttons are the window's own XML children, which keep their
-- place -- so this stands down there.
local function SeatItemsOf(frame)
    local items = frame.Items
    if type(items) ~= "table" then
        return
    end
    local level = frame:GetFrameLevel() + ITEM_LEVEL_OFFSET
    if level > MAX_FRAME_LEVEL then
        level = MAX_FRAME_LEVEL
    end
    for i = 1, #items do
        local button = items[i]
        if button:GetFrameLevel() ~= level then
            button:SetFrameLevel(level)
        end
    end
end

-- Every shown window we own, whether or not the layers are engaged: the
-- buttons go astray under Blizzard's own raise as well as under the band.
function core.SeatItems()
    for _, frame in ipairs(Containers()) do
        if frame.moveMyBags == "attached" and frame:IsShown() then
            SeatItemsOf(frame)
        end
    end
end

-- Bring one window to the top, pushing every other back a layer. The order is
-- the player's: nothing else -- not a layout pass, not reopening the bags --
-- ever reshuffles it. Takes the button as a second argument and ignores it,
-- since it is hooked straight onto OnMouseDown: any click on a window makes it
-- the active one.
function core.Raise(frame)
    if frame.moveMyBags ~= "attached" or not Option("layers") then
        return
    end

    EngageLayers()
    AdmitShown()

    local key = FrameKey(frame)
    local at = IndexInStack(key)
    if at then
        table.remove(stack, at)
    end
    table.insert(stack, 1, key)

    ApplyBand()

    -- The band just moved windows; put their buttons back with them. Read from
    -- the map AdmitShown built rather than another walk of Containers().
    for _, shown in pairs(frameByKey) do
        SeatItemsOf(shown)
    end
end
