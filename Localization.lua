--[[ 
	Localization wrapper. Rather than modifying the window fields with hard-to-read
	values like "___TOKEN___", I'll "manually" apply the localized text value 
	to every single field on the forms.
	
	A bit more work to maintain, but way easier on the eys when Hudson'ing stuff
]]


--[[
	Fields that use "standard texts" do not require localization, such as:	
		"Cancel", "Purchase", "Accept" button texts 
		Currency names on the settings tab	
]]

local Localization = {}
Apollo.RegisterPackage(Localization, "PurchaseConfirmation:Localization", 1, {"Gemini:Locale-1.0"})

function Localization.LocalizeDialog(wnd)	
	local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

	wnd:FindChild("DialogArea"):FindChild("Title"):SetText(L["Dialog_WindowTitle"])
	wnd:FindChild("DialogArea"):FindChild("DetailsButton"):SetText("   " .. L["Dialog_ButtonDetails"]) -- 3 spaces as leftpadding

	wnd:FindChild("FoldoutArea"):FindChild("ThresholdFixed"):FindChild("Label"):SetText(L["Dialog_DetailsLabel_Fixed"])
	wnd:FindChild("FoldoutArea"):FindChild("ThresholdAverage"):FindChild("Label"):SetText(L["Dialog_DetailsLabel_Average"])
	wnd:FindChild("FoldoutArea"):FindChild("ThresholdEmptyCoffers"):FindChild("Label"):SetText(L["Dialog_DetailsLabel_EmptyCoffers"])
end






