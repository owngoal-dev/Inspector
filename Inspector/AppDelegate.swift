//
//  AppDelegate.swift
//  Inspector
//
//  Created by qaq on 3/8/2026.
//

import Combine
import UIKit

final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UpdateNotice.shared.startWatching()
        return true
    }

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(
            name: nil,
            sessionRole: connectingSceneSession.role
        )
        configuration.delegateClass = SceneDelegate.self
        return configuration
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    private let model = ProcessListModel()
    private var contentObservation: AnyCancellable?
    private var revealDeadline: Task<Void, Never>?
    private var hasRevealed = false

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        // The asset catalog's global accent only reaches UIKit from iOS 14.
        window.tintColor = UIColor(named: "AccentColor")
        // The launch screen's own surface holds the window until there is a
        // list to show: the app's first frame is then the finished list, not
        // an empty one that fills itself in a moment later.
        window.rootViewController = LaunchPlaceholderViewController()
        window.makeKeyAndVisible()
        self.window = window
    }

    // Sampling follows the scene, not the launch: a locked-screen launch
    // (uiopen, prewarming) connects a scene that never becomes active, and an
    // unconditional start would keep an unnecessary client connection and
    // sampling loop alive behind the lock screen.
    func sceneDidBecomeActive(_ scene: UIScene) {
        model.start()
        waitForContent()
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        model.stop()
    }

    // The list is worth showing once it has rows, or once the connection has
    // failed and the screen can say why; the deadline keeps a service that
    // never answers from leaving the app on the launch surface for good.
    private func waitForContent() {
        guard !hasRevealed else { return }
        contentObservation = model.changes.sink { [weak self] in self?.revealIfReady() }
        revealDeadline = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            self?.reveal()
        }
    }

    private func revealIfReady() {
        guard !model.rows.isEmpty else {
            if case .failed = model.phase { reveal() }
            return
        }
        reveal()
    }

    private func reveal() {
        guard !hasRevealed, let window else { return }
        hasRevealed = true
        contentObservation = nil
        revealDeadline?.cancel()
        revealDeadline = nil
        let list = InspectorSplitViewController(model: model)
        let finish = { UpdateNotice.shared.presentIfPending(in: window) }
        // The mark the launch screen left behind dissolves into the list
        // instead of the two swapping between frames; someone who has asked
        // for less motion gets the swap without it.
        if UIAccessibility.isReduceMotionEnabled {
            window.rootViewController = list
            finish()
        } else {
            UIView.transition(with: window, duration: 0.3, options: .transitionCrossDissolve) {
                window.rootViewController = list
            } completion: { _ in
                finish()
            }
        }
    }
}

// The launch screen's surface, mark and all, held over the window until the
// process list has rows: the app opens on the frame the system was already
// showing, so the hand-off from the launch screen is invisible.
private final class LaunchPlaceholderViewController: UIViewController {
    // The size the launch storyboard draws the mark at.
    private static let markSize: CGFloat = 96

    override func loadView() {
        let view = UIView()
        view.backgroundColor = .systemBackground
        let mark = UIImageView(image: UIImage(named: "LaunchIcon"))
        mark.contentMode = .scaleAspectFit
        mark.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(mark)
        NSLayoutConstraint.activate([
            mark.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            mark.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            mark.widthAnchor.constraint(equalToConstant: Self.markSize),
            mark.heightAnchor.constraint(equalToConstant: Self.markSize),
        ])
        self.view = view
    }
}

/// An update or a removal took the running copy's executable
/// (`ExecutableWatch`); the watch cannot tell which. After an update this is
/// old code against a daemon the package's postinst has already restarted.
@MainActor
final class UpdateNotice {
    static let shared = UpdateNotice()

    private var isPending = false

    func startWatching() {
        ExecutableWatch.start { [weak self] in
            guard let self else { return }
            self.isPending = true
            let window = UIApplication.shared.connectedScenes
                .filter { $0.activationState == .foregroundActive }
                .compactMap { ($0.delegate as? SceneDelegate)?.window }
                .first
            self.presentIfPending(in: window)
        }
    }

    // A suspended app hears about the update as it resumes, possibly before
    // any scene is active again; the notice then waits for the next one.
    func presentIfPending(in window: UIWindow?) {
        guard isPending, var presenter = window?.rootViewController else { return }
        while let presented = presenter.presentedViewController {
            presenter = presented
        }
        isPending = false
        let alert = UIAlertController(
            title: String(localized: "Inspector Was Updated or Removed"),
            message: String(
                localized: "This copy is no longer installed. Quit it and open Inspector again to continue."
            ),
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: String(localized: "Later"), style: .cancel))
        alert.addAction(UIAlertAction(title: String(localized: "Quit Inspector"), style: .default) { _ in
            QuietExit.run()
        })
        presenter.present(alert, animated: true)
    }
}
