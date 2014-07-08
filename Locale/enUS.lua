-- Default english localization
local debug = false
local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("PurchaseConfirmation", "enUS", true, not debug)

if not L then
	return
end

	--[[ CONFIRMATION DIALOG ]]
	
-- Main window labels
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

L["Settings_Modules_Button"] = "Modules"


	--[[ MODULES ]]
	
L["Modules_WindowTitle"] = "Modules"

L["Module_Enable"] = "Enable"
L["Module_Failure_Addon_Missing"] = "Required addon %q not found."
	
L["Module_VendorPurchase_Title"] = "Vendor: Purchase"
L["Module_VendorPurchase_Description"] = "This module intercepts item purchases in the main Vendor-addon. This covers all the regular vendors, such as General Goods vendors, scattered throughout Nexus."

L["Module_VendorRepair_Title"] = "Vendor: Repair"
L["Module_VendorRepair_Description"] = "This module intercepts single- and all-item repairs performed in the main Vendor-addon. It does not request confirmation for auto-repairs initiated by addon 'JunkIt'."

L["Module_HousingBuyToCrate_Title"] = "Housing: Buy To Crate"
L["Module_HousingBuyToCrate_Description"] = "This module intercepts buying housing decor items (to your crate). It does not affect Housing item repair/placement cost, only buying to your crate."

L["Module_SpaceStashBankSlot_Title"] = "SpaceStash: Buy Bank Slot"
L["Module_SpaceStashBankSlot_Description"] = "If you're using the SpaceStash addon, this will intercept bank-slot purchases."

L["Module_LilVendorPurchase_Title"] = "LilVendor: Purchase"
L["Module_LilVendorPurchase_Description"] = "If you're using the LilVendor addon, this will intercept purchases. Same as for the stock Vendor addon, except for the LilVendor replacement addon."

L["Module_ViragsMultibuyerPurchase_Title"] = "ViragsMultibyer: Purchase"
L["Module_ViragsMultibuyerPurchase_Description"] = "If you're using the ViragsMultibyer addon, this will intercept purchases before showing the ViragsMultibuyer-internal confirmation dialog."

L["Module_CostumesDye_Title"] = "Costumes: Dye"
L["Module_CostumesDye_Description"] = "Looking good is never cheap, especially not in WildStar. This module lets you think twice before dropping 2 Platinum on that sweet blood-red dye."

