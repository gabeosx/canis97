@preconcurrency import AppKit
import SwiftUI

/// A narrow AppKit escape hatch for native List double-click activation. The
/// table keeps ownership of selection; this bridge only observes its double
/// action after AppKit has identified a clicked row.
struct NativeListDoubleActionBridge: NSViewRepresentable {
    let onDoubleAction: @MainActor (Int) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onDoubleAction: onDoubleAction)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { context.coordinator.install(from: view) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        context.coordinator.onDoubleAction = onDoubleAction
        DispatchQueue.main.async { context.coordinator.install(from: view) }
    }

    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onDoubleAction: @MainActor (Int) -> Void
        private weak var tableView: NSTableView?
        private weak var previousTarget: AnyObject?
        private var previousDoubleAction: Selector?

        init(onDoubleAction: @escaping @MainActor (Int) -> Void) {
            self.onDoubleAction = onDoubleAction
        }

        func install(from view: NSView) {
            guard let tableView = findTableView(startingAt: view) else { return }
            guard self.tableView !== tableView else { return }

            uninstall()
            self.tableView = tableView
            previousTarget = tableView.target as AnyObject?
            previousDoubleAction = tableView.doubleAction
            tableView.target = self
            tableView.doubleAction = #selector(handleDoubleAction(_:))
        }

        @objc private func handleDoubleAction(_ sender: NSTableView) {
            let clickedRow = sender.clickedRow
            guard clickedRow >= 0 else { return }

            if sender.selectedRow != clickedRow {
                sender.selectRowIndexes(IndexSet(integer: clickedRow), byExtendingSelection: false)
            }
            onDoubleAction(clickedRow)
        }

        func uninstall() {
            guard let tableView else { return }
            if tableView.target === self {
                tableView.target = previousTarget
                tableView.doubleAction = previousDoubleAction
            }
            self.tableView = nil
            previousTarget = nil
            previousDoubleAction = nil
        }

        private func findTableView(startingAt view: NSView) -> NSTableView? {
            var current: NSView? = view
            while let candidate = current {
                if let tableView = findTableView(in: candidate) { return tableView }
                current = candidate.superview
            }
            return nil
        }

        private func findTableView(in view: NSView) -> NSTableView? {
            if let tableView = view as? NSTableView { return tableView }
            for subview in view.subviews {
                if let tableView = findTableView(in: subview) { return tableView }
            }
            return nil
        }
    }
}
