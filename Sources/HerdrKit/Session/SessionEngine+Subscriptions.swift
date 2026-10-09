import Foundation

extension SessionEngine {
    /// Carries out the planner's commands.
    func perform(_ commands: [SubscriptionPlanner.Command]) {
        for command in commands {
            switch command {
            case .start(let generation, let set):
                let client = client
                let timeout = subscribeTimeout
                Task { [weak self] in
                    do {
                        let subscription = try await EventSubscription.start(path: client.socketPath, set: set, timeout: timeout)
                        await self?.subscriptionStarted(generation, subscription) ?? subscription.close()
                    } catch {
                        await self?.handle(.startFailed(generation: generation, error as? HerdrError ?? .disconnected))
                    }
                }
            case .close(let generation):
                subscriptions.removeValue(forKey: generation)?.close()
            case .refresh:
                markDirty()
            case .gap:
                epoch += 1
            case .scheduleRetry(let delay):
                scheduleRetry(after: delay)
            case .state(let state):
                connection = state
                watchSocketDirectory(state.isDisconnected)
                publish([])
            }
        }
    }

    func handle(_ input: SubscriptionPlanner.Input) {
        guard !stopped else { return }
        perform(planner.handle(input))
    }

    private func subscriptionStarted(_ generation: Int, _ subscription: EventSubscription) {
        guard !stopped else {
            subscription.close()
            return
        }
        subscriptions[generation] = subscription
        let onEvent: @Sendable (HerdrEvent) async -> Void = { [weak self] _ in await self?.markDirty() }
        // The pump ends by itself once the subscription's connection closes.
        Task { [weak self] in
            let end = await subscription.run(onEvent: onEvent)
            await self?.handle(.ended(generation: generation, end))
        }
        retryTask?.cancel()
        watchSocketDirectory(false)
        perform(planner.handle(.started(generation: generation)))
    }

    private func scheduleRetry(after delay: Duration) {
        retryTask?.cancel()
        retryTask = Task { [weak self] in
            try? await Task.sleep(for: delay)
            guard !Task.isCancelled else { return }
            await self?.handle(.retry)
        }
    }

    /// While herdr is down, retry as soon as its socket folder changes.
    private func watchSocketDirectory(_ watch: Bool) {
        if watch, dirWatcher == nil {
            dirWatcher = SocketDirWatcher(socketPath: client.socketPath) { [weak self] in
                Task { await self?.socketDirectoryChanged() }
            }
        } else if !watch {
            dirWatcher?.cancel()
            dirWatcher = nil
        }
    }

    private func socketDirectoryChanged() {
        guard planner.waitingForRetry, planner.active == nil else { return }
        retryTask?.cancel()
        handle(.retry)
    }
}

extension ConnectionState {
    var isDisconnected: Bool {
        if case .disconnected = self { true } else { false }
    }
}
