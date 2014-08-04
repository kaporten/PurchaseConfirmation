require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the Housing addon,
	specifically for the "buy to crate".
]]

-- GeminiLocale & GeminiHook
local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")
local H = Apollo.GetPackage("Gemini:Hook-1.0").tPackage

-- Register module as package
local HousingBuyToCrate = {
	MODULE_ID = "PurchaseConfirmation:HousingBuyToCrate",
	strTitle = L["Module_HousingBuyToCrate_Title"],
	strDescription = L["Module_HousingBuyToCrate_Description"],
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
	
	-- Dependency check on required addon
	if housing == nil then
		self.strFailureMessage = string.format(L["Module_Failure_Addon_Missing"], "Housing")
		error(self.strFailureMessage)
	end	
	
	return self
end

function HousingBuyToCrate:Activate()
	-- Hook into Vendor (if not already done)
	if H:IsHooked(housing, "OnBuyToCrateBtn") then
		log:debug("Module %s already active, ignoring Activate request", module.MODULE_ID)
	else
		log:info("Activating module: %s", module.MODULE_ID)		
		H:RawHook(housing, "OnBuyToCrateBtn", HousingBuyToCrate.Intercept) -- Actual buy-intercept
		H:RawHook(housing, "OnWindowClosed", HousingBuyToCrate.OnWindowClosed) -- Closing the vendor-window
	end
end

function HousingBuyToCrate:Deactivate()
	if H:IsHooked(housing, "OnBuyToCrateBtn") then
		log:info("Deactivating module: %s", module.MODULE_ID)
		H:Unhook(housing, "OnBuyToCrateBtn")		
		H:Unhook(housing, "OnWindowClosed")
	else
		log:debug("Module %s not active, ignoring Deactivate request", module.MODULE_ID)
	end
end


--- Main hook interceptor function.
-- Called on Housing addons "Buy to crate" buttonclick / item rightclick.
function HousingBuyToCrate:Intercept(wndControl, wndHandler)
	log:info("Intercept: enter method")

	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = H.hooks[housing]["OnBuyToCrateBtn"],
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
	
	local wnd = addon:GetDetailsForm(module.MODULE_ID, housing.wndDecorate, addon.eDetailForms.Preview)
	
	-- Set basic info on details area
	wnd:FindChild("ItemName"):SetText(tItemData.strName)
	wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
	wnd:FindChild("ItemPrice"):SetMoneySystem(tPurchaseData.tCurrency.eType)
	
	wnd:FindChild("ModelWindow"):SetDecorInfo(tItemData.nId)
		
	-- Rely on standard "Purchase" text strings on dialog, just return window with preview
	return wnd
end

function HousingBuyToCrate:OnWindowClosed(...)
	-- First, pass the window closed call on to Housing
	H.hooks[housing]["OnWindowClosed"](housing, ...)
	
	-- Second, cancel the confirmation dialog
	addon.OnCancelPurchase(addon)
end
