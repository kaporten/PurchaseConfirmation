require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the Vendor addon,
	specifically for the regular "purchase item" functionality.
]]


local MODULE_NAME = "PurchaseConfirmation:Modules:VendorPurchase"

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

local VendorPurchase = {}
Apollo.RegisterPackage(VendorPurchase, MODULE_NAME, 1, {"Vendor"})

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
	-- Grab addon references for later use
	self.vendor = Apollo.GetAddon("Vendor") -- real Vendor to hook
	self.addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	
	-- Store log ref for easy access 
	self.log = self.addon.log

	-- Hook into Vendor
	self.hook = self.vendor.FinalizeBuy -- store ref to original function
	self.vendor.FinalizeBuy = self.InterceptPurchase -- replace Vendors FinalizeBuy with own interceptor

		
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	-- TODO: Test how this plays out with 2 vendors in close proximity (open both, move away from one)
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", addon)
	
	return self
end

function VendorPurchase:PrepareDialogDetails(wndParent, tCallbackData, fDialogDetailsReady)
	local addon = Apollo.GetAddon("PurchaseConfirmation") -- PurchaseConfirmation main adon
	local module = addon.modules[MODULE_NAME] -- VendorPurchase module

	-- Async lazy-loading of form on first hit
	if module.wnd == nil then
		-- Store parameters for reuse in delayed invocation
		module.pendingPriceCheckData = {wndParent, tCallbackData, fDialogDetailsReady}
		
		-- Initiate load of XML document
		module.xmlDoc = XmlDoc.CreateFromFile("VendorPurchase.xml")
		module.xmlDoc:RegisterCallback("OnDocLoaded", module)
		
		-- Await 2nd call, once form is loaded
		return 
	end
	
	local tItemData = tCallbackData.data
	
	-- Set basic info on details area
	module.wnd:FindChild("ItemName"):SetText(tItemData.strName)
	module.wnd:FindChild("ItemIcon"):SetSprite(tItemData.strIcon)
	module.wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
	module.wnd:FindChild("ItemPrice"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)
	module.wnd:FindChild("CantUse"):Show(VendorPurchase:HelperPrereqFailed(tItemData))
	
	-- Only show stack size count if we're buying more a >1 size stack
	if (tItemData.nStackSize > 1) then
		module.wnd:FindChild("StackSize"):SetText(tItemData.nStackSize)
		module.wnd:FindChild("StackSize"):Show(true, true)
	else
		module.wnd:FindChild("StackSize"):Show(false, true)
	end
	
	-- Extract item quality
	local eQuality = tonumber(Item.GetDetailedInfo(tItemData).tPrimary.eQuality)

	-- Add pixie quality-color border to the ItemIcon element
	local tPixieOverlay = {
		strSprite = "UI_BK3_ItemQualityWhite",
		loc = {fPoints = {0, 0, 1, 1}, nOffsets = {0, 0, 0, 0}},
		cr = qualityColors[math.max(1, math.min(eQuality, #qualityColors))]
	}	
	module.wnd:FindChild("ItemIcon"):AddPixie(tPixieOverlay)

	-- Update tooltip to match current item
	module.wnd:SetData(tItemData)	
	module.vendor:OnVendorListItemGenerateTooltip(self.wnd, self.wnd)
	
	-- Dialog details are prepared, call main-addon function to show dialog	
	fDialogDetailsReady(wnd)
end


function VendorPurchase:OnDocLoaded()
	-- Check that XML document is properly loaded
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "XML document was not loaded")
		self.log:error("XML document was not loaded")
		return
	end
		
	-- Load Vendor item purchase details form
	self.wnd = Apollo.LoadForm(self.xmlDoc, "ItemLineForm", wndParent, self)
	if self.wndConfirmDialog == nil then
		Apollo.AddAddonErrorText(self, "Could not load the ConfirmDialog window")
		self.log:error("OnDocLoaded", "wndConfirmDialog is nil!")
		return
	end
	
	self.wnd:Show(false, true)	
	self.xmlDoc = nil

	local pendingPriceCheckData = self.pendingPriceCheckData
	self.pendingPriceCheckData = nil
	
	self:PrepareDialogDetails(unpack(pendingPriceCheckData))
end


--- Main hook interceptor function.
-- Called on Vendor's "Purchase" buttonclick / item rightclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendr
function VendorPurchase:InterceptPurchase(tItemData)
	local addon = Apollo.GetAddon("PurchaseConfirmation") -- PurchaseConfirmation main adon
	local module = addon.modules[MODULE_NAME] -- VendorPurchase module
	
	module.log:debug("VendorPurchase.InterceptPurchase: enter method")
		
	-- Store item details for easier debugging. Not actually used in application code.
	module.tItemData = tItemData
	module.tItemDetails = Item.GetDetailedInfo(tItemData)
	
	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = self.hook,
		data = tItemData,
	}

	--[[
		Skip unsupported operations by calling addon:CompletePurchase.
		(not addon:ConfirmPurchase). CompletePurchase essentially just
		calls the supplied hook function without futher interferance with
		the purchase itself.
	]]
		
	-- Only check thresholds if this is a purchase (not sales, repairs or buybacks)
	if not module.vendor.wndVendor:FindChild("VendorTab0"):IsChecked() then
		module.log:info("VendorPurchase.InterceptPurchase: Not a purchase")
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	-- No itemdata on purchase, somehow... "this should never happen"
	if not tItemData then
		module.log:warn("VendorPurchase.InterceptPurchase: No tItemData")
		addon:CompletePurchase(tCallbackData)
		return
	end

	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(tItemData.tPriceInfo.eCurrencyType1)
	if tCurrency == nil then
		module.log:info("VendorPurchase.InterceptPurchase: Unsupported currentTypes " .. tostring(tItemData.tPriceInfo.eCurrencyType1) .. " and " .. tostring(tItemData.tPriceInfo.eCurrencyType2))
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	--[[
		Purchase type is supported. Initiate price-check.
	]]
	
	-- Get price of current purchase
	local monPrice = module:GetItemPrice(tItemData)
	
	-- Request pricecheck
	addon:PriceCheck(monPrice, tCallbackData, tCurrency)
end


--- Extracts item price from tItemData
-- @param tItemData Current purchase item data, as supplied by the Vendor addon
function VendorPurchase:GetItemPrice(tItemData)
	self.log:debug("VendorPurchase.GetItemPrice: enter method")
		
	-- NB: "itemData" is a table property on tItemData. Yeah.
	local monPrice = tItemData.itemData:GetBuyPrice():Multiply(tItemData.nStackSize):GetAmount()
	self.log:debug("VendorPurchase.GetItemPrice: Item price extracted: " .. monPrice)

	return monPrice
end


