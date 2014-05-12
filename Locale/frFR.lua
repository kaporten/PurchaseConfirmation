local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("PurchaseConfirmation", "frFR")
if not L then return end

--[[ Proper Translations ]]--

--[[ Google Translations ]]--


	--[[ CONFIRMATION DIALOG ]]

-- Main window labels
L["Dialog_WindowTitle"] = "Confirmation d'achat"
L["Dialog_ButtonDetails"] = "Détails"

-- Detail window foldout labels
L["Dialog_DetailsLabel_Fixed"] = "Montant fixe"
L["Dialog_DetailsLabel_Average"] = "Les dépenses moyennes"
L["Dialog_DetailsLabel_EmptyCoffers"] = "Caisses vides"

-- Detail window foldout tooltips
L["Dialog_DetailsTooltip_Breached"] = "Le seuil est violé"
L["Dialog_DetailsTooltip_NotBreached"] = "Seuil n'est pas violé"
L["Dialog_DetailsTooltip_Disabled"] = "Le seuil est d�sactiv�"


	--[[ SETTINGS WINDOW ]]

-- Main window labels
L["Settings_WindowTitle"] = "PurchaseConfirmation Paramètres"
L["Settings_Balance"] = "Balance courante"

-- Individual threshold labels and descriptions
L["Settings_Threshold_Fixed_Enable"] = "Activer seuil \"supérieure fixe\":"
L["Settings_Threshold_Fixed_Description"] = "Toujours demander confirmation pour les achats supérieurs à ce montant."

L["Settings_Threshold_Puny_Enable"] = "Activer seuil de \"montant chétif\":"
L["Settings_Threshold_Puny_Description"] = "Ne jamais demander confirmation pour les achats inférieurs à ce montant, et de ne pas utiliser l'achat en \"dépenses moyenne\" calcul des seuils."

L["Settings_Threshold_Average_Enable"] = "Activer seuil \"de la dépense moyenne\" [1-100%]:"
L["Settings_Threshold_Average_Description"] = "Demander confirmation si le prix d'achat est supérieur au pourcentage indiqué ci-dessus de la moyenne de l'histoire de votre achat récent."

L["Settings_Threshold_EmptyCoffers_Enable"] = "Activer \"caisses vides\" seuil [1-100%]:"
L["Settings_Threshold_EmptyCoffers_Description"] = "Demande confirmation si l'achat a coûté plus que le pourcentage précis de votre solde actuel."