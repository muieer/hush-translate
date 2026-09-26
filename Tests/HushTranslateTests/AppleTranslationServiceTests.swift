import XCTest
import Translation
@testable import HushTranslate

@MainActor
final class AppleTranslationServiceTests: XCTestCase {
    private let input = TranslationRequest(text: "Hello", sourceLang: "auto", targetLang: "zh-Hans")

    private func waitForJob(_ service: AppleTranslationService, differentFrom old: UUID? = nil) async throws -> UUID {
        for _ in 0..<200 {
            if let id = service.job?.id, id != old { return id }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        throw TestError.timeout
    }
    private enum TestError: Error { case timeout, unavailable }

    private func service() -> AppleTranslationService {
        AppleTranslationService(routeSelection: { _ in (.lowLatency, false) })
    }

    func testLowLatencyAvailabilityAndDownload() throws {
        let installed = try AppleTranslationService.Route.choose(lowLatency: .installed)
        XCTAssertEqual(installed.route, .lowLatency)
        XCTAssertFalse(installed.needsDownload)
        let supported = try AppleTranslationService.Route.choose(lowLatency: .supported)
        XCTAssertEqual(supported.route, .lowLatency)
        XCTAssertTrue(supported.needsDownload)
        XCTAssertThrowsError(try AppleTranslationService.Route.choose(lowLatency: .unsupported))
        if #available(macOS 26.4, *) {
            let job = AppleTranslationService.Job(id: UUID(), request: input, route: .lowLatency)
            XCTAssertEqual(job.configuration.preferredStrategy, .lowLatency)
        }
    }

    func testAutomaticSourceIsResolvedAndExplicitSourceIsPreserved() {
        let english = TranslationRequest(text: "This is a sentence written in English.", sourceLang: "auto", targetLang: "zh-Hans")
        XCTAssertEqual(AppleTranslationService.resolvingSource(in: english).sourceLang, "en")
        var explicit = english
        explicit.sourceLang = "fr"
        XCTAssertEqual(AppleTranslationService.resolvingSource(in: explicit).sourceLang, "fr")
        var ambiguous = english
        ambiguous.text = "12345"
        XCTAssertEqual(AppleTranslationService.resolvingSource(in: ambiguous).sourceLang, "auto")
    }

    func testUnidentifiedPreflightAllowsSessionToHandleLanguageSelection() async throws {
        let selection = try await AppleTranslationService.preflight {
            throw TranslationError.unableToIdentifyLanguage
        }
        XCTAssertEqual(selection.route, .lowLatency)
        XCTAssertTrue(selection.needsDownload)
    }

    func testResolvedLanguageReachesSessionAndSameLanguageReturnsOriginal() async throws {
        let service = service()
        let request = TranslationRequest(text: "This is a sentence written in English.", sourceLang: "auto", targetLang: "zh-Hans")
        let caller = Task { try await service.translate(request) }
        let id = try await waitForJob(service)
        XCTAssertEqual(service.job?.request.sourceLang, "en")
        await service.execute(id: id) { _ in "这是一句英语。" }
        _ = try await caller.value
        var same = request
        same.targetLang = "en"
        let original = try await service.translate(same)
        XCTAssertEqual(original, same.text)
        XCTAssertNil(service.job)
    }

    func testDownloadConsentActivatesWindowBeforeStartingSession() async throws {
        let service = AppleTranslationService(routeSelection: { _ in (.lowLatency, true) })
        var activated = false
        let caller = Task {
            try await service.translate(input) {
                XCTAssertNil(service.job)
                activated = true
            }
        }
        let id = try await waitForJob(service)
        XCTAssertTrue(activated)
        await service.execute(id: id) { _ in "你好" }
        let result = try await caller.value
        XCTAssertEqual(result, "你好")
    }

    func testConsecutiveSameLanguageRequestsAndNoDuplicateExecution() async throws {
        let service = service()
        for _ in 0..<2 {
            let task = Task { try await service.translate(input) }
            let id = try await waitForJob(service)
            await service.execute(id: id) { _ in "你好" }
            await service.execute(id: id) { _ in XCTFail("Duplicate execution"); return "duplicate" }
            let result = try await task.value
            XCTAssertEqual(result, "你好")
            XCTAssertNil(service.job)
        }
    }

    func testSupersededAndLateResultsCannotCompleteNewJob() async throws {
        let service = service()
        let old = Task { try await service.translate(input) }
        let oldID = try await waitForJob(service)
        var pending: CheckedContinuation<String, Never>?
        let execution = Task {
            await service.execute(id: oldID) { _ in
                await withCheckedContinuation { pending = $0 }
            }
        }
        while pending == nil { await Task.yield() }
        let next = Task { try await service.translate(input) }
        let newID = try await waitForJob(service, differentFrom: oldID)
        pending?.resume(returning: "stale")
        await execution.value
        XCTAssertEqual(service.job?.id, newID)
        service.cancel(id: oldID)
        XCTAssertEqual(service.job?.id, newID)
        await service.execute(id: newID) { _ in "latest" }
        let result = try await next.value
        XCTAssertEqual(result, "latest")
        do { _ = try await old.value; XCTFail("Old job must cancel") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }

    func testCallerCancellationAndHostDisappearanceResumeWaiters() async throws {
        let service = service()
        let caller = Task { try await service.translate(input) }
        _ = try await waitForJob(service)
        caller.cancel()
        do { _ = try await caller.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
        XCTAssertNil(service.job)
        let next = Task { try await service.translate(input) }
        let id = try await waitForJob(service)
        service.cancel(id: id)
        service.cancel(id: id)
        do { _ = try await next.value; XCTFail("Expected cancellation") } catch is CancellationError {} catch { XCTFail("\(error)") }
    }

    func testErrorsAndEmptyResultsEndJob() async throws {
        let service = service()
        let task = Task { try await service.translate(input) }
        let id = try await waitForJob(service)
        await service.execute(id: id) { _ in throw TestError.unavailable }
        do { _ = try await task.value; XCTFail("Expected failure") } catch TestError.unavailable {} catch { XCTFail("\(error)") }
        XCTAssertNil(service.job)
        let empty = Task { try await service.translate(input) }
        let emptyID = try await waitForJob(service)
        await service.execute(id: emptyID) { _ in " " }
        do { _ = try await empty.value; XCTFail("Expected empty result failure") } catch AppleTranslationFailure.emptyResult {} catch { XCTFail("\(error)") }
        XCTAssertNil(service.job)
    }
}
