-- MoveMyBags.Kuro -- the slash commands and the status report.

local ADDON, ns = ...
local L = ns.L

local core = ns.core
local S = ns.state

local Print = core.Print
local Option = core.Option
local Containers = core.Containers
local FrameKey = core.FrameKey
local ScaleFactor = core.ScaleFactor
local ReadPos = core.ReadPos
local SelectContext = core.SelectContext
local Contexts = core.Contexts
local ContextIsOwn = core.ContextIsOwn
local Locked = core.Locked
local LayoutNames = core.LayoutNames
local COMMAND = core.COMMAND
local COMBINED_KEY = core.COMBINED_KEY
local CONTEXT_DEFAULT = core.CONTEXT_DEFAULT
local LAYOUT_NAME_MAX = core.LAYOUT_NAME_MAX

local function Round(n)
    return math.floor(n + 0.5)
end

local function DescribeKey(key)
    if key == COMBINED_KEY then
        return "combined window"
    end
    return "bag " .. tostring(key)
end

-- Everything a bug report needs, in the order a reader needs it: what the
-- client is, whether the hooks found what they expect, which features are
-- standing down and why, and then the windows and positions themselves.
-- Reads state only; a status command that changed anything would make the
-- report untrustworthy.
local function Status()
    local version = C_AddOns and C_AddOns.GetAddOnMetadata
        and C_AddOns.GetAddOnMetadata(ADDON, "Version") or "?"
    local clientVersion, build, _, interface = "?", "?", nil, "?"
    if GetBuildInfo then
        clientVersion, build, _, interface = GetBuildInfo()
    end
    Print(string.format("status -- MoveMyBags.Kuro %s on client %s (build %s, interface %s)",
        tostring(version), tostring(clientVersion), tostring(build), tostring(interface)))

    Print("layout hook: " .. (S.hooked and "live (UpdateContainerFrameAnchors)"
        or "missing; relying on each window's OnShow"))

    local compacting
    if S.gapsUnavailable then
        compacting = S.hooked and "standing down (Blizzard's layout did not replay)"
            or "standing down (no layout hook to measure)"
    elseif S.geoValid then
        compacting = string.format("ready (%d column%s, spacing %s)",
            #S.geoColumns, #S.geoColumns == 1 and "" or "s", tostring(S.geoSpacing))
    else
        compacting = "not measured yet"
    end
    Print("compacting: " .. compacting)

    Print(string.format("options: connect %s, close holes %s, layers %s, contexts %s",
        Option("snap") and "on" or "off",
        Option("compact") and "on" or "off",
        Option("layers") and "on" or "off",
        Option("contexts") and "on" or "off"))
    if ns.EditModeStatus then
        Print("Edit Mode: " .. ns.EditModeStatus())
    end

    Print(string.format("layers: %s; locked: %s; dragging: %s",
        S.layered and "engaged" or "off",
        Locked() and "yes" or "no",
        S.dragging and DescribeKey(FrameKey(S.dragging)) or "nothing"))

    if S.errorCount == 0 then
        Print("errors: none")
    else
        Print(string.format("errors: %d%s -- last: %s", S.errorCount,
            S.broken and " (stood down for this session)" or "", tostring(S.lastError)))
    end

    if not SelectContext() then
        Print("saved positions: database not loaded yet")
    else
        local names = LayoutNames()
        Print(string.format("context: %s, %s; arrangement: %s; saved layouts: %d%s",
            S.context,
            ContextIsOwn() and "with its own arrangement" or "following the default arrangement",
            core.IsOwn() and "this character's" or "account-wide",
            #names, #names > 0 and (" (" .. table.concat(names, ", ") .. ")") or ""))

        local contexts, ordered, total = Contexts(), {}, 0
        for ctx, flat in pairs(contexts) do
            ordered[#ordered + 1] = ctx
            for _ in pairs(flat) do
                total = total + 1
            end
        end
        table.sort(ordered)
        Print("saved positions: " .. total)
        for _, ctx in ipairs(ordered) do
            for key, p in pairs(contexts[ctx]) do
                Print(string.format("  [%s] %s at %d,%d%s", ctx, DescribeKey(key), Round(p.x), Round(p.y),
                    p.h and string.format(" (height %d)", Round(p.h)) or ""))
            end
        end
    end

    local shown = 0
    for _, frame in ipairs(Containers()) do
        if frame:IsShown() then
            shown = shown + 1
            local key = FrameKey(frame)
            local x, y = ReadPos(frame)
            local where = x and string.format("%d,%d", Round(x), Round(y)) or "no rect"
            local state = frame.moveMyBagsKuro or "not attached"
            if state == "attached" then
                if S.pos and S.pos[key] then
                    state = "moved"
                elseif S.defaults[key] then
                    state = "on Blizzard's slot"
                end
            end
            Print(string.format("  %s shows %s: %s, level %s, at %s, scale %.2f",
                tostring(frame:GetName()), DescribeKey(key), state,
                tostring(frame:GetFrameLevel()), where, ScaleFactor(frame)))
        end
    end
    Print("windows on screen: " .. shown)
end

SLASH_MOVEMYBAGSKURO1 = "/movemybagskuro"
SLASH_MOVEMYBAGSKURO2 = "/mmbk"
SlashCmdList.MOVEMYBAGSKURO = function(msg)
    msg = msg or ""
    local command, rest = msg:match("^%s*(%a+)%s*(.-)%s*$")
    command = command and command:lower() or ""
    rest = rest or ""

    if command == "status" then
        local ok, err = pcall(Status)
        if not ok then
            Print(L["status failed: %s"]:format(tostring(err)))
        end

    elseif command == "levels" then
        local ok, err = pcall(core.TraceDumpLevels)
        if not ok then
            Print("levels failed: " .. tostring(err))
        end

    elseif command == "trace" then
        core.TraceCommand(rest)

    elseif command == "reset" then
        if rest:lower() == "all" then
            core.ResetAll()
            Print(L["all bag positions reset, in every context."])
        else
            core.ResetContext()
            if S.context == CONTEXT_DEFAULT then
                Print(L["all bag positions reset."])
            else
                Print(L["the %s arrangement is forgotten; it follows your usual one again."]:format(S.context))
            end
        end

    elseif command == "save" or command == "load" or command == "delete" then
        local name = core.LayoutName(rest)
        if not name then
            Print(L["give the layout a name of up to %d characters: %s"]:format(LAYOUT_NAME_MAX,
                COMMAND:format("/mmbk " .. command .. " <name>")))
        elseif command == "save" then
            core.SaveLayout(name)
            Print(L["layout '%s' saved."]:format(name))
        elseif command == "load" then
            if core.LoadLayout(name) then
                Print(L["layout '%s' loaded."]:format(name))
            else
                Print(L["no layout called '%s'. %s lists them."]:format(name, COMMAND:format("/mmbk layouts")))
            end
        else
            if core.DeleteLayout(name) then
                Print(L["layout '%s' deleted."]:format(name))
            else
                Print(L["no layout called '%s'. %s lists them."]:format(name, COMMAND:format("/mmbk layouts")))
            end
        end

    elseif command == "layouts" then
        local names = LayoutNames()
        if #names == 0 then
            Print(L["no saved layouts. %s saves the current arrangement under a name."]:format(
                COMMAND:format("/mmbk save <name>")))
        else
            Print(L["saved layouts: %s"]:format(table.concat(names, ", ")))
        end

    elseif command == "lock" or command == "unlock" then
        if not MoveMyBagsKuroDB then
            return
        end
        local lock = command == "lock"
        if lock == Locked() then
            Print(lock and L["bags are already locked."] or L["bags are not locked."])
        else
            core.SetLocked(lock)
            Print(lock and L["bags locked. %s to move them again."]:format(COMMAND:format("/mmbk unlock"))
                or L["bags unlocked."])
        end

    elseif command == "config" or command == "options" then
        if ns.OpenSettings then
            ns.OpenSettings()
        end

    else
        Print(L["drag a bag window by its frame to move it, or Shift-drag its title bar. Shift-right-click a window to put it back. %s puts them all back; %s stops them being dragged; %s opens the options; %s shows what the addon is doing."]
            :format(COMMAND:format("/mmbk reset"), COMMAND:format("/mmbk lock"),
                COMMAND:format("/mmbk config"), COMMAND:format("/mmbk status")))
        Print(L["%s, %s and %s keep arrangements by name; %s lists them. The bank and a merchant each remember their own arrangement once you move a bag there."]
            :format(COMMAND:format("/mmbk save <name>"), COMMAND:format("/mmbk load <name>"),
                COMMAND:format("/mmbk delete <name>"), COMMAND:format("/mmbk layouts")))
    end
end
