--[[
    Show Healing Progress - color picker for the TextColor sandbox option.

    Mod sandbox options have no color type, so TextColor is a string holding a
    hex color ("8CCCFF"). On the new game sandbox page (SandboxOptionsScreen)
    its text box is swapped for a color square that opens the game's HSB color
    picker (the one the debug item editor uses for clothing colors), next to a
    smaller box with the hex, which can still be typed in.

    The page reads and writes the value through the control's getText/setText
    (SandboxOptionsScreen:settingsToUI / settingsFromUI), so that is all the
    swap needs to keep. The host server settings and the in-game admin panel
    build their controls inline, so there the option stays a plain hex box.
--]]

require "OptionScreens/SandboxOptions"
require "ISUI/ISColorPickerHSB"
require "ShowHealingProgress/SHP_Core"

if not SandboxOptionsScreen or not SandboxOptionsScreen.createControlForSetting then return end

local OPTION = "PZShowHealingProgress.TextColor"
local GAP = 6

SHPColorControl = ISPanel:derive("SHPColorControl")

function SHPColorControl:createChildren()
    local h = self.height
    local swatchWidth = h * 2

    self.swatch = ISButton:new(0, 0, swatchWidth, h, "", self, SHPColorControl.onSwatch)
    self.swatch:initialise()
    self.swatch:instantiate()
    self.swatch.tooltip = self.tooltip
    self:addChild(self.swatch)

    self.entry = ISTextEntryBox:new(self.initialText, swatchWidth + GAP, 0, self.width - swatchWidth - GAP, h)
    self.entry.font = UIFont.Medium
    self.entry.tooltip = self.tooltip
    self.entry:initialise()
    self.entry:instantiate()
    self.entry.target = self
    self.entry.onTextChangeFunction = SHPColorControl.updateSwatch
    self:addChild(self.entry)

    self:updateSwatch()
end

function SHPColorControl:color()
    local r, g, b = SHP.parseColor(self.entry:getText())
    if r then return r, g, b end
    return SHP.parseColor(SHP.DEFAULT_COLOR_HEX)
end

function SHPColorControl:updateSwatch()
    local r, g, b = self:color()
    self.swatch.backgroundColor = { r = r, g = g, b = b, a = 1 }
    self.swatch.backgroundColorMouseOver = { r = r, g = g, b = b, a = 1 }
end

function SHPColorControl:onSwatch()
    local r, g, b = self:color()
    local info = ColorInfo.new()
    info:set(r, g, b, 1)
    if not self.picker then
        self.picker = ISColorPickerHSB:new(0, 0, info)
        self.picker:initialise()
        self.picker.keepOnScreen = true
    end
    local picker = self.picker
    picker:setX(self.swatch:getAbsoluteX())
    picker:setY(self.swatch:getAbsoluteY() + self.swatch:getHeight())
    -- Called on Accept (and by a controller, which closes the picker itself).
    picker.pickedFunc = function(_, color)
        self:setText(SHP.toHex(color.r, color.g, color.b))
        picker:removeFromUIManager()
    end
    picker:setInitialColor(info)
    picker:addToUIManager()
    picker:setAlwaysOnTop(true)
end

-- What SandboxOptionsScreen reads and writes.
function SHPColorControl:getText()
    return self.entry:getText()
end

function SHPColorControl:setText(text)
    self.entry:setText(text or "")
    self:updateSwatch()
end

function SHPColorControl:new(x, y, width, height, text, tooltip)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.initialText = text or SHP.DEFAULT_COLOR_HEX
    o.tooltip = tooltip
    return o
end

local originalCreateControl = SandboxOptionsScreen.createControlForSetting
function SandboxOptionsScreen:createControlForSetting(setting, tooltip)
    local control = originalCreateControl(self, setting, tooltip)
    if setting.name ~= OPTION or not control then return control end
    -- Same size as the text box the page made for it.
    local colorControl = SHPColorControl:new(0, 0, control:getWidth(), control:getHeight(), setting.text, tooltip)
    colorControl:initialise()
    colorControl:instantiate()
    return colorControl
end
