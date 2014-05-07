-- Default english localization
local debug = true
local L = Apollo.GetPackage("GeminiLocale-1.0").tPackage:NewLocale("PurchaseConfirmation", "enUS", true, not debug)

if not L then
	return
end

	--[[ CONFIRMATION DIALOG ]]

-- Main window labels
L["Dialog_WindowTitle"] = "Confirm Purchase"
L["Dialog_ButtonConfirm"] = "Purchase"
L["Dialog_ButtonCancel"] = "Cancel"
L["Dialog_ButtonDetails"] = "Details"

-- Detail window foldout labels
L["Dialog_DetailsLabel_Fixed"] = "Fixed amount"
L["Dialog_DetailsLabel_Average"] = "Average spending"
L["Dialog_DetailsLabel_EmptyCoffers"] = "Empty coffers"

-- Detail window foldout tooltips
L["Dialog_DetailsTooltip_Breached"] = "Threshold is breached"
L["Dialog_DetailsTooltip_NotBreached"] = "Threshold is not breached"


	--[[ SETTINGS WINDOW ]]

-- Main window labels
L["Settings_WindowTitle"] = "PurchaseConfirmation Settings"
L["Settings_ButtonAccept"] = "Accept"
L["Settings_ButtonCancel"] = "Cancel"
L["Settings_Balance"] = "Current balance"

-- Shortish currency descriptions, that will fit the tab-button layout
L["Settings_TabCurrency_Credits"] = "Credits"
L["Settings_TabCurrency_Renown"] = "Renown"
L["Settings_TabCurrency_Prestige"] = "Prestige"
L["Settings_TabCurrency_CraftingVouchers"] = "Crafting"
L["Settings_TabCurrency_ElderGems"] = "Elder Gems"

-- Individual threshold labels and descriptions
L["Settings_Threshold_Fixed_Enable"] = "Enable \"fixed upper\" threshold:"
L["Settings_Threshold_Fixed_Description"] = "Always request confirmation for purchases above this amount."

L["Settings_Threshold_Puny_Enable"] = "Enable \"puny amount\" threshold:"
L["Settings_Threshold_Puny_Description"] = "Never request confirmation for purchases below this amount, and do not use the purchase in \"average spending\" threshold calculations."

L["Settings_Threshold_Average_Enable"] = "Enable \"average spending\" threshold [1-100%]:"
L["Settings_Threshold_Average_Description"] = "Request confirmation if purchase price is more than the specified percentage above the average of your recent purchase history."

L["Settings_Threshold_EmptyCoffers_Enable"] = "Enable \"empty coffers\" threshold [1-100%]:"
L["Settings_Threshold_EmptyCoffers_Description"] = "Request confirmation if purchase cost more than the specified percentage of your current balance."