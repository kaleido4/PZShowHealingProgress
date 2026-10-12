dofile(ROOT .. "/tests/harness.lua")

local FONT_HEIGHT = 10

-- Vanilla bits the client file touches. The vanilla list item draws its body
-- part name and returns y + one line + the 5 px gap, like ISHealthBodyPartListBox.
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
    getTextManager = function() return { getFontHeight = function() return FONT_HEIGHT end } end
    getText = function(key, a, b)
        local templates = { IGUI_SHP_Progress = "%1: %2 healed" }
        local s = templates[key] or key
        -- Function replacements, so a "%" in the value is taken literally.
        if a ~= nil then s = string.gsub(s, "%%1", function() return tostring(a) end) end
        if b ~= nil then s = string.gsub(s, "%%2", function() return tostring(b) end) end
        return s
    end
    getNumActivePlayers = function() return #game.players end
    getSpecificPlayer = function(i) return game.players[i + 1] end
    Perks = { Doctor = "Doctor" }
    SandboxVars = { PZShowHealingProgress = { RequiredFirstAidLevel = opts.required, TextColor = opts.color } }

    ISHealthPanel = {}
    function ISHealthPanel:update() self.vanillaUpdates = (self.vanillaUpdates or 0) + 1 end
    ISHealthBodyPartListBox = {}
    function ISHealthBodyPartListBox:doDrawItem(y, item, alt)
        self.texts[#self.texts + 1] = { text = "vanilla", y = y }
        return y + FONT_HEIGHT + 5
    end

    dofile(MOD .. "client/ShowHealingProgress/SHP_Core.lua")
    dofile(MOD .. "client/ShowHealingProgress/SHP_Client.lua")
    return game
end

local function fire(name, a, b)
    local ev = rawget(Events, name)
    if not ev then return end
    for i = 1, #ev.handlers do ev.handlers[i](a, b) end
end

local function newPlayer(parts, opts)
    opts = opts or {}
    local p = { modData = {}, parts = parts, isLocal = opts.isLocal ~= false, dead = false, username = opts.username or "bob",
                firstAid = opts.firstAid or 0 }
    function p:getModData() return self.modData end
    function p:getPerkLevel(perk) return perk == Perks.Doctor and self.firstAid or 0 end
    function p:isLocalPlayer() return self.isLocal end
    function p:isDead() return self.dead end
    function p:getUsername() return self.username end
    function p:getBodyDamage()
        local s = self
        return { getBodyParts = function() return javaList(s.parts) end }
    end
    function p:getBodyDamageRemote()
        local s = self
        return { getBodyParts = function() return javaList(s.parts) end }
    end
    return p
end

-- doctor: the one treating, when it is not the patient (ISHealthPanel.otherPlayer).
local function newPanel(patient, doctor)
    local panel = setmetatable({ visible = true }, { __index = ISHealthPanel })
    function panel:isReallyVisible() return self.visible end
    function panel:getPatient() return patient end
    function panel:getDoctor() return doctor or patient end
    local list = setmetatable({ parent = panel, texts = {} }, { __index = ISHealthBodyPartListBox })
    function list:drawText(text, x, y, r, g, b, a, font)
        self.texts[#self.texts + 1] = { text = text, x = x, y = y, r = r, g = g, b = b }
    end
    panel.listbox = list
    return panel, list
end

local function draw(list, bp, y)
    list.texts = {}
    return list:doDrawItem(y or 100, { item = { bodyPart = bp } }, false)
end

print("SHP client")

test("adds a line under the body part and makes the item taller", function()
    local bp = newBodyPart()
    local game = setupGame()
    local player = newPlayer({ bp })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.cutTime = 20
    fire("EveryOneMinute")
    heal(bp, 5)

    local panel, list = newPanel(player)
    local bottom = draw(list, bp, 100)
    eq(#list.texts, 2)
    eq(list.texts[2].text, "- IGUI_health_Cut: 25% healed")
    eq(list.texts[2].x, 15)
    near(list.texts[2].r, 0x8C / 255, "light blue r")
    near(list.texts[2].g, 0xCC / 255, "light blue g")
    near(list.texts[2].b, 1.0, "light blue b")
    eq(list.texts[2].y, 110, "right below the vanilla lines, before the gap")
    eq(bottom, 100 + FONT_HEIGHT * 2 + 5, "vanilla gap kept at the bottom")
end)

test("draws nothing extra and keeps the vanilla height without wounds", function()
    local bp = newBodyPart()
    local game = setupGame()
    local player = newPlayer({ bp })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    local panel, list = newPanel(player)
    eq(draw(list, bp, 100), 115)
    eq(#list.texts, 1)
end)

test("wounds that heal while the panel is closed keep their start", function()
    local bp = newBodyPart()
    local game = setupGame()
    local player = newPlayer({ bp })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.scratchTime = 10
    fire("EveryOneMinute")
    heal(bp, 5)
    fire("EveryOneMinute")

    local panel, list = newPanel(player)
    panel:update()
    eq(panel.vanillaUpdates, 1, "vanilla update still runs")
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Scratched: 50% healed")
end)

test("progress is saved in the player's mod data", function()
    local bp = newBodyPart()
    local game = setupGame()
    local player = newPlayer({ bp })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.burnTime = 80
    fire("EveryOneMinute")
    local saved = player.modData.ShowHealingProgress
    truthy(saved, "mod data")
    eq(saved.parts[0].burn.peak, 80)

    -- "Reload": the same mod data, a fresh Lua state.
    setupGame()
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    heal(bp, 40)
    local panel, list = newPanel(player)
    panel:update()
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Burned: 50% healed")
end)

test("estimated progress is marked with ~ until it is healed", function()
    local bp = newBodyPart()
    bp.cutTime = 10
    bp.isBandaged = true
    local game = setupGame()
    local player = newPlayer({ bp })
    game.players = { player }
    fire("OnCreatePlayer", 0, player) -- wound already there when the mod starts
    local panel, list = newPanel(player)
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Cut: ~50% healed")
    heal(bp, 10)
    panel:update()
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Cut: 100% healed")
end)

test("the line goes away when the bandage is removed after healing", function()
    local bp = newBodyPart()
    local game = setupGame()
    local player = newPlayer({ bp })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.scratchTime = 8
    bp.isBandaged = true
    local panel, list = newPanel(player)
    panel:update()
    heal(bp, 8)
    panel:update()
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Scratched: 100% healed")
    bp.isBandaged = false
    panel:update()
    draw(list, bp)
    eq(#list.texts, 1)
end)

test("hint is appended in brackets", function()
    local bp = newBodyPart()
    local game = setupGame()
    local player = newPlayer({ bp })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.deepWoundTime = 15
    local panel, list = newPanel(player)
    panel:update()
    heal(bp, 20)
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_DeepWound: 80% healed (IGUI_SHP_NeedsBandage)")
end)

test("does not scan while the other player is too far away", function()
    local bp = newBodyPart()
    bp.cutTime = 10
    local game = setupGame({ client = true })
    local other = newPlayer({ bp }, { isLocal = false, username = "alice" })
    local panel, list = newPanel(other)
    panel:update()
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Cut: ~50% healed")
    -- Too far: the panel wipes its copy of their body.
    panel.blockingMessage = "too far"
    bp.cutTime = 0
    panel:update()
    panel.blockingMessage = nil
    bp.cutTime = 10
    panel:update()
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Cut: ~50% healed", "record kept")
end)

test("another player's body is tracked in memory, not in their mod data", function()
    local bp = newBodyPart()
    local game = setupGame({ client = true })
    local other = newPlayer({ bp }, { isLocal = false, username = "alice" })
    local panel, list = newPanel(other)
    panel:update()
    bp.fractureTime = 40
    panel:update()
    heal(bp, 10)
    draw(list, bp)
    -- First seen on their body: the start is guessed as the usual largest (80).
    eq(list.texts[2].text, "- IGUI_health_Fracture: ~62% healed")
    eq(other.modData.ShowHealingProgress, nil)
end)

test("does not scan while the panel is hidden", function()
    local bp = newBodyPart()
    local game = setupGame({ client = true })
    local other = newPlayer({ bp }, { isLocal = false, username = "alice" })
    local panel, list = newPanel(other)
    panel.visible = false
    bp.cutTime = 10
    panel:update()
    draw(list, bp)
    eq(#list.texts, 1)
end)

test("dead players are skipped by the minute scan", function()
    local bp = newBodyPart()
    local game = setupGame()
    local player = newPlayer({ bp })
    player.dead = true
    game.players = { player }
    fire("EveryOneMinute")
    eq(player.modData.ShowHealingProgress, nil)
end)

test("lines are hidden below the required First Aid level", function()
    local bp = newBodyPart()
    local game = setupGame({ required = 3 })
    local player = newPlayer({ bp }, { firstAid = 2 })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.cutTime = 20
    local panel, list = newPanel(player)
    panel:update()
    eq(draw(list, bp, 100), 115, "vanilla height")
    eq(#list.texts, 1, "only the vanilla line")
end)

test("lines show from the required level on", function()
    local bp = newBodyPart()
    local game = setupGame({ required = 3 })
    local player = newPlayer({ bp }, { firstAid = 3 })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.cutTime = 20
    local panel, list = newPanel(player)
    panel:update()
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Cut: 0% healed")
end)

test("tracking carries on while hidden, so a level up shows the real number", function()
    local bp = newBodyPart()
    local game = setupGame({ required = 3 })
    local player = newPlayer({ bp }, { firstAid = 1 })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.scratchTime = 10
    fire("EveryOneMinute")
    heal(bp, 6)
    local panel, list = newPanel(player)
    panel:update()
    draw(list, bp)
    eq(#list.texts, 1, "hidden at level 1")
    player.firstAid = 3 -- leveled up, same panel still open
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Scratched: 60% healed")
end)

test("when treating another player, the one treating needs the level", function()
    local bp = newBodyPart()
    bp.cutTime = 10
    local game = setupGame({ client = true, required = 5 })
    local patient = newPlayer({ bp }, { isLocal = false, username = "alice", firstAid = 10 })
    local novice = newPlayer({}, { firstAid = 2 })
    local panel, list = newPanel(patient, novice)
    panel:update()
    draw(list, bp)
    eq(#list.texts, 1, "the patient's own level does not count")
    local medic = newPlayer({}, { firstAid = 5 })
    panel, list = newPanel(patient, medic)
    panel:update()
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Cut: ~50% healed")
end)

test("level 0 needs no First Aid at all", function()
    local bp = newBodyPart()
    local game = setupGame({ required = 0 })
    local player = newPlayer({ bp }, { firstAid = 0 })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.burnTime = 50
    local panel, list = newPanel(player)
    panel:update()
    draw(list, bp)
    eq(list.texts[2].text, "- IGUI_health_Burned: 0% healed")
end)

test("lines are drawn in the sandbox text color", function()
    local bp = newBodyPart()
    local game = setupGame({ color = "FFE659" }) -- yellow
    local player = newPlayer({ bp })
    game.players = { player }
    fire("OnCreatePlayer", 0, player)
    bp.cutTime = 20
    local panel, list = newPanel(player)
    panel:update()
    draw(list, bp)
    near(list.texts[2].r, 1, "r")
    near(list.texts[2].g, 0xE6 / 255, "g")
    near(list.texts[2].b, 0x59 / 255, "b")
end)

finish("SHP client")
