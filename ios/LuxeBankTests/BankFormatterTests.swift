import Foundation
import Testing
@testable import LuxeBank

struct BankFormatterTests {
    @Test func formatsCurrencyWithGroupingAndTwoDecimals() {
        #expect(BankFormatter.currency(Decimal(482_545_075) / 100) == "฿4,825,450.75")
        #expect(BankFormatter.currency(Decimal(12_345) / 10) == "฿1,234.50")
        #expect(BankFormatter.currency(0) == "฿0.00")
    }

    @Test func prefixesNegativeCurrencyWithMinusSign() {
        #expect(BankFormatter.currency(-580) == "−฿580.00")
    }

    @Test func signsTransactionAmounts() {
        #expect(BankFormatter.signedAmount(-28_500) == "−28,500.00")
        #expect(BankFormatter.signedAmount(12_800) == "+12,800.00")
    }

    @Test func splitsSatangFromBaht() {
        let parts = BankFormatter.currencyParts(Decimal(482_545_075) / 100)
        #expect(parts.main == "฿4,825,450")
        #expect(parts.fraction == ".75")
    }

    @Test func roundsHalfUpToTwoDecimals() {
        #expect(BankFormatter.amount(Decimal(1_005) / 1_000) == "1.01")
    }

    @Test func formatsPercent() {
        #expect(BankFormatter.percent(Decimal(68) / 10) == "6.8%")
        #expect(BankFormatter.percent(67) == "67%")
    }

    @Test func showsTimeForTodayAndDayMonthOtherwise() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Asia/Bangkok"))
        let locale = Locale(identifier: "en_US")
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 20)))
        let today = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 19, minute: 10)))
        let earlier = try #require(calendar.date(from: DateComponents(year: 2026, month: 10, day: 9, hour: 9, minute: 30)))

        #expect(BankFormatter.transactionDate(today, now: now, calendar: calendar, locale: locale).contains("19:10"))
        #expect(BankFormatter.transactionDate(earlier, now: now, calendar: calendar, locale: locale).contains("9"))
    }
}
