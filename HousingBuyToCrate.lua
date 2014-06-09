require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the Housing addon,
	specifically for the "buy to crate".
]]

-- GeminiLocale
local locale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

-- Register module as package
local HousingBuyToCrate = {
	MODULE_ID = "PurchaseConfirmation:HousingBuyToCrate",
	strTitle = locale["Module_HousingBuyToCrate_Title"],
	strDescription = locale["Module_HousingBuyToCrate_Description"],
}
Apollo.RegisterPackage(HousingBuyToCrate, HousingBuyToCrate.MODULE_ID, 1, {"PurchaseConfirmation", "Housing"})

-- "glocals" set during Init
local addon, module, housing, log

-- Copied from the Util addon. Used to set item quality borders on the confirmation dialog
-- TODO: Figure out how to use list in Util addon itself.
local qualityColors = {
	ApolloColor.new("ItemQuality_Inferior"),
	ApolloColor.new("ItemQuality_Average"),
	ApolloColor.new("ItemQuality_Good"),
	ApolloColor.new("ItemQuality_Excellent"),
	ApolloColor.new("ItemQuality_Superb"),
	ApolloColor.new("ItemQuality_Legendary"),
	ApolloColor.new("ItemQuality_Artifact"),
	ApolloColor.new("00000000")
}


--- Standard Lua prototype class definition
function HousingBuyToCrate:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

--- Registers this addon wrapper.
-- Called by PurchaseConfirmation during initialization.
function HousingBuyToCrate:Init()
	addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	module = self -- Current module
	log = addon.log
	housing = Apollo.GetAddon("Housing") -- real Housing to hook
	
	if housing == nil then
		error("Addon Housing not installed")
	end
		
	-- Ensures an open confirm dialog is closed when leaving Housing vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	--Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", addon)
	
	self.xmlDoc = XmlDoc.CreateFromFile("HousingBuyToCrate.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	return self
end

function HousingBuyToCrate:OnDocLoaded()	
	-- Check that XML document is properly loaded
	if module.xmlDoc == nil or not module.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(module, "XML document was not loaded")
		log:error("XML document was not loaded")
		return
	end
		
	-- Load Vendor item purchase details form
	local parent = addon.wndDialog:FindChild("DialogArea"):FindChild("VendorSpecificArea")
	module.wnd = Apollo.LoadForm(module.xmlDoc, "ItemLineForm", parent, module)
	if module.wnd == nil then
		Apollo.AddAddonErrorText(module, "Could not load the ConfirmDialog window")
		log:error("OnDocLoaded: wndConfirmDialog is nil!")
		return
	end
	
	module.wnd:Show(true, true)	
	module.xmlDoc = nil
	
	log:info("Module " .. module.MODULE_ID .. " fully loaded")
end

function HousingBuyToCrate:Activate()
	-- Hook into Vendor (if not already done)
	if module.hook == nil then
		log:info("Activating module: " .. module.MODULE_ID)
		module.hook = housing.OnBuyToCrateBtn -- store ref to original function
		housing.OnBuyToCrateBtn = module.Intercept -- replace Housings "OnBuyToCrate" with own interceptor
	else
		log:debug("Module " .. module.MODULE_ID .. " already active, ignoring Activate request")
	end
end

function HousingBuyToCrate:Deactivate()
	if module.hook ~= nil then
		log:info("Deactivating module: " .. module.MODULE_ID)
		housing.OnBuyToCrateBtn = module.hook -- restore original function ref
		module.hook = nil -- clear hook
	else
		log:debug("Module " .. module.MODULE_ID .. " not active, ignoring Deactivate request")
	end
end


--- Main hook interceptor function.
-- Called on Housing addons "Buy to crate" buttonclick / item rightclick.
function HousingBuyToCrate:Intercept(wndControl, wndHandler)
	log:info("Intercept: enter method")

	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = module.hook,
		hookParams = {wndControl, wndHandler},
		hookedAddon = housing
	}	
	
	-- Extract tItemData from purchase
	local tItemData
    if housing.bIsVendor then
		local nRow = housing.wndListView:GetCurrentRow()
		if nRow ~= nil then
			tItemData = self.wndListView:GetCellData(nRow, 1)
		end
	end
	
	-- No itemdata extractable, delegate to Housing and move on
	if tItemData == nil then 
		log:warn("No Housing Buy-to-crate purchase could be identified")
		addon:CompletePurchase(tCallbackData)
	end
	
	-- Store purchase details on module for easier debugging
	if addon.DEBUG_MODE == true then
		module.tItemData = tItemData
	end
	
	-- Also store on tCallbackData to avoid having to extract from wndControl/handler again
	tCallbackData.tItemData = tItemData
	
	-- Price and currency type are simple props on the tItemData table
	local monPrice = tItemData.nCost
	local eCurrencyType = tItemData.eCurrencyType

	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(eCurrencyType)
	if tCurrency == nil then
		log:info("Intercept: Unsupported currentType " .. tostring(eCurrencyType))
		addon:CompletePurchase(tCallbackData)
		return
	end	
		
	-- Aggregated purchase data
	local tPurchaseData = {
		tCallbackData = tCallbackData,
		tCurrency = tCurrency,
		monPrice = monPrice,
	}	
	
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)	
end


--- Provide details for if/when the main-addon decides to show the confirmation dialog.
-- @param tPurchaseDetails, containing all required info about on-going purchase
-- @return [1] window to display on the central details-spot on the dialog.
-- @return [2] table of text strings to set for title/buttons on the dialog
function HousingBuyToCrate:GetDialogDetails(tPurchaseData)
	log:debug("GetDialogWindowDetails: enter method")

	local tItemData = tPurchaseData.tCallbackData.tItemData
	local monPrice = tPurchaseData.monPrice	
	
	local wnd = module.wnd
	
	-- Set basic info on details area
	wnd:FindChild("ItemName"):SetText(tItemData.strName)
	wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
	wnd:FindChild("ItemPrice"):SetMoneySystem(tPurchaseData.tCurrency.eType)
	
	wnd:FindChild("ModelWindow"):SetDecorInfo(tItemData.nId)
		
	-- Rely on standard "Purchase" text strings on dialog, just return window with preview
	return wnd
end
