import AskKit
import SwiftUI

/// Ask Pantry. Eighteen skills across meals, supplies, kitchen, and table.
/// Three host specialists cover the clock, pantry stock, and dinner. Each has a working title in the status line.
///
/// `guide` appends pantry lines onto the built-in AskGuide prompts.
/// A reply prompt is QUESTION, SKILL, FACTS, the PANTRY section, and CONVERSATION.
/// The chat shows the first three chips. Type a phrase below, or the skill id alone, for the rest.
enum PantrySample {
    static let dinnerName = "Tomato pasta"
    static let minutes = "25"
    static let servings = "2"
    static let onHand = "pasta, tomatoes, garlic, olive oil, parmesan"
    static let missing = "fresh basil"
    static let market = "the market on 4th"
    static let missingItem = "butter"
    static let standIn = "olive oil"
    static let breakfastName = "Overnight oats"
    static let lunchName = "Tomato toast"
    static let lunchMinutes = "10"
    static let spiceList = "salt, black pepper, chili flakes"
    static let expiryDays = "3 days"
    static let wineLeft = "half a bottle"
    static let tomorrowMeal = "tomato soup"

    /// Appends pantry lines onto the built-in AskGuide prompts. Use `.replace` to drop a built-in block.
    static let guide = AskGuide(
        routeOpening: .append("This assistant answers questions about cooking and the pantry."),
        routeRules: .append("""
        dinner is what to cook tonight. breakfast is the morning meal. lunch is the midday meal. \
        servings is how many people dinner feeds. cookTime is how long dinner takes. steps is how to cook it. \
        substitute is what to use when an ingredient is missing.
        stock is what is already on the shelf. shopping is what still needs to be bought. \
        expiry is how long the tomatoes keep. leftovers is food already cooked. spices is salt, pepper, and chili.
        appliance is the stove and the oven. timer is a kitchen timer. diet is restrictions on file.
        wine is what is open to drink. guests is whether anyone extra is coming. mealPlan is tomorrow's meal.
        Do not invent a meal or an ingredient.
        """),
        replyInstructions: .append("Do not invent ingredients, times, or stores."),
        followUpInstructions: .append("Do not invent ingredients or stores.")
    )

    static func assistant() throws -> AskAssistant {
        try AskAssistant(AskConfiguration(
            assistantName: "Ask Pantry",
            persistence: .memory,
            domains: [
                AskDomain(
                    id: "meals",
                    summary: "Cooking",
                    routingNotes: "What to cook, how long it takes, how to make it, and what to use when something is missing."
                ),
                AskDomain(
                    id: "supplies",
                    summary: "Pantry and shopping",
                    routingNotes: "What is on hand, what to buy, what is going bad, and which spices are on the shelf."
                ),
                AskDomain(
                    id: "kitchen",
                    summary: "Kitchen",
                    routingNotes: "The stove, a running timer, and diet notes."
                ),
                AskDomain(
                    id: "table",
                    summary: "Table",
                    routingNotes: "Who is eating, what is poured, and tomorrow's meal."
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
        AskSpecialist(
            id: "pantry.clock",
            title: "Clock",
            symbolName: "clock",
            workingTitle: "Checking the time",
            instructions: """
            Call the clock tool once and say the time it returns. \
            If it says Not allowed, say you cannot see that. Do not invent the time.
            """,
            tools: { [SampleClockTool()] },
            matches: { SampleSpecialist.matches($0, anyOf: ["time", "clock"]) }
        ),
        SampleSpecialist.lookup(
            id: "pantry.stock",
            title: "Pantry",
            symbolName: "refrigerator",
            workingTitle: "Checking the pantry",
            toolName: "stock",
            toolDescription: "Ingredients already on the shelf.",
            result: "On hand: \(onHand). Spices: \(spiceList). Still need \(missing).",
            words: ["pantry", "stock", "ingredient", "hand", "spice", "spices"]
        ),
        SampleSpecialist.lookup(
            id: "pantry.dinner",
            title: "Dinner",
            symbolName: "fork.knife",
            workingTitle: "Looking up dinner",
            toolName: "dinner",
            toolDescription: "Tonight's meal from what is on hand.",
            result: "Dinner is \(dinnerName). It takes \(minutes) minutes and serves \(servings).",
            words: ["dinner", "cook", "recipe", "pasta", "meal", "eat"]
        )
    ]

    static func context() -> AskContext {
        AskContext(
            promptBlock: """
            dinner=\(dinnerName) minutes=\(minutes) servings=\(servings) \
            breakfast=\(breakfastName) lunch=\(lunchName) \
            onHand=\(onHand) missing=\(missing) market=\(market) \
            no \(missingItem), use \(standIn) spices=\(spiceList) \
            tomatoesGood=\(expiryDays) leftovers=none stove=free oven=off timer=none \
            diet=none wine=\(wineLeft) guests=none tomorrow=\(tomorrowMeal)
            """,
            values: [
                "dinnerName": dinnerName,
                "minutes": minutes,
                "servings": servings,
                "onHand": onHand,
                "missing": missing,
                "market": market,
                "missingItem": missingItem,
                "standIn": standIn
            ],
            sections: [
                AskPromptSection(
                    title: "PANTRY",
                    text: """
                    Dinner is \(dinnerName), \(minutes) minutes, serves \(servings). Breakfast is \(breakfastName). Lunch is \(lunchName), \(lunchMinutes) minutes.
                    On hand: \(onHand). Spices: \(spiceList).
                    Still need \(missing) from \(market). There is no \(missingItem). Use \(standIn).
                    The tomatoes are good for \(expiryDays). There are no leftovers.
                    The stove is free and the oven is off. No timer is running. No diet restrictions are on file.
                    \(wineLeft.capitalized) of red is open. Dinner is for \(servings), with no extra guests. Tomorrow is \(tomorrowMeal).
                    """
                )
            ]
        )
    }

    /// The chat shows the first three. The other fifteen are typed.
    static let chips: [AskChip] = [
        AskChip(id: "dinner", skillID: "dinner", title: "What's for dinner?"),
        AskChip(id: "stock", skillID: "stock", title: "What's on hand?"),
        AskChip(id: "shopping", skillID: "shopping", title: "Shopping list")
    ]

    /// First matching phrase wins. Typing the skill id alone also matches.
    static func route(_ utterance: String) -> AskRoute? {
        SampleSkill.route(utterance, ids: skills.map(\.id), keywords: [
            ("mealPlan", ["tomorrow", "meal plan", "soup"]),
            ("guests", ["guest", "coming over", "company"]),
            ("wine", ["wine", "bottle", "something to drink"]),
            ("diet", ["diet", "restriction", "vegan", "allergy", "gluten"]),
            ("timer", ["timer"]),
            ("appliance", ["stove", "oven", "burner", "appliance"]),
            ("spices", ["spice", "pepper", "chili", "salt"]),
            ("leftovers", ["leftover"]),
            ("expiry", ["expire", "expiry", "goes bad", "still good"]),
            ("shopping", ["shop", "shopping", "buy", "basil", "missing"]),
            ("substitute", ["butter", "substitute", "instead", "swap", "cream"]),
            ("breakfast", ["breakfast", "oats", "oatmeal"]),
            ("lunch", ["lunch", "toast"]),
            ("steps", ["step", "boil", "simmer", "how do i make"]),
            ("cookTime", ["how long", "cook time", "how many minutes"]),
            ("servings", ["serving", "servings", "how many does it feed"]),
            ("dinner", ["dinner", "cook", "pasta", "meal", "recipe", "eat"]),
            ("stock", ["on hand", "pantry", "ingredient", "in stock", "what do we have"])
        ])
    }

    private static let skills: [AskSkill] = [
        dinner, substitute, stock, shopping
    ] + extras.map(SampleSkill.make)

    private static let extras: [SampleSkillSpec] = [
        SampleSkillSpec(
            id: "breakfast",
            domainID: "meals",
            title: "Breakfast",
            summary: "The meal ready in the morning",
            routingNotes: "Breakfast and overnight oats.",
            spoken: "\(breakfastName) is ready in the morning. It serves \(servings).",
            facts: "Breakfast is \(breakfastName). It serves \(servings).",
            headline: breakfastName,
            detail: "Ready in the morning",
            actionTitle: "Breakfast",
            covered: [breakfastName],
            workingTitle: "Checking breakfast"
        ),
        SampleSkillSpec(
            id: "lunch",
            domainID: "meals",
            title: "Lunch",
            summary: "A quick meal for the middle of the day",
            routingNotes: "Lunch and tomato toast.",
            spoken: "\(lunchName) takes \(lunchMinutes) minutes.",
            facts: "Lunch is \(lunchName). It takes \(lunchMinutes) minutes.",
            headline: lunchName,
            detail: "\(lunchMinutes) min",
            actionTitle: "Lunch",
            covered: [lunchMinutes],
            workingTitle: "Checking lunch"
        ),
        SampleSkillSpec(
            id: "servings",
            domainID: "meals",
            title: "Servings",
            summary: "How many people dinner feeds",
            routingNotes: "Servings and how many people the meal feeds.",
            spoken: "\(dinnerName) serves \(servings).",
            facts: "\(dinnerName) serves \(servings).",
            headline: servings,
            detail: dinnerName,
            actionTitle: "Servings",
            covered: [servings],
            workingTitle: "Checking servings"
        ),
        SampleSkillSpec(
            id: "cookTime",
            domainID: "meals",
            title: "Cook time",
            summary: "How long dinner takes to cook",
            routingNotes: "Cook time and how many minutes dinner needs.",
            spoken: "\(dinnerName) takes \(minutes) minutes.",
            facts: "\(dinnerName) takes \(minutes) minutes.",
            headline: "\(minutes) min",
            detail: dinnerName,
            actionTitle: "Time",
            covered: [minutes],
            workingTitle: "Checking cook time"
        ),
        SampleSkillSpec(
            id: "steps",
            domainID: "meals",
            title: "Steps",
            summary: "How to cook tonight's dinner",
            routingNotes: "The recipe steps: boil, simmer, and toss.",
            spoken: "Boil the pasta, simmer the tomatoes, then toss them together.",
            facts: "Boil the pasta. Simmer the tomatoes. Toss them with garlic, olive oil, and parmesan.",
            headline: "Boil, simmer, toss",
            detail: dinnerName,
            actionTitle: "Steps",
            covered: ["Boil the pasta"],
            workingTitle: "Checking the steps"
        ),
        SampleSkillSpec(
            id: "expiry",
            domainID: "supplies",
            title: "Tomatoes",
            summary: "How long the fresh tomatoes will keep",
            routingNotes: "Expiry, whether the tomatoes are still good, and when they go bad.",
            spoken: "The tomatoes are good for \(expiryDays).",
            facts: "The tomatoes are good for \(expiryDays).",
            headline: expiryDays,
            detail: "Still good",
            actionTitle: "Freshness",
            covered: [expiryDays],
            workingTitle: "Checking freshness"
        ),
        SampleSkillSpec(
            id: "leftovers",
            domainID: "supplies",
            title: "Leftovers",
            summary: "Food already cooked and waiting in the fridge",
            routingNotes: "Leftovers in the fridge.",
            spoken: "There are no leftovers in the fridge.",
            facts: "There are no leftovers in the fridge.",
            headline: "None",
            detail: "Fridge is clear",
            actionTitle: "Leftovers",
            covered: ["no leftovers"],
            workingTitle: "Checking leftovers"
        ),
        SampleSkillSpec(
            id: "spices",
            domainID: "supplies",
            title: "Spices",
            summary: "Seasonings already on the shelf",
            routingNotes: "Salt, pepper, chili flakes, and other spices.",
            spoken: "The shelf has \(spiceList).",
            facts: "Spices on hand: \(spiceList).",
            headline: "On the shelf",
            detail: spiceList.capitalized,
            actionTitle: "Spices",
            covered: [spiceList],
            workingTitle: "Checking spices"
        ),
        SampleSkillSpec(
            id: "appliance",
            domainID: "kitchen",
            title: "Stove",
            summary: "Whether the stove and oven are free",
            routingNotes: "The stove, the oven, and the burners.",
            spoken: "The stove is free. The oven is off.",
            facts: "The stove is free. The oven is off.",
            headline: "Free",
            detail: "Oven is off",
            actionTitle: "Stove",
            covered: ["stove is free"],
            workingTitle: "Checking the stove"
        ),
        SampleSkillSpec(
            id: "timer",
            domainID: "kitchen",
            title: "Timer",
            summary: "Whether a kitchen timer is running",
            routingNotes: "A kitchen timer and whether one is running.",
            spoken: "No timer is running.",
            facts: "No kitchen timer is running.",
            headline: "Not running",
            detail: "Nothing on the clock",
            actionTitle: "Timer",
            covered: ["No timer"],
            workingTitle: "Checking the timer"
        ),
        SampleSkillSpec(
            id: "diet",
            domainID: "kitchen",
            title: "Diet",
            summary: "Diet restrictions saved for this kitchen",
            routingNotes: "Allergies, vegan, gluten, and other diet restrictions.",
            spoken: "No diet restrictions are on file.",
            facts: "No diet restrictions are on file.",
            headline: "None on file",
            detail: "No allergies listed",
            actionTitle: "Diet",
            covered: ["No diet"],
            workingTitle: "Checking diet notes"
        ),
        SampleSkillSpec(
            id: "wine",
            domainID: "table",
            title: "Wine",
            summary: "What is open to drink with dinner",
            routingNotes: "Wine, an open bottle, and something to drink.",
            spoken: "\(wineLeft.capitalized) of red is open.",
            facts: "\(wineLeft.capitalized) of red wine is open.",
            headline: wineLeft.capitalized,
            detail: "Red, already open",
            actionTitle: "Wine",
            covered: [wineLeft],
            workingTitle: "Checking the wine"
        ),
        SampleSkillSpec(
            id: "guests",
            domainID: "table",
            title: "Guests",
            summary: "Whether anyone extra is coming to dinner",
            routingNotes: "Guests, company, and people coming over.",
            spoken: "Dinner is for \(servings). No extra guests.",
            facts: "Dinner is for \(servings). No extra guests are coming.",
            headline: "No guests",
            detail: "Set for \(servings)",
            actionTitle: "Guests",
            covered: ["No extra guests"],
            workingTitle: "Checking guests"
        ),
        SampleSkillSpec(
            id: "mealPlan",
            domainID: "table",
            title: "Tomorrow",
            summary: "The meal planned for tomorrow",
            routingNotes: "Tomorrow's meal, the meal plan, and soup.",
            spoken: "Tomorrow is \(tomorrowMeal).",
            facts: "Tomorrow's meal is \(tomorrowMeal).",
            headline: tomorrowMeal.capitalized,
            detail: "Tomorrow",
            actionTitle: "Plan",
            covered: [tomorrowMeal],
            workingTitle: "Checking tomorrow's meal"
        )
    ]

    private static let dinner = AskSkill(
        id: "dinner",
        domainID: "meals",
        title: "Dinner",
        summary: "The meal the pantry can make tonight",
        contextKeys: ["dinnerName", "minutes", "servings", "onHand"],
        routingNotes: "What is for dinner, what to cook, and the recipe from what is on hand.",
        fulfillment: .intent { invocation in
            AskChatActivity.update("Looking up dinner")
            let name = invocation.context.value(for: "dinnerName") ?? Self.dinnerName
            let minutes = invocation.context.value(for: "minutes") ?? Self.minutes
            let servings = invocation.context.value(for: "servings") ?? Self.servings
            let onHand = invocation.context.value(for: "onHand") ?? Self.onHand
            return AskIntentCard(
                title: name,
                spoken: "\(name) is ready to cook. It takes \(minutes) minutes and serves \(servings).",
                coveredPhrases: ["\(minutes) minutes"],
                action: AskAction(id: "recipe", title: "Recipe"),
                facts: "\(name) takes \(minutes) minutes and serves \(servings). On hand: \(onHand).",
                view: DinnerCard(name: name, minutes: minutes, servings: servings, onHand: onHand)
            )
        }
    )

    private static let substitute = AskSkill(
        id: "substitute",
        domainID: "meals",
        title: "Substitute",
        summary: "What to use when an ingredient is missing",
        contextKeys: ["missingItem", "standIn"],
        routingNotes: "Replacing butter, cream, or another ingredient that is not in the pantry.",
        fulfillment: .reply { invocation in
            AskChatActivity.update("Finding a substitute")
            let missing = invocation.context.value(for: "missingItem") ?? Self.missingItem
            let standIn = invocation.context.value(for: "standIn") ?? Self.standIn
            return AskReply(
                text: "There is no \(missing). Use the \(standIn) you have.",
                spoken: "There is no \(missing). Use the \(standIn) you have.",
                actions: [AskAction(id: "swap", title: "Swap")],
                facts: "There is no \(missing). Use \(standIn)."
            )
        }
    )

    private static let stock = AskSkill(
        id: "stock",
        domainID: "supplies",
        title: "On hand",
        summary: "What is already in the pantry",
        contextKeys: ["onHand"],
        routingNotes: "Listing the pantry, ingredients on hand, and what you already have.",
        fulfillment: .intent { invocation in
            AskChatActivity.update("Checking the pantry")
            let onHand = invocation.context.value(for: "onHand") ?? Self.onHand
            return AskIntentCard(
                title: "On hand",
                spoken: "The pantry has \(onHand). That is enough for dinner.",
                coveredPhrases: [onHand],
                action: AskAction(id: "pantry", title: "Pantry"),
                facts: "On hand: \(onHand).",
                view: StockCard(onHand: onHand)
            )
        }
    )

    private static let shopping = AskSkill(
        id: "shopping",
        domainID: "supplies",
        title: "Shopping list",
        summary: "The ingredient still to buy",
        contextKeys: ["missing", "market"],
        routingNotes: "The shopping list, what is missing, and where to buy it.",
        fulfillment: .intent { invocation in
            AskChatActivity.update("Checking the shopping list")
            let missing = invocation.context.value(for: "missing") ?? Self.missing
            let market = invocation.context.value(for: "market") ?? Self.market
            return AskIntentCard(
                title: "Shopping list",
                spoken: "You still need \(missing). \(market.capitalized) has it.",
                coveredPhrases: [missing],
                action: AskAction(id: "list", title: "List"),
                facts: "Still need \(missing) from \(market).",
                view: ShoppingCard(missing: missing, market: market)
            )
        }
    )
}
