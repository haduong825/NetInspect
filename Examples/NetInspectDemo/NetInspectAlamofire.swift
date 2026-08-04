import Alamofire
import Foundation
import NetInspectURLSession

/// Demo-only factory for Alamofire sessions whose traffic is captured by NetInspect.
enum NetInspectAlamofire {
    static func makeSession(
        configuration: URLSessionConfiguration = .default,
        delegate: SessionDelegate = SessionDelegate(),
        rootQueue: DispatchQueue = DispatchQueue(label: "com.netinspect.demo.alamofire.rootQueue"),
        startRequestsImmediately: Bool = true,
        requestQueue: DispatchQueue? = nil,
        serializationQueue: DispatchQueue? = nil,
        interceptor: RequestInterceptor? = nil,
        serverTrustManager: ServerTrustManager? = nil,
        redirectHandler: RedirectHandler? = nil,
        cachedResponseHandler: CachedResponseHandler? = nil,
        eventMonitors: [EventMonitor] = [AlamofireNotifications()]
    ) -> Session {
        Session(
            configuration: NetInspectURLSession.configuration(basedOn: configuration),
            delegate: delegate,
            rootQueue: rootQueue,
            startRequestsImmediately: startRequestsImmediately,
            requestQueue: requestQueue,
            serializationQueue: serializationQueue,
            interceptor: interceptor,
            serverTrustManager: serverTrustManager,
            redirectHandler: redirectHandler,
            cachedResponseHandler: cachedResponseHandler,
            eventMonitors: eventMonitors
        )
    }
}
