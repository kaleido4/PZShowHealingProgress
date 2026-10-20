dofile(ROOT .. "/tests/harness.lua")

-- The bits of the game SHP_Client.lua needs to load, as in test_client.lua.
local function setupGame(opts)
    opts = opts or {}
    local game = { players = {}, client = opts.client or false }
    Events = setmetatable({}, { __index = function(t, name)
        local ev = { handlers = {} }
        ev.Add = function(fn) ev.handlers[#ev.handlers + 1] = fn end
        rawset(t, name, ev)
        return ev
    end })
    require = function() end
    isClient = function() return game.client end
    UIFont = { Small = "Small" }
    getTextManager = function() return { getFontHeight = function() return 10 end } end
    getText = function(key, a)
        local templates = { IGUI_SHP_Healed = "%1 healed", IGUI_SHP_Progress = "%1: %2 healed" }
        local s = templates[key] or key
        if a ~= nil then s = string.gsub(s, "%%1", function() return tostring(a) end) end
        return s
    end
    getNumActivePlayers = function() return #game.players end
    getSpecificPlayer = function(i) return game.players[i + 1] end
    Perks = { Doctor = "Doctor" }
    SandboxVars = { PZShowHealingProgress = { RequiredFirstAidLevel = opts.required } }
    ISHealthPanel = {}
    function ISHealthPanel:update() end
    ISHealthBodyPartListBox = {}
    function ISHealthBodyPartListBox:doDrawItem(y) return y + 15 end
    return game
end

-- A mock of Wounds Overhaul's body view: refresh() rebuilds woundInfo from the
-- body, labels and notes as in its vanillaEntries, plus a condition of its own.
local function installWoundsOverhaul()
    Wounds = { body = {} }
    function Wounds.body.damage(player)
        if isClient() and not player:isLocalPlayer() then return player:getBodyDamageRemote() end
        return player:getBodyDamage()
    end
    WoundsBodyView = {}
    WoundsBodyView.__index = WoundsBodyView
    function WoundsBodyView:refresh()
        self.refreshes = (self.refreshes or 0) + 1
        local info = {}
        local parts = Wounds.body.damage(self.player):getBodyParts()
        for i = 0, parts:size() - 1 do
            local p = parts:get(i)
            local out = {}
            local function add(key, detail) out[#out + 1] = { label = { key, key }, detail = detail, vanilla = true } end
            if p:getFractureTime() > 0 then add("IGUI_health_Fracture", p:isSplint() and "splinted" or "no splint") end
            if p:getBiteTime() > 0 then add("IGUI_health_Bitten") end
            if p:getDeepWoundTime() > 0 then add(self.gunshot and "IGUI_Wounds_GunshotWound" or "IGUI_health_DeepWound") end
            if p:getBurnTime() > 0 then add("IGUI_Wounds_VBurn") end
            if p:getCutTime() > 0 then add("IGUI_health_Cut") end
            if p:getScratchTime() > 0 then add("IGUI_health_Scratched") end
            if p:getStitchTime() > 0 then add(self.packed and "IGUI_Wounds_Packed" or "IGUI_health_Stitched", "92% quality") end
            if self.infection then out[#out + 1] = { label = { "IGUI_Sepsis_Wound", "Infection" }, detail = "spreading" } end
            if #out > 0 then info[tostring(i)] = out end
        end
        self.woundInfo = info
        return "refreshed"
    end
end

local function newPlayer(parts, opts)
    opts = opts or {}
    local p = { modData = {}, parts = parts, isLocal = opts.isLocal ~= false, username = opts.username or "bob", firstAid = opts.firstAid or 0 }
    function p:getModData() return self.modData end
    function p:isLocalPlayer() return self.isLocal end
    function p:isDead() return false end
    function p:getUsername() return self.username end
    function p:getPerkLevel(perk) return perk == Perks.Doctor and self.firstAid or 0 end
    function p:getBodyDamage() local s = self return { getBodyParts = function() return javaList(s.parts) end } end
    function p:getBodyDamageRemote() return self:getBodyDamage() end
    return p
end

local function loadMod()
    dofile(MOD .. "client/ShowHealingProgress/SHP_Core.lua")
    dofile(MOD .. "client/ShowHealingProgress/SHP_Client.lua")
    dofile(MOD .. "client/ShowHealingProgress/SHP_WoundsOverhaul.lua")
end

local function fire(name, a, b)
    local ev = rawget(Events, name)
    if not ev then return end
    for i = 1, #ev.handlers do ev.handlers[i](a, b) end
end

-- A player whose first scan is done, so new wounds are seen starting.
local function setup(opts)
    opts = opts or {}
    local game = setupGame(opts)
    installWoundsOverhaul()
    loadMod()
    fire("OnGameStart")
    local bp = newBodyPart(0)
    local player = newPlayer({ bp }, opts)
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    local view = setmetatable({ player = player }, WoundsBodyView)
    return view, bp, player, game
end

local function entry(view, label)
    for _, e in ipairs((view.woundInfo or {})["0"] or {}) do
        if e.label[1] == label then return e end
    end
    return nil
end

print("SHP Wounds Overhaul")

test("without Wounds Overhaul the file does nothing", function()
    setupGame()
    Wounds, WoundsBodyView = nil, nil
    loadMod()
    fire("OnGameStart")
    eq(SHP.installWoundsOverhaul(), false)
    eq(WoundsBodyView, nil)
end)

test("progress goes into the note of the matching wound", function()
    local view, bp = setup()
    bp.fractureTime = 40
    bp.splintFactor = 2
    eq(view:refresh(), "refreshed", "their result is passed on")
    heal(bp, 10)
    view:refresh()
    eq(entry(view, "IGUI_health_Fracture").detail, "splinted, 25% healed")
end)

test("a wound with no note gets the progress as its note", function()
    local view, bp = setup()
    bp.cutTime = 20
    view:refresh()
    heal(bp, 15)
    view:refresh()
    eq(entry(view, "IGUI_health_Cut").detail, "75% healed")
end)

test("their burn and gunshot labels map to ours", function()
    local view, bp = setup()
    bp.burnTime = 80
    bp.deepWoundTime = 20
    view.gunshot = true
    view:refresh()
    heal(bp, 10)
    view:refresh()
    eq(entry(view, "IGUI_Wounds_VBurn").detail, "12% healed")
    eq(entry(view, "IGUI_Wounds_GunshotWound").detail, "50% healed")
end)

test("stitches get their progress, packing does not", function()
    local view, bp = setup()
    stitch(bp, 20)
    view:refresh()
    eq(entry(view, "IGUI_health_Stitched").detail, "92% quality, 50% healed")
    view.packed = true
    view:refresh()
    eq(entry(view, "IGUI_Wounds_Packed").detail, "92% quality", "left alone")
end)

test("their own conditions are left alone", function()
    local view, bp = setup()
    bp.scratchTime = 10
    view.infection = true
    view:refresh()
    eq(entry(view, "IGUI_Sepsis_Wound").detail, "spreading")
end)

test("notes do not pile up across refreshes", function()
    local view, bp = setup()
    bp.fractureTime = 40
    for _ = 1, 5 do view:refresh() end
    eq(entry(view, "IGUI_health_Fracture").detail, "no splint, 0% healed")
end)

test("the refresh tracks the body, so healing with the panel open is followed", function()
    local view, bp = setup()
    view:refresh() -- nothing yet
    bp.scratchTime = 10 -- happens while the panel is open, no minute has passed
    view:refresh()
    heal(bp, 4)
    view:refresh()
    eq(entry(view, "IGUI_health_Scratched").detail, "40% healed", "start seen by the refresh")
end)

test("wounds already there show the estimate mark", function()
    local game = setupGame()
    installWoundsOverhaul()
    loadMod()
    fire("OnGameStart")
    local bp = newBodyPart(0)
    bp.cutTime = 10
    local player = newPlayer({ bp })
    local view = setmetatable({ player = player }, WoundsBodyView)
    view:refresh()
    eq(entry(view, "IGUI_health_Cut").detail, "~50% healed")
end)

test("below the required First Aid level there is no progress", function()
    local view, bp, player = setup({ required = 4, firstAid = 3 })
    bp.cutTime = 10
    view:refresh()
    eq(entry(view, "IGUI_health_Cut").detail, nil)
    player.firstAid = 4
    view:refresh()
    eq(entry(view, "IGUI_health_Cut").detail, "0% healed")
end)

test("on a patient the one treating needs the level", function()
    local game = setupGame({ client = true, required = 5 })
    installWoundsOverhaul()
    loadMod()
    fire("OnGameStart")
    local bp = newBodyPart(0)
    local patient = newPlayer({ bp }, { isLocal = false, username = "alice", firstAid = 10 })
    local view = setmetatable({ player = patient, foreign = true, doctor = newPlayer({}, { firstAid = 2 }) }, WoundsBodyView)
    bp.cutTime = 10
    view:refresh()
    eq(entry(view, "IGUI_health_Cut").detail, nil, "the patient's own level does not count")
    view.doctor = newPlayer({}, { firstAid = 5 })
    view:refresh()
    eq(entry(view, "IGUI_health_Cut").detail, "~50% healed")
    eq(patient.modData.ShowHealingProgress, nil, "a patient is tracked in memory, as on the vanilla panel")
end)

test("a failure on our side leaves their panel as it was", function()
    local view, bp = setup()
    bp.cutTime = 10
    SHP.getLines = function() error("boom") end
    local printed
    local realPrint = print
    print = function(s) printed = s end
    local result = view:refresh()
    print = realPrint
    eq(result, "refreshed")
    eq(entry(view, "IGUI_health_Cut").detail, nil, "their entry untouched")
    truthy(printed and string.find(printed, "boom"), "said once in the log")
end)

test("installing twice wraps once", function()
    local view, bp = setup()
    SHP.installWoundsOverhaul()
    SHP.installWoundsOverhaul()
    bp.cutTime = 20
    view:refresh()
    eq(entry(view, "IGUI_health_Cut").detail, "0% healed")
end)

finish("SHP Wounds Overhaul")
