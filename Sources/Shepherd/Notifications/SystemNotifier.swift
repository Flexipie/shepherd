import Foundation
import os
import ShepherdCore
import UserNotifications

/// System notifications through `UNUserNotificationCenter`. Asks for permission the first time
/// it has something to post, and checks it again before every post, so turning notifications on
/// in System Settings later works without a restart. While they are off there, the bar's footer
/// says so. A notification is identified by its agent, so a new one for the
/// same agent replaces the old. Clicking it or Jump shows the agent; Reply sends the typed text
/// (a reply while the agent is blocked, a prompt otherwise), the same as the notch stage does.
@MainActor
final class SystemNotifier: NSObject, Notifier, UNUserNotificationCenterDelegate {
    private let center: UNUserNotificationCenter
    private let store: HerdStore
    private let actions: any AgentActions
    private let config: ConfigStore
    private static let log = Logger(subsystem: "dev.flexipie.shepherd", category: "notifications")

    static let category = "agent.blocked"
    static let replyCategory = "agent.blocked.reply"
    static let jumpAction = "jump"
    static let replyAction = "reply"

    /// nil outside an app bundle (such as `swift run`), where the notification center is not
    /// available.
    init?(store: HerdStore, actions: any AgentActions, config: ConfigStore) {
        guard Bundle.main.bundleIdentifier != nil, Bundle.main.bundleURL.pathExtension == "app" else { return nil }
        center = .current()
        self.store = store
        self.actions = actions
        self.config = config
        super.init()
        center.delegate = self
        let jump = UNNotificationAction(identifier: Self.jumpAction, title: "Jump")
        let reply = UNTextInputNotificationAction(identifier: Self.replyAction, title: "Reply", textInputButtonTitle: "Send",
                                                  textInputPlaceholder: "Reply")
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.category, actions: [jump], intentIdentifiers: []),
            UNNotificationCategory(identifier: Self.replyCategory, actions: [reply, jump], intentIdentifiers: []),
        ])
    }

    func post(_ notice: AgentNotice) {
        Task {
            guard await authorize() else { return }
            let content = UNMutableNotificationContent()
            content.title = notice.agent.name
            let place = notice.agent.project.isEmpty ? "" : " in \(notice.agent.project)"
            content.body = notice.reason == .blocked ? "Needs you\(place)" : "Finished\(place)"
            content.categoryIdentifier = notice.canReply ? Self.replyCategory : Self.category
            content.threadIdentifier = notice.agent.id.description
            content.userInfo = ["source": notice.agent.id.source.rawValue, "local": notice.agent.id.local]
            let request = UNNotificationRequest(identifier: notice.agent.id.description, content: content, trigger: nil)
            do {
                try await center.add(request)
            } catch {
                Self.log.error("posting failed: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    func withdraw(_ agent: AgentID) {
        center.removeDeliveredNotifications(withIdentifiers: [agent.description])
    }

    /// Asks only while the user has not decided; afterwards reads what they chose.
    private func authorize() async -> Bool {
        let granted: Bool
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: granted = true
        case .notDetermined: granted = (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: granted = false
        }
        config.report(granted ? nil : "Notifications are off for Shepherd in System Settings > Notifications",
                      for: "notifications.permission")
        return granted
    }

    // MARK: UNUserNotificationCenterDelegate

    /// Shepherd has no window of its own, so a notification always shows as a banner.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification)
        async -> UNNotificationPresentationOptions {
        [.banner, .list]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        guard let source = info["source"] as? String, let local = info["local"] as? String else { return }
        let agent = AgentID(source: SourceID(rawValue: source), local: local)
        let text = (response as? UNTextInputNotificationResponse)?.userText
        let action = response.actionIdentifier
        await MainActor.run { self.respond(action, agent: agent, text: text) }
    }

    private func respond(_ action: String, agent: AgentID, text: String?) {
        switch action {
        case Self.replyAction:
            guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return }
            let blocked = store.agents.first { $0.id == agent }?.status == .blocked
            Task {
                do {
                    if blocked { try await actions.sendText(agent, text) } else { try await actions.prompt(agent, text) }
                } catch {
                    Self.log.error("reply failed: \(String(describing: error), privacy: .public)")
                }
            }
        case Self.jumpAction, UNNotificationDefaultActionIdentifier:
            actions.jump(to: agent)
        default:
            break
        }
    }
}
