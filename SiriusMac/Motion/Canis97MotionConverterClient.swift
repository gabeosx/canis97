import Canis97MotionSafety
@preconcurrency import Foundation

actor Canis97MotionConverterClient {
    enum ClientError: Error, Equatable, Sendable {
        case oversizedInput
        case service(Canis97MotionConversionFailure)
        case malformedReply
        case interrupted
        case invalidated
        case timedOut
        case cancelled
        case validationFailed(MotionSafetyDiagnostic.Code)
    }

    private let serviceName: String
    private let limits: MotionSafetyLimits
    private let maximumRequestBytes: Int
    private let timeout: Duration

    init(
        serviceName: String = "com.canis97.player.motion-converter",
        limits: MotionSafetyLimits = .production,
        maximumRequestBytes: Int = 6 * 1_024 * 1_024,
        timeout: Duration = .seconds(10)
    ) {
        self.serviceName = serviceName
        self.limits = limits
        self.maximumRequestBytes = maximumRequestBytes
        self.timeout = timeout
    }

    func convert(_ request: Data) async throws -> CanonicalMotionDocument {
        guard request.count <= maximumRequestBytes else { throw ClientError.oversizedInput }

        return try await withThrowingTaskGroup(of: CanonicalMotionDocument.self) { group in
            group.addTask { [serviceName, limits] in
                try await Self.performRequest(request, serviceName: serviceName, limits: limits)
            }
            group.addTask { [timeout] in
                try await Task.sleep(for: timeout)
                throw ClientError.timedOut
            }
            defer { group.cancelAll() }
            guard let document = try await group.next() else { throw ClientError.cancelled }
            return document
        }
    }

    private static func performRequest(
        _ request: Data,
        serviceName: String,
        limits: MotionSafetyLimits
    ) async throws -> CanonicalMotionDocument {
        let completion = XPCCompletion()
        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                let connection = NSXPCConnection(serviceName: serviceName)
                completion.install(continuation, connection: connection)
                connection.remoteObjectInterface = NSXPCInterface(with: Canis97MotionXPCProtocol.self)
                connection.interruptionHandler = { completion.finish(.failure(ClientError.interrupted)) }
                connection.invalidationHandler = { completion.finish(.failure(ClientError.invalidated)) }
                connection.resume()

                guard let proxy = connection.remoteObjectProxyWithErrorHandler({ _ in
                    completion.finish(.failure(ClientError.service(.transportFailure)))
                }) as? Canis97MotionXPCProtocol else {
                    completion.finish(.failure(ClientError.service(.transportFailure)))
                    return
                }
                proxy.convert(request) { data in
                    do {
                        let reply = try JSONDecoder().decode(Canis97MotionConversionReply.self, from: data)
                        if let failure = reply.failure, reply.canonicalData == nil {
                            completion.finish(.failure(ClientError.service(failure)))
                            return
                        }
                        guard reply.failure == nil, let canonicalData = reply.canonicalData else {
                            throw ClientError.malformedReply
                        }
                        do {
                            completion.finish(.success(try CanonicalMotionCodec.decode(canonicalData, limits: limits)))
                        } catch let error as MotionSafetyError {
                            completion.finish(.failure(ClientError.validationFailed(error.diagnostic.code)))
                        } catch {
                            completion.finish(.failure(ClientError.malformedReply))
                        }
                    } catch {
                        completion.finish(.failure(ClientError.malformedReply))
                    }
                }
            }
        } onCancel: {
            completion.finish(.failure(ClientError.cancelled))
        }
    }
}

private final class XPCCompletion: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<CanonicalMotionDocument, Error>?
    private var connection: NSXPCConnection?

    func install(_ continuation: CheckedContinuation<CanonicalMotionDocument, Error>, connection: NSXPCConnection) {
        lock.lock()
        self.continuation = continuation
        self.connection = connection
        lock.unlock()
    }

    func finish(_ result: Result<CanonicalMotionDocument, Error>) {
        lock.lock()
        let continuation = self.continuation
        self.continuation = nil
        let connection = self.connection
        self.connection = nil
        lock.unlock()

        guard let continuation else { return }
        connection?.invalidate()
        continuation.resume(with: result)
    }
}
