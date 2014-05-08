-----------------------------------------------------------------------------------------------
-- Client Lua Script for PurchaseConfirmation
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------

--[[
	PurchaseConfirmation by Porten. Please contact me via Curse for suggestions, 
	bug-reports etc.
	
	Props for the inspect and Gemini libraries go to their respective authors. 
	If I'm missing license documents or similar disclaimers, please let me know.
]]

require "Apollo"
require "GameLib"
require "Window"
require "Money"
require "Item"

-- Addon object itself
local PurchaseConfirmation = {} 
	
-- Gemini logging ref stored in chunk for logging shorthand methods
-- TODO: either use Gemini logging "raw", or create a real wrapper class for it.
local log
 
-- Constants for addon name, version etc.
local ADDON_NAME = "PurchaseConfirmation"
local ADDON_VERSION = {1, 0, 0} -- major, minor, bugfix

-- Should be false/"ERROR" for release builds
local DEBUG_MODE = true -- Debug mode = never actually delegate to Vendor (never actually purchase stuff)
local LOG_LEVEL = "ERROR" -- Only log errors, not info/debug/warn

-- Vendor addon references
local VENDOR_ADDON_NAME = "Vendor" -- Used when loading/declaring dependencies to Vendor
local VENDOR_BUY_TAB_NAME = "VendorTab0" -- Used to check if the Vendor used to buy or sell etc

local DETAIL_WINDOW_HEIGHT = 100

local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation", true)


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

-- Standard object instance creation
function PurchaseConfirmation:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

-- Addon registration
function PurchaseConfirmation:Init()
	local bHasConfigureFunction = true
	local strConfigureButtonText = "Purchase Conf."
	local tDependencies = {VENDOR_ADDON_NAME, "Util", "Gemini:Logging-1.2",}
	
	Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 
-- Called when addon loaded, sets up default config and variables, initializes XML form loading
function PurchaseConfirmation:OnLoad()

	-- GeminiLogger options
	local opt = {
		level = LOG_LEVEL,
		pattern = "%d %n %c %l - %m",
		appender = "GeminiConsole"
	}
	log = Apollo.GetPackage("Gemini:Logging-1.2").tPackage:GetLogger(opt)		
	logdebug("OnLoad", "GeminiLogging configured")
	
	--[[
		Supported currencies. Fields:
			eType = currency enum type used by Apollo API
			strName = hardcoded name for the currency, to be referenced in saved config (to disconnect from enum ordering)
			strDescription = description of the currency type -- not used anywhere yet
			wndPanel = handle to settings window panel for this currency, to be populated in OnDocLoaded
	]]
	-- Order of elements must match Settings GUI button layout
	self.seqCurrencies = {																		
		{eType = Money.CodeEnumCurrencyType.Credits,			strName = "Credits",			strDescription = Apollo.GetString("CRB_Credits_Desc")},
		{eType = Money.CodeEnumCurrencyType.Renown,				strName = "Renown",				strDescription = Apollo.GetString("CRB_Renown_Desc")},
		{eType = Money.CodeEnumCurrencyType.Prestige,			strName = "Prestige",			strDescription = Apollo.GetString("CRB_Prestige_Desc")},
		{eType = Money.CodeEnumCurrencyType.CraftingVouchers,	strName = "CraftingVouchers",	strDescription = Apollo.GetString("CRB_Crafting_Voucher_Desc")},
		{eType = Money.CodeEnumCurrencyType.ElderGems,			strName = "ElderGems",			strDescription = Apollo.GetString("CRB_Elder_Gems_Desc")},
	}
	self.currentCurrencyIdx = 1 -- Default, show idx 1 on settings
		
	-- tSettings will be poulated prior to OnLoad, in OnRestore if saved settings exist
	-- If not, set to a clean default
	if self.tSettings == nil then
		self.tSettings = self:DefaultSettings()
	end

	-- Store original Vendor function, Inject own version into Vendor addon
	self.vendorFinalizeBuy = Apollo.GetAddon(VENDOR_ADDON_NAME).FinalizeBuy -- store ref to original function
	Apollo.GetAddon(VENDOR_ADDON_NAME).FinalizeBuy = PurchaseConfirmation.CheckPurchase -- replace Vendors FinalizeBuy with own	
	
	-- Ensures an open confirm dialog is closed when leaving vendor range
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", self)	
	
	-- Slash commands to manually open the settings window
	Apollo.RegisterSlashCommand("purchaseconfirmation", "OnConfigure", self)
	Apollo.RegisterSlashCommand("purconf", "OnConfigure", self)
	
	-- Load the XML file and await callback
	self.xmlDoc = XmlDoc.CreateFromFile("PurchaseConfirmation.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	logexit("OnLoad")
end

-- Called when XML doc is fully loaded/parsed. Create and configure forms.
function PurchaseConfirmation:OnDocLoaded()
	logenter("OnDocLoaded")
		
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
	
	-- Dialog form has details-foldout enabled in Hudson for editability. Collapse it by default
	self:OnDetailsButtonUncheck()

	-- Load settings dialog form
	self.wndSettings = Apollo.LoadForm(self.xmlDoc, "SettingsForm", nil, self)
	Localization.LocalizeSettings(self.wndSettings)
	if self.wndSettings == nil then
		Apollo.AddAddonErrorText(self, "Could not load the SettingsForm window")
		logerror("OnDocLoaded", "wndSettings is nil!")
		return
	end	
	self.wndSettings:Show(false, true)
	
	
	for i,tCurrency in ipairs(self.seqCurrencies) do
		-- Set text on header button (size of seqCurrencies must match actual button layout on SettingsForm!)
		local btn = self.wndSettings:FindChild("CurrencyBtn" .. i)
		btn:SetData(tCurrency)
	
		-- Load "individual currency panel" settings forms, and spawn one for each currency type
		tCurrency.wndPanel = Apollo.LoadForm(self.xmlDoc, "SettingsCurrencyTabForm", self.wndSettings:FindChild("CurrencyTabArea"), self)
		Localization.LocalizeSettingsTab(tCurrency.wndPanel)

		if tCurrency.wndPanel == nil then
			Apollo.AddAddonErrorText(self, "Could not load the CurrencyPanelForm window")
			logerror("OnDocLoaded", "wndPanel is nil!")
			return
		end
		
		if (i == 1) then		
			tCurrency.wndPanel:Show(true, true)
			self.wndSettings:FindChild("CurrencySelectorSection"):SetRadioSelButton("PurchaseConfirmation_CurrencySelection", btn)
		else	
			tCurrency.wndPanel:Show(false, true)
		end
				
		tCurrency.wndPanel:SetName("CurrencyPanel_" .. tCurrency.strName) -- "CurrencyPanel_Credits" etc.
		
		-- Set appropriate currency type on amount fields
		tCurrency.wndPanel:FindChild("FixedSection"):FindChild("Amount"):SetMoneySystem(tCurrency.eType)
		tCurrency.wndPanel:FindChild("PunySection"):FindChild("Amount"):SetMoneySystem(tCurrency.eType)
		logdebug("OnDocLoaded", "Configured currency-settings for '" .. tostring(tCurrency.strName) .. "' (" .. tostring(tCurrency.eType) .. ")")
	end
		
	-- Now that forms are loaded, remove XML doc for gc
	self.xmlDoc = nil
	
	-- If running debug-mode, warn user (should never make it into production)
	if DEBUG_MODE == true then
		Print("Addon '" .. ADDON_NAME .. "' running in debug-mode! Vendor purchases are disabled. Please contact me via Curse if you ever see this, since I probably forgot to disable debug-mode before releasing. For shame :(")
	end
	
	logexit("OnDocLoaded")
end

-- Called on Vendor's "Purchase" buttonclick, hijacked
function PurchaseConfirmation:CheckPurchase(tItemData)
	logenter("CheckPurchase")
	
	-- CheckPurchase is called by Vendor, not PurchaseConfirmation. So "self" targets Vendor.	
	-- Get reference to PurchaseConfirmation addon to use in this Vendor-initialized callstack.	
	local addon = Apollo.GetAddon(ADDON_NAME)
	
	-- Store itemdata in addon for easier debugging. Not used in application code.
	addon.tItemData = tItemData 
	
	--[[ SKIP UNSUPPORTED CASES ]]
	
	-- Only execute any checks during purchases (not sales, repairs or buybacks)
	if not Apollo.GetAddon(VENDOR_ADDON_NAME).wndVendor:FindChild(VENDOR_BUY_TAB_NAME):IsChecked() then
		loginfo("CheckPurchase", "Not a purchase")
		addon:DelegateToVendor(tItemData)
		return
	end
	
	-- No itemdata on purchase, somehow... "this should never happen"
	if not tItemData then
		logwarn("CheckPurchase", "No tItemData")
		addon:DelegateToVendor(tItemData)
		return
	end

	-- Check if current currency is in supported-list
	local tCurrency = addon:GetSupportedCurrencyByEnum(tItemData.tPriceInfo.eCurrencyType1)
	if tCurrency == nil then
		loginfo("CheckPurchase", "Unsupported currentTypes " .. tostring(tItemData.tPriceInfo.eCurrencyType1) .. " and " .. tostring(tItemData.tPriceInfo.eCurrencyType2))
		addon:DelegateToVendor(tItemData)
		return
	end
	
	
	--[[ CHECK THRESHOLDS ]]
	
	-- Extract current purchase price from tItemdata
	local monPrice = addon:GetItemPrice(tItemData)
	
	-- Get local ref to currency-specific settings
	local tSettings = addon.tSettings[tCurrency.strName]
	
	-- Check if price is below puny limit
	if tSettings.tPuny.bEnabled then
		local monPunyLimit = addon:GetPunyLimit(tSettings)
		if monPunyLimit and monPrice < monPunyLimit then
			-- Price is below puny-limit, delegate to Vendor without adding price to history
			loginfo("CheckPurchase", "Puny amount " .. monPrice .. " ignored")
			addon:DelegateToVendor(tItemData)
			return
		end
	end
	
	-- Sequence of thresholds to check
	local tThresholds = {
		fixed = { -- Fixed threshold config
			monThreshold = tSettings.tFixed.monThreshold,
			bEnabled = tSettings.tFixed.bEnabled,
			strType = "Fixed"
		},
		average = { -- Average threshold config
			monThreshold = tSettings.tAverage.monThreshold,
			bEnabled = tSettings.tAverage.bEnabled,
			strType = "Average"
		},
		emptyCoffers = { -- Empty Coffers threshold config
			monThreshold = addon:GetEmptyCoffersThreshold(tSettings, tCurrency),
			bEnabled = tSettings.tEmptyCoffers.bEnabled,
			strType = "EmptyCoffers"
		},
	}
		
	-- Check all thresholds in order, register breach status on threshold table
	local bRequestConfirmation = false
	for _,v in pairs(tThresholds) do
		local bBreached = addon:IsThresholdBreached(v, tItemData, monPrice)
		v.bBreached = bBreached
		
		-- Track if any of them were breached
		if bBreached then
			bRequestConfirmation = true
		end
	end

	-- If confirmation is required, show dialog and DO NOT proceed to confirm purchase	
	if bRequestConfirmation then
		addon:RequestPurchaseConfirmation(tThresholds, tItemData, monPrice)
		return 
	end
	
	-- No thresholds breached, just confirm purchase
	addon:ConfirmPurchase(tItemData)
end

-- Empty coffers threshold is a % of the players total credit
function PurchaseConfirmation:GetEmptyCoffersThreshold(tSettings, tCurrency)
	logenter("GetEmptyCoffersThreshold")
	local monCurrentPlayerCash = GameLib.GetPlayerCurrency(tCurrency.eType):GetAmount()
	local threshold = math.floor(monCurrentPlayerCash * (tSettings.tEmptyCoffers.nPercent/100))
	logdebug("GetEmptyCoffersThreshold", "Empty coffers threshold calculated for " .. tCurrency.strName .. ": " .. tostring(tSettings.tEmptyCoffers.nPercent) .. "% of " .. tostring(monCurrentPlayerCash) .. " = " .. tostring(threshold))
	logexit("GetEmptyCoffersThreshold")
	return threshold
end

-- Checks if a given threshold is enabled & breached
function PurchaseConfirmation:IsThresholdBreached(tThreshold, tItemData, monPrice)
	logenter("IsThresholdBreached")
	
	-- Is threshold enabled?
	if not tThreshold.bEnabled then
		logdebug("IsThresholdBreached", "Threshold type " .. tThreshold.strType .. " disabled, skipping price check")
		return false
	end
	
	-- Is threshold available?
	if not tThreshold.monThreshold or tThreshold.monThreshold < 0 then
		logdebug("IsThresholdBreached", "Threshold type " .. tThreshold.strType .. " has no active amount, skipping price check")
		return false
	end
	
	-- Is threshold breached?
	if monPrice > tThreshold.monThreshold then
		loginfo("IsThresholdBreached", tThreshold.strType .. " threshold, unsafe amount (amount>=threshold): " .. monPrice  .. ">=" .. tThreshold.monThreshold)
		return true
	else
		-- safe amount
		loginfo("IsThresholdBreached", tThreshold.strType .. " threshold, safe amount (amount<threshold): " .. monPrice  .. "<" .. tThreshold.monThreshold)
		return false
	end
end

-- Gets item price from tItemData
function PurchaseConfirmation:GetItemPrice(tItemData)
	logenter("GetItemPrice")
		
	-- NB: "itemData" is a table property on tItemData. Yeah.
	local monPrice = tItemData.itemData:GetBuyPrice():Multiply(tItemData.nStackSize):GetAmount()
	logdebug("GetItemPrice", "Item price extracted: " .. monPrice)
	
	logexit("GetItemPrice")
	return monPrice
end

-- Determines the current punyLimit
function PurchaseConfirmation:GetPunyLimit(tSettings)
	logenter("GetPunyLimit")

	-- No more of that confusing level-scaling stuff
	local monPunyLimit = tSettings.tPuny.monThreshold
	
	logexit("GetPunyLimit")
	return monPunyLimit
end

-- Price for current purchase is unsafe: show warning dialogue
-- Configure all relevant fields & display properties in confirmation dialog before showing
function PurchaseConfirmation:RequestPurchaseConfirmation(tThresholds, tItemData, monPrice)
	logenter("RequestPurchaseConfirmation")
	
	local addon = Apollo.GetAddon(ADDON_NAME)
	local vendor = Apollo.GetAddon(VENDOR_ADDON_NAME)
	local wndDialog = self.wndConfirmDialog
	wndDialog:SetData(tItemData)

	-- Store item details on addon for easier debugging (not used in application code)	
	addon.itemDetailInfo = Item.GetDetailedInfo(tItemData)

		
	--[[ BASIC DIALOG DATA ]]

	-- Basic info
	local wndMainDialogArea = wndDialog:FindChild("DialogArea")
	wndMainDialogArea:FindChild("ItemName"):SetText(tItemData.strName)
	wndMainDialogArea:FindChild("ItemIcon"):SetSprite(tItemData.strIcon)
	wndMainDialogArea:FindChild("ItemPrice"):SetAmount(monPrice, true)
	wndMainDialogArea:FindChild("ItemPrice"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)
	wndMainDialogArea:FindChild("CantUse"):Show(vendor:HelperPrereqFailed(tItemData))

	-- Only show stack size count if we're buying more a >1 size stack
	if (tItemData.nStackSize > 1) then
		wndMainDialogArea:FindChild("StackSize"):SetText(tItemData.nStackSize)
		wndMainDialogArea:FindChild("StackSize"):Show(true, true)
	else
		wndMainDialogArea:FindChild("StackSize"):Show(false, true)
	end
	
	-- Extract item quality
	local eQuality = tonumber(Item.GetDetailedInfo(tItemData).tPrimary.eQuality)

	-- Add pixie quality-color border to the ItemIcon element
	local tPixieOverlay = {
		strSprite = "UI_BK3_ItemQualityWhite",
		loc = {fPoints = {0, 0, 1, 1}, nOffsets = {0, 0, 0, 0}},
		cr = qualityColors[math.max(1, math.min(eQuality, #qualityColors))]
	}	
	wndMainDialogArea:FindChild("ItemIcon"):AddPixie(tPixieOverlay)

	-- Update tooltip to match current item
	local itemArea = wndMainDialogArea:FindChild("ItemArea")
	itemArea:SetData(tItemData)
	vendor:OnVendorListItemGenerateTooltip(itemArea, itemArea) -- Yes, params are switched!

		
	-- [[ DETAILED THRESHOLD AREA ]]
	
	-- Set detailed dialog data. For now, assume Fixed,Average,EmptyCoffers ordering in input
	local wndDetails = self.wndConfirmDialog:FindChild("DetailsArea")
	addon:UpdateConfirmationDetailsLine(tItemData, tThresholds.fixed, wndDetails:FindChild("ThresholdFixed"))
	addon:UpdateConfirmationDetailsLine(tItemData, tThresholds.average, wndDetails:FindChild("ThresholdAverage"))
	addon:UpdateConfirmationDetailsLine(tItemData, tThresholds.emptyCoffers, wndDetails:FindChild("ThresholdEmptyCoffers"))
	
	
	--[[
		Deactivate main vendor window while waiting for input, to avoid
		multiple unconfirmed purchases interfering with eachother.
		Remember to enable Vendor again, for any possible dialog exit-path!
	]]
	Apollo.GetAddon(VENDOR_ADDON_NAME).wndVendor:Enable(false)
	wndDialog:ToFront()
	wndDialog:Show(true)
	
	logexit("RequestPurchaseConfirmation")
end

-- Sets current display values on a single "details line" on the confirmation dialog
function PurchaseConfirmation:UpdateConfirmationDetailsLine(tItemData, tThreshold, wndLine)
	logenter("UpdateConfirmationDetailsLine")
	wndLine:FindChild("Amount"):SetAmount(tThreshold.monThreshold, true)
	wndLine:FindChild("Amount"):SetMoneySystem(tItemData.tPriceInfo.eCurrencyType1)

	if tThreshold.bEnabled then
		wndLine:FindChild("Icon"):Show(tThreshold.bBreached)
		wndLine:FindChild("Label"):SetTextColor("xkcdLightGrey")
		wndLine:FindChild("Amount"):SetTextColor("xkcdLightGrey")
		if tThreshold.bBreached then
			wndLine:SetTooltip(L["Dialog_DetailsTooltip_Breached"])
		else
			wndLine:SetTooltip(L["Dialog_DetailsTooltip_NotBreached"])
		end
	else
		wndLine:FindChild("Icon"):Show(false)
		wndLine:FindChild("Label"):SetTextColor("xkcdMediumGrey")
		wndLine:FindChild("Amount"):SetTextColor("xkcdMediumGrey")
		wndLine:SetTooltip(L"Threshold is disabled")
	end
	logexit("UpdateConfirmationDetailsLine")
end

--[[
function PurchaseConfirmation:ProduceThresholdTooltipFixed(tThreshold, monAmount)
	if tThreshold.bEnabled then
end
]]

-- Called when a purchase is confirmed, either because the "Confirm" was pressed on dialog
-- or because the purchase did not breach any thresholds (and was not puny)
function PurchaseConfirmation:ConfirmPurchase(tItemData)
	logenter("ConfirmPurchase")

	-- CheckPurchase is called both by Vendor and PurchaseConfirmation. 
	-- Get reference to PurchaseConfirmation addon to use in the Vendor-initialized callstacks.
	local addon = Apollo.GetAddon(ADDON_NAME)
	
	local monPrice = addon:GetItemPrice(tItemData)

	-- Get currency settings
	local tCurrency = addon:GetSupportedCurrencyByEnum(tItemData.tPriceInfo.eCurrencyType1)	
	local tSettings = addon.tSettings[tCurrency.strName]
		
	-- Add element to end of list
	if tSettings.tAverage.seqPriceHistory == nil then tSettings.tAverage.seqPriceHistory = {} end
	table.insert(tSettings.tAverage.seqPriceHistory, monPrice)
	
	-- Remove oldest element(s, in case of history size reduction) from start of list if size is overgrown
	while #tSettings.tAverage.seqPriceHistory>tSettings.tAverage.nHistorySize do
		table.remove(tSettings.tAverage.seqPriceHistory, 1)
	end
	
	-- Update the average threshold
	local oldAverage = tSettings.tAverage.monThreshold
	local newAverage = addon:CalculateAverage(tSettings.tAverage.seqPriceHistory)
	
	-- Update the current tAverage.monThreshold, so it is ready for next purchase-test
	newAverage = newAverage * (1+(tSettings.tAverage.nPercent/100)) -- add x% to threshold
	tSettings.tAverage.monThreshold = math.floor(newAverage) -- round off
	
	loginfo("ConfirmPurchase", "Updated Average threshold from " .. tostring(oldAverage) .. " to " .. tostring(tSettings.tAverage.monThreshold))
	
	addon:DelegateToVendor(tItemData)
	logenter("ConfirmPurchase")
end

-- Iterates over all sequence elements, calcs the average
function PurchaseConfirmation:CalculateAverage(seqPriceHistory)
	logenter("CalculateAverage")
	local total = 0
	
	if #seqPriceHistory <= 0 then
		return 0
	end
	
	for i,v in ipairs(seqPriceHistory) do
		total = total + v
	end
	
	local avg = math.floor(total / #seqPriceHistory)
	logdebug("CalculateAverage", "Average=" .. avg)
	
	logexit("CalculateAverage")
	
	return avg
end

-- Called whenver a transaction is approved. Calls the real Vendor:OnBuy.
function PurchaseConfirmation:DelegateToVendor(tItemData)
	logenter("DelegateToVendor")
	
	logdebug("DelegateToVendor", "debugMode=" .. tostring(DEBUG_MODE))
	if DEBUG_MODE == true then
		Print("PurchaseConfirmation: purchase ignored!")
		return
	end
	
	-- Original vendor function stored on PurchaseConfirmation self
	Apollo.GetAddon(ADDON_NAME).vendorFinalizeBuy(Apollo.GetAddon(VENDOR_ADDON_NAME), tItemData)
	logexit("DelegateToVendor")
end


-----------------------------------------------------------------------------------------------
-- ConfirmPurchaseDialogForm button click functions
-----------------------------------------------------------------------------------------------

-- when the Purchase button is clicked
function PurchaseConfirmation:OnConfirmPurchase()
	logenter("OnConfirmPurchase")
	
	-- Hide dialog and register confirmed purchase
	self.wndConfirmDialog:Show(false, true)
	Apollo.GetAddon(VENDOR_ADDON_NAME).wndVendor:Enable(true)
	
	-- Extract item being purchased, and delegate to Vendor
	local tItemData = self.wndConfirmDialog:GetData()
	self:ConfirmPurchase(tItemData)

	logexit("OnConfirmPurchase")
end

-- when the Cancel button is clicked
function PurchaseConfirmation:OnCancelPurchase()
	logenter("OnCancelPurchase")
	self.wndConfirmDialog:Show(false, true)
	Apollo.GetAddon(VENDOR_ADDON_NAME).wndVendor:Enable(true)
	logexit("OnCancelPurchase")
end

-- Locates the supported currency config by its ID (rather than its name). Returns nil if not supported.
function PurchaseConfirmation:GetSupportedCurrencyByEnum(eType)
	for _,tCurrency in ipairs(self.seqCurrencies) do
		if tCurrency.eType == eType then return tCurrency end
	end
	return nil
end

-- When checking the details button, show the details panel
function PurchaseConfirmation:OnDetailsButtonCheck( wndHandler, wndControl, eMouseButton )
	logenter("OnDetailsButtonCheck")
	
	-- Resize the main window frame so that it is possible to drag it around via the hidden details section
	local left, top, right, bottom = self.wndConfirmDialog:GetAnchorOffsets()
	logdebug("OnDetailsButtonCheck", "left="..left..", top="..top..", right="..right..", bottom="..bottom)
	bottom = bottom + DETAIL_WINDOW_HEIGHT
	self.wndConfirmDialog:SetAnchorOffsets(left, top, right, bottom)

	local details = self.wndConfirmDialog:FindChild("DetailsArea")
	details:Show(true, true)
	logexit("OnDetailsButtonCheck")
end

-- When checking the details button, hide the details panel
function PurchaseConfirmation:OnDetailsButtonUncheck( wndHandler, wndControl, eMouseButton )
	logenter("OnDetailsButtonUncheck")

	-- Resize the main window frame so that it is not possible to drag it around via the hidden details section
	local left, top, right, bottom = self.wndConfirmDialog:GetAnchorOffsets()
	logdebug("OnDetailsButtonUncheck", "left="..left..", top="..top..", right="..right..", bottom="..bottom)
	bottom = bottom - DETAIL_WINDOW_HEIGHT
	self.wndConfirmDialog:SetAnchorOffsets(left, top, right, bottom)
	
	local details = self.wndConfirmDialog:FindChild("DetailsArea")
	details:Show(false, true)
	logexit("OnDetailsButtonUncheck")
end

-- Clicking the detail-panel configure button opens the config
function PurchaseConfirmation:OnDetailsOpenSettings()
	-- TODO: pre-select current currency in settings window
	self:OnConfigure()
end


---------------------------------------------------------------------------------------------------
-- Settings save/restore hooks
---------------------------------------------------------------------------------------------------

-- Save addon config per character. Called by engine when performing a controlled game shutdown.
function PurchaseConfirmation:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	-- Add current addon version to settings, for future compatibility/load checks
	self.tSettings.addonVersion = ADDON_VERSION
	
	-- Simply save the entire tSettings structure
	return self.tSettings
end

-- Restore addon config per character. Called by engine when loading UI.
function PurchaseConfirmation:OnRestore(eType, tSavedData)
	logenter("OnRestore")
	
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	--[[
		Perform field-by-field extraction of saved data
		Doing a simple assign of tSettings=tSavedData would cause errors when loading
		settings from previous addon-versions.	
	]]
	self.tSettings = self:RestoreSettings(tSavedData)

	logexit("OnRestore")
end

-----------------------------------------------------------------------------------------------
-- Convenience wrappers of the GeminiLogging methods
-----------------------------------------------------------------------------------------------
function composemessage(strFuncname, strMessage)
	if strFuncname == nil then
		strFuncname = "nil"
	end
	
	if strMessage == nil then
		strMessage = "nil"
	end
	
	return strFuncname .. ": " .. strMessage
end

function logdebug(strFuncname, strMessage)
	log:debug(composemessage(strFuncname, strMessage))
end

function loginfo(strFuncname, strMessage)
	log:info(composemessage(strFuncname, strMessage))
end

function logwarn(strFuncname, strMessage)
	log:warn(composemessage(strFuncname, strMessage))
end

function logerror(strFuncname, strMessage)
	log:error(composemessage(strFuncname, strMessage))
end

-- Enter and exit method debug traces. Figure out if some Lua-style AOP is possible instead...
function logenter(strFuncname)
	logdebug(strFuncname, "Enter method")
end

-- logexit is only used during "regular" fuction exits, 
-- not null-guard exits and similar. In those cases, look for warn logs instead.
function logexit(strFuncname)
	logdebug(strFuncname, "Exit method")
end

-----------------------------------------------------------------------------------------------
-- PurchaseConfirmation Instance
-----------------------------------------------------------------------------------------------
local PurchaseConfirmationInst = PurchaseConfirmation:new()
PurchaseConfirmationInst:Init()


