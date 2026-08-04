import Foundation
import NetInspectCore

public final class NetInspectURLProtocol: URLProtocol {
    private static let handledKey = "NetInspectURLProtocol.handled"
    private var session: URLSession?
    private var forwardingDelegate: ForwardingDelegate?
    private var startDate = Date()
    private var requestData: Data?
    private var responseData = Data()
    private var response: HTTPURLResponse?
    private var completed = false

    public override class func canInit(with request: URLRequest) -> Bool {
        guard URLProtocol.property(forKey: handledKey, in: request) == nil else { return false }
        guard let scheme = request.url?.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }

    public override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    public override func startLoading() {
        startDate = Date()
        requestData = request.httpBody
        let mutableRequest = (request as NSURLRequest).mutableCopy() as! NSMutableURLRequest
        URLProtocol.setProperty(true, forKey: Self.handledKey, in: mutableRequest)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        configuration.timeoutIntervalForRequest = request.timeoutInterval
        configuration.timeoutIntervalForResource = request.timeoutInterval

        let delegate = ForwardingDelegate(owner: self)
        forwardingDelegate = delegate
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        self.session = session
        session.dataTask(with: mutableRequest as URLRequest).resume()
    }

    public override func stopLoading() {
        guard !completed else { return }
        completed = true
        session?.invalidateAndCancel()
        session = nil
        record(statusCode: nil, error: "Request cancelled")
    }

    private func receive(response: URLResponse, completion: @escaping (URLSession.ResponseDisposition) -> Void) {
        self.response = response as? HTTPURLResponse
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        completion(.allow)
    }

    private func receive(data: Data) {
        responseData.append(data)
        client?.urlProtocol(self, didLoad: data)
    }

    private func complete(error: Error?) {
        guard !completed else { return }
        completed = true
        if let error {
            client?.urlProtocol(self, didFailWithError: error)
        } else {
            client?.urlProtocolDidFinishLoading(self)
        }
        record(statusCode: response?.statusCode, error: error?.localizedDescription)
        session?.finishTasksAndInvalidate()
        session = nil
    }

    private func record(statusCode: Int?, error: String?) {
        let capture = NetInspect.currentCaptureConfiguration()
        let requestHeaders = capture.captureRequestHeaders ? (request.allHTTPHeaderFields ?? [:]) : [:]
        let responseHeaders = capture.captureResponseHeaders ? (response?.allHeaderFields.reduce(into: [String: String]()) { result, item in
            result[String(describing: item.key)] = String(describing: item.value)
        } ?? [:]) : [:]
        let elapsed = Date().timeIntervalSince(startDate) * 1000
        let event = NetworkEvent(
            timestamp: startDate,
            url: request.url?.absoluteString ?? "",
            method: request.httpMethod ?? "GET",
            requestHeaders: requestHeaders,
            requestBody: CapturedBody.from(data: requestData, maxBytes: capture.maxBodyBytes),
            responseStatusCode: statusCode,
            responseHeaders: responseHeaders,
            responseBody: CapturedBody.from(data: responseData, maxBytes: capture.maxBodyBytes),
            durationMilliseconds: elapsed,
            errorDescription: error,
            requestBytes: requestData?.count,
            responseBytes: responseData.isEmpty ? nil : responseData.count
        )
        NetInspect.record(.network(event))
    }

    private final class ForwardingDelegate: NSObject, URLSessionDataDelegate, URLSessionTaskDelegate {
        weak var owner: NetInspectURLProtocol?

        init(owner: NetInspectURLProtocol) {
            self.owner = owner
        }

        func urlSession(
            _ session: URLSession,
            dataTask: URLSessionDataTask,
            didReceive response: URLResponse,
            completionHandler: @escaping (URLSession.ResponseDisposition) -> Void
        ) {
            owner?.receive(response: response, completion: completionHandler)
        }

        func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
            owner?.receive(data: data)
        }

        func urlSession(
            _ session: URLSession,
            task: URLSessionTask,
            willPerformHTTPRedirection response: HTTPURLResponse,
            newRequest request: URLRequest,
            completionHandler: @escaping (URLRequest?) -> Void
        ) {
            if let owner {
                owner.client?.urlProtocol(owner, wasRedirectedTo: request, redirectResponse: response)
            }
            completionHandler(request)
        }

        func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
            owner?.complete(error: error)
        }
    }
}

public enum NetInspectURLSession {
    public static func configuration(
        basedOn configuration: URLSessionConfiguration = .default
    ) -> URLSessionConfiguration {
        let copy = (configuration.copy() as? URLSessionConfiguration) ?? configuration
        var classes = copy.protocolClasses ?? []
        if !classes.contains(where: { $0 == NetInspectURLProtocol.self }) {
            classes.insert(NetInspectURLProtocol.self, at: 0)
        }
        copy.protocolClasses = classes
        return copy
    }

    public static func makeSession(
        configuration: URLSessionConfiguration = .default,
        delegate: URLSessionDelegate? = nil,
        delegateQueue: OperationQueue? = nil
    ) -> URLSession {
        URLSession(configuration: Self.configuration(basedOn: configuration), delegate: delegate, delegateQueue: delegateQueue)
    }
}
