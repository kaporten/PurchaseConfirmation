local L = Apollo.GetPackage("Gemini:Locale-1.0").tPackage:NewLocale("PurchaseConfirmation", "koKR")
if not L then return end

--[[ Proper Translations ]]--

--[[ Google Translations ]]--


	--[[ CONFIRMATION DIALOG ]]

-- Main window labels
L["Dialog_WindowTitle"] = "구매 확인"
L["Dialog_ButtonDetails"] = "세부"

-- Detail window foldout labels
L["Dialog_DetailsLabel_Fixed"] = "고정 된 양"
L["Dialog_DetailsLabel_Average"] = "평균 지출"
L["Dialog_DetailsLabel_EmptyCoffers"] = "빈 금고"

-- Detail window foldout tooltips
L["Dialog_DetailsTooltip_Breached"] = "임계 값 위반된다"
L["Dialog_DetailsTooltip_NotBreached"] = "임계 값이 위반되지 않는다"
L["Dialog_DetailsTooltip_Disabled"] = "임계 값을 사용할 수"


	--[[ SETTINGS WINDOW ]]

-- Main window labels
L["Settings_WindowTitle"] = "구매 확인 설정"
L["Settings_Balance"] = "현재 잔액"

-- Individual threshold labels and descriptions
L["Settings_Threshold_Fixed_Enable"] = "고정 된 상한 임계 값을 사용 :"
L["Settings_Threshold_Fixed_Description"] = "항상이 금액 이상 구매에 대한 확인을 요청합니다."

L["Settings_Threshold_Puny_Enable"] = "아주 작은 양의 임계 값을 사용 :"
L["Settings_Threshold_Puny_Description"] = "이 금액 아래의 구매에 대한 확인을 요청하지 마십시오, 평균 지출 임계 값 계산에 구입을 사용하지 않습니다."

L["Settings_Threshold_Average_Enable"] = "평균 지출 임계 값을 사용 [1-100%]:"
L["Settings_Threshold_Average_Description"] = "구입 가격이 최근 구매 내역의 평균 위의 지정된 비율보다는 더 많은 것 인 경우에 확인을 요청합니다."

L["Settings_Threshold_EmptyCoffers_Enable"] = "빈 금고 임계 값을 사용 [1-100%]:"
L["Settings_Threshold_EmptyCoffers_Description"] = "구입은 현재 잔액의 지정된 비율보다 비용이 경우 요청 확인."


	--[[ MODULES ]]
	
L["Module_VendorPurchase_Title"] = "공급 업체: 매수"
L["Module_VendorPurchase_Description"] = "주요 벤더 애드온에이 모듈을 차단 항목을 구매. 이 관계에 흩어져 등 일반 제품 공급 업체 등 모든 일반 업체를 다룹니다."

L["Module_VendorRepair_Title"] = "공급 업체: 수리"
L["Module_VendorRepair_Description"] = "주요 벤더 애드온에서 수행이 모듈을 차단 단일 및 모든 항목을 수리. 이 애드온 'JunkIt'에 의해 시작 자동 수리에 대한 확인을 요청하지 않습니다."