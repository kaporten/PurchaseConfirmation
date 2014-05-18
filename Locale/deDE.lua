local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("PurchaseConfirmation", "deDE")
if not L then return end

--[[ Proper Translations ]]--

--[[ Google Translations ]]--


	--[[ CONFIRMATION DIALOG ]]

-- Main window labels
L["Dialog_ButtonDetails"] = "Detail"

-- Detail window foldout labels
L["Dialog_DetailsLabel_Fixed"] = "Festbetrag"
L["Dialog_DetailsLabel_Average"] = "Durchschnittsausgaben"
L["Dialog_DetailsLabel_EmptyCoffers"] = "Leere Kassen"

-- Detail window foldout tooltips
L["Dialog_DetailsTooltip_Breached"] = "Schwelle verletzt"
L["Dialog_DetailsTooltip_NotBreached"] = "Schwelle nicht verletzt"
L["Dialog_DetailsTooltip_Disabled"] = "Schwelle ist deaktiviert"


	--[[ SETTINGS WINDOW ]]

-- Main window labels
L["Settings_WindowTitle"] = "PurchaseConfirmation Einstellungen"
L["Settings_Balance"] = "Aktuelle Bilanz"

-- Individual threshold labels and descriptions
L["Settings_Threshold_Fixed_Enable"] = "\"Festen oberen\" Schwelle aktivieren:"
L["Settings_Threshold_Fixed_Description"] = "Verlangen immer Bestätigung für Einkäufe über diesen Betrag."

L["Settings_Threshold_Puny_Enable"] = "\"Mickrigen Betrag\" Schwelle aktivieren:"
L["Settings_Threshold_Puny_Description"] = "Nie fordern Bestätigung für Einkäufe unter diesem Betrag, und verwenden Sie nicht den Kauf in \"durchschnittlichen Ausgaben\" Schwelle Berechnungen."

L["Settings_Threshold_Average_Enable"] = "\"Durchschnittlichen Ausgaben\" Schwelle aktivieren [1-100%]:"
L["Settings_Threshold_Average_Description"] = "Bestätigung anfordern, wenn Kaufpreis ist mehr als die angegebene Prozentsatz über dem Durchschnitt des letzten Kauf-Geschichte."

L["Settings_Threshold_EmptyCoffers_Enable"] = "\"Leeren Kassen\" Schwelle aktivieren [1-100%]:"
L["Settings_Threshold_EmptyCoffers_Description"] = "Bestätigung anfordern, wenn Kauf mehr kosten als der angegebene Prozentsatz von Ihren aktuellen Kontostand."

L["Settings_Modules_Button"] = "Module"


	--[[ MODULES ]]

L["Modules_WindowTitle"] = "PurchaseConfirmation Module"

L["Module_Enable"] = "Aktivieren Modul"
	
L["Module_VendorPurchase_Title"] = "Verkäufer: Kauf"
L["Module_VendorPurchase_Description"] = "Dieses Modul fängt Artikel Einkäufe in der Haupt-Verkäufer-Addon. Dies umfasst alle regulären Hersteller, wie zB allgemeine Ware-Anbieter, während Nexus verstreut."
L["Module_VendorPurchase_DialogHeader"] = "Confirm Purchase"
L["Module_VendorPurchase_DialogAcceptButton"] = "Purchase"

L["Module_VendorRepair_Title"] = "Verkäufer: Reparieren"
L["Module_VendorRepair_Description"] = "Dieses Modul Abschnitte ein-und all-Artikel Reparaturen in der Haupt-Verkäufer-Addon durchgeführt. Es muss nicht fordern Bestätigung für die Auto-Reparaturen durch Addon 'JunkIt' initiiert."
L["Module_VendorRepair_DialogHeader"] = "Confirm Repair"
L["Module_VendorRepair_DialogAcceptButton_Single"] = "Repair"
L["Module_VendorRepair_DialogAcceptButton_All"] = "Repair All"