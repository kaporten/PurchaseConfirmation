local L = Apollo.GetPackage("GeminiLocale-1.0").tPackage:NewLocale("PurchaseConfirmation", "koKR")
if not L then return end

--[[ Proper Translations ]]--

--[[ Google Translations ]]--

	--[[ CONFIRMATION DIALOG ]]

-- Main window labels
L["Dialog_WindowTitle"] = "구매 확인"
L["Dialog_ButtonConfirm"] = "매수"
L["Dialog_ButtonCancel"] = "취소"
L["Dialog_ButtonDetails"] = "세부"

-- Detail window foldout labels
L["Dialog_DetailsLabel_Fixed"] = "고정 된 양"
L["Dialog_DetailsLabel_Average"] = "평균 지출"
L["Dialog_DetailsLabel_EmptyCoffers"] = "빈 금고"

-- Detail window foldout tooltips
L["Dialog_DetailsTooltip_Breached"] = "임계 값 위반된다"
L["Dialog_DetailsTooltip_NotBreached"] = "임계 값이 위반되지 않는다"


	--[[ SETTINGS WINDOW ]]

-- Main window labels
L["Settings_WindowTitle"] = "구매 확인 설정"
L["Settings_ButtonAccept"] = "동의"
L["Settings_ButtonCancel"] = "취소"
L["Settings_Balance"] = "현재 잔액"

-- Shortish currency descriptions, that will fit the tab-button layout
L["Settings_TabCurrency_Credits"] = "Credits"
L["Settings_TabCurrency_Renown"] = "Renown"
L["Settings_TabCurrency_Prestige"] = "Prestige"
L["Settings_TabCurrency_CraftingVouchers"] = "Crafting"
L["Settings_TabCurrency_ElderGems"] = "Elder Gems"

-- Individual threshold labels and descriptions
L["Settings_Threshold_Fixed_Enable"] = "고정 된 상한 임계 값을 사용 :"
L["Settings_Threshold_Fixed_Description"] = "항상이 금액 이상 구매에 대한 확인을 요청합니다."

L["Settings_Threshold_Puny_Enable"] = "아주 작은 양의 임계 값을 사용 :"
L["Settings_Threshold_Puny_Description"] = "이 금액 아래의 구매에 대한 확인을 요청하지 마십시오, 평균 지출 임계 값 계산에 구입을 사용하지 않습니다."

L["Settings_Threshold_Average_Enable"] = "평균 지출 임계 값을 사용 [1-100%]:"
L["Settings_Threshold_Average_Description"] = "구입 가격이 최근 구매 내역의 평균 위의 지정된 비율보다는 더 많은 것 인 경우에 확인을 요청합니다."

L["Settings_Threshold_EmptyCoffers_Enable"] = "빈 금고 임계 값을 사용 [1-100%]:"
L["Settings_Threshold_EmptyCoffers_Description"] = "구입은 현재 잔액의 지정된 비율보다 비용이 경우 요청 확인."