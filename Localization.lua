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








