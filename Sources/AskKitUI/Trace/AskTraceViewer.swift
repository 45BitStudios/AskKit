import AskKit
import AskKitIntents
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Toolbar button that opens the debug trace viewer. Renders nothing in Release.
public struct AskTraceButton: View {
    @State private var isPresented = false
    #if DEBUG
    private var snippetCards: (@MainActor (AskTraceTurn) async -> [AnyView])?
    #endif

    public init() {
        #if DEBUG
        snippetCards = nil
        #endif
    }

    #if DEBUG
    init(snippetCards: (@MainActor (AskTraceTurn) async -> [AnyView])?) {
        self.snippetCards = snippetCards
    }
    #endif

    public var body: some View {
        #if DEBUG
        Button {
            AskCue.tap()
            isPresented = true
        } label: {
            Image(systemName: "point.3.connected.trianglepath.dotted")
        }
        .accessibilityLabel("Ask trace")
        .sheet(isPresented: $isPresented) {
            AskTraceScreen(showsClose: true, snippetCards: snippetCards)
        }
        #else
        EmptyView()
        #endif
    }
}

#if DEBUG
#if os(iOS) || os(visionOS)
@MainActor
public enum AskTraceViewer {
    /// Presents the trace list over whatever is on top of `window`.
    public static func present(in window: UIWindow) {
        guard var top = window.rootViewController else { return }
        while let presented = top.presentedViewController {
            if presented is AskTraceHostingController { return }
            top = presented
        }
        let host = AskTraceHostingController(rootView: AskTraceScreen(showsClose: true))
        host.modalPresentationStyle = .pageSheet
#if os(iOS)
        host.sheetPresentationController?.detents = [.large()]
        host.sheetPresentationController?.prefersGrabberVisible = true
#endif
        top.present(host, animated: true)
    }
}

private final class AskTraceHostingController: UIHostingController<AskTraceScreen> {}
#endif

public struct AskTraceScreen: View {
    @StateObject private var viewModel: AskTraceViewModel
    private let showsClose: Bool
    private let turnID: UUID?

    public init(
        showsClose: Bool = true,
        turnID: UUID? = nil,
        snippetCards: (@MainActor (AskTraceTurn) async -> [AnyView])? = nil
    ) {
        self.showsClose = showsClose
        self.turnID = turnID
        AskCardRenderer.install()
        _viewModel = StateObject(wrappedValue: AskTraceViewModel(store: .live(), snippetCards: snippetCards))
    }

    public var body: some View {
        if showsClose {
            NavigationStack {
                AskTraceRootView(viewModel: viewModel, showsClose: true, turnID: turnID)
            }
        } else {
            AskTraceRootView(viewModel: viewModel, showsClose: false, turnID: turnID)
        }
    }
}
#endif
