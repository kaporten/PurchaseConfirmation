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

L["Modules_WindowTitle"] = "Module"

L["Module_Enable"] = "Aktivieren"
L["Module_Failure_Addon_Missing"] = "Erforderliche Addon %q nicht gefunden."
	
L["Module_VendorPurchase_Title"] = "Verkäufer: Kauf"
L["Module_VendorPurchase_Description"] = "Dieses Modul fängt Artikel Einkäufe in der Haupt-Verkäufer-Addon. Dies umfasst alle regulären Hersteller, wie zB allgemeine Ware-Anbieter, während Nexus verstreut."

L["Module_VendorRepair_Title"] = "Verkäufer: Reparieren"
L["Module_VendorRepair_Description"] = "Dieses Modul Abschnitte ein-und all-Artikel Reparaturen in der Haupt-Verkäufer-Addon durchgeführt. Es muss nicht fordern Bestätigung für die Auto-Reparaturen durch Addon 'JunkIt' initiiert."

L["Module_HousingBuyToCrate_Title"] = "Gehäuse: Um Kiste kaufen"
L["Module_HousingBuyToCrate_Description"] = "Dieses Modul fängt Kauf Gehäuse Kultur Elemente (um Ihre Kiste). Es hat keinen Einfluss Housing Artikel Reparatur / Platzierungskosten, nur den Kauf, um Ihre Kiste."

L["Module_SpaceStashBankSlot_Title"] = "SpaceStash: Kaufen Bank-Slot"
L["Module_SpaceStashBankSlot_Description"] = "Wenn Sie das Addon SpaceStash sind, wird diese Bank-Slot-Käufe abzufangen."

L["Module_LilVendorPurchase_Title"] = "LilVendor: Kauf"
L["Module_LilVendorPurchase_Description"] = "Wenn Sie das Addon LilVendor sind, wird diese Käufe abzufangen. Gleiche wie für die Lager-Verkauf-Addon, mit Ausnahme der Ersatz LilVendor Addon."

L["Module_ViragsMultibuyerPurchase_Title"] = "ViragsMultibyer: Kauf"
L["Module_ViragsMultibuyerPurchase_Description"] = "Wenn Sie das Addon ViragsMultibyer sind, wird diese Käufe vor, die die ViragsMultibuyer internen Bestätigungsdialog abfangen."

L["Module_CostumesDye_Title"] = "Kostüme: Färben"
L["Module_CostumesDye_Description"] = "Sieht gut aus ist niemals billig, vor allem nicht in Wildstar. Mit diesem Modul können Sie sich zweimal überlegen, vor dem Ablegen 2 Platinum auf diesem süßen blutroten Färbe."
