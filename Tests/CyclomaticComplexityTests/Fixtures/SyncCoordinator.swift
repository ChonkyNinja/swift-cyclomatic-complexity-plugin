actor SyncCoordinator {
    enum State { case idle, loading, ready, failed }

    private(set) var state: State = .idle

    var canRetry: Bool {
        if case .failed = state { return true }
        return false
    }

    func synchronize(force: Bool, online: Bool) async throws -> State {
        guard online else { return .failed }
        if force || state == .idle {
            state = .loading
        }
        switch state {
        case .idle: return .idle
        case .loading: return .ready
        case .ready: return .ready
        case .failed: return .failed
        }
    }

    func makeCompletion() -> (Bool) -> Bool {
        { success in
            if success { return true }
            return false
        }
    }
}
