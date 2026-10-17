import Foundation
import os

#if canImport(HealthKit)
import HealthKit

/// One permission prompt for every health read. Parallel tool calls wait here.
/// `authorizationStatus` is the write status. A read-only app is sharingDenied even when reading is allowed.
actor AskHealthAuthorization {
    static let shared = AskHealthAuthorization()
    private var requested = false

    func prepare() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        if requested { return true }
        var types = Set<HKObjectType>()
        for metric in AskHealthCatalog.Metric.allCases {
            if let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) {
                types.insert(type)
            }
        }
        // A read request for the blood pressure correlation throws.
        // Systolic is already in the catalog; diastolic is the other half of the pair.
        if let diastolic = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) {
            types.insert(diastolic)
        }
        types.insert(HKWorkoutType.workoutType())
        if let sleep = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        guard !types.isEmpty else { return false }
        do {
            try await HKHealthStore().requestAuthorization(toShare: [], read: types)
            requested = true
            return true
        } catch {
            return false
        }
    }
}

package enum AskHealthRead {
    static func lines(kind: String, span: String = "today") async -> String {
        guard await AskHealthAuthorization.shared.prepare() else { return AskAppleCopy.denied }
        if AskHealthCatalog.isActivity(kind) {
            return await activity(kind: kind, span: span)
        }
        let metrics = AskHealthCatalog.metrics(matching: kind)
        var lines = Array(repeating: "", count: metrics.count)
        await withTaskGroup(of: (Int, String).self) { group in
            for (index, metric) in metrics.enumerated() {
                group.addTask {
                    (index, await reading(metric, span: span))
                }
            }
            for await (index, line) in group {
                lines[index] = line
            }
        }
        return lines.joined(separator: "\n")
    }

    package static func series(metric: AskHealthCatalog.Metric, range: AskHealthRange) async -> AskHealthSeriesSnapshot {
        let axis = AskHealthCatalog.axisLabel(for: metric)
        guard await AskHealthAuthorization.shared.prepare(),
              let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) else {
            return .unavailable(axis)
        }
        let calendar = Calendar.current
        let now = Date()
        guard let window = AskHealthBuckets.window(range: range, now: now, calendar: calendar) else {
            return .empty(axis)
        }
        let sample = HKQuery.predicateForSamples(withStart: window.start, end: window.end, options: .strictStartDate)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: sample)
        let measure = measure(for: metric)
        do {
            if metric.latestSample {
                return try await samples(metric, measure: measure, axis: axis, predicate: predicate)
            }
            return try await buckets(
                metric,
                measure: measure,
                axis: axis,
                predicate: predicate,
                range: range,
                window: window,
                now: now,
                calendar: calendar
            )
        } catch {
            return refusal(error) ? .unavailable(axis) : .empty(axis)
        }
    }

    /// Workouts and sleep. The header is `Workouts:` or `Sleep:`, which is not a chart measurement.
    private static func activity(kind: String, span: String) async -> String {
        let folded = kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if folded == "sleep" {
            return await sleep(span: span)
        }
        return await workouts(span: span)
    }

    private static func activitySpan(_ span: String) -> String {
        span == "month" || span == "year" ? span : "week"
    }

    private static func activityPhrase(_ span: String) -> String {
        switch activitySpan(span) {
        case "month": "this month"
        case "year": "this year"
        default: "this week"
        }
    }

    private static func workouts(span: String) async -> String {
        let phrase = activityPhrase(span)
        let calendar = Calendar.current
        let end = Date()
        let start = AskHealthBuckets.start(span: activitySpan(span), now: end, calendar: calendar)
        let sample = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = HKSamplePredicate.workout(sample)
        let descriptor = HKSampleQueryDescriptor<HKWorkout>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.startDate, order: .reverse)],
            limit: 8
        )
        let found: [HKWorkout]
        do {
            found = try await descriptor.result(for: HKHealthStore())
        } catch {
            return refusal(error) ? "Workouts: \(AskAppleCopy.denied)" : "Workouts: Nothing recorded \(phrase)."
        }
        guard !found.isEmpty else { return "Workouts: Nothing recorded \(phrase)." }
        let rows = found.map { workoutLine($0) }
        return (["Workouts: \(found.count) \(phrase)"] + rows).joined(separator: "\n")
    }

    private static func workoutLine(_ workout: HKWorkout) -> String {
        let name = AskAppleCopy.plain(workoutName(workout.workoutActivityType), limit: 40)
        let minutes = max(Int((workout.duration / 60).rounded()), 0)
        let length = minutes == 1 ? "1 minute" : "\(minutes) minutes"
        var parts = [name.isEmpty ? "Workout" : name, length]
        if let distance = workoutDistance(workout) {
            parts.append(distance)
        }
        parts.append(workout.startDate.formatted(date: .abbreviated, time: .omitted))
        return parts.joined(separator: " · ")
    }

    private static func workoutDistance(_ workout: HKWorkout) -> String? {
        let metric = Locale.current.measurementSystem == .metric
        let unit: HKUnit = metric ? .meterUnit(with: .kilo) : .mile()
        let label = metric ? "kilometers" : "miles"
        let identifiers: [HKQuantityTypeIdentifier] = [.distanceWalkingRunning, .distanceCycling, .distanceSwimming]
        for identifier in identifiers {
            guard let type = HKQuantityType.quantityType(forIdentifier: identifier),
                  let sum = workout.statistics(for: type)?.sumQuantity() else { continue }
            let value = sum.doubleValue(for: unit)
            guard value > 0.05 else { continue }
            let number = value.formatted(.number.precision(.fractionLength(1)))
            return "\(number) \(label)"
        }
        return nil
    }

    private static func workoutName(_ type: HKWorkoutActivityType) -> String {
        switch type {
        case .running: "Running"
        case .walking: "Walking"
        case .cycling: "Cycling"
        case .swimming: "Swimming"
        case .hiking: "Hiking"
        case .yoga: "Yoga"
        case .traditionalStrengthTraining, .functionalStrengthTraining: "Strength"
        case .highIntensityIntervalTraining: "Intervals"
        case .elliptical: "Elliptical"
        case .rowing: "Rowing"
        case .stairClimbing, .stairs: "Stairs"
        case .pilates: "Pilates"
        case .coreTraining: "Core"
        case .cooldown: "Cooldown"
        case .mixedCardio, .crossTraining: "Cardio"
        case .dance, .cardioDance, .socialDance: "Dance"
        default: "Workout"
        }
    }

    /// Asleep stages for each night. A night with no stage falls back to time in bed.
    private static func sleep(span: String) async -> String {
        let phrase = activityPhrase(span)
        guard let type = HKCategoryType.categoryType(forIdentifier: .sleepAnalysis) else {
            return "Sleep: \(AskAppleCopy.denied)"
        }
        let calendar = Calendar.current
        let end = Date()
        let start = AskHealthBuckets.start(span: activitySpan(span), now: end, calendar: calendar)
        let sample = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = HKSamplePredicate.categorySample(type: type, predicate: sample)
        let descriptor = HKSampleQueryDescriptor<HKCategorySample>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 400
        )
        let samples: [HKCategorySample]
        do {
            samples = try await descriptor.result(for: HKHealthStore())
        } catch {
            return refusal(error) ? "Sleep: \(AskAppleCopy.denied)" : "Sleep: Nothing recorded \(phrase)."
        }
        let asleep = HKCategoryValueSleepAnalysis.allAsleepValues
        var staged: [Date: TimeInterval] = [:]
        var inBed: [Date: TimeInterval] = [:]
        for sample in samples {
            guard let value = HKCategoryValueSleepAnalysis(rawValue: sample.value) else { continue }
            let night = calendar.startOfDay(for: sample.endDate)
            let length = sample.endDate.timeIntervalSince(sample.startDate)
            guard length > 0 else { continue }
            if asleep.contains(value) {
                staged[night, default: 0] += length
            } else if value == .inBed {
                inBed[night, default: 0] += length
            }
        }
        let nights = Set(staged.keys).union(inBed.keys)
        guard !nights.isEmpty else { return "Sleep: Nothing recorded \(phrase)." }
        let total = nights.reduce(0.0) { sum, night in
            if let hours = staged[night], hours > 0 { return sum + hours }
            return sum + (inBed[night] ?? 0)
        }
        let average = total / Double(nights.count) / 3600
        let hours = average.formatted(.number.precision(.fractionLength(1)))
        return "Sleep: \(hours) hours a night \(phrase)"
    }

    private static func reading(_ metric: AskHealthCatalog.Metric, span: String) async -> String {
        if metric == .bloodPressure {
            do {
                return try await bloodPressure()
            } catch {
                let value = refusal(error) ? AskAppleCopy.denied : "Nothing recorded."
                return "\(metric.title): \(value)"
            }
        }
        guard let type = HKQuantityType.quantityType(forIdentifier: metric.identifier) else {
            return "\(metric.title): \(AskAppleCopy.denied)"
        }
        let measure = measure(for: metric)
        let covered = metric.latestSample || AskHealthCatalog.periodPhrase(span) == nil ? "today" : span
        do {
            if metric.latestSample {
                return try await latest(metric, type: type, measure: measure)
            }
            return try await period(metric, type: type, measure: measure, span: covered)
        } catch {
            let value = refusal(error) ? AskAppleCopy.denied : (metric.latestSample ? "Nothing recorded." : AskHealthCatalog.missingValue(span: covered))
            return "\(metric.title): \(value)"
        }
    }

    private static func bloodPressure() async throws -> String {
        guard let type = HKCorrelationType.correlationType(forIdentifier: .bloodPressure),
              let systolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureSystolic),
              let diastolicType = HKQuantityType.quantityType(forIdentifier: .bloodPressureDiastolic) else {
            return "Blood pressure: \(AskAppleCopy.denied)"
        }
        let predicate = HKSamplePredicate.correlation(type: type)
        let descriptor = HKSampleQueryDescriptor<HKCorrelation>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: HKHealthStore()).first else {
            return "Blood pressure: Nothing recorded."
        }
        let unit = HKUnit.millimeterOfMercury()
        let systolic = sample.objects(for: systolicType)
            .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
            .first
        let diastolic = sample.objects(for: diastolicType)
            .compactMap { ($0 as? HKQuantitySample)?.quantity.doubleValue(for: unit) }
            .first
        guard let systolic, let diastolic else {
            return "Blood pressure: Nothing recorded."
        }
        let sys = formatted(systolic, fraction: 0, percent: false)
        let dia = formatted(diastolic, fraction: 0, percent: false)
        let when = sample.endDate.formatted(date: .abbreviated, time: .omitted)
        return "Blood pressure: \(sys)/\(dia) mmHg · \(when)"
    }

    /// Today, or a longer range when the question asked for one. The end is now.
    private static func period(
        _ metric: AskHealthCatalog.Metric,
        type: HKQuantityType,
        measure: (unit: HKUnit, label: String, fraction: Int),
        span: String
    ) async throws -> String {
        let calendar = Calendar.current
        let end = Date()
        let start = AskHealthBuckets.start(span: span, now: end, calendar: calendar)
        let sample = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let predicate = HKSamplePredicate.quantitySample(type: type, predicate: sample)
        let options: HKStatisticsOptions = metric.averageToday ? .discreteAverage : .cumulativeSum
        let descriptor = HKStatisticsQueryDescriptor(predicate: predicate, options: options)
        let statistics = try await descriptor.result(for: HKHealthStore())
        let quantity = metric.averageToday ? statistics?.averageQuantity() : statistics?.sumQuantity()
        guard let quantity else {
            return "\(metric.title): \(AskHealthCatalog.missingValue(span: span))"
        }
        let number = formatted(quantity.doubleValue(for: measure.unit), fraction: measure.fraction, percent: metric.percent)
        return AskHealthCatalog.summary(title: metric.title, value: "\(number) \(measure.label)", span: span)
    }

    private static func buckets(
        _ metric: AskHealthCatalog.Metric,
        measure: (unit: HKUnit, label: String, fraction: Int),
        axis: String,
        predicate: HKSamplePredicate<HKQuantitySample>,
        range: AskHealthRange,
        window: AskHealthWindow,
        now: Date,
        calendar: Calendar
    ) async throws -> AskHealthSeriesSnapshot {
        let average = metric.averageToday
        let options: HKStatisticsOptions = average ? .discreteAverage : .cumulativeSum
        let descriptor = HKStatisticsCollectionQueryDescriptor(
            predicate: predicate,
            options: options,
            anchorDate: window.start,
            intervalComponents: range.interval
        )
        let collection = try await descriptor.result(for: HKHealthStore())
        let found = PointBox()
        let unit = measure.unit
        let percent = metric.percent
        collection.enumerateStatistics(from: window.start, to: window.end) { statistics, _ in
            let quantity = average ? statistics.averageQuantity() : statistics.sumQuantity()
            let recorded = quantity != nil
            let raw = quantity?.doubleValue(for: unit) ?? 0
            found.add(AskHealthPoint(
                id: String(statistics.startDate.timeIntervalSinceReferenceDate),
                date: statistics.startDate,
                value: percent ? raw * 100 : raw,
                recorded: recorded
            ))
        }
        let dates = AskHealthBuckets.dates(range: range, now: now, calendar: calendar)
        let collected = found.all()
        let points = dates.map { date in
            if let match = collected.first(where: { calendar.isDate($0.date, equalTo: date, toGranularity: range.bucket) }) {
                return AskHealthPoint(id: match.id, date: date, value: match.value, recorded: match.recorded)
            }
            return AskHealthPoint(id: "empty-\(date.timeIntervalSinceReferenceDate)", date: date, value: 0, recorded: false)
        }
        let statistics = try await HKStatisticsQueryDescriptor(predicate: predicate, options: options).result(for: HKHealthStore())
        let quantity = average ? statistics?.averageQuantity() : statistics?.sumQuantity()
        let recorded = quantity != nil || points.contains(where: \.recorded)
        guard let quantity else {
            return AskHealthSeriesSnapshot(points: points, headline: "Nothing recorded.", axisLabel: axis, denied: false, recorded: recorded)
        }
        let number = formatted(quantity.doubleValue(for: unit), fraction: measure.fraction, percent: percent)
        let headline = AskHealthCatalog.headline(value: number, unit: measure.label, range: range)
        return AskHealthSeriesSnapshot(points: points, headline: headline, axisLabel: axis, denied: false, recorded: true)
    }

    private static func samples(
        _ metric: AskHealthCatalog.Metric,
        measure: (unit: HKUnit, label: String, fraction: Int),
        axis: String,
        predicate: HKSamplePredicate<HKQuantitySample>
    ) async throws -> AskHealthSeriesSnapshot {
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 60
        )
        let found = try await descriptor.result(for: HKHealthStore())
        let ordered = found.sorted { $0.endDate < $1.endDate }
        guard let newest = ordered.last else { return .empty(axis) }
        let points = ordered.enumerated().map { index, sample in
            let raw = sample.quantity.doubleValue(for: measure.unit)
            return AskHealthPoint(
                id: "\(sample.uuid.uuidString)-\(index)",
                date: sample.endDate,
                value: metric.percent ? raw * 100 : raw,
                recorded: true
            )
        }
        let number = formatted(newest.quantity.doubleValue(for: measure.unit), fraction: measure.fraction, percent: metric.percent)
        let when = newest.endDate.formatted(date: .abbreviated, time: .omitted)
        return AskHealthSeriesSnapshot(
            points: points,
            headline: "\(number) \(measure.label) · \(when)",
            axisLabel: axis,
            denied: false,
            recorded: true
        )
    }

    private static func latest(
        _ metric: AskHealthCatalog.Metric,
        type: HKQuantityType,
        measure: (unit: HKUnit, label: String, fraction: Int)
    ) async throws -> String {
        let predicate = HKSamplePredicate.quantitySample(type: type)
        let descriptor = HKSampleQueryDescriptor<HKQuantitySample>(
            predicates: [predicate],
            sortDescriptors: [SortDescriptor(\.endDate, order: .reverse)],
            limit: 1
        )
        guard let sample = try await descriptor.result(for: HKHealthStore()).first else {
            return "\(metric.title): Nothing recorded."
        }
        let number = formatted(sample.quantity.doubleValue(for: measure.unit), fraction: measure.fraction, percent: metric.percent)
        let when = sample.endDate.formatted(date: .abbreviated, time: .omitted)
        return "\(metric.title): \(number) \(measure.label) · \(when)"
    }

    private static func formatted(_ value: Double, fraction: Int, percent: Bool) -> String {
        let number = percent ? value * 100 : value
        return number.formatted(.number.precision(.fractionLength(fraction)))
    }

    private static func measure(for metric: AskHealthCatalog.Metric) -> (unit: HKUnit, label: String, fraction: Int) {
        let metricSystem = Locale.current.measurementSystem == .metric
        switch metric {
        case .steps, .flights:
            return (.count(), metric == .steps ? "steps" : "flights", 0)
        case .heart, .restingHeart:
            return (HKUnit.count().unitDivided(by: .minute()), "beats per minute", 0)
        case .breathing:
            return (HKUnit.count().unitDivided(by: .minute()), "breaths per minute", 0)
        case .energy:
            return (.kilocalorie(), "kilocalories", 0)
        case .distance:
            return metricSystem
                ? (.meterUnit(with: .kilo), "kilometers", 1)
                : (.mile(), "miles", 1)
        case .exercise:
            return (.minute(), "minutes", 0)
        case .weight:
            return metricSystem
                ? (.gramUnit(with: .kilo), "kilograms", 1)
                : (.pound(), "pounds", 1)
        case .height:
            return metricSystem
                ? (.meterUnit(with: .centi), "centimeters", 0)
                : (.inch(), "inches", 0)
        case .bodyFat, .oxygen:
            return (.percent(), "percent", 0)
        case .bloodPressure:
            return (.millimeterOfMercury(), "mmHg", 0)
        case .glucose:
            return (HKUnit(from: "mg/dL"), "milligrams per deciliter", 0)
        case .temperature:
            return metricSystem
                ? (.degreeCelsius(), "degrees Celsius", 1)
                : (.degreeFahrenheit(), "degrees Fahrenheit", 1)
        case .vo2:
            let unit = HKUnit.literUnit(with: .milli)
                .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))
            return (unit, "milliliters per kilogram per minute", 1)
        }
    }

    private static func refusal(_ error: Error) -> Bool {
        let ns = error as NSError
        guard ns.domain == HKErrorDomain else { return false }
        switch HKError.Code(rawValue: ns.code) {
        case .errorAuthorizationDenied, .errorAuthorizationNotDetermined, .errorRequiredAuthorizationDenied,
             .errorHealthDataUnavailable, .errorHealthDataRestricted:
            return true
        default:
            return false
        }
    }
}

/// Collects chart buckets from a HealthKit enumeration.
final class PointBox: @unchecked Sendable {
    private let lock = NSLock()
    private var points: [AskHealthPoint] = []

    func add(_ point: AskHealthPoint) {
        lock.lock()
        points.append(point)
        lock.unlock()
    }

    func all() -> [AskHealthPoint] {
        lock.lock()
        defer { lock.unlock() }
        return points
    }
}
#else
/// HealthKit is not on this platform. The health tool is never offered here; these keep the callers compiling.
package enum AskHealthRead {
    static func lines(kind: String, span: String = "today") async -> String { AskAppleCopy.unavailable }

    package static func series(metric: AskHealthCatalog.Metric, range: AskHealthRange) async -> AskHealthSeriesSnapshot {
        .unavailable(AskHealthCatalog.axisLabel(for: metric))
    }
}
#endif
