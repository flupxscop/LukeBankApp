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
            return String(localized: "date.todayAt \(time(date, calendar: calendar, locale: locale))", locale: locale)
        }
        return date.formatted(style(locale: locale, calendar: calendar).day().month(.abbreviated))
    }

    /// "19:10" — banking apps in Thailand show a 24-hour clock regardless of locale.
    static func time(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        date.formatted(
            Date.VerbatimFormatStyle(
                format: "\(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)):\(minute: .twoDigits)",
                locale: locale,
                timeZone: calendar.timeZone,
                calendar: calendar
            )
        )
    }

    /// History section title: "วันนี้ · 10 ต.ค." for today, otherwise "9 ต.ค. 2569".
    static func dayHeader(_ day: Date, now: Date = Date(), calendar: Calendar = .current, locale: Locale = .current) -> String {
        if calendar.isDate(day, inSameDayAs: now) {
            let short = day.formatted(style(locale: locale, calendar: calendar).day().month(.abbreviated))
            return String(localized: "date.todayHeader \(short)", locale: locale)
        }
        return day.formatted(style(locale: locale, calendar: calendar).day().month(.abbreviated).year())
    }

    /// "9 ต.ค. 2569 · 09:30" for the transaction detail.
    static func dateTime(_ date: Date, calendar: Calendar = .current, locale: Locale = .current) -> String {
        date.formatted(style(locale: locale, calendar: calendar).day().month(.abbreviated).year())
            + " · " + time(date, calendar: calendar, locale: locale)
    }

    private static func style(locale: Locale, calendar: Calendar) -> Date.FormatStyle {
        Date.FormatStyle(locale: locale, calendar: calendar, timeZone: calendar.timeZone)
    }
}
