#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
import XCTest
@testable import NetInspectCore
@testable import NetInspectUI

@MainActor
final class NetInspectUITests: XCTestCase {
    func testShakeObserverInvokesCallbackForShakeMotion() {
        var callbackCount = 0
        let observer = NetInspectShakeObserver { callbackCount += 1 }

        observer.motionEnded(.motionShake, with: nil)

        XCTAssertEqual(callbackCount, 1)
    }

    func testShakeObserverIgnoresOtherMotionTypes() {
        var callbackCount = 0
        let observer = NetInspectShakeObserver { callbackCount += 1 }

        observer.motionEnded(.remoteControlPlay, with: nil)
        observer.motionEnded(.remoteControlPause, with: nil)

        XCTAssertEqual(callbackCount, 0)
    }

    func testShakeObserverCanBecomeFirstResponder() {
        let observer = NetInspectShakeObserver {}

        XCTAssertTrue(observer.canBecomeFirstResponder)
    }

    func testMonitorViewControllerUsesConfiguredPresentationStyle() {
        let configuration = NetInspectUIConfiguration(
            title: "Debug Monitor",
            presentationStyle: .formSheet
        )

        let controller = NetInspectUI.makeViewController(configuration: configuration)

        XCTAssertEqual(controller.modalPresentationStyle, .formSheet)
        XCTAssertTrue(controller is UIHostingController<NetInspectMonitorView>)
    }

    func testShakeInstallerCreatesInstallerViewController() {
        let configuration = NetInspectUIConfiguration(title: "Demo")
        let controller = NetInspectShakeInstaller.InstallerViewController(configuration: configuration)

        XCTAssertEqual(type(of: controller), NetInspectShakeInstaller.InstallerViewController.self)
        XCTAssertNil(controller.viewIfLoaded?.superview)
    }
}
#endif
