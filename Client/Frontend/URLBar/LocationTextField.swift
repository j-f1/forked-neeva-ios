/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// This code is loosely based on https://github.com/Antol/APAutocompleteTextField

import SwiftUI
import Shared
import Combine

struct LocationTextField: UIViewRepresentable {
    @Binding var text: String
    @Binding var editing: Bool
    let onSubmit: (String) -> ()

    @EnvironmentObject private var historyModel: HistorySuggestionModel

    func makeUIView(context: Context) -> AutocompleteTextField {
        let tf = AutocompleteTextField(text: $text, isActive: $editing, onSubmit: onSubmit, historyModel: historyModel)

        tf.font = UIFont.systemFont(ofSize: 16)
        tf.backgroundColor = .clear
        tf.adjustsFontForContentSizeCategory = true
        tf.clipsToBounds = true
        tf.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        tf.keyboardType = .webSearch
        tf.autocorrectionType = .no
        tf.autocapitalizationType = .none
        tf.returnKeyType = .go
        tf.clearButtonMode = .whileEditing
        tf.textAlignment = .left
        tf.accessibilityIdentifier = "address"
        tf.accessibilityLabel = .URLBarLocationAccessibilityLabel
        tf.enablesReturnKeyAutomatically = true
        tf.attributedPlaceholder =
            NSAttributedString(string: .TabLocationURLPlaceholder, attributes: [NSAttributedString.Key.foregroundColor: UIColor.secondaryLabel])


        tf.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        DispatchQueue.main.async {
            tf.becomeFirstResponder()
            tf.selectAll(nil)
        }
        tf.text = text

        return tf
    }

    func updateUIView(_ tf: AutocompleteTextField, context: Context) {
        tf.onSubmit = onSubmit
        if tf.text != text {
            tf.text = text
        }
        if !editing {
            tf.resignFirstResponder()
        }
    }
}

class AutocompleteTextField: UITextField, UITextFieldDelegate {
    var onSubmit: (String) -> ()

    @Binding private var binding: String
    @Binding private var isActive: Bool
    private var historyModel: HistorySuggestionModel

    private let copyShortcutKey = "c"
    fileprivate var defaultTint = UIColor.ui.adaptive.blue
    private var subscription: AnyCancellable?

    override var accessibilityValue: String? {
        get {
            return (self.text ?? "") + (historyModel.autocompleteSuggestion ?? "")
        }
        set(value) {
            super.accessibilityValue = value
        }
    }

    init(text: Binding<String>, isActive: Binding<Bool>, onSubmit: @escaping (String) -> (), historyModel: HistorySuggestionModel) {
        self._binding = text
        self._isActive = isActive
        self.onSubmit = onSubmit
        self.historyModel = historyModel
        super.init(frame: .zero)
        super.delegate = self

        self.addAction(UIAction { [weak self] _ in
            guard let self = self, let text = self.text else { return }
            self.binding = text
        }, for: .editingChanged)

        subscription = historyModel.$autocompleteSuggestion.sink { [unowned self] suggestion in
            // TODO: unify this logic with LocationEditView
            if let suggestion = suggestion,
               isEditing && markedTextRange == nil,
               let normalized = Optional(normalizeString(self.text ?? "")),
               suggestion.hasPrefix(normalized),
               normalized.count < suggestion.count,
               !normalized.isEmpty {
                tintColor = defaultTint.withAlphaComponent(0)
            } else {
                tintColor = defaultTint
            }
        }
        tintColor = text.wrappedValue.isEmpty ? defaultTint : defaultTint.withAlphaComponent(0)
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var keyCommands: [UIKeyCommand]? {
        return [
            UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: [], action: #selector(self.handleKeyCommand(sender:))),
            UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: [], action: #selector(self.handleKeyCommand(sender:))),
            UIKeyCommand(input: UIKeyCommand.inputEscape, modifierFlags: [], action: #selector(self.handleKeyCommand(sender:))),
            UIKeyCommand(input: copyShortcutKey, modifierFlags: .command, action: #selector(self.handleKeyCommand(sender:)))
        ]
    }

    @objc func handleKeyCommand(sender: UIKeyCommand) {
        guard let input = sender.input else {
            return
        }
        switch input {
        case UIKeyCommand.inputLeftArrow:
            TelemetryWrapper.recordEvent(category: .action, method: .press, object: .keyCommand, extras: ["action": "autocomplete-left-arrow"])
            if historyModel.autocompleteSuggestion != nil {
                applyCompletion()

                // Set the current position to the beginning of the text.
                selectedTextRange = textRange(from: beginningOfDocument, to: beginningOfDocument)
            } else if let range = selectedTextRange {
                if range.start == beginningOfDocument {
                    break
                }

                guard let cursorPosition = position(from: range.start, offset: -1) else {
                    break
                }

                selectedTextRange = textRange(from: cursorPosition, to: cursorPosition)
            }
        case UIKeyCommand.inputRightArrow:
            TelemetryWrapper.recordEvent(category: .action, method: .press, object: .keyCommand, extras: ["action": "autocomplete-right-arrow"])
            if historyModel.autocompleteSuggestion != nil {
                applyCompletion()

                // Set the current position to the end of the text.
                selectedTextRange = textRange(from: endOfDocument, to: endOfDocument)
            } else if let range = selectedTextRange {
                if range.end == endOfDocument {
                    break
                }

                guard let cursorPosition = position(from: range.end, offset: 1) else {
                    break
                }

                selectedTextRange = textRange(from: cursorPosition, to: cursorPosition)
            }
        case UIKeyCommand.inputEscape:
            TelemetryWrapper.recordEvent(category: .action, method: .press, object: .keyCommand, extras: ["action": "autocomplete-cancel"])
            isActive = false
        case copyShortcutKey:
            if let suggestion = historyModel.autocompleteSuggestion {
                UIPasteboard.general.string = suggestion
            } else if let selectedTextRange = self.selectedTextRange {
                UIPasteboard.general.string = self.text(in: selectedTextRange)
            }
        default:
            break
        }
    }

    fileprivate func normalizeString(_ string: String) -> String {
        return string.lowercased().stringByTrimmingLeadingCharactersInSet(CharacterSet.whitespaces)
    }

    /// Commits the completion by setting the text and removing the highlight.
    @discardableResult fileprivate func applyCompletion() -> Bool {
        // Clear the current completion, then set the text without the attributed style.
        guard let suggestion = historyModel.autocompleteSuggestion else { return false }
        binding = suggestion
        // Move the cursor to the end of the completion.
        selectedTextRange = textRange(from: endOfDocument, to: endOfDocument)
        return true
    }

    func textFieldShouldEndEditing(_ textField: UITextField) -> Bool {
        applyCompletion()
        return true
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        let interaction: LogConfig.Interaction = historyModel.autocompleteSuggestion == nil
            ? .NoSuggestion : .AutocompleteSuggestion
        ClientLogger.shared.logCounter(interaction)
        if let text = historyModel.autocompleteSuggestion ?? text {
            if !text.trimmingCharacters(in: .whitespaces).isEmpty {
                onSubmit(text)
                return true
            } else {
                return false
            }
        }
        return true
    }

    override func setMarkedText(_ markedText: String?, selectedRange: NSRange) {
        // Clear the autocompletion if any provisionally inserted text has been
        // entered (e.g., a partial composition from a Japanese keyboard).
        historyModel.clearSuggestion()
        super.setMarkedText(markedText, selectedRange: selectedRange)
    }

    override func deleteBackward() {
        if !historyModel.clearSuggestion() {
            if selectedTextRange != textRange(from: beginningOfDocument, to: beginningOfDocument) {
                historyModel.skipNextAutocomplete()
            }
            super.deleteBackward()
        }
    }

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        applyCompletion()
        super.touchesBegan(touches, with: event)
    }
}

extension AutocompleteTextField: MenuHelperInterface {
    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == MenuHelper.SelectorPasteAndGo {
            return UIPasteboard.general.hasStrings
        }

        return super.canPerformAction(action, withSender: sender)
    }

    @objc func menuHelperPasteAndGo() {
        UIPasteboard.general.asyncString().uponQueue(.main) {
            if let input = $0.successValue as? String {
                self.onSubmit(input)
            }
        }
    }
}
