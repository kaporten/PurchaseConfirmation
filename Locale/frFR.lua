local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("PurchaseConfirmation", "frFR")
if not L then return end

--[[ Proper Translations ]]--

--[[ Google Translations ]]--


	--[[ CONFIRMATION DIALOG ]]

-- Main window labels
L["Dialog_ButtonDetails"] = "Détails"

-- Detail window foldout labels
L["Dialog_DetailsLabel_Fixed"] = "Montant fixe"
L["Dialog_DetailsLabel_Average"] = "Les dépenses moyennes"
L["Dialog_DetailsLabel_EmptyCoffers"] = "Caisses vides"

-- Detail window foldout tooltips
L["Dialog_DetailsTooltip_Breached"] = "Le seuil est violé"
L["Dialog_DetailsTooltip_NotBreached"] = "Seuil n'est pas violé"
L["Dialog_DetailsTooltip_Disabled"] = "Le seuil est désactivé"


	--[[ SETTINGS WINDOW ]]

-- Main window labels
L["Settings_WindowTitle"] = "PurchaseConfirmation Paramètres"
L["Settings_Balance"] = "Balance courante"

-- Individual threshold labels and descriptions
L["Settings_Threshold_Fixed_Enable"] = "Activer seuil \"supérieure fixe\":"
L["Settings_Threshold_Fixed_Description"] = "Toujours demander confirmation pour les achats supérieurs à ce montant."

L["Settings_Threshold_Puny_Enable"] = "Activer seuil \"montant chétif\":"
L["Settings_Threshold_Puny_Description"] = "Ne jamais demander confirmation pour les achats inférieurs à ce montant, et de ne pas utiliser l'achat en \"dépenses moyenne\" calcul des seuils."

L["Settings_Threshold_Average_Enable"] = "Activer seuil \"dépense moyenne\" [1-100%]:"
L["Settings_Threshold_Average_Description"] = "Demander confirmation si le prix d'achat est supérieur au pourcentage indiqué ci-dessus de la moyenne de l'histoire de votre achat récent."

L["Settings_Threshold_EmptyCoffers_Enable"] = "Activer seuil \"caisses vides\" [1-100%]:"
L["Settings_Threshold_EmptyCoffers_Description"] = "Demande confirmation si l'achat a coûté plus que le pourcentage précis de votre solde actuel."

L["Settings_Modules_Button"] = "Modules!"


	--[[ MODULES ]]

L["Modules_WindowTitle"] = "PurchaseConfirmation Modules"

L["Module_Enable"] = "Activer Module"

L["Module_VendorPurchase_Title"] = "Vendeur: Acheter"
L["Module_VendorPurchase_Description"] = "Cet article intercepte module achats dans le principal vendeur-addon. Cela couvre tous les vendeurs réguliers, tels que les fournisseurs Général Marchandises, dispersés à travers Nexus."

L["Module_VendorRepair_Title"] = "Vendeur: Réparation"
L["Module_VendorRepair_Description"] = "Ce module intercepte les réparations simples et tous postes réalisées dans le principal vendeur-addon. Il ne demande pas de confirmation pour l'auto-réparation initiées par addon 'JunkIt."

L["Module_HousingBuyToCrate_Title"] = "Maison: Acheter Pour caisse"
L["Module_HousingBuyToCrate_Description"] = "Ce module intercepte l'achat d'articles de décoration du logement (à votre caisse). Il n'affecte pas le logement élément de coût de réparation / placement, que l'achat de votre caisse."
