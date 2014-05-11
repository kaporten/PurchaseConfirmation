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
local ADDON_VERSION = {2, 0, 0} -- major, minor, bugfix

-- Should be false/"ERROR" for release builds
local DEBUG_MODE = true -- Debug mode = never actually delegate to Vendor (never actually purchase stuff)
local LOG_LEVEL = "ERROR" -- Only log errors, not info/debug/warn

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
	local tDependencies = {VENDOR_ADDON_NAME, "Gemini:Logging-1.2",}
	
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
	self.log = log
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
	
	-- Hook into supported Addons
	local vendorHook = Apollo.GetPackage("PurchaseConfirmation:Addons:Vendor").tPackage:Register()

	
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
	
	local Localization = Apollo.GetPackage("PurchaseConfirmation:Localization").tPackage
		
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
function PurchaseConfirmation:IsThresholdBreached(tThreshold, monPrice)
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

-- Determines the current punyLimit
function PurchaseConfirmation:GetPunyLimit(tSettings)
	logenter("GetPunyLimit")

	-- No more of that confusing level-scaling stuff
	local monPunyLimit = tSettings.tPuny.monThreshold
	
	logexit("GetPunyLimit")
	return monPunyLimit
end

--- Price for current purchase is unsafe: show confirmation dialogue
-- Configure all relevant fields & display properties in confirmation dialog before showing
-- @param tThresholds Detailed data on which thresholds were breached
-- @param tCallbackData Addonhook-specific callback data
function PurchaseConfirmation:RequestConfirmation(tThresholds, tCallbackData)
	self.log:debug("PurchaseConfirmation.RequestConfirmation: enter method")
	
	wndConfirmDialog:SetData(tCallbackData)

		
	--[[
		The dialog contains an area called "VendorSpecificArea" which will
		contain detailed info about the current purchase to confirm.
		The contents of this area is to be provided by the addonhook which
		initiated the purchase confirmation BASIC DIALOG DATA ]]

	-- Basic info
	-- Hide all vendor-specific info on dialog
	local children = wndMainDialogArea:FindChild("DialogArea"):FindChild("VendorSpecificArea"):GetChildren()
	for _,v in pairs(children) do
		v:Show(false, true)
	end
	
	-- ... except vendor-specific info for the hooked addon which produced this
	local wndVendorSpecificArea = tCallbackData.fUpdateDetailsWindow(tCallbackData.data)
	wndVendorSpecificArea:Show(true, true)
	
	
	local wndMainDialogArea = wndDialog:FindChild("DialogArea")
	

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
		Apollo.GetAddon(VENDOR_ADDON_NAME).wndVendor:Enable(false)
		]]

	wndDialog:ToFront()
	wndDialog:Show(true)

end

--- Called by addon-hook when a purchase is taking place.
-- Checks all thresholds:
--  1. If puny limit is enabled/breached, the purchase will be completed without further action.
--  2. If any threshold is enabled/breached, the confirmation dialog will be shown
-- @param monPrice Price of current purchase
-- @param tCallbackData Addonhook-specific callback data
function PurchaseConfirmation:PriceCheck(monPrice, tCallbackData)
	self.log:debug("PurchaseConfirmation.PriceCheck: enter method")

	-- Get local ref to currency-specific threshold settings
	local tSettings = self.tSettings[tCurrency.strName]
	
	-- Check if price is below puny limit
	if tSettings.tPuny.bEnabled then
		local monPunyLimit = self:GetPunyLimit(tSettings)
		if monPunyLimit and monPrice < monPunyLimit then
			-- Price is below puny-limit, complete purchase (without adding price to history etc)
			self.log:info("Vendor.FinalizeBuy: Puny amount " .. monPrice .. " ignored")
			self:CompletePurchase(tCallbackData)
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
			monThreshold = self:GetEmptyCoffersThreshold(tSettings, tCurrency),
			bEnabled = tSettings.tEmptyCoffers.bEnabled,
			strType = "EmptyCoffers"
		},
	}
		
	-- Check all thresholds in order, register breach status on threshold table
	local bRequestConfirmation = false
	for _,v in pairs(tThresholds) do
		v.bBreached = self:IsThresholdBreached(v, monPrice)		
		
		-- Track if any of them were breached
		if v.bBreached then
			bRequestConfirmation = true
		end
	end

	-- If confirmation is required, show dialog and DO NOT proceed to confirm purchase	
	if bRequestConfirmation then
		self:RequestConfirmation(tThresholds, monPrice, tCallbackData)
		return 
	end
	
	-- No thresholds breached, just update price history and complete purchase
	self:UpdateAveragePriceHistory(tSettings, monPrice)
	self:CompletePurchase(tCallbackData)
end


--- Called when a purchase should be fully completed against "bakcend" addon.
-- @param tCallbackData hook/data structure supplied by addon-wrapper which initiated the purchase
function PurchaseConfirmation:CompletePurchase(tCallbackData)
	self.log:debug("PurchaseConfirmation.CompletePurchase: enter method")	
	
	-- Delegate to supplied hook method, unless debug mode is on
	if DEBUG_MODE == true then
		Print("PurchaseConfirmation: purchase ignored!")
	else
		tCallbackData.hook(tCallbackData.data)	
	end	
end


function PurchaseConfirmation:UpdateAveragePriceHistory(tSettings, monPrice)
	-- Add element to end of price history list
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




-----------------------------------------------------------------------------------------------
-- ConfirmPurchaseDialogForm button click functions
-----------------------------------------------------------------------------------------------

-- when the Purchase button is clicked
function PurchaseConfirmation:OnConfirmPurchase()
	logenter("OnConfirmPurchase")
	
	-- Hide dialog and register confirmed purchase
	self.wndConfirmDialog:Show(false, true)
	--Apollo.GetAddon(VENDOR_ADDON_NAME).wndVendor:Enable(true)
	
	-- Extract item being purchased, and delegate to Vendor
	local tItemData = self.wndConfirmDialog:GetData()
	self:ConfirmPurchase(tItemData)

	logexit("OnConfirmPurchase")
end

-- when the Cancel button is clicked
function PurchaseConfirmation:OnCancelPurchase()
	logenter("OnCancelPurchase")
	self.wndConfirmDialog:Show(false, true)
	--Apollo.GetAddon(VENDOR_ADDON_NAME).wndVendor:Enable(true)
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


