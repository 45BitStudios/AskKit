import Foundation
import os

#if canImport(Contacts)
import Contacts

enum AskContactsRead {
    static func add(name: String, phone: String, email: String) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = CNContactStore()
        guard await allow(store) else { return AskAppleCopy.denied }
        AskContactsHistory.sync(store: store)
        let cleaned = AskAppleCopy.plain(name, limit: 120)
        let parts = cleaned.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
        guard let given = parts.first else { return "A name is needed." }
        let contact = CNMutableContact()
        contact.givenName = given
        if parts.count > 1 {
            contact.familyName = parts.dropFirst().joined(separator: " ")
        }
        let number = AskAppleCopy.plain(phone, limit: 40)
        if !number.isEmpty {
            contact.phoneNumbers = [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: number))]
        }
        let address = AskAppleCopy.plain(email, limit: 120)
        if !address.isEmpty {
            contact.emailAddresses = [CNLabeledValue(label: CNLabelHome, value: address as NSString)]
        }
        let request = CNSaveRequest()
        request.add(contact, toContainerWithIdentifier: nil)
        do {
            try store.execute(request)
        } catch {
            return "Could not add the contact."
        }
        AskContactsHistory.record(identifier: contact.identifier)
        let saved = AskContactLine.line(name: cleaned, phone: number, email: address)
        return AskAppleCopy.addedPrefix + saved
#endif
    }

    static func update(name: String, phone: String?, email: String?, newName: String?) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = CNContactStore()
        guard await allow(store) else { return AskAppleCopy.denied }
        switch await match(store, name: name) {
        case .none:
            return "No matching contacts."
        case .many:
            return "More than one contact is named \(AskAppleCopy.plain(name, limit: 80))."
        case .one(let contact):
            let mutable = contact.mutableCopy() as! CNMutableContact
            if let newName {
                let cleaned = AskAppleCopy.plain(newName, limit: 120)
                let parts = cleaned.split(whereSeparator: \.isWhitespace).map(String.init).filter { !$0.isEmpty }
                if let given = parts.first {
                    mutable.givenName = given
                    mutable.familyName = parts.count > 1 ? parts.dropFirst().joined(separator: " ") : ""
                }
            }
            if let phone {
                let number = AskAppleCopy.plain(phone, limit: 40)
                mutable.phoneNumbers = number.isEmpty
                    ? []
                    : [CNLabeledValue(label: CNLabelPhoneNumberMain, value: CNPhoneNumber(stringValue: number))]
            }
            if let email {
                let address = AskAppleCopy.plain(email, limit: 120)
                mutable.emailAddresses = address.isEmpty
                    ? []
                    : [CNLabeledValue(label: CNLabelHome, value: address as NSString)]
            }
            let request = CNSaveRequest()
            request.update(mutable)
            do {
                try store.execute(request)
            } catch {
                return "Could not change the contact."
            }
            return AskAppleCopy.updatedPrefix + line(mutable)
        }
#endif
    }

    static func remove(name: String) async -> String {
#if os(watchOS)
        // Apple Watch can read this source but not change it.
        return AskAppleCopy.readOnly
#else
        let store = CNContactStore()
        guard await allow(store) else { return AskAppleCopy.denied }
        switch await match(store, name: name) {
        case .none:
            return "No matching contacts."
        case .many:
            return "More than one contact is named \(AskAppleCopy.plain(name, limit: 80))."
        case .one(let contact):
            let saved = line(contact)
            let mutable = contact.mutableCopy() as! CNMutableContact
            let request = CNSaveRequest()
            request.delete(mutable)
            do {
                try store.execute(request)
            } catch {
                return "Could not remove the contact."
            }
            return AskAppleCopy.removedPrefix + saved
        }
#endif
    }

    private enum Match {
        case one(CNContact)
        case none
        case many
    }

    private static func match(_ store: CNContactStore, name: String) async -> Match {
        let wanted = AskAppleCopy.folded(name)
        guard !wanted.isEmpty else { return .none }
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        request.predicate = CNContact.predicateForContacts(matchingName: name)
        var found: [CNContact] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                let formatted = CNContactFormatter.string(from: contact, style: .fullName)?
                    .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                let folded = AskAppleCopy.folded(formatted)
                if folded == wanted || AskContactLine.matches(name: formatted, query: name) {
                    found.append(contact)
                }
                if found.count > 1 { stop.pointee = true }
            }
        } catch {
            return .none
        }
        if found.count == 1, let contact = found.first { return .one(contact) }
        return found.isEmpty ? .none : .many
    }

    static func lines(matching name: String, prefix: Bool = false) async -> String {
        let store = CNContactStore()
        let granted = await allow(store)
        guard granted else { return AskAppleCopy.denied }
        AskContactsHistory.sync(store: store)
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor
        ]
        let request = CNContactFetchRequest(keysToFetch: keys)
        // Short prefixes need a full scan. Contacts' name predicate misses many of them.
        let scanAll = prefix && !name.isEmpty && name.count <= 2
        if !name.isEmpty, !scanAll {
            request.predicate = CNContact.predicateForContacts(matchingName: name)
        }
        let cap = name.isEmpty ? 5 : (scanAll ? 200 : 40)
        var lines: [String] = []
        do {
            try store.enumerateContacts(with: request) { contact, stop in
                lines.append(line(contact))
                if lines.count >= cap { stop.pointee = true }
            }
        } catch {
            return AskAppleCopy.denied
        }
        let matched = name.isEmpty ? lines : AskContactLine.filtered(lines, query: name, prefix: prefix)
        let kept = Array(matched.prefix(name.isEmpty ? 5 : 8))
        guard !kept.isEmpty else { return name.isEmpty ? "No contacts." : "No matching contacts." }
        return kept.joined(separator: "\n")
    }

    static func lines(addedWithinDays days: Int) async -> String {
        let store = CNContactStore()
        guard await allow(store) else { return AskAppleCopy.denied }
        AskContactsHistory.sync(store: store)
        let ids = AskContactsHistory.identifiers(addedWithinDays: days)
        guard !ids.isEmpty else { return "No recently added contacts." }
        let keys: [CNKeyDescriptor] = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        var lines: [String] = []
        for id in ids.prefix(8) {
            guard let contact = try? store.unifiedContact(withIdentifier: id, keysToFetch: keys) else { continue }
            lines.append(line(contact))
        }
        guard !lines.isEmpty else { return "No recently added contacts." }
        return lines.joined(separator: "\n")
    }

    private static func allow(_ store: CNContactStore) async -> Bool {
        switch CNContactStore.authorizationStatus(for: .contacts) {
        case .authorized, .limited:
            return true
        case .notDetermined:
            return (try? await store.requestAccess(for: .contacts)) ?? false
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }

    private static func line(_ contact: CNContact) -> String {
        let formatted = CNContactFormatter.string(from: contact, style: .fullName)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = (formatted?.isEmpty == false) ? formatted! : "Contact"
        let phone = contact.phoneNumbers.first?.value.stringValue
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let email = contact.emailAddresses.first.map {
            String($0.value).trimmingCharacters(in: .whitespacesAndNewlines)
        } ?? ""
        return AskContactLine.line(name: name, phone: phone, email: email)
    }
}
#else
/// Contacts is not on this platform. The contacts tool is never offered here; these keep the callers compiling.
enum AskContactsRead {
    static func add(name: String, phone: String, email: String) async -> String { AskAppleCopy.unavailable }

    static func update(name: String, phone: String?, email: String?, newName: String?) async -> String { AskAppleCopy.unavailable }

    static func remove(name: String) async -> String { AskAppleCopy.unavailable }

    static func lines(matching name: String, prefix: Bool = false) async -> String { AskAppleCopy.unavailable }

    static func lines(addedWithinDays days: Int) async -> String { AskAppleCopy.unavailable }
}
#endif
