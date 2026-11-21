//
//  AppSystemTrays.swift
//  NucleantUI
//
//  The app's `SystemTray` items, kept up to date. The app's body is read
//  for them under observation: when anything it read for them changes — a
//  model the label or the menu rows were made from, an `isInserted`
//  binding — it is read again, and each item shows what it says now. In the
//  `.window` style a click toggles the item's window, made the first time
//  and kept, views and state, from one click to the next. Phones and
//  tablets have no system tray, and none of it is built for them.
//

#if !os(iOS) && !os(Android)
import Foundation
import Observation
import NucleantVulkan
import NucleantWindow

@MainActor
final class AppSystemTrays<Node: NucleantContainerNode> {

    /// The trays as the app's body declares them now.
    private let declared: @MainActor () -> [_SystemTrayScene<Node>]

    /// The platform's tray: show an item, show what changed in it, take it
    /// away.
    var insert: @MainActor (TrayItem) -> Void = { _ in }
    var refresh: @MainActor (TrayItem) -> Void = { _ in }
    var remove: @MainActor (TrayItem) -> Void = { _ in }

    /// Quit the app — what taking out an item with no `isInserted` does.
    var quit: @MainActor () -> Void = {}

    /// Brings a tray's window up, hidden until its item is clicked. The
    /// runtime's puts it on the app's GPU device first.
    var present: @MainActor (HostingWindow<Node>) throws -> Void = { try $0.present() }

    /// The app's windows, for the views in a tray's window to open them.
    weak var windows: AppWindows<Node>?

    /// One per tray, in the order declared.
    private(set) var slots: [Slot] = []

    @MainActor
    final class Slot {
        let item: TrayItem
        var isInserted = false
        var binding: Binding<Bool>?
        var makePanel: (@MainActor () -> HostingWindow<Node>)?
        var panel: HostingWindow<Node>?

        init(item: TrayItem) {
            self.item = item
        }
    }

    /// Whether any of the items is in the tray now.
    var hasInsertedItem: Bool {
        slots.contains { $0.isInserted }
    }

    init(declared: @escaping @MainActor () -> [_SystemTrayScene<Node>]) {
        self.declared = declared
    }

    /// Put the items up, and follow the body from here on.
    func start() {
        update()
    }

    private func update() {
        let trays = withObservationTracking {
            let trays = declared()
            for tray in trays {
                _ = tray.isInserted?.wrappedValue
            }
            return trays
        } onChange: { [weak self] in
            Task { @MainActor in self?.update() }
        }
        for (index, tray) in trays.enumerated() {
            apply(tray, at: index)
        }
    }

    private func apply(_ tray: _SystemTrayScene<Node>, at index: Int) {
        if index == slots.count {
            slots.append(Slot(item: TrayItem(title: tray.title, action: .menu([]))))
        }
        let slot = slots[index]
        let item = slot.item
        item.title = tray.title
        item.iconName = tray.systemImage
        item.icon = tray.image.map { TrayIcon(width: $0.width, height: $0.height, pixels: $0.pixels) }
        item.showsTitle = tray.showsTitle
        if tray.usesWindow == true {
            item.action = .press { [weak self] anchor in
                self?.togglePanel(at: index, below: anchor)
            }
        } else {
            item.action = .menu(tray.menuItems)
        }
        item.onRemove = { [weak self] in
            self?.takenOut(at: index)
        }
        slot.binding = tray.isInserted
        slot.makePanel = tray.makePanel

        if tray.isInserted?.wrappedValue ?? true {
            if slot.isInserted {
                refresh(item)
            } else {
                slot.isInserted = true
                insert(item)
            }
        } else if slot.isInserted {
            slot.isInserted = false
            slot.panel?.hideTrayPanel()
            remove(item)
        }
    }

    /// The person took the item out of the tray: its binding says so, or,
    /// with none, the app quits.
    private func takenOut(at index: Int) {
        let slot = slots[index]
        slot.isInserted = false
        slot.panel?.hideTrayPanel()
        if let binding = slot.binding {
            binding.wrappedValue = false
        } else {
            quit()
        }
    }

    /// The item's window, shown under it or hidden — made the first time.
    private func togglePanel(at index: Int, below anchor: TrayAnchor) {
        let slot = slots[index]
        if let panel = slot.panel {
            panel.toggleTrayPanel(below: anchor)
            return
        }
        guard let makePanel = slot.makePanel else { return }
        let panel = makePanel()
        panel.isTrayPanel = true
        windows?.wire(panel) { [weak panel] in panel?.hideTrayPanel() }
        do {
            try present(panel)
        } catch {
            nucleantLogError("NucleantUI: a SystemTray's window failed to present: \(error)\n")
            return
        }
        slot.panel = panel
        panel.toggleTrayPanel(below: anchor)
    }
}
#endif
