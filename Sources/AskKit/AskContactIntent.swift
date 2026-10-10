import AppIntents
import UIKit

public enum AskContactIntentError: Error, CustomLocalizedStringResourceConvertible {
    case unavailable

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .unavailable:
            "That contact action isn't available."
        }
    }
}

/// Builds `tel:` and `mailto:` URLs from the strings on a contact card.
enum AskContactDial {
    static func telURL(_ phone: String) -> URL? {
        let trimmed = phone.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let allowed = CharacterSet(charactersIn: "+0123456789")
        let digits = String(trimmed.unicodeScalars.filter { allowed.contains($0) })
        guard !digits.isEmpty else { return nil }
        return URL(string: "tel:\(digits)")
    }

    static func mailURL(_ email: String) -> URL? {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.contains("@"), !trimmed.contains(where: \.isWhitespace) else { return nil }
        var allowed = CharacterSet.urlPathAllowed
        allowed.insert(charactersIn: "@+")
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: allowed) else { return nil }
        return URL(string: "mailto:\(encoded)")
    }
}

/// Starts a phone call. Shortcuts can pass an ``AskContactEntity`` from Ask. It is not an extra Siri phrase.
public struct OpenAskCallIntent: AppIntent {
    public static let title: LocalizedStringResource = "Call Contact"
    public static let description = IntentDescription("Starts a phone call to a contact.")

    public static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Contact")
    public var contact: AskContactEntity?

    @Parameter(title: "Phone")
    public var phone: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Call \(\.$contact)") {
            \.$phone
        }
    }

    public init() {
        self.contact = nil
        self.phone = ""
    }

    public init(contact: AskContactEntity) {
        self.contact = contact
        self.phone = contact.phone
    }

    public init(phone: String) {
        self.contact = nil
        self.phone = phone
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let number = contact?.phone.isEmpty == false ? contact!.phone : phone
        try await askOpenContactURL(
            AskContactDial.telURL(number),
            canContinue: systemContext.currentMode.canContinueInForeground
        ) {
            try await self.continueInForeground("Opening Phone.", alwaysConfirm: false)
        }
        return .result(dialog: "Calling \(number).")
    }
}

/// The phone row on a contact card. A result dialog would open a second shortcut window on top of the snippet.
struct AskCallTap: AppIntent {
    static let title: LocalizedStringResource = "Call Contact"
    static let isDiscoverable = false

    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Phone")
    var phone: String

    init() {}

    init(phone: String) {
        self.phone = phone
    }

    func perform() async throws -> some IntentResult {
        try await askOpenContactURL(
            AskContactDial.telURL(phone),
            canContinue: systemContext.currentMode.canContinueInForeground
        ) {
            try await self.continueInForeground("Opening Phone.", alwaysConfirm: false)
        }
        return .result()
    }
}

/// Opens Mail to a contact. Shortcuts can pass an ``AskContactEntity`` from Ask. It is not an extra Siri phrase.
public struct OpenAskEmailIntent: AppIntent {
    public static let title: LocalizedStringResource = "Email Contact"
    public static let description = IntentDescription("Opens Mail to a contact.")

    public static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    public static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Contact")
    public var contact: AskContactEntity?

    @Parameter(title: "Email")
    public var email: String

    public static var parameterSummary: some ParameterSummary {
        Summary("Email \(\.$contact)") {
            \.$email
        }
    }

    public init() {
        self.contact = nil
        self.email = ""
    }

    public init(contact: AskContactEntity) {
        self.contact = contact
        self.email = contact.email
    }

    public init(email: String) {
        self.contact = nil
        self.email = email
    }

    public func perform() async throws -> some IntentResult & ProvidesDialog {
        let address = contact?.email.isEmpty == false ? contact!.email : email
        try await askOpenContactURL(
            AskContactDial.mailURL(address),
            canContinue: systemContext.currentMode.canContinueInForeground
        ) {
            try await self.continueInForeground("Opening Mail.", alwaysConfirm: false)
        }
        return .result(dialog: "Emailing \(address).")
    }
}

/// The email row on a contact card. A result dialog would open a second shortcut window on top of the snippet.
struct AskEmailTap: AppIntent {
    static let title: LocalizedStringResource = "Email Contact"
    static let isDiscoverable = false

    static var supportedModes: IntentModes { [.background, .foreground(.dynamic)] }
    static var allowedExecutionTargets: IntentExecutionTargets { .main }

    @Parameter(title: "Email")
    var email: String

    init() {}

    init(email: String) {
        self.email = email
    }

    func perform() async throws -> some IntentResult {
        try await askOpenContactURL(
            AskContactDial.mailURL(email),
            canContinue: systemContext.currentMode.canContinueInForeground
        ) {
            try await self.continueInForeground("Opening Mail.", alwaysConfirm: false)
        }
        return .result()
    }
}

private func askOpenContactURL(
    _ url: URL?,
    canContinue: Bool,
    resumeInForeground: () async throws -> Void
) async throws {
    guard let url else { throw AskContactIntentError.unavailable }
    if await AskContactOpen.open(url) { return }
    // A shortcut over the Home Screen has no foreground scene, so Phone and Mail ignore the first open.
    guard canContinue else { throw AskContactIntentError.unavailable }
    try await resumeInForeground()
    guard await AskContactOpen.open(url) else {
        throw AskContactIntentError.unavailable
    }
}

enum AskContactOpen {
    @MainActor
    static func open(_ url: URL) async -> Bool {
        await UIApplication.shared.open(url)
    }
}
