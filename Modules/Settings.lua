require "Apollo"
require "Window"

--[[
	Various functions for controlling the settings.
]]

-- Register module as package
local Settings = {}
local MODULE_NAME = "PurchaseConfirmation:Settings"
Apollo.RegisterPackage(Settings, MODULE_NAME, 1, {"PurchaseConfirmation"})

-- "glocals" set during Init
local log

--- Standard Lua prototype class definition
function Settings:new(o)
	o = o or {}
	setmetatable(o, self)
	self.__index = self 
	return o
end

--- Registers the Settings module.
-- Called by PurchaseConfirmation during initialization.
function Settings:Init()
	addon = Apollo.GetAddon("PurchaseConfirmation") -- main addon, calling the shots
	log = addon.log
			
	-- Slash commands to manually open the settings window
	Apollo.RegisterSlashCommand("purchaseconfirmation", "OnConfigure", self)
	Apollo.RegisterSlashCommand("purconf", "OnConfigure", self)
	
	self.xmlDoc = XmlDoc.CreateFromFile("Modules/Settings.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	return self
end

--- Called when XML document is fully loaded, ready to produce forms.
function Settings:OnDocLoaded()	
	-- Check that XML document is properly loaded
	if self.xmlDoc == nil or not self.xmlDoc:IsLoaded() then
		Apollo.AddAddonErrorText(self, "XML document was not loaded")
		log:error("XML document was not loaded")
		return
	end
		
	-- Load Settings form
	self.wndSettings = Apollo.LoadForm(self.xmlDoc, "SettingsForm", nil, self)
	if self.wndSettings == nil then
		Apollo.AddAddonErrorText(self, "Could not load the SettingsForm window")
		log:error("Settings.OnDocLoaded: wndSettings is nil!")
		return
	end	
	self.wndSettings:Show(false, true)
	self:LocalizeSettings(self.wndSettings)
	
	-- Load currency-distinct
	for i,tCurrency in ipairs(addon.seqCurrencies) do
		-- Set text on header button (size of seqCurrencies must match actual button layout on SettingsForm!)
		local btn = self.wndSettings:FindChild("CurrencyBtn" .. i)
		btn:SetData(tCurrency)
		btn:SetTooltip(tCurrency.strDescription)
	
		-- Load "individual currency panel" settings forms, and spawn one for each currency type
		-- TODO: this breaks isolation. Move to self.
		tCurrency.wndPanel = Apollo.LoadForm(self.xmlDoc, "SettingsCurrencyTabForm", self.wndSettings:FindChild("CurrencyTabArea"), self)
		self:LocalizeSettingsTab(tCurrency.wndPanel)

		if tCurrency.wndPanel == nil then
			Apollo.AddAddonErrorText(self, "Could not load the CurrencyPanelForm window")
			log:error("OnDocLoaded: wndPanel is nil!")
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
		log:debug("OnDocLoaded: Created currency panel for '" .. tostring(tCurrency.strName) .. "' (" .. tostring(tCurrency.eType) .. ")")
	end

	self.xmlDoc = nil
end

--- Localizes the main Settings window
function Settings:LocalizeSettings(wnd)
	local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

	wnd:FindChild("WindowTitle"):SetText(L["Settings_WindowTitle"])
	wnd:FindChild("BalanceLabel"):SetText(L["Settings_Balance"])
end

--- Localize an individual settings tab
function Settings:LocalizeSettingsTab(wnd)
	local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

	wnd:FindChild("FixedSection"):FindChild("EnableButtonLabel"):SetText(L["Settings_Threshold_Fixed_Enable"])
	wnd:FindChild("FixedSection"):FindChild("Description"):SetText(L["Settings_Threshold_Fixed_Description"])

	wnd:FindChild("PunySection"):FindChild("EnableButtonLabel"):SetText(L["Settings_Threshold_Puny_Enable"])
	wnd:FindChild("PunySection"):FindChild("Description"):SetText(L["Settings_Threshold_Puny_Description"])

	wnd:FindChild("AverageSection"):FindChild("EnableButtonLabel"):SetText(L["Settings_Threshold_Average_Enable"])
	wnd:FindChild("AverageSection"):FindChild("Description"):SetText(L["Settings_Threshold_Average_Description"])

	wnd:FindChild("EmptyCoffersSection"):FindChild("EnableButtonLabel"):SetText(L["Settings_Threshold_EmptyCoffers_Enable"])
	wnd:FindChild("EmptyCoffersSection"):FindChild("Description"):SetText(L["Settings_Threshold_EmptyCoffers_Description"])
end


-- Shows the Settings window, after populating it with current data.
-- Invoked from main Addon list via Configure, or registered slash commands. 
function Settings:OnConfigure()
	log:info("Configure")
	-- Update values on GUI with current settings before showing
	self:PopulateSettingsWindow()
	self:UpdateBalance()

	self.wndSettings:Show(true, true)
	self.wndSettings:ToFront()
end

-- Populates the settings window with current configuration values (for all currency types)
function Settings:PopulateSettingsWindow()
	-- Loop over all supported currencytypes, populate each one with current settings
	for _,currencyType in ipairs(addon.seqCurrencies) do
		local wndCurrency = currencyType.wndPanel
		local tCurrencySettings = addon.tSettings[currencyType.strName]
		self:PopulateSettingsWindowForCurrency(wndCurrency, tCurrencySettings)
	end
end

function Settings:UpdateBalance()
	-- Find checked (displayed) currency type, update balance window
	local tCurrency = self.wndSettings:FindChild("CurrencySelectorSection"):GetRadioSelButton("PurchaseConfirmation_CurrencySelection"):GetData()
	self.wndSettings:FindChild("Balance"):SetMoneySystem(tCurrency.eType)
	self.wndSettings:FindChild("CurrentBalanceSection"):FindChild("Balance"):SetAmount(GameLib.GetPlayerCurrency(tCurrency.eType):GetAmount(), false)
end

-- Populates the currency control form for a single currency-type
function Settings:PopulateSettingsWindowForCurrency(wndCurrencyControl, tSettings)
	--[[
		For each individual field, check if a value exist in tSettings,
		and set the value in the corresponding UI field.
	]]
	
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
	
	-- Puny settings
	local punySection = wndCurrencyControl:FindChild("PunySection")
	if tSettings.tPuny.bEnabled ~=nil then punySection:FindChild("EnableButton"):SetCheck(tSettings.tPuny.bEnabled) end
	if tSettings.tPuny.monThreshold ~=nil then punySection:FindChild("Amount"):SetAmount(tSettings.tPuny.monThreshold, true) end
end

-- Restores saved settings into the tSettings structure.
-- Invoked during game load.
function Settings:RestoreSettings(tSavedData)
	--[[
		To gracefully handle changes to the config-structure across different versions of savedata:
		1) Prepare a set of global default values
		2) Load up each individual *currently supported* value, and override the default value
		
		That ensures that "extra" properties (for older configs) in the savedata set 
		are thrown away, and that new "missing" properties are given default values
		
		To support loading older settings-types (when upgrading addon version), load
		old settings formats first, in order
	]]
	local tSettings = self:DefaultSettings()
	self:FillSettings_0_7(tSettings, tSavedData) -- ver 0.7 single-currency settings
	self:FillSettings_0_8(tSettings, tSavedData) -- ver 0.8+ multi-currency settings
	
	return tSettings
end

-- Addonv 0.7 settings; "flat", and only supports Credits.
function Settings:FillSettings_0_7(tSettings, tSavedData)
	log:debug("Restoring v0.7-style saved settings")
	if type(tSavedData) == "table" then -- should be outer settings table
		local tTarget = tSettings["Credits"]
	
		-- Fixed
		if type(tSavedData.bFixedThresholdEnabled) == "boolean" then tTarget.tFixed.bEnabled = tSavedData.bFixedThresholdEnabled end
		if type(tSavedData.monFixedThreshold) == "number" then tTarget.tFixed.monThreshold = tSavedData.monFixedThreshold end

		-- Empty coffers
		if type(tSavedData.bEmptyCoffersThresholdEnabled) == "boolean" then tTarget.tEmptyCoffers.bEnabled = tSavedData.bEmptyCoffersThresholdEnabled end
		if type(tSavedData.nPercentEmptyCoffers) == "number" then tTarget.tEmptyCoffers.nPercent = tSavedData.nPercentEmptyCoffers end
				
		-- Average
		if type(tSavedData.bAverageThresholdEnabled) == "boolean" then tTarget.tAverage.bEnabled = tSavedData.bAverageThresholdEnabled end
		if type(tSavedData.nPercentAboveAverage) == "number" then tTarget.tAverage.nPercent = tSavedData.nPercentAboveAverage end
		if type(tSavedData.seqPriceHistory) == "table" then tTarget.tAverage.seqPriceHistory = tSavedData.seqPriceHistory end
		if type(tSavedData.monAverageThreshold) == "boolean" then tTarget.tAverage.monAmount = tSavedData.monAverageThreshold end
		if type(tSavedData.nPriceHistorySize) == "number" then tTarget.tAverage.nHistorySize = tSavedData.nPriceHistorySize end
		
		-- Puny
		if type(tSavedData.monPunyLimitPerLevel) == "number" then tTarget.tPuny.monAmount = tSavedData.monPunyLimitPerLevel end		
	end	
end

-- Addon v0.8 settings; "layered", and supports multiple currencies
function Settings:FillSettings_0_8(tSettings, tSavedData)
	log:debug("Restoring v0.8-style saved settings")
	if type(tSavedData) == "table" then -- should be outer settings table	
		for _,v in ipairs(addon.seqCurrencies) do
			if type(tSavedData[v.strName]) == "table" then -- should be individual currency table table
				local tSaved = tSavedData[v.strName] -- assumed present in default settings
				local tTarget = tSettings[v.strName]
				
				if type(tSaved.tFixed) == "table" then -- does fixed section exist?
					if type(tSaved.tFixed.bEnabled) == "boolean" then tTarget.tFixed.bEnabled = tSaved.tFixed.bEnabled end
					if type(tSaved.tFixed.monThreshold) == "number" then tTarget.tFixed.monThreshold = tSaved.tFixed.monThreshold end
				end
				
				if type(tSaved.tEmptyCoffers) == "table" then
					if type(tSaved.tEmptyCoffers.bEnabled) == "boolean" then tTarget.tEmptyCoffers.bEnabled = tSaved.tEmptyCoffers.bEnabled end
					if type(tSaved.tEmptyCoffers.nPercent) == "number" then tTarget.tEmptyCoffers.nPercent = tSaved.tEmptyCoffers.nPercent end
				end
				
				if type(tSaved.tAverage) == "table" then
					if type(tSaved.tAverage.bEnabled) == "boolean" then tTarget.tAverage.bEnabled = tSaved.tAverage.bEnabled end
					if type(tSaved.tAverage.monThreshold) == "number" then tTarget.tAverage.monThreshold = tSaved.tAverage.monThreshold end
					if type(tSaved.tAverage.nPercent) == "number" then tTarget.tAverage.nPercent = tSaved.tAverage.nPercent end
					if type(tSaved.tAverage.nHistorySize) == "number" then tTarget.tAverage.nHistorySize = tSaved.tAverage.nHistorySize end
					if type(tSaved.tAverage.seqPriceHistory) == "table" then tTarget.tAverage.seqPriceHistory = tSaved.tAverage.seqPriceHistory end
				end

				if type(tSaved.tPuny) == "table" then
					if type(tSaved.tPuny.bEnabled) == "boolean" then tTarget.tPuny.bEnabled = tSaved.tPuny.bEnabled end
					if type(tSaved.tPuny.monThreshold) == "number" then tTarget.tPuny.monThreshold = tSaved.tPuny.monThreshold end
				end				
			end
		end
	end
end

-- Returns a set of current-version default settings for all currency types
function Settings:DefaultSettings()
	log:debug("Preparing default settings")

	-- Contains individual settings for all currency types
	local tAllSettings = {}

	-- Initially populate all currency type with "conservative" / generic default values
	for _,v in ipairs(addon.seqCurrencies) do
		local t = {}
		tAllSettings[v.strName] = t
		
		-- Fixed
		t.tFixed = {}
		t.tFixed.bEnabled = true		-- Fixed threshold enabled
		t.tFixed.monThreshold = 0		-- No amount configured
		
		-- Empty coffers
		t.tEmptyCoffers = {}
		t.tEmptyCoffers.bEnabled = true	-- Empty Coffers threshold enabled
		t.tEmptyCoffers.nPercent = 50	-- Breach at 50% of current avail currency
		
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

	return tAllSettings	
end

-- When the settings window is closed via Cancel, revert all changed values to current config
function Settings:OnCancelSettings()
	-- Hide settings window, without saving any entered values. 
	-- Settings GUI will revert to old values on next OnConfigure
	self.wndSettings:Show(false, true)	
end

-- Extracts settings fields one by one, and updates tSettings accordingly.
function Settings:OnAcceptSettings()
	-- Hide settings window
	self.wndSettings:Show(false, true)
	
	-- For all currencies, extract UI values into settings
	for _,v in ipairs(addon.seqCurrencies) do
		self:AcceptSettingsForCurrency(v.wndPanel, addon.tSettings[v.strName])
	end
end

function Settings:AcceptSettingsForCurrency(wndPanel, tSettings)
	
	--[[ FIXED THRESHOLD SETTINGS ]]	
	
	local wndFixedSection = wndPanel:FindChild("FixedSection")
	
	-- Fixed threshold checkbox	
	tSettings.tFixed.bEnabled = self:ExtractSettingCheckbox(
		wndFixedSection:FindChild("EnableButton"),
		"tFixed.bEnabled",
		tSettings.tFixed.bEnabled)
	
	-- Fixed threshold amount
	tSettings.tFixed.monThreshold = self:ExtractSettingAmount(
		wndFixedSection:FindChild("Amount"),
		"tFixed.monThreshold",
		tSettings.tFixed.monThreshold)


	--[[ EMPTY COFFERS SETTINGS ]]
	
	local wndEmptyCoffersSection = wndPanel:FindChild("EmptyCoffersSection")
	
	-- Empty coffers threshold checkbox	
	tSettings.tEmptyCoffers.bEnabled = self:ExtractSettingCheckbox(
		wndEmptyCoffersSection:FindChild("EnableButton"),
		"tEmptyCoffers.bEnabled",
		tSettings.tEmptyCoffers.bEnabled)
	
	-- Empty coffers percentage
	tSettings.tEmptyCoffers.nPercent = self:ExtractOrRevertSettingNumber(
		wndEmptyCoffersSection:FindChild("PercentEditBox"),
		"tEmptyCoffers.nPercent",
		tSettings.tEmptyCoffers.nPercent,
		1, 100)
	
	
	--[[ AVERAGE THRESHOLD SETTINGS ]]

	local wndAverageSection = wndPanel:FindChild("AverageSection")
	
	-- Average threshold checkbox
	tSettings.tAverage.bEnabled = self:ExtractSettingCheckbox(
		wndAverageSection:FindChild("EnableButton"),
		"tAverage.bEnabled",
		tSettings.tAverage.bEnabled)

	-- Average percent number input field
	tSettings.tAverage.nPercent = self:ExtractOrRevertSettingNumber(
		wndAverageSection:FindChild("PercentEditBox"),
		"tAverage.nPercent",
		tSettings.tAverage.nPercent,
		1, 100)

	
	--[[ PUNY AMOUNT SETTINGS ]]
	
	local wndPunySection = wndPanel:FindChild("PunySection")

	-- Puny threshold checkbox
	tSettings.tPuny.bEnabled = self:ExtractSettingCheckbox(
		wndPunySection:FindChild("EnableButton"),
		"tPuny.bEnabled",
		tSettings.tPuny.bEnabled)
	
	-- Puny threshold limit (per level)
	tSettings.tPuny.monThreshold = self:ExtractSettingAmount(
		wndPunySection:FindChild("Amount"),
		"tPuny.monThreshold",
		tSettings.tPuny.monThreshold)
end

-- Extracts text-field as a number within specified bounts. Reverts text field to currentValue if input value is invalid.
function Settings:ExtractOrRevertSettingNumber(wndField, strName, currentValue, minValue, maxValue)
	local textValue = wndField:GetText()
	local newValue = tonumber(textValue)

	-- Input-value must be parsable as a number
	if newValue == nil then
		log:warn("Settings.ExtractOrRevertSettingNumber: Field " .. strName .. ": value '" .. textValue .. "' is not a number, reverting to previous value '" .. currentValue .. "'")
		wndField:SetText(currentValue)
		return currentValue
	end
	
	-- Input-value is a number, but must be within specified bounds
	if newValue < minValue or newValue > maxValue then
		log:warn("Settings.ExtractOrRevertSettingNumber: Field " .. strName .. ": value '" .. newValue .. "' is not within bounds [" .. minValue .. "-" .. maxValue .. "], reverting to previous value '" .. currentValue .. "'")
		wndField:SetText(currentValue)
		return currentValue
	end
	
	-- Input-value is accepted, log if changed or not
	if newValue == currentValue then
		log:debug("Settings.ExtractOrRevertSettingNumber: Field " .. strName .. ": value '" .. newValue .. "' is unchanged")
	else
		log:info("Settings.ExtractOrRevertSettingNumber: Field " .. strName .. ": value '" .. newValue .. "' updated from previous value '" .. currentValue .. "'")
	end
	return newValue;
end

-- Extracts an amount-field, and logs if it is changed from currentValue
function Settings:ExtractSettingAmount(wndField, strName, currentValue)
	local newValue = wndField:GetAmount()
	if newValue == currentValue then
		log:debug("Settings.ExtractSettingAmount: Field " .. tostring(strName) .. ": value '" .. tostring(newValue) .. "' is unchanged")
	else
		log:info("Settings.ExtractSettingAmount: Field " .. tostring(strName) .. ": value '" .. tostring(newValue) .. "' updated from previous value '" .. tostring(currentValue) .. "'")
	end
	return newValue
end

-- Extracts a checkbox-field, and logs if it is changed from currentValue
function Settings:ExtractSettingCheckbox(wndField, strName, currentValue)
	local newValue = wndField:IsChecked()
	if newValue == currentValue then
		log:debug("Settings.ExtractSettingCheckbox: Field " .. strName .. ": value '" .. tostring(newValue) .. "' is unchanged")
	else
		log:info("Settings.ExtractSettingCheckbox: Field " .. strName .. ": value '" .. tostring(newValue) .. "' updated from previous value '" .. tostring(currentValue) .. "'")
	end
	return newValue
end


---------------------------------------------------------------------------------------------------
-- Currency tab selection
---------------------------------------------------------------------------------------------------

function Settings:OnCurrencySelection(wndHandler, wndControl)
	local tCurrency = wndHandler:GetData()
		for k,v in ipairs(addon.seqCurrencies) do
		if v.strName == tCurrency.strName then
			v.wndPanel:Show(true, true)
		else
			v.wndPanel:Show(false, true)
		end
	end	
	self:UpdateBalance()
end
