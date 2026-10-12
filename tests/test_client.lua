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
    local p = { modData = {}, parts = parts, isLocal = opts.isLocal ~= false, dead = false, username = opts.username or "bob" }
    function p:getModData() return self.modData end
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

local function newPanel(patient)
    local panel = setmetatable({ visible = true }, { __index = ISHealthPanel })
    function panel:isReallyVisible() return self.visible end
    function panel:getPatient() return patient end
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
    near(list.texts[2].r, 0.55, "light blue r")
    near(list.texts[2].g, 0.8, "light blue g")
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

finish("SHP client")
