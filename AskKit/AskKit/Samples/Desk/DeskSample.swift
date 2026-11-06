import AskKit
import AskKitUI
import SwiftUI

/// Ask Desk. Eighteen skills across visit, workplace, building, and schedule.
/// Three host specialists cover visitors, rooms, and packages. Each has a working title in the status line.
///
/// `guide` appends desk lines onto the built-in AskGuide prompts.
/// A reply prompt is QUESTION, SKILL, FACTS, the DESK section, and CONVERSATION.
/// The chat shows the first three chips. Type a phrase below, or the skill id alone, for the rest.
enum DeskSample {
    static let opens = "8 a.m."
    static let closes = "6 p.m."
    static let guest = "Ada"
    static let host = "Jordan"
    static let room = "Birch"
    static let freeUntil = "3 p.m."
    static let packageFor = "Jordan"
    static let network = "FrontDesk"
    static let parkingRow = "row C"
    static let floor = "floor 4"
    static let printerName = "Oak"
    static let roomCapacity = "6"
    static let coffeeUntil = "4 p.m."
    static let lostItem = "a black umbrella"
    static let lobbyTemperature = "70 degrees"
    static let nextGuest = "Sam"
    static let nextGuestTime = "2 p.m."

    /// Appends desk lines onto the built-in AskGuide prompts. Use `.replace` to drop a built-in block.
    static let guide = AskGuide(
        routeOpening: .append("This assistant answers questions about the front desk."),
        routeRules: .append("""
        hours is when the desk opens and closes. pass is today's visitor pass. wifi is the lobby network. \
        restroom is where to find the bathroom. parking is visitor parking. badge is printing a visitor badge.
        room is which meeting room is free. packages is a delivery at the desk. directory is where a person sits. \
        printer is the office printer. capacity is how many people the room holds. coffee is the lounge coffee.
        elevator is where the elevators are. lostFound is lost and found. emergency is the exit. \
        lobbyTemp is the lobby temperature.
        nextVisitor is who comes next. afterHours is who to call after closing.
        Do not invent a guest, a room, or a package.
        """),
        replyInstructions: .append("Do not invent names, rooms, or times."),
        followUpInstructions: .append("Do not invent names or times.")
    )

    static func assistant(persistence: AskPersistence = .memory) throws -> AskAssistant {
        try AskAssistant(AskConfiguration(
            assistantName: "Ask Desk",
            persistence: persistence,
            domains: [
                AskDomain(
                    id: "visit",
                    summary: "Front desk",
                    routingNotes: "Hours, the visitor pass, Wi-Fi, the restroom, parking, and a badge."
                ),
                AskDomain(
                    id: "workplace",
                    summary: "Rooms and people",
                    routingNotes: "A free meeting room, packages, where someone sits, the printer, room size, and coffee."
                ),
                AskDomain(
                    id: "building",
                    summary: "Building",
                    routingNotes: "Elevators, lost and found, the emergency exit, and the lobby temperature."
                ),
                AskDomain(
                    id: "schedule",
                    summary: "Schedule",
                    routingNotes: "The next visitor, and who to call after the desk closes."
                )
            ],
            skills: skills,
            context: { context() },
            chips: { _ in chips },
            fastPath: { route($0) },
            guide: guide,
            specialists: specialists
        ))
    }

    /// Host specialists. Matching questions show each working title beside the thinking orb.
    private static let specialists: [AskSpecialist] = [
        SampleSpecialist.lookup(
            id: "desk.visitor",
            title: "Visitor",
            symbolName: "person.text.rectangle",
            workingTitle: "Checking today's visitor",
            toolName: "visitor",
            toolDescription: "Today's visitor pass and host.",
            result: "\(guest) is visiting \(host). The visitor badge prints at the desk.",
            words: ["visitor", "guest", "pass", "badge", "ada"]
        ),
        SampleSpecialist.lookup(
            id: "desk.room",
            title: "Room",
            symbolName: "door.left.hand.open",
            workingTitle: "Checking meeting rooms",
            toolName: "room",
            toolDescription: "Which meeting room is free this afternoon.",
            result: "\(room) is free until \(freeUntil) and holds \(roomCapacity) people.",
            words: ["room", "birch", "meeting", "capacity", "seats"]
        ),
        SampleSpecialist.lookup(
            id: "desk.packages",
            title: "Packages",
            symbolName: "shippingbox",
            workingTitle: "Checking packages",
            toolName: "packages",
            toolDescription: "Deliveries waiting at the desk.",
            result: "One package for \(packageFor) is at the desk.",
            words: ["package", "packages", "delivery", "parcel", "mail"]
        )
    ]

    static func context() -> AskContext {
        AskContext(
            promptBlock: """
            opens=\(opens) closes=\(closes) guest=\(guest) host=\(host) \
            room=\(room) freeUntil=\(freeUntil) packageFor=\(packageFor) \
            wifi=\(network) parking=\(parkingRow) floor=\(floor) printer=\(printerName) \
            capacity=\(roomCapacity) coffeeUntil=\(coffeeUntil) lost=\(lostItem) \
            lobby=\(lobbyTemperature) next=\(nextGuest) at=\(nextGuestTime)
            """,
            values: [
                "opens": opens,
                "closes": closes,
                "guest": guest,
                "host": host,
                "room": room,
                "freeUntil": freeUntil,
                "packageFor": packageFor
            ],
            sections: [
                AskPromptSection(
                    title: "DESK",
                    text: """
                    The desk is open from \(opens) until \(closes). After \(closes), call security on the lobby phone.
                    \(guest) is visiting \(host). The visitor badge prints at the desk. Wi-Fi is \(network). The password is at the desk.
                    Visitor parking is \(parkingRow). The restroom is down the hall on the left.
                    \(room) is free until \(freeUntil) and holds \(roomCapacity) people. \(host) sits on \(floor). The \(printerName) printer has paper.
                    Coffee is in the lounge until \(coffeeUntil). One package for \(packageFor) is at the desk.
                    Elevators are past the desk on the right. \(lostItem.capitalized) is in lost and found.
                    The emergency exit is at the end of the hall. The lobby is \(lobbyTemperature).
                    The next visitor is \(nextGuest) at \(nextGuestTime).
                    """
                )
            ]
        )
    }

    /// The chat shows the first three. The other fifteen are typed.
    static let chips: [AskChip] = [
        AskChip(id: "hours", skillID: "hours", title: "What time do you close?"),
        AskChip(id: "pass", skillID: "pass", title: "Visitor pass"),
        AskChip(id: "room", skillID: "room", title: "Meeting room")
    ]

    /// First matching phrase wins. Typing the skill id alone also matches.
    static func route(_ utterance: String) -> AskRoute? {
        SampleSkill.route(utterance, ids: skills.map(\.id), keywords: [
            ("afterHours", ["after hours", "security", "lobby phone"]),
            ("nextVisitor", ["next visitor", "appointment", "sam"]),
            ("lobbyTemp", ["lobby temperature", "thermostat", "how warm", "how cold"]),
            ("emergency", ["emergency", "fire exit", "the exit", "stairs"]),
            ("lostFound", ["lost and found", "umbrella"]),
            ("elevator", ["elevator"]),
            ("coffee", ["coffee", "lounge"]),
            ("capacity", ["capacity", "how many seats", "holds", "how many fit"]),
            ("badge", ["badge"]),
            ("printer", ["printer", "print"]),
            ("directory", ["directory", "what floor", "where is jordan", "floor 4"]),
            ("packages", ["package", "delivery", "parcel"]),
            ("room", ["meeting room", "birch", "book a room", "meeting"]),
            ("parking", ["parking", "row c", "visitor spot"]),
            ("restroom", ["restroom", "bathroom", "washroom"]),
            ("wifi", ["wifi", "wi-fi", "password", "network"]),
            ("pass", ["visitor pass", "visitor", "guest", "ada"]),
            ("hours", ["closing time", "what time do you close", "hours", "when do you open", "when do you close"])
        ])
    }

    private static let skills: [AskSkill] = [
        hours, pass, roomBooking, packages
    ] + extras.map(SampleSkill.make)

    private static let extras: [SampleSkillSpec] = [
        SampleSkillSpec(
            id: "wifi",
            domainID: "visit",
            title: "Wi-Fi",
            summary: "The lobby wireless network",
            routingNotes: "Wi-Fi, the network name, and where to get the password.",
            spoken: "The network is \(network). Ask the desk for the password.",
            facts: "Wi-Fi is \(network). The password is posted at the desk.",
            headline: network,
            detail: "Password is at the desk",
            actionTitle: "Wi-Fi",
            covered: [network],
            workingTitle: "Checking Wi-Fi"
        ),
        SampleSkillSpec(
            id: "restroom",
            domainID: "visit",
            title: "Restroom",
            summary: "Where the visitor restroom is",
            routingNotes: "The restroom, bathroom, and washroom.",
            spoken: "The restroom is down the hall on the left.",
            facts: "The restroom is down the hall on the left.",
            headline: "Down the hall",
            detail: "On the left",
            actionTitle: "Restroom",
            covered: ["down the hall"],
            workingTitle: "Checking the restroom"
        ),
        SampleSkillSpec(
            id: "parking",
            domainID: "visit",
            title: "Parking",
            summary: "Where a visitor can park",
            routingNotes: "Visitor parking, row C, and visitor spots.",
            spoken: "Visitor parking is \(parkingRow). The first hour is free.",
            facts: "Visitor parking is \(parkingRow). The first hour is free.",
            headline: parkingRow.capitalized,
            detail: "First hour free",
            actionTitle: "Parking",
            covered: [parkingRow],
            workingTitle: "Checking parking"
        ),
        SampleSkillSpec(
            id: "badge",
            domainID: "visit",
            title: "Badge",
            summary: "Printing a badge for today's visitor",
            routingNotes: "A visitor badge and printing it at the desk.",
            spoken: "The badge for \(guest) prints at the desk.",
            facts: "The visitor badge for \(guest) prints at the desk.",
            headline: guest,
            detail: "Prints at the desk",
            actionTitle: "Badge",
            covered: [guest],
            workingTitle: "Checking the badge"
        ),
        SampleSkillSpec(
            id: "directory",
            domainID: "workplace",
            title: "Directory",
            summary: "Where a person sits in the building",
            routingNotes: "The directory, which floor someone is on, and where Jordan sits.",
            spoken: "\(host) is on \(floor).",
            facts: "\(host) sits on \(floor).",
            headline: host,
            detail: floor.capitalized,
            actionTitle: "Directory",
            covered: [floor],
            workingTitle: "Looking up the directory"
        ),
        SampleSkillSpec(
            id: "printer",
            domainID: "workplace",
            title: "Printer",
            summary: "Which office printer has paper",
            routingNotes: "The printer and whether it has paper.",
            spoken: "The \(printerName) printer has paper.",
            facts: "The \(printerName) printer has paper and is ready.",
            headline: printerName,
            detail: "Paper loaded",
            actionTitle: "Printer",
            covered: [printerName],
            workingTitle: "Checking the printer"
        ),
        SampleSkillSpec(
            id: "capacity",
            domainID: "workplace",
            title: "Room size",
            summary: "How many people the free meeting room holds",
            routingNotes: "Room capacity, how many seats, and how many people fit.",
            spoken: "\(room) holds \(roomCapacity) people.",
            facts: "\(room) holds \(roomCapacity) people.",
            headline: roomCapacity,
            detail: room,
            actionTitle: "Capacity",
            covered: [roomCapacity],
            workingTitle: "Checking room size"
        ),
        SampleSkillSpec(
            id: "coffee",
            domainID: "workplace",
            title: "Coffee",
            summary: "Where coffee is and until when",
            routingNotes: "Coffee in the lounge and when it is put away.",
            spoken: "Coffee is in the lounge until \(coffeeUntil).",
            facts: "Coffee is in the lounge until \(coffeeUntil).",
            headline: "Until \(coffeeUntil)",
            detail: "Lounge",
            actionTitle: "Coffee",
            covered: [coffeeUntil],
            workingTitle: "Checking coffee"
        ),
        SampleSkillSpec(
            id: "elevator",
            domainID: "building",
            title: "Elevators",
            summary: "Where the elevators are from the desk",
            routingNotes: "The elevators past the desk.",
            spoken: "The elevators are past the desk on the right.",
            facts: "The elevators are past the desk on the right.",
            headline: "On the right",
            detail: "Past the desk",
            actionTitle: "Elevators",
            covered: ["on the right"],
            workingTitle: "Checking elevators"
        ),
        SampleSkillSpec(
            id: "lostFound",
            domainID: "building",
            title: "Lost and found",
            summary: "An item waiting in lost and found",
            routingNotes: "Lost and found, and the umbrella turned in today.",
            spoken: "\(lostItem.capitalized) is in lost and found.",
            facts: "\(lostItem.capitalized) is in lost and found.",
            headline: "Umbrella",
            detail: "Turned in today",
            actionTitle: "Lost and found",
            covered: ["umbrella"],
            workingTitle: "Checking lost and found"
        ),
        SampleSkillSpec(
            id: "emergency",
            domainID: "building",
            title: "Exit",
            summary: "Where the emergency exit is",
            routingNotes: "The emergency exit, the fire exit, and the stairs.",
            spoken: "The exit is at the end of the hall. The stairs are on the left.",
            facts: "The emergency exit is at the end of the hall. The stairs are on the left.",
            headline: "End of the hall",
            detail: "Stairs on the left",
            actionTitle: "Exit",
            covered: ["end of the hall"],
            workingTitle: "Checking the exit"
        ),
        SampleSkillSpec(
            id: "lobbyTemp",
            domainID: "building",
            title: "Lobby",
            summary: "The temperature in the lobby",
            routingNotes: "Lobby temperature and the thermostat.",
            spoken: "The lobby is \(lobbyTemperature).",
            facts: "The lobby is \(lobbyTemperature).",
            headline: lobbyTemperature,
            detail: "Lobby",
            actionTitle: "Temperature",
            covered: [lobbyTemperature],
            workingTitle: "Checking lobby temperature"
        ),
        SampleSkillSpec(
            id: "nextVisitor",
            domainID: "schedule",
            title: "Next visitor",
            summary: "Who is expected at the desk next",
            routingNotes: "The next visitor, Sam, and the next appointment.",
            spoken: "\(nextGuest) is expected at \(nextGuestTime) to see \(host).",
            facts: "The next visitor is \(nextGuest) at \(nextGuestTime), here to see \(host).",
            headline: nextGuest,
            detail: nextGuestTime,
            actionTitle: "Next",
            covered: [nextGuestTime],
            workingTitle: "Checking the next visitor"
        ),
        SampleSkillSpec(
            id: "afterHours",
            domainID: "schedule",
            title: "After hours",
            summary: "Who to call after the desk closes",
            routingNotes: "After hours, security, and the lobby phone.",
            spoken: "After \(closes), call security on the lobby phone.",
            facts: "After \(closes), call security on the lobby phone.",
            headline: "Security",
            detail: "Lobby phone",
            actionTitle: "After hours",
            covered: [closes],
            workingTitle: "Checking after hours"
        )
    ]

    private static let hours = AskSkill(
        id: "hours",
        domainID: "visit",
        title: "Hours",
        summary: "When the front desk is open",
        contextKeys: ["opens", "closes"],
        routingNotes: "Opening time, closing time, and whether the desk is open.",
        fulfillment: .reply { invocation in
            AskChatActivity.update("Checking desk hours")
            let opens = invocation.context.value(for: "opens") ?? Self.opens
            let closes = invocation.context.value(for: "closes") ?? Self.closes
            return AskReply(
                text: "The desk is open from \(opens) until \(closes).",
                spoken: "The desk is open from \(opens) until \(closes).",
                actions: [AskAction(id: "hours", title: "Hours")],
                facts: "The desk opens at \(opens) and closes at \(closes)."
            )
        }
    )

    private static let pass = AskSkill(
        id: "pass",
        domainID: "visit",
        title: "Visitor pass",
        summary: "Today's visitor pass",
        contextKeys: ["guest", "host"],
        routingNotes: "A visitor pass, who it is for, and who they are meeting.",
        fulfillment: .intent { invocation in
            AskChatActivity.update("Checking today's visitor")
            let guest = invocation.context.value(for: "guest") ?? Self.guest
            let host = invocation.context.value(for: "host") ?? Self.host
            return AskIntentCard(
                title: "Visitor pass",
                spoken: "The visitor pass for \(guest) is ready. \(host) is the host.",
                replacesBubble: true,
                action: AskAction(id: "pass", title: "Show pass"),
                facts: "The visitor pass for \(guest) is ready. \(host) is the host. It is valid today.",
                view: PassCard(guest: guest, host: host)
            )
        }
    )

    private static let roomBooking = AskSkill(
        id: "room",
        domainID: "workplace",
        title: "Meeting room",
        summary: "The room that is free this afternoon",
        contextKeys: ["room", "freeUntil"],
        routingNotes: "Booking a meeting room and which room is free.",
        fulfillment: .intent { invocation in
            AskChatActivity.update("Checking meeting rooms")
            let room = invocation.context.value(for: "room") ?? Self.room
            let freeUntil = invocation.context.value(for: "freeUntil") ?? Self.freeUntil
            return AskIntentCard(
                title: room,
                spoken: "\(room) is open this afternoon. It is free until \(freeUntil).",
                coveredPhrases: [freeUntil],
                action: AskAction(id: "room", title: "Book"),
                facts: "\(room) is free until \(freeUntil).",
                view: RoomCard(room: room, freeUntil: freeUntil)
            )
        }
    )

    private static let packages = AskSkill(
        id: "packages",
        domainID: "workplace",
        title: "Packages",
        summary: "A delivery waiting at the desk",
        contextKeys: ["packageFor"],
        routingNotes: "Packages, mail, and deliveries waiting to be picked up.",
        fulfillment: .reply { invocation in
            AskChatActivity.update("Checking packages")
            let person = invocation.context.value(for: "packageFor") ?? Self.packageFor
            return AskReply(
                text: "One package for \(person) is at the desk.",
                spoken: "One package for \(person) is at the desk.",
                actions: [AskAction(id: "packages", title: "Packages")],
                facts: "One package for \(person) is at the desk."
            )
        }
    )
}
