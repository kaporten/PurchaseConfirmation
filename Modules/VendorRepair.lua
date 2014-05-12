require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the Vendor addon,
	specifically for the regular "purchase item" functionality.
]]

-- Register module as package
local VendorRepair = {}
local MODULE_NAME = "PurchaseConfirmation:VendorRepair"
Apollo.RegisterPackage(VendorRepair, MODULE_NAME, 1, {"PurchaseConfirmation", "Vendor"})

-- "glocals" set during Init
local addon, module, vendor, log

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
	vendor = Apollo.GetAddon("Vendor") -- real Vendor to hook
	
	-- Hook into Vendor
	self.hook = vendor.FinalizeBuy -- store ref to original function
	vendor.FinalizeBuy = self.InterceptPurchase -- replace Vendors FinalizeBuy with own interceptor
		
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	-- TODO: Test how this plays out with 2 vendors in close proximity (open both, move away from one)
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", addon)
	
	self.xmlDoc = XmlDoc.CreateFromFile("Modules/VendorRepair.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	return self
end

function VendorRepair:OnDocLoaded()	
	-- Check that XML document is properly loaded
	if module.xmlDoc == nil or not module.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(module, "XML document was not loaded")
		log:error("XML document was not loaded")
		return
	end
		
	-- Single-item repair line
	local parent = addon.wndDialog:FindChild("DialogArea"):FindChild("VendorSpecificArea")
	module.wndItem = Apollo.LoadForm(module.xmlDoc, "ItemLineForm", parent, module)
	if module.wndItem == nil then
		Apollo.AddAddonErrorText(module, "Could not load the ItemLineForm window")
		log:error("OnDocLoaded: wndItem is nil!")
		return
	end

	-- Repair-all repair line
	local parent = addon.wndDialog:FindChild("DialogArea"):FindChild("VendorSpecificArea")
	module.wndAll = Apollo.LoadForm(module.xmlDoc, "RepairAllForm", parent, module)
	if module.wndAll == nil then
		Apollo.AddAddonErrorText(module, "Could not load the RepairAllForm window")
		log:error("OnDocLoaded: wndAll is nil!")
		return
	end
		
	module.wndItem:Show(false, true)	
	module.wndAll:Show(false, true)	
	module.xmlDoc = nil
end

function VendorRepair:UpdateDialogDetails(monPrice, tCallbackData)	
	log:debug("PrepareDialogDetails: enter method")

	local tItemData = tCallbackData.hookParams
	local wnd
	
	if tItemData then
		-- Single item repair (basically the same as single-item purchase)
		wnd = module.wndItem
		wnd:FindChild("ItemName"):SetText(tItemData.strName)
		wnd:FindChild("ItemIcon"):SetSprite(tItemData.strIcon)
		wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
		wnd:FindChild("ItemPrice"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)
		wnd:FindChild("CantUse"):Show(vendor:HelperPrereqFailed(tItemData))
					
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

		-- Update tooltip to match current item
		wnd:SetData(tItemData)	
		vendor:OnVendorListItemGenerateTooltip(wnd, wnd)				
	else
		-- All items repair
		wnd = module.wndAll
		wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
		wnd:FindChild("ItemPrice"):SetMoneySystem(tCallbackData.eCurrencyType1)		
	end
	
	
	-- Set basic info on details area
	module.wndItem:Show(tItemData, true)
	module.wndAll:Show(not tItemData, true)

	return wnd
end

--- Main hook interceptor function.
-- Called on Vendor's "Purchase" buttonclick / item rightclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendr
function VendorRepair:InterceptPurchase(tItemData)
	log:debug("InterceptPurchase: enter method")
		
	-- Store item details for easier debugging. Not actually used in application code.
	module.tItemData = tItemData -- Will be nil for "Repair all" ops
	
	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = module.hook,
		hookParams = tItemData,
		hookedAddon = Apollo.GetAddon("Vendor")
	}

	--[[
		Skip unsupported operations by calling addon:CompletePurchase.
		(not addon:ConfirmPurchase). CompletePurchase essentially just
		calls the supplied hook function without futher interferance with
		the purchase itself.
	]]
		
	-- Only check thresholds if this is a repair
	if not vendor.wndVendor:FindChild("VendorTab3"):IsChecked() then
		log:debug("InterceptPurchase: Not a repair")
		addon:CompletePurchase(tCallbackData)
		return
	end

	-- A list of repairable items should exist in tRepariableItems
	if not vendor.tRepairableItems then
		log:warn("InterceptPurchase: No repairable items found")
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	-- Assumption: all repairs will be of same (single) currency type
	local eCurrencyType1 = vendor.tRepairableItems[1].tPriceInfo.eCurrencyType1
	tCallbackData.eCurrencyType1 = eCurrencyType1
	
	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(eCurrencyType1)
	if tCurrency == nil then
		log:info("InterceptPurchase: Unsupported currentTypes " .. tostring(vendor.tRepairableItems[1].tPriceInfo.eCurrencyType1) .. " and " .. tostring(vendor.tRepairableItems[1].tPriceInfo.eCurrencyType2))
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
		monPrice = module:GetRepairCost(tItemData),
	}
		
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)
end

--- Extracts the repair cost for an item
-- @param tItemData Current item to repair, as supplied by the Vendor addon
function VendorRepair:GetRepairCost(tItemData)
	log:debug("GetRepairCost: enter method")
		
	local idLocation = tItemData and tItemData.idLocation or nil
	if idLocation then
		return tItemData.itemData:GetRepairCost() -- single item repair
	else
		-- Summarize total repair cost manually
		local total = 0
		for _,v in pairs(vendor.tRepairableItems) do
			total = total + v.itemData:GetRepairCost()
		end
		return total
	end
end
