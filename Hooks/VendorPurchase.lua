--[[
	Provides hook-in functionality for the Vendor addon,
	specifically for the regular "purchase item" functionality.
]]

local VP = {}
Apollo.RegisterPackage(VP, "PurchaseConfirmation:Hooks:VendorPurchase", 1, {"Vendor"})

--- Registers this addon wrapper.
-- Called by PurchaseConfirmation during initialization.
function VP:Register()
	-- Grab addon references for later use
	self.vendor = Apollo.GetAddon("Vendor") -- real Vendor to hook
	self.addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	
	-- Store log ref for easy access 
	self.log = self.self.log

	-- Hook into Vendor
	self.hook = self.vendor.FinalizeBuy -- store ref to original function
	self.vendor.FinalizeBuy = self.InterceptPurchase -- replace Vendors FinalizeBuy with own interceptor
	
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	-- TODO: Test how this plays out with 2 vendors in close proximity (open both, move away from one)
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", addon)
end

function VP:LoadForm()
	self.xmlDoc = XmlDoc.CreateFromFile("Hooks/VendorPurchase.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)

end

function VP:OnDocLoaded()
	-- Check that XML document is properly loaded
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "XML document was not loaded")
		logerror("XML document was not loaded")
		return
	end
		
	-- Load confirmation dialog form 
	self.wndConfirmDialog = Apollo.LoadForm(self.xmlDoc, "DialogForm", nil, self)
	Localization.LocalizeDialog(self.wndConfirmDialog)
	if self.wndConfirmDialog == nil then
		Apollo.AddAddonErrorText(self, "Could not load the ConfirmDialog window")
		logerror("OnDocLoaded", "wndConfirmDialog is nil!")
		return
	end
	self.wndConfirmDialog:Show(false, true)	
	self.xmlDoc = nil

end


--- Main hook interceptor function.
-- Called on Vendor's "Purchase" buttonclick / item rightclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendr
function VP:InterceptPurchase(tItemData)
	self.log:debug("VendorPurchase.InterceptPurchase: enter method")
		
	-- Store item details for easier debugging. Not actually used in application code.
	self.tItemData = tItemData
	self.tItemDetails = Item.GetDetailedInfo(tItemData)
	
	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		fUpdateDetails = VP.UpdateWindowDetails,
		fComplete = VP.CompletePurchase,
		data = tItemData,
	}

	--[[
		Skip unsupported operations by calling addon:CompletePurchase.
		(not addon:ConfirmPurchase). CompletePurchase essentially just
		calls the supplied hook function without futher interferance with
		the purchase itself.
	]]
		
	-- Only check thresholds if this is a purchase (not sales, repairs or buybacks)
	if not self.vendor.wndVendor:FindChild("VendorTab0"):IsChecked() then
		self.log:info("VendorPurchase.InterceptPurchase: Not a purchase")
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	-- No itemdata on purchase, somehow... "this should never happen"
	if not tItemData then
		self.log:warn("VendorPurchase.InterceptPurchase: No tItemData")
		addon:CompletePurchase(tCallbackData)
		return
	end

	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(tItemData.tPriceInfo.eCurrencyType1)
	if tCurrency == nil then
		self.log:info("VendorPurchase.InterceptPurchase: Unsupported currentTypes " .. tostring(tItemData.tPriceInfo.eCurrencyType1) .. " and " .. tostring(tItemData.tPriceInfo.eCurrencyType2))
		addon:CompletePurchase(tCallbackData)
		return
	end
	
	--[[
		Purchase type is supported. Initiate price-check.
	]]
	
	-- Get price of current purchase
	local monPrice = self:GetItemPrice(tItemData)
	
	-- Request pricecheck
	addon:PriceCheck(monPrice, tCallbackData)
end


--- Extracts item price from tItemData
-- @param tItemData Current purchase item data, as supplied by the Vendor addon
function VP:GetItemPrice(tItemData)
	self.log:debug("VendorPurchase.GetItemPrice: enter method")
		
	-- NB: "itemData" is a table property on tItemData. Yeah.
	local monPrice = tItemData.itemData:GetBuyPrice():Multiply(tItemData.nStackSize):GetAmount()
	self.log:debug("VendorPurchase.GetItemPrice: Item price extracted: " .. monPrice)

	return monPrice
end


-- docload
function VP:OnFormLoaded()
	-- stuff
	wndMainDialogArea:FindChild("ItemName"):SetText(tItemData.strName)
	wndMainDialogArea:FindChild("ItemIcon"):SetSprite(tItemData.strIcon)
	wndMainDialogArea:FindChild("ItemPrice"):SetAmount(monPrice, true)
	wndMainDialogArea:FindChild("ItemPrice"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)
	wndMainDialogArea:FindChild("CantUse"):Show(VP:HelperPrereqFailed(tItemData))

end

function VP:UpdateWindowDetails()
end



