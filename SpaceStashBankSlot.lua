require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the SpaceStash addon,
	specifically for the regular "buy bank slot" functionality.
]]

-- GeminiLocale
local locale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

-- Register module as package
local SpaceStashBankSlot = {
	MODULE_ID = "PurchaseConfirmation:SpaceStashBankSlot",
	strTitle = locale["Module_SpaceStashBankSlot_Title"],
	strDescription = locale["Module_SpaceStashBankSlot_Description"],
}
Apollo.RegisterPackage(SpaceStashBankSlot, SpaceStashBankSlot.MODULE_ID, 1, {"SpaceStashBank"})

-- "glocals" set during Init
local addon, module, spacestash, log


--- Standard Lua prototype class definition
function SpaceStashBankSlot:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

--- Registers this addon wrapper.
-- Called by PurchaseConfirmation during initialization.
function SpaceStashBankSlot:Init()
	addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	module = self -- Current module
	log = addon.log
	spacestash = Apollo.GetAddon("SpaceStashBank")
	
	-- Dependency check on required addon
	if spacestash == nil then
		self.strFailureMessage = string.format(locale["Module_Failure_Addon_Missing"], "SpaceStashBank")
		error(self.strFailureMessage)
	end	
			
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	Apollo.RegisterEventHandler("HideBank", "OnCancelPurchase", addon)

	return self
end

function SpaceStashBankSlot:Activate()
	-- Hook into SpaceStash addon
	if module.hook == nil then
		log:info("Activating module: " .. module.MODULE_ID)
		module.hook = spacestash.OnBuyBankSlot -- store ref to original function
		spacestash.OnBuyBankSlot = module.Intercept -- replace Vendors FinalizeBuy with own interceptor
	else
		log:debug("Module " .. module.MODULE_ID .. " already active, ignoring Activate request")
	end
end

function SpaceStashBankSlot:Deactivate()
	if module.hook ~= nil then
		log:info("Deactivating module: " .. module.MODULE_ID)
		spacestash.OnBuyBankSlot = module.hook -- restore original function ref
		module.hook = nil -- clear hook
	else
		log:debug("Module " .. module.MODULE_ID .. " not active, ignoring Deactivate request")
	end
end

--- Main hook interceptor function.
-- Called on Vendor's "Purchase" buttonclick / item rightclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendr
function SpaceStashBankSlot:Intercept()
	log:debug("Intercept: enter method")
		
	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = module.hook,
		hookParams = nil,
		hookedAddon = spacestash
	}
	
	local eCurrencyType1 = GameLib.GetNextBankBagCost():GetMoneyType()	
	
	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(eCurrencyType1)
	if tCurrency == nil then
		log:info("Intercept: Unsupported currentType " .. tostring(eCurrencyType1))
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
		monPrice = GameLib.GetNextBankBagCost():GetAmount()
	}
		
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)
end


--- Provide details for if/when the main-addon decides to show the confirmation dialog.
-- @param tPurchaseDetails, containing all required info about on-going purchase
-- @return [1] window to display on the central details-spot on the dialog.
-- @return [2] table of text strings to set for title/buttons on the dialog
function SpaceStashBankSlot:GetDialogDetails(tPurchaseData)	
	log:debug("ProduceDialogDetailsWindow: enter method")

	local tCallbackData = tPurchaseData.tCallbackData
	local monPrice = tPurchaseData.monPrice		
			
	local wnd = addon:GetDetailsForm(module.MODULE_ID, spacestash.wndMain, addon.eDetailForms.SimpleIcon)

	wnd:FindChild("Text"):SetText(Apollo.GetString("Bank_BuySlotBtn"))
	wnd:FindChild("Icon"):SetSprite("IconSprites:Icon_ItemMisc_Bag_10Slot")
	wnd:FindChild("Price"):SetAmount(monPrice, true)
	wnd:FindChild("Price"):SetMoneySystem(tPurchaseData.tCurrency.eType)
	
	return wnd
end


