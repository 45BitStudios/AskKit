# Running the Ask Garage Siri evaluations

These evaluations drive Siri on a signed iPhone. They do not run in the simulator, and `swift test` does not compile them. The fixture check below does run in the package tests.

The symbols in `AskKit/AskKitSiriEvaluations/AskGarageSiriEvaluation.swift` are the iOS 27.3 `SiriEvaluations` and `AppIntentsTesting` API: `SiriService.run(scenario:)`, `SiriScenario`, `SiriScenarioLoader`, `UserTurn`, `Calls(.ordered)`, `Calls(.disallowed)`, `Loads(.required)`, `SiriResponse(.contains(_:caseSensitive:))`, `SiriExpectationEvaluator`, `Evaluation.computeSiriMetrics(into:)`, `IntentDefinitions(bundleIdentifier:)`, `.intents`, `.skills`, `.evaluates`, and `EvaluationContext`. The four tools take no parameters, so the expectations do not use `expect`.

## Fixture check (simulator or `swift test`)

This does not start Siri.

```sh
xcodebuild test -scheme AskKit-Package -destination 'platform=iOS Simulator,name=iPhone 18 Pro,OS=27.3' -skip-testing:AskKitEvaluations -only-testing:AskKitTests/AskGarageSiriEvalFixtureTests
```

## Device run

1. Use Xcode 27.3 (this repo was checked against beta 27C5020n). The evaluations target sets `ASK_SAMPLE_SIRI_TOOLS`. Xcode 27.2 does not have `SiriEvaluations`.
2. Open `AskKit/AskKit.xcodeproj`.
3. The evaluations target does not set a development team. In Signing & Capabilities for `AskKitSiriEvaluations`, choose the same team as the AskKit app. Do not commit that change from this task.
4. Connect an iPhone on iOS 27.3. Turn on Developer Mode. In Settings > Developer, turn on Enable UI Automation. Turn on Siri and Apple Intelligence, and let the models finish downloading.
5. Select the AskKit scheme and the phone. Run the app once, and leave Ask Garage selected. Siri only sees the tools after that launch.
6. Select the `AskKitSiriEvaluations` scheme. Its test plan is `AskKit/AskKitSiriEvaluations.xctestplan`. Parallel testing is off.
7. Product > Test, with the phone as the destination. Or:

```sh
xcodebuild test -project AskKit/AskKit.xcodeproj -scheme AskKitSiriEvaluations -destination 'id=DEVICE_UDID' -only-testing:AskKitSiriEvaluations
```

Replace `DEVICE_UDID` with the phone from `xcrun xctrace list devices` or Xcode's Devices window. Do not use a simulator destination. The simulator SDK does not include `SiriEvaluations`.

8. Keep the phone unlocked. Each turn can take up to a minute. A failure means Siri did not call the expected tool, called a disallowed one, or did not load the named skill. A passing `Loads` result does not prove Siri followed every sentence in the skill.

The scenarios are the 16 cases in `Tests/AskKitTests/GarageSiriEvalCatalog.swift`: two phrasings for each of the four read tools, two for `ready-to-drive`, two for `cabin-before-departure`, and four out-of-scope requests that must not call those tools.
