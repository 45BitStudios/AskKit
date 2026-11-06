# Siri tools and on-device answers

Keep the on-device model, Private Cloud Compute, ordinary App Intents, and Siri custom tools apart.

## Overview

``AskAnswerLane`` names the four paths.

- ``AskAnswerLane/onDeviceModel`` is `SystemLanguageModel`. It does not need the network. Apple Watch and Apple TV do not use it here.
- ``AskAnswerLane/privateCloudModel`` is `PrivateCloudComputeLanguageModel`. It needs a network. Apple Watch can use it. Apple TV cannot. It is not a Siri tool.
- ``AskAnswerLane/ordinaryAppIntent`` is a Shortcuts or button intent. It does not require the Siri tool loop.
- ``AskAnswerLane/siriCustomTool`` is `ToolIntent`. The group lab says that loop runs with Siri on the server.

``AskSiriBoundary/block(lane:online:platform:signals:)`` is the library check. A live `LanguageModelSession` still uses ``AskOnDeviceResponder`` for model availability, quota, and the instruction window.

## Context, schema, and skills

Custom tools and Siri app skills come into scope through ``AskSiriContextSignal``: the app is named, the app is in the foreground, a Live Activity is up, or an entity from search is already in the conversation. Schemas are eligible without those gates. ``AskToolAdoption`` picks the schema when one matches.

``AskSiriLimits/previewToolCap`` is 40 custom tools. ``AskSiriLimits/skillCallsToAllow(proposed:)`` does not stop at 32. The 30-to-32 remark was about calls inside one skill, and it is not a ceiling.

``AskSiriSkillGuidance`` records that a tool stands alone and that a skill does not roll work back. ``AskSiriSkillGuidance/citesSwiftType(_:typeName:)`` is true when the skill names the Swift type. Use ordinary words instead.

``AskEntityParameter/choose(count:performOnlyNeedsIdentifiers:)`` returns an identifier collection only for more than one entity when `perform` does not need the fields. That is the `EntityCollection` case.

## Privacy

``AskDeviceLock`` maps to `IntentAuthenticationPolicy`. ``AskFieldVisibility/internal`` maps to `visibility: .internal`. ``AskConsumerConsent`` is separate. ``AskDisclosure/modelMayRead(_:deviceUnlocked:)`` applies those three. ``AskDisclosure/performMustValidate`` stays true. ``AskPerformConfirmation`` tells the app to call `requestConfirmation` for an irrevocable or physical action. New fields default to visible and allowed while locked.

## Process and long work

``AskIntentProcess/preference(processAlreadyRunning:)`` uses the running process, otherwise the extension. ``AskIntentProcess/crossesFromIPhoneToMac`` is false. ``AskLongRun/adoptsLongRunningIntent`` is false because no AskKit intent needs a progress UI past the normal intent time.

## Tests

``AskSiriEvaluationRuntime/runsInLibraryUnitTests`` is false. SiriEvaluations needs a signed device. The simulator SDK does not include it. It does not use an LLM judge, and Instruments is the latency tool. The unit tests cover the policy, the discovery phrases, and `AskSnippetButtonIntent.perform()`.

## Topics

- ``AskSiriBoundary``
- ``AskAnswerLane``
- ``AskDisclosure``
- ``AskOnDeviceResponder``
