--[[
    Show Healing Progress - wound tracking (no UI, unit-tested).

    The game only keeps the time a wound has left to heal (BodyPart.DamageUpdate,
    B42.21): scratch, cut, deep wound, bite, fracture and burn timers start at a
    random value and count down to 0, which is when the wound is healed. So we
    remember the value each wound started at (its peak) and show
    1 - remaining / peak.

    A wound can also get worse before it heals: walking barefoot or in broken
    shoes adds up to 3 to a foot's scratch or cut (IsoPlayer.updateFootInjuries),
    a new scratch, cut or fracture on the same body part replaces the timer with
    a new roll, and an unbandaged deep wound is pushed back up to 3. The peak
    then moves up to the worst value seen, so progress drops instead of
    starting over. A wound that healed and comes back starts again from 0%.

    Stitches work the other way: stitching zeroes the deep wound timer and a
    stitch timer counts up instead. Stitches can be removed safely from 40 on
    (removing them earlier reopens the deep wound), so their progress is
    stitchTime / 40 and needs no tracking. Bandaging clears the stitched flag
    (BodyPart.setBandaged) and removing the bandage sets it again from the
    stitch timer, which keeps running under the bandage, so we go by the timer.

    A healed wound stays at 100% while a bandage, stitches or a splint is still
    on the body part, and disappears once they are all removed.

    Store layout (lives in the player's mod data, so it is saved with the game):
        store.init           true after the first scan
        store.parts[index]   records of one body part, by BodyPart:getIndex()
            [wound id] = { peak, est, done }
                peak  worst value the wound has had
                est   start was not seen (wound existed before the mod was
                      added, or another player's body): peak is a guess
                done  healed, kept while the body part still has treatment
--]]

SHP = SHP or {}

-- typical: the largest starting value the game normally rolls for this wound,
-- used as a guess when we did not see the wound start.
SHP.WOUNDS = {
    { id = "scratch",   label = "IGUI_health_Scratched", typical = 15,  get = function(bp) return bp:getScratchTime() end },
    { id = "cut",       label = "IGUI_health_Cut",       typical = 20,  get = function(bp) return bp:getCutTime() end },
    { id = "deepWound", label = "IGUI_health_DeepWound", typical = 20,  get = function(bp) return bp:getDeepWoundTime() end },
    { id = "bite",      label = "IGUI_health_Bitten",    typical = 80,  get = function(bp) return bp:getBiteTime() end },
    { id = "fracture",  label = "IGUI_health_Fracture",  typical = 80,  get = function(bp) return bp:getFractureTime() end },
    { id = "burn",      label = "IGUI_health_Burned",    typical = 100, get = function(bp) return bp:getBurnTime() end },
}
SHP.STITCH_LABEL = "IGUI_health_Stitched"
SHP.STITCH_REMOVABLE = 40
-- A deep wound stops healing at 3 unless it is bandaged and free of glass.
SHP.DEEP_WOUND_FLOOR = 3

local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

-- Not bp:stitched(), which is false while a bandage covers the stitches.
function SHP.isStitched(bp)
    return bp:getStitchTime() > 0
end

function SHP.hasTreatment(bp)
    return bp:bandaged() or SHP.isStitched(bp) or bp:isSplint() or bp:getSplintFactor() > 0
end

local function isEmpty(t)
    for _ in pairs(t) do return false end -- Kahlua has no next()
    return true
end

-- Updates the records of one body part.
-- seenStart: a wound that has no record yet started just now (false on the
-- first scan, and for other players whose body we only see while treating them).
function SHP.updatePart(store, bp, seenStart)
    store.parts = store.parts or {}
    local key = bp:getIndex()
    local part = store.parts[key] or {}
    local treated = SHP.hasTreatment(bp)

    for _, wound in ipairs(SHP.WOUNDS) do
        local value = wound.get(bp)
        local rec = part[wound.id]
        if wound.id == "deepWound" and SHP.isStitched(bp) then
            -- Stitching zeroes the timer without healing it; the stitch line takes over.
            part[wound.id] = nil
        elseif value > 0 then
            if not rec or rec.done then
                -- A new wound, or a healed one that came back.
                local est = not seenStart and not rec
                rec = { peak = value, est = est }
                if est then rec.peak = math.max(value, wound.typical) end
                part[wound.id] = rec
            elseif value > rec.peak then
                -- Worse than ever seen (and worse than any guess): measure from here.
                rec.peak = value
                rec.est = false
            end
        elseif rec then
            if treated then
                rec.done = true
            else
                part[wound.id] = nil
            end
        end
    end

    if isEmpty(part) then
        store.parts[key] = nil
    else
        store.parts[key] = part
    end
end

function SHP.update(store, bodyParts, trustNewWounds)
    local seenStart = trustNewWounds and store.init == true
    for i = 0, bodyParts:size() - 1 do
        SHP.updatePart(store, bodyParts:get(i), seenStart)
    end
    store.init = true
end

-- Lines to show under a body part, in the order the health panel lists wounds:
-- { label = translation key, progress = 0..1, est = bool, hint = translation key or nil }
-- Active wounds use the live timer, so the text never lags behind the game.
function SHP.getLines(store, bp)
    local lines = {}
    local part = store.parts and store.parts[bp:getIndex()]
    if part then
        for _, wound in ipairs(SHP.WOUNDS) do
            local rec = part[wound.id]
            if rec then
                local value = wound.get(bp)
                local line = { label = wound.label, est = rec.est == true }
                if rec.done or value <= 0 then
                    line.progress = 1
                else
                    line.progress = clamp01(1 - value / rec.peak)
                    if wound.id == "deepWound" and value <= SHP.DEEP_WOUND_FLOOR then
                        if bp:haveGlass() then
                            line.hint = "IGUI_SHP_GlassInside"
                        elseif not bp:bandaged() then
                            line.hint = "IGUI_SHP_NeedsBandage"
                        end
                    end
                end
                lines[#lines + 1] = line
            end
        end
    end
    if SHP.isStitched(bp) then
        lines[#lines + 1] = {
            label = SHP.STITCH_LABEL,
            progress = clamp01(bp:getStitchTime() / SHP.STITCH_REMOVABLE),
            est = false,
        }
    end
    return lines
end

-- Sandbox: First Aid level needed to see the lines, 0 (anyone) to 10.
function SHP.requiredLevel()
    local vars = SandboxVars and SandboxVars.PZShowHealingProgress
    local level = vars and tonumber(vars.RequiredFirstAidLevel) or 0
    return math.max(0, math.min(10, level))
end

-- Whether someone with this First Aid level may see the lines.
function SHP.canSee(firstAidLevel)
    return (firstAidLevel or 0) >= SHP.requiredLevel()
end

-- Sandbox TextColor: a hex color like "8CCCFF" (the sandbox page has a color
-- picker for it, see SHP_SandboxColor.lua). Light blue unless set.
SHP.DEFAULT_COLOR_HEX = "8CCCFF"

local HEX_DIGITS = "0123456789ABCDEF"

-- "8CCCFF" or "#8cccff" -> r, g, b in 0..1; nil if it is not a 6-digit hex color.
function SHP.parseColor(text)
    if type(text) ~= "string" then return nil end
    local hex = string.match(text, "^%s*#?(%x%x%x%x%x%x)%s*$")
    if not hex then return nil end
    return tonumber(string.sub(hex, 1, 2), 16) / 255,
        tonumber(string.sub(hex, 3, 4), 16) / 255,
        tonumber(string.sub(hex, 5, 6), 16) / 255
end

-- r, g, b in 0..1 -> "8CCCFF".
function SHP.toHex(r, g, b)
    local out = ""
    for _, v in ipairs({ r, g, b }) do
        local n = math.floor(math.max(0, math.min(1, v)) * 255 + 0.5)
        local hi, lo = math.floor(n / 16), n % 16
        out = out .. string.sub(HEX_DIGITS, hi + 1, hi + 1) .. string.sub(HEX_DIGITS, lo + 1, lo + 1)
    end
    return out
end

-- r, g, b of the text, from the sandbox TextColor option. Drawn every frame,
-- so the last parse is kept. lastText starts as a value no option can have,
-- so the first call always parses (even when the option is missing: nil).
local NOT_PARSED = {}
local lastText, lastR, lastG, lastB = NOT_PARSED
function SHP.textColor()
    local vars = SandboxVars and SandboxVars.PZShowHealingProgress
    local text = vars and vars.TextColor
    if text ~= lastText then
        lastText = text
        lastR, lastG, lastB = SHP.parseColor(text)
        if not lastR then lastR, lastG, lastB = SHP.parseColor(SHP.DEFAULT_COLOR_HEX) end
    end
    return lastR, lastG, lastB
end

-- Whole percent, rounded down so 100 only shows once the wound is really healed.
function SHP.percent(progress)
    return math.floor(progress * 100)
end
