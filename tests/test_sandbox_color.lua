dofile(ROOT .. "/tests/harness.lua")

-- Just enough of the vanilla UI classes for SHP_SandboxColor.lua. instantiate()
-- builds the children, as ISUIElement:instantiate does.
local function setupUI()
    require = function() end
    UIFont = { Medium = "Medium" }

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
    function ISUIElement:getWidth() return self.width end
    function ISUIElement:getHeight() return self.height end
    function ISUIElement:setX(x) self.x = x end
    function ISUIElement:setY(y) self.y = y end
    function ISUIElement:getAbsoluteX() return (self.parent and self.parent:getAbsoluteX() or 0) + self.x end
    function ISUIElement:getAbsoluteY() return (self.parent and self.parent:getAbsoluteY() or 0) + self.y end
    function ISUIElement:addToUIManager() self.onScreen = true end
    function ISUIElement:removeFromUIManager() self.onScreen = false end
    function ISUIElement:setAlwaysOnTop(b) self.alwaysOnTop = b end

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
    function ISTextEntryBox:onTextChange()
        if self.onTextChangeFunction then self.onTextChangeFunction(self.target, self) end
    end

    ColorInfo = { new = function()
        local c = {}
        function c:set(r, g, b, a) self.r, self.g, self.b, self.a = r, g, b, a end
        return c
    end }

    ISColorPickerHSB = ISUIElement:derive("ISColorPickerHSB")
    function ISColorPickerHSB:new(x, y, info)
        local o = ISUIElement.new(self, x, y, 400, 230)
        o.initial = info
        return o
    end
    function ISColorPickerHSB:setInitialColor(info) self.initial = info end

    -- The vanilla page makes a text box for string options.
    SandboxOptionsScreen = {}
    function SandboxOptionsScreen:createControlForSetting(setting, tooltip)
        local c = ISTextEntryBox:new(setting.text, 0, 0, 300, 24)
        c.tooltip = tooltip
        c:initialise()
        c:instantiate()
        return c
    end

    SHPColorControl = nil
    dofile(MOD .. "client/ShowHealingProgress/SHP_Core.lua")
    dofile(MOD .. "client/ShowHealingProgress/SHP_SandboxColor.lua")
end

local function colorSetting(text)
    return { name = "PZShowHealingProgress.TextColor", type = "string", text = text }
end

local function control(text)
    local screen = setmetatable({}, { __index = SandboxOptionsScreen })
    return screen:createControlForSetting(colorSetting(text), "tip")
end

print("SHP sandbox color")

test("other options keep the page's own control", function()
    setupUI()
    local screen = setmetatable({}, { __index = SandboxOptionsScreen })
    local c = screen:createControlForSetting({ name = "PZShowHealingProgress.RequiredFirstAidLevel", type = "entry", text = "0" }, "tip")
    eq(c.Type, "ISTextEntryBox")
end)

test("TextColor gets a color square and a hex box, as big as the text box was", function()
    setupUI()
    local c = control("8CCCFF")
    eq(c.Type, "SHPColorControl")
    eq(c:getWidth(), 300)
    eq(c:getHeight(), 24)
    eq(c:getText(), "8CCCFF")
    near(c.swatch.backgroundColor.r, 0x8C / 255)
    near(c.swatch.backgroundColor.b, 1)
    eq(c.swatch.tooltip, "tip")
    eq(c.entry.tooltip, "tip")
    truthy(c.entry.x >= c.swatch.width, "hex box beside the square")
    eq(c.entry.x + c.entry.width, 300, "fills the rest")
end)

test("the page's save and load go through getText and setText", function()
    setupUI()
    local c = control("8CCCFF")
    c:setText("FF0000") -- settingsToUI
    eq(c:getText(), "FF0000") -- settingsFromUI
    near(c.swatch.backgroundColor.r, 1)
    near(c.swatch.backgroundColor.g, 0)
end)

test("typing a hex color updates the square", function()
    setupUI()
    local c = control("8CCCFF")
    c.entry.text = "00FF00"
    c.entry:onTextChange()
    near(c.swatch.backgroundColor.g, 1)
    near(c.swatch.backgroundColor.r, 0)
    c.entry.text = "not a color"
    c.entry:onTextChange()
    near(c.swatch.backgroundColor.r, 0x8C / 255, "default shown")
    eq(c:getText(), "not a color", "what was typed is kept")
end)

test("clicking the square opens the picker under it with the current color", function()
    setupUI()
    local c = control("FF8000")
    c.x, c.y = 500, 200
    c.swatch.onclick(c.swatch.target, c.swatch)
    local picker = c.picker
    truthy(picker and picker.onScreen, "picker shown")
    eq(picker.alwaysOnTop, true)
    eq(picker.x, 500)
    eq(picker.y, 224, "just below the square")
    near(picker.initial.r, 1)
    near(picker.initial.g, 0x80 / 255)
end)

test("accepting a color writes its hex and closes the picker", function()
    setupUI()
    local c = control("8CCCFF")
    c.swatch.onclick(c.swatch.target, c.swatch)
    c.picker.pickedFunc(nil, { r = 1, g = 0.5, b = 0 })
    eq(c:getText(), "FF8000")
    near(c.swatch.backgroundColor.g, 0x80 / 255)
    eq(c.picker.onScreen, false)
end)

test("does nothing without the sandbox page", function()
    setupUI()
    SandboxOptionsScreen = nil
    SHPColorControl = nil
    dofile(MOD .. "client/ShowHealingProgress/SHP_SandboxColor.lua")
    eq(SHPColorControl, nil)
end)

finish("SHP sandbox color")
