require "Apollo"
require "Window"

--[[
	Provides hook-in functionality for the ViragsMultibuyer addon.
]]

-- GeminiLocale
local locale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")
local H = Apollo.GetPackage("Gemini:Hook-1.0").tPackage

-- Register module as package
local ViragsMultibuyerPurchase = {
	MODULE_ID = "PurchaseConfirmation:ViragsMultibuyerPurchase",
	strTitle = locale["Module_ViragsMultibuyerPurchase_Title"],
	strDescription = locale["Module_ViragsMultibuyerPurchase_Description"],
}
Apollo.RegisterPackage(ViragsMultibuyerPurchase, ViragsMultibuyerPurchase.MODULE_ID, 1, {"ViragsMultibuyer"})

-- "glocals" set during Init
local addon, module, multibuyer, log

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
function ViragsMultibuyerPurchase:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

--- Registers this addon wrapper.
-- Called by PurchaseConfirmation during initialization.
function ViragsMultibuyerPurchase:Init()
	addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	module = self -- Current module
	log = addon.log
	multibuyer = Apollo.GetAddon("ViragsMultibuyer")	

	-- Dependency check on required addon
	if multibuyer == nil then
		self.strFailureMessage = string.format(locale["Module_Failure_Addon_Missing"], "ViragsMultibuyer")
		error(self.strFailureMessage)
	end	

	-- Dependency check on required addon (Vendor also required for Virags)
	if Apollo.GetAddon("Vendor") == nil then
		self.strFailureMessage = string.format(locale["Module_Failure_Addon_Missing"], "Vendor")
		error(self.strFailureMessage)
	end	

	
	-- Ensures an open confirm dialog is closed when leaving vendor range
	-- NB: register the event so that it is fired on main addon, not this wrapper
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", addon)
	
	return self
end


function ViragsMultibuyerPurchase:Activate()
	-- Hook into Vendor (if not already done)
	if H:IsHooked(multibuyer, "FinalizeBuy") then
		log:debug("Module %s already active, ignoring Activate request", module.MODULE_ID)
	else
		log:info("Activating module: %s", module.MODULE_ID)		
		H:RawHook(multibuyer, "FinalizeBuy", ViragsMultibuyerPurchase.Intercept) -- Actual buy-intercept
	end
end

function ViragsMultibuyerPurchase:Deactivate()
	if H:IsHooked(multibuyer, "FinalizeBuy") then
		log:info("Deactivating module: %s", module.MODULE_ID)
		H:Unhook(multibuyer, "FinalizeBuy")		
	else
		log:debug("Module %s not active, ignoring Deactivate request", module.MODULE_ID)
	end
end



--- Main hook interceptor function.
-- Called on Vendors's "Purchase" buttonclick / item rightclick.
-- @tItemData item being "operated on" (purchase, sold, buyback) on the Vendor
function ViragsMultibuyerPurchase:Intercept(tItemData, bConfirmPurchase)
	log:debug("Intercept: enter method")
		
	-- Store purchase details on module for easier debugging
	if addon.DEBUG_MODE == true then
		module.tItemData = tItemData
	end
	
	-- Prepare addon-specific callback data, used if/when the user confirms a purchase
	local tCallbackData = {
		module = module,
		hook = H.hooks[multibuyer]["FinalizeBuy"],
		hookParams = {
			tItemData, 
			bConfirmPurchase
		},
		bHookParamsUnpack = true,
		hookedAddon = multibuyer
	}

	--[[
		Skip unsupported operations by calling addon:CompletePurchase.
		(not addon:ConfirmPurchase). CompletePurchase essentially just
		calls the supplied hook function without futher interferance with
		the purchase itself.
	]]
		
	-- Only check thresholds if this is a purchase (not sales, repairs or buybacks)
	if not Apollo.GetAddon("Vendor").wndVendor:FindChild("VendorTab0"):IsChecked() then
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
	
	-- ViragsMultibuyer has a 250 stacksize max
	local nCount = multibuyer:GetCount()
	if nCount > 250 then 
		nCount = 250
	end
	log:debug("ViragsMultibuyer count determined: %d", nCount)
	tCallbackData.nCount = nCount
			
	-- ViragsMultibuyer logic for when to show internal confirm dialog
	if not bConfirmPurchase and not (Apollo.IsShiftKeyDown() and nCount == 1) then
		log:info("Intercept: ViragsMultibuyer presenting own dialog")
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
		monPrice = module:GetPrice(tItemData, nCount),
	}
		
	-- Request pricecheck
	addon:PriceCheck(tPurchaseData)
end

--- Extracts item price from tItemData
-- @param tItemData Current purchase item data, as supplied by the Vendor addon
function ViragsMultibuyerPurchase:GetPrice(tItemData, nCount)
	log:debug("GetPrice: enter method")
	local monPrice = 0
	
	if type(tItemData.itemData) == "userdata" then
		-- Regular items have a nested "itemData" object with functions for getting price etc.
		-- If that exist, use it to extract price details since that is how the Vendor module does it
		monPrice = tItemData.itemData:GetBuyPrice():Multiply(nCount):GetAmount()
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
function ViragsMultibuyerPurchase:GetDialogDetails(tPurchaseData)
	log:debug("GetDialogWindowDetails: enter method")
	
	local tCallbackData = tPurchaseData.tCallbackData
	local monPrice = tPurchaseData.monPrice	
	
	local tItemData = tCallbackData.hookParams[1]
	local wnd = addon.tDetailForms[addon.eDetailForms.StandardItem]
		
	-- Set basic info on details area
	wnd:FindChild("ItemName"):SetText(tItemData.strName)
	wnd:FindChild("ItemIcon"):SetSprite(tItemData.strIcon)
	wnd:FindChild("ItemPrice"):SetAmount(monPrice, true)
	wnd:FindChild("ItemPrice"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)
	wnd:FindChild("CantUse"):Show(Apollo.GetAddon("Vendor"):HelperPrereqFailed(tItemData))
	
	-- Only show stack size count if we're buying more a >1 size stack
	if (tCallbackData.nCount > 1) then
		wnd:FindChild("StackSize"):SetText(tCallbackData.nCount)
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
	Apollo.GetAddon("Vendor"):OnVendorListItemGenerateTooltip(wnd, wnd)

	return wnd
end
