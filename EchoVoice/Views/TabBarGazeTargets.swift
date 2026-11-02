import SwiftUI
import UIKit

/// The native tab bar can be centered on iPad and changes shape across OS
/// versions. Register its actual controls instead of dividing the window into
/// phone-sized targets. If UIKit cannot expose a matching set, select nothing.
struct TabBarGazeTargets: UIViewRepresentable {
    @Environment(EyeGazeManager.self) private var eyeGaze
    let tabs: [Int]
    @Binding var selection: Int

    func makeUIView(context: Context) -> TabBarTargetReader {
        let view = TabBarTargetReader()
        view.isUserInteractionEnabled = false
        view.isAccessibilityElement = false
        view.readTargets = { [weak coordinator = context.coordinator] window in
            coordinator?.refresh(in: window)
        }
        return view
    }

    func updateUIView(_ view: TabBarTargetReader, context: Context) {
        context.coordinator.tabs = tabs
        context.coordinator.select = { selection = $0 }
    }

    func makeCoordinator() -> Coordinator { Coordinator(eyeGaze: eyeGaze) }

    static func dismantleUIView(_ view: TabBarTargetReader, coordinator: Coordinator) {
        view.stop()
        coordinator.clear()
    }

    @MainActor
    final class Coordinator {
        let eyeGaze: EyeGazeManager
        let token = UUID()
        var tabs: [Int] = []
        var select: (Int) -> Void = { _ in }
        private var registered: [Int: CGRect] = [:]

        init(eyeGaze: EyeGazeManager) { self.eyeGaze = eyeGaze }

        func clear() {
            for tab in registered.keys { eyeGaze.unregisterTarget(id: "tab-\(tab)", token: token) }
            if !registered.isEmpty { eyeGaze.resetDwell() }
            registered = [:]
        }

        func refresh(in window: UIWindow?) {
            guard let window, eyeGaze.isHandsFreeActive,
                  let controller = tabController(in: window.rootViewController),
                  controller.presentedViewController == nil,
                  window.rootViewController?.presentedViewController == nil,
                  !controller.tabBar.isHidden, controller.tabBar.alpha > 0 else {
                clear()
                return
            }
            let bar = controller.tabBar
            let buttons = controls(in: bar).sorted {
                $0.convert($0.bounds, to: window).midX < $1.convert($1.bounds, to: window).midX
            }
            guard buttons.count == tabs.count else { clear(); return }
            // Tab items follow the interface's reading direction.
            let ordered = bar.effectiveUserInterfaceLayoutDirection == .rightToLeft ? Array(buttons.reversed()) : buttons
            guard ordered.allSatisfy({ button in
                let center = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: window)
                var hit = window.hitTest(center, with: nil)
                while let view = hit {
                    if view === button { return true }
                    hit = view.superview
                }
                return false
            }) else { clear(); return }
            let frames = Dictionary(uniqueKeysWithValues: zip(tabs, ordered).map { tab, button in
                (tab, button.convert(button.bounds, to: window))
            })
            guard frames != registered else { return }
            clear()
            registered = frames
            for (tab, frame) in frames {
                eyeGaze.registerTarget(id: "tab-\(tab)", token: token, frame: frame, kind: .standard) { [weak self] in
                    self?.select(tab)
                }
            }
        }

        private func tabController(in controller: UIViewController?) -> UITabBarController? {
            guard let controller else { return nil }
            if let tabs = controller as? UITabBarController { return tabs }
            return controller.children.lazy.compactMap { self.tabController(in: $0) }.first
        }

        private func controls(in view: UIView) -> [UIControl] {
            guard !view.isHidden, view.alpha > 0 else { return [] }
            if let control = view as? UIControl, control.bounds.width >= 44, control.bounds.height >= 44 {
                return control.isEnabled ? [control] : []
            }
            return view.subviews.flatMap { controls(in: $0) }
        }
    }
}

final class TabBarTargetReader: UIView {
    var readTargets: ((UIWindow?) -> Void)?
    private var timer: Timer?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        stop()
        guard window != nil else { readTargets?(nil); return }
        // Also notices modal presentation, whose dimmed tab bar still exists
        // in UIKit's hierarchy and must stop accepting dwell selections.
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.readTargets?(self.window)
            }
        }
    }

    func stop() { timer?.invalidate(); timer = nil }
}
