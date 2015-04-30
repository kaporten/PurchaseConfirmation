require "Apollo"
require "Window"

--[[
	Various functions for controlling the settings.
]]

-- GeminiLocale
local locale = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

-- Register module as package
local Settings = {}
Apollo.RegisterPackage(Settings, "PurchaseConfirmation:Settings", 1, {"PurchaseConfirmation"})

-- "glocals" set during Init
local addon, log

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
	
	self.xmlDoc = XmlDoc.CreateFromFile("Settings.xml")
	self.xmlDoc:RegisterCallback("OnDocLoaded", self)
	
	return self
end

--- Called when XML document is fully loaded, ready to produce forms.
function Settings:OnDocLoaded()	
	log:info("Loading Settings GUI")
	
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
		log:error("OnDocLoaded: Error loading main Settings form.")
		return
	end	
	self.wndSettings:Show(false, true)
	self:LocalizeSettings(self.wndSettings)
	self.wndSettings:FindChild("VersionLabel"):SetText(self:GetVersionString())
	
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
			log:error("OnDocLoaded: Error loading Settings currency-panel form.")
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

	-- Build indexed list of modules
	log:debug("Sorting modules according to status and name")
	local sortedModules = {}	
	for _,m in pairs(addon.modules) do
		table.insert(sortedModules, m)
	end
	
	-- Sort indexed list of modules as ok>failed,name
	table.sort(sortedModules, 
		function(a, b)
			if a.bFailed == false and b.bFailed == true then return true end
			if a.bFailed == true and b.bFailed == false then return false end
			return a.MODULE_ID < b.MODULE_ID
		end
	)
	log:debug("Sorted list of modules ready")
		
	-- Add module line to module-config window, for each available module. 	
	self.wndSettings:FindChild("ModulesPopout"):Show(false, true)
	for _,m in ipairs(sortedModules) do
		log:info("Loading form for module " .. m.MODULE_ID)
		local wnd = Apollo.LoadForm(self.xmlDoc, "ModulesLineForm", self.wndSettings:FindChild("ModulesContainer"), self)
		if wnd == nil then
			Apollo.AddAddonErrorText(self, "Could not load the ModulesFormLine window")
			log:error("Error loading Settings Module-line form")
			return
		end
		self:LocalizeModuleEntry(wnd, m)
		wnd:SetData(m.MODULE_ID)
	end
	self.wndSettings:FindChild("ModulesContainer"):ArrangeChildrenVert()

	self.xmlDoc = nil
	log:info("Settings GUI loaded successfully")
end


--- Converts the addons {minor, major, bugfix} version array to a .-seperated String
function Settings:GetVersionString()
	local str = "v"
	local first = true
	for _,v in ipairs(addon.ADDON_VERSION) do
		if first then 
			str = str .. v
			first = false
		else 
			str = str .. "." .. v
		end
	end
	return str
end


function Settings:LocalizeModuleEntry(wnd, m)
	-- m.strTitle + m.strDescription are prelocalized during module initialization
	wnd:FindChild("EnableButtonLabel"):SetText(tostring(locale["Module_Enable"]) .. " '" .. tostring(m.strTitle) .. "'")	
	wnd:FindChild("Description"):SetText(m.strDescription)
end

--- Localizes the main Settings window
function Settings:LocalizeSettings(wnd)
	local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:GetLocale("PurchaseConfirmation")

	wnd:FindChild("WindowTitle"):SetText(L["Settings_WindowTitle"])
	wnd:FindChild("BalanceLabel"):SetText(L["Settings_Balance"])
	
	wnd:FindChild("ModulesPopoutTitle"):SetText(locale["Modules_WindowTitle"])
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
	self:PopulateModules()

	self.wndSettings:Show(true, false)
	self.wndSettings:ToFront()
end

-- Populates the settings window with current configuration values (for all currency types)
function Settings:PopulateSettingsWindow()
	-- Loop over all supported currencytypes, populate each one with current settings
	for _,currencyType in ipairs(addon.seqCurrencies) do
		local wndCurrency = currencyType.wndPanel
		local tCurrencySettings = addon.tSettings.Currencies[currencyType.strName]
		self:PopulateSettingsWindowForCurrency(wndCurrency, tCurrencySettings)
	end
end

function Settings:UpdateBalance()
	-- Find checked (displayed) currency type, update balance window
	local tCurrency = self.wndSettings:FindChild("CurrencySelectorSection"):GetRadioSelButton("PurchaseConfirmation_CurrencySelection"):GetData()
	self.wndSettings:FindChild("Balance"):SetMoneySystem(tCurrency.eType)
	self.wndSettings:FindChild("CurrentBalanceSection"):FindChild("Balance"):SetAmount(GameLib.GetPlayerCurrency(tCurrency.eType):GetAmount(), true)
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

function Settings:PopulateModules()
	for _,wndModule in ipairs(self.wndSettings:FindChild("ModulesContainer"):GetChildren()) do
		local moduleId = wndModule:GetData()
		log:info("Populating module " .. moduleId)
		
		-- Set EnableButton state as defined in settings
		wndModule:FindChild("EnableButton"):SetCheck(addon.tSettings.Modules[moduleId].bEnabled) -- GetData == moduleId
		
		-- Show or hide EnableButton / Failure-cross as according to module failure state
		local module = addon.modules[moduleId]
		local bFailed = module.bFailed	
		wndModule:FindChild("EnableButton"):Show(not bFailed)
		wndModule:FindChild("FailureNotification"):Show(bFailed)		
		
		log:debug("setting tooltip")
		
		-- Set failure tooltip if module failed
		if bFailed == true then			
			wndModule:SetTooltip(module.strFailureMessage)
		else
			wndModule:SetTooltip("")
		end
	end
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
	
	-- Override default values with saved data, if present
	if tSavedData ~= nil then
		self:FillSettings(tSettings, tSavedData)
	end
	
	return tSettings
end

function Settings:FillSettings(tSettings, tSavedData)
	log:debug("Restoring v2.3-style saved settings")
	if type(tSavedData) == "table" then -- should be outer settings table	
	
		-- Per-currency configuration
		if type(tSavedData.Currencies) == "table" then
			for _,v in ipairs(addon.seqCurrencies) do
				if type(tSavedData.Currencies[v.strName]) == "table" then -- should be individual currency table table
					local tSaved = tSavedData.Currencies[v.strName] -- assumed present in default settings
					local tTarget = tSettings.Currencies[v.strName]
					
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
		
		-- Per-module configuration
		if type(tSavedData.Modules) == "table" then
			for _,moduleName in pairs(addon.moduleNames) do
				if type(tSavedData.Modules[moduleName]) == "table" then
					local moduleSettings = tSavedData.Modules[moduleName]
					
					-- Enable-boolean
					if type(moduleSettings.bEnabled) == "boolean" then tSettings.Modules[moduleName].bEnabled = moduleSettings.bEnabled end
					
					-- Saved dialog position
					if type(moduleSettings.tPosition) == "table" then tSettings.Modules[moduleName].tPosition = moduleSettings.tPosition end
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
	tAllSettings.Currencies = {}
	tAllSettings.Modules = {}

	-- Initially populate all currency type with "conservative" / generic default values
	for _,v in ipairs(addon.seqCurrencies) do
		local t = {}
		tAllSettings.Currencies[v.strName] = t
		
		-- Fixed
		t.tFixed = {}
		t.tFixed.bEnabled = (v.eType ~= Money.CodeEnumCurrencyType.Credits) -- Fixed threshold enabled for all except normal cash
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
	
	tAllSettings.Modules = {}
	for _,v in pairs(addon.moduleNames) do
		local tModule = {bEnabled = true}
		tAllSettings.Modules[v] = tModule			
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
		self:AcceptSettingsForCurrency(v.wndPanel, addon.tSettings.Currencies[v.strName])
	end
	
	-- For all modules, extract UI values into settings
	for _,v in pairs(addon.modules) do
		self:AcceptSettingsForModule(v.MODULE_ID)
	end

	-- Request that main addon update module status according to new settings
	addon:UpdateModuleStatus()
end

function Settings:AcceptSettingsForModule(moduleId)	
	-- The Settings->ModuleLineForm window instance should have had 
	-- the moduleId set as userdata during load
	local wnd = self.wndSettings:FindChild("ModulesContainer"):FindChildByUserData(moduleId)
	
	if wnd == nil then
		log:error("Could not find settings for module " .. moduleId .. " (specific module not found)")
		return
	end
	
	local btn = wnd:FindChild("EnableButton")
	local name = "Modules[" .. moduleId .."].bEnabled"
	local current = addon.tSettings.Modules[moduleId].bEnabled
		
	addon.tSettings.Modules[moduleId].bEnabled = self:ExtractSettingCheckbox(btn, name, current) 
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

--- Shows the Modules popout
function Settings:OnShowModules(wndHandler, wndControl, eMouseButton)
	local wndModules = self.wndSettings:FindChild("ModulesPopout")
	wndModules:Show(not wndModules:IsVisible(), true)
	wndModules:ToFront()
	log:debug("Toggled modules popout")
end


