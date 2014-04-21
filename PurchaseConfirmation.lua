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

require "Window"  
require "GameLib"
require "Apollo"


-- Addon object itself
local PurchaseConfirmation = {} 

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
local ADDON_VERSION = "0.7.2"
local DEBUG_MODE = false -- Debug mode = never actually delegate to Vendor (never actually purchase stuff)

local VENDOR_ADDON = "Vendor" -- Used when loading/declaring dependencies to Vendor
local kstrTabBuy = "VendorTab0"


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
	local strConfigureButtonText = "Purch. Conf."
	local tDependencies = {VENDOR_ADDON, "Gemini:Logging-1.2"}
    Apollo.RegisterAddon(self, bHasConfigureButton, strConfigureButtonText, tDependencies)
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
	
	-- Now that forms are loaded, remove XML doc for gc
	self.xmlDoc = nil
	  
	
	--[[ HARDCODED DEFAULT SETTINGS ]]
	
	-- tSettings will be poulated prior to OnLoad, in OnRestore if saved settings exist
	if tSettings == nil then
		-- Fixed
		tSettings = {}
		tSettings.bFixedThresholdEnabled = true	-- Fixed threshold enabled
		tSettings.monFixedThreshold = 10000		-- Breach at 1g
	
		-- Empty coffers
		tSettings.bEmptyCoffersThresholdEnabled = true	-- Empty Coffers threshold enabled
		tSettings.nPercentEmptyCoffers = 75				-- Breach at 80% of current avail credits
	
		-- Average
		tSettings.bAverageThresholdEnabled = true	-- Average threshold enabled
		tSettings.monAverageThreshold = 0			-- Initial calculated average history
		tSettings.nPercentAboveAverage = 75			-- Breach at 75% above average spending
		tSettings.nPriceHistorySize = 25			-- Keep 25 elements in price history
		tSettings.seqPriceHistory = {}				-- Empty list of price elements
		
		-- Puny limit
		tSettings.monPunyLimitPerLevel = 100 -- Default puny limit = 1s per level		
	end

		
	--[[ ADDON REGISTRATION AND FUNCTION INJECTION ]]
	
	-- Slash command opens settings window
	Apollo.RegisterSlashCommand("purchaseconfirmation", "OnConfigure", self)
	Apollo.RegisterSlashCommand("purconf", "OnConfigure", self)

	-- Inject own OnBuy function into Vendor addon	
	vendorFinalizeBuy = Apollo.GetAddon(VENDOR_ADDON).FinalizeBuy -- store ref to original function
	Apollo.GetAddon(VENDOR_ADDON).FinalizeBuy = PurchaseConfirmation.CheckPurchase -- replace Vendors FinalizeBuy with own
	
	logexit("OnDocLoaded")
end

-----------------------------------------------------------------------------------------------
-- PurchaseConfirmation Functions
-----------------------------------------------------------------------------------------------

-- Called on Vendor's "Purchase" buttonclick, hijacked
function PurchaseConfirmation:CheckPurchase(tItemData)
	logenter("CheckPurchase")
	
	-- Only execute any checks during purchases (not sales, repairs or buybacks)
	if not Apollo.GetAddon(VENDOR_ADDON).wndVendor:FindChild(kstrTabBuy):IsChecked() then
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
	tFixedThreshold.monThreshold = tSettings.monFixedThreshold
	tFixedThreshold.bEnabled = tSettings.bFixedThresholdEnabled
	tFixedThreshold.strType = "Fixed"
	tFixedThreshold.strWarning = "This is super expensive."
	tThresholds[#tThresholds+1] = tFixedThreshold
	
	-- Empty Coffers threshold config
	local tEmptyCoffersThreshold = {}
	tEmptyCoffersThreshold.monPrice = monPrice
	tEmptyCoffersThreshold.monThreshold = PurchaseConfirmation:GetEmptyCoffersThreshold()
	tEmptyCoffersThreshold.bEnabled = tSettings.bEmptyCoffersThresholdEnabled
	tEmptyCoffersThreshold.strType = "EmptyCoffers"
	tEmptyCoffersThreshold.strWarning = "This will pretty much bankrupt you."
	tThresholds[#tThresholds+1] = tEmptyCoffersThreshold
	
	-- Average threshold config
	local tAverageThreshold = {}
	tAverageThreshold.monPrice = monPrice
	tAverageThreshold.monThreshold = tSettings.monAverageThreshold
	tAverageThreshold.bEnabled = tSettings.bAverageThresholdEnabled
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
	local threshold = math.floor(monCurrentPlayerCash * (tSettings.nPercentEmptyCoffers/100))
	loginfo("GetEmptyCoffersThreshold", "Empty coffers threshold calculated: " .. tostring(tSettings.nPercentEmptyCoffers) .. "% of " .. tostring(monCurrentPlayerCash) .. " = " .. tostring(threshold))
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
	
	-- Calc punylimit as simple function of current level * monPunyLimitPerLevel
	local nLevel = GameLib.GetPlayerUnit():GetBasicStats().nLevel
	local monPunyLimit = nLevel * tonumber(tSettings.monPunyLimitPerLevel)
	logdebug("GetPunyLimit", "playerLevel=" .. nLevel .. ", monPunyLimitPerLevel=" .. tSettings.monPunyLimitPerLevel ..", calculated monPunyLimit=" .. monPunyLimit)
	
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
	Apollo.GetAddon(VENDOR_ADDON).wndVendor:Enable(false)
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
	while #tSettings.seqPriceHistory>tSettings.nPriceHistorySize do
		table.remove(tSettings.seqPriceHistory, 1)
	end		
	
	-- Update the average threshold
	local oldAverage = tSettings.monAverageThreshold
	local newAverage = PurchaseConfirmation:CalculateAverage()
		
	-- Update the current monAverageThreshold, so it is ready for next purchase-test
	newAverage = newAverage * (1+(tSettings.nPercentAboveAverage/100)) -- add x% to threshold
	tSettings.monAverageThreshold = math.floor(newAverage ) -- round off
	
	loginfo("ConfirmPurchase", "Updated Average threshold from " .. tostring(oldAverage) .. " to " .. tostring(tSettings.monAverageThreshold))
	
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
	
	vendorFinalizeBuy(Apollo.GetAddon(VENDOR_ADDON), tItemData)
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
	Apollo.GetAddon(VENDOR_ADDON).wndVendor:Enable(true)
		
	-- Extract item being purchased, and delegate to Vendor
	local tItemData = wndConfirmDialog:GetData()
	PurchaseConfirmation:ConfirmPurchase(tItemData)	

	logexit("OnConfirmPurchase")
end

-- when the Cancel button is clicked
function PurchaseConfirmation:OnCancelPurchase()
	logenter("OnCancelPurchase")
	wndConfirmDialog:Show(false, true)
	Apollo.GetAddon(VENDOR_ADDON).wndVendor:Enable(true)
	logexit("OnCancelPurchase")
end


---------------------------------------------------------------------------------------------------
-- SettingsForm button click functions
---------------------------------------------------------------------------------------------------

-- When the settings window is closed via Cancel, revert all changed values to current config
function PurchaseConfirmation:OnCancelSettings()
	logenter("OnCancelSettings")
	
	-- Hide settings window, without saving any entered values. 
	-- Settings GUI will revert to old values on next OnConfigure
	wndSettings:Show(false, true)
	wndSettings:ToFront()
	
	logexit("OnCancelSettings")
end

-- Extracts settings fields one by one, and updates tSettings accordingly.
function PurchaseConfirmation:OnAcceptSettings()
	logenter("OnAcceptSettings")
	-- Hide settings window
	wndSettings:Show(false, true)
	

	--[[ FIXED THRESHOLD SETTINGS ]]
	
	-- Fixed threshold checkbox
	tSettings.bFixedThresholdEnabled = PurchaseConfirmation:ExtractSettingCheckbox(
		wndSettings:FindChild("FixedSection"):FindChild("FixedEnableButton"),
		"bFixedThresholdEnabled",
		tSettings.bFixedThresholdEnabled)
	
	-- Fixed threshold amount
	tSettings.monFixedThreshold = PurchaseConfirmation:ExtractSettingAmount(
		wndSettings:FindChild("FixedSection"):FindChild("FixedAmount"),
		"monFixedThreshold",
		tSettings.monFixedThreshold)


	--[[ EMPTY COFFERS SETTINGS ]]
	
	-- Empty coffers threshold checkbox
	tSettings.bEmptyCoffersThresholdEnabled = PurchaseConfirmation:ExtractSettingCheckbox(
		wndSettings:FindChild("EmptyCoffersEnableButton"),
		"bEmptyCoffersThresholdEnabled",
		tSettings.bEmptyCoffersThresholdEnabled)
	
	-- Empty coffers percentage
	tSettings.nPercentEmptyCoffers = PurchaseConfirmation:ExtractOrRevertSettingNumber(
		wndSettings:FindChild("EmptyCoffersEditBox"),
		"nPercentEmptyCoffers",
		tSettings.nPercentEmptyCoffers,
		1, 100)
		
		
	--[[ AVERAGE THRESHOLD SETTINGS ]]

	-- Average threshold checkbox
	tSettings.bAverageThresholdEnabled = PurchaseConfirmation:ExtractSettingCheckbox(
		wndSettings:FindChild("AverageEnableButton"),
		"bAverageThresholdEnabled",
		tSettings.bAverageThresholdEnabled)		

	-- Average percent number input field
	tSettings.nPercentAboveAverage = PurchaseConfirmation:ExtractOrRevertSettingNumber(
		wndSettings:FindChild("AveragePercentEditBox"),
		"nPercentAboveAverage",
		tSettings.nPercentAboveAverage,
		1, 999)

	-- History size number input field
	tSettings.nPriceHistorySize = PurchaseConfirmation:ExtractOrRevertSettingNumber(
		wndSettings:FindChild("AverageHistorySizeEditBox"),
		"nPriceHistorySize",
		tSettings.nPriceHistorySize,
		1, 999)


	--[[ PUNY AMOUNT SETTINGS ]]
	
	tSettings.monPunyLimitPerLevel = PurchaseConfirmation:ExtractSettingAmount(
		wndSettings:FindChild("PunyAmount"),
		"monPunyLimitPerLevel",
		tSettings.monPunyLimitPerLevel)		
	
	logexit("OnAcceptSettings")
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

	tSettings = tSavedData
	
	PurchaseConfirmation:CalculateAverage()
	logexit("OnRestore")
end

-- Addon config button and slash-command invocation
function PurchaseConfirmation:OnConfigure()
	logenter("OnConfigure")
	PurchaseConfirmation:PopulateSettingsWindow()
	wndSettings:Show(true, true)
	wndSettings:ToFront()
	logexit("OnConfigure")
end

-- Populates the settings window with current configuration values
function PurchaseConfirmation:PopulateSettingsWindow()
	logenter("PopulateSettingsWindow")
	
	-- Fixed settings
	if tSettings.bFixedThresholdEnabled ~= nil then	wndSettings:FindChild("FixedEnableButton"):SetCheck(tSettings.bFixedThresholdEnabled) end	
	if tSettings.monFixedThreshold ~= nil then wndSettings:FindChild("FixedAmount"):SetAmount(tSettings.monFixedThreshold, true) end

	-- Empty coffers settings
	if tSettings.bEmptyCoffersThresholdEnabled ~= nil then wndSettings:FindChild("EmptyCoffersEnableButton"):SetCheck(tSettings.bEmptyCoffersThresholdEnabled) end
	if tSettings.nPercentEmptyCoffers ~= nil then wndSettings:FindChild("EmptyCoffersEditBox"):SetText(tSettings.nPercentEmptyCoffers) end
	
	-- Average settings
	if tSettings.bAverageThresholdEnabled ~= nil then wndSettings:FindChild("AverageEnableButton"):SetCheck(tSettings.bAverageThresholdEnabled) end
	if tSettings.nPercentAboveAverage ~= nil then wndSettings:FindChild("AveragePercentEditBox"):SetText(tSettings.nPercentAboveAverage) end
	if tSettings.nPriceHistorySize ~= nil then wndSettings:FindChild("AverageHistorySizeEditBox"):SetText(tSettings.nPriceHistorySize) end
	
	-- Puny settings
	if tSettings.monPunyLimitPerLevel ~=nil then wndSettings:FindChild("PunyAmount"):SetAmount(tSettings.monPunyLimitPerLevel, true) end
	
	logexit("PopulateSettingsWindow")
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