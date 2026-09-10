import Foundation
import VitrineDomain

/// A bounded, SSRF-checked fetch of one remote image.
///
/// It lives apart from `BackgroundImageStore` because the store's other job — copying a
/// user-selected file into a content-addressed directory — shares nothing with it but the
/// byte cap. Keeping the transport, its host policy, its session configuration, and its
/// streaming delegate together means the rules that decide which hosts may be contacted
/// sit next to the code that contacts them, including the redirect re-check.
///
/// One of the app's two direct `URLSession` clients (the other verifies a license key),
/// and the only one that fetches a URL the user supplies, which is why the host policy
/// applies to the initial request and to every redirect.
nonisolated public enum RemoteImageFetcher {

    /// The remote loader shares the universal import limit. Keep this name as the
    /// streaming API's explicit contract and for source compatibility with callers.
    nonisolated public static let maxRemoteImageBytes = BackgroundImageStore.maxImportBytes

    /// Keep the direct remote fetch from lingering forever on a slow or stalled
    /// host. The cap still comes from `maxRemoteImageBytes`; this only bounds the
    /// request's wall-clock time.
    nonisolated private static let remoteImageRequestTimeout: TimeInterval = 20

    /// Loads a remote background image without ever accumulating more than
    /// `maxBytes` in memory. This is the default production loader behind
    /// `importImage(downloadedFrom:)`; tests can inject a tiny cap and local URL protocol to
    /// exercise the transport boundary without a live network.
    nonisolated public static func loadBoundedRemoteImage(
        from url: URL,
        maxBytes: Int = maxRemoteImageBytes
    ) async throws -> (Data, URLResponse) {
        try await loadBoundedRemoteImage(
            from: url,
            maxBytes: maxBytes,
            configuration: remoteImageSessionConfiguration())
    }

    /// The lower-level chunk loader accepts a session configuration so focused tests can use a
    /// local `URLProtocol`. Production supplies an ephemeral configuration; the purpose-built
    /// session never shares cookies or cache state and is cancelled after the request completes.
    nonisolated public static func loadBoundedRemoteImage(
        from url: URL,
        maxBytes: Int,
        configuration: URLSessionConfiguration
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = remoteImageRequestTimeout

        let delegate = BoundedRemoteImageSessionDelegate(maxBytes: maxBytes)
        let delegateQueue = OperationQueue()
        delegateQueue.name = "com.johnny4young.vitrine.remote-image"
        delegateQueue.maxConcurrentOperationCount = 1
        delegateQueue.qualityOfService = .utility
        let session = URLSession(
            configuration: configuration,
            delegate: delegate,
            delegateQueue: delegateQueue)
        defer { session.invalidateAndCancel() }
        return try await delegate.load(request, in: session)
    }

    /// Whether a URL is safe to request for a remote background image. This mirrors
    /// URL capture's scheme and private-host policy and is shared by initial validation,
    /// redirect filtering, and response re-checking.
    nonisolated public static func isAllowedRemoteImageDownloadURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
            let host = url.host, !host.isEmpty
        else {
            return false
        }
        return !PrivateHostPolicy.isPrivateLocalhost(host: host)
    }

    /// Builds the privacy-preserving production session for direct image downloads:
    /// ephemeral storage avoids sending/reading shared website cookies, and the redirect
    /// delegate refuses private/local targets before `URLSession` follows them.
    nonisolated private static func remoteImageSessionConfiguration()
        -> URLSessionConfiguration
    {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = remoteImageRequestTimeout
        configuration.timeoutIntervalForResource = remoteImageRequestTimeout
        return configuration
    }
}

/// Owns one bounded remote-image data task.
///
/// `URLSession.AsyncBytes` exposes a byte-at-a-time sequence even though the transport delivers
/// chunks. Collecting inside `didReceive data` preserves those chunks, rejects a response before
/// appending the chunk that would cross the cap, and cancels the task immediately. The lock covers
/// the only cross-executor races: task cancellation versus serial URLSession delegate callbacks.
nonisolated private final class BoundedRemoteImageSessionDelegate: NSObject,
    URLSessionDataDelegate, @unchecked Sendable
{
    private typealias Output = (Data, URLResponse)

    private struct State {
        var collector: BoundedDataCollector
        var response: URLResponse?
        var continuation: CheckedContinuation<Output, Error>?
        var task: URLSessionDataTask?
        var isFinished = false
    }

    private let lock = NSLock()
    private var state: State

    public init(maxBytes: Int) {
        state = State(collector: BoundedDataCollector(limit: maxBytes))
    }

    public func load(
        _ request: URLRequest, in session: URLSession
    ) async throws -> (Data, URLResponse) {
        try Task.checkCancellation()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation {
                (continuation: CheckedContinuation<Output, Error>) in
                let task = session.dataTask(with: request)
                let shouldCancel = withLockedState { state in
                    guard !state.isFinished, !Task.isCancelled else {
                        state.isFinished = true
                        return true
                    }
                    state.continuation = continuation
                    state.task = task
                    return false
                }

                guard !shouldCancel else {
                    task.cancel()
                    continuation.resume(throwing: CancellationError())
                    return
                }
                task.resume()
            }
        } onCancel: {
            self.cancel()
        }
    }

    private func cancel() {
        let completion = withLockedState {
            state -> (
                CheckedContinuation<Output, Error>?, URLSessionDataTask?
            ) in
            guard !state.isFinished else { return (nil, nil) }
            state.isFinished = true
            defer {
                state.continuation = nil
                state.task = nil
            }
            return (state.continuation, state.task)
        }
        completion.1?.cancel()
        completion.0?.resume(throwing: CancellationError())
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive response: URLResponse,
        completionHandler: @escaping @Sendable (URLSession.ResponseDisposition) -> Void
    ) {
        let expectedLength = response.expectedContentLength
        var continuation: CheckedContinuation<Output, Error>?
        let disposition = withLockedState { state -> URLSession.ResponseDisposition in
            guard !state.isFinished else { return .cancel }
            if expectedLength > Int64(state.collector.limit) {
                state.isFinished = true
                continuation = state.continuation
                state.continuation = nil
                state.task = nil
                return .cancel
            }
            state.response = response
            return .allow
        }

        completionHandler(disposition)
        if let continuation {
            dataTask.cancel()
            continuation.resume(
                throwing: BackgroundImageStore.ImportError.tooLarge)
        }
    }

    public func urlSession(
        _ session: URLSession,
        dataTask: URLSessionDataTask,
        didReceive data: Data
    ) {
        var continuation: CheckedContinuation<Output, Error>?
        let exceededLimit = withLockedState { state -> Bool in
            guard !state.isFinished else { return false }
            do {
                try state.collector.append(data)
                return false
            } catch {
                state.isFinished = true
                continuation = state.continuation
                state.continuation = nil
                state.task = nil
                return true
            }
        }

        guard exceededLimit else { return }
        dataTask.cancel()
        continuation?.resume(
            throwing: BackgroundImageStore.ImportError.tooLarge)
    }

    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        let completion = withLockedState {
            state -> (
                CheckedContinuation<Output, Error>?, Result<Output, Error>?
            ) in
            guard !state.isFinished else { return (nil, nil) }
            state.isFinished = true
            let continuation = state.continuation
            state.continuation = nil
            state.task = nil

            if let error {
                return (continuation, .failure(error))
            }
            guard let response = state.response ?? task.response else {
                return (
                    continuation,
                    .failure(BackgroundImageStore.ImportError.downloadFailed)
                )
            }
            return (continuation, .success((state.collector.data, response)))
        }
        guard let continuation = completion.0, let result = completion.1 else { return }
        continuation.resume(with: result)
    }

    /// Refuses private/local redirects before URLSession follows them. The entry URL and final
    /// response remain checked by `BackgroundImageStore`; this closes the mid-flight redirect gap.
    public func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping @Sendable (URLRequest?) -> Void
    ) {
        guard let redirectedURL = request.url,
            RemoteImageFetcher.isAllowedRemoteImageDownloadURL(redirectedURL)
        else {
            completionHandler(nil)
            return
        }
        completionHandler(request)
    }

    private func withLockedState<Result>(_ body: (inout State) -> Result) -> Result {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }
}
