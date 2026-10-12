--[[
    Show Healing Progress - health panel lines.

    Adds "- <wound>: x% healed" under each body part in the Health tab, after
    the vanilla lines. The vanilla list item is drawn first and we only append
    to it (wrapping ISHealthBodyPartListBox:doDrawItem), so other mods that
    wrap it keep working.

    Wounds are tracked (SHP_Core.lua) every game minute for local players, so
    their starting value is known even when the panel was closed, and every
    frame while a health panel is open. Another player's body is only tracked
    while we look at it, so wounds already there when we first look show an
    estimate ("~").
--]]

require "XpSystem/ISUI/ISHealthPanel"
require "ShowHealingProgress/SHP_Core"

local MOD_DATA_KEY = "ShowHealingProgress"
local FONT_HGT_SMALL = getTextManager():getFontHeight(UIFont.Small)
local LINE_X = 15        -- same indent as the vanilla wound lines
local ITEM_BOTTOM_GAP = 5 -- vanilla doDrawItem ends with y = y + 5
local TEXT_R, TEXT_G, TEXT_B = 0.55, 0.8, 1.0 -- light blue, apart from the vanilla red and green

local remoteStores = {} -- other players' bodies, by username, this session only

local function isLocal(patient)
    return patient:isLocalPlayer()
end

local function storeFor(patient)
    if isLocal(patient) then
        local modData = patient:getModData()
        modData[MOD_DATA_KEY] = modData[MOD_DATA_KEY] or {}
        return modData[MOD_DATA_KEY]
    end
    local key = patient:getUsername()
    remoteStores[key] = remoteStores[key] or {}
    return remoteStores[key]
end

-- Same source as ISHealthPanel:getDamagedParts.
local function bodyPartsOf(patient)
    if isClient() and not isLocal(patient) then
        return patient:getBodyDamageRemote():getBodyParts()
    end
    return patient:getBodyDamage():getBodyParts()
end

local function scan(patient)
    SHP.update(storeFor(patient), bodyPartsOf(patient), isLocal(patient))
end

local function scanLocalPlayers()
    for i = 0, getNumActivePlayers() - 1 do
        local player = getSpecificPlayer(i)
        if player and not player:isDead() then
            scan(player)
        end
    end
end

local function lineText(line)
    local pct = SHP.percent(line.progress) .. "%"
    if line.est and line.progress < 1 then pct = "~" .. pct end
    local text = "- " .. getText("IGUI_SHP_Progress", getText(line.label), pct)
    if line.hint then text = text .. " (" .. getText(line.hint) .. ")" end
    return text
end

local originalUpdate = ISHealthPanel.update
function ISHealthPanel:update()
    originalUpdate(self)
    -- blockingMessage: the other player is too far away and the panel wiped
    -- its copy of their body, so it shows no real wounds.
    if self:isReallyVisible() and not self.blockingMessage then
        scan(self:getPatient())
    end
end

local originalDoDrawItem = ISHealthBodyPartListBox.doDrawItem
function ISHealthBodyPartListBox:doDrawItem(y, item, alt)
    y = originalDoDrawItem(self, y, item, alt)
    local bodyPart = item.item and item.item.bodyPart
    if not bodyPart or not self.parent or not self.parent.getPatient then return y end

    local lines = SHP.getLines(storeFor(self.parent:getPatient()), bodyPart)
    if #lines == 0 then return y end

    y = y - ITEM_BOTTOM_GAP
    for _, line in ipairs(lines) do
        self:drawText(lineText(line), LINE_X, y, TEXT_R, TEXT_G, TEXT_B, 1, UIFont.Small)
        y = y + FONT_HGT_SMALL
    end
    return y + ITEM_BOTTOM_GAP
end

Events.OnCreatePlayer.Add(function(playerNum, player)
    if player then scan(player) end
end)
Events.EveryOneMinute.Add(scanLocalPlayers)
