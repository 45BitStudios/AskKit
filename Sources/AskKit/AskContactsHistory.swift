#if canImport(Contacts)
import AskContactsChangeHistory
import Contacts
import Foundation
import os

/// Tracks when contacts were first seen as added.
///
/// Contacts has no public creation date. Change history reports adds without timestamps, so this
/// saves a baseline history token on first sync, then records identifiers for later add events
/// (and for contacts Ask itself creates) with the time they were observed.
enum AskContactsHistory {
    static let tokenKey = "AskKit.contacts.historyToken"
    static let baselinedKey = "AskKit.contacts.historyBaselined"
    static let addedAtKey = "AskKit.contacts.addedAt"

    private static let lock = OSAllocatedUnfairLock()

    /// Contact identifiers first seen as added within `days` ending at `now`.
    static func identifiers(
        addedWithinDays days: Int,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> [String] {
        let clamped = max(1, min(days, 3_650))
        guard let start = Calendar.current.date(byAdding: .day, value: -clamped, to: now) else { return [] }
        return lock.withLockUnchecked {
            let map = addedAt(defaults: defaults)
            return map
                .filter { $0.value >= start }
                .sorted { $0.value > $1.value }
                .map(\.key)
        }
    }

    /// Records a contact Ask just created.
    static func record(
        identifier: String,
        at date: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        let id = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !id.isEmpty else { return }
        lock.withLockUnchecked {
            var map = addedAt(defaults: defaults)
            if map[id] == nil {
                map[id] = date
                defaults.set(encode(map), forKey: addedAtKey)
            }
            defaults.set(true, forKey: baselinedKey)
        }
    }

    /// Pulls Contacts change history and updates the saved add times.
    @discardableResult
    static func sync(
        store: CNContactStore,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) -> Bool {
        let request = CNChangeHistoryFetchRequest()
        request.shouldUnifyResults = true
        request.additionalContactKeyDescriptors = [
            CNContactFormatter.descriptorForRequiredKeys(for: .fullName),
            CNContactPhoneNumbersKey as CNKeyDescriptor,
            CNContactEmailAddressesKey as CNKeyDescriptor,
            CNContactIdentifierKey as CNKeyDescriptor
        ]
        let baseline: Bool = lock.withLockUnchecked {
            let ready = defaults.bool(forKey: baselinedKey)
            if let token = defaults.data(forKey: tokenKey), !token.isEmpty {
                request.startingToken = token
            }
            return !ready
        }

        guard let result = try? AskContactsChangeHistoryFetch.result(for: store, request: request) else {
            return false
        }
        let enumerator = result.value

        let visitor = Visitor()
        for case let event as CNChangeHistoryEvent in enumerator {
            event.accept(visitor)
        }

        lock.withLockUnchecked {
            // A drop resets the cache. Do not stamp rebuild/baseline adds as "recent".
            var map = visitor.droppedEverything ? [:] : addedAt(defaults: defaults)
            if !baseline, !visitor.droppedEverything {
                for id in visitor.added where map[id] == nil {
                    map[id] = now
                }
            }
            for id in visitor.deleted {
                map.removeValue(forKey: id)
            }
            defaults.set(encode(map), forKey: addedAtKey)
            let token = result.currentHistoryToken
            if !token.isEmpty {
                defaults.set(token, forKey: tokenKey)
            }
            defaults.set(true, forKey: baselinedKey)
        }
        return true
    }

    /// Test helper. Clears saved history state.
    static func resetForTesting(defaults: UserDefaults = .standard) {
        lock.withLockUnchecked {
            defaults.removeObject(forKey: tokenKey)
            defaults.removeObject(forKey: baselinedKey)
            defaults.removeObject(forKey: addedAtKey)
        }
    }

    /// Test helper. Applies add/delete events without calling Contacts.
    static func ingestForTesting(
        added: [String],
        deleted: [String] = [],
        baseline: Bool,
        now: Date = Date(),
        defaults: UserDefaults = .standard
    ) {
        lock.withLockUnchecked {
            var map = addedAt(defaults: defaults)
            if !baseline {
                for id in added where map[id] == nil {
                    map[id] = now
                }
            }
            for id in deleted {
                map.removeValue(forKey: id)
            }
            defaults.set(encode(map), forKey: addedAtKey)
            defaults.set(true, forKey: baselinedKey)
        }
    }

    private static func addedAt(defaults: UserDefaults) -> [String: Date] {
        guard let raw = defaults.dictionary(forKey: addedAtKey) as? [String: Double] else { return [:] }
        return raw.mapValues { Date(timeIntervalSince1970: $0) }
    }

    private static func encode(_ map: [String: Date]) -> [String: Double] {
        Dictionary(uniqueKeysWithValues: map.map { ($0.key, $0.value.timeIntervalSince1970) })
    }

    private final class Visitor: NSObject, CNChangeHistoryEventVisitor {
        var added: [String] = []
        var deleted: [String] = []
        var droppedEverything = false

        func visit(_ event: CNChangeHistoryDropEverythingEvent) {
            droppedEverything = true
            added.removeAll()
            deleted.removeAll()
        }

        func visit(_ event: CNChangeHistoryAddContactEvent) {
            let id = event.contact.identifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { added.append(id) }
        }

        func visit(_ event: CNChangeHistoryUpdateContactEvent) {}

        func visit(_ event: CNChangeHistoryDeleteContactEvent) {
            let id = event.contactIdentifier.trimmingCharacters(in: .whitespacesAndNewlines)
            if !id.isEmpty { deleted.append(id) }
        }
    }
}
#endif
