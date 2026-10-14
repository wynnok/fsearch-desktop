import FsearchService
import XCTest
@testable import FsearchSample

final class PermissionStatusTests: XCTestCase {
    @MainActor
    func testSkipPersistsAndRestrictedReadyCoverageIsSeparateFromContentWorkAndFailure() async throws {
        var dismissed = false
        let state = PermissionStatusModel(onDismiss: { dismissed = true })
        XCTAssertTrue(state.showOnboarding)
        state.skipOnboarding()
        XCTAssertTrue(dismissed)
        XCTAssertFalse(PermissionStatusModel(onboardingDismissed: dismissed).showOnboarding)
        state.apply(ServiceStatus(mode: "engine", ready: true, engineValidated: true,
                                  upstreamVersion: "0.2.1", contentPending: 12, fullDiskAccess: false))
        XCTAssertEqual(state.nameMessage, "名称索引就绪")
        XCTAssertTrue(state.coverageMessage.contains("受限"))
        XCTAssertTrue(state.contentMessage.contains("12"))
        state.recordFailure(FsearchError.bridge("bad /private/个人资料.txt"))
        XCTAssertTrue(state.failureMessage?.contains("重试") == true)
        XCTAssertFalse(state.failureMessage?.contains("个人资料") == true)
        await state.recheck { ServiceStatus(mode: "engine", ready: false, engineValidated: true,
                                           upstreamVersion: "0.2.1", fullDiskAccess: nil) }
        XCTAssertNil(state.failureMessage)
        XCTAssertEqual(state.nameMessage, "名称索引初始化中")
        XCTAssertTrue(state.recheckMessage?.contains("重新检查") == true)
        XCTAssertTrue(state.coverageMessage.contains("未验证"))
    }

    @MainActor
    func testGrantedAccessIsRecognizedSeparatelyFromIndexingAndPermissionChanges() async {
        let state = PermissionStatusModel()
        state.apply(ServiceStatus(mode: "engine", ready: false, engineValidated: true,
                                  upstreamVersion: "0.2.1", contentPending: 12, fullDiskAccess: true,
                                  fullDiskAccessAtStartup: true))
        XCTAssertTrue(state.coverageMessage.contains("已授权"))
        XCTAssertTrue(state.coverageMessage.contains("正在建立"))
        XCTAssertFalse(state.needsRestart)
        await state.recheck {
            ServiceStatus(mode: "engine", ready: true, engineValidated: true,
                          upstreamVersion: "0.2.1", fullDiskAccess: true, fullDiskAccessAtStartup: false)
        }
        XCTAssertTrue(state.needsRestart)
        XCTAssertTrue(state.coverageMessage.contains("授权变化"))
        XCTAssertTrue(state.recheckMessage?.contains("重新打开") == true)
        state.apply(ServiceStatus(mode: "engine", ready: true, engineValidated: true,
                                  upstreamVersion: "0.2.1", fullDiskAccess: false, fullDiskAccessAtStartup: true))
        XCTAssertTrue(state.needsRestart)
    }
}
