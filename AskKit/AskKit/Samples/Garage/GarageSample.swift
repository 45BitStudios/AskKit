import AskKit
import SwiftUI

/// Ask Garage. Nineteen skills across battery, cabin, trip, and care.
/// All eight Apple sources can be selected in the composer. The first five start on.
/// Music, weather, and alarms stay off until another source is turned off. Ask about the next drive to see the fact card.
///
/// `guide` appends garage lines onto the built-in AskGuide prompts.
/// A reply prompt is QUESTION, SKILL, FACTS, the GARAGE section, and CONVERSATION.
/// The chat shows the first three chips. Type a phrase below, or the skill id alone, for the rest.
enum GarageSample {
    static let vehicle = "Ioniq 5"
    static let battery = "68 percent"
    static let minutesTo80 = "32"
    static let chargeLimit = "80 percent"
    static let chargeRate = "11 kW"
    static let range = "214 miles"
    static let chargerName = "Electrify America"
    static let chargerDistance = "0.4 miles"
    static let openStalls = "2"
    static let cabin = "72 degrees"
    static let departure = "7:30 a.m."
    static let seatHeat = "low"
    static let defrost = "off"
    static let tirePressure = "36 psi"
    static let odometer = "18,420 miles"
    static let tripMeter = "12 miles"
    static let efficiency = "3.6 miles per kWh"
    static let serviceIn = "2,400 miles"
    static let serviceDate = "October 20"
    static let washer = "low"
    static let software = "2026.10"
    static let locks = "locked"

    /// Appends garage lines onto the built-in AskGuide prompts. Use `.replace` to drop a built-in block.
    static let guide = AskGuide(
        routeOpening: .append("This assistant answers questions about the car in the garage."),
        routeRules: .append("""
        chargeStatus is the battery percent and the minutes to 80. chargeLimit is the maximum charge setting. \
        chargeRate is how fast it is charging. plugStatus is whether the cable is connected.
        precondition is warming the cabin before departure. seatHeat is the heated seat. defrost is the windshield.
        rangeLeft is how far it can still drive. findCharger is where to plug in, never chargeStatus. \
        tirePressure is the tires. odometer is total miles. tripMeter is miles on this drive. \
        efficiency is miles per kilowatt hour.
        nextService is upcoming maintenance. washerFluid is the washer fluid. softwareVersion is the car software. \
        lockStatus is the doors. lights is the headlights.
        Do not invent a charger, a range, or a reading.
        """),
        replyInstructions: .append("""
        Say the numbers FACTS already state. Do not invent chargers, times, or miles. \
        If a tool returns a calendar event, a reminder, a contact, a place, a health reading, a song, an album, the forecast, or an alarm, you may say it. \
        If a tool says Not allowed, say you cannot see that.
        """),
        followUpInstructions: .append("Do not invent places or numbers.")
    )

    static let appleAccess: AskAppleAccess = [.calendar, .reminders, .contacts, .location, .health, .music, .weather, .alarms]

    static func assistant() throws -> AskAssistant {
        AskAppleSelection.rememberIfNeeded(
            [.calendar, .reminders, .contacts, .location, .health],
            allowed: appleAccess,
            for: "Ask Garage"
        )
        return try AskAssistant(AskConfiguration(
            assistantName: "Ask Garage",
            persistence: .memory,
            domains: [
                AskDomain(
                    id: "battery",
                    summary: "Charging",
                    routingNotes: "Battery percent, the charge limit, charging speed, and whether the cable is connected."
                ),
                AskDomain(
                    id: "cabin",
                    summary: "Cabin",
                    routingNotes: "Warming the cabin before departure, seat heat, and defrost."
                ),
                AskDomain(
                    id: "trip",
                    summary: "Driving",
                    routingNotes: "Range left, a place to plug in, tire pressure, and the miles driven."
                ),
                AskDomain(
                    id: "care",
                    summary: "Upkeep",
                    routingNotes: "Service, washer fluid, software, the doors, and the headlights."
                )
            ],
            skills: skills,
            context: { context() },
            chips: { _ in chips },
            fastPath: { route($0) },
            guide: guide,
            appleAccess: appleAccess
        ))
    }

    static func context() -> AskContext {
        AskContext(
            promptBlock: """
            vehicle=\(vehicle) battery=\(battery) minutesTo80=\(minutesTo80) limit=\(chargeLimit) \
            rate=\(chargeRate) plugged=home range=\(range) charger=\(chargerName) \
            distance=\(chargerDistance) stalls=\(openStalls) cabin=\(cabin) departure=\(departure) \
            seatHeat=\(seatHeat) defrost=\(defrost) tires=\(tirePressure) odometer=\(odometer) \
            trip=\(tripMeter) efficiency=\(efficiency) service=\(serviceIn) washer=\(washer) \
            software=\(software) locks=\(locks) lights=off
            """,
            values: [
                "vehicle": vehicle,
                "battery": battery,
                "minutesTo80": minutesTo80,
                "range": range,
                "chargerName": chargerName,
                "chargerDistance": chargerDistance,
                "openStalls": openStalls,
                "cabin": cabin,
                "departure": departure
            ],
            sections: [
                AskPromptSection(
                    title: "GARAGE",
                    text: """
                    The car is an \(vehicle), plugged in at home, charging at \(chargeRate).
                    The battery is at \(battery), about \(minutesTo80) minutes from 80 percent. The charge limit is \(chargeLimit).
                    The cabin will be \(cabin) by \(departure). The driver seat heat is \(seatHeat). Front defrost is \(defrost).
                    Range is \(range) with Eco mode on. The nearest fast charger is \(chargerName), \(chargerDistance) away, with \(openStalls) stalls open.
                    Tires are \(tirePressure). The odometer reads \(odometer). This trip is \(tripMeter). Efficiency is \(efficiency).
                    Service is due in \(serviceIn), on \(serviceDate). Washer fluid is \(washer). Software is \(software). The doors are \(locks). The headlights are off.
                    """
                )
            ]
        )
    }

    /// The chat shows the first three. The other sixteen are typed.
    static let chips: [AskChip] = [
        AskChip(id: "charge", skillID: "chargeStatus", title: "Charge status"),
        AskChip(id: "range", skillID: "rangeLeft", title: "Range"),
        AskChip(id: "charger", skillID: "findCharger", title: "Find a charger")
    ]

    /// First matching phrase wins. Typing the skill id alone also matches.
    static func route(_ utterance: String) -> AskRoute? {
        SampleSkill.route(utterance, ids: skills.map(\.id), keywords: [
            ("nextDrive", ["next drive"]),
            ("softwareVersion", ["software", "version", "update"]),
            ("washerFluid", ["washer", "wiper"]),
            ("nextService", ["service", "maintenance"]),
            ("lockStatus", ["locked", "unlock", "door", "trunk"]),
            ("lights", ["headlight", "headlights", "lights"]),
            ("tirePressure", ["tire", "psi", "pressure"]),
            ("odometer", ["odometer", "total miles"]),
            ("tripMeter", ["trip meter", "this trip", "trip so far"]),
            ("efficiency", ["efficiency", "per kwh", "kilowatt hour"]),
            ("seatHeat", ["seat"]),
            ("defrost", ["defrost", "windshield"]),
            ("chargeLimit", ["charge limit", "the limit"]),
            ("chargeRate", ["charge rate", "charging speed", "kilowatt", "how fast"]),
            ("plugStatus", ["plugged", "latch", "connector"]),
            ("findCharger", ["charger", "station", "stall"]),
            ("rangeLeft", ["range", "how far", "miles left"]),
            ("precondition", ["warm", "precondition", "departure", "climate", "cabin"]),
            ("chargeStatus", ["battery", "percent", "charge"])
        ])
    }

    private static let skills: [AskSkill] = [
        chargeStatus, precondition, rangeLeft, findCharger
    ] + extras.map(SampleSkill.make)

    private static let extras: [SampleSkillSpec] = [
        SampleSkillSpec(
            id: "nextDrive",
            domainID: "trip",
            title: "Next drive",
            summary: "When the next drive leaves",
            routingNotes: "The next drive on the calendar, and where the car is.",
            spoken: "Your next drive is set for \(departure). The car can go about \(range).",
            facts: "The next drive is at \(departure). Range is \(range).",
            headline: departure,
            detail: "From the calendar",
            actionTitle: "Trip",
            replyOnly: true
        ),
        SampleSkillSpec(
            id: "chargeLimit",
            domainID: "battery",
            title: "Charge limit",
            summary: "The maximum charge the car is set to reach",
            routingNotes: "The charge limit and whether charging stops at 80 percent.",
            spoken: "The charge limit is \(chargeLimit).",
            facts: "The charge limit on the \(vehicle) is \(chargeLimit).",
            headline: chargeLimit,
            detail: "Charging stops here",
            actionTitle: "Limit",
            covered: [chargeLimit]
        ),
        SampleSkillSpec(
            id: "chargeRate",
            domainID: "battery",
            title: "Charge rate",
            summary: "How fast the car is charging right now",
            routingNotes: "Charging speed at home, in kilowatts.",
            spoken: "It is charging at \(chargeRate) on the home charger.",
            facts: "The \(vehicle) is charging at home at \(chargeRate).",
            headline: chargeRate,
            detail: "Home charger",
            actionTitle: "Rate",
            covered: [chargeRate]
        ),
        SampleSkillSpec(
            id: "plugStatus",
            domainID: "battery",
            title: "Plug",
            summary: "Whether the charge cable is connected",
            routingNotes: "Plugged in, the latch, and the connector at home.",
            spoken: "The \(vehicle) is plugged in at home. The latch is closed.",
            facts: "The \(vehicle) is plugged in at home. The charge latch is closed.",
            headline: "Plugged in",
            detail: "Latch closed · home",
            actionTitle: "Plug",
            covered: ["plugged in"]
        ),
        SampleSkillSpec(
            id: "seatHeat",
            domainID: "cabin",
            title: "Seat heat",
            summary: "Whether the driver seat heater is on",
            routingNotes: "Heated seat and seat heat level.",
            spoken: "The driver seat heat is \(seatHeat).",
            facts: "The driver seat heat in the \(vehicle) is \(seatHeat).",
            headline: seatHeat.capitalized,
            detail: "Driver seat",
            actionTitle: "Seat",
            covered: [seatHeat]
        ),
        SampleSkillSpec(
            id: "defrost",
            domainID: "cabin",
            title: "Defrost",
            summary: "Whether the front defrost is on",
            routingNotes: "Windshield defrost and the front defroster.",
            spoken: "Front defrost is \(defrost).",
            facts: "Front defrost on the \(vehicle) is \(defrost).",
            headline: defrost.capitalized,
            detail: "Front windshield",
            actionTitle: "Defrost",
            covered: [defrost]
        ),
        SampleSkillSpec(
            id: "tirePressure",
            domainID: "trip",
            title: "Tires",
            summary: "Tire pressure on all four tires",
            routingNotes: "Tire pressure and psi.",
            spoken: "All four tires are at \(tirePressure).",
            facts: "All four tires on the \(vehicle) are at \(tirePressure).",
            headline: tirePressure,
            detail: "All four tires",
            actionTitle: "Tires",
            covered: [tirePressure]
        ),
        SampleSkillSpec(
            id: "odometer",
            domainID: "trip",
            title: "Odometer",
            summary: "Total miles on the car",
            routingNotes: "The odometer and total miles driven.",
            spoken: "The odometer reads \(odometer).",
            facts: "The \(vehicle) odometer reads \(odometer).",
            headline: odometer,
            detail: "Total",
            actionTitle: "Odometer",
            covered: [odometer]
        ),
        SampleSkillSpec(
            id: "tripMeter",
            domainID: "trip",
            title: "This trip",
            summary: "Miles driven on the current trip",
            routingNotes: "The trip meter and miles on this drive.",
            spoken: "This trip is \(tripMeter).",
            facts: "The current trip is \(tripMeter).",
            headline: tripMeter,
            detail: "Since reset",
            actionTitle: "Trip",
            covered: [tripMeter]
        ),
        SampleSkillSpec(
            id: "efficiency",
            domainID: "trip",
            title: "Efficiency",
            summary: "Miles the car gets per kilowatt hour",
            routingNotes: "Driving efficiency and miles per kilowatt hour.",
            spoken: "Efficiency is \(efficiency).",
            facts: "The \(vehicle) is getting \(efficiency).",
            headline: efficiency,
            detail: "Recent driving",
            actionTitle: "Efficiency",
            covered: [efficiency]
        ),
        SampleSkillSpec(
            id: "nextService",
            domainID: "care",
            title: "Service",
            summary: "When the next service visit is due",
            routingNotes: "Maintenance, the next service, and miles until it is due.",
            spoken: "Service is due in \(serviceIn), on \(serviceDate).",
            facts: "Service for the \(vehicle) is due in \(serviceIn), on \(serviceDate).",
            headline: serviceIn,
            detail: serviceDate,
            actionTitle: "Service",
            covered: [serviceIn]
        ),
        SampleSkillSpec(
            id: "washerFluid",
            domainID: "care",
            title: "Washer fluid",
            summary: "Whether the windshield washer fluid is low",
            routingNotes: "Washer fluid and the wiper reservoir.",
            spoken: "Washer fluid is \(washer).",
            facts: "Washer fluid on the \(vehicle) is \(washer).",
            headline: washer.capitalized,
            detail: "Windshield washer",
            actionTitle: "Washer",
            covered: [washer]
        ),
        SampleSkillSpec(
            id: "softwareVersion",
            domainID: "care",
            title: "Software",
            summary: "The software version on the car",
            routingNotes: "Car software, the version, and whether an update is waiting.",
            spoken: "Software is \(software). It is up to date.",
            facts: "The \(vehicle) software is \(software). It is up to date.",
            headline: software,
            detail: "Up to date",
            actionTitle: "Software",
            covered: [software]
        ),
        SampleSkillSpec(
            id: "lockStatus",
            domainID: "care",
            title: "Locks",
            summary: "Whether the doors are locked",
            routingNotes: "Door locks, the trunk, and whether the car is locked.",
            spoken: "The doors are \(locks). The trunk is closed.",
            facts: "The \(vehicle) doors are \(locks). The trunk is closed.",
            headline: locks.capitalized,
            detail: "Trunk closed",
            actionTitle: "Locks",
            covered: [locks]
        ),
        SampleSkillSpec(
            id: "lights",
            domainID: "care",
            title: "Lights",
            summary: "Whether the headlights are on",
            routingNotes: "Headlights and whether the lights were left on.",
            spoken: "The headlights are off.",
            facts: "The \(vehicle) headlights are off.",
            headline: "Off",
            detail: "Headlights",
            actionTitle: "Lights",
            covered: ["off"]
        )
    ]

    private static let chargeStatus = AskSkill(
        id: "chargeStatus",
        domainID: "battery",
        title: "Charge status",
        summary: "Current battery and time to 80 percent",
        contextKeys: ["vehicle", "battery", "minutesTo80"],
        routingNotes: "How full the battery is, whether the car is charging at home, and when it reaches 80 percent.",
        fulfillment: .intent { invocation in
            let vehicle = invocation.context.value(for: "vehicle") ?? Self.vehicle
            let battery = invocation.context.value(for: "battery") ?? Self.battery
            let minutes = invocation.context.value(for: "minutesTo80") ?? Self.minutesTo80
            return AskIntentCard(
                title: "Charge",
                spoken: "Your \(vehicle) is at \(battery). About \(minutes) minutes until 80 percent.",
                coveredPhrases: [battery],
                action: AskAction(id: "charging", title: "Charging"),
                facts: "The \(vehicle) battery is at \(battery). Charging at home. About \(minutes) minutes until 80 percent.",
                view: ChargeCard(vehicle: vehicle, battery: battery, minutesTo80: minutes)
            )
        }
    )

    private static let precondition = AskSkill(
        id: "precondition",
        domainID: "cabin",
        title: "Precondition",
        summary: "Warm the cabin before departure",
        contextKeys: ["vehicle", "cabin", "departure"],
        routingNotes: "Cabin temperature, preconditioning, and being ready to leave.",
        fulfillment: .intent { invocation in
            let vehicle = invocation.context.value(for: "vehicle") ?? Self.vehicle
            let cabin = invocation.context.value(for: "cabin") ?? Self.cabin
            let departure = invocation.context.value(for: "departure") ?? Self.departure
            return AskIntentCard(
                title: "Climate",
                spoken: "Warm the \(vehicle) before you leave. The cabin will be \(cabin) by \(departure).",
                coveredPhrases: [cabin],
                action: AskAction(id: "climate", title: "Climate"),
                facts: "Warm the \(vehicle). The cabin will be \(cabin) by \(departure).",
                view: ClimateCard(vehicle: vehicle, cabin: cabin, departure: departure)
            )
        }
    )

    private static let rangeLeft = AskSkill(
        id: "rangeLeft",
        domainID: "trip",
        title: "Range",
        summary: "How far the car can go on this charge",
        contextKeys: ["vehicle", "range"],
        routingNotes: "Remaining range, miles left, and how far the car can drive.",
        fulfillment: .intent { invocation in
            let vehicle = invocation.context.value(for: "vehicle") ?? Self.vehicle
            let range = invocation.context.value(for: "range") ?? Self.range
            return AskIntentCard(
                title: "Range",
                spoken: "Your \(vehicle) can go about \(range). Eco mode is on.",
                coveredPhrases: [range],
                action: AskAction(id: "trip", title: "Trip"),
                facts: "The \(vehicle) can go about \(range). Eco mode is on.",
                view: RangeCard(vehicle: vehicle, range: range)
            )
        }
    )

    private static let findCharger = AskSkill(
        id: "findCharger",
        domainID: "trip",
        title: "Find a charger",
        summary: "Nearest fast charger",
        contextKeys: ["chargerName", "chargerDistance", "openStalls"],
        routingNotes: "Where to plug in, nearby chargers, and open stalls.",
        fulfillment: .intent { invocation in
            let name = invocation.context.value(for: "chargerName") ?? Self.chargerName
            let distance = invocation.context.value(for: "chargerDistance") ?? Self.chargerDistance
            let stalls = invocation.context.value(for: "openStalls") ?? Self.openStalls
            return AskIntentCard(
                title: name,
                spoken: "The nearest fast charger is ready. \(stalls) stalls are open. I can open the map.",
                coveredPhrases: ["stalls are open"],
                action: AskAction(id: "map", title: "Map"),
                facts: "\(name) is \(distance) away. \(stalls) stalls are open. It is a 150 kW charger.",
                view: ChargerCard(name: name, distance: distance, openStalls: stalls)
            )
        }
    )
}
