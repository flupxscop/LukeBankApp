import SwiftUI
import UIKit

/// Digits-only field that formats while typing (e.g. "1-2345-67890-12-1").
/// UIKit applies each edit synchronously, so fast typing and paste never lose characters,
/// which SwiftUI's `TextField` cannot guarantee when the binding rewrites the text.
struct FormattedDigitsField: UIViewRepresentable {
    @Binding var digits: String
    let maxDigits: Int
    let placeholder: String
    let format: (String) -> String
    @Binding var isFocused: Bool
    var accessibilityIdentifier: String?

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.keyboardType = .numberPad
        field.textContentType = .username
        field.placeholder = placeholder
        field.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: UIFont(name: "Thonburi-Bold", size: 17) ?? .boldSystemFont(ofSize: 17))
        field.adjustsFontForContentSizeCategory = true
        field.textColor = UIColor(BankTheme.ink)
        field.accessibilityIdentifier = accessibilityIdentifier
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        field.addTarget(context.coordinator, action: #selector(Coordinator.didBegin), for: .editingDidBegin)
        field.addTarget(context.coordinator, action: #selector(Coordinator.didEnd), for: .editingDidEnd)
        return field
    }

    func updateUIView(_ field: UITextField, context: Context) {
        context.coordinator.parent = self
        let formatted = format(digits)
        if field.text != formatted { field.text = formatted }
        if isFocused, !field.isFirstResponder {
            DispatchQueue.main.async { field.becomeFirstResponder() }
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: FormattedDigitsField

        init(parent: FormattedDigitsField) {
            self.parent = parent
        }

        func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
            let current = textField.text ?? ""
            guard let swiftRange = Range(range, in: current) else { return false }
            var proposed = current.replacingCharacters(in: swiftRange, with: string)
            // Backspace over a separator removes the digit before it.
            let deletesSeparatorOnly = string.isEmpty && current[swiftRange].allSatisfy { !$0.isNumber }
            if deletesSeparatorOnly, let lastDigit = current[..<swiftRange.lowerBound].lastIndex(where: \.isNumber) {
                proposed = String(current[..<lastDigit]) + String(current[swiftRange.upperBound...])
            }
            let digits = String(proposed.compactMap { $0.wholeNumberValue.map(String.init) }.joined().prefix(parent.maxDigits))
            textField.text = parent.format(digits)
            parent.digits = digits
            return false
        }

        @objc func didBegin() { parent.isFocused = true }
        @objc func didEnd() { parent.isFocused = false }
    }
}
