import AppKit

/// Narrow interface for the translation panel. Apple's `TranslationSession` is only vended through a SwiftUI view
/// modifier (macOS 15+), so the session lives behind this small bridge. Everything runs on-device.
@MainActor
protocol TranslationSessionProviding: AnyObject {
    var hostView: NSView { get }
    func translate(text: String, targetIdentifier: String) async throws -> String
    func cancel()
}

@MainActor
enum TranslationBridge {
    static func makeProvider() -> TranslationSessionProviding? {
#if canImport(Translation) && canImport(SwiftUI)
        guard #available(macOS 15.0, *) else { return nil }
        return SessionProvider()
#else
        return nil
#endif
    }

    /// The user's first preferred language, e.g. "zh-Hans" or "en".
    static var targetIdentifier: String {
        Locale.preferredLanguages.first ?? "en"
    }
}

#if canImport(Translation) && canImport(SwiftUI)
import SwiftUI
import Translation

@available(macOS 15.0, *)
@MainActor
private final class SessionProvider: TranslationSessionProviding {
    private let model = BridgeModel()

    lazy var hostView: NSView = NSHostingView(rootView: BridgeView(model: model))

    func translate(text: String, targetIdentifier: String) async throws -> String {
        try await model.translate(text: text, targetIdentifier: targetIdentifier)
    }

    func cancel() { model.cancel() }
}

@available(macOS 15.0, *)
@MainActor
private final class BridgeModel: ObservableObject {
    @Published var configuration: TranslationSession.Configuration?

    private struct Pending {
        let id: UUID
        let text: String
        let continuation: CheckedContinuation<String, Error>
    }

    private var pending: Pending?

    func translate(text: String, targetIdentifier: String) async throws -> String {
        let requestID = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                pending?.continuation.resume(throwing: CancellationError())
                pending = Pending(id: requestID, text: text, continuation: continuation)
                configuration = TranslationSession.Configuration(
                    source: nil,
                    target: Locale.Language(identifier: targetIdentifier)
                )
            }
        } onCancel: {
            Task { @MainActor [weak self] in
                guard self?.pending?.id == requestID else { return }
                self?.cancel()
            }
        }
    }

    func perform(using session: TranslationSession) async {
        guard let request = pending else { return }
        do {
            let response = try await session.translate(request.text)
            finish(request.id, .success(response.targetText))
        } catch {
            finish(request.id, .failure(error))
        }
    }

    func cancel() {
        configuration = nil
        guard let request = pending else { return }
        pending = nil
        request.continuation.resume(throwing: CancellationError())
    }

    private func finish(_ id: UUID, _ result: Result<String, Error>) {
        guard let request = pending, request.id == id else { return }
        pending = nil
        configuration = nil
        request.continuation.resume(with: result)
    }
}

@available(macOS 15.0, *)
private struct BridgeView: View {
    @ObservedObject var model: BridgeModel

    var body: some View {
        Color.clear
            .allowsHitTesting(false)
            .translationTask(model.configuration) { session in
                await model.perform(using: session)
            }
    }
}
#endif
