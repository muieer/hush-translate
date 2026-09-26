import Foundation
import SwiftUI
import Translation
import NaturalLanguage

/// Bridges the existing async translation pipeline to macOS 15's view-bound session.
@MainActor
final class AppleTranslationService: ObservableObject {
    enum Route: Equatable {
        case lowLatency

        static func choose(lowLatency: LanguageAvailability.Status) throws -> (route: Route, needsDownload: Bool) {
            if lowLatency == .installed { return (.lowLatency, false) }
            if lowLatency == .supported { return (.lowLatency, true) }
            throw AppleTranslationFailure.unsupported
        }
    }

    struct Job: Identifiable {
        let id: UUID
        let request: TranslationRequest
        let route: Route

        var configuration: TranslationSession.Configuration {
            let source = request.sourceLang == "auto" ? nil : Locale.Language(identifier: request.sourceLang)
            let target = Locale.Language(identifier: request.targetLang)
            if #available(macOS 26.4, *) {
                return TranslationSession.Configuration(source: source, target: target,
                    preferredStrategy: .lowLatency)
            }
            return TranslationSession.Configuration(source: source, target: target)
        }
    }

    @Published private(set) var job: Job?
    private let routeSelection: ((TranslationRequest) async throws -> (route: Route, needsDownload: Bool))?
    private var continuation: CheckedContinuation<String, Error>?
    private var runningID: UUID?

    init(routeSelection: ((TranslationRequest) async throws -> (route: Route, needsDownload: Bool))? = nil) {
        self.routeSelection = routeSelection
    }

    func translate(_ request: TranslationRequest, onDownloadRequired: @MainActor () -> Void = {}) async throws -> String {
        try Task.checkCancellation()
        let request = Self.resolvingSource(in: request)
        if request.sourceLang == request.targetLang { return request.text }
        let selection: (route: Route, needsDownload: Bool)
        if let routeSelection {
            selection = try await routeSelection(request)
        } else {
            selection = try await selectRoute(for: request)
        }
        try Task.checkCancellation()
        if selection.needsDownload { onDownloadRequired() }
        let id = UUID()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { pending in
                cancel()
                continuation = pending
                job = Job(id: id, request: request, route: selection.route)
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel(id: id) }
        }
    }

    /// Resolve once so availability checks and the session use the same source language.
    /// Leave ambiguous text to the view-bound session, which can ask the user to choose.
    static func resolvingSource(in request: TranslationRequest) -> TranslationRequest {
        guard request.sourceLang == "auto" else { return request }
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(request.text)
        guard let language = recognizer.dominantLanguage,
              language != .undetermined else { return request }
        var resolved = request
        resolved.sourceLang = language.rawValue
        return resolved
    }

    private func selectRoute(for request: TranslationRequest) async throws -> (route: Route, needsDownload: Bool) {
        let target = Locale.Language(identifier: request.targetLang)
        let source = request.sourceLang == "auto" ? nil : Locale.Language(identifier: request.sourceLang)
        let availability: LanguageAvailability
        if #available(macOS 26.4, *) {
            availability = LanguageAvailability(preferredStrategy: .lowLatency)
        } else {
            availability = LanguageAvailability()
        }
        return try await Self.preflight {
            if let source { return await availability.status(from: source, to: target) }
            return try await availability.status(for: request.text, to: target)
        }
    }

    static func preflight(_ status: () async throws -> LanguageAvailability.Status) async throws -> (route: Route, needsDownload: Bool) {
        do {
            return try Route.choose(lowLatency: await status())
        } catch TranslationError.unableToIdentifyLanguage {
            // Availability is only a preflight. The session can identify the text or
            // present a language picker; activate its window in case interaction is needed.
            return (.lowLatency, true)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as AppleTranslationFailure {
            throw error
        } catch {
            throw Self.classify(error)
        }
    }

    fileprivate static func classify(_ error: Error) -> AppleTranslationFailure {
        switch error {
        case TranslationError.unsupportedSourceLanguage,
             TranslationError.unsupportedTargetLanguage,
             TranslationError.unsupportedLanguagePairing:
            return .unsupported
        case TranslationError.unableToIdentifyLanguage:
            return .unidentified
        default:
            return .failed(error.localizedDescription)
        }
    }

    /// The host can be refreshed repeatedly, but each job is executed only once.
    func execute(id: UUID, operation: (TranslationRequest) async throws -> String) async {
        guard let job, job.id == id, runningID != id else { return }
        runningID = id
        do {
            let text = try await operation(job.request)
            try Task.checkCancellation()
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw AppleTranslationFailure.emptyResult
            }
            finish(id: id, result: .success(text))
        } catch {
            finish(id: id, result: .failure(error))
        }
    }

    func cancel(id: UUID? = nil) {
        guard let job, id == nil || id == job.id else { return }
        finish(id: job.id, result: .failure(CancellationError()))
    }

    private func finish(id: UUID, result: Result<String, Error>) {
        guard job?.id == id else { return }
        let pending = continuation
        continuation = nil
        runningID = nil
        job = nil
        pending?.resume(with: result)
    }
}

enum AppleTranslationFailure: LocalizedError {
    case unsupported, unidentified, emptyResult, failed(String)

    var errorDescription: String? {
        switch self {
        case .unsupported:
            return L10n.tr("Apple 翻译不支持当前语言组合。请更换源语言或目标语言，或在设置中选择其他翻译来源。")
        case .unidentified:
            return L10n.tr("Apple 翻译无法识别源语言。请在结果窗口中手动选择源语言后重试。")
        case .emptyResult:
            return L10n.tr("Apple 翻译未返回译文，请重新选择文字后重试。")
        case .failed(let detail):
            return L10n.format("Apple 翻译未完成：%@", detail)
        }
    }
}

struct AppleTranslationHost: View {
    @ObservedObject var service: AppleTranslationService

    var body: some View {
        Group {
            if let job = service.job {
                AppleTranslationTaskView(service: service, job: job)
                    // A fresh view-bound session also handles consecutive requests with identical languages.
                    .id(job.id)
            }
        }
        .frame(width: 0, height: 0)
    }
}

private struct AppleTranslationTaskView: View {
    let service: AppleTranslationService
    let job: AppleTranslationService.Job

    var body: some View {
        Color.clear
            .translationTask(job.configuration) { session in
                await service.execute(id: job.id) { request in
                    do {
                        // The service already selected an installed model when one is available.
                        // Otherwise this view-bound session can request the system's download consent.
                        return try await session.translate(request.text).targetText
                    } catch is CancellationError {
                        throw CancellationError()
                    } catch let error as AppleTranslationFailure {
                        throw error
                    } catch {
                        throw AppleTranslationService.classify(error)
                    }
                }
            }
            .onDisappear { service.cancel(id: job.id) }
    }
}
