--[[
    Show Healing Progress - Wounds Overhaul support.

    Wounds Overhaul (Workshop 3775026731) takes the vanilla Health tab out of the
    character window and puts its own panel in its place, so the lines this mod
    draws in vanilla's body part list are never on screen. Its panel lists each
    limb's findings as entries ({ label = { key, fallback }, detail, ... }) in
    WoundsBodyView.woundInfo, rebuilt by WoundsBodyView:refresh() every frame,
    and draws an entry's `detail` as a small note beside its name ("splinted").

    So after each refresh, the healing progress goes into the note of the
    matching wound: "Fracture   splinted, 45% healed". Notes are not part of how
    it decides a limb has been examined (only the labels are), so a changing
    number never makes a limb look unexamined, and a wound that is hidden until
    examined keeps its progress hidden too.

    Without Wounds Overhaul none of this runs, and the vanilla Health tab works
    exactly as before (SHP_Client.lua). Everything is guarded: if a Wounds
    Overhaul update changes its panel, the progress just goes missing from it.

    Packing (Wounds Overhaul's treatment for a bullet track) is left without a
    number on purpose: it borrows the stitch clock and holds it near zero until
    its own countdown seals the wound, so a stitch percentage there would be
    wrong.
--]]

require "ShowHealingProgress/SHP_Core"
require "ShowHealingProgress/SHP_Client"

-- Wounds Overhaul's entry label -> our wound line label.
SHP.WO_LABELS = {
    IGUI_health_Scratched    = "IGUI_health_Scratched",
    IGUI_health_Cut          = "IGUI_health_Cut",
    IGUI_health_DeepWound    = "IGUI_health_DeepWound",
    IGUI_Wounds_GunshotWound = "IGUI_health_DeepWound", -- a deep wound made by a bullet
    IGUI_health_Bitten       = "IGUI_health_Bitten",
    IGUI_health_Fracture     = "IGUI_health_Fracture",
    IGUI_Wounds_VBurn        = "IGUI_health_Burned",
    IGUI_health_Stitched     = "IGUI_health_Stitched",
}

-- Adds the progress to the notes of one refreshed Wounds Overhaul body view.
function SHP.addToWoundsOverhaul(view)
    local patient = view.player
    if not patient or type(view.woundInfo) ~= "table" then return end
    -- On a patient, the one treating needs the First Aid level.
    local viewer = view.foreign and view.doctor or patient
    if not SHP.characterCanSee(viewer) then return end

    -- Their body source: the patient's synced copy when it is somebody else.
    local bd = Wounds.body.damage(patient)
    if not bd then return end
    local parts = bd:getBodyParts()

    -- Vanilla's panel is not on screen, so its update no longer tracks this
    -- body every frame; this refresh does instead.
    local store = SHP.storeFor(patient)
    SHP.update(store, parts, patient:isLocalPlayer())

    for i = 0, parts:size() - 1 do
        local entries = view.woundInfo[tostring(i)]
        if entries then
            local byLabel = {}
            for _, line in ipairs(SHP.getLines(store, parts:get(i))) do
                byLabel[line.label] = line
            end
            for _, e in ipairs(entries) do
                local ours = e.vanilla and type(e.label) == "table" and SHP.WO_LABELS[e.label[1]]
                local line = ours and byLabel[ours]
                if line then
                    local healed = getText("IGUI_SHP_Healed", SHP.percentText(line))
                    e.detail = e.detail and (e.detail .. ", " .. healed) or healed
                end
            end
        end
    end
end

local faultSaid = false

function SHP.installWoundsOverhaul()
    if type(WoundsBodyView) ~= "table" or type(WoundsBodyView.refresh) ~= "function" then return false end
    if type(Wounds) ~= "table" or type(Wounds.body) ~= "table" or type(Wounds.body.damage) ~= "function" then return false end
    if WoundsBodyView.SHP_wrapped then return true end
    WoundsBodyView.SHP_wrapped = true

    local original = WoundsBodyView.refresh
    function WoundsBodyView:refresh(...)
        local result = original(self, ...)
        local ok, err = pcall(SHP.addToWoundsOverhaul, self)
        if not ok and not faultSaid then
            faultSaid = true
            print("[ShowHealingProgress] Wounds Overhaul panel: healing progress not shown: " .. tostring(err))
        end
        return result
    end
    return true
end

-- At game start every mod's Lua is loaded, whatever the load order. Instances
-- made earlier pick the wrapped method up too: they look it up on the class.
SHP.installWoundsOverhaul()
Events.OnGameStart.Add(SHP.installWoundsOverhaul)
