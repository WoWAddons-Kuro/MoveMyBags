-- MoveMyBags -- shared state, the failure guard, and the frame helpers every
-- other module reads.
--
-- The core is split into modules that load in the order the TOC lists them;
-- each one publishes what the next needs on `ns.core` and keeps its own
-- working state local. State that more than one module reads or writes lives
-- on `ns.state`, so a module reads it at use time rather than capturing a
-- stale copy. Nothing here is reachable from other addons: `ns` is the
-- private table the client passes every file of this addon.

local _, ns = ...
local L = ns.L

local core = {}
ns.core = core

local S = {}
ns.state = S

-- The combined window has no meaningful bag ID of its own, and bag 0 is the
-- backpack, so it gets a key that cannot collide.
core.COMBINED_KEY = "combined"

-- How close (in UIParent units) a dropped window has to land to another
-- window's edge, or the screen's, before it aligns flush to it.
core.SNAP_DISTANCE = 12

core.COMMAND = "|cffffff78%s|r"
local PREFIX = "|cff33ff99MoveMyBags.Kuro|r: "

local _G = _G
local UIParent = UIParent
local wipe = wipe

S.defaults = {}          -- where Blizzard's own layout pass last put each bag
S.blizzardLaidOut = nil  -- the pending flush follows a Blizzard layout pass
S.gapsUnavailable = nil  -- our reading of Blizzard's layout does not hold
S.warnedAboutGaps = nil  -- said so once, when it first mattered
S.compacted = nil        -- the last pass closed a hole, so undoing it needs work
S.retrying = 0           -- seconds spent waiting for a bag to acquire a rect
S.dragging = nil         -- the frame the player is currently dragging, if any
S.droppedFrame = nil     -- dropped, and not yet settled against the new layout

S.flusher = CreateFrame("Frame")
S.flusher:Hide()

-- The addon moves the dragged window itself, a frame at a time, rather than
-- handing the job to StartMoving. See Core/Drag.lua for why.
S.dragger = CreateFrame("Frame")
S.dragger:Hide()

--------------------------------------------------------------------------
-- helpers
--------------------------------------------------------------------------

local function Print(msg)
    print(PREFIX .. msg)
end
core.Print = Print

--------------------------------------------------------------------------
-- failure: stand down rather than error every frame
--------------------------------------------------------------------------

-- Every entry point is wrapped: the error goes to the error handler so
-- BugSack and friends capture it with a stack, the chat sees it once, and
-- after ERROR_LIMIT of them the addon stops touching the windows until a
-- reload. Saved positions are left alone (DESIGN.md "Robustness").
local ERROR_LIMIT = 3

S.errorCount = 0
S.lastError = nil        -- the message, for /movemybags status
S.broken = false         -- stood down for the session

local function StandDown()
    S.broken = true
    S.dragging = nil
    S.flusher:Hide()
    S.dragger:Hide()
end

local function Fail(err)
    S.errorCount = S.errorCount + 1
    S.lastError = tostring(err)

    local handler = geterrorhandler and geterrorhandler()
    if handler then
        pcall(handler, S.lastError)
    end

    if S.errorCount == 1 then
        Print(L["hit an error. %s shows it; please report it. %s"]:format(
            core.COMMAND:format("/mmbk status"), S.lastError))
    end
    if S.errorCount >= ERROR_LIMIT and not S.broken then
        StandDown()
        Print(L["standing down for this session after %d errors. The bag windows are Blizzard's again until you %s."]
            :format(S.errorCount, core.COMMAND:format("/reload")))
    end
end
core.Fail = Fail

-- Wrap an entry point. Discards return values, so it is for handlers only;
-- the two OnUpdates call pcall themselves because they act on Flush's result.
function core.Guarded(fn)
    return function(...)
        if S.broken then
            return
        end
        local ok, err = pcall(fn, ...)
        if not ok then
            Fail(err)
        end
    end
end

--------------------------------------------------------------------------
-- options
--------------------------------------------------------------------------

-- Three behaviours can be switched off: connecting windows while dragging,
-- closing the hole a moved bag leaves, and layering. Each defaults to on,
-- which is what the addon always did, and is stored in the database under a
-- plain key so the Settings panel can write it directly (see Options.lua).
-- Nil reads as on, so a database from before the keys existed changes
-- nothing. The lock is the fourth and oldest, and defaults the other way.
function core.Option(key)
    return MoveMyBagsKuroDB == nil or MoveMyBagsKuroDB[key] ~= false
end

-- The other kind of switch: off unless the player turned it on.
function core.Flag(key)
    return MoveMyBagsKuroDB ~= nil and MoveMyBagsKuroDB[key] == true
end

--------------------------------------------------------------------------
-- frames
--------------------------------------------------------------------------

-- IsCombinedBagContainer is defined on BaseContainerFrameMixin (false) and
-- overridden on ContainerFrameCombinedBagsMixin (true), so every container
-- frame answers it. GetBagID is ContainerFrameMixin's accessor and simply
-- returns GetID; the fallback covers Classic, which has only GetID.
function core.FrameKey(frame)
    if frame.IsCombinedBagContainer and frame:IsCombinedBagContainer() then
        return core.COMBINED_KEY
    end
    if frame.GetBagID then
        return frame:GetBagID()
    end
    return frame:GetID()
end

local function ScaleFactor(frame)
    local ui = UIParent:GetEffectiveScale()
    if not ui or ui == 0 then
        return 1
    end
    return frame:GetEffectiveScale() / ui
end
core.ScaleFactor = ScaleFactor

-- GetLeft/GetBottom report in the frame's own units; everything is stored in
-- UIParent units so a saved position survives Blizzard rescaling the bags.
-- Returns nil when the frame has not been laid out yet, so callers can retry.
function core.ReadPos(frame)
    local left, bottom = frame:GetLeft(), frame:GetBottom()
    if not left or not bottom then
        return nil
    end
    local s = ScaleFactor(frame)
    return left * s, bottom * s
end

-- SetPoint offsets are applied in the anchored frame's own units, so the
-- stored UIParent-unit coordinates have to be divided back out. Skipping this
-- looks correct only while a bag happens to sit at UIParent's scale, which
-- stops being true the moment enough bags are open for Blizzard to shrink them.
function core.Place(frame, x, y)
    local s = ScaleFactor(frame)
    if s == 0 then
        return
    end
    frame:ClearAllPoints()
    frame:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", x / s, y / s)
end

-- SetClampedToScreen constrains dragging, not SetPoint, so a restored position
-- has to be clamped: resolution and UI-scale changes can otherwise strand a bag
-- off-screen with no way to grab it back.
function core.Clamp(frame, x, y)
    local s = ScaleFactor(frame)
    local maxX = UIParent:GetWidth() - frame:GetWidth() * s
    local maxY = UIParent:GetHeight() - frame:GetHeight() * s
    if maxX < 0 then maxX = 0 end
    if maxY < 0 then maxY = 0 end
    if x < 0 then x = 0 elseif x > maxX then x = maxX end
    if y < 0 then y = 0 elseif y > maxY then y = maxY end
    return x, y
end

-- Blizzard's own enumeration source, plus the combined window, which is
-- parented to UIParent and so is not in that array. Deliberately does not call
-- ContainerFrameUtil_EnumerateContainerFrames: that lazily builds a cache
-- Blizzard reads later, and priming it from tainted code would hand it our
-- taint. Reused table -- never iterate it from inside another iteration.
local frameList = {}

function core.Containers()
    wipe(frameList)

    local container = ContainerFrameContainer
    local array = container and container.ContainerFrames
    if array then
        for i = 1, #array do
            frameList[#frameList + 1] = array[i]
        end
    else
        -- Classic. The frames are globals ContainerFrame1..NUM_CONTAINER_FRAMES
        -- (13), and Blizzard lays the shown ones out in the order their names
        -- sit in ContainerFrame1.bags -- the order they were opened in, which
        -- is not the index order once a window has been closed and its frame
        -- reused. The replay has to walk Blizzard's order, so the shown frames
        -- go in that order first and the hidden ones follow by index. Read
        -- only; the table is Blizzard's.
        local first = _G.ContainerFrame1
        local bags = first and type(first.bags) == "table" and first.bags or nil
        if bags then
            for i = 1, #bags do
                local frame = _G[bags[i]]
                if frame and frame:IsShown() then
                    frameList[#frameList + 1] = frame
                end
            end
        end
        for i = 1, NUM_CONTAINER_FRAMES or 13 do
            local frame = _G["ContainerFrame" .. i]
            if frame and not (bags and frame:IsShown()) then
                frameList[#frameList + 1] = frame
            end
        end
    end

    if ContainerFrameCombinedBags then
        frameList[#frameList + 1] = ContainerFrameCombinedBags
    end

    return frameList
end

function core.Request()
    if S.broken then
        return
    end
    S.retrying = 0   -- a fresh trigger gets a fresh retry budget
    S.flusher:Show()
end
