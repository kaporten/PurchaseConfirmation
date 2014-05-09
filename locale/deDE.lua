local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("PurchaseConfirmation", "deDE")
if not L then return end

--[[ Proper Translations ]]--

--[[ Google Translations ]]--


	--[[ CONFIRMATION DIALOG ]]

-- Main window labels
L["Dialog_WindowTitle"] = "Einkauf Bestätigung"
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