dofile(ROOT .. "/tests/harness.lua")

local OPTION = "PZShowHealingProgress.TextColor"

-- Just enough of the vanilla UI classes for SHP_SandboxColor.lua. instantiate()
-- builds the children, as ISUIElement:instantiate does; classes are made the
-- way derive() makes them (an instance's metatable is its class).
local function setupUI()
    require = function() end
    Joypad = { AButton = "A", BButton = "B" }

    ISUIElement = { Type = "ISUIElement" }
    ISUIElement.__index = ISUIElement
    function ISUIElement:derive(name)
        local cls = setmetatable({ Type = name }, { __index = self })
        cls.__index = cls
        return cls
    end
    function ISUIElement.new(class, x, y, w, h)
        return setmetatable({ x = x, y = y, width = w, height = h, children = {} }, class)
    end
    function ISUIElement:initialise() end
    function ISUIElement:instantiate()
        self.javaObject = true
        if self.createChildren then self:createChildren() end
    end
    function ISUIElement:addChild(c) c.parent = self; self.children[#self.children + 1] = c end
    function ISUIElement:removeChild(c)
        for i, v in ipairs(self.children) do
            if v == c then table.remove(self.children, i); break end
        end
        c.parent = nil
    end
    function ISUIElement:getX() return self.x end
    function ISUIElement:getY() return self.y end
    function ISUIElement:getWidth() return self.width end
    function ISUIElement:getHeight() return self.height end
    function ISUIElement:setX(x) self.x = x end
    function ISUIElement:setY(y) self.y = y end
    function ISUIElement:getAbsoluteX() return (self.parent and self.parent:getAbsoluteX() or 0) + self.x end
    function ISUIElement:getAbsoluteY() return (self.parent and self.parent:getAbsoluteY() or 0) + self.y end
    function ISUIElement:setCapture(b) self.capture = b end
    function ISUIElement:setVisible(b) self.visible = b end
    function ISUIElement:bringToTop() self.onTop = true end

    ISPanel = ISUIElement:derive("ISPanel")
    function ISPanel:new(x, y, w, h) return ISUIElement.new(self, x, y, w, h) end

    ISButton = ISUIElement:derive("ISButton")
    function ISButton:new(x, y, w, h, title, target, onclick)
        local o = ISUIElement.new(self, x, y, w, h)
        o.target, o.onclick = target, onclick
        return o
    end

    ISTextEntryBox = ISUIElement:derive("ISTextEntryBox")
    function ISTextEntryBox:new(text, x, y, w, h)
        local o = ISUIElement.new(self, x, y, w, h)
        o.text = text
        return o
    end
    function ISTextEntryBox:getText() return self.text end
    function ISTextEntryBox:setText(t) self.text = t end

    ColorInfo = { new = function(r, g, b, a) return { r = r, g = g, b = b, a = a } end }

    ISColorPicker = ISUIElement:derive("ISColorPicker")
    function ISColorPicker:new(x, y) return ISUIElement.new(self, x, y, 300, 120) end
    function ISColorPicker:setInitialColor(info) self.initial = info end
    -- What the grid does when a color is clicked: report it, then close.
    function ISColorPicker:pick(color)
        self.parent:removeChild(self)
        self.pickedFunc(self.pickedTarget, color, true)
    end

    -- New game page: makes a text box for string options.
    SandboxOptionsScreen = ISUIElement:derive("SandboxOptionsScreen")
    function SandboxOptionsScreen:createControlForSetting(setting, tooltip)
        local c = ISTextEntryBox:new(setting.text, 0, 0, 300, 24)
        c.tooltip = tooltip
        c:initialise()
        c:instantiate()
        return c
    end

    -- In-game admin page: builds the controls inline and keeps them in tables.
    ISServerSandboxOptionsUI = ISUIElement:derive("ISServerSandboxOptionsUI")
    function ISServerSandboxOptionsUI:createPanel(page)
        local panel = ISPanel:new(10, 40, 600, 400)
        panel.controls, panel.joypadButtonsY = {}, {}
        self:addChild(panel)
        for i, setting in ipairs(page.settings) do
            local c = ISTextEntryBox:new(setting.text, 250, i * 30, 200, 20)
            c.tooltip = "tip"
            panel:addChild(c)
            self.controls[setting.name] = c
            panel.controls[setting.name] = c
            panel.joypadButtonsY[#panel.joypadButtonsY + 1] = { c }
        end
        return panel
    end

    -- Host settings: a local page class, reachable only through its object.
    local Page3 = ISUIElement:derive("Page3")
    function Page3:createPanel(category, page)
        local panel = ISPanel:new(0, 0, 600, 400)
        panel.controls = {}
        self:addChild(panel)
        self.controls[category] = self.controls[category] or {}
        for i, setting in ipairs(page.settings) do
            local c = ISTextEntryBox:new(setting.text, 250, i * 30, 200, 20)
            panel:addChild(c)
            self.controls[category][setting.name] = c
            panel.controls[setting.name] = c
        end
        return panel
    end
    ServerSettingsScreen = ISUIElement:derive("ServerSettingsScreen")
    function ServerSettingsScreen:create()
        self.pageEdit = ISUIElement.new(Page3, 0, 0, 800, 600)
        self.pageEdit.controls = {}
        self:addChild(self.pageEdit)
        self.pageEdit:createPanel("Mods", { settings = { { name = OPTION, text = "FF0000" } } })
    end

    SHPColorControl = nil
    dofile(MOD .. "client/ShowHealingProgress/SHP_Core.lua")
    dofile(MOD .. "client/ShowHealingProgress/SHP_SandboxColor.lua")
end

local function newGameControl(text, screenHeight)
    local screen = ISUIElement.new(SandboxOptionsScreen, 0, 0, 1000, screenHeight or 800)
    local c = screen:createControlForSetting({ name = OPTION, type = "string", text = text }, "tip")
    c.x, c.y = 500, 200
    screen.children = { c }
    c.parent = screen
    return c, screen
end

local function click(control)
    control.button.onclick(control.button.target, control.button)
end

print("SHP sandbox color")

test("other options keep the page's own control", function()
    setupUI()
    local screen = setmetatable({}, { __index = SandboxOptionsScreen })
    local c = screen:createControlForSetting({ name = "PZShowHealingProgress.RequiredFirstAidLevel", type = "entry", text = "0" }, "tip")
    eq(c.Type, "ISTextEntryBox")
end)

test("new game page: TextColor is a color button, no text box", function()
    setupUI()
    local c = newGameControl("8CCCFF")
    eq(c.Type, "SHPColorControl")
    eq(c:getWidth(), 300, "as wide as the text box was")
    eq(c:getHeight(), 24)
    eq(#c.children, 1, "just the button")
    eq(c.button.Type, "ISButton")
    eq(c.button.x, 0, "at the start, where other controls start")
    eq(c.button.width, 48, "a wide square, like Options")
    eq(c.button.tooltip, "tip")
    near(c.button.backgroundColor.r, 0x8C / 255)
    near(c.button.backgroundColor.b, 1)
    eq(c:getText(), "8CCCFF")
end)

test("the page's save and load go through getText and setText", function()
    setupUI()
    local c = newGameControl("8CCCFF")
    c:setText("FF0000") -- settingsToUI
    eq(c:getText(), "FF0000") -- settingsFromUI
    near(c.button.backgroundColor.r, 1)
    near(c.button.backgroundColor.g, 0)
    c:setText("junk")
    near(c.button.backgroundColor.r, 0x8C / 255, "shows the default for a bad value")
end)

test("clicking the button opens the grid under it, on the screen", function()
    setupUI()
    local c, screen = newGameControl("FF8000")
    click(c)
    local picker = c.picker
    eq(picker.parent, screen, "on the screen, not in the scrolling page")
    eq(picker.x, 500)
    eq(picker.y, 225, "just below the button")
    eq(picker.capture, true)
    eq(picker.onTop, true)
    near(picker.initial.r, 1)
    near(picker.initial.g, 0x80 / 255)
end)

test("the grid opens above the button when there is no room below", function()
    setupUI()
    local c = newGameControl("FF8000", 300)
    click(c)
    eq(c.picker.y, 200 - 120 - 1, "above the button")
end)

test("picking a color stores its hex and shows it on the button", function()
    setupUI()
    local c = newGameControl("8CCCFF")
    click(c)
    c.picker:pick({ r = 0.2, g = 0.8, b = 1 })
    eq(c:getText(), "33CCFF")
    near(c.button.backgroundColor.r, 0x33 / 255)
    eq(c.picker.parent, nil, "grid closed")
    click(c)
    eq(c.picker.parent ~= nil, true, "opens again")
end)

test("in-game sandbox options: the text box is swapped for the button in place", function()
    setupUI()
    local ui = ISUIElement.new(ISServerSandboxOptionsUI, 100, 100, 800, 600)
    ui.controls = {}
    local panel = ui:createPanel({ settings = {
        { name = "PZShowHealingProgress.RequiredFirstAidLevel", text = "2" },
        { name = OPTION, text = "00FF00" },
    } })
    local c = ui.controls[OPTION]
    eq(c.Type, "SHPColorControl")
    eq(panel.controls[OPTION], c, "page table")
    eq(panel.joypadButtonsY[2][1], c, "controller row")
    eq(c.parent, panel)
    eq(c.x, 250) eq(c.y, 60) eq(c.width, 200) eq(c.height, 20)
    eq(c:getText(), "00FF00")
    eq(c.button.tooltip, "tip")
    for _, child in ipairs(panel.children) do
        truthy(child.Type ~= "ISTextEntryBox" or child == ui.controls["PZShowHealingProgress.RequiredFirstAidLevel"], "old text box removed")
    end
    eq(ui.controls["PZShowHealingProgress.RequiredFirstAidLevel"].Type, "ISTextEntryBox", "other options untouched")
end)

test("host server settings: swapped after create, and on later rebuilds", function()
    setupUI()
    local screen = ISUIElement.new(ServerSettingsScreen, 0, 0, 1000, 800)
    screen:create()
    local c = screen.pageEdit.controls.Mods[OPTION]
    eq(c.Type, "SHPColorControl")
    eq(c:getText(), "FF0000")
    screen.pageEdit:createPanel("Mods", { settings = { { name = OPTION, text = "0000FF" } } })
    c = screen.pageEdit.controls.Mods[OPTION]
    eq(c.Type, "SHPColorControl", "rebuilt page too")
    eq(c:getText(), "0000FF")
end)

test("a controller can open the grid", function()
    setupUI()
    local c = newGameControl("8CCCFF")
    local joypadData = {}
    c:setJoypadFocused(true, joypadData)
    c:onJoypadDown(Joypad.AButton, joypadData)
    eq(joypadData.focus, c.picker)
end)

finish("SHP sandbox color")
