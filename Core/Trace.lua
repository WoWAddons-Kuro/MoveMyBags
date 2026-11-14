-- MoveMyBags.Kuro -- diagnostic tracing for the frame-level bug.
--
-- Symptom under investigation: a container window's Bg child frame ends up at
-- MAX_FRAME_LEVEL (10000) while the window itself is at level 1, so the
-- semi-transparent background paints over the item buttons. Bg normally sits
-- one level *below* its window, so a window reaching level 0 would push Bg to
-- -1, which the client cannot represent. This module records who moves
-- container frame levels, and dumps the live child-level picture on demand.
--
--   /mmbk levels   -- every container: its level, each child's level and the
--                     offset it had when first seen; mismatches are flagged
--   /mmbk trace    -- the last TRACE_CAPACITY SetFrameLevel calls on
--                     containers, newest last, with a short call stack
--   /mmbk trace clear

local _, ns = ...

local core = ns.core
local S = ns.state

local Print = core.Print
local Containers = core.Containers
local FrameKey = core.FrameKey

local TRACE_CAPACITY = 60

-- Ring buffer of SetFrameLevel calls on container windows.
local traceEntries = {}       -- array of strings, oldest first

-- frame -> { [child] = offsetFromWindowWhenFirstSeen }
local childOffsetsByFrame = {}

-- frame -> true once hooked
local hookedFrames = {}

S.traceLowLevelCount = 0      -- SetFrameLevel calls asking for < 1

local function ChildName(frame, child)
    local name = child:GetName()
    if name then
        return name
    end
    local key = child.GetParentKey and child:GetParentKey()
    if key then
        return tostring(frame:GetName()) .. "." .. tostring(key)
    end
    return "<anon " .. tostring(child:GetObjectType()) .. ">"
end

local function Record(text)
    traceEntries[#traceEntries + 1] = text
    if #traceEntries > TRACE_CAPACITY then
        table.remove(traceEntries, 1)
    end
end

-- A compact stack: the first few frames that are not this file.
local function ShortStack()
    local stack = debugstack(3, 6, 0) or ""
    local lines = {}
    for line in stack:gmatch("[^\n]+") do
        line = line:gsub("^%s*%[string \"", ""):gsub("\"%]", "")
        line = line:gsub("Interface/AddOns/", "")
        lines[#lines + 1] = line
    end
    return table.concat(lines, " <- ")
end

local function SnapshotChildOffsets(frame)
    local offsets = {}
    local base = frame:GetFrameLevel() or 0
    local children = { frame:GetChildren() }
    for i = 1, #children do
        local child = children[i]
        offsets[child] = (child:GetFrameLevel() or 0) - base
    end
    childOffsetsByFrame[frame] = offsets
end

local function OnSetFrameLevel(frame, level)
    local flag = ""
    if type(level) == "number" and level < 1 then
        S.traceLowLevelCount = S.traceLowLevelCount + 1
        flag = " |cffff4040<<< BELOW 1|r"
    end
    Record(string.format("%s %s -> %s%s  combat=%s  %s",
        date("%H:%M:%S"), tostring(frame:GetName()), tostring(level), flag,
        InCombatLockdown() and "yes" or "no", ShortStack()))
end

-- Called from the flush every pass; hooks any container not yet hooked and
-- takes the offset snapshot the first time the window is seen.
function core.TraceAttach()
    for _, frame in ipairs(Containers()) do
        if not hookedFrames[frame] then
            hookedFrames[frame] = true
            hooksecurefunc(frame, "SetFrameLevel", OnSetFrameLevel)
            SnapshotChildOffsets(frame)
        end
    end
end

-- Put back any child whose level no longer matches the offset it had when we
-- first saw the window. This is what heals a Bg stranded at MAX_FRAME_LEVEL:
-- whether the window reached an invalid level through our band or through
-- Blizzard's own layout, the child is returned to where its template put it.
-- A child whose restored level would be negative is left alone -- setting it
-- would just re-trigger the wrap -- so the band's LEVEL_FLOOR is what keeps
-- this from ever being needed in the first place.
S.traceRepairCount = 0

function core.TraceRepairChildren(frame)
    local offsets = childOffsetsByFrame[frame]
    if not offsets then
        return
    end
    local base = frame:GetFrameLevel() or 0
    for child, offset in pairs(offsets) do
        local expected = base + offset
        if expected >= 0 and expected <= 10000 then
            local level = child:GetFrameLevel() or 0
            if level ~= expected then
                child:SetFrameLevel(expected)
                S.traceRepairCount = S.traceRepairCount + 1
                Record(string.format("%s REPAIR %s %d -> %d (window at %d)",
                    date("%H:%M:%S"), ChildName(frame, child), level, expected, base))
            end
        end
    end
end

local function DumpLevels()
    local shownOnly = true
    for _, frame in ipairs(Containers()) do
        if not shownOnly or frame:IsShown() then
            local base = frame:GetFrameLevel() or 0
            Print(string.format("%s (%s) level %d, shown=%s, strata=%s",
                tostring(frame:GetName()), tostring(FrameKey(frame)), base,
                frame:IsShown() and "yes" or "no", tostring(frame:GetFrameStrata())))
            local offsets = childOffsetsByFrame[frame] or {}
            local children = { frame:GetChildren() }
            for i = 1, #children do
                local child = children[i]
                local level = child:GetFrameLevel() or 0
                local offset = offsets[child]
                local expected = offset and (base + offset) or nil
                local flag = ""
                if expected and expected ~= level then
                    flag = string.format(" |cffff4040MISMATCH expected %d|r", expected)
                elseif not expected then
                    flag = " (new child, no snapshot)"
                end
                -- Only print chrome and anything wrong; the item buttons are many.
                local name = ChildName(frame, child)
                if flag ~= "" or not name:find("^<anon") then
                    Print(string.format("    %s level %d (offset %s)%s",
                        name, level, offset and tostring(offset) or "?", flag))
                end
            end
        end
    end
    Print(string.format("SetFrameLevel calls below 1 this session: %d", S.traceLowLevelCount))
end

local function DumpTrace()
    if #traceEntries == 0 then
        Print("trace: no SetFrameLevel calls recorded on container windows yet")
        return
    end
    Print(string.format("trace: last %d SetFrameLevel calls on containers (oldest first)", #traceEntries))
    for i = 1, #traceEntries do
        Print("  " .. traceEntries[i])
    end
end

function core.TraceCommand(rest)
    rest = (rest or ""):lower()
    if rest == "clear" then
        wipe(traceEntries)
        S.traceLowLevelCount = 0
        Print("trace cleared")
    else
        DumpTrace()
    end
end

core.TraceDumpLevels = DumpLevels