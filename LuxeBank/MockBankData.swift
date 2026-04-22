import SwiftUI

enum MockBankData {
    static let account = AccountSummary(
        name: "บัญชีหลัก พรีเมียร์",
        maskedNumber: "•••• 4289",
        balance: 4_825_450.75,
        changeRate: 6.8,
        accent: BankTheme.softGold
    )

    static let actions: [QuickAction] = [
        QuickAction(title: "โอนเงิน", icon: "arrow.up.right"),
        QuickAction(title: "เติมเงิน", icon: "plus"),
        QuickAction(title: "จ่ายบิล", icon: "doc.text"),
        QuickAction(title: "ลงทุน", icon: "chart.line.uptrend.xyaxis")
    ]

    static let transactions: [TransactionItem] = [
        TransactionItem(
            merchant: "Sarnies Bangkok",
            category: "อาหารและเครื่องดื่ม",
            dateText: "วันนี้ 19:10",
            amount: -580.00,
            icon: "fork.knife",
            tint: Color(red: 0.94, green: 0.70, blue: 0.42)
        ),
        TransactionItem(
            merchant: "คอนโด เดอะ ริเวอร์",
            category: "ค่าเช่าที่พัก",
            dateText: "18 เม.ย. 09:30",
            amount: -28_500.00,
            icon: "building.2.fill",
            tint: Color(red: 0.43, green: 0.74, blue: 0.98)
        ),
        TransactionItem(
            merchant: "กองทุนเปิด Wealth Plus",
            category: "ผลตอบแทนการลงทุน",
            dateText: "17 เม.ย. 14:25",
            amount: 12_800.00,
            icon: "sparkles",
            tint: Color(red: 0.48, green: 0.88, blue: 0.67)
        ),
        TransactionItem(
            merchant: "BTS Rabbit เติมเที่ยว",
            category: "เดินทาง",
            dateText: "15 เม.ย. 08:00",
            amount: -1_250.00,
            icon: "car.fill",
            tint: Color(red: 0.95, green: 0.55, blue: 0.59)
        )
    ]

    static let insights: [SpendingInsight] = [
        SpendingInsight(title: "ไลฟ์สไตล์", amountText: "฿38,200 / ฿50,000", progress: 0.76),
        SpendingInsight(title: "ท่องเที่ยว", amountText: "฿12,400 / ฿25,000", progress: 0.50),
        SpendingInsight(title: "เป้าหมายเงินออม", amountText: "฿186,000 / ฿240,000", progress: 0.78)
    ]
}
