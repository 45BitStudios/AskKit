import Evaluations
import Foundation
@testable import AskKit

/// Garage's catalog, prompts, and facts. Kept beside the sample so a score measures that assistant.
struct AskEvalSkill: Sendable, Equatable {
    var id: String
    var domainID: String
    var title: String
    var summary: String
    var routingNotes: String
    var spoken: String
    var facts: String
    var requiredPhrases: [String]
}

struct AskRouteLabel: Codable, Sendable, Equatable {
    var skillID: String
    var domainID: String
    var earlier: [String]
}

struct AskReplyLabel: Codable, Sendable, Equatable {
    var text: String
    var skillID: String
    var facts: String
    var requiredPhrases: [String]
}

struct AskFollowUpLabel: Codable, Sendable, Equatable {
    var skillID: String
    var question: String
    var answeredSkillID: String
    var allowedSkillIDs: [String]
    var plausibleSkillIDs: [String]
    var justAsked: String
    var spoken: String
}

enum AskEvalCatalog {
    static let assistantName = "Ask Garage"

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
        Do not paste the GARAGE section. \
        If a tool returns a calendar event, a reminder, a contact, a place, a health reading, or what is playing, you may say it. \
        If a tool says Not allowed, say you cannot see that.
        """),
        followUpInstructions: .append("Do not invent places or numbers.")
    )

    static let domains: [AskDomain] = [
        AskDomain(id: "battery", summary: "Charging", routingNotes: "Battery percent, the charge limit, charging speed, and whether the cable is connected."),
        AskDomain(id: "cabin", summary: "Cabin", routingNotes: "Warming the cabin before departure, seat heat, and defrost."),
        AskDomain(id: "trip", summary: "Driving", routingNotes: "Range left, a place to plug in, tire pressure, and the miles driven."),
        AskDomain(id: "care", summary: "Upkeep", routingNotes: "Service, washer fluid, software, the doors, and the headlights.")
    ]

    static let context = """
    vehicle=Ioniq 5 battery=68 percent minutesTo80=32 limit=80 percent rate=11 kW plugged=home range=214 miles \
    charger=Electrify America distance=0.4 miles stalls=2 cabin=72 degrees departure=7:30 a.m. seatHeat=low \
    defrost=off tires=36 psi odometer=18,420 miles trip=12 miles efficiency=3.6 miles per kWh service=2,400 miles \
    washer=low software=2026.10 locks=locked lights=off
    """

    static let section = AskPromptSection(
        title: "GARAGE",
        text: """
        The car is an Ioniq 5, plugged in at home, charging at 11 kW.
        The battery is at 68 percent, about 32 minutes from 80 percent. The charge limit is 80 percent.
        The cabin will be 72 degrees by 7:30 a.m. The driver seat heat is low. Front defrost is off.
        Range is 214 miles with Eco mode on. The nearest fast charger is Electrify America, 0.4 miles away, with 2 stalls open.
        Tires are 36 psi. The odometer reads 18,420 miles. This trip is 12 miles. Efficiency is 3.6 miles per kWh.
        Service is due in 2,400 miles, on October 20. Washer fluid is low. Software is 2026.10. The doors are locked. The headlights are off.
        """
    )

    static let skills: [AskEvalSkill] = [
        AskEvalSkill(id: "chargeStatus", domainID: "battery", title: "Charge status", summary: "Current battery and time to 80 percent", routingNotes: "How full the battery is, whether the car is charging at home, and when it reaches 80 percent.", spoken: "Your Ioniq 5 is at 68 percent. About 32 minutes until 80 percent.", facts: "The Ioniq 5 battery is at 68 percent. Charging at home. About 32 minutes until 80 percent.", requiredPhrases: ["68 percent", "32"]),
        AskEvalSkill(id: "chargeLimit", domainID: "battery", title: "Charge limit", summary: "The maximum charge the car is set to reach", routingNotes: "The charge limit and whether charging stops at 80 percent.", spoken: "The charge limit is 80 percent.", facts: "The charge limit on the Ioniq 5 is 80 percent.", requiredPhrases: ["80 percent"]),
        AskEvalSkill(id: "chargeRate", domainID: "battery", title: "Charge rate", summary: "How fast the car is charging right now", routingNotes: "Charging speed at home, in kilowatts.", spoken: "It is charging at 11 kW on the home charger.", facts: "The Ioniq 5 is charging at home at 11 kW.", requiredPhrases: ["11 kW"]),
        AskEvalSkill(id: "plugStatus", domainID: "battery", title: "Plug", summary: "Whether the charge cable is connected", routingNotes: "Plugged in, the latch, and the connector at home.", spoken: "The Ioniq 5 is plugged in at home. The latch is closed.", facts: "The Ioniq 5 is plugged in at home. The charge latch is closed.", requiredPhrases: ["plugged in"]),
        AskEvalSkill(id: "precondition", domainID: "cabin", title: "Precondition", summary: "Warm the cabin before departure", routingNotes: "Cabin temperature, preconditioning, and being ready to leave.", spoken: "Warm the Ioniq 5 before you leave. The cabin will be 72 degrees by 7:30 a.m.", facts: "Warm the Ioniq 5. The cabin will be 72 degrees by 7:30 a.m.", requiredPhrases: ["72 degrees", "7:30"]),
        AskEvalSkill(id: "seatHeat", domainID: "cabin", title: "Seat heat", summary: "Whether the driver seat heater is on", routingNotes: "Heated seat and seat heat level.", spoken: "The driver seat heat is low.", facts: "The driver seat heat in the Ioniq 5 is low.", requiredPhrases: ["low"]),
        AskEvalSkill(id: "defrost", domainID: "cabin", title: "Defrost", summary: "Whether the front defrost is on", routingNotes: "Windshield defrost and the front defroster.", spoken: "Front defrost is off.", facts: "Front defrost on the Ioniq 5 is off.", requiredPhrases: ["off"]),
        AskEvalSkill(id: "rangeLeft", domainID: "trip", title: "Range", summary: "How far the car can go on this charge", routingNotes: "Remaining range, miles left, and how far the car can drive.", spoken: "Your Ioniq 5 can go about 214 miles. Eco mode is on.", facts: "The Ioniq 5 can go about 214 miles. Eco mode is on.", requiredPhrases: ["214 miles"]),
        AskEvalSkill(id: "findCharger", domainID: "trip", title: "Find a charger", summary: "Nearest fast charger", routingNotes: "Where to plug in, nearby chargers, and open stalls.", spoken: "The nearest fast charger is ready. 2 stalls are open. I can open the map.", facts: "Electrify America is 0.4 miles away. 2 stalls are open. It is a 150 kW charger.", requiredPhrases: ["Electrify America", "0.4"]),
        AskEvalSkill(id: "nextDrive", domainID: "trip", title: "Next drive", summary: "When the next drive leaves", routingNotes: "The next drive on the calendar, and where the car is.", spoken: "Your next drive is set for 7:30 a.m. The car can go about 214 miles.", facts: "The next drive is at 7:30 a.m. Range is 214 miles.", requiredPhrases: ["7:30"]),
        AskEvalSkill(id: "tirePressure", domainID: "trip", title: "Tires", summary: "Tire pressure on all four tires", routingNotes: "Tire pressure and psi.", spoken: "All four tires are at 36 psi.", facts: "All four tires on the Ioniq 5 are at 36 psi.", requiredPhrases: ["36 psi"]),
        AskEvalSkill(id: "odometer", domainID: "trip", title: "Odometer", summary: "Total miles on the car", routingNotes: "The odometer and total miles driven.", spoken: "The odometer reads 18,420 miles.", facts: "The Ioniq 5 odometer reads 18,420 miles.", requiredPhrases: ["18,420"]),
        AskEvalSkill(id: "tripMeter", domainID: "trip", title: "This trip", summary: "Miles driven on the current trip", routingNotes: "The trip meter and miles on this drive.", spoken: "This trip is 12 miles.", facts: "The current trip is 12 miles.", requiredPhrases: ["12 miles"]),
        AskEvalSkill(id: "efficiency", domainID: "trip", title: "Efficiency", summary: "Miles the car gets per kilowatt hour", routingNotes: "Driving efficiency and miles per kilowatt hour.", spoken: "Efficiency is 3.6 miles per kWh.", facts: "The Ioniq 5 is getting 3.6 miles per kWh.", requiredPhrases: ["3.6"]),
        AskEvalSkill(id: "nextService", domainID: "care", title: "Service", summary: "When the next service visit is due", routingNotes: "Maintenance, the next service, and miles until it is due.", spoken: "Service is due in 2,400 miles, on October 20.", facts: "Service for the Ioniq 5 is due in 2,400 miles, on October 20.", requiredPhrases: ["2,400", "October 20"]),
        AskEvalSkill(id: "washerFluid", domainID: "care", title: "Washer fluid", summary: "Whether the windshield washer fluid is low", routingNotes: "Washer fluid and the wiper reservoir.", spoken: "Washer fluid is low.", facts: "Washer fluid on the Ioniq 5 is low.", requiredPhrases: ["low"]),
        AskEvalSkill(id: "softwareVersion", domainID: "care", title: "Software", summary: "The software version on the car", routingNotes: "Car software, the version, and whether an update is waiting.", spoken: "Software is 2026.10. It is up to date.", facts: "The Ioniq 5 software is 2026.10. It is up to date.", requiredPhrases: ["2026.10"]),
        AskEvalSkill(id: "lockStatus", domainID: "care", title: "Locks", summary: "Whether the doors are locked", routingNotes: "Door locks, the trunk, and whether the car is locked.", spoken: "The doors are locked. The trunk is closed.", facts: "The Ioniq 5 doors are locked. The trunk is closed.", requiredPhrases: ["locked"]),
        AskEvalSkill(id: "lights", domainID: "care", title: "Lights", summary: "Whether the headlights are on", routingNotes: "Headlights and whether the lights were left on.", spoken: "The headlights are off.", facts: "The Ioniq 5 headlights are off.", requiredPhrases: ["off"])
    ]

    static func skill(_ id: String) -> AskEvalSkill? {
        skills.first { AskEvalScore.same($0.id, id) }
    }

    static func domainID(for skillID: String) -> String {
        skill(skillID)?.domainID ?? ""
    }

    /// Domain of a skill id, or the id itself when the model returned a domain name.
    static func domain(of token: String) -> String {
        AskEvalScore.resolvedDomain(
            of: token,
            skills: skills.map { ($0.id, $0.domainID) },
            domains: domains.map(\.id)
        )
    }

    static func askSkills() -> [AskSkill] {
        skills.map { spec in
            AskSkill(
                id: spec.id,
                domainID: spec.domainID,
                title: spec.title,
                summary: spec.summary,
                routingNotes: spec.routingNotes,
                fulfillment: .reply { _ in
                    AskReply(text: spec.spoken, spoken: spec.spoken, facts: spec.facts)
                }
            )
        }
    }

    static func routeRequest(question: String, earlier: [String]) -> AskModelRequest {
        AskModelRequest(
            instructions: guide.routeInstructions(domains: domains, skills: askSkills()),
            prompt: guide.routePrompt(context: context, earlier: earlier, request: question)
        )
    }

    static func replyRequest(question: String, skill: AskEvalSkill) -> AskModelRequest {
        AskModelRequest(
            instructions: guide.resolvedReplyInstructions,
            prompt: guide.replyPrompt(
                question: question,
                skillID: skill.id,
                facts: skill.facts,
                sections: [section],
                conversation: ""
            ),
            facts: skill.facts
        )
    }

    static func followUpRequest(_ gold: AskFollowUpLabel) -> AskModelRequest {
        let conversation = guide.conversation(
            turns: [("user", gold.justAsked), ("assistant", gold.spoken)],
            assistantName: assistantName
        )
        return AskModelRequest(
            instructions: guide.resolvedFollowUpInstructions,
            prompt: guide.followUpPrompt(
                question: gold.justAsked,
                skillID: gold.answeredSkillID,
                allowed: gold.allowedSkillIDs,
                sections: [section],
                conversation: conversation
            )
        )
    }

    static func allowed(after skillID: String) -> [String] {
        skills.map(\.id).filter { !AskEvalScore.same($0, skillID) }
    }

    static let routeSamples: [ModelSample<AskRouteLabel>] = [
        route("How full is the battery?", "chargeStatus"),
        route("What is the charge limit?", "chargeLimit"),
        route("How fast is it charging?", "chargeRate"),
        route("Is the cable plugged in?", "plugStatus"),
        route("Warm the cabin before I leave", "precondition"),
        route("Is the seat heater on?", "seatHeat"),
        route("Is the front defrost on?", "defrost"),
        route("How much range is left?", "rangeLeft"),
        route("Where is the nearest charger?", "findCharger"),
        route("Where can I plug in?", "findCharger"),
        route("When is the next drive?", "nextDrive"),
        route("What is the tire pressure?", "tirePressure"),
        route("What does the odometer say?", "odometer"),
        route("How many miles on this trip?", "tripMeter"),
        route("What is the efficiency?", "efficiency"),
        route("When is the next service?", "nextService"),
        route("Is the washer fluid low?", "washerFluid"),
        route("What software version is on the car?", "softwareVersion"),
        route("Are the doors locked?", "lockStatus"),
        route("Are the headlights on?", "lights"),
        route("What about the tires?", "tirePressure", earlier: ["How full is the battery?"])
    ]

    static let replySamples: [ModelSample<AskReplyLabel>] = [
        reply("chargeStatus", "How full is the battery?"),
        reply("rangeLeft", "How much range is left?"),
        reply("findCharger", "Where is the nearest charger?"),
        reply("precondition", "Warm the cabin before I leave"),
        reply("tirePressure", "What is the tire pressure?"),
        reply("odometer", "What does the odometer say?")
    ]

    static let followUpSamples: [ModelSample<AskFollowUpLabel>] = [
        followUp("chargeStatus", "How full is the battery?", plausible: ["chargeLimit", "chargeRate", "plugStatus", "rangeLeft", "findCharger", "nextDrive"]),
        followUp("rangeLeft", "How much range is left?", plausible: ["findCharger", "chargeStatus", "efficiency", "nextDrive"]),
        followUp("findCharger", "Where is the nearest charger?", plausible: ["rangeLeft", "plugStatus", "chargeRate", "nextDrive"]),
        followUp("precondition", "Warm the cabin before I leave", plausible: ["seatHeat", "defrost", "nextDrive"]),
        followUp("tirePressure", "What is the tire pressure?", plausible: ["nextService", "rangeLeft", "efficiency"]),
        followUp("lockStatus", "Are the doors locked?", plausible: ["lights", "nextDrive"])
    ]

    private static func route(_ question: String, _ skillID: String, earlier: [String] = []) -> ModelSample<AskRouteLabel> {
        ModelSample(
            prompt: question,
            expected: AskRouteLabel(skillID: skillID, domainID: domainID(for: skillID), earlier: earlier)
        )
    }

    private static func reply(_ skillID: String, _ question: String) -> ModelSample<AskReplyLabel> {
        let skill = skill(skillID)!
        return ModelSample(
            prompt: question,
            expected: AskReplyLabel(text: skill.spoken, skillID: skill.id, facts: skill.facts, requiredPhrases: skill.requiredPhrases)
        )
    }

    private static func followUp(_ skillID: String, _ question: String, plausible: [String]) -> ModelSample<AskFollowUpLabel> {
        let skill = skill(skillID)!
        return ModelSample(
            prompt: question,
            expected: AskFollowUpLabel(
                skillID: "",
                question: "",
                answeredSkillID: skill.id,
                allowedSkillIDs: allowed(after: skill.id),
                plausibleSkillIDs: plausible,
                justAsked: question,
                spoken: skill.spoken
            )
        )
    }
}
