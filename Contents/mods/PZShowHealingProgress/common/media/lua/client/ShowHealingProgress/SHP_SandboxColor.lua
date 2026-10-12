--[[
    Show Healing Progress - color button for the TextColor sandbox option.

    Mod sandbox options have no color type, so TextColor is a string holding a
    hex color ("8CCCFF"). Wherever the game shows sandbox options, its text box
    is replaced with a color button like the ones in Options > Display
    (MainOptions:addColorButton): a square in the current color that opens the
    game's color grid (ISColorPicker) under it.

    The screens read and write each option through its control's getText and
    setText (settingsToUI / settingsFromUI), so that is all the button has to
    keep. Where the button goes:
      - new game sandbox page (SandboxOptionsScreen): it makes each control in
        createControlForSetting, so ours is made there instead of a text box;
      - in-game sandbox options for admins and debug (ISServerSandboxOptionsUI)
        and host server settings (ServerSettingsScreen): they make controls
        inline, so the text box is swapped for the button after a page is built,
        in the same place, in every table that held it.
--]]

require "ISUI/ISColorPicker"
require "OptionScreens/SandboxOptions"
require "OptionScreens/ServerSettingsScreen"
require "ISUI/AdminPanel/ISServerSandboxOptionsUI"
require "ShowHealingProgress/SHP_Core"

local OPTION = "PZShowHealingProgress.TextColor"

-- ---------------------------------------------------------------------------
-- The control: a transparent strip as big as the text box was, with the color
-- button at its start, where the other controls' boxes start.
-- ---------------------------------------------------------------------------

SHPColorControl = ISPanel:derive("SHPColorControl")

function SHPColorControl:createChildren()
    local h = self.height
    self.button = ISButton:new(0, 0, h * 2, h, "", self, SHPColorControl.onButton)
    self.button:initialise()
    self.button:instantiate()
    self.button.tooltip = self.tooltip
    self:addChild(self.button)
    self:updateButton()
end

function SHPColorControl:color()
    local r, g, b = SHP.parseColor(self.value)
    if r then return r, g, b end
    return SHP.parseColor(SHP.DEFAULT_COLOR_HEX)
end

function SHPColorControl:updateButton()
    local r, g, b = self:color()
    self.button.backgroundColor = { r = r, g = g, b = b, a = 1 }
    self.button.backgroundColorMouseOver = { r = r, g = g, b = b, a = 1 }
end

local function topParent(element)
    while element.parent do element = element.parent end
    return element
end

-- Like MainOptions:onObjHighlightColor: the grid goes on the screen itself,
-- under the button (or above it when there is no room), and takes the mouse
-- until a color is picked or it is clicked away.
function SHPColorControl:onButton()
    local root = topParent(self)
    if not self.picker then
        self.picker = ISColorPicker:new(0, 0)
        self.picker:initialise()
        self.picker.pickedTarget = self
        self.picker.pickedFunc = SHPColorControl.onPicked
    end
    local picker, button = self.picker, self.button
    local x = button:getAbsoluteX() - root:getAbsoluteX()
    local y = button:getAbsoluteY() - root:getAbsoluteY() + button:getHeight() + 1
    if y + picker:getHeight() > root:getHeight() then
        y = y - button:getHeight() - picker:getHeight() - 2
    end
    picker:setX(x)
    picker:setY(y)
    local r, g, b = self:color()
    picker:setInitialColor(ColorInfo.new(r, g, b, 1))
    root:addChild(picker)
    picker:setCapture(true)
    picker:setVisible(true)
    picker:bringToTop()
end

-- While a color is being picked and when the grid closes.
function SHPColorControl:onPicked(color)
    self:setText(SHP.toHex(color.r, color.g, color.b))
end

-- What the screens read and write.
function SHPColorControl:getText()
    return self.value
end

function SHPColorControl:setText(text)
    self.value = text
    if self.button then self:updateButton() end
end

-- For controller navigation, where a screen lists the control.
function SHPColorControl:setJoypadFocused(focused)
    self.joypadFocused = focused
    if self.button then self.button.joypadFocused = focused end
end

function SHPColorControl:onJoypadDown(button, joypadData)
    if button == Joypad.AButton then
        self:onButton()
        if joypadData then joypadData.focus = self.picker end
    end
end

function SHPColorControl:forceClick()
    self:onButton()
end

function SHPColorControl:new(x, y, width, height, text, tooltip)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.value = text or SHP.DEFAULT_COLOR_HEX
    o.tooltip = tooltip
    return o
end

-- ---------------------------------------------------------------------------
-- Putting it on the screens
-- ---------------------------------------------------------------------------

local function newControl(x, y, width, height, text, tooltip)
    local control = SHPColorControl:new(x, y, width, height, text, tooltip)
    control:initialise()
    control:instantiate()
    return control
end

local function replaceIn(t, old, new)
    if type(t) ~= "table" then return end
    for k, v in pairs(t) do
        if v == old then t[k] = new end
    end
end

-- Puts the button where a page put the TextColor text box, and makes every
-- table that held the text box (the screen's controls, the page's, the
-- controller rows) hold the button.
function SHP.swapColorControl(old, owners)
    if not old or old.Type ~= "ISTextEntryBox" or not old.parent then return nil end
    local parent = old.parent
    local new = newControl(old:getX(), old:getY(), old:getWidth(), old:getHeight(), old:getText(), old.tooltip)
    parent:removeChild(old)
    parent:addChild(new)
    for _, t in pairs(owners) do replaceIn(t, old, new) end
    replaceIn(parent.controls, old, new)
    replaceIn(parent.joypadButtons, old, new)
    for _, row in ipairs(parent.joypadButtonsY or {}) do replaceIn(row, old, new) end
    return new
end

-- New game sandbox page.
if SandboxOptionsScreen and SandboxOptionsScreen.createControlForSetting then
    local original = SandboxOptionsScreen.createControlForSetting
    function SandboxOptionsScreen:createControlForSetting(setting, tooltip)
        local control = original(self, setting, tooltip)
        if setting.name ~= OPTION or not control then return control end
        return newControl(0, 0, control:getWidth(), control:getHeight(), setting.text, tooltip)
    end
end

-- In-game sandbox options (admin panel, debug).
if ISServerSandboxOptionsUI and ISServerSandboxOptionsUI.createPanel then
    local original = ISServerSandboxOptionsUI.createPanel
    function ISServerSandboxOptionsUI:createPanel(page)
        local panel = original(self, page)
        if self.controls and self.controls[OPTION] then
            SHP.swapColorControl(self.controls[OPTION], { self.controls, panel and panel.controls })
        end
        return panel
    end
end

-- Host server settings: the page editor (a local class there) builds every
-- page in create(), and again whenever its createPanel runs.
local function swapInPageEdit(pageEdit)
    for _, controls in pairs(pageEdit.controls or {}) do
        if type(controls) == "table" and controls[OPTION] then
            SHP.swapColorControl(controls[OPTION], { controls })
        end
    end
end

if ServerSettingsScreen and ServerSettingsScreen.create then
    local original = ServerSettingsScreen.create
    function ServerSettingsScreen:create(...)
        local result = original(self, ...)
        local pageEdit = self.pageEdit
        if pageEdit then
            swapInPageEdit(pageEdit)
            local class = getmetatable(pageEdit)
            class = class and class.__index
            if type(class) == "table" and class.createPanel and not class.SHP_colorWrapped then
                class.SHP_colorWrapped = true
                local originalPanel = class.createPanel
                class.createPanel = function(pe, ...)
                    local panel = originalPanel(pe, ...)
                    swapInPageEdit(pe)
                    return panel
                end
            end
        end
        return result
    end
end
