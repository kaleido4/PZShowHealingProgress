dofile(ROOT .. "/tests/harness.lua")
dofile(MOD .. "client/ShowHealingProgress/SHP_Core.lua")

-- A local player's store after the first scan, so new wounds are seen starting.
local function trackedStore(bp)
    local store = {}
    SHP.update(store, javaList({ bp }), true)
    return store
end

local function scan(store, bp, trust)
    if trust == nil then trust = true end
    SHP.update(store, javaList({ bp }), trust)
end

local function lines(store, bp)
    return SHP.getLines(store, bp)
end

local function onlyLine(store, bp)
    local l = lines(store, bp)
    eq(#l, 1, "line count")
    return l[1]
end

print("SHP core")

test("a new wound starts at 0% and counts up as it heals", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.cutTime = 20
    scan(store, bp)
    local line = onlyLine(store, bp)
    eq(line.label, "IGUI_health_Cut")
    near(line.progress, 0)
    eq(line.est, false, "est")
    heal(bp, 5)
    near(onlyLine(store, bp).progress, 0.25, "live value without a rescan")
    scan(store, bp)
    near(onlyLine(store, bp).progress, 0.25)
end)

test("a wound healed without treatment disappears", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.scratchTime = 10
    scan(store, bp)
    heal(bp, 10)
    scan(store, bp)
    eq(#lines(store, bp), 0, "lines")
    eq(count(store.parts), 0, "tracked parts")
end)

test("a healed wound stays at 100% until the bandage comes off", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.scratchTime = 10
    bp.isBandaged = true
    scan(store, bp)
    heal(bp, 12)
    scan(store, bp)
    local line = onlyLine(store, bp)
    eq(line.progress, 1)
    eq(SHP.percent(line.progress), 100)
    scan(store, bp)
    eq(onlyLine(store, bp).progress, 1, "still there on the next scan")
    bp.isBandaged = false
    scan(store, bp)
    eq(#lines(store, bp), 0, "lines after removing the bandage")
    eq(count(store.parts), 0, "tracked parts")
end)

test("a healed fracture stays at 100% until the splint comes off", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.fractureTime = 60
    bp.splintFactor = 3
    scan(store, bp)
    heal(bp, 30)
    near(onlyLine(store, bp).progress, 0.5)
    heal(bp, 30)
    scan(store, bp)
    eq(onlyLine(store, bp).progress, 1)
    bp.splintFactor = 0
    scan(store, bp)
    eq(#lines(store, bp), 0)
end)

test("percent rounds down so 100 means healed", function()
    eq(SHP.percent(0.999), 99)
    eq(SHP.percent(0.5), 50)
    eq(SHP.percent(1), 100)
end)

test("stitching replaces the deep wound line with a stitch line", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.deepWoundTime = 18
    scan(store, bp)
    eq(onlyLine(store, bp).label, "IGUI_health_DeepWound")
    stitch(bp, 10)
    scan(store, bp)
    local line = onlyLine(store, bp)
    eq(line.label, "IGUI_health_Stitched")
    near(line.progress, 0.25, "10 of 40")
    bp.stitchTime = 40
    eq(onlyLine(store, bp).progress, 1, "removable at 40")
    bp.stitchTime = 50
    eq(onlyLine(store, bp).progress, 1, "capped")
end)

test("the stitch line stays when a bandage goes over the stitches", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.deepWoundTime = 18
    scan(store, bp)
    stitch(bp, 10)
    scan(store, bp)
    bp.isBandaged = true
    eq(bp:stitched(), false, "game flag while bandaged")
    scan(store, bp)
    local line = onlyLine(store, bp)
    eq(line.label, "IGUI_health_Stitched")
    near(line.progress, 0.25)
    bp.stitchTime = 30 -- keeps counting under the bandage
    scan(store, bp)
    near(onlyLine(store, bp).progress, 0.75)
end)

test("stitched and bandaged between two scans does not look like a healed deep wound", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.deepWoundTime = 18
    scan(store, bp)
    stitch(bp, 10)
    bp.isBandaged = true
    scan(store, bp)
    local line = onlyLine(store, bp)
    eq(line.label, "IGUI_health_Stitched")
end)

test("removing stitches early reopens the deep wound from 0%", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.deepWoundTime = 18
    scan(store, bp)
    heal(bp, 4)
    scan(store, bp)
    stitch(bp, 10)
    scan(store, bp)
    removeStitches(bp, 12)
    scan(store, bp)
    local line = onlyLine(store, bp)
    eq(line.label, "IGUI_health_DeepWound")
    near(line.progress, 0)
    eq(line.est, false)
end)

test("removing stitches from 40 on leaves a small scratch that is tracked", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    stitch(bp, 45)
    scan(store, bp)
    removeStitches(bp, 4)
    scan(store, bp)
    local line = onlyLine(store, bp)
    eq(line.label, "IGUI_health_Scratched")
    near(line.progress, 0)
end)

test("a new injury on the same wound restarts from 0%", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.scratchTime = 10
    scan(store, bp)
    heal(bp, 5)
    scan(store, bp)
    near(onlyLine(store, bp).progress, 0.5)
    bp.scratchTime = 8 -- rolled lower than the first scratch, higher than what was left
    scan(store, bp)
    near(onlyLine(store, bp).progress, 0)
end)

test("a new injury after healing under a bandage is tracked again", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.cutTime = 10
    bp.isBandaged = true
    scan(store, bp)
    heal(bp, 10)
    scan(store, bp)
    eq(onlyLine(store, bp).progress, 1)
    bp.cutTime = 15
    scan(store, bp)
    near(onlyLine(store, bp).progress, 0)
end)

test("an unbandaged deep wound held at 3 is not a new injury and says why", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.deepWoundTime = 20
    bp.isBandaged = true
    scan(store, bp)
    heal(bp, 18) -- 2 left while bandaged
    scan(store, bp)
    near(onlyLine(store, bp).progress, 0.9)
    bp.isBandaged = false
    heal(bp, 0) -- the game lifts it back to 3
    eq(bp.deepWoundTime, 3, "mock floor")
    scan(store, bp)
    local line = onlyLine(store, bp)
    near(line.progress, 0.85, "not reset")
    eq(line.hint, "IGUI_SHP_NeedsBandage")
end)

test("a deep wound held at 3 by glass says so even when bandaged", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.deepWoundTime = 20
    bp.glass = true
    bp.isBandaged = true
    scan(store, bp)
    heal(bp, 30)
    scan(store, bp)
    eq(onlyLine(store, bp).hint, "IGUI_SHP_GlassInside")
end)

test("no hint while a deep wound is still healing", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.deepWoundTime = 20
    scan(store, bp)
    heal(bp, 10)
    eq(onlyLine(store, bp).hint, nil)
end)

test("wounds already there on the first scan are estimated", function()
    local bp = newBodyPart()
    bp.scratchTime = 6
    bp.fractureTime = 90
    local store = {}
    scan(store, bp)
    local l = lines(store, bp)
    eq(#l, 2)
    eq(l[1].label, "IGUI_health_Scratched")
    eq(l[1].est, true)
    near(l[1].progress, 1 - 6 / 15, "guessed start")
    eq(l[2].label, "IGUI_health_Fracture")
    eq(l[2].est, true)
    near(l[2].progress, 0, "worse than the usual start")
    bp.scratchTime = 12 -- a new scratch on top
    scan(store, bp)
    eq(lines(store, bp)[1].est, false, "new injury is seen starting")
end)

test("the first-scan flag is saved in the store", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    eq(store.init, true)
    bp.burnTime = 70
    scan(store, bp)
    eq(onlyLine(store, bp).est, false)
end)

test("another player's wounds are estimated when first seen", function()
    local bp = newBodyPart()
    local store = {}
    scan(store, bp, false)
    bp.cutTime = 10
    scan(store, bp, false)
    eq(onlyLine(store, bp).est, true)
end)

test("several wounds on one body part get one line each, in panel order", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.burnTime = 50
    bp.biteTime = 60
    bp.scratchTime = 5
    stitch(bp, 20)
    scan(store, bp)
    local l = lines(store, bp)
    eq(#l, 4)
    eq(l[1].label, "IGUI_health_Scratched")
    eq(l[2].label, "IGUI_health_Bitten")
    eq(l[3].label, "IGUI_health_Burned")
    eq(l[4].label, "IGUI_health_Stitched")
end)

test("a healed wound next to one still healing goes once nothing is applied", function()
    local bp = newBodyPart()
    local store = trackedStore(bp)
    bp.scratchTime = 5
    bp.fractureTime = 40
    scan(store, bp)
    heal(bp, 5)
    scan(store, bp)
    local line = onlyLine(store, bp)
    eq(line.label, "IGUI_health_Fracture")
end)

test("body parts are tracked separately", function()
    local a, b = newBodyPart(3), newBodyPart(7)
    local store = {}
    SHP.update(store, javaList({ a, b }), true)
    a.cutTime = 10
    b.cutTime = 20
    SHP.update(store, javaList({ a, b }), true)
    heal(a, 5)
    heal(b, 5)
    near(onlyLine(store, a).progress, 0.5)
    near(onlyLine(store, b).progress, 0.25)
end)

finish("SHP core")
