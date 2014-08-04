require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for dying items in the Costumes addon
]]

-- GeminiLocale
local locale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")
local H = Apollo.GetPackage("Gemini:Hook-1.0").tPackage

-- Register module as package
local CostumesDye = {
	MODULE_ID = "PurchaseConfirmation:CostumesDye",
	strTitle = locale["Module_CostumesDye_Title"],
	strDescription = locale["Module_CostumesDye_Description"],
}
Apollo.RegisterPackage(CostumesDye, CostumesDye.MODULE_ID, 1, {"PurchaseConfirmation", "Costumes"})

-- "glocals" set during Init
local addon, module, costumes, log

--- Standard Lua prototype class definition
function CostumesDye:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

--- Registers this addon wrapper.
-- Called by PurchaseConfirmation during initialization.
function CostumesDye:Init()
	addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	module = self -- Current module
	log = addon.log
	costumes = Apollo.GetAddon("Costumes") -- real Vendor to hook

	-- Dependency check on required addon
	if costumes == nil then
		self.strFailureMessage = string.format(locale["Module_Failure_Addon_Missing"], "Costumes")
		error(self.strFailureMessage)
	end	
			
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	Apollo.RegisterEventHandler("HideDye", "OnCancelPurchase", addon)
	
	return self
end

function CostumesDye:Activate()
	-- Hook into Vendor (if not already done)
	if H:IsHooked(costumes, "OnDyeBtnClicked") then
		log:debug("Module %s already active, ignoring Activate request", module.MODULE_ID)
	else
		log:info("Activating module: %s", module.MODULE_ID)		
		H:RawHook(costumes, "OnDyeBtnClicked", CostumesDye.Intercept) -- Actual buy-intercept
	end
end

function CostumesDye:Deactivate()
	if H:IsHooked(costumes, "OnDyeBtnClicked") then
		log:info("Deactivating module: %s", module.MODULE_ID)
		H:Unhook(costumes, "OnDyeBtnClicked")		
	else
		log:debug("Module %s not active, ignoring Deactivate request", module.MODULE_ID)
	end
end

--- Main hook interceptor function.
-- Called on Costumes's "Dye" buttonclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendr
function CostumesDye:Intercept(wndHandler, wndControl)
	log:debug("Intercept: enter method")
		
	-- Store purchase details on module for easier debugging
	if addon.DEBUG_MODE == true then
		module.wndHandler = wndHandler
		module.wndControl = wndControl
	end
	
	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = H.hooks[costumes]["OnDyeBtnClicked"],
		hookParams = {
			wndHandler, 
			wndControl
		},
		bHookParamsUnpack = true,
		hookedAddon = costumes
	}

	--[[
		Skip unsupported operations by calling addon:CompletePurchase.
		(not addon:ConfirmPurchase). CompletePurchase essentially just
		calls the supplied hook function without futher interferance with
		the purchase itself.
	]]
	
	-- Input sanity checks copied from Costumes addon
	if wndHandler ~= wndControl then return end
	if not GameLib.CanDye() then return end	
	
	--[[
		Purchase type is supported. Initiate price-check.
	]]
	
	-- Aggregated purchase data
	local tPurchaseData = {
		tCallbackData = tCallbackData,
		tCurrency = addon:GetSupportedCurrencyByEnum(costumes.wndCost:GetCurrency():GetMoneyType()),
		monPrice = costumes.wndCost:GetAmount(),
	}
		
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)
end

--- Provide details for if/when the main-addon decides to show the confirmation dialog.
-- @param tPurchaseDetails, containing all required info about on-going purchase
-- @return [1] window to display on the central details-spot on the dialog.
-- @return [2] table of text strings to set for title/buttons on the dialog
function CostumesDye:GetDialogDetails(tPurchaseData)	
	log:debug("ProduceDialogDetailsWindow: enter method")

	local tCallbackData = tPurchaseData.tCallbackData
	local monPrice = tPurchaseData.monPrice
	
	local wnd = addon:GetDetailsForm(module.MODULE_ID, costumes.wndMain, addon.eDetailForms.SimpleIcon)
	
	wnd:FindChild("Text"):SetText(Apollo.GetString("Dyeing_WindowTitle"))
	wnd:FindChild("Icon"):SetSprite("IconSprites:Icon_ItemDyes_UI_Item_Dye_BlueGreen_Primary_000")
	wnd:FindChild("Price"):SetAmount(monPrice, true)
	wnd:FindChild("Price"):SetMoneySystem(tPurchaseData.tCurrency.eType)	
	
	return wnd
end


