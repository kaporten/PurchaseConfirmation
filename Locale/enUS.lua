-- Default english localization
local debug = false
local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("PurchaseConfirmation", "enUS", true, not debug)

if not L then
	return
end

	--[[ CONFIRMATION DIALOG ]]
	
-- Main window labels
L["Dialog_WindowTitle"] = "Confirm Purchase"
L["Dialog_ButtonDetails"] = "Details"

-- Detail window foldout labels
L["Dialog_DetailsLabel_Fixed"] = "Fixed amount"
L["Dialog_DetailsLabel_Average"] = "Average spending"
L["Dialog_DetailsLabel_EmptyCoffers"] = "Empty coffers"

-- Detail window foldout tooltips
L["Dialog_DetailsTooltip_Breached"] = "Threshold is breached"
L["Dialog_DetailsTooltip_NotBreached"] = "Threshold is not breached"
L["Dialog_DetailsTooltip_Disabled"] = "Threshold is disabled"


	--[[ SETTINGS WINDOW ]]

-- Main window labels
L["Settings_WindowTitle"] = "PurchaseConfirmation Settings"
L["Settings_Balance"] = "Current balance"

-- Individual threshold labels and descriptions
L["Settings_Threshold_Fixed_Enable"] = "Enable \"fixed upper\" threshold:"
L["Settings_Threshold_Fixed_Description"] = "Always request confirmation for purchases above this amount."

L["Settings_Threshold_Puny_Enable"] = "Enable \"puny amount\" threshold:"
L["Settings_Threshold_Puny_Description"] = "Never request confirmation for purchases below this amount, and do not use the purchase in \"average spending\" threshold calculations."

L["Settings_Threshold_Average_Enable"] = "Enable \"average spending\" threshold [1-100%]:"
L["Settings_Threshold_Average_Description"] = "Request confirmation if purchase price is more than the specified percentage above the average of your recent purchase history."

L["Settings_Threshold_EmptyCoffers_Enable"] = "Enable \"empty coffers\" threshold [1-100%]:"
L["Settings_Threshold_EmptyCoffers_Description"] = "Request confirmation if purchase cost more than the specified percentage of your current balance."


	--[[ MODULES ]]
	
L["Module_Enable"] = "Enable Module"
	
L["Module_VendorPurchase_Title"] = "Vendor: Purchase"
L["Module_VendorPurchase_Description"] = "This module intercepts item purchases in the main Vendor-addon. This covers all the regular vendors, such as General Goods vendors, scattered throughout Nexus."

L["Module_VendorRepair_Title"] = "Vendor: Repair"
L["Module_VendorRepair_Description"] = "This module intercepts single- and all-item repairs performed in the main Vendor-addon. It does not request confirmation for auto-repairs initiated by addon 'JunkIt'."