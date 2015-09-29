require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the Vendor addon,
	specifically for the regular "purchase item" functionality.
]]

-- GeminiLocale
local locale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

-- Register module as package
local VendorPurchase = {
	MODULE_ID = "PurchaseConfirmation:VendorPurchase",
	strTitle = locale["Module_VendorPurchase_Title"],
	strDescription = locale["Module_VendorPurchase_Description"],
}
Apollo.RegisterPackage(VendorPurchase, VendorPurchase.MODULE_ID, 1, {"PurchaseConfirmation", "Vendor"})

-- "glocals" set during Init
local addon, module, vendorAddon, log

--- Standard Lua prototype class definition
function VendorPurchase:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

--- Registers this addon wrapper.
-- Called by PurchaseConfirmation during initialization.
function VendorPurchase:Init()
	addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	module = self -- Current module
	log = addon.log
	
	-- Reference to vendor addon
	vendorAddon = Apollo.GetAddon("Vendor")
	if vendorAddon == nil then
		self.strFailureMessage = string.format(locale["Module_Failure_Addon_Missing"], "Vendor")
		error(self.strFailureMessage)
	end
		
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", addon)
	
	return self
end

function VendorPurchase:Activate()
	if module.hook == nil then
		log:info("Activating module: " .. module.MODULE_ID)
		module.hook = vendorAddon.FinalizeBuy
		vendorAddon.FinalizeBuy = module.Intercept
	else
		log:debug("Module " .. module.MODULE_ID .. " already active, ignoring Activate request")
	end
end

function VendorPurchase:Deactivate()
	if module.hook ~= nil then
		log:info("Deactivating module: " .. module.MODULE_ID)
		vendorAddon.FinalizeBuy = module.hook
		module.hook = nil
	else
		log:debug("Module " .. module.MODULE_ID .. " not active, ignoring Deactivate request")
	end
end

--- Main hook interceptor function.
-- Called on Vendor's "Purchase" buttonclick / item rightclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendor
function VendorPurchase:Intercept(tItemData)
	log:debug("Intercept: enter method")
		
	-- Store purchase details on module for easier debugging
	if addon.DEBUG_MODE == true then
		module.tItemData = tItemData
	end
	
	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = module.hook,
		hookParams = {
			tItemData
		},
		bHookParamsUnpack = true,
		hookedAddon = vendorAddon
	}

	--[[
		Skip unsupported operations by calling addon:CompletePurchase.
		(not addon:ConfirmPurchase). CompletePurchase essentially just
		calls the supplied hook function without futher interferance with
		the purchase itself.
	]]
		
	-- Only check thresholds if this is a purchase (not sales, repairs or buybacks)
	if not vendorAddon.tWndRefs.wndVendor:FindChild("VendorTab0"):IsChecked() then
		log:debug("Intercept: Not a purchase")
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	-- No itemdata on purchase, somehow... "this should never happen"
	if not tItemData then
		log:warn("Intercept: No tItemData")
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	-- Determine spinner purchase-count
	local nSpinnerAmount = 1
	local wndSpinner = vendorAddon.tWndRefs.wndVendor:FindChild("AmountValue")
	if wndSpinner ~= nil then
		nSpinnerAmount = wndSpinner:GetValue() or 1
	end
	--log:info("Spinner Amount: " .. nSpinnerAmount)
	
	-- Determine stacksize 
	local nStackSize = tItemData.nStackSize or 1
	--log:info("Stack Size: " .. nStackSize)
	
	local nCount = nSpinnerAmount * nStackSize
	--log:info("Total item count: " .. nCount)
	
	tCallbackData.nCount = nCount
	log:warn("Item count determined: %d", tCallbackData.nCount)		
	
	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(tItemData.tPriceInfo.eCurrencyType1)
	if tCurrency == nil then
		log:info("Intercept: Unsupported currentTypes " .. tostring(tItemData.tPriceInfo.eCurrencyType1) .. " and " .. tostring(tItemData.tPriceInfo.eCurrencyType2))
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	--[[
		Purchase type is supported. Initiate price-check.
	]]

	-- Aggregated purchase data
	local tPurchaseData = {
		tCallbackData = tCallbackData,
		tCurrency = tCurrency,
		monPrice = module:GetPrice(tItemData, nCount),
	}
		
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)
end

--- Extracts item price from tItemData
-- @param tItemData Current purchase item data, as supplied by the Vendor addon
function VendorPurchase:GetPrice(tItemData, nCount)
	log:debug("GetPrice: enter method, count: %s", tostring(nCount))
	local monPrice = tItemData.tPriceInfo.nAmount1 * nCount	
	log:debug("GetPrice: Price extracted: " .. monPrice)

	return monPrice
end

--- Provide details for if/when the main-addon decides to show the confirmation dialog.
-- @param tPurchaseDetails, containing all required info about on-going purchase
-- @return [1] window to display on the central details-spot on the dialog.
-- @return [2] table of text strings to set for title/buttons on the dialog
function VendorPurchase:GetDialogDetails(tPurchaseData)
	log:debug("GetDialogWindowDetails: enter method")
	
	local tCallbackData = tPurchaseData.tCallbackData
	local monPrice = tPurchaseData.monPrice	
	
	local tItemData = tCallbackData.hookParams[1]
	
	-- Get standard detail form for a dialog with Vendor as parent
	local wnd = addon:GetDetailsForm(module.MODULE_ID, vendorAddon.tWndRefs.wndVendor, addon.eDetailForms.StandardItem)
		
	-- Set basic info on details area
	wnd:FindChild("ItemName"):SetText(tItemData.strName)
	wnd:FindChild("ItemIcon"):GetWindowSubclass():SetItem(tItemData.itemData)
	wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
	wnd:FindChild("ItemPrice"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)
	wnd:FindChild("CantUse"):Show(vendorAddon:HelperPrereqFailed(tItemData))
	
	-- Only show stack size count if we're buying more a >1 size stack
	if (tCallbackData.nCount > 1) then
		wnd:FindChild("StackSize"):SetText(tCallbackData.nCount)
		wnd:FindChild("StackSize"):Show(true, true)
	else
		wnd:FindChild("StackSize"):Show(false, true)
	end

	-- Update tooltip to match current item
	wnd:SetData(tItemData)	
	vendorAddon:OnVendorListItemGenerateTooltip(wnd, wnd)

	return wnd
end
