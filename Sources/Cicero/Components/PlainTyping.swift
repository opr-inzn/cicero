import AppKit

enum PlainTyping {
    private typealias Become = @convention(c) (NSResponder, Selector) -> Bool
    private static var isInstalled = false
    private static let none = NSTextContentType(rawValue: "none")

    static func install() {
        guard !isInstalled else { return }
        isInstalled = true
        // AppKit adds AutoFill to the context menu of every editable text view, whatever its content type, unless this is off before the first menu opens.
        UserDefaults.standard.register(defaults: ["NSAutoFillSystemInsertMenuEnabled": false])
        // Before AppKit's own becomeFirstResponder, which is where AutoFill and the field editor's setup look at these.
        hook(NSTextView.self) { view in
            guard let textView = view as? NSTextView, textView.isEditable else { return }
            turnOff(in: textView)
        }
        hook(NSTextField.self) { view in
            guard let field = view as? NSTextField, field.isEditable else { return }
            field.isAutomaticTextCompletionEnabled = false
            if field.contentType == nil { field.contentType = none }
        }
    }

    private static func hook(_ type: AnyClass, before: @escaping (NSResponder) -> Void) {
        let selector = #selector(NSResponder.becomeFirstResponder)
        guard let method = class_getInstanceMethod(type, selector) else { return }
        let appKit = unsafeBitCast(method_getImplementation(method), to: Become.self)
        let become: @convention(block) (NSResponder) -> Bool = { responder in
            before(responder)
            return appKit(responder, selector)
        }
        // Added on the class itself, so the hook on NSTextView doesn't also run for NSResponder's other subclasses.
        if !class_addMethod(type, selector, imp_implementationWithBlock(become), method_getTypeEncoding(method)) {
            method_setImplementation(method, imp_implementationWithBlock(become))
        }
    }

    private static func turnOff(in textView: NSTextView) {
        textView.enabledTextCheckingTypes = 0
        textView.isContinuousSpellCheckingEnabled = false
        textView.isGrammarCheckingEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticLinkDetectionEnabled = false
        textView.isAutomaticDataDetectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.smartInsertDeleteEnabled = false
        textView.inlinePredictionType = .no
        textView.writingToolsBehavior = .none
        if textView.contentType == nil { textView.contentType = none }
    }
}
