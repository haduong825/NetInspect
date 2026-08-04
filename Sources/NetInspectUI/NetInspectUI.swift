#if canImport(UIKit) && canImport(SwiftUI)
import SwiftUI
import UIKit
import NetInspectCore

public struct NetInspectUIConfiguration: Sendable {
    public var title: String
    public var presentationStyle: UIModalPresentationStyle

    public init(title: String = "NetInspect", presentationStyle: UIModalPresentationStyle = .pageSheet) {
        self.title = title
        self.presentationStyle = presentationStyle
    }
}

private func resignActiveKeyboard() {
    UIApplication.shared.sendAction(
        #selector(UIResponder.resignFirstResponder),
        to: nil,
        from: nil,
        for: nil
    )
}

private final class NetInspectHostingController: UIHostingController<NetInspectMonitorView> {
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        dismissKeyboardAfterPresentation()
    }

    private func dismissKeyboardAfterPresentation() {
        resignActiveKeyboard()
        view.endEditing(true)

        // SwiftUI's searchable field can receive focus one run-loop after the
        // hosting controller appears. Resign again after that focus pass.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.endEditing(true)
            resignActiveKeyboard()
        }
    }
}

/// Installs the shake gesture listener and presents the monitor over the app's current screen.
@MainActor
public enum NetInspectUI {
    private static var observers: [ObjectIdentifier: NetInspectShakeObserver] = [:]
    private static var configuration = NetInspectUIConfiguration()

    public static func installShakeToPresent(
        in window: UIWindow,
        configuration: NetInspectUIConfiguration = .init()
    ) {
        self.configuration = configuration
        let key = ObjectIdentifier(window)
        guard observers[key] == nil else {
            return
        }

        let observer = NetInspectShakeObserver { [weak window] in
            guard let window else { return }
            present(in: window, configuration: configuration)
        }
        observer.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
        observer.view.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
        observer.view.alpha = 0.01
        observer.view.isUserInteractionEnabled = false
        // A SwiftUI app commonly uses UIHostingController as its root. UIKit does
        // not support adding UIKit-managed subviews directly to the hosting view,
        // so keep the standalone observer beside it at the window level instead.
        // The registry retains its controller; UIKit containment is intentionally
        // omitted because its view is not inside a parent controller's view.
        window.addSubview(observer.view)
        observers[key] = observer
        observer.activate()
    }

    public static func present(
        from viewController: UIViewController? = nil,
        configuration: NetInspectUIConfiguration = .init()
    ) {
        let presenter = viewController ?? keyWindow?.topMostViewController
        guard let presenter, let window = presenter.view.window ?? keyWindow else { return }
        present(in: window, from: presenter, configuration: configuration)
    }

    public static func makeViewController(
        configuration: NetInspectUIConfiguration = .init()
    ) -> UIViewController {
        let controller = NetInspectHostingController(rootView: NetInspectMonitorView(title: configuration.title))
        controller.modalPresentationStyle = configuration.presentationStyle
        return controller
    }

    private static func present(
        in window: UIWindow,
        from suppliedPresenter: UIViewController? = nil,
        configuration: NetInspectUIConfiguration
    ) {
        let presenter = suppliedPresenter ?? window.topMostViewController
        guard let presenter, presenter.presentedViewController == nil else { return }
        let controller = makeViewController(configuration: configuration)
        resignActiveKeyboard()
        presenter.present(controller, animated: true) {
            controller.view.endEditing(true)
            resignActiveKeyboard()
        }
    }

    private static var keyWindow: UIWindow? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }
}

public final class NetInspectShakeObserver: UIViewController {
    private let onShake: () -> Void

    public init(onShake: @escaping () -> Void) {
        self.onShake = onShake
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("NetInspectShakeObserver does not support NSCoder initialization")
    }

    public override var canBecomeFirstResponder: Bool { true }

    func activate() {
        view.isHidden = false
        becomeFirstResponder()
    }

    public override func motionEnded(_ motion: UIEvent.EventSubtype, with event: UIEvent?) {
        guard motion == .motionShake else { return }
        onShake()
    }
}

/// Add this to a SwiftUI root view when the app does not expose its UIWindow.
public struct NetInspectShakeInstaller: View {
    private let configuration: NetInspectUIConfiguration

    public init(configuration: NetInspectUIConfiguration = .init()) {
        self.configuration = configuration
    }

    public var body: some View {
        InstallerRepresentable(configuration: configuration)
            .frame(width: 0, height: 0)
            .allowsHitTesting(false)
    }

    public final class InstallerViewController: UIViewController {
        private let configuration: NetInspectUIConfiguration
        private var didInstall = false

        init(configuration: NetInspectUIConfiguration) {
            self.configuration = configuration
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            fatalError("NetInspectShakeInstaller does not support NSCoder initialization")
        }

        public override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            installIfPossible()
        }

        public override func didMove(toParent parent: UIViewController?) {
            super.didMove(toParent: parent)
            installIfPossible()
        }

        private func installIfPossible() {
            guard !didInstall, let window = view.window else { return }
            didInstall = true
            NetInspectUI.installShakeToPresent(in: window, configuration: configuration)
        }
    }
}

private struct InstallerRepresentable: UIViewControllerRepresentable {
    let configuration: NetInspectUIConfiguration

    func makeUIViewController(context: Context) -> NetInspectShakeInstaller.InstallerViewController {
        NetInspectShakeInstaller.InstallerViewController(configuration: configuration)
    }

    func updateUIViewController(
        _ viewController: NetInspectShakeInstaller.InstallerViewController,
        context: Context
    ) {}
}

public struct NetInspectMonitorView: View {
    fileprivate enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case network = "Network"
        case console = "Console"
        case duplicates = "Duplicates"

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All events"
            case .network: return "Network"
            case .console: return "Console"
            case .duplicates: return "Duplicates"
            }
        }
    }

    fileprivate enum StatusFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case success = "Success"
        case clientError = "4xx"
        case serverError = "5xx"
        case failed = "Failed"

        var id: String { rawValue }
    }

    fileprivate enum LogLevelFilter: String, CaseIterable, Identifiable {
        case all = "All"
        case trace
        case debug
        case info
        case warning
        case error
        case fault

        var id: String { rawValue }

        var title: String {
            rawValue == "All" ? rawValue : rawValue.capitalized
        }
    }

    fileprivate enum SortOrder: String, CaseIterable, Identifiable {
        case newest = "Newest first"
        case oldest = "Oldest first"

        var id: String { rawValue }
    }

    @Environment(\.dismiss) private var dismiss
    @State private var events: [NetInspectEvent] = []
    @State private var filter: Filter = .all
    @State private var statusFilter: StatusFilter = .all
    @State private var logLevelFilter: LogLevelFilter = .all
    @State private var sortOrder: SortOrder = .newest
    @State private var searchText = ""
    @State private var showingFilters = false
    @State private var showingClearConfirmation = false
    @State private var didCopyAll = false
    private let title: String
    private let refreshTimer = Timer.publish(every: 0.5, on: .main, in: .common).autoconnect()

    public init(title: String = "NetInspect") {
        self.title = title
    }

    private var filteredEvents: [NetInspectEvent] {
        let matchingEvents = events.filter { event in
            matchesType(event) && matchesStatus(event) && matchesLogLevel(event) && matchesSearch(event)
        }

        switch sortOrder {
        case .newest:
            return matchingEvents.sorted { $0.timestamp > $1.timestamp }
        case .oldest:
            return matchingEvents.sorted { $0.timestamp < $1.timestamp }
        }
    }

    private var requestCount: Int {
        events.reduce(into: 0) { count, event in
            if case .network = event { count += 1 }
        }
    }

    private var duplicateGroups: [DuplicateNetworkCall] {
        let networkEvents = events.compactMap { event -> NetworkEvent? in
            guard case .network(let network) = event else { return nil }
            return network
        }
        return NetworkEvent.duplicateGroups(in: networkEvents)
    }

    private var visibleDuplicateGroups: [DuplicateNetworkCall] {
        duplicateGroups.compactMap { group in
            let calls = group.calls.filter { network in
                let event = NetInspectEvent.network(network)
                return matchesStatus(event) && matchesSearch(event)
            }
            guard !calls.isEmpty else { return nil }
            let orderedCalls = calls.sorted {
                sortOrder == .newest ? $0.timestamp > $1.timestamp : $0.timestamp < $1.timestamp
            }
            return DuplicateNetworkCall(
                key: group.key,
                method: group.method,
                url: group.url,
                calls: orderedCalls
            )
        }
    }

    private var errorCount: Int {
        events.reduce(into: 0) { count, event in
            switch event {
            case .network(let network):
                if network.errorDescription != nil || (network.responseStatusCode ?? 0) >= 400 {
                    count += 1
                }
            case .console(let log):
                if log.level == .error || log.level == .fault { count += 1 }
            }
        }
    }

    private var activeFilterCount: Int {
        [filter != .all, statusFilter != .all, logLevelFilter != .all, sortOrder != .newest]
            .filter { $0 }
            .count
    }

    public var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                summaryHeader
                eventTypePicker

                if filter == .duplicates && visibleDuplicateGroups.isEmpty {
                    NetInspectEmptyState(
                        hasEvents: !events.isEmpty,
                        onClearFilters: clearFilters,
                        emptyTitle: "No duplicate APIs",
                        emptyMessage: "Repeated calls with the same method and URL will appear here."
                    )
                } else if filter == .duplicates {
                    List {
                        ForEach(visibleDuplicateGroups) { group in
                            Section {
                                ForEach(group.calls, id: \.id) { call in
                                    NavigationLink(destination: NetInspectEventDetailView(event: .network(call))) {
                                        NetInspectDuplicateCallRow(call: call)
                                    }
                                }
                            } header: {
                                NetInspectDuplicateGroupHeader(group: group)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                } else if filteredEvents.isEmpty {
                    NetInspectEmptyState(
                        hasEvents: !events.isEmpty,
                        onClearFilters: clearFilters
                    )
                } else {
                    List(filteredEvents, id: \.eventID) { event in
                        NavigationLink(destination: NetInspectEventDetailView(event: event)) {
                            NetInspectEventRow(event: event)
                        }
                    }
                    .listStyle(.plain)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Search URL, message, method…"
            )
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        showingClearConfirmation = true
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .disabled(events.isEmpty)
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 12) {
                        Button {
                            copyAllEvents()
                        } label: {
                            Image(systemName: didCopyAll ? "checkmark" : "doc.on.doc")
                        }
                        .accessibilityLabel(didCopyAll ? "Copied all events" : "Copy all events")
                        .disabled(events.isEmpty)
                        Button {
                            showingFilters = true
                        } label: {
                            ZStack(alignment: .topTrailing) {
                                Image(systemName: "line.3.horizontal.decrease.circle")
                                if activeFilterCount > 0 {
                                    Text("\(activeFilterCount)")
                                        .font(.system(size: 9, weight: .bold))
                                        .foregroundColor(.white)
                                        .frame(width: 15, height: 15)
                                        .background(Color.accentColor)
                                        .clipShape(Circle())
                                        .offset(x: 8, y: -8)
                                }
                            }
                            .accessibilityLabel("Filters")
                            .accessibilityValue(activeFilterCount == 0 ? "None" : "\(activeFilterCount) active")
                        }
                        Button("Done") { dismiss() }
                    }
                }
            }
            .confirmationDialog(
                "Clear captured events?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) {
                    NetInspect.clear()
                    events = []
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all network requests and console logs from the current buffer.")
            }
            .sheet(isPresented: $showingFilters) {
                NetInspectFilterSheet(
                    filter: $filter,
                    statusFilter: $statusFilter,
                    logLevelFilter: $logLevelFilter,
                    sortOrder: $sortOrder,
                    onReset: clearFilters
                )
            }
        }
        .onAppear(perform: reload)
        .onReceive(refreshTimer) { _ in reload() }
    }

    private var summaryHeader: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Live capture")
                        .font(.subheadline.weight(.semibold))
                    HStack(spacing: 5) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 7, height: 7)
                        Text("Recording events")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Text("\(filteredEvents.count) shown")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                NetInspectMetricCard(
                    title: "Events",
                    value: events.count.formatted(),
                    symbol: "waveform.path.ecg",
                    tint: .indigo
                )
                NetInspectMetricCard(
                    title: "Requests",
                    value: requestCount.formatted(),
                    symbol: "arrow.up.right",
                    tint: .blue
                )
                NetInspectMetricCard(
                    title: "Issues",
                    value: errorCount.formatted(),
                    symbol: "exclamationmark.triangle",
                    tint: errorCount > 0 ? .orange : .green
                )
            }
        }
        .padding(.horizontal)
        .padding(.top, 12)
        .padding(.bottom, 14)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private var eventTypePicker: some View {
        Picker("Event type", selection: $filter) {
            ForEach(Filter.allCases) { item in
                Text(item.title).tag(item)
            }
        }
        .pickerStyle(.segmented)
        .padding(.horizontal)
        .padding(.bottom, 10)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    private func matchesType(_ event: NetInspectEvent) -> Bool {
        switch filter {
        case .all: return true
        case .network:
            if case .network = event { return true }
            return false
        case .console:
            if case .console = event { return true }
            return false
        case .duplicates:
            guard case .network(let network) = event else { return false }
            return duplicateGroups.contains { group in group.calls.contains { $0.id == network.id } }
        }
    }

    private func matchesStatus(_ event: NetInspectEvent) -> Bool {
        guard statusFilter != .all else { return true }
        guard case .network(let network) = event else { return false }
        guard let status = network.responseStatusCode else {
            return statusFilter == .failed
        }

        switch statusFilter {
        case .all: return true
        case .success: return (200..<400).contains(status) && network.errorDescription == nil
        case .clientError: return (400..<500).contains(status)
        case .serverError: return status >= 500
        case .failed: return status >= 400 || network.errorDescription != nil
        }
    }

    private func matchesLogLevel(_ event: NetInspectEvent) -> Bool {
        guard logLevelFilter != .all else { return true }
        guard case .console(let log) = event else { return false }
        return log.level.rawValue == logLevelFilter.rawValue
    }

    private func matchesSearch(_ event: NetInspectEvent) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !query.isEmpty else { return true }
        return event.searchableText.localizedCaseInsensitiveContains(query)
    }

    private func clearFilters() {
        filter = .all
        statusFilter = .all
        logLevelFilter = .all
        sortOrder = .newest
        searchText = ""
    }

    private func reload() {
        guard let data = try? NetInspect.exportJSON() else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let envelope = try? decoder.decode(ExportEnvelope.self, from: data) else { return }
        events = envelope.events
    }

    private func copyAllEvents() {
        guard let data = try? NetInspect.exportJSON(),
              let value = String(data: data, encoding: .utf8) else { return }
        UIPasteboard.general.string = value
        didCopyAll = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            didCopyAll = false
        }
    }
}

private struct NetInspectMetricCard: View {
    let title: String
    let value: String
    let symbol: String
    let tint: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: symbol)
                .font(.caption.weight(.bold))
                .foregroundStyle(tint)
            Text(value)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NetInspectEmptyState: View {
    let hasEvents: Bool
    let onClearFilters: () -> Void
    var emptyTitle: String? = nil
    var emptyMessage: String? = nil

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: hasEvents ? "line.3.horizontal.decrease.circle" : "waveform.path.ecg")
                .font(.system(size: 38, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 72, height: 72)
                .background(Color.accentColor.opacity(0.12))
                .clipShape(Circle())
            Text(emptyTitle ?? (hasEvents ? "No matching events" : "No events yet"))
                .font(.headline)
            Text(emptyMessage ?? (hasEvents ? "Try a different search or reset your filters." : "Network calls and console logs will appear here."))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
            if hasEvents {
                Button("Reset filters", action: onClearFilters)
                    .buttonStyle(.borderedProminent)
                    .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

private struct NetInspectDuplicateGroupHeader: View {
    let group: DuplicateNetworkCall

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(group.method)
                    .font(.caption.weight(.bold))
                Spacer()
                Text("\(group.calls.count) calls")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
            Text(group.url)
                .font(.caption)
                .lineLimit(2)
                .textCase(nil)
        }
        .foregroundStyle(.primary)
        .padding(.vertical, 4)
    }
}

private struct NetInspectDuplicateCallRow: View {
    let call: NetworkEvent

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "clock.arrow.circlepath")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 3) {
                Text(call.timestamp.formatted(date: .abbreviated, time: .standard))
                    .font(.subheadline.monospacedDigit())
                HStack(spacing: 6) {
                    NetInspectStatusPill(network: call)
                    Text(call.durationText)
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct NetInspectFilterSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var filter: NetInspectMonitorView.Filter
    @Binding var statusFilter: NetInspectMonitorView.StatusFilter
    @Binding var logLevelFilter: NetInspectMonitorView.LogLevelFilter
    @Binding var sortOrder: NetInspectMonitorView.SortOrder
    let onReset: () -> Void

    var body: some View {
        NavigationView {
            Form {
                Section("Event type") {
                    Picker("Show", selection: $filter) {
                        ForEach(NetInspectMonitorView.Filter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                }
                Section {
                    Picker("Status", selection: $statusFilter) {
                        ForEach(NetInspectMonitorView.StatusFilter.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                    Picker("Log level", selection: $logLevelFilter) {
                        ForEach(NetInspectMonitorView.LogLevelFilter.allCases) { item in
                            Text(item.title).tag(item)
                        }
                    }
                } header: {
                    Text("Refine results")
                } footer: {
                    Text("Status applies to network requests. Log level applies to console events.")
                }
                Section("Sort") {
                    Picker("Order", selection: $sortOrder) {
                        ForEach(NetInspectMonitorView.SortOrder.allCases) { item in
                            Text(item.rawValue).tag(item)
                        }
                    }
                }
                Section {
                    Button("Reset all filters", action: onReset)
                        .foregroundStyle(.red)
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct NetInspectEventRow: View {
    let event: NetInspectEvent

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NetInspectEventIcon(event: event)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 7) {
                    switch event {
                    case .network(let network):
                        Text(network.method)
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.primary)
                        NetInspectStatusPill(network: network)
                    case .console(let log):
                        Text(log.level.rawValue.uppercased())
                            .font(.caption.weight(.bold))
                            .foregroundStyle(log.level.tint)
                        Text(log.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 4)
                    Text(event.timestamp.formatted(date: .numeric, time: .standard))
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                switch event {
                case .network(let network):
                    Text(network.displayURL)
                        .font(.subheadline)
                        .lineLimit(1)
                    HStack(spacing: 5) {
                        Image(systemName: "arrow.down.circle")
                        Text(network.durationText)
                        if let error = network.errorDescription, !error.isEmpty {
                            Text("·")
                            Text(error)
                                .lineLimit(1)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                case .console(let log):
                    Text(log.message)
                        .font(.subheadline)
                        .lineLimit(2)
                    Text(log.thread)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .padding(.vertical, 7)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct NetInspectEventIcon: View {
    let event: NetInspectEvent

    var body: some View {
        let tint = event.tint
        return Image(systemName: event.symbolName)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(tint)
            .frame(width: 34, height: 34)
            .background(tint.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct NetInspectStatusPill: View {
    let network: NetworkEvent
    let search: NetInspectDetailSearch?

    init(network: NetworkEvent, search: NetInspectDetailSearch? = nil) {
        self.network = network
        self.search = search
    }

    @ViewBuilder
    private var statusText: some View {
        if let search {
            search.highlightedText(network.statusLabel, field: .status)
        } else {
            Text(network.statusLabel)
        }
    }

    var body: some View {
        let color = network.statusTint
        return statusText
            .font(.caption2.weight(.semibold))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }
}

private struct NetInspectCopyButton: View {
    let value: String
    let label: String
    let systemImage: String
    @State private var didCopy = false

    init(value: String, label: String = "Copy", systemImage: String = "doc.on.doc") {
        self.value = value
        self.label = label
        self.systemImage = systemImage
    }

    var body: some View {
        Button {
            UIPasteboard.general.string = value
            didCopy = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                didCopy = false
            }
        } label: {
            Image(systemName: didCopy ? "checkmark" : systemImage)
        }
        .font(.subheadline)
        .buttonStyle(.bordered)
        .controlSize(.small)
        .accessibilityLabel(didCopy ? "Copied" : "Copy \(label.lowercased())")
    }
}

private enum NetInspectDetailField: Hashable {
    case method
    case date
    case url
    case status
    case duration
    case responseSize
    case error
    case requestHeaderKey(String)
    case requestHeaderValue(String)
    case responseHeaderKey(String)
    case responseHeaderValue(String)
    case requestBody
    case responseBody
    case level
    case category
    case message
    case thread
    case metadataKey(String)
    case metadataValue(String)
    case rawJSON
}

private struct NetInspectDetailSearchItem {
    let field: NetInspectDetailField
    let value: String
}

private struct NetInspectDetailSearch {
    let query: String
    let currentMatchIndex: Int
    let items: [NetInspectDetailSearchItem]

    var matchCount: Int {
        items.reduce(into: 0) { count, item in
            count += matchingRanges(in: item.value).count
        }
    }

    func highlightedText(_ value: String, field: NetInspectDetailField) -> Text {
        Text(highlightedAttributedString(value, field: field))
    }

    private func highlightedAttributedString(_ value: String, field: NetInspectDetailField) -> AttributedString {
        var attributed = AttributedString(value)
        guard !query.isEmpty else { return attributed }

        let ranges = matchingRanges(in: value)
        let matchOffset = matchOffset(for: field)
        for (localIndex, range) in ranges.enumerated() {
            let startOffset = value.distance(from: value.startIndex, to: range.lowerBound)
            let endOffset = value.distance(from: value.startIndex, to: range.upperBound)
            let attributedStart = attributed.index(attributed.startIndex, offsetByCharacters: startOffset)
            let attributedEnd = attributed.index(attributed.startIndex, offsetByCharacters: endOffset)
            let isCurrentMatch = matchOffset + localIndex == currentMatchIndex

            attributed[attributedStart..<attributedEnd].backgroundColor = isCurrentMatch ? .orange : .yellow
            attributed[attributedStart..<attributedEnd].foregroundColor = .black
        }
        return attributed
    }

    private func matchOffset(for field: NetInspectDetailField) -> Int {
        var offset = 0
        for item in items {
            if item.field == field { return offset }
            offset += matchingRanges(in: item.value).count
        }
        return offset
    }

    private func matchingRanges(in value: String) -> [Range<String.Index>] {
        guard !query.isEmpty else { return [] }

        var ranges: [Range<String.Index>] = []
        var searchStart = value.startIndex
        while searchStart < value.endIndex,
              let range = value.range(
                  of: query,
                  options: [.caseInsensitive, .diacriticInsensitive],
                  range: searchStart..<value.endIndex
              ) {
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }
}

private struct NetInspectEventDetailView: View {
    let event: NetInspectEvent
    @State private var showingRawJSON = false
    @State private var detailSearchText = ""
    @State private var currentMatchIndex = 0

    private var detailSearch: NetInspectDetailSearch {
        NetInspectDetailSearch(
            query: detailSearchText,
            currentMatchIndex: currentMatchIndex,
            items: detailSearchItems
        )
    }

    private var detailSearchItems: [NetInspectDetailSearchItem] {
        var items: [NetInspectDetailSearchItem] = []

        switch event {
        case .network(let network):
            items.append(.init(field: .method, value: network.method))
            items.append(.init(field: .date, value: network.timestamp.formatted(date: .abbreviated, time: .standard)))
            items.append(.init(field: .url, value: network.url))
            items.append(.init(field: .status, value: network.statusLabel))
            items.append(.init(field: .duration, value: network.durationText))
            items.append(.init(field: .responseSize, value: network.responseSizeText))

            if let error = network.errorDescription, !error.isEmpty {
                items.append(.init(field: .error, value: error))
            }
            items.append(contentsOf: searchItems(for: network.requestHeaders, keyField: NetInspectDetailField.requestHeaderKey, valueField: NetInspectDetailField.requestHeaderValue))
            items.append(contentsOf: searchItems(for: network.responseHeaders, keyField: NetInspectDetailField.responseHeaderKey, valueField: NetInspectDetailField.responseHeaderValue))

            if let body = network.requestBody {
                items.append(.init(field: .requestBody, value: formattedBodyValue(body)))
            }
            if let body = network.responseBody {
                items.append(.init(field: .responseBody, value: formattedBodyValue(body)))
            }
        case .console(let log):
            items.append(.init(field: .level, value: log.level.rawValue.capitalized))
            items.append(.init(field: .category, value: log.category))
            items.append(.init(field: .message, value: log.message))
            items.append(.init(field: .thread, value: log.thread))
            items.append(contentsOf: searchItems(for: log.metadata, keyField: NetInspectDetailField.metadataKey, valueField: NetInspectDetailField.metadataValue))
        }

        items.append(.init(field: .rawJSON, value: renderedJSON))
        return items
    }

    private func searchItems(
        for values: [String: String],
        keyField: (String) -> NetInspectDetailField,
        valueField: (String) -> NetInspectDetailField
    ) -> [NetInspectDetailSearchItem] {
        values.keys.sorted().flatMap { key in
            [
                .init(field: keyField(key), value: key),
                .init(field: valueField(key), value: values[key] ?? "")
            ]
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                detailHeader(search: detailSearch)
                detailContent(search: detailSearch)
                DisclosureGroup("Raw event JSON", isExpanded: $showingRawJSON) {
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Spacer()
                            NetInspectCopyButton(value: renderedJSON, label: "Copy JSON")
                        }
                        detailSearch.highlightedText(renderedJSON, field: .rawJSON)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.top, 10)
                }
                .padding()
                .background(Color(uiColor: .secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Event details")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(
            text: $detailSearchText,
            placement: .navigationBarDrawer(displayMode: .always),
            prompt: "Search in detail"
        )
        .onChange(of: detailSearchText) { _ in
            currentMatchIndex = 0
        }
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if !detailSearchText.isEmpty {
                    HStack(spacing: 8) {
                        Text(detailSearch.matchCount == 0 ? "0/0" : "\(min(currentMatchIndex + 1, detailSearch.matchCount))/\(detailSearch.matchCount)")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                        Button(action: nextMatch) {
                            Image(systemName: "chevron.down")
                        }
                        .disabled(detailSearch.matchCount == 0)
                        .accessibilityLabel("Next match")
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func detailHeader(search: NetInspectDetailSearch) -> some View {
        switch event {
        case .network(let network):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NetInspectEventIcon(event: event)
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            search.highlightedText(network.method, field: .method)
                                .font(.title3.weight(.bold))
                            NetInspectStatusPill(network: network, search: search)
                        }
                        search.highlightedText(network.timestamp.formatted(date: .abbreviated, time: .standard), field: .date)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    HStack(spacing: 6) {
                        NetInspectCopyButton(value: renderedJSON, label: "Copy event")
                        NetInspectCopyButton(value: curlCommand, label: "Copy cURL", systemImage: "terminal")
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    search.highlightedText(network.url, field: .url)
                        .font(.system(.subheadline, design: .monospaced))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    NetInspectCopyButton(value: network.url, label: "Copy URL")
                }
            }
        case .console(let log):
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    NetInspectEventIcon(event: event)
                    VStack(alignment: .leading, spacing: 3) {
                        search.highlightedText(log.level.rawValue.capitalized, field: .level)
                            .font(.title3.weight(.bold))
                            .foregroundStyle(log.level.tint)
                        search.highlightedText(log.category, field: .category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    NetInspectCopyButton(value: renderedJSON, label: "Copy event")
                }
                HStack(alignment: .top, spacing: 8) {
                    search.highlightedText(log.message, field: .message)
                        .font(.body)
                        .textSelection(.enabled)
                    Spacer(minLength: 0)
                    NetInspectCopyButton(value: log.message, label: "Copy message")
                }
            }
        }
    }

    @ViewBuilder
    private func detailContent(search: NetInspectDetailSearch) -> some View {
        switch event {
        case .network(let network):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    NetInspectDetailStat(title: "Status", value: network.statusLabel, search: search, field: .status)
                    NetInspectDetailStat(title: "Duration", value: network.durationText, search: search, field: .duration)
                    NetInspectDetailStat(title: "Response", value: network.responseSizeText, search: search, field: .responseSize)
                }
                if let error = network.errorDescription, !error.isEmpty {
                    NetInspectDetailSection(
                        title: "Error",
                        symbol: "exclamationmark.triangle",
                        tint: .red,
                        copyText: error
                    ) {
                        search.highlightedText(error, field: .error).textSelection(.enabled)
                    }
                }
                if !network.requestHeaders.isEmpty {
                    NetInspectDetailSection(
                        title: "Request headers",
                        symbol: "arrow.up",
                        tint: .blue,
                        copyText: formattedKeyValueText(network.requestHeaders)
                    ) {
                        NetInspectKeyValueList(values: network.requestHeaders, search: search, fieldKind: .requestHeaders)
                    }
                }
                if !network.responseHeaders.isEmpty {
                    NetInspectDetailSection(
                        title: "Response headers",
                        symbol: "arrow.down",
                        tint: .green,
                        copyText: formattedKeyValueText(network.responseHeaders)
                    ) {
                        NetInspectKeyValueList(values: network.responseHeaders, search: search, fieldKind: .responseHeaders)
                    }
                }
                if let body = network.requestBody {
                    NetInspectDetailSection(
                        title: "Request body",
                        symbol: "doc.text",
                        tint: .orange,
                        copyText: formattedBodyValue(body)
                    ) {
                        NetInspectBodyView(capturedBody: body, search: search, field: .requestBody)
                    }
                }
                if let body = network.responseBody {
                    NetInspectDetailSection(
                        title: "Response body",
                        symbol: "doc.text",
                        tint: .indigo,
                        copyText: formattedBodyValue(body)
                    ) {
                        NetInspectBodyView(capturedBody: body, search: search, field: .responseBody)
                    }
                }
            }
        case .console(let log):
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    NetInspectDetailStat(title: "Thread", value: log.thread)
                    NetInspectDetailStat(title: "Metadata", value: log.metadata.count.formatted())
                }
                if !log.metadata.isEmpty {
                    NetInspectDetailSection(
                        title: "Metadata",
                        symbol: "tag",
                        tint: .purple,
                        copyText: formattedKeyValueText(log.metadata)
                    ) {
                        NetInspectKeyValueList(values: log.metadata, search: search, fieldKind: .metadata)
                    }
                }
            }
        }
    }

    private func nextMatch() {
        guard detailSearch.matchCount > 0 else { return }
        currentMatchIndex = (currentMatchIndex + 1) % detailSearch.matchCount
    }

    private var renderedJSON: String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(event), let string = String(data: data, encoding: .utf8) else {
            return "Unable to encode event"
        }
        return string
    }

    private var curlCommand: String {
        guard case .network(let network) = event else { return "" }

        var parts = [
            "curl",
            "--request \(shellEscape(network.method))",
            shellEscape(network.url)
        ]

        for key in network.requestHeaders.keys.sorted() {
            let value = network.requestHeaders[key] ?? ""
            parts.append("--header \(shellEscape("\(key): \(value)"))")
        }

        if let body = network.requestBody {
            switch body.encoding {
            case .utf8:
                parts.append("--data-raw \(shellEscape(body.value))")
            case .base64:
                parts.append("--data-binary \"$(printf '%s' \(shellEscape(body.value)) | base64 --decode)\"")
            }
        }

        return parts.joined(separator: " ")
    }
}

private struct NetInspectDetailStat: View {
    let title: String
    let value: String
    let search: NetInspectDetailSearch?
    let field: NetInspectDetailField?

    init(
        title: String,
        value: String,
        search: NetInspectDetailSearch? = nil,
        field: NetInspectDetailField? = nil
    ) {
        self.title = title
        self.value = value
        self.search = search
        self.field = field
    }

    @ViewBuilder
    private var valueText: some View {
        if let search, let field {
            search.highlightedText(value, field: field)
        } else {
            Text(value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            valueText
                .font(.subheadline.weight(.semibold))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(11)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct NetInspectDetailSection<Content: View>: View {
    let title: String
    let symbol: String
    let tint: Color
    let copyText: String?
    @State private var isExpanded = true
    @ViewBuilder let content: () -> Content

    init(
        title: String,
        symbol: String,
        tint: Color,
        copyText: String? = nil,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.symbol = symbol
        self.tint = tint
        self.copyText = copyText
        self.content = content
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            content()
                .padding(.top, 10)
        } label: {
            HStack {
                Label(title, systemImage: symbol)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(tint)
                Spacer()
                if let copyText {
                    NetInspectCopyButton(value: copyText)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct NetInspectKeyValueList: View {
    enum FieldKind {
        case requestHeaders
        case responseHeaders
        case metadata
    }

    let values: [String: String]
    let search: NetInspectDetailSearch?
    let fieldKind: FieldKind?

    init(
        values: [String: String],
        search: NetInspectDetailSearch? = nil,
        fieldKind: FieldKind? = nil
    ) {
        self.values = values
        self.search = search
        self.fieldKind = fieldKind
    }

    private func keyField(_ key: String) -> NetInspectDetailField? {
        switch fieldKind {
        case .requestHeaders: return .requestHeaderKey(key)
        case .responseHeaders: return .responseHeaderKey(key)
        case .metadata: return .metadataKey(key)
        case nil: return nil
        }
    }

    private func valueField(_ key: String) -> NetInspectDetailField? {
        switch fieldKind {
        case .requestHeaders: return .requestHeaderValue(key)
        case .responseHeaders: return .responseHeaderValue(key)
        case .metadata: return .metadataValue(key)
        case nil: return nil
        }
    }

    @ViewBuilder
    private func highlightedText(_ value: String, field: NetInspectDetailField?) -> some View {
        if let search, let field {
            search.highlightedText(value, field: field)
        } else {
            Text(value)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(values.keys.sorted(), id: \.self) { key in
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .top, spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            highlightedText(key, field: keyField(key))
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            highlightedText(values[key] ?? "", field: valueField(key))
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        Spacer(minLength: 0)
                        NetInspectCopyButton(value: "\(key): \(values[key] ?? "")")
                    }
                }
                if key != values.keys.sorted().last {
                    Divider()
                }
            }
        }
    }
}

private struct NetInspectBodyView: View {
    let capturedBody: CapturedBody
    let search: NetInspectDetailSearch?
    let field: NetInspectDetailField?

    init(
        capturedBody: CapturedBody,
        search: NetInspectDetailSearch? = nil,
        field: NetInspectDetailField? = nil
    ) {
        self.capturedBody = capturedBody
        self.search = search
        self.field = field
    }

    var body: some View {
        let displayValue = formattedBodyValue(capturedBody)
        let isJSON = displayValue != capturedBody.value

        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if capturedBody.isTruncated {
                    Label("Body truncated", systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
                if isJSON {
                    Label("JSON", systemImage: "curlybraces")
                        .font(.caption)
                        .foregroundStyle(.indigo)
                }
                Spacer()
                NetInspectCopyButton(value: displayValue, label: "Copy body")
            }
            if let search, let field {
                search.highlightedText(displayValue, field: field)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text(displayValue)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

private func formattedKeyValueText(_ values: [String: String]) -> String {
    values.keys.sorted().map { key in
        "\(key): \(values[key] ?? "")"
    }.joined(separator: "\n")
}

private func shellEscape(_ value: String) -> String {
    "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
}

private func formattedBodyValue(_ body: CapturedBody) -> String {
    guard body.encoding == .utf8,
          let data = body.value.data(using: .utf8),
          let object = try? JSONSerialization.jsonObject(with: data),
          let prettyData = try? JSONSerialization.data(
              withJSONObject: object,
              options: [.prettyPrinted, .sortedKeys, .fragmentsAllowed]
          ),
          let prettyValue = String(data: prettyData, encoding: .utf8) else {
        return body.value
    }
    return prettyValue
}

private extension NetInspectEvent {
    var eventID: UUID {
        switch self {
        case .network(let event): return event.id
        case .console(let event): return event.id
        }
    }

    var searchableText: String {
        switch self {
        case .network(let network):
            let status = network.responseStatusCode.map(String.init) ?? ""
            let requestHeaders = network.requestHeaders.map { "\($0.key) \($0.value)" }.joined(separator: " ")
            let responseHeaders = network.responseHeaders.map { "\($0.key) \($0.value)" }.joined(separator: " ")
            let requestBody = network.requestBody?.value ?? ""
            let responseBody = network.responseBody?.value ?? ""
            return "\(network.url) \(network.method) \(status) \(network.errorDescription ?? "") \(requestHeaders) \(responseHeaders) \(requestBody) \(responseBody)"
        case .console(let log):
            let metadata = log.metadata.map { "\($0.key) \($0.value)" }.joined(separator: " ")
            return "\(log.level.rawValue) \(log.category) \(log.message) \(log.thread) \(metadata)"
        }
    }

    var symbolName: String {
        switch self {
        case .network: return "arrow.up.right"
        case .console(let log):
            switch log.level {
            case .trace, .debug: return "ladybug"
            case .info: return "info.circle"
            case .warning: return "exclamationmark.triangle"
            case .error, .fault: return "xmark.octagon"
            }
        }
    }

    var tint: Color {
        switch self {
        case .network(let network): return network.statusTint
        case .console(let log): return log.level.tint
        }
    }
}

private extension NetworkEvent {
    var displayURL: String {
        guard let parsedURL = URL(string: url), let host = parsedURL.host else { return url }
        let path = parsedURL.path.isEmpty ? "/" : parsedURL.path
        return "\(host)\(path)"
    }

    var statusLabel: String {
        if let status = responseStatusCode { return String(status) }
        return errorDescription == nil ? "—" : "Error"
    }

    var statusTint: Color {
        guard let status = responseStatusCode else {
            return errorDescription == nil ? .secondary : .red
        }
        if status >= 500 { return .red }
        if status >= 400 { return .orange }
        if (200..<400).contains(status) && errorDescription == nil { return .green }
        return .secondary
    }

    var durationText: String {
        guard let durationMilliseconds else { return "Duration unavailable" }
        if durationMilliseconds >= 1000 {
            return String(format: "%.2f s", durationMilliseconds / 1000)
        }
        return "\(Int(durationMilliseconds.rounded())) ms"
    }

    var responseSizeText: String {
        guard let responseBytes else { return "—" }
        return ByteCountFormatter.string(fromByteCount: Int64(responseBytes), countStyle: .file)
    }
}

private extension LogLevel {
    var tint: Color {
        switch self {
        case .trace, .debug: return .secondary
        case .info: return .blue
        case .warning: return .orange
        case .error, .fault: return .red
        }
    }
}

private extension UIWindow {
    var topMostViewController: UIViewController? {
        guard let rootViewController else { return nil }
        return rootViewController.topMostViewController
    }
}

private extension UIViewController {
    var topMostViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostViewController
        }
        if let navigation = self as? UINavigationController {
            return navigation.visibleViewController?.topMostViewController ?? navigation
        }
        if let tab = self as? UITabBarController {
            return tab.selectedViewController?.topMostViewController ?? tab
        }
        return self
    }
}
#endif
