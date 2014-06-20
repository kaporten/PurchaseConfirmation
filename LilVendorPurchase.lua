require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the LilVendor addon,
	specifically for the regular "purchase item" functionality.
]]

-- GeminiLocale
local locale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

-- Register module as package
local LilVendorPurchase = {
	MODULE_ID = "PurchaseConfirmation:LilVendorPurchase",
	strTitle = locale["Module_LilVendorPurchase_Title"],
	strDescription = locale["Module_LilVendorPurchase_Description"],
}
Apollo.RegisterPackage(LilVendorPurchase, LilVendorPurchase.MODULE_ID, 1, {"LilVendor"})

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
function LilVendorPurchase:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

--- Registers this addon wrapper.
-- Called by PurchaseConfirmation during initialization.
function LilVendorPurchase:Init()
	addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	module = self -- Current module
	log = addon.log
	vendor = Apollo.GetAddon("LilVendor") -- LilVendor addon
	
	-- Dependency check on required addon
	if vendor == nil then
		self.strFailureMessage = string.format(locale["Module_Failure_Addon_Missing"], "LilVendor")
		error(self.strFailureMessage)
	end		
			
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", addon)
	
	self.xmlDoc = XmlDoc.CreateFromFile("VendorPurchase.xml") -- reuse stock VendorPurchase form
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	return self
end

function LilVendorPurchase:OnDocLoaded()	
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

function LilVendorPurchase:Activate()
	-- Hook into Vendor (if not already done)
	if module.hook == nil then
		log:info("Activating module: " .. module.MODULE_ID)
		module.hook = vendor.FinalizeBuy -- store ref to original function
		vendor.FinalizeBuy = module.Intercept -- replace Vendors FinalizeBuy with own interceptor
	else
		log:debug("Module " .. module.MODULE_ID .. " already active, ignoring Activate request")
	end
end

function LilVendorPurchase:Deactivate()
	if module.hook ~= nil then
		log:info("Deactivating module: " .. module.MODULE_ID)
		vendor.FinalizeBuy = module.hook -- restore original function ref
		module.hook = nil -- clear hook
	else
		log:debug("Module " .. module.MODULE_ID .. " not active, ignoring Deactivate request")
	end
end


--- Main hook interceptor function.
-- Called on Vendor's "Purchase" buttonclick / item rightclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendor
function LilVendorPurchase:Intercept(tItemData)
	log:debug("Intercept: enter method")
		
	-- Store purchase details on module for easier debugging
	if addon.DEBUG_MODE == true then
		module.tItemData = tItemData
	end
	
	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = module.hook,
		hookParams = tItemData,
		hookedAddon = vendor
	}

	--[[
		Skip unsupported operations by calling addon:CompletePurchase.
		(not addon:ConfirmPurchase). CompletePurchase essentially just
		calls the supplied hook function without futher interferance with
		the purchase itself.
	]]
		
	-- Only check thresholds if this is a purchase (not sales, repairs or buybacks)
	if not vendor.wndLilVendor:FindChild("VendorTab0"):IsChecked() then
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
		monPrice = module:GetPrice(tItemData),
	}
		
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)
end

--- Extracts item price from tItemData
-- @param tItemData Current purchase item data, as supplied by the Vendor addon
function LilVendorPurchase:GetPrice(tItemData)
	log:debug("GetPrice: enter method")
	local monPrice = 0
	
	if type(tItemData.itemData) == "table" then
		-- Regular items have a nested "itemData" object with functions for getting price etc.
		-- If that exist, use it to extract price details since that is how the Vendor module does it
		monPrice = tItemData.itemData:GetBuyPrice():Multiply(tItemData.nStackSize):GetAmount()
	elseif type(tItemData.tPriceInfo) == "table" then
		-- If no nested itemData table exists, just get the "raw" price. Only known case so far: buying the mount speed upgrade.
		monPrice = tItemData.tPriceInfo.nAmount1		
	end
	
	log:debug("GetPrice: Price extracted: " .. monPrice)

	return monPrice
end

--- Provide details for if/when the main-addon decides to show the confirmation dialog.
-- @param tPurchaseDetails, containing all required info about on-going purchase
-- @return [1] window to display on the central details-spot on the dialog.
-- @return [2] table of text strings to set for title/buttons on the dialog
function LilVendorPurchase:GetDialogDetails(tPurchaseData)
	log:debug("GetDialogWindowDetails: enter method")

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
	-- Some items (like mount speed upgrade) has no quality. Set default quality to none and override if quality is present
	local eQuality = #qualityColors
	local tItemDetailedInfo = Item.GetDetailedInfo(tItemData)
	if type(tItemDetailedInfo.tPrimary) == "table" then
		eQuality = tonumber(tItemDetailedInfo.tPrimary.eQuality)
	end

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