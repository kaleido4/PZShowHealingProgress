--[[
    Test harness: assertions and a mock of the bits of the Project Zomboid API
    the mod uses. BodyPart follows the game code (B42.21) where it matters:
      * stitching zeroes the deep wound timer;
      * the stitched flag reads false while bandaged (setBandaged clears it,
        removing the bandage sets it again from the stitch timer);
      * removing stitches before 40 reopens the deep wound, from 40 on it
        leaves a small scratch;
      * heal(bp, amount) lowers every wound timer, and an unbandaged (or
        glass-filled) deep wound stops at 3.
--]]

MOD = ROOT .. "/Contents/mods/PZShowHealingProgress/common/media/lua/"

local passed, failed = 0, 0

function test(name, fn)
    local ok, err = pcall(fn)
    if ok then
        passed = passed + 1
        print("  ok   " .. name)
    else
        failed = failed + 1
        print("  FAIL " .. name .. ": " .. tostring(err))
    end
end

function finish(suite)
    print(suite .. ": " .. passed .. " passed, " .. failed .. " failed")
    if failed > 0 then error(suite .. ": " .. failed .. " test(s) failed") end
end

function eq(actual, expected, what)
    if actual ~= expected then
        error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

function near(actual, expected, what)
    if math.abs(actual - expected) > 0.0001 then
        error((what or "value") .. ": expected " .. tostring(expected) .. ", got " .. tostring(actual))
    end
end

function truthy(v, what)
    if not v then error((what or "value") .. ": expected true, got " .. tostring(v)) end
end

function count(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

function javaList(t)
    return {
        size = function() return #t end,
        get = function(_, i) return t[i + 1] end,
    }
end

---------------------------------------------------------------------------
-- Body parts
---------------------------------------------------------------------------

local TIMERS = { "scratchTime", "cutTime", "deepWoundTime", "biteTime", "fractureTime", "burnTime" }

function newBodyPart(index)
    local bp = {
        index = index or 0,
        scratchTime = 0, cutTime = 0, deepWoundTime = 0, biteTime = 0, fractureTime = 0, burnTime = 0,
        stitchTime = 0, isStitched = false,
        isBandaged = false, splintFactor = 0, glass = false,
    }
    function bp:getIndex() return self.index end
    function bp:getScratchTime() return self.scratchTime end
    function bp:getCutTime() return self.cutTime end
    function bp:getDeepWoundTime() return self.deepWoundTime end
    function bp:getBiteTime() return self.biteTime end
    function bp:getFractureTime() return self.fractureTime end
    function bp:getBurnTime() return self.burnTime end
    function bp:getStitchTime() return self.stitchTime end
    function bp:stitched() return self.isStitched and not self.isBandaged end
    function bp:bandaged() return self.isBandaged end
    function bp:isSplint() return self.splintFactor > 0 end
    function bp:getSplintFactor() return self.splintFactor end
    function bp:haveGlass() return self.glass end
    return bp
end

function heal(bp, amount)
    for _, field in ipairs(TIMERS) do
        local value = bp[field]
        if value > 0 then
            value = value - amount
            -- The game applies the floor before checking for "healed", so such a
            -- deep wound never reaches 0.
            if field == "deepWoundTime" and value < 3 and (bp.glass or not bp.isBandaged) then
                value = 3
            end
            bp[field] = math.max(0, value)
        end
    end
end

function stitch(bp, stitchTime)
    bp.isStitched = true
    bp.deepWoundTime = 0
    bp.stitchTime = stitchTime
end

function removeStitches(bp, newWoundTime)
    bp.isStitched = false
    if bp.stitchTime < 40 then
        bp.deepWoundTime = newWoundTime
    else
        bp.scratchTime = newWoundTime
    end
    bp.stitchTime = 0
end
