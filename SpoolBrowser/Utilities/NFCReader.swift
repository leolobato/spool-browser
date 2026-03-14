import CoreNFC

final class NFCReader: NSObject, NFCNDEFReaderSessionDelegate, @unchecked Sendable {
    private var session: NFCNDEFReaderSession?
    private var completion: ((Result<URL, Error>) -> Void)?
    private let lock = NSLock()

    enum NFCReadError: LocalizedError, Sendable {
        case noTag
        case noRecords
        case noURL
        case sessionCancelled

        var errorDescription: String? {
            switch self {
            case .noTag:
                return "No NFC tag was detected."
            case .noRecords:
                return "The NFC tag has no records."
            case .noURL:
                return "The NFC tag does not contain a valid URL."
            case .sessionCancelled:
                return "NFC session was cancelled."
            }
        }
    }

    func read(completion: @escaping @Sendable (Result<URL, Error>) -> Void) {
        lock.lock()
        self.completion = completion
        lock.unlock()

        guard NFCNDEFReaderSession.readingAvailable else {
            completion(.failure(NFCReadError.noTag))
            return
        }

        let newSession = NFCNDEFReaderSession(delegate: self, queue: nil, invalidateAfterFirstRead: true)
        lock.lock()
        session = newSession
        lock.unlock()

        newSession.alertMessage = "Hold your iPhone near an NFC tag."
        newSession.begin()
    }

    // MARK: - NFCNDEFReaderSessionDelegate

    func readerSession(_ session: NFCNDEFReaderSession, didDetectNDEFs messages: [NFCNDEFMessage]) {
        guard let record = messages.first?.records.first else {
            callCompletion(with: .failure(NFCReadError.noRecords))
            return
        }

        if let url = record.wellKnownTypeURIPayload() {
            session.alertMessage = "Tag read successfully!"
            callCompletion(with: .success(url))
        } else {
            callCompletion(with: .failure(NFCReadError.noURL))
        }
    }

    func readerSession(_ session: NFCNDEFReaderSession, didInvalidateWithError error: Error) {
        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorUserCanceled {
            callCompletion(with: .failure(NFCReadError.sessionCancelled))
            return
        }

        if let nfcError = error as? NFCReaderError,
           nfcError.code == .readerSessionInvalidationErrorFirstNDEFTagRead {
            return
        }

        lock.lock()
        let hasCompletion = completion != nil
        lock.unlock()

        if hasCompletion {
            callCompletion(with: .failure(NFCReadError.noURL))
        }
    }

    func readerSessionDidBecomeActive(_ session: NFCNDEFReaderSession) {}

    // MARK: - Private

    private func callCompletion(with result: Result<URL, Error>) {
        lock.lock()
        let completionHandler = completion
        completion = nil
        session = nil
        lock.unlock()

        if let handler = completionHandler {
            DispatchQueue.main.async {
                handler(result)
            }
        }
    }
}
