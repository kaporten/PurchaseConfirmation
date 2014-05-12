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
local DEBUG_MODE = false -- Debug mode = never actually delegate to Vendor (never actually purchase stuff)
local LOG_LEVEL = "INFO" -- Only log errors, not info/debug/warn

local DETAIL_WINDOW_HEIGHT = 100

local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation", true)

-- Names of addon-hook modules to load 
local moduleNames = {
	"PurchaseConfirmation:Modules:VendorPurchase"
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
	log:debug("PurchaseConfirmation.OnLoad: GeminiLogging configured")

	-- Store ref to log in addon, so that modules can access it via GetAddon
	self.log = log
	
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
	
	-- Slash commands to manually open the settings window
	Apollo.RegisterSlashCommand("purchaseconfirmation", "OnConfigure", self)
	Apollo.RegisterSlashCommand("purconf", "OnConfigure", self)
	
	-- Load the XML file and await callback
	self.xmlDoc = XmlDoc.CreateFromFile("PurchaseConfirmation.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)	
end

-- Called when XML doc is fully loaded/parsed. Create and configure forms.
function PurchaseConfirmation:OnDocLoaded()	
	local Localization = Apollo.GetPackage("PurchaseConfirmation:Localization").tPackage
		
	-- Check that XML document is properly loaded
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "XML document was not loaded")
		log:error("PurchaseConfirmation.OnDocLoaded: XML document was not loaded")
		return
	end
		
	-- Load confirmation dialog form 
	self.wndDialog = Apollo.LoadForm(self.xmlDoc, "DialogForm", nil, self)
	Localization.LocalizeDialog(self.wndDialog)
	if self.wndDialog == nil then
		Apollo.AddAddonErrorText(self, "Could not load the ConfirmDialog window")
		log:error("PurchaseConfirmation.OnDocLoaded: wndDialog is nil!")
		return
	end
	self.wndDialog:Show(false, true)	
	
	-- Dialog form has details-foldout enabled in Hudson for editability. Collapse it by default
	self:OnDetailsButtonUncheck()

	-- Load settings dialog form
	self.wndSettings = Apollo.LoadForm(self.xmlDoc, "SettingsForm", nil, self)
	Localization.LocalizeSettings(self.wndSettings)
	if self.wndSettings == nil then
		Apollo.AddAddonErrorText(self, "Could not load the SettingsForm window")
		log:error("PurchaseConfirmation.OnDocLoaded: wndSettings is nil!")
		return
	end	
	self.wndSettings:Show(false, true)
	
	
	for i,tCurrency in ipairs(self.seqCurrencies) do
		-- Set text on header button (size of seqCurrencies must match actual button layout on SettingsForm!)
		local btn = self.wndSettings:FindChild("CurrencyBtn" .. i)
		btn:SetData(tCurrency)
		btn:SetTooltip(tCurrency.strDescription)
	
		-- Load "individual currency panel" settings forms, and spawn one for each currency type
		tCurrency.wndPanel = Apollo.LoadForm(self.xmlDoc, "SettingsCurrencyTabForm", self.wndSettings:FindChild("CurrencyTabArea"), self)
		Localization.LocalizeSettingsTab(tCurrency.wndPanel)

		if tCurrency.wndPanel == nil then
			Apollo.AddAddonErrorText(self, "Could not load the CurrencyPanelForm window")
			log:error("PurchaseConfirmation.OnDocLoaded: wndPanel is nil!")
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
		log:debug("PurchaseConfirmation.OnDocLoaded: Configured currency-settings for '" .. tostring(tCurrency.strName) .. "' (" .. tostring(tCurrency.eType) .. ")")
	end
		
	-- Now that forms are loaded, remove XML doc for gc
	self.xmlDoc = nil
	
	
	-- Load modules
	self.modules = {}
	for k,v in ipairs(moduleNames) do
		self.modules[v] = Apollo.GetPackage(v).tPackage:new():Init()
	end
	
	-- If running debug-mode, warn user (should never make it into production)
	if DEBUG_MODE == true then
		Print("Addon '" .. ADDON_NAME .. "' running in debug-mode! Vendor purchases are disabled. Please contact me via Curse if you ever see this, since I probably forgot to disable debug-mode before releasing. For shame :(")
	end
end

-- Empty coffers threshold is a % of the players total credit
function PurchaseConfirmation:GetEmptyCoffersThreshold(tSettings, tCurrency)
	local monCurrentPlayerCash = GameLib.GetPlayerCurrency(tCurrency.eType):GetAmount()
	local threshold = math.floor(monCurrentPlayerCash * (tSettings.tEmptyCoffers.nPercent/100))
	log:debug("PurchaseConfirmation.GetEmptyCoffersThreshold: Empty coffers threshold calculated for " .. tCurrency.strName .. ": " .. tostring(tSettings.tEmptyCoffers.nPercent) .. "% of " .. tostring(monCurrentPlayerCash) .. " = " .. tostring(threshold))	
	return threshold
end

-- Checks if a given threshold is enabled & breached
function PurchaseConfirmation:IsThresholdBreached(tThreshold, monPrice)
	-- Is threshold enabled?
	if not tThreshold.bEnabled then
		log:debug("PurchaseConfirmation.IsThresholdBreached: Threshold type " .. tThreshold.strType .. " disabled, skipping price check")
		return false
	end
	
	-- Is threshold available?
	if not tThreshold.monThreshold or tThreshold.monThreshold < 0 then
		log:debug("PurchaseConfirmation.IsThresholdBreached: Threshold type " .. tThreshold.strType .. " has no active amount, skipping price check")
		return false
	end
	
	-- Is threshold breached?
	if monPrice > tThreshold.monThreshold then
		log:info("PurchaseConfirmation.IsThresholdBreached: " .. tThreshold.strType .. " threshold, unsafe amount (amount>=threshold): " .. monPrice  .. ">=" .. tThreshold.monThreshold)
		return true
	else
		-- safe amount
		log:debug("PurchaseConfirmation.IsThresholdBreached: " .. tThreshold.strType .. " threshold, safe amount (amount<threshold): " .. monPrice  .. "<" .. tThreshold.monThreshold)
		return false
	end
end


--- Called by addon-hook when a purchase is taking place.
function PurchaseConfirmation:PriceCheck(tPurchaseData)
	log:debug("PurchaseConfirmation.PriceCheck: enter method")

	local addon = Apollo.GetAddon("PurchaseConfirmation")
	
	-- Get local ref to currency-specific threshold settings
	local tSettings = addon.tSettings[tPurchaseData.tCurrency.strName]
	local tCurrency = tPurchaseData.tCurrency
	local monPrice = tPurchaseData.monPrice
	
	-- Check if price is below puny limit
	if tSettings.tPuny.bEnabled then
		local monPunyLimit = tSettings.tPuny.monThreshold
		if monPunyLimit and monPrice < monPunyLimit then
			-- Price is below puny-limit, complete purchase (without adding price to history etc)
			log:info("Vendor.FinalizeBuy: Puny amount " .. monPrice .. " ignored")
			self:CompletePurchase(tPurchaseData.tCallbackData)
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
		v.bBreached = addon:IsThresholdBreached(v, monPrice)		
		
		-- Track if any of them were breached
		if v.bBreached then
			bRequestConfirmation = true
		end
	end

	-- If confirmation is required, show dialog and DO NOT proceed to confirm purchase	
	if bRequestConfirmation then
		addon:RequestConfirmation(tPurchaseData, tThresholds)
		return 
	end
	
	-- No thresholds breached, just update price history and complete purchase
	addon:UpdateAveragePriceHistory(tSettings, monPrice)
	addon:CompletePurchase(tPurchaseData.tCallbackData)
end


--- Price for current purchase is unsafe: show confirmation dialogue
-- Configure all relevant fields & display properties in confirmation dialog before showing
-- @param tThresholds Detailed data on which thresholds were breached
-- @param tCallbackData Addonhook-specific callback data
function PurchaseConfirmation:RequestConfirmation(tPurchaseData, tThresholds)

	local addon = Apollo.GetAddon("PurchaseConfirmation")

	local tCallbackData = tPurchaseData.tCallbackData
	local monPrice = tPurchaseData.monPrice
	local tCurrency = tPurchaseData.tCurrency
	
	-- Prepare central details area	
	local wndDetails = tCallbackData.module:UpdateDialogDetails(monPrice, tCallbackData)
	
	-- Hide all detail children
	local children = addon.wndDialog:FindChild("DialogArea"):FindChild("VendorSpecificArea"):GetChildren()
	for _,v in pairs(children) do
		-- ... except vendor-specific info for the module which caused this price check
		v:Show(false, true)
	end
	wndDetails:Show(true, true)
	
	-- Prepare foldout area	
	local wndFoldout = self.wndDialog:FindChild("FoldoutArea")
	addon:UpdateConfirmationDetailsLine(wndFoldout:FindChild("ThresholdFixed"), 		tThresholds.fixed, 			tCurrency)
	addon:UpdateConfirmationDetailsLine(wndFoldout:FindChild("ThresholdAverage"),		tThresholds.average, 		tCurrency)
	addon:UpdateConfirmationDetailsLine(wndFoldout:FindChild("ThresholdEmptyCoffers"), 	tThresholds.emptyCoffers, 	tCurrency)
		
	-- Set full purchase on dialog window
	addon.wndDialog:SetData(tPurchaseData)
	
	-- Show dialog, await button click
	addon.wndDialog:ToFront()
	addon.wndDialog:Show(true)
end


--- Called when a purchase should be fully completed against "bakcend" addon.
-- @param tCallbackData hook/data structure supplied by addon-wrapper which initiated the purchase
function PurchaseConfirmation:CompletePurchase(tCallbackData)
	log:debug("PurchaseConfirmation.CompletePurchase: enter method")	
	
	-- Delegate to supplied hook method, unless debug mode is on
	if DEBUG_MODE == true then
		Print("PurchaseConfirmation: purchase ignored!")
	else
		tCallbackData.hook(tCallbackData.hookedAddon, tCallbackData.hookParams)
	end	
end


function PurchaseConfirmation:UpdateAveragePriceHistory(tSettings, monPrice)
	local addon = Apollo.GetAddon("PurchaseConfirmation")
	
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

	log:info("PurchaseConfirmation.UpdateAveragePriceHistory: Updated Average threshold from " .. tostring(oldAverage) .. " to " .. tostring(tSettings.tAverage.monThreshold))
end

-- Sets current display values on a single "details line" on the confirmation dialog
function PurchaseConfirmation:UpdateConfirmationDetailsLine(wndLine, tThreshold, tCurrency)
	wndLine:FindChild("Amount"):SetAmount(tThreshold.monThreshold, true)
	wndLine:FindChild("Amount"):SetMoneySystem(tCurrency.eType)

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
		wndLine:SetTooltip(L["Threshold is disabled"])
	end
end

--- Iterates over all sequence elements, calcs the average value
-- @param seqPriceHistory Sequence of numbers (amounts)
function PurchaseConfirmation:CalculateAverage(seqPriceHistory)
	local total = 0
	
	if #seqPriceHistory <= 0 then
		return 0
	end
	
	for i,v in ipairs(seqPriceHistory) do
		total = total + v
	end
	
	local avg = math.floor(total / #seqPriceHistory)
	log:debug("PurchaseConfirmation.CalculateAverage: Average=" .. avg)
		
	return avg
end


-----------------------------------------------------------------------------------------------
-- ConfirmPurchaseDialogForm button click functions
-----------------------------------------------------------------------------------------------

-- when the Purchase button is clicked
function PurchaseConfirmation:OnConfirmPurchase()	
	-- Hide dialog and register confirmed purchase
	self.wndDialog:Show(false, true)
	
	-- Extract item being purchased, and delegate to Vendor
	local tPurchaseData = self.wndDialog:GetData()
	local tSettings = self.tSettings[tPurchaseData.tCurrency.strName]
	
	-- Purchase is confirmed, update history and complete against backend module
	self:UpdateAveragePriceHistory(tSettings, tPurchaseData.monPrice)
	self:CompletePurchase(tPurchaseData.tCallbackData)
end

-- when the Cancel button is clicked
function PurchaseConfirmation:OnCancelPurchase()
	self.wndDialog:Show(false, true)
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
	-- Resize the main window frame so that it is possible to drag it around via the hidden details section
	local left, top, right, bottom = self.wndDialog:GetAnchorOffsets()
	bottom = bottom + DETAIL_WINDOW_HEIGHT
	self.wndDialog:SetAnchorOffsets(left, top, right, bottom)

	local foldout = self.wndDialog:FindChild("FoldoutArea")
	foldout:Show(true, true)
end

-- When checking the details button, hide the details panel
function PurchaseConfirmation:OnDetailsButtonUncheck( wndHandler, wndControl, eMouseButton )
	-- Resize the main window frame so that it is not possible to drag it around via the hidden details section
	local left, top, right, bottom = self.wndDialog:GetAnchorOffsets()
	bottom = bottom - DETAIL_WINDOW_HEIGHT
	self.wndDialog:SetAnchorOffsets(left, top, right, bottom)
	
	local foldout = self.wndDialog:FindChild("FoldoutArea")
	foldout:Show(false, true)
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
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	--[[
		Perform field-by-field extraction of saved data
		Doing a simple assign of tSettings=tSavedData would cause errors when loading
		settings from previous addon-versions.	
	]]
	self.tSettings = self:RestoreSettings(tSavedData)
end

-----------------------------------------------------------------------------------------------
-- PurchaseConfirmation Instance
-----------------------------------------------------------------------------------------------
local PurchaseConfirmationInst = PurchaseConfirmation:new()
PurchaseConfirmationInst:Init()


