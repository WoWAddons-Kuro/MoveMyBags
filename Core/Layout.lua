-- MoveMyBags -- the layout pass: snapshot every shown bag, close the hole a
-- moved one leaves, settle a dropped window, then override the moved ones.

local _, ns = ...
local L = ns.L

local core = ns.core
local S = ns.state

local Print = core.Print
local Fail = core.Fail
local Option = core.Option
local Containers = core.Containers
local FrameKey = core.FrameKey
local ScaleFactor = core.ScaleFactor
local ReadPos = core.ReadPos
local Place = core.Place
local Clamp = core.Clamp
local SelectContext = core.SelectContext
local SavedFor = core.SavedFor
local EngageLayers = core.EngageLayers
local ApplyLevels = core.ApplyLevels
local SeatItems = core.SeatItems
local SNAP_DISTANCE = core.SNAP_DISTANCE

local UIParent = UIParent
local wipe = wipe

-- Contact is not overlap: two flush windows share an edge exactly, and the
-- arithmetic that put them there leaves the odd trailing bit behind.
local OVERLAP_EPSILON = 0.5

-- Moving a window clear of one neighbour can land it on another, so the search
-- runs again from wherever it got to. Bounded, because a crowded screen can
-- have no clear spot at all and a drop must not spin looking for one.
local OVERLAP_PASSES = 8

--------------------------------------------------------------------------
-- layout: snapshot every shown bag, then override the moved ones
--------------------------------------------------------------------------

-- Reused across passes so a bag-heavy layout does not churn the allocator.
local order, snapX, snapY = {}, {}, {}

--------------------------------------------------------------------------
-- closing the hole a moved bag leaves
--------------------------------------------------------------------------

-- Blizzard keeps laying a moved bag out in the column as though it never left,
-- so dragging one out leaves a hole. The column geometry needed to close it
-- is measured from the layout Blizzard just produced, never reproduced from
-- constants (DESIGN.md "Closing the hole"), and cached so the column re-flows
-- the instant a bag is dropped. It checks itself on every layout pass:
-- replaying the placement with nothing removed has to reproduce what
-- Blizzard did, or compacting stands down until a pass it can reproduce.

local COLUMN_EPSILON = 1   -- UIParent units

local reflowX, reflowY = {}, {}

-- Geometry measured from Blizzard's last layout pass, reused between passes so
-- a drop can re-flow immediately. On the shared state because the status
-- command reports it and a scale change invalidates it.
S.geoColumns = {}
S.geoSpacing = nil
S.geoFreeHeight = nil
S.geoValid = nil
local geoColumns = S.geoColumns

local function RightToLeft(a, b)
    return a.x > b.x
end

local function HeightUI(frame)
    return frame:GetHeight() * ScaleFactor(frame)
end

local function IsCombined(frame)
    return frame.IsCombinedBagContainer and frame:IsCombinedBagContainer() or false
end

-- Group the snapshot into columns, ordered the way Blizzard fills them
-- (rightmost first). All columns share a bottom edge, so one reading suffices.
local function BuildColumns(frames)
    wipe(geoColumns)

    for i = 1, #frames do
        local frame = frames[i]
        local x = snapX[frame]
        local found
        for c = 1, #geoColumns do
            if math.abs(geoColumns[c].x - x) <= COLUMN_EPSILON then
                found = geoColumns[c]
                break
            end
        end
        if found then
            if snapY[frame] < found.bottom then
                found.bottom = snapY[frame]
            end
        else
            geoColumns[#geoColumns + 1] = { x = x, bottom = snapY[frame] }
        end
    end

    table.sort(geoColumns, RightToLeft)
end

-- Consecutive bags in Blizzard's own order that share a column are stacked, so
-- the gap between them is the spacing constant. Nil when nothing is stacked.
local function MeasureSpacing(frames)
    for i = 2, #frames do
        local prev, frame = frames[i - 1], frames[i]
        if math.abs(snapX[frame] - snapX[prev]) <= COLUMN_EPSILON then
            return snapY[frame] - (snapY[prev] + HeightUI(prev))
        end
    end
    return nil
end

-- Replay Blizzard's placement loop over the bags `keep` accepts, mirroring its
-- structure exactly -- including that the free-height accounting subtracts each
-- bag's height but not the spacing between stacked bags. Classic's loop
-- subtracts one more term per bag, VISIBLE_CONTAINER_SPACING, which is a
-- global there and absent on Mainline; it is read rather than hardcoded, and
-- it is not the stacked gap (CONTAINER_SPACING, 0 on Classic), so it cannot
-- be measured from the layout. Returns false if it would need more columns
-- than Blizzard used, which removing bags cannot cause but the replay checks.
local function Reflow(frames, keep)
    wipe(reflowX)
    wipe(reflowY)

    local column, prev = 1, nil
    local free = S.geoFreeHeight
    local bottom = geoColumns[1].bottom
    local accounted = tonumber(VISIBLE_CONTAINER_SPACING) or 0

    for i = 1, #frames do
        local frame = frames[i]
        if keep(frame) then
            local height = HeightUI(frame)
            if not prev then
                reflowX[frame], reflowY[frame] = geoColumns[1].x, bottom
            elseif free < height or IsCombined(prev) then
                column = column + 1
                if not geoColumns[column] then
                    return false
                end
                free = S.geoFreeHeight
                reflowX[frame], reflowY[frame] = geoColumns[column].x, bottom
            else
                reflowX[frame] = reflowX[prev]
                reflowY[frame] = reflowY[prev] + HeightUI(prev) + S.geoSpacing
            end
            prev = frame
            free = free - height - accounted * ScaleFactor(frame)
        end
    end

    return true
end

local function KeepAll()
    return true
end

local function KeepUnmoved(frame)
    return not SavedFor(frame)
end

-- Does replaying the placement with nothing removed reproduce Blizzard's own
-- output? If not, our reading of the layout is wrong and must not be used.
local function ModelMatches(frames)
    for i = 1, #frames do
        local frame = frames[i]
        if not reflowX[frame]
            or math.abs(reflowX[frame] - snapX[frame]) > COLUMN_EPSILON
            or math.abs(reflowY[frame] - snapY[frame]) > COLUMN_EPSILON then
            return false
        end
    end
    return true
end

-- Re-measure the column geometry from a layout Blizzard just produced, and
-- confirm we can reproduce that layout before trusting the measurement.
local function RemeasureGeometry(frames)
    S.geoValid = false

    BuildColumns(frames)
    S.geoSpacing = MeasureSpacing(frames)
    if not S.geoSpacing or #geoColumns == 0 then
        return false   -- nothing stacked; nothing to compact either
    end
    S.geoFreeHeight = GetScreenHeight() - geoColumns[1].bottom

    if not Reflow(frames, KeepAll) or not ModelMatches(frames) then
        S.gapsUnavailable = true
        return false
    end

    -- The model reproduces Blizzard's output again, so lift the stand-down: a
    -- single bad reading -- another addon nudging a bag for a frame, a layout
    -- caught mid-scale-change -- should not cost the feature for the rest of the
    -- session. warnedAboutGaps deliberately stays set, so a layout that flaps
    -- explains itself once rather than on every bag open.
    S.gapsUnavailable = false

    S.geoValid = true
    return true
end

-- A bag window's height is ceil(slots / 4) rows, so it grows when the bag is
-- upgraded -- and the same bag ID can be a different size on another character.
-- Blizzard's bags are bottom-anchored and grow upward, which is right for a bag
-- parked low on the screen but wrong for one parked high: it would grow off the
-- top and be clamped back down, moving the window the player placed. So a bag
-- remembers how tall it was, and one sitting in the upper half of the screen
-- keeps its top edge instead of its bottom.
local function RestoreY(frame, saved)
    if type(saved.h) ~= "number" then
        return saved.y   -- stored before heights were recorded
    end

    -- The recorded height is the frame's own, not the scaled one: SetScale does
    -- not change GetHeight, so this moves only when the bag's row count does.
    -- Blizzard shrinking every bag must not be mistaken for a bag upgrade.
    local delta = frame:GetHeight() - saved.h
    if delta == 0 then
        return saved.y
    end

    local scale = ScaleFactor(frame)
    if saved.y + frame:GetHeight() * scale * 0.5 <= UIParent:GetHeight() * 0.5 then
        return saved.y   -- lower half: grow upward, the way Blizzard's own do
    end

    return saved.y - delta * scale
end

--------------------------------------------------------------------------
-- settling a dropped window: flush to its neighbours, never on top of one
--------------------------------------------------------------------------

-- Bag windows are opaque, so any overlap hides the window underneath, and a
-- window dropped squarely on another hides it completely. Two rules settle a
-- drop, in this order:
--
--   * snapping -- a drop landing within SNAP_DISTANCE of another window's edge,
--     or the screen's, aligns exactly flush to it, so a deliberate arrangement
--     does not end up a few pixels out;
--   * clearing -- a drop still overlapping a window moves to the nearest
--     position flush against one, so it ends up beside what it landed on rather
--     than over it.
--
-- Only the window just dropped ever moves. Nothing already parked shifts on its
-- own; that is the rule the rest of the addon is built on, and it is why the
-- search moves the one window the player still has hold of.
--
-- Both run inside the flush the drop triggers rather than in OnDragStop,
-- because the same drop also closes the hole the window left behind. The column
-- re-stacks in that pass, so the positions worth aligning against are the ones
-- the pass is about to produce -- not the ones still on screen while the mouse
-- button was down, which are a slot out.

-- Where the placement loop at the end of Flush is about to put this frame, in
-- UIParent units. Shared with that loop so the two can never disagree.
local function FinalPosition(frame, reflowed, reopening)
    local saved = SavedFor(frame)
    if saved then
        return Clamp(frame, saved.x, RestoreY(frame, saved))
    end
    if reflowed and reflowX[frame] then
        return Clamp(frame, reflowX[frame], reflowY[frame])
    end
    local slot = reopening and S.defaults[FrameKey(frame)]
    if slot then
        return slot.x, slot.y
    end
    return snapX[frame], snapY[frame]
end

-- The rects every other shown window is about to occupy. Measured once per
-- drop and reused between passes -- and read instead of the frames themselves,
-- so the search never walks Containers() from inside another iteration of it.
local rects, rectCount = {}, 0

local function AddRect(frame, x, y)
    local s = ScaleFactor(frame)
    rectCount = rectCount + 1
    local rect = rects[rectCount]
    if not rect then
        rect = {}
        rects[rectCount] = rect
    end
    rect.x, rect.y = x, y
    rect.w, rect.h = frame:GetWidth() * s, frame:GetHeight() * s
end

local function CollectRects(exclude, reflowed, reopening)
    rectCount = 0
    for i = 1, #order do
        local frame = order[i]
        if frame ~= exclude then
            AddRect(frame, FinalPosition(frame, reflowed, reopening))
        end
    end
end

-- The rects the other windows occupy *right now*, read from the frames rather
-- than from a snapshot. This is what a live drag settles against: mid-drag the
-- only honest answer is what the player can actually see on screen.
function core.CollectLiveRects(exclude)
    rectCount = 0
    for _, frame in ipairs(Containers()) do
        if frame ~= exclude and frame:IsShown() then
            local x, y = ReadPos(frame)
            if x then
                AddRect(frame, x, y)
            end
        end
    end
end

-- How much of the two ranges is shared. Zero or less when they only touch.
local function Span(aMin, aMax, bMin, bMax)
    local low = aMin > bMin and aMin or bMin
    local high = aMax < bMax and aMax or bMax
    return high - low
end

-- Total area a window at this position would hide. Summed rather than counted
-- so the search can still rank positions when a crowded screen offers no
-- completely clear one.
local function OverlapArea(x, y, width, height)
    local total = 0
    for i = 1, rectCount do
        local rect = rects[i]
        local px = Span(x, x + width, rect.x, rect.x + rect.w)
        if px > OVERLAP_EPSILON then
            local py = Span(y, y + height, rect.y, rect.y + rect.h)
            if py > OVERLAP_EPSILON then
                total = total + px * py
            end
        end
    end
    return total
end

-- Two ranges overlap, or come within the snap distance of touching.
local function Alongside(aMin, aMax, bMin, bMax)
    return aMin - SNAP_DISTANCE <= bMax and bMin - SNAP_DISTANCE <= aMax
end

-- Which alignments a neighbour may offer depends on how the two windows sit.
-- Overlapping on the other axis means they are face to face, and the only
-- alignment that means anything there is contact: this edge to that opposite
-- edge. Merely sitting near each other means they are side by side or stacked,
-- and the useful alignment is the shared gridline: left to left, top to top.
--
-- Offering both regardless is what makes a drop line its left edge up with a
-- window it is face to face with -- landing it squarely on top, which is exactly
-- what the clearing pass below would then have to undo.
--
-- A window on the far side of the screen offers nothing either way. Without
-- that rule a drop jumps to the edge of something it shares no rows or columns
-- with, which reads as the window moving for no reason.
--
-- X is settled first and Y judged against the result, so a window that has just
-- gone flush against a neighbour's side is then free to line its bottom edge up
-- with that neighbour's.
local function SnapPosition(frame, x, y)
    local s = ScaleFactor(frame)
    local width, height = frame:GetWidth() * s, frame:GetHeight() * s
    local best

    local function consider(edge, target)
        local delta = target - edge
        if math.abs(delta) <= SNAP_DISTANCE and (not best or math.abs(delta) < math.abs(best)) then
            best = delta
        end
    end

    best = nil
    consider(x, 0)
    consider(x + width, UIParent:GetWidth())
    for i = 1, rectCount do
        local rect = rects[i]
        local right, top = rect.x + rect.w, rect.y + rect.h
        if Span(y, y + height, rect.y, top) > OVERLAP_EPSILON then
            consider(x + width, rect.x)   -- our right edge to their left
            consider(x, right)            -- our left edge to their right
        elseif Alongside(y, y + height, rect.y, top) then
            consider(x, rect.x)           -- share a left edge
            consider(x + width, right)    -- share a right edge
        end
    end
    x = x + (best or 0)

    best = nil
    consider(y, 0)
    consider(y + height, UIParent:GetHeight())
    for i = 1, rectCount do
        local rect = rects[i]
        local right, top = rect.x + rect.w, rect.y + rect.h
        if Span(x, x + width, rect.x, right) > OVERLAP_EPSILON then
            consider(y + height, rect.y)  -- our top edge to their bottom
            consider(y, top)              -- our bottom edge to their top
        elseif Alongside(x, x + width, rect.x, right) then
            consider(y, rect.y)           -- share a bottom edge
            consider(y + height, top)     -- share a top edge
        end
    end

    return x, y + (best or 0)
end
core.SnapPosition = SnapPosition

-- Move a still-overlapping drop to the nearest position that hides nothing.
-- The candidates are the four flush positions around each window in the way --
-- left of it, right of it, below it, above it -- which is what makes the result
-- land against a neighbour rather than merely beside it. Candidates that would
-- put the window off screen are not offered, since a window you cannot reach is
-- worse than one you cannot read.
--
-- Nearest is measured from the drop, not from the last hop, so a chain of
-- pushes still ends up as close as it can to where the player aimed.
local function ClearOverlap(frame, x, y)
    local s = ScaleFactor(frame)
    local width, height = frame:GetWidth() * s, frame:GetHeight() * s
    if OverlapArea(x, y, width, height) <= 0 then
        return x, y
    end

    local maxX = UIParent:GetWidth() - width
    local maxY = UIParent:GetHeight() - height
    local dropX, dropY = x, y

    for _ = 1, OVERLAP_PASSES do
        local bestX, bestY, bestArea, bestMove

        local function consider(cx, cy)
            if cx < 0 or cx > maxX or cy < 0 or cy > maxY then
                return
            end
            local area = OverlapArea(cx, cy, width, height)
            local dcx, dcy = cx - dropX, cy - dropY
            local move = dcx * dcx + dcy * dcy
            if not bestArea or area < bestArea - OVERLAP_EPSILON
                or (area <= bestArea + OVERLAP_EPSILON and move < bestMove) then
                bestX, bestY, bestArea, bestMove = cx, cy, area, move
            end
        end

        for i = 1, rectCount do
            local rect = rects[i]
            consider(rect.x - width, y)
            consider(rect.x + rect.w, y)
            consider(x, rect.y - height)
            consider(x, rect.y + rect.h)
        end

        if not bestX then
            break
        end
        if bestArea <= 0 then
            return bestX, bestY
        end
        if bestX == x and bestY == y then
            break   -- the best on offer is where we already are
        end
        x, y = bestX, bestY
    end

    -- Nowhere on screen is clear: more windows than fit, or one wider than the
    -- screen. Leave the drop exactly where the player put it rather than move it
    -- somewhere arbitrary that is still overlapping.
    return dropX, dropY
end
core.ClearOverlap = ClearOverlap

-- Settle the window just dropped against the layout this pass is about to
-- produce. Runs once, on the flush that drop triggered; from then on the saved
-- position is the player's and is never revisited.
local function SettleDrop(frame, reflowed, reopening)
    local saved = S.pos[FrameKey(frame)]
    if not saved or not Option("snap") then
        return
    end

    -- Not clamped here: a saved position is the player's, and the restore
    -- clamps it for display without rewriting it. Every alignment offered above
    -- is to an on-screen edge, and the clearing pass rejects any candidate that
    -- would put the window out of reach, so neither introduces one.
    CollectRects(frame, reflowed, reopening)
    saved.x, saved.y = ClearOverlap(frame, SnapPosition(frame, saved.x, saved.y))
end

--------------------------------------------------------------------------
-- the flush
--------------------------------------------------------------------------

-- Returns true when the work is done, false to retry on the next frame.
local function Flush()
    if not SelectContext() then
        -- The layout hook is installed at load, so a layout pass can flag one
        -- of these before ADDON_LOADED has built the database. Drop the flag
        -- with the flush it belonged to rather than letting it apply to a
        -- later one, for the same reason the retry give-up does.
        S.blizzardLaidOut = false
        S.droppedFrame = nil
        return true
    end

    -- A drag that never gets its OnDragStop -- the window hidden from under it --
    -- would leave the marker set and make every later flush skip that window, so
    -- its saved position would stop being applied. The addon drives the drag
    -- itself, so IsDragging has nothing to say about it: the window still being
    -- on screen is the condition, and the drag updater checks the same thing.
    local dragging = S.dragging
    if dragging and not dragging:IsShown() then
        dragging = nil
        S.dragging = nil
        S.dragger:Hide()
    end

    wipe(order)
    wipe(snapX)
    wipe(snapY)

    local incomplete, anyMoved, anyStandby = false, false, false

    for _, frame in ipairs(Containers()) do
        -- A frame being dragged is following the cursor, and a layout pass can
        -- fire mid-drag: clicking a vendor or the bank while holding a bag runs
        -- OpenAllBagsMatchingContext. Its rect is then wherever the mouse
        -- happens to be, so it must not be snapshotted -- recording that as
        -- Blizzard's own slot breaks reset for the bag. The drag updater owns
        -- that window's position until it is dropped; the flush leaves it be.
        if frame:IsShown() and frame ~= dragging then
            local x, y = ReadPos(frame)
            if x then
                order[#order + 1] = frame
                snapX[frame], snapY[frame] = x, y
                if SavedFor(frame) then
                    anyMoved = true
                elseif frame.moveMyBags ~= "attached" then
                    anyStandby = true
                end
            else
                -- Blizzard's layout pass is still in flight. Retry rather than
                -- snapshotting a rect that does not exist yet.
                incomplete = true
            end
        end
    end

    if incomplete then
        return false
    end

    -- A saved position is the player arranging the windows, which is the same
    -- ask as picking one up: from here on the windows are layered. Re-asserted
    -- on every pass rather than only when the order changes, because Blizzard
    -- raises each window to the top of the strata as it generates it, which
    -- undoes the band on every bag open.
    -- Kuro: hook SetFrameLevel on every container before the band touches any
    -- of them, so the trace sees our own calls as well as Blizzard's.
    core.TraceAttach()
    if Option("layers") and (S.layered or anyMoved) then
        EngageLayers()
        ApplyLevels()
    end

    -- Every pass, layered or not: Blizzard rebuilds a window's item buttons
    -- each time it generates the window, and this is the first pass after.
    SeatItems()

    -- Remember where Blizzard wants each bag, so a reset can put it back
    -- without calling UpdateContainerFrameAnchors() from tainted code. After a
    -- Blizzard layout pass every snapshot is Blizzard's; otherwise only the
    -- bags we are not overriding are still sitting where Blizzard left them.
    local fromBlizzard = S.blizzardLaidOut
    S.blizzardLaidOut = false

    -- Mid-drag, do the one thing that cannot wait -- re-anchoring the other
    -- windows to UIParent, so the bag being dragged cannot tow its followers --
    -- and hold every cached reading as it is: the remembered slots, the column
    -- geometry, and whether a hole is currently closed. The drop brings its own
    -- Request(), which is the pass that gets to act on all of it. The flag is
    -- still consumed above: this *is* the flush that layout pass asked for.
    if dragging then
        if anyMoved then
            for i = 1, #order do
                local frame = order[i]
                local saved = SavedFor(frame)
                if saved then
                    Place(frame, Clamp(frame, saved.x, RestoreY(frame, saved)))
                else
                    Place(frame, snapX[frame], snapY[frame])
                end
            end
        end
        return true
    end

    local defaults = S.defaults
    for i = 1, #order do
        local frame = order[i]
        local key = FrameKey(frame)
        -- An unmoved bag is usually sitting where *we* put it after compacting,
        -- not where Blizzard did, so only a pass following Blizzard's own layout
        -- may refresh the remembered slot. The exception is when compacting is
        -- off entirely, where an unmoved bag is on Blizzard's slot by definition.
        if fromBlizzard or (S.gapsUnavailable and not SavedFor(frame)) then
            local d = defaults[key]
            if not d then
                d = {}
                defaults[key] = d
            end
            d.x, d.y = snapX[frame], snapY[frame]
            -- The window's size and scale as last seen, for anything that has
            -- to stand in for the window while it is closed (Edit Mode).
            d.w, d.h, d.s = frame:GetWidth(), frame:GetHeight(), ScaleFactor(frame)
        end
    end

    -- Re-measured on every layout pass, not just when something is moved: the
    -- first drag has to be able to close the hole it just made, and by then
    -- Blizzard's gapped layout is no longer on screen to measure. Writes only to
    -- the reflow tables, so it moves nothing on its own.
    --
    -- Deliberately re-measured even while standing down, so that a stand-down
    -- can be lifted again -- see RemeasureGeometry. fromBlizzard implies the
    -- anchor hook exists, so the no-layout-function case never reaches this.
    if fromBlizzard and #order > 1 then
        RemeasureGeometry(order)
    end

    -- Re-stacked from the geometry measured at the last layout pass, which is
    -- what lets a drop close the hole immediately instead of waiting for the
    -- next bag open. A window we stood down on is not ours to move, and the
    -- column cannot be re-stacked around one that has to stay put, so
    -- compacting sits this out entirely while any such window is open.
    local reflowed = Option("compact") and anyMoved and S.geoValid and not anyStandby and #order > 1
        and Reflow(order, KeepUnmoved)

    -- A hole we had closed has to re-open whenever we are not closing one this
    -- pass, not only when the last moved bag was put back: the geometry behind
    -- the re-stack also goes stale under a scale or resolution change, and
    -- leaving the flag set would strand the column compacted with nothing moved
    -- to justify it. The snapshot cannot re-open it -- that holds the compacted
    -- positions the bags are still sitting on -- so the remembered slots, which
    -- are the gaps the bags came out of, are what the placement loop uses.
    local reopening = S.compacted and not reflowed
    S.compacted = reflowed and true or false

    -- Settle a just-dropped window against everything above, then forget the
    -- drop: this is the one pass that is allowed to move it. Cleared even when
    -- the window is no longer eligible -- closed between the drop and this pass,
    -- or reset out from under it -- so a stale marker cannot move a later drop.
    local drop = S.droppedFrame
    S.droppedFrame = nil
    if drop and snapX[drop] and SavedFor(drop) then
        SettleDrop(drop, reflowed, reopening)
    end

    -- Nothing the user has moved is on screen: leave Blizzard's layout, and its
    -- anchor chain, completely untouched. The one exception is a column of ours
    -- still closed, which has to re-open before we stand down.
    if not anyMoved and not reopening then
        return true
    end

    -- Explain the hole once, the first time it matters, rather than on every
    -- bag open for someone who never drags anything -- or who turned
    -- compacting off and is not expecting it.
    if S.gapsUnavailable and not S.warnedAboutGaps and Option("compact") then
        S.warnedAboutGaps = true
        Print(L["this client's bag layout is not one this addon can re-stack, so the column is left as Blizzard draws it. Dragging still works."])
    end

    -- Re-anchoring every shown bag to UIParent breaks the bag-to-bag chain, so
    -- a moved bag does not drag its followers along with it.
    for i = 1, #order do
        local frame = order[i]
        Place(frame, FinalPosition(frame, reflowed, reopening))
    end

    return true
end

-- Flush retries when a shown bag has no rect yet, which normally lasts a single
-- frame while Blizzard's layout lands. If one never acquires a rect -- another
-- addon clearing its points, a reparent gone wrong -- an unbounded retry would
-- run this OnUpdate every frame for the rest of the session, which is a
-- permanent framerate cost with nothing to trace it back to. Give up after a
-- second and wait: the next bag open, drag or reset tries again.
local RETRY_SECONDS = 1

S.flusher:SetScript("OnUpdate", function(self, elapsed)
    if S.broken then
        self:Hide()
        return
    end

    local ok, done = pcall(Flush)
    if not ok then
        -- Drop the pass, flags and all, the way the retry give-up does: a
        -- pending layout flag or drop marker must not outlive the pass that
        -- raised it. The stand-down, if this is the error that triggers it,
        -- has already hidden this frame.
        S.retrying = 0
        S.blizzardLaidOut = false
        S.droppedFrame = nil
        self:Hide()
        Fail(done)
        return
    end
    if done then
        S.retrying = 0
        self:Hide()
        return
    end

    S.retrying = S.retrying + (elapsed or 0)
    if S.retrying >= RETRY_SECONDS then
        -- Abandoning the flush has to drop the pending-layout flag too. Flush()
        -- only clears it once it gets past the retry check, so leaving it set
        -- here would make the *next* flush -- typically one a drag triggered --
        -- believe it follows a Blizzard layout pass, and record the position the
        -- bag was just dropped on as Blizzard's own slot. Reset would then put
        -- that bag back where the player dropped it.
        --
        -- The pending drop goes with it. Settling belongs to the flush the drop
        -- asked for; carrying the marker into some later pass would shuffle a
        -- window the player parked a while ago against a layout they never
        -- dropped it into.
        S.retrying = 0
        S.blizzardLaidOut = false
        S.droppedFrame = nil
        self:Hide()
    end
end)
