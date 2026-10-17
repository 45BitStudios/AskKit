import AskKit
import AskKitIntents
import AskKitUI
import SwiftUI
#if os(iOS)
import UIKit
#endif

struct SampleHost: View {
    let client: AskIntentClient
    @State private var project: SampleProject
    @State private var assistant: AskAssistant
    @State private var showsSamples = false

    init(client: AskIntentClient) {
        self.client = client
        let project = SampleProject.selected
        _project = State(initialValue: project)
        _assistant = State(initialValue: client.assistant)
    }

    var body: some View {
        NavigationStack {
            AskChatView(
                assistant: assistant,
                appearance: project.appearance,
                embedsNavigation: false,
                feedback: AskAnswerFeedback(),
                menu: {
                    Button("Sample projects", systemImage: "wrench.and.screwdriver") {
                        SampleCue.tap()
                        showsSamples = true
                    }
                }
            )
            .id(project.id)
        }
        .sheet(isPresented: $showsSamples) {
            SampleProjectsSheet(selection: project) { chosen in
                let next = chosen.makeAssistant()
                SampleProject.selected = chosen
                assistant = next
                client.assistant = next
                project = chosen
            }
        }
        .task(id: project.id) {
            guard project == .open else { return }
            // Reload the saved Vision index, then index only photos newer than lastIndexDate.
            await AskPhotos.prepareIndexOnLaunch()
        }
    }
}

private struct SampleProjectsSheet: View {
    let selection: SampleProject
    let onSelect: (SampleProject) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(SampleProject.allCases) { project in
                Button {
                    SampleCue.selection()
                    onSelect(project)
                    dismiss()
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: project.symbol)
                            .font(.title3)
                            .foregroundStyle(project.appearance.tint)
                            .frame(width: 32)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(project.title)
                                .font(.body)
                                .foregroundStyle(.primary)
                            Text(project.detail)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.leading)
                        }
                        Spacer(minLength: 8)
                        if project == selection {
                            Image(systemName: "checkmark")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(project.appearance.tint)
                                .accessibilityHidden(true)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(project.title)
                .accessibilityHint(project.detail)
                .accessibilityAddTraits(project == selection ? .isSelected : [])
            }
            .navigationTitle("Samples")
            .sampleInlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        SampleCue.tap()
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

extension View {
    /// Inline title on platforms that have one. The Mac and Apple TV keep their own title.
    @ViewBuilder
    fileprivate func sampleInlineTitle() -> some View {
#if os(iOS) || os(visionOS) || os(watchOS)
        navigationBarTitleDisplayMode(.inline)
#else
        self
#endif
    }
}

/// iPhone plays a tap. The Mac, Apple TV, and visionOS stay quiet, matching `AskCue`.
private enum SampleCue {
    static func tap() {
#if os(iOS)
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
#endif
    }

    static func selection() {
#if os(iOS)
        UISelectionFeedbackGenerator().selectionChanged()
#endif
    }
}
