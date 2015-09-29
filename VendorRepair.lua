require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the Vendor addon,
	specifically for the regular "repair item" functionality.
]]

-- GeminiLocale
local locale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

-- Register module as package
local VendorRepair = {
	MODULE_ID = "PurchaseConfirmation:VendorRepair",
	strTitle = locale["Module_VendorRepair_Title"],
	strDescription = locale["Module_VendorRepair_Description"],
}
Apollo.RegisterPackage(VendorRepair, VendorRepair.MODULE_ID, 1, {"PurchaseConfirmation"})

-- "glocals" set during Init
local addon, module, vendorAddon, log

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
function VendorRepair:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

--- Registers this addon wrapper.
-- Called by PurchaseConfirmation during initialization.
function VendorRepair:Init()
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

function VendorRepair:Activate()
	if module.hook == nil then
		log:info("Activating module: " .. module.MODULE_ID)
		module.hook = vendorAddon.FinalizeBuy
		vendorAddon.FinalizeBuy = module.Intercept
	else
		log:debug("Module " .. module.MODULE_ID .. " already active, ignoring Activate request")
	end
end

function VendorRepair:Deactivate()
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
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendr
function VendorRepair:Intercept(tItemData)
	log:debug("Intercept: enter method")
		
	-- Store purchase details on module for easier debugging
	if addon.DEBUG_MODE == true then
		module.tItemData = tItemData -- Will be nil for "Repair all" ops
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
		
	-- Only check thresholds if this is a repair
	if not vendorAddon.tWndRefs.wndVendor:FindChild("VendorTab3"):IsChecked() then
		log:debug("Intercept: Not a repair")
		addon:CompletePurchase(tCallbackData)
		return
	end

	-- A list of repairable items should exist in tRepariableItems
	if not vendorAddon.tRepairableItems then
		log:warn("Intercept: No repairable items found")
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	-- Assumption: all repairs will be of same (single) currency type
	local eCurrencyType1 = vendorAddon.tRepairableItems[1].tPriceInfo.eCurrencyType1
	tCallbackData.eCurrencyType1 = eCurrencyType1
	
	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(eCurrencyType1)
	if tCurrency == nil then
		log:info("Intercept: Unsupported currentTypes " .. tostring(vendorAddon.tRepairableItems[1].tPriceInfo.eCurrencyType1) .. " and " .. tostring(vendorAddon.tRepairableItems[1].tPriceInfo.eCurrencyType2))
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
		monPrice = module:GetPrice(tItemData),
	}
		
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)
end

--- Extracts the repair cost for an item
-- @param tItemData Current item to repair, as supplied by the Vendor addon
function VendorRepair:GetPrice(tItemData)
	log:debug("GetPrice: enter method")
		
	local idLocation = tItemData and tItemData.idLocation or nil
	if idLocation then
		return tItemData.itemData:GetRepairCost() -- single item repair
	else
		-- Summarize total repair cost manually
		local total = 0
		for _,v in pairs(vendorAddon.tRepairableItems) do
			total = total + v.itemData:GetRepairCost()
		end 
		
		log:debug("GetPrice: Price extracted: " .. total)
		return total
	end
end

--- Provide details for if/when the main-addon decides to show the confirmation dialog.
-- @param tPurchaseDetails, containing all required info about on-going purchase
-- @return [1] window to display on the central details-spot on the dialog.
-- @return [2] table of text strings to set for title/buttons on the dialog
function VendorRepair:GetDialogDetails(tPurchaseData)	
	log:debug("ProduceDialogDetailsWindow: enter method")

	local tCallbackData = tPurchaseData.tCallbackData
	local monPrice = tPurchaseData.monPrice		
	
	local tItemData = tCallbackData.hookParams[1]
	local wnd
	
	if tItemData then
		-- Single item repair (basically the same as single-item purchase)		
		wnd = addon:GetDetailsForm(module.MODULE_ID, vendorAddon.tWndRefs.wndVendor, addon.eDetailForms.StandardItem)
		wnd:FindChild("ItemName"):SetText(tItemData.strName)
		wnd:FindChild("ItemIcon"):SetSprite(tItemData.strIcon)
		wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
		wnd:FindChild("ItemPrice"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)
		wnd:FindChild("CantUse"):Show(vendorAddon:HelperPrereqFailed(tItemData))
					
		-- Extract item quality
		local eQuality = tonumber(Item.GetDetailedInfo(tItemData).tPrimary.eQuality)
	
		-- Add pixie quality-color border to the ItemIcon element
		local tPixieOverlay = {
			strSprite = "UI_BK3_ItemQualityWhite",
			loc = {fPoints = {0, 0, 1, 1}, nOffsets = {0, 0, 0, 0}},
			cr = qualityColors[math.max(1, math.min(eQuality, #qualityColors))]
		}
		wnd:FindChild("ItemIcon"):DestroyAllPixies()
		wnd:FindChild("ItemIcon"):AddPixie(tPixieOverlay)

		wnd:FindChild("StackSize"):Show(false, true)
		
		-- Update tooltip to match current item
		wnd:SetData(tItemData)	
		vendorAddon:OnVendorListItemGenerateTooltip(wnd, wnd)				
	else
		-- All items repair
		wnd = addon:GetDetailsForm(module.MODULE_ID, vendorAddon.tWndRefs.wndVendor, addon.eDetailForms.SimpleIcon)
		
		wnd:FindChild("Text"):SetText(Apollo.GetString("Vendor_RepairAll"))
		wnd:FindChild("Price"):SetAmount(monPrice, true)
		wnd:FindChild("Price"):SetMoneySystem(tCallbackData.eCurrencyType1)
		wnd:FindChild("Icon"):SetSprite("IconSprites:Icon_BuffWarplots_repair")
	end	
	
	-- Build optional table of static text strings (strTitle, StrConfirm, strCancel)
	tStrings = {}
	tStrings.strTitle = Apollo.GetString("CRB_Confirm") .. " " .. Apollo.GetString("Launcher_Repair") -- "Confirm Repair"
	if tItemData then
		tStrings.strConfirm = Apollo.GetString("Launcher_Repair") -- "Repair"
	else
		-- To keep consistent with stock Vendor UI, don't show item count on button
		tStrings.strConfirm = String_GetWeaselString(Apollo.GetString("Vendor_RepairAll"), "") -- "Repair All" 
	end	
	
	return wnd, tStrings
end


