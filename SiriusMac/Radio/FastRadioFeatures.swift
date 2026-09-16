import AppKit
import Foundation
import Observation
import SiriusXMClient
import SwiftUI

/// Remembers confirmed channel transitions for a true A/B return action.
/// Selection and failed tune attempts never alter this state.
struct ChannelReturnTracker: Equatable {
    private(set) var current: LiveChannelID?
    private(set) var previous: LiveChannelID?

    mutating func observeConfirmed(_ channelID: LiveChannelID) {
        guard current != channelID else { return }
        previous = current
        current = channelID
    }

    func candidate(among availableIDs: [LiveChannelID]) -> LiveChannelID? {
        guard let previous, availableIDs.contains(previous) else { return nil }
        return previous
    }

    mutating func reset() {
        current = nil
        previous = nil
    }
}

struct ActiveListeningHistoryObservation: Equatable {
    let channel: LibraryChannelSnapshot
    let program: LiveNowProgram
    let beganAt: Date

    var identity: String {
        ListeningHistoryRecord.key(channelID: channel.id, program: program)
    }
}

/// A local countdown with no network or playback authority of its own.
@MainActor
@Observable
final class SleepTimerController {
    typealias Sleeper = @Sendable (TimeInterval) async throws -> Void

    private let now: @Sendable () -> Date
    private let sleep: Sleeper
    private var task: Task<Void, Never>?
    private var generation = 0
    private var expirationHandler: (@MainActor () -> Void)?

    private(set) var deadline: Date?
    private(set) var remainingSeconds: TimeInterval = 0

    init(
        now: @escaping @Sendable () -> Date = Date.init,
        sleep: @escaping Sleeper = { seconds in
            try await Task.sleep(for: .seconds(seconds))
        }
    ) {
        self.now = now
        self.sleep = sleep
    }

    var isActive: Bool { deadline != nil }

    var statusText: String {
        guard isActive else { return "Off" }
        let totalMinutes = max(1, Int(ceil(remainingSeconds / 60)))
        return totalMinutes == 1 ? "1 minute remaining" : "\(totalMinutes) minutes remaining"
    }

    func setExpirationHandler(_ handler: @escaping @MainActor () -> Void) {
        expirationHandler = handler
    }

    func start(minutes: Int) {
        start(duration: TimeInterval(max(1, minutes) * 60))
    }

    func start(duration: TimeInterval) {
        generation &+= 1
        task?.cancel()
        let expected = generation
        let target = now().addingTimeInterval(max(0, duration))
        deadline = target
        remainingSeconds = max(0, target.timeIntervalSince(now()))
        task = Task { @MainActor [weak self] in
            guard let self else { return }
            while !Task.isCancelled, self.generation == expected {
                let remaining = target.timeIntervalSince(self.now())
                self.remainingSeconds = max(0, remaining)
                if remaining <= 0 {
                    self.deadline = nil
                    self.task = nil
                    self.expirationHandler?()
                    return
                }
                do {
                    try await self.sleep(min(1, remaining))
                } catch {
                    return
                }
            }
        }
    }

    func cancel() {
        generation &+= 1
        task?.cancel()
        task = nil
        deadline = nil
        remainingSeconds = 0
    }
}

@MainActor
enum TunePaletteSearch {
    static func results(
        channels: [LiveChannel],
        favoriteIDs: [LiveChannelID],
        query: String,
        liveNow: LiveNowLibraryProjection
    ) -> [LiveChannel] {
        let favoriteRanks = Dictionary(uniqueKeysWithValues: favoriteIDs.enumerated().map { ($0.element, $0.offset) })
        let ordered = channels.sorted { left, right in
            switch (favoriteRanks[left.id], favoriteRanks[right.id]) {
            case let (leftRank?, rightRank?): return leftRank < rightRank
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil):
                if left.displayNumber != right.displayNumber {
                    return (left.displayNumber ?? .max) < (right.displayNumber ?? .max)
                }
                return (left.name ?? left.id.rawValue).localizedStandardCompare(right.name ?? right.id.rawValue) == .orderedAscending
            }
        }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return ordered }
        return ordered.filter { channel in
            liveNow.matches(
                LibraryChannelItem(channel: channel, availability: .available),
                query: trimmed
            )
        }
    }
}

struct TunePaletteView: View {
    let controller: ListeningSessionController
    @Environment(\.dismissWindow) private var dismissWindow
    @State private var query = ""
    @State private var selection: LiveChannelID?
    @FocusState private var searchIsFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Channel, number, category, show, or artist", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($searchIsFocused)
                    .onSubmit { tuneSelected() }
            }
            .padding(14)

            Divider()

            if results.isEmpty {
                ContentUnavailableView.search(text: query)
            } else {
                List(results, id: \.id, selection: $selection) { channel in
                    TunePaletteRow(
                        channel: channel,
                        program: liveNow.program(for: channel.id),
                        isFavorite: controller.libraryStore.isFavorite(channel.id)
                    )
                    .tag(channel.id)
                    .contentShape(.rect)
                    .onTapGesture(count: 2) { tune(channel.id) }
                }
                .listStyle(.inset)
                .onKeyPress(.return) { tuneSelected(); return .handled }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .background {
            TunePaletteKeyRouter(
                moveUp: { moveSelection(by: -1) },
                moveDown: { moveSelection(by: 1) },
                submit: tuneSelected,
                cancel: { dismissWindow(id: ProductIdentity.SceneID.tune) }
            )
            .frame(width: 0, height: 0)
        }
        .onAppear {
            selection = results.first?.id
            focusSearch()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { notification in
            guard let window = notification.object as? NSWindow,
                  window.title == "Tune"
            else { return }
            focusSearch()
        }
        .onChange(of: query) { _, _ in selection = results.first?.id }
        .accessibilityIdentifier("tune-palette")
    }

    private var liveNow: LiveNowLibraryProjection {
        LiveNowLibraryProjection(monitor: controller.listeningModel.liveNow)
    }

    private var results: [LiveChannel] {
        TunePaletteSearch.results(
            channels: controller.listeningModel.state.snapshot?.channels ?? [],
            favoriteIDs: controller.libraryStore.favoriteChannelIDs,
            query: query,
            liveNow: liveNow
        )
    }

    private func tuneSelected() {
        guard let selection else { return }
        tune(selection)
    }

    private func moveSelection(by offset: Int) {
        guard !results.isEmpty else {
            selection = nil
            return
        }
        guard let selection,
              let currentIndex = results.firstIndex(where: { $0.id == selection })
        else {
            self.selection = results.first?.id
            return
        }
        let destination = min(max(currentIndex + offset, results.startIndex), results.index(before: results.endIndex))
        self.selection = results[destination].id
    }

    private func focusSearch() {
        Task { @MainActor in
            // WindowGroup scenes are retained after dismissWindow. Waiting for
            // the key-window transition makes focus reliable on every reopen.
            await Task.yield()
            searchIsFocused = true
        }
    }

    private func tune(_ channelID: LiveChannelID) {
        guard controller.tune(channelID: channelID, originIDs: results.map(\.id)) != nil else { return }
        dismissWindow(id: ProductIdentity.SceneID.tune)
    }
}

/// Routes navigation keys before the focused NSTextField consumes them for
/// caret movement. The monitor is restricted to this palette's key window and
/// is removed with the hosting view, so it cannot become a global shortcut.
private struct TunePaletteKeyRouter: NSViewRepresentable {
    let moveUp: @MainActor () -> Void
    let moveDown: @MainActor () -> Void
    let submit: @MainActor () -> Void
    let cancel: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(moveUp: moveUp, moveDown: moveDown, submit: submit, cancel: cancel)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.hostingView = view
        context.coordinator.installMonitor()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.moveUp = moveUp
        context.coordinator.moveDown = moveDown
        context.coordinator.submit = submit
        context.coordinator.cancel = cancel
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.removeMonitor()
    }

    @MainActor
    final class Coordinator {
        weak var hostingView: NSView?
        var moveUp: @MainActor () -> Void
        var moveDown: @MainActor () -> Void
        var submit: @MainActor () -> Void
        var cancel: @MainActor () -> Void
        private var monitor: Any?

        init(
            moveUp: @escaping @MainActor () -> Void,
            moveDown: @escaping @MainActor () -> Void,
            submit: @escaping @MainActor () -> Void,
            cancel: @escaping @MainActor () -> Void
        ) {
            self.moveUp = moveUp
            self.moveDown = moveDown
            self.submit = submit
            self.cancel = cancel
        }

        func installMonitor() {
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                guard let self,
                      let window = self.hostingView?.window,
                      event.window === window,
                      window.isKeyWindow
                else { return event }

                switch event.keyCode {
                case 126:
                    self.moveUp()
                case 125:
                    self.moveDown()
                case 36, 76:
                    self.submit()
                case 53:
                    self.cancel()
                default:
                    return event
                }
                return nil
            }
        }

        func removeMonitor() {
            guard let monitor else { return }
            NSEvent.removeMonitor(monitor)
            self.monitor = nil
        }

    }
}

private struct TunePaletteRow: View {
    let channel: LiveChannel
    let program: LiveNowProgram?
    let isFavorite: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(channel.displayNumber.map(String.init) ?? "—")
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .frame(width: 40, alignment: .trailing)
            VStack(alignment: .leading, spacing: 3) {
                Text(channel.name ?? "Unnamed channel")
                    .fontWeight(.medium)
                if let program {
                    Text([program.title, program.artist].compactMap { $0 }.joined(separator: " — "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                } else if let category = channel.category {
                    Text(category).font(.caption).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if isFavorite {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Favorite")
            }
        }
        .padding(.vertical, 4)
    }
}

struct ListeningHistoryView: View {
    let controller: ListeningSessionController
    @State private var confirmsClear = false

    var body: some View {
        Group {
            if controller.libraryStore.listeningHistory.isEmpty {
                ContentUnavailableView(
                    "No Listening History",
                    systemImage: "clock.arrow.circlepath",
                    description: Text("Programs appear here after they play with current metadata.")
                )
            } else {
                List(controller.libraryStore.listeningHistory) { entry in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(entry.title).fontWeight(.medium)
                            Spacer()
                            Text(entry.lastHeardAt, style: .relative)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text(historyDetail(entry))
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 5)
                    .contextMenu {
                        Button("Copy") { copy(entry.copyText) }
                    }
                }
            }
        }
        .frame(minWidth: 560, minHeight: 440)
        .toolbar {
            ToolbarItem {
                Button("Copy Latest", systemImage: "doc.on.doc") {
                    controller.copyWhatDidIJustHear()
                }
                .disabled(controller.libraryStore.listeningHistory.isEmpty)
            }
            ToolbarItem {
                Button("Clear History", systemImage: "trash", role: .destructive) {
                    confirmsClear = true
                }
                .disabled(controller.libraryStore.listeningHistory.isEmpty)
            }
        }
        .confirmationDialog("Clear listening history?", isPresented: $confirmsClear) {
            Button("Clear History", role: .destructive) { controller.libraryStore.clearListeningHistory() }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func historyDetail(_ entry: ListeningHistoryEntry) -> String {
        var parts: [String] = []
        if let artist = entry.artist { parts.append(artist) }
        parts.append(entry.channel.name ?? entry.channel.displayNumber.map { "Channel \($0)" } ?? "Saved channel")
        if entry.heardDuration >= 1 {
            parts.append(Duration.seconds(entry.heardDuration).formatted(.units(allowed: [.minutes, .seconds], width: .abbreviated)))
        }
        return parts.joined(separator: " · ")
    }

    private func copy(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}

struct MenuBarTunerView: View {
    let controller: ListeningSessionController
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let channel = confirmedChannel {
            Text(channel.name ?? "Current channel")
            if let program = controller.listeningModel.metadataPresentation.currentLiveProgram {
                Text([program.title, program.artist].compactMap { $0 }.joined(separator: " — "))
            }
            Divider()
        }

        Button(controller.commandAvailability.playPauseTitle) {
            _ = controller.toggleConfirmedPlayback()
        }
        .disabled(!controller.commandAvailability.playPause)

        Button("Return to Previous Channel") {
            _ = controller.returnToPreviousChannel()
        }
        .disabled(!controller.canReturnToPreviousChannel)

        Menu("Favorites") {
            if controller.libraryStore.favorites.isEmpty {
                Text("No favorites yet")
            } else {
                ForEach(controller.libraryStore.favorites, id: \.id) { favorite in
                    Button(favorite.name ?? favorite.displayNumber.map { "Channel \($0)" } ?? "Saved channel") {
                        _ = controller.tune(channelID: favorite.id, originIDs: controller.libraryStore.favoriteChannelIDs)
                    }
                }
            }
        }

        SleepTimerMenu(controller: controller)

        Divider()

        Button("Tune…") { openWindow(id: ProductIdentity.SceneID.tune) }
        Button("Show Library") {
            _ = controller.requestLibraryOpen()
            openWindow(id: ProductIdentity.SceneID.library)
        }
        Button("Listening History") { openWindow(id: ProductIdentity.SceneID.history) }
    }

    private var confirmedChannel: LiveChannel? {
        guard let id = controller.listeningModel.confirmedChannelID else { return nil }
        return controller.listeningModel.state.snapshot?.channels.first { $0.id == id }
    }
}

struct SleepTimerMenu: View {
    let controller: ListeningSessionController

    var body: some View {
        Menu(controller.sleepTimer.isActive ? "Sleep Timer: \(controller.sleepTimer.statusText)" : "Sleep Timer") {
            ForEach([15, 30, 45, 60], id: \.self) { minutes in
                Button("\(minutes) Minutes") { controller.sleepTimer.start(minutes: minutes) }
            }
            if controller.sleepTimer.isActive {
                Divider()
                Button("Cancel Sleep Timer") { controller.sleepTimer.cancel() }
            }
        }
    }
}
