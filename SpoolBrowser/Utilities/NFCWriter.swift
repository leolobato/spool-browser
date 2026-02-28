import CoreNFC

final class NFCWriter: NSObject, NFCNDEFReaderSessionDelegate, @unchecked Sendable {
    private var session: NFCNDEFReaderSession?
    private var urlToWrite: URL?
    private var completion: ((Result<Void, Error>) -> Void)?
    private let lock = NSLock()

    enum NFCWriteError: LocalizedError, Sendable {
        case noURL
        case noTag
        case notNDEFCompliant
        case readOnly
        case insufficientCapacity
        case writeFailed(String)
        case sessionInvalidated

        var errorDescription: String? {
            switch self {
            case .noURL:
                return "No URL provided to write."
            case .noTag:
                return "No NFC tag was detected."
            case .notNDEFCompliant:
                return "The tag is not NDEF compliant."
            case .readOnly:
                return "The tag is read-only and cannot be written to."
            case .insufficientCapacity:
                return "The tag does not have enough capacity for this URL."
            case .writeFailed(let reason):
                return "Failed to write to tag: \(reason)"
            case .sessionInvalidated:
                return "NFC session was invalidated."
            }
        }
    }

    func write(url: URL, completion: @escaping @Sendable (Result<Void, Error>) -> Void) {
        lock.lock()
        self.urlToWrite = url
        self.completion = completion
        lock.unlock()

        guard NFCNDEFReaderSession.readingAvailable else {
            completion(.failure(NFCWriteError.writeFailed("NFC is not available on this device.")))
            return
        }

        let newSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: false)
        lock.lock()
        session = newSession
        lock.unlock()

        newSession.alertMessage = "Hold your iPhone near the NFC tag to write the URL."
        newSession.begin()
    }

    // MARK: - NFCNDEFReaderSessionDelegate

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        // Not used for writing
    }

    func readerSession(_ session: NFCNDEFReaderSession, didDetect tags: [NFCNDEFTag]) {
        guard let tag = tags.first else {
            session.invalidate(errorMessage: "No tag detected.")
            callCompletion(with: .failure(NFCWriteError.noTag))
            return
        }

        lock.lock()
        let url = urlToWrite
        lock.unlock()

        guard let url = url else {
            session.invalidate(errorMessage: "No URL to write.")
            callCompletion(with: .failure(NFCWriteError.noURL))
            return
        }

        session.connect(to: tag) { [weak self] error in
            guard let self = self else { return }

            if let error = error {
                session.invalidate(errorMessage: "Connection failed.")
                self.callCompletion(with: .failure(NFCWriteError.writeFailed(error.localizedDescription)))
                return
            }

            tag.queryNDEFStatus { [weak self] status, capacity, error in
                guard let self = self else { return }

                if let error = error {
                    session.invalidate(errorMessage: "Failed to query tag.")
                    self.callCompletion(with: .failure(NFCWriteError.writeFailed(error.localizedDescription)))
                    return
                }

                switch status {
                case .notSupported:
                    session.invalidate(errorMessage: "Tag is not NDEF compliant.")
                    self.callCompletion(with: .failure(NFCWriteError.notNDEFCompliant))

                case .readOnly:
                    session.invalidate(errorMessage: "Tag is read-only.")
                    self.callCompletion(with: .failure(NFCWriteError.readOnly))

                case .readWrite:
                    guard let uriPayload = NFCNDEFPayload.wellKnownTypeURIPayload(url: url) else {
                        session.invalidate(errorMessage: "Failed to create URL payload.")
                        self.callCompletion(with: .failure(NFCWriteError.writeFailed("Could not create NDEF payload from URL.")))
                        return
                    }

                    let message = NFCNDEFMessage(records: [uriPayload])

                    let messageLength = message.length
                    if messageLength > capacity {
                        session.invalidate(errorMessage: "Tag capacity too small.")
                        self.callCompletion(with: .failure(NFCWriteError.insufficientCapacity))
                        return
                    }

                    tag.writeNDEF(message) { [weak self] error in
                        guard let self = self else { return }

                        if let error = error {
                            session.invalidate(errorMessage: "Write failed.")
                            self.callCompletion(with: .failure(NFCWriteError.writeFailed(error.localizedDescription)))
                        } else {
                            session.alertMessage = "URL written successfully!"
                            session.invalidate()
                            self.callCompletion(with: .success(()))
                        }
                    }

                @unknown default:
                    session.invalidate(errorMessage: "Unknown tag status.")
                    self.callCompletion(with: .failure(NFCWriteError.writeFailed("Unknown tag status.")))
                }
            }
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        // Check if this is a user cancellation
        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorUserCanceled {
            callCompletion(with: .failure(NFCWriteError.sessionInvalidated))
            return
        }

        lock.lock()
        let hasCompletion = completion != nil
        lock.unlock()

        if hasCompletion {
            callCompletion(with: .failure(NFCWriteError.writeFailed(error.localizedDescription)))
        }
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {
        // Session is active, waiting for tag
    }

    // MARK: - Private

    private func callCompletion(with result: Result<Void, Error>) {
        lock.lock()
        let completionHandler = completion
        completion = nil
        session = nil
        urlToWrite = nil
        lock.unlock()

        if let handler = completionHandler {
            DispatchQueue.main.async {
                handler(result)
            }
        }
    }
}
