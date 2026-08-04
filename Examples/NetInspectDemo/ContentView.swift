import Foundation
import SwiftUI
import Alamofire
import NetInspectCore
import NetInspectURLSession
import NetInspectUI

struct ContentView: View {
    private enum NetworkClient: String {
        case urlSession = "URLSession"
        case alamofire = "Alamofire"
    }

    private struct DemoService: Identifiable {
        let id: String
        let title: String
        let provider: String
        let method: String
        let url: URL
        let description: String
        let body: Data?
        let headers: [String: String]
        let client: NetworkClient
    }

    private struct ServiceResult {
        let message: String
        let detail: String
        let statusCode: Int?
        let isSuccess: Bool
    }

    private static let services: [DemoService] = [
        DemoService(
            id: "jsonplaceholder",
            title: "Posts API",
            provider: "JSONPlaceholder",
            method: "GET",
            url: URL(string: "https://jsonplaceholder.typicode.com/posts/1")!,
            description: "Public demo REST API returning a sample post.",
            body: nil,
            headers: [:],
            client: .urlSession
        ),
        DemoService(
            id: "rest-countries",
            title: "Country API",
            provider: "REST Countries",
            method: "GET",
            url: URL(string: "https://restcountries.com/v3.1/name/vietnam?fields=name,capital,population")!,
            description: "Live country data with a compact field selection.",
            body: nil,
            headers: [:],
            client: .urlSession
        ),
        DemoService(
            id: "httpbin",
            title: "Request Echo",
            provider: "httpbin",
            method: "POST",
            url: URL(string: "https://httpbin.org/anything/netinspect-demo")!,
            description: "Echo service useful for inspecting request bodies and headers.",
            body: Data(#"{"source":"NetInspectDemo","message":"Hello from the demo app"}"#.utf8),
            headers: ["Content-Type": "application/json"],
            client: .alamofire
        )
    ]

    private static let alamofireSession = NetInspectAlamofire.makeSession()

    @State private var events: [NetInspectEvent] = []
    @State private var results: [String: ServiceResult] = [:]
    @State private var runningServices: Set<String> = []

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    intro

                    Text("Public services")
                        .font(.title3.weight(.semibold))

                    VStack(spacing: 12) {
                        ForEach(Self.services) { service in
                            serviceCard(service)
                        }
                    }

                    HStack {
                        Text("Captured events")
                            .font(.title3.weight(.semibold))
                        Spacer()
                        Text("\(events.count)")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }

                    if events.isEmpty {
                        Text("Send a request above to populate the NetInspect event stream.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(events.indices, id: \.self) { index in
                                eventRow(events[index])
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("NetInspect")
            .toolbar {
                Button("Run all") { runAllServices() }
                Button("Monitor") { NetInspectUI.present() }
            }
        }
        .background(NetInspectShakeInstaller())
        .onAppear(perform: refresh)
    }

    private var intro: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Service Playground")
                .font(.largeTitle.weight(.bold))
            Text("Call public APIs through instrumented URLSession and Alamofire clients, then inspect every request, response, and payload in NetInspect.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private func serviceCard(_ service: DemoService) -> some View {
        let result = results[service.id]
        let isRunning = runningServices.contains(service.id)

        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.title)
                        .font(.headline)
                    Text(service.provider)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 5) {
                    Text(service.method)
                        .font(.caption.weight(.bold).monospaced())
                        .foregroundStyle(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.blue.opacity(0.12), in: Capsule())
                    Text(service.client.rawValue)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
            }

            Text(service.description)
                .font(.subheadline)

            Text(service.url.absoluteString)
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)

            if let result {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: result.isSuccess ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(result.isSuccess ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.message)
                            .font(.subheadline.weight(.semibold))
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                    Spacer()
                    if let statusCode = result.statusCode {
                        Text(String(statusCode))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Button {
                request(service)
            } label: {
                Label(isRunning ? "Requesting…" : "Send request", systemImage: isRunning ? "hourglass" : "arrow.up.right")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(isRunning)
        }
        .padding()
        .background(Color(uiColor: .secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private func eventRow(_ event: NetInspectEvent) -> some View {
        switch event {
        case .network(let network):
            VStack(alignment: .leading, spacing: 3) {
                Text("NETWORK \(network.method) \(network.responseStatusCode.map(String.init) ?? "-")")
                    .font(.headline)
                Text(network.url)
                    .font(.caption)
                    .lineLimit(2)
                Text("\(Int(network.durationMilliseconds ?? 0)) ms")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        case .console(let log):
            VStack(alignment: .leading, spacing: 3) {
                Text("\(log.level.rawValue.uppercased()) · \(log.category)")
                    .font(.headline)
                Text(log.message)
                    .font(.body)
            }
            .padding(.vertical, 4)
        }
    }

    private func refresh() {
        guard let data = try? NetInspect.exportJSON() else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(ExportEnvelope.self, from: data) else { return }
        events = envelope.events
    }

    private func runAllServices() {
        Self.services.forEach(request)
    }

    private func request(_ service: DemoService) {
        guard !runningServices.contains(service.id) else { return }

        runningServices.insert(service.id)
        var request = URLRequest(url: service.url)
        request.httpMethod = service.method
        request.httpBody = service.body
        service.headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }

        switch service.client {
        case .urlSession:
            let session = NetInspectURLSession.makeSession()
            session.dataTask(with: request) { data, response, error in
                finishRequest(service, data: data, response: response, error: error)
            }.resume()
        case .alamofire:
            Self.alamofireSession.request(request).responseData { response in
                finishRequest(service, data: response.data, response: response.response, error: response.error)
            }
        }
    }

    private func finishRequest(_ service: DemoService, data: Data?, response: URLResponse?, error: Error?) {
        let httpResponse = response as? HTTPURLResponse
        let result: ServiceResult

        if let error {
            result = ServiceResult(
                message: "Request failed",
                detail: error.localizedDescription,
                statusCode: httpResponse?.statusCode,
                isSuccess: false
            )
        } else {
            result = summarize(data: data, service: service, statusCode: httpResponse?.statusCode)
        }

        DispatchQueue.main.async {
            results[service.id] = result
            runningServices.remove(service.id)
            refresh()
        }
    }

    private func summarize(data: Data?, service: DemoService, statusCode: Int?) -> ServiceResult {
        let successfulStatus = (200..<300).contains(statusCode ?? 0)
        guard successfulStatus else {
            return ServiceResult(
                message: "HTTP request returned an error",
                detail: responseSnippet(data),
                statusCode: statusCode,
                isSuccess: false
            )
        }

        guard let data,
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return ServiceResult(
                message: "Request completed",
                detail: responseSnippet(data),
                statusCode: statusCode,
                isSuccess: true
            )
        }

        switch service.id {
        case "jsonplaceholder":
            let post = object as? [String: Any]
            let id = post?["id"] as? Int ?? 0
            let title = post?["title"] as? String ?? "No title"
            return ServiceResult(message: "Loaded post #\(id)", detail: title, statusCode: statusCode, isSuccess: true)
        case "rest-countries":
            let country = (object as? [[String: Any]])?.first
            let name = (country?["name"] as? [String: Any])?["common"] as? String ?? "Unknown country"
            let capital = (country?["capital"] as? [String])?.first ?? "No capital"
            let population = country?["population"] as? Int ?? 0
            return ServiceResult(
                message: name,
                detail: "Capital: \(capital) · Population: \(population.formatted())",
                statusCode: statusCode,
                isSuccess: true
            )
        case "httpbin":
            let echoedMethod = (object as? [String: Any])?["method"] as? String ?? service.method
            return ServiceResult(
                message: "Echoed \(echoedMethod) request",
                detail: "httpbin returned the request payload and headers.",
                statusCode: statusCode,
                isSuccess: true
            )
        default:
            return ServiceResult(message: "Request completed", detail: responseSnippet(data), statusCode: statusCode, isSuccess: true)
        }
    }

    private func responseSnippet(_ data: Data?) -> String {
        guard let data, let body = String(data: data, encoding: .utf8) else { return "No response body" }
        let snippet = String(body.prefix(180)).replacingOccurrences(of: "\n", with: " ")
        return snippet + (body.count > 180 ? "…" : "")
    }
}

typealias NetInspectDemoView = ContentView
