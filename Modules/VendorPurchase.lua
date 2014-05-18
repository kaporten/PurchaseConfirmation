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
	vendor = Apollo.GetAddon("Vendor") -- real Vendor to hook
		
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	-- TODO: Test how this plays out with 2 vendors in close proximity (open both, move away from one)
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", addon)
	
	self.xmlDoc = XmlDoc.CreateFromFile("Modules/VendorPurchase.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	return self
end

function VendorPurchase:OnDocLoaded()	
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

function VendorPurchase:Activate()
	-- Hook into Vendor (if not already done)
	if module.hook == nil then
		log:info("Activating module: " .. module.MODULE_ID)
		module.hook = vendor.FinalizeBuy -- store ref to original function
		vendor.FinalizeBuy = module.InterceptPurchase -- replace Vendors FinalizeBuy with own interceptor
	else
		log:debug("Module " .. module.MODULE_ID .. " already active, ignoring Activate request")
	end
end

function VendorPurchase:Deactivate()
	if module.hook ~= nil then
		log:info("Deactivating module: " .. module.MODULE_ID)
		vendor.FinalizeBuy = module.hook -- restore original function ref
		module.hook = nil -- clear hook
	else
		log:debug("Module " .. module.MODULE_ID .. " not active, ignoring Deactivate request")
	end
end

function VendorPurchase:ProduceDialogDetailsWindow(tPurchaseData)
	log:debug("ProduceDialogDetailsWindow: enter method")

	local tCallbackData = tPurchaseData.tCallbackData
	local monPrice = tPurchaseData.monPrice	
	
	local tItemData = tCallbackData.hookParams
	local wnd = module.wnd
	
	-- Set basic info on details area
	wnd:FindChild("ItemName"):SetText(tItemData.strName)
	wnd:FindChild("ItemIcon"):SetSprite(tItemData.strIcon)
	wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
	wnd:FindChild("ItemPrice"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)
	wnd:FindChild("CantUse"):Show(vendor:HelperPrereqFailed(tItemData))
	
	-- Only show stack size count if we're buying more a >1 size stack
	if (tItemData.nStackSize > 1) then
		wnd:FindChild("StackSize"):SetText(tItemData.nStackSize)
		wnd:FindChild("StackSize"):Show(true, true)
	else
		wnd:FindChild("StackSize"):Show(false, true)
	end
	
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
	vendor:OnVendorListItemGenerateTooltip(self.wnd, self.wnd)

	return wnd
end

--- Main hook interceptor function.
-- Called on Vendor's "Purchase" buttonclick / item rightclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendr
function VendorPurchase:InterceptPurchase(tItemData)
	log:debug("InterceptPurchase: enter method")
		
	-- Store item details for easier debugging. Not actually used in application code.
	module.tItemData = tItemData
	
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
		
	-- Only check thresholds if this is a purchase (not sales, repairs or buybacks)
	if not vendor.wndVendor:FindChild("VendorTab0"):IsChecked() then
		log:debug("InterceptPurchase: Not a purchase")
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	-- No itemdata on purchase, somehow... "this should never happen"
	if not tItemData then
		log:warn("InterceptPurchase: No tItemData")
		addon:CompletePurchase(tCallbackData)
		return
	end

	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(tItemData.tPriceInfo.eCurrencyType1)
	if tCurrency == nil then
		log:info("InterceptPurchase: Unsupported currentTypes " .. tostring(tItemData.tPriceInfo.eCurrencyType1) .. " and " .. tostring(tItemData.tPriceInfo.eCurrencyType2))
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
		monPrice = module:GetItemPrice(tItemData),
	}
		
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)
end


--- Extracts item price from tItemData
-- @param tItemData Current purchase item data, as supplied by the Vendor addon
function VendorPurchase:GetItemPrice(tItemData)
	log:debug("GetItemPrice: enter method")
		
	-- NB: "itemData" is a table property on tItemData. Yeah.
	local monPrice = tItemData.itemData:GetBuyPrice():Multiply(tItemData.nStackSize):GetAmount()
	log:debug("GetItemPrice: Item price extracted: " .. monPrice)

	return monPrice
end


