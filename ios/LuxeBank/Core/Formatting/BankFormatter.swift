import Foundation

/// Formats money and dates for display. Amounts are always `Decimal` (spec 6.5).
enum BankFormatter {
    private static let numberFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        formatter.groupingSize = 3
        formatter.decimalSeparator = "."
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.roundingMode = .halfUp
        return formatter
    }()

    /// "4,825,450.75" — absolute value, two decimals.
    static func amount(_ value: Decimal) -> String {
        numberFormatter.string(from: abs(value) as NSDecimalNumber) ?? "0.00"
    }

    /// "฿4,825,450.75", or "−฿580.00" for negative values.
    static func currency(_ value: Decimal) -> String {
        (value < 0 ? "−" : "") + "฿" + amount(value)
    }

    /// "+12,800.00" / "−580.00" for transaction lists.
    static func signedAmount(_ value: Decimal) -> String {
        (value < 0 ? "−" : "+") + amount(value)
    }

    /// Splits "฿4,825,450.75" into ("฿4,825,450", ".75") so the satang can be dimmed.
    static func currencyParts(_ value: Decimal) -> (main: String, fraction: String) {
        let full = currency(value)
        guard let dot = full.lastIndex(of: ".") else { return (full, "") }
        return (String(full[..<dot]), String(full[dot...]))
    }

    /// "6.8%"
    static func percent(_ value: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 1
        return (formatter.string(from: value as NSDecimalNumber) ?? "0") + "%"
    }

    /// "วันนี้ 19:10" for today, otherwise a short day and month such as "9 ต.ค.".
    static func transactionDate(
        _ date: Date,
        now: Date = Date(),
        calendar: Calendar = .current,
        locale: Locale = .current
    ) -> String {
        if calendar.isDate(date, inSameDayAs: now) {
            // Banking apps in Thailand show a 24-hour clock regardless of locale.
            let time = date.formatted(
                Date.VerbatimFormatStyle(
                    format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                    locale: locale,
                    timeZone: calendar.timeZone,
                    calendar: calendar
                )
            )
            return String(localized: "date.todayAt \(time)", locale: locale)
        }
        return date.formatted(style(locale: locale, calendar: calendar).day().month(.abbreviated))
    }

    private static func style(locale: Locale, calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
