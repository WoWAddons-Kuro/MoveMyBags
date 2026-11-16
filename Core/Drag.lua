-- MoveMyBags.Kuro -- the drag, the gestures, and the hooks that attach them to
-- Blizzard's windows.

local _, ns = ...

local core = ns.core
local S = ns.state

local Fail = core.Fail
local Guarded = core.Guarded
local Option = core.Option
local Containers = core.Containers
local FrameKey = core.FrameKey
local ScaleFactor = core.ScaleFactor
local ReadPos = core.ReadPos
local Place = core.Place
local Clamp = core.Clamp
local Request = core.Request
local SelectContext = core.SelectContext
local WritablePositions = core.WritablePositions
local ResetFrame = core.ResetFrame
local Locked = core.Locked
local Raise = core.Raise
local SnapPosition = core.SnapPosition
local ClearOverlap = core.ClearOverlap
local CollectLiveRects = core.CollectLiveRects
local SNAP_DISTANCE = core.SNAP_DISTANCE

local UIParent = UIParent

-- A drag landing this close (in UIParent units) to where it started, or to
-- Blizzard's own slot, is an accidental nudge rather than a move.
local SNAP_TOLERANCE = 2

--------------------------------------------------------------------------
-- drag
--------------------------------------------------------------------------

-- The window follows the cursor from here rather than from StartMoving, so the
-- settling rules can run while the player can still see them (DESIGN.md
-- "Settling a drop", "Where they run"). One OnUpdate for the length of a
-- drag. The cursor's own position is the input, not a per-frame delta, so
-- nothing accumulates: a window held against an obstacle does not drift away
-- from the pointer once it comes free.

-- Where each bag sat when its drag began, in UIParent units. A bag the addon
-- has re-stacked is not on Blizzard's slot, so "did it move?" has to be asked
-- against where it actually started, not only against Blizzard's layout.
local dragOriginX, dragOriginY = {}, {}

-- Where the cursor was when the drag began, and the position it has asked for
-- since -- before any settling, and so what "did the player move it?" is judged
-- against. Both in UIParent units.
local dragCursorX, dragCursorY
local dragRawX, dragRawY

-- Until the drag has carried the window this far from where it started, it just
-- follows the cursor. Blizzard stacks the column CONTAINER_SPACING apart, which
-- is inside SNAP_DISTANCE, so without this every bag lifted out of the column
-- would snap flush against its neighbours the instant it was picked up -- before
-- the player had moved it anywhere.
local DRAG_ENGAGE = SNAP_DISTANCE

-- GetCursorPosition reports in screen pixels, which is UIParent units times its
-- effective scale -- the same conversion ReadPos does for a frame.
local function CursorUI()
    local x, y = GetCursorPosition()
    local s = UIParent:GetEffectiveScale()
    if not x or not s or s == 0 then
        return nil
    end
    return x / s, y / s
end

local function EndDrag()
    S.dragging = nil
    S.dragger:Hide()
end

local function OnDragStart(frame)
    -- Ahead of the locked check: a window being picked up is the active one
    -- whether or not it is allowed to go anywhere.
    Raise(frame)

    if Locked() then
        return
    end

    local x, y = ReadPos(frame)
    if not x then
        return   -- no rect to drag from yet; let the click pass
    end
    local cx, cy = CursorUI()
    if not cx then
        return
    end

    -- SetClampedToScreen changes how Blizzard's own chain lays out near the
    -- screen edge, so a bag only gains it once the player actually moves it.
    -- Until then the layout is Blizzard's, untouched. The drag does its own
    -- clamping below, so this covers only a move started by something else.
    frame:SetClampedToScreen(true)

    dragOriginX[frame], dragOriginY[frame] = x, y
    dragCursorX, dragCursorY = cx, cy
    dragRawX, dragRawY = x, y
    S.dragging = frame
    S.dragger:Show()
end

local function DragUpdate()
    local frame = S.dragging
    -- The window can go out from under the drag -- closed by a keybind, or by
    -- the bank shutting the bags -- and the client will not send OnDragStop for
    -- a frame that is gone. Ending it here keeps the marker from stranding.
    if not frame or not frame:IsShown() then
        EndDrag()
        Request()
        return
    end

    local cx, cy = CursorUI()
    if not cx then
        return
    end

    local x, y = Clamp(frame,
        dragOriginX[frame] + (cx - dragCursorX),
        dragOriginY[frame] + (cy - dragCursorY))
    dragRawX, dragRawY = x, y

    if not Option("snap")
        or (math.abs(x - dragOriginX[frame]) <= DRAG_ENGAGE
            and math.abs(y - dragOriginY[frame]) <= DRAG_ENGAGE) then
        Place(frame, x, y)
        return
    end

    CollectLiveRects(frame)
    Place(frame, ClearOverlap(frame, SnapPosition(frame, x, y)))
end

S.dragger:SetScript("OnUpdate", function(self)
    if S.broken then
        self:Hide()
        return
    end
    local ok, err = pcall(DragUpdate)
    if not ok then
        -- Let go of the window where it is. The drop is not stored: a position
        -- an error left it at is not one the player chose.
        EndDrag()
        Fail(err)
    end
end)

local function OnDragStop(frame)
    -- Cleared first, ahead of every early return including the locked one: a
    -- stale value here would make every later flush skip this window, and its
    -- saved position would silently stop being applied.
    EndDrag()
    if Locked() then
        return
    end
    -- A no-op for a drag this addon drove, and a tidy-up for one something else
    -- started on the same frame.
    frame:StopMovingOrSizing()

    local ox, oy = dragOriginX[frame], dragOriginY[frame]
    dragOriginX[frame], dragOriginY[frame] = nil, nil

    -- Where the window actually ended up, settled against its neighbours.
    local settledX, settledY = ReadPos(frame)

    -- The two checks below ask what the *player* did, so they read the position
    -- the cursor asked for rather than the one settling arrived at. A bag lifted
    -- out of the column sits within SNAP_DISTANCE of its neighbours, so once the
    -- drag engages, the settled position is flush against one of them -- and
    -- putting a bag back on its own slot would never read as putting it back.
    local x, y = dragRawX, dragRawY
    dragRawX, dragRawY = nil, nil

    if not SelectContext() then
        return
    end
    if not x then
        x, y = settledX, settledY
    end
    if not x then
        return
    end
    local key = FrameKey(frame)
    local pos = S.pos

    -- A bag that was never moved and lands where it started has not been moved
    -- now either. That start may be a slot the addon compacted it into rather
    -- than Blizzard's own, which the check below would not recognise, and the
    -- nudge would then be stored as a real move and stick when the column
    -- re-opens.
    if not pos[key] and ox
        and math.abs(x - ox) <= SNAP_TOLERANCE and math.abs(y - oy) <= SNAP_TOLERANCE then
        Place(frame, ox, oy)
        Request()
        return
    end

    -- Landing back on Blizzard's own slot is not a move. Storing it would opt
    -- the bag into override mode permanently for no visible difference, so
    -- treat it as a reset instead. Checked before the drop is settled: a drop
    -- that barely moved should read as "put it back", not get pulled onto a
    -- neighbour's edge and stored as a deliberate position.
    local d = S.defaults[key]
    if d and math.abs(x - d.x) <= SNAP_TOLERANCE and math.abs(y - d.y) <= SNAP_TOLERANCE then
        if pos[key] then
            WritablePositions()[key] = nil
        end
        Place(frame, d.x, d.y)
        Request()
        return
    end

    -- A real move, so what gets stored is where the drag left the window --
    -- settled flush against its neighbours -- not the raw position the two
    -- checks above needed.
    if settledX then
        x, y = settledX, settledY
    end

    -- Height is recorded with the position: a bag's window grows when the bag
    -- does, and the restore needs to know which edge the player aimed at. Stored
    -- unscaled, so Blizzard rescaling the bags does not read as a bag upgrade.
    local height = frame:GetHeight()
    pos = WritablePositions()
    local saved = pos[key]
    if not saved then
        saved = {}
        pos[key] = saved
    end
    saved.x, saved.y, saved.h = x, y, height
    -- Width and scale ride along for the same reason the defaults carry them.
    saved.w, saved.s = frame:GetWidth(), ScaleFactor(frame)
    -- The drag anchored it to UIParent already, so this normally changes
    -- nothing -- but it is what guarantees the next flush reads back exactly
    -- what was stored, whatever else touched the frame on the way.
    Place(frame, x, y)

    -- Snapping and overlap clearing happen in that flush rather than here: they
    -- have to align against the column *after* it has closed up around this
    -- drop, and only the flush knows where that puts everything.
    S.droppedFrame = frame

    -- Dragging is the whole interface: the rest of the column closes up as soon
    -- as the bag is dropped, not on the next bag open.
    Request()
end

-- Shift-right-click returns a single bag to the default stack.
local function OnMouseUp(frame, button)
    if button ~= "RightButton" or not IsShiftKeyDown() then
        return
    end
    if not SelectContext() then
        return
    end
    if ResetFrame(frame) then
        Request()
    end
end

local function OnFrameShow()
    Request()
end

--------------------------------------------------------------------------
-- attaching to the windows
--------------------------------------------------------------------------

-- If Blizzard ever ships native bag movement, get out of the way rather than
-- stacking a second drag handler on theirs -- the risk register calls that the
-- good outcome. Today ContainerFrameTemplate and ContainerFrameCombinedBags
-- have no OnDragStart, no RegisterForDrag and no Edit Mode registration, so
-- either signal appearing means Blizzard took the job over.
local function BlizzardMovesThisFrame(frame)
    -- EditModeSystemMixin:OnSystemLoad asserts that every Edit Mode system
    -- frame carries self.system, so it is a reliable marker.
    if frame.system ~= nil then
        return true
    end

    -- The ScriptBindings forbidden aspect makes querying or hooking scripts on
    -- a frame an error rather than a refusal. If a bag window ever gains it,
    -- stand down instead of throwing on every layout pass.
    local ok, handler = pcall(frame.GetScript, frame, "OnDragStart")
    if not ok then
        return true
    end
    return handler ~= nil
end

-- The title bar and the bag icon are child buttons of Blizzard's whose press
-- opens the bag's menu unless Shift is held, and a click on them never reaches
-- the window (DESIGN.md "The title bar"). So they are hooked for the drag and
-- the gestures, and a drag from them is forwarded only with Shift held: the
-- one press there the menu leaves alone. The window body needs no modifier.
-- Item buttons are never hooked; they are the part of a bag window closest to
-- Blizzard's secure path.
local function TitleDragStart(frame)
    if not IsShiftKeyDown() then
        return
    end
    OnDragStart(frame)
end

-- A plain drag on the title bar never started one here, so there is nothing to
-- stop. Forwarding regardless would run the drop logic on a window that was
-- never picked up, and that logic places the window.
local function TitleDragStop(frame)
    if S.dragging ~= frame then
        return
    end
    OnDragStop(frame)
end

local function HookTitleButton(button, frame)
    button:RegisterForDrag("LeftButton")
    button:HookScript("OnMouseDown", Guarded(function()
        Raise(frame)
    end))
    button:HookScript("OnDragStart", Guarded(function()
        TitleDragStart(frame)
    end))
    button:HookScript("OnDragStop", Guarded(function()
        TitleDragStop(frame)
    end))
    button:HookScript("OnMouseUp", Guarded(function(_, mouseButton)
        OnMouseUp(frame, mouseButton)
    end))
end

local function HookChildButtons(frame)
    local children = { frame:GetChildren() }

    for i = 1, #children do
        local child = children[i]
        -- The router carries the key/value Blizzard identifies it by, which is
        -- steadier than its position in the child list.
        if child.routeToSibling == "PortraitButton" then
            HookTitleButton(child, frame)
        end
    end

    if frame.PortraitButton then
        HookTitleButton(frame.PortraitButton, frame)
    end
end

-- Wrapped, for the same reason the stand-down check reads scripts through
-- pcall: a forbidden aspect on one of these children would make walking them an
-- error rather than a refusal, and a window that cannot be raised by its title
-- bar is worth much less than a window that errors on every layout pass.
local function HookTitleBar(frame)
    pcall(HookChildButtons, frame)
end

local function Attach(frame)
    if frame.moveMyBagsKuro then
        return
    end

    if BlizzardMovesThisFrame(frame) then
        -- Remembered so the decision is not re-made on every layout pass. The
        -- flusher still re-anchors this frame to break Blizzard's chain; it
        -- just never gets a saved position applied.
        frame.moveMyBagsKuro = "standby"
        return
    end
    frame.moveMyBagsKuro = "attached"

    -- The XML templates already set movable and enableMouse; set them anyway so
    -- the addon does not silently break if a template changes.
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")

    -- HookScript, never SetScript: we add handlers, we do not replace them.
    -- Item buttons register their own drag, so left-drag on an item still picks
    -- up the item rather than moving the bag.
    frame:HookScript("OnDragStart", Guarded(OnDragStart))
    frame:HookScript("OnDragStop", Guarded(OnDragStop))
    frame:HookScript("OnMouseUp", Guarded(OnMouseUp))
    -- Clicking a window brings it to the top layer. Only the layer changes --
    -- the position is untouched, and a locked window still comes forward. The
    -- window itself owns its border and the gaps in the item grid; its title bar
    -- and bag icon are separate buttons and are hooked by hand.
    frame:HookScript("OnMouseDown", Guarded(Raise))
    HookTitleBar(frame)
    -- Covers clients where UpdateContainerFrameAnchors is no longer a global.
    frame:HookScript("OnShow", Guarded(OnFrameShow))
end

local function AttachAll()
    for _, frame in ipairs(Containers()) do
        Attach(frame)
    end
end
core.AttachAll = AttachAll

--------------------------------------------------------------------------
-- hook
--------------------------------------------------------------------------

-- Post-hook only. Replacing this global is the classic taint vector, and doing
-- the SetPoint inline is what got Drift's item clicks blocked. The hook just
-- flags; the flusher does the work next frame, outside the secure stack that
-- opened the bags (ShowUIPanel -> SetUIPanel -> OpenAllBagsMatchingContext).
S.hooked = false

local function HookLayout()
    if S.hooked or not UpdateContainerFrameAnchors then
        return false
    end
    S.hooked = true
    hooksecurefunc("UpdateContainerFrameAnchors", Guarded(function()
        AttachAll()
        S.blizzardLaidOut = true
        Request()
    end))
    return true
end
core.HookLayout = HookLayout

-- Tried now, and again at PLAYER_LOGIN: if Blizzard_UIPanels_Game ever becomes
-- load-on-demand the global is nil while this file runs and appears later, and
-- giving up at load time would silently leave compacting off for good.
if not HookLayout() then
    -- Without a layout pass to measure and validate against, the column
    -- geometry can never be established. Dragging still works; the hole a
    -- moved bag leaves just stays open.
    S.gapsUnavailable = true
end
