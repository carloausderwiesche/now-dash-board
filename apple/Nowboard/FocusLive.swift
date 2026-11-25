// iPhone only: the focused task outside the app. The Lock Screen banner (a
// Live Activity, drawn by the widget extension, ADR 0013) and the Home Screen
// quick actions (long-press the app icon).

#if os(iOS)
    import ActivityKit
    import NowboardKit
    import SwiftUI
    import UIKit

    /// The focused task, as the banner and the quick actions show it.
    struct FocusNow: Equatable, Sendable {
        var id: String
        var info: FocusInfo
    }

    @MainActor
    enum FocusLive {
        /// The focused Today task. None on the demo board, so trying the app
        /// doesn't leave a made-up task on the Lock Screen.
        static func now(in store: BoardStore) -> FocusNow? {
            #if DEBUG
                let demo = ProcessInfo.processInfo.arguments.contains("-livedemo")  // try it in the simulator
            #else
                let demo = false
            #endif
            guard !store.isDemo || demo, let t = store.tasks.first(where: { $0.status == .today && $0.focus }) else { return nil }
            let c = category(for: t.area, in: store.settings.categories)
            let dark = Theme.all.first(where: \.dark) ?? Theme.all[0]
            return FocusNow(id: t.id, info: FocusInfo(
                // Anyone can read the Lock Screen.
                title: t.isPrivate ? "Private task" : t.title,
                category: c.name,
                color: c.color.strong(in: dark).resolve(in: EnvironmentValues()),
                done: t.items.filter(\.done).count, total: t.items.count))
        }

        /// Starts, updates or ends the banner and refreshes the quick actions.
        static func sync(_ focus: FocusNow?) async {
            updateQuickActions(focus)
            await syncActivity(focus)
        }

        /// Off the main actor: ActivityKit's activities can't be sent across it.
        private nonisolated static func syncActivity(_ focus: FocusNow?) async {
            let running = Activity<FocusAttributes>.activities
            for activity in running where activity.attributes.id != focus?.id {
                await activity.end(nil, dismissalPolicy: .immediate)
            }
            guard let focus else { return }
            let content = ActivityContent(state: FocusAttributes.ContentState(focus: focus.info), staleDate: nil)
            if let activity = running.first(where: { $0.attributes.id == focus.id }) {
                await activity.update(content)
            } else if ActivityAuthorizationInfo().areActivitiesEnabled {
                do {
                    _ = try Activity.request(attributes: FocusAttributes(id: focus.id, since: .now), content: content)
                } catch {
                    print("Live Activity:", error)
                }
            }
        }

        // MARK: Quick actions

        /// Set at launch: the actions need the store.
        static weak var store: BoardStore?

        private static func updateQuickActions(_ focus: FocusNow?) {
            var items = [UIApplicationShortcutItem(type: "new", localizedTitle: "New task", localizedSubtitle: nil,
                                                   icon: UIApplicationShortcutIcon(systemImageName: "plus"))]
            if let focus {
                let info = ["id": focus.id as NSString]
                items.append(UIApplicationShortcutItem(type: "open", localizedTitle: focus.info.title, localizedSubtitle: "Now",
                                                       icon: UIApplicationShortcutIcon(systemImageName: "scope"), userInfo: info))
                items.append(UIApplicationShortcutItem(type: "done", localizedTitle: "Mark done", localizedSubtitle: focus.info.title,
                                                       icon: UIApplicationShortcutIcon(systemImageName: "checkmark.circle"), userInfo: info))
            }
            UIApplication.shared.shortcutItems = items
        }

        static func perform(_ item: UIApplicationShortcutItem) {
            guard let store else { return }
            let id = item.userInfo?["id"] as? String
            Task {
                // Launched by the action: the board isn't read yet.
                if let id, store.task(id) == nil { await store.reload() }
                switch item.type {
                case "new": store.adding = true
                case "open": if let id, store.task(id) != nil { store.openID = id }
                case "done": if let id, store.task(id)?.status == .today { store.finish(id) }
                default: break
                }
            }
        }
    }

    /// Hands quick actions to FocusLive: at launch (the scene's connection
    /// options) and while running (the scene delegate).
    final class AppDelegate: NSObject, UIApplicationDelegate {
        func application(_ application: UIApplication, configurationForConnecting session: UISceneSession,
                         options: UIScene.ConnectionOptions) -> UISceneConfiguration {
            if let item = options.shortcutItem { FocusLive.perform(item) }
            let config = UISceneConfiguration(name: nil, sessionRole: session.role)
            config.delegateClass = SceneDelegate.self
            return config
        }
    }

    final class SceneDelegate: NSObject, UIWindowSceneDelegate {
        func windowScene(_ windowScene: UIWindowScene, performActionFor item: UIApplicationShortcutItem) async -> Bool {
            FocusLive.perform(item)
            return true
        }
    }
#endif
