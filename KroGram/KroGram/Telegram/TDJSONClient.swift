import Foundation
import TDLibFramework

typealias JSON = [String: Any]

/// JSON payload wrapper so it can cross concurrency boundaries.
struct TDObject: @unchecked Sendable {
    let json: JSON
}

struct TDError: Error, Sendable {
    let code: Int
    let message: String
}

/// Thin wrapper over TDLib's JSON interface (td_json_client).
/// One process-wide instance: TDLib allows a single receiving thread.
/// Requests and responses are never logged (they can contain phone numbers and codes).
final class TDJSONClient: @unchecked Sendable {
    static let shared = TDJSONClient()

    private let lock = NSLock()
    private var clientID: Int32 = 0
    private var pending: [Int: CheckedContinuation<TDObject, Error>] = [:]
    private var nextExtra = 1
    private var sink: AsyncStream<TDObject>.Continuation?

    private init() {
        _ = td_execute(#"{"@type":"setLogVerbosityLevel","new_verbosity_level":1}"#)
        let thread = Thread { [unowned self] in self.receiveLoop() }
        thread.name = "krochat.tdlib.receive"
        thread.qualityOfService = .utility
        thread.start()
    }

    /// Starts a fresh TDLib client; updates for it are delivered to `sink`.
    func startSession(sink newSink: AsyncStream<TDObject>.Continuation) {
        lock.lock()
        let stale = pending
        pending.removeAll()
        sink = newSink
        clientID = td_create_client_id()
        let id = clientID
        lock.unlock()
        for (_, continuation) in stale {
            continuation.resume(throwing: TDError(code: -1, message: "SESSION_RESTARTED"))
        }
        td_send(id, #"{"@type":"getOption","name":"version"}"#)
    }

    func request(_ query: JSON) async throws -> TDObject {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<TDObject, Error>) in
            lock.lock()
            let extra = nextExtra
            nextExtra += 1
            pending[extra] = continuation
            let id = clientID
            lock.unlock()
            var payload = query
            payload["@extra"] = extra
            guard let data = try? JSONSerialization.data(withJSONObject: payload),
                  let text = String(data: data, encoding: .utf8) else {
                lock.lock(); pending.removeValue(forKey: extra); lock.unlock()
                continuation.resume(throwing: TDError(code: -2, message: "ENCODE_FAILED"))
                return
            }
            td_send(id, text)
        }
    }

    /// Fire-and-forget request.
    func send(_ query: JSON) {
        lock.lock(); let id = clientID; lock.unlock()
        guard let data = try? JSONSerialization.data(withJSONObject: query),
              let text = String(data: data, encoding: .utf8) else { return }
        td_send(id, text)
    }

    private func receiveLoop() {
        while true {
            guard let raw = td_receive(1.0) else { continue }
            handle(String(cString: raw))
        }
    }

    private func handle(_ text: String) {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? JSON else { return }

        lock.lock()
        let current = clientID
        let output = sink
        lock.unlock()

        if let cid = (object["@client_id"] as? NSNumber)?.int32Value, cid != current { return }

        if let extra = (object["@extra"] as? NSNumber)?.intValue {
            lock.lock()
            let continuation = pending.removeValue(forKey: extra)
            lock.unlock()
            if let continuation {
                if (object["@type"] as? String) == "error" {
                    continuation.resume(throwing: TDError(
                        code: (object["code"] as? NSNumber)?.intValue ?? 0,
                        message: object["message"] as? String ?? ""
                    ))
                } else {
                    continuation.resume(returning: TDObject(json: object))
                }
                return
            }
        }
        output?.yield(TDObject(json: object))
    }
}
