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

-- Addon object itself
local PurchaseConfirmation = {} 

--[[ 
	TODO: Move settings and window/function handles inside PurchaseConfirmation scope.
	Only constants should be outside of instance-scope.
	
	This is not entirely trivial, since the CheckPurchase function *and all functions 
	down the call stack* are injected into the Vendor addon. This leaves them unable
	to reference self via the : invocation, since the self there will be Vendor, not
	PurchaseConfirmation. 
	Solutions: 
	Have the methods lookup Apollo.GetAddon("PurchaseConfirmation") and access the 
	variables that way? Most likely the "injection entry point" (CheckPurchase) could
	just do a one-time lookup of tSettings and window-handles, and then pass refs to
	called functions. 
	Consider moving injected code into a seperate file / scope to clarify that they are
	NOT internal workings of PurchaseConfirmation scope.
]]
	
-- Settings and window handles
local tSettings = nil
local wndConfirmDialog = nil
local wndSettings = nil

-- Handle to "real" vendor method
local vendorFinalizeBuy = nil

-- Gemini logging
local log = nil
 
-- Constants for addon name, version etc.
local ADDON_NAME = "PurchaseConfirmation"
local ADDON_VERSION = "0.8"
local DEBUG_MODE = false -- Debug mode = never actually delegate to Vendor (never actually purchase stuff)

local VENDOR_ADDON_NAME = "Vendor" -- Used when loading/declaring dependencies to Vendor
local VENDOR_ADDON
local kstrTabBuy = "VendorTab0"

--[[
	Supported currencies
		eType = currency enum type used by Apollo API
		strName = hardcoded name for the currency, to be referenced in saved config
		strTitle = display-title to be used on the left-right settings selection buttons
		strDescription = description of the currency type -- not used anywhere yet
]]
local seqCurrencyTypes = {
	{eType = Money.CodeEnumCurrencyType.Credits, 			strName = "Credits",			strTitle = Apollo.GetString("CRB_Credits"), 			strDescription = Apollo.GetString("CRB_Credits_Desc")},
	{eType = Money.CodeEnumCurrencyType.Renown, 			strName = "Renown", 			strTitle = Apollo.GetString("CRB_Renown"), 			strDescription = Apollo.GetString("CRB_Renown_Desc")},
	{eType = Money.CodeEnumCurrencyType.ElderGems, 			strName = "ElderGems",			strTitle = Apollo.GetString("CRB_Elder_Gems"), 		strDescription = Apollo.GetString("CRB_Elder_Gems_Desc")},
	{eType = Money.CodeEnumCurrencyType.Prestige, 			strName = "Prestige",			strTitle = Apollo.GetString("CRB_Prestige"), 			strDescription = Apollo.GetString("CRB_Prestige_Desc")},
	{eType = Money.CodeEnumCurrencyType.CraftingVouchers, 	strName = "CraftingVouchers",	strTitle = Apollo.GetString("CRB_Crafting_Vouchers"), 	strDescription = Apollo.GetString("CRB_Crafting_Voucher_Desc")}
}

-- Standard object instance creation
function PurchaseConfirmation:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

-- Addon registration
-- Describes configuration button options and dependencies (Vendor) for load-ordering I assume.
function PurchaseConfirmation:Init()
	local bHasConfigureFunction = true
	local strConfigureButtonText = "Purchase Conf."
	local tDependencies = {VENDOR_ADDON_NAME, "Gemini:Logging-1.2"}
	
	Apollo.RegisterAddon(self, bHasConfigureFunction, strConfigureButtonText, tDependencies)
end
 
-- OnLoad called when addon is allowed to load. 
-- Should initialize XML load/parse and nothing else.
function PurchaseConfirmation:OnLoad()
	
	-- GeminiLogger options
	local opt = {
			level = "INFO",
			pattern = "%d %n %c %l - %m",
			appender = "GeminiConsole"
		}
	log = Apollo.GetPackage("Gemini:Logging-1.2").tPackage:GetLogger(opt)

	-- load our form file
	self.xmlDoc = XmlDoc.CreateFromFile("PurchaseConfirmation.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	Apollo.RegisterEventHandler("CloseVendorWindow", "OnCancelPurchase", self)
	
	logexit("OnLoad")
end

-- Called when XML doc is fully loaded/parsed. Initialize all addon variables.
function PurchaseConfirmation:OnDocLoaded()
	logenter("OnDocLoaded")

	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "XML document was not loaded")
		return
	end
	
	
	--[[ BUILD FORMS ]]
	
	wndConfirmDialog = Apollo.LoadForm(self.xmlDoc, "ConfirmPurchaseDialogForm", nil, self)
	if wndConfirmDialog == nil then
		Apollo.AddAddonErrorText(self, "Could not load the ConfirmDialog window for some reason")
		logerror("OnDocLoaded", "wndConfirmDialog is nil!")
		return
	end
	wndConfirmDialog:Show(false, true)	

	wndSettings = Apollo.LoadForm(self.xmlDoc, "SettingsForm", nil, self)
	if wndSettings == nil then
		Apollo.AddAddonErrorText(self, "Could not load the SettingsForm window for some reason")
		logerror("OnDocLoaded", "wndSettings is nil!")
		return
	end	
	wndSettings:Show(false, true)
	wndSettings:FindChild("CurrencySelector"):SetData(seqCurrencyTypes[1])
	wndSettings:FindChild("CurrencySelector"):FindChild("Name"):SetText(wndSettings:FindChild("CurrencySelector"):GetData().strTitle) -- NB: Title, not Name. Assuming Title is localized.
	
	for _,v in seqCurrencyTypes do
		local wndCurrencyControls = Apollo.LoadForm(self.xmlDoc, "CurrencyControlsForm", wndSettings:FindChild("CurrencyControlsArea"), self)
		if wndCurrencyControls == nil then
			Apollo.AddAddonErrorText(self, "Could not load the CurrencyControlsForm window for some reason")
			logerror("OnDocLoaded", "wndCurrencyControls is nil!")
			return
		end
		
		wndCurrencyControls:Show(false, true)		
		wndCurrencyControls:SetName("CurrencyControl_" .. v.strName) -- "CurrencyControl_Credits" etc
		
		-- Set appropriate currency on amount fields
		wndCurrencyControls:FindChild("FixedSection"):FindChild("Amount"):SetMoneySystem(v.eType)
		wndCurrencyControls:FindChild("PunySection"):FindChild("Amount"):SetMoneySystem(v.eType)
	end
	
		
	-- Now that forms are loaded, remove XML doc for gc
	self.xmlDoc = nil
	
	
	--[[ SETTINGS ]]
	
	-- tSettings will be poulated prior to OnLoad, in OnRestore if saved settings exist
	if tSettings == nil then
		tSettings = PurchaseConfirmation:DefaultSettings()
	end
	
	
	--[[ ADDON REGISTRATION AND FUNCTION INJECTION ]]
	
	-- Slash command opens settings window
	Apollo.RegisterSlashCommand("purchaseconfirmation", "OnConfigure", self)
	Apollo.RegisterSlashCommand("purconf", "OnConfigure", self)

	-- Store reference to Vendor in global
	VENDOR_ADDON = Apollo.GetAddon(VENDOR_ADDON_NAME)
	
	-- Inject own OnBuy function into Vendor addon
	vendorFinalizeBuy = VENDOR_ADDON.FinalizeBuy -- store ref to original function
	VENDOR_ADDON.FinalizeBuy = PurchaseConfirmation.CheckPurchase -- replace Vendors FinalizeBuy with own
	
	logexit("OnDocLoaded")
end


-----------------------------------------------------------------------------------------------
-- PurchaseConfirmation Functions
-----------------------------------------------------------------------------------------------

-- Called on Vendor's "Purchase" buttonclick, hijacked
function PurchaseConfirmation:CheckPurchase(tItemData)
	logenter("CheckPurchase")
	
	-- Only execute any checks during purchases (not sales, repairs or buybacks)
	if not VENDOR_ADDON.wndVendor:FindChild(kstrTabBuy):IsChecked() then
		loginfo("CheckPurchase", "Not a purchase")
		PurchaseConfirmation:DelegateToVendor(tItemData)
		return
	end
	
	-- No itemdata, somehow... "this should never happen"
	if not tItemData then
		logwarn("CheckPurchase", "No tItemData")
		PurchaseConfirmation:DelegateToVendor(tItemData)
		return
	end

	-- Currently, only Credit purchases are supported.
	if tItemData.tPriceInfo.eCurrencyType1 ~= 1 or tItemData.tPriceInfo.eCurrencyType2 ~= 1 then
		loginfo("CheckPurchase", "Unsupported currenttypes " .. tostring(tItemData.tPriceInfo.eCurrencyType1) .. " and " .. tostring(tItemData.tPriceInfo.eCurrencyType2))
		PurchaseConfirmation:DelegateToVendor(tItemData)
		return
	end
	
	-- Extract current purchase price from tItemdata
	local monPrice = PurchaseConfirmation:GetItemPrice(tItemData)
	
	-- Check if price is below puny limit
	local monPunyLimit = PurchaseConfirmation:GetPunyLimit()
	if monPunyLimit and monPrice < monPunyLimit then
		-- Price is below puny-limit, delegate to Vendor without adding price to history
		loginfo("CheckPurchase", "Puny amount " .. monPrice .. " ignored")
		PurchaseConfirmation:DelegateToVendor(tItemData)
		return -- Puny amount approved, no further checks required
	end
	
	-- Sequence of thresholds to check
	local tThresholds = {}
	
	-- Fixed threshold config
	local tFixedThreshold = {}
	tFixedThreshold.monPrice = monPrice
	tFixedThreshold.monThreshold = tSettings.tFixed.monThreshold
	tFixedThreshold.bEnabled = tSettings.tFixed.bEnabled
	tFixedThreshold.strType = "Fixed"
	tFixedThreshold.strWarning = "This is super expensive."
	tThresholds[#tThresholds+1] = tFixedThreshold
	
	-- Empty Coffers threshold config
	local tEmptyCoffersThreshold = {}
	tEmptyCoffersThreshold.monPrice = monPrice
	tEmptyCoffersThreshold.monThreshold = PurchaseConfirmation:GetEmptyCoffersThreshold()
	tEmptyCoffersThreshold.bEnabled = tSettings.tEmptyCoffers.bEnabled
	tEmptyCoffersThreshold.strType = "EmptyCoffers"
	tEmptyCoffersThreshold.strWarning = "This will pretty much bankrupt you."
	tThresholds[#tThresholds+1] = tEmptyCoffersThreshold
	
	-- Average threshold config
	local tAverageThreshold = {}
	tAverageThreshold.monPrice = monPrice
	tAverageThreshold.monThreshold = tSettings.tAverage.monThreshold
	tAverageThreshold.bEnabled = tSettings.tAverage.bEnabled
	tAverageThreshold.strType = "Average"
	tAverageThreshold.strWarning = "You don't usually buy stuff this expensive."
	tThresholds[#tThresholds+1] = tAverageThreshold
	
	-- Check all thresholds in order, raise warning for first breach
	for i,v in ipairs(tThresholds) do
		log:debug(tostring(i))
		if PurchaseConfirmation:IsThresholdBreached(v, tItemData) then 
			PurchaseConfirmation:RequestPurchaseConfirmation(v, tItemData)
			return 
		end
	end
	
	-- No thresholds breached
	PurchaseConfirmation:ConfirmPurchase(tItemData)
end

-- Empty coffers threshold is a % of the players total credit
function PurchaseConfirmation:GetEmptyCoffersThreshold()
	logenter("GetEmptyCoffersThreshold")
	local monCurrentPlayerCash = GameLib.GetPlayerCurrency():GetAmount()
	local threshold = math.floor(monCurrentPlayerCash * (tSettings.tEmptyCoffers.nPercent/100))
	loginfo("GetEmptyCoffersThreshold", "Empty coffers threshold calculated: " .. tostring(tSettings.tEmptyCoffers.nPercent) .. "% of " .. tostring(monCurrentPlayerCash) .. " = " .. tostring(threshold))
	logexit("GetEmptyCoffersThreshold")
	return threshold
end

-- Checks if a given threshold is enabled & breached
function PurchaseConfirmation:IsThresholdBreached(tThreshold, tItemData)
	logenter("IsThresholdBreached")
	
	-- Is threshold enabled?
	if not tThreshold.bEnabled then
		logdebug("IsThresholdBreached", "Threshold type " .. tThreshold.strType .. " disabled, skipping price check")
		return false
	end
	
	-- Is threshold available?
	if not tThreshold.monThreshold or tThreshold.monThreshold <= 0 then
		logdebug("IsThresholdBreached", "Threshold type " .. tThreshold.strType .. " has no active amount, skipping price check")
		return false
	end
	
	-- Is threshold breached?
	if tThreshold.monPrice < tThreshold.monThreshold then
		-- safe amount
		logdebug("IsThresholdBreached", tThreshold.strType .. " threshold, safe amount (amount<threshold): " .. tThreshold.monPrice .. "<" .. tThreshold.monThreshold)
		return false
	else
		logdebug("IsThresholdBreached", tThreshold.strType .. " threshold, unsafe amount (amount>=threshold): " .. tThreshold.monPrice .. ">=" .. tThreshold.monThreshold)
		return true
	end
end

-- Gets item price from tItemData
function PurchaseConfirmation:GetItemPrice(tItemData)
	logenter("GetItemPrice")

	self.tItemData = tItemData -- Add to self for in-game debugging
	
	-- NB: "itemData" is a table property on tItemData. Yeah.
	monPrice = tItemData.itemData:GetBuyPrice():Multiply(tItemData.nStackSize):GetAmount()
	logdebug("GetItemPrice", "Item price extracted: " .. monPrice)
	
	logexit("GetItemPrice")
	return monPrice
end

-- Determines the current punyLimit
function PurchaseConfirmation:GetPunyLimit()
	logenter("GetPunyLimit")
	
	-- Calc punylimit as simple function of current level * tPuny.monThreshold
	local nLevel = GameLib.GetPlayerUnit():GetBasicStats().nLevel
	local monPunyLimit = nLevel * tonumber(tSettings.tPuny.monThreshold)
	logdebug("GetPunyLimit", "playerLevel=" .. nLevel .. ", tPuny.monThreshold=" .. tSettings.tPuny.monThreshold ..", calculated monPunyLimit=" .. monPunyLimit)
	
	logexit("GetPunyLimit")
	return monPunyLimit
end

-- Price for current purchase is unsafe: show warning dialogue
function PurchaseConfirmation:RequestPurchaseConfirmation(tThreshold, tItemData)
	logenter("RequestPurchaseConfirmation")
	
	self.tItemData = tItemData
	
	wndConfirmDialog:SetData(tItemData)
	wndConfirmDialog:FindChild("ItemName"):SetText(tItemData.strName)
	wndConfirmDialog:FindChild("ItemIcon"):SetSprite(tItemData.strIcon)
	wndConfirmDialog:FindChild("ItemPrice"):SetAmount(tThreshold.monPrice, true)
--	wndConfirmDialog:FindChild("WarningText"):SetText(tThreshold.strWarning)
	
	--[[
		Deactivate main vendor window while waiting for input, to avoid
		multiple unconfirmed purchases interfering with eachother.
		Remember to enable Vendor again, for any possible dialog exit-path!

		TODO: Instead of having 1 single dialog window which cockblocks Vendor 
		while waiting for response, have multiple instances of dialog boxes?
		Could be done by keeping XML and loading a new form per request.
		Probably just more confusing for the user, compared to blocking Vendor 
		while waiting for approval.
	]]
	VENDOR_ADDON.wndVendor:Enable(false)
	wndConfirmDialog:ToFront()
	wndConfirmDialog:Show(true)
	
	logexit("RequestPurchaseConfirmation")
end

function PurchaseConfirmation:ConfirmPurchase(tItemData)
	logenter("ConfirmPurchase")

	local monPrice = PurchaseConfirmation:GetItemPrice(tItemData)

	-- Add element to end of list
	if tSettings.seqPriceHistory == nil then tSettings.seqPriceHistory = {} end
	table.insert(tSettings.seqPriceHistory, monPrice)
	
	-- Remove oldest element(s, in case of history size reduction) from start of list if size is overgrown
	while #tSettings.seqPriceHistory>tSettings.tAverage.nHistorySize do
		table.remove(tSettings.seqPriceHistory, 1)
	end
	
	-- Update the average threshold
	local oldAverage = tSettings.tAverage.monThreshold
	local newAverage = PurchaseConfirmation:CalculateAverage()
	
	-- Update the current tAverage.monThreshold, so it is ready for next purchase-test
	newAverage = newAverage * (1+(tSettings.tAverage.nPercent/100)) -- add x% to threshold
	tSettings.tAverage.monThreshold = math.floor(newAverage ) -- round off
	
	loginfo("ConfirmPurchase", "Updated Average threshold from " .. tostring(oldAverage) .. " to " .. tostring(tSettings.tAverage.monThreshold))
	
	PurchaseConfirmation:DelegateToVendor(tItemData)
	logenter("ConfirmPurchase")
end

function PurchaseConfirmation:CalculateAverage()
	logenter("CalculateAverage")
	local total = 0
	
	if #tSettings.seqPriceHistory <= 0 then
		return 0
	end
	
	for i,v in ipairs(tSettings.seqPriceHistory) do
		total = total + v
	end
	
	local avg = math.floor(total / #tSettings.seqPriceHistory)
	logdebug("CalculateAverage", "Average=" .. avg)
	
	logexit("CalculateAverage")
	
	return avg
end

-- Called whenver a transaction is approved. Calls the real Vendor:OnBuy.
function PurchaseConfirmation:DelegateToVendor(tItemData)
	logenter("DelegateToVendor")
	
	logdebug("DelegateToVendor", "debugMode=" .. tostring(DEBUG_MODE))
	if DEBUG_MODE == true then
		Print("PURCHASE CONFIRMATION DEBUG MODE, SKIPPING ACTUAL PURCHASE")
		return
	end
	
	vendorFinalizeBuy(VENDOR_ADDON, tItemData)
	logexit("DelegateToVendor")
end

-----------------------------------------------------------------------------------------------
-- ConfirmPurchaseDialogForm button click functions
-----------------------------------------------------------------------------------------------

-- when the Purchase button is clicked
function PurchaseConfirmation:OnConfirmPurchase()
	logenter("OnConfirmPurchase")
	-- Hide dialog and register confirmed purchase
	wndConfirmDialog:Show(false, true)
	VENDOR_ADDON.wndVendor:Enable(true)
	
	-- Extract item being purchased, and delegate to Vendor
	local tItemData = wndConfirmDialog:GetData()
	PurchaseConfirmation:ConfirmPurchase(tItemData)

	logexit("OnConfirmPurchase")
end

-- when the Cancel button is clicked
function PurchaseConfirmation:OnCancelPurchase()
	logenter("OnCancelPurchase")
	wndConfirmDialog:Show(false, true)
	VENDOR_ADDON.wndVendor:Enable(true)
	logexit("OnCancelPurchase")
end


---------------------------------------------------------------------------------------------------
-- SettingsForm button click functions
---------------------------------------------------------------------------------------------------

function PurchaseConfirmation:DefaultSettings()

	-- Contains individual settings for all currency types
	local tAllSettings = {}

	-- Initially populate all currency type with "conservative" / generic default values 	
	for _,v in seqCurrencyTypes do
		local t
		tAllSettings[v.eType] = t
		
		-- Fixed
		t.tFixed = {}
		t.tFixed.bEnabled = false		-- Fixed threshold disabled
		t.tFixed.monThreshold = 0		-- No amount configured
		
		-- Empty coffers
		t.tEmptyCoffers = {}
		t.tEmptyCoffers.bEnabled = true	-- Empty Coffers threshold enabled
		t.tEmptyCoffers.nPercent = 75	-- Breach at 75% of current avail currency
		
		-- Average
		t.tAverage = {}
		t.tAverage.bEnabled = true		-- Average threshold enabled
		t.tAverage.monThreshold = 0		-- Initial calculated average history
		t.tAverage.nPercent = 75		-- Breach at 75% above average spending
		t.tAverage.nHistorySize = 25	-- Keep 25 elements in price history
		t.tAverage.seqPriceHistory = {}	-- Empty list of price elements
			
		-- Puny limit
		t.tPuny = {}
		t.tPuny.bEnabled = false		-- Puny threshold disabled
		t.tPuny.monThreshold = 0 		-- No amount configured
	end

	-- Override default values for Credits with appropriate Credits-only defaults
	tAllSettings[Money.CodeEnumCurrencyType.Credits].tFixed.bEnabled = true			-- Enable fixed threshold
	tAllSettings[Money.CodeEnumCurrencyType.Credits].tFixed.monThreshold = 50000	-- 5g
	tAllSettings[Money.CodeEnumCurrencyType.Credits].tPuny.bEnabled = true			-- Enable puny threshold
	tAllSettings[Money.CodeEnumCurrencyType.Credits].tFixed.monThreshold = 100		-- 1s (per level)

	return tAllSettings	
end


-- When the settings window is closed via Cancel, revert all changed values to current config
function PurchaseConfirmation:OnCancelSettings()
	logenter("OnCancelSettings")
	
	-- Hide settings window, without saving any entered values. 
	-- Settings GUI will revert to old values on next OnConfigure
	wndSettings:Show(false, true)	
	
	logexit("OnCancelSettings")
end

-- Extracts settings fields one by one, and updates tSettings accordingly.
function PurchaseConfirmation:OnAcceptSettings()
	logenter("OnAcceptSettings")
	-- Hide settings window
	wndSettings:Show(false, true)
	
	for _,v in seqCurrencyTypes do
		local wnd = wndSettings:FindChild("CurrencyControl_" .. v.strName)
		local t = tSettings[v.strName]
		PurchaseConfirmation:UpdateSettingsForCurrency(wnd, t)
	end
	
	logexit("OnAcceptSettings")
end

function PurchaseConfirmation:UpdateSettingsForCurrency(wndCurrencyConfiguration, tCurrency)
	
	--[[ FIXED THRESHOLD SETTINGS ]]
	
	local wndFixedSection = wndCurrencyConfiguration:FindChild("FixedSection")
	
	-- Fixed threshold checkbox	
	tSettings.tFixed.bEnabled = PurchaseConfirmation:ExtractSettingCheckbox(
		fixedSection:FindChild("EnableButton"),
		"tFixed.bEnabled",
		tSettings.tFixed.bEnabled)
	
	-- Fixed threshold amount
	tSettings.tFixed.monThreshold = PurchaseConfirmation:ExtractSettingAmount(
		fixedSection:FindChild("Amount"),
		"tFixed.monThreshold",
		tSettings.tFixed.monThreshold)


	--[[ EMPTY COFFERS SETTINGS ]]
	
	local wndEmptyCoffersSection = wndCurrencyConfiguration:FindChild("EmptyCoffersSection")
	
	-- Empty coffers threshold checkbox	
	tSettings.tEmptyCoffers.bEnabled = PurchaseConfirmation:ExtractSettingCheckbox(
		wndEmptyCoffersSection:FindChild("EnableButton"),
		"tEmptyCoffers.bEnabled",
		tSettings.tEmptyCoffers.bEnabled)
	
	-- Empty coffers percentage
	tSettings.tEmptyCoffers.nPercent = PurchaseConfirmation:ExtractOrRevertSettingNumber(
		wndEmptyCoffersSection:FindChild("PercentEditBox"),
		"tEmptyCoffers.nPercent",
		tSettings.tEmptyCoffers.nPercent,
		1, 100)
	
	
	--[[ AVERAGE THRESHOLD SETTINGS ]]

	local wndAverageSection = wndCurrencyConfiguration:FindChild("AverageSection")
	
	-- Average threshold checkbox
	tSettings.tAverage.bEnabled = PurchaseConfirmation:ExtractSettingCheckbox(
		wndAverageSection:FindChild("EnableButton"),
		"tAverage.bEnabled",
		tSettings.tAverage.bEnabled)

	-- Average percent number input field
	tSettings.tAverage.nPercent = PurchaseConfirmation:ExtractOrRevertSettingNumber(
		wndAverageSection:FindChild("PercentEditBox"),
		"tAverage.nPercent",
		tSettings.tAverage.nPercent,
		1, 999)

	-- History size number input field
	tSettings.tAverage.nHistorySize = PurchaseConfirmation:ExtractOrRevertSettingNumber(
		wndAverageSection:FindChild("HistorySizeEditBox"),
		"tAverage.nHistorySize",
		tSettings.tAverage.nHistorySize,
		1, 999)
	
	
	--[[ PUNY AMOUNT SETTINGS ]]
	
	local wndPunySection = wndCurrencyConfiguration:FindChild("PunySection")

	-- Puny threshold checkbox
	tSettings.tPuny.bEnabled = PurchaseConfirmation:ExtractSettingCheckbox(
		wndAverageSection:FindChild("EnableButton"),
		"tPuny.bEnabled",
		tSettings.tPuny.bEnabled)
	
	-- Puny threshold limit (per level)
	tSettings.tPuny.monThreshold = PurchaseConfirmation:ExtractSettingAmount(
		wndPunySection:FindChild("Amount"),
		"tPuny.monThreshold",
		tSettings.tPuny.monThreshold)
end

---------------------------------------------------------------------------------------------------
-- Settings left/right selector
---------------------------------------------------------------------------------------------------

function PurchaseConfirmation:OnCurrencyLeftButton(wndHandler, wndControl, eMouseButton)
	tCurrentCurrency = wndHandler:GetData()
	
	-- Identify current index in the seqCurrencyType list
	local idx = 1
	for k,v in seqCurrencyTypes do
		if v.eType = tCurrentCurrency.eType then idx = k end
	end
	
	-- Determine next index
	if idx == #seqCurrencyTypes then
		idx = 1
	else
		idx = idx+1
	if 	
end

function PurchaseConfirmation:OnCurrencyRightButton(wndHandler, wndControl, eMouseButton)
	
end

function PurchaseConfirmation:UpdateSelectedCurrency(currencyIdx)
	tCurrencyType = seqCurrencyTypes[currencyIdx]
	wndSettings:FindChild("CurrencySelector"):SetData(tCurrencyType)
	wndSettings:FindChild("CurrencySelector"):FindChild("Name"):SetText(tCurrencyType.strTitle) -- NB: Title, not Name. Assuming Title is localized.
	
	-- Show/hide appropriate currency config windows
	for k,v in seqCurrencies do
		
	end

end

---------------------------------------------------------------------------------------------------
-- Settings save/restore related related functionality
---------------------------------------------------------------------------------------------------

-- Save addon config per character. Called by engine when performing a controlled game shutdown.
function PurchaseConfirmation:OnSave(eType)
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end
	
	return tSettings
end

-- Restore addon config per character. Called by engine when loading UI.
function PurchaseConfirmation:OnRestore(eType, tSavedData)
	logenter("OnRestore")
	if eType ~= GameLib.CodeEnumAddonSaveLevel.Character then 
		return 
	end

	--[[
		To gracefully handle changes to the config-structure across different versions of savedata:
		1) Prepare a set of global default values
		2) Load up each individual *currently supported* value, and override the default
		
		That ensures that "extra" properties (for older configs) in the savedata set 
		are thrown away, and that new "missing" properties are given default values
	]]
	tDefaultSettings = PurchaseConfirmation:DefaultSettings()
	
	if type(tSavedData) == "table" then -- should be outer settings table
		for _,v in seqCurrencyTypes do
			if type(tSavedData[v.strName]) == "table" then -- should be individual currency table table
				local t = tDefaultSettings[v.strName]
				
				if type(t.tFixed) == "table" then -- does fixed section exist?
					if type(t.tFixed.bEnabled) == "boolean" then tDefaultSettings[v.strName].tFixed.bEnabled = t.tFixed.bEnabled end
					if type(t.tFixed.monThreshold) == "number" then tDefaultSettings[v.strName].tFixed.monThreshold= t.tFixed.monThreshold end
				end
				
				if type(t.tEmptyCoffers) == "table" then
					if type(t.tEmptyCoffers.bEnabled) == "boolean" then tDefaultSettings[v.strName].tEmptyCoffers.bEnabled = t.tEmptyCoffers.bEnabled end
					if type(t.tEmptyCoffers.nPercent) == "number" then tDefaultSettings[v.strName].tEmptyCoffers.nPercent = t.tEmptyCoffers.nPercent end
				end
				
				if type(t.tAverage) == "table" then
					if type(t.tAverage.bEnabled) == "boolean" then tDefaultSettings[v.strName].tAverage.bEnabled = t.tAverage.bEnabled end
					if type(t.tAverage.monThreshold) == "number" then tDefaultSettings[v.strName].tAverage.monThreshold = t.tAverage.monThreshold end
					if type(t.tAverage.nPercent) == "number" then tDefaultSettings[v.strName].tAverage.nPercent = t.tAverage.nPercent end
					if type(t.tAverage.nHistorySize) == "number" then tDefaultSettings[v.strName].tAverage.nHistorySize = t.tAverage.nHistorySize end
					if type(t.tAverage.seqPriceHistory) == "table" then tDefaultSettings[v.strName].tAverage.seqPriceHistory = t.tAverage.seqPriceHistory end
				end

				if type(t.tPuny) == "table" then
					if type(t.tPuny.bEnabled) == "boolean" then tDefaultSettings[v.strName].tPuny.bEnabled = t.tPuny.bEnabled end
					if type(t.tPuny.monThreshold) == "number" then tDefaultSettings[v.strName].tPuny.monThreshold = t.tPuny.monThreshold end
				end				
			end
		end
	end
	
	-- TODO: Add support for loading (but not saving) <0.8-style settings. Can be removed again after a few releases.
	
	logexit("OnRestore")
end


-- Addon config button and slash-command invocation
function PurchaseConfirmation:OnConfigure()
	logenter("OnConfigure")
	
	-- Update values on GUI with current settings before showing
	PurchaseConfirmation:PopulateSettingsWindow()

	wndSettings:Show(true, true)	
	wndSettings:ToFront()
	
	logexit("OnConfigure")
end

-- Populates the settings window with current configuration values (for all currency types)
function PurchaseConfirmation:PopulateSettingsWindow()
	logenter("PopulateSettingsWindow")
		
	for _,v in seqCurrencyTypes do
		local wnd = wndSettings:FindChild("CurrencyControl_" .. v.strName)
		local t = tSettings[v.strName]
		PurchaseConfirmation:PopulateSettingsWindowForCurrency(wnd, t)
	end
	
	logexit("PopulateSettingsWindow")
end


-- Populates the currency control form for a single currency-type
function PurchaseConfirmation:PopulateSettingsWindowForCurrency(wndCurrencyControl, tSettings)
	logenter("PopulateCurrencyControls")
	
	-- Fixed settings
	local fixedSection = wndCurrencyControl:FindChild("FixedSection")
	if tSettings.tFixed.bEnabled ~= nil then fixedSection:FindChild("EnableButton"):SetCheck(tSettings.tFixed.bEnabled) end
	if tSettings.tFixed.monThreshold ~= nil then fixedSection:FindChild("Amount"):SetAmount(tSettings.tFixed.monThreshold, true) end

	-- Empty coffers settings
	local emptyCoffersSection = wndCurrencyControl:FindChild("EmptyCoffersSection")
	if tSettings.tEmptyCoffers.bEnabled ~= nil then emptyCoffersSection:FindChild("EnableButton"):SetCheck(tSettings.tEmptyCoffers.bEnabled) end
	if tSettings.tEmptyCoffers.nPercent ~= nil then emptyCoffersSection:FindChild("PercentEditBox"):SetText(tSettings.tEmptyCoffers.nPercent) end
	
	-- Average settings
	local averageSection = wndCurrencyControl:FindChild("AverageSection")
	if tSettings.tAverage.bEnabled ~= nil then averageSection:FindChild("EnableButton"):SetCheck(tSettings.tAverage.bEnabled) end
	if tSettings.tAverage.nPercent ~= nil then averageSection:FindChild("PercentEditBox"):SetText(tSettings.tAverage.nPercent) end
	if tSettings.tAverage.nHistorySize ~= nil then averageSection:FindChild("HistorySizeEditBox"):SetText(tSettings.tAverage.nHistorySize) end
	
	-- Puny settings
	local punySection = wndCurrencyControl:FindChild("PunySection")
	if tSettings.tPuny.bEnabled ~=nil then punySection:FindChild("PunySection"):FindChild("EnableButton"):SetCheck(tSettings.tPuny.bEnabled) end
	if tSettings.tPuny.monThreshold ~=nil then punySection:FindChild("Amount"):SetAmount(tSettings.tPuny.monThreshold, true) end
	
	logexit("PopulateCurrencyControls")
end

-- Extracts text-field as a number within specified bounts. Reverts text field to currentValue if input value is invalid.
function PurchaseConfirmation:ExtractOrRevertSettingNumber(wndField, strName, currentValue, minValue, maxValue)
	local newValue = tonumber(wndField:GetText())

	-- Input-value must be parsable as a number
	if newValue == nil then
		logwarn("ExtractOrRevertSettingNumber", "Field " .. strName .. ": value '" .. newValue .. "' is not a number, reverting to previous value '" .. currentValue .. "'")
		wndField:SetText(currentValue)
		return currentValue
	end
	
	-- Input-value is a number, but must be within specified bounds
	if newValue < minValue or newValue > maxValue then
		logwarn("ExtractOrRevertSettingNumber", "Field " .. strName .. ": value '" .. newValue .. "' is not within bounds [" .. minValue .. "-" .. maxValue .. "], reverting to previous value '" .. currentValue .. "'")
		wndField:SetText(currentValue)
		return currentValue
	end
	
	-- Input-value is accepted, log if changed or not
	if newValue == currentValue then
		logdebug("ExtractOrRevertSettingNumber", "Field " .. strName .. ": value '" .. newValue .. "' is unchanged")
	else
		loginfo("ExtractOrRevertSettingNumber", "Field " .. strName .. ": value '" .. newValue .. "' updated from previous value '" .. currentValue .. "'")
	end
	return newValue;
end

-- Extracts an amount-field, and logs if it is changed from currentValue
function PurchaseConfirmation:ExtractSettingAmount(wndField, strName, currentValue)
	local newValue = wndField:GetAmount()
	if newValue == currentValue then
		logdebug("ExtractSettingAmount", "Field " .. tostring(strName) .. ": value '" .. tostring(newValue) .. "' is unchanged")
	else
		loginfo("ExtractSettingAmount", "Field " .. tostring(strName) .. ": value '" .. tostring(newValue) .. "' updated from previous value '" .. tostring(currentValue) .. "'")
	end
	return newValue
end

-- Extracts a checkbox-field, and logs if it is changed from currentValue
function PurchaseConfirmation:ExtractSettingCheckbox(wndField, strName, currentValue)
	local newValue = wndField:IsChecked()
	if newValue == currentValue then
		logdebug("ExtractSettingCheckbox", "Field " .. strName .. ": value '" .. tostring(newValue) .. "' is unchanged")
	else
		loginfo("ExtractSettingCheckbox", "Field " .. strName .. ": value '" .. tostring(newValue) .. "' updated from previous value '" .. tostring(currentValue) .. "'")
	end
	return newValue
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
