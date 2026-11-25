// Dragging cards on the Mac, like src/useDnd.ts: a press becomes a drag after
// 5pt, a copy of the card follows the pointer, a faded "ghost" shows where it
// will land and the other cards slide aside; Esc cancels. Built on a plain
// drag gesture, not the system's drag and drop, which shows a "+ copy" cursor
// (the reason the Tauri app doesn't use HTML5 drag and drop either).
//
// The views report where sections and cards are (in the "board" coordinate
// space); DropRules (NowboardKit, tested) decides the spot.

import NowboardKit
import SwiftUI

@MainActor
@Observable
final class DragController {
    /// The card being dragged, or nil.
    private(set) var id: String?
    /// Where the preview is: the list, and the card it goes before.
    private(set) var target: DropTarget?
    /// Where the copy of the card is drawn (its top-left corner) and its size.
    private(set) var cloneOrigin: CGPoint = .zero
    private(set) var cloneSize: CGSize = .zero

    // Measured by the views. Not observed: changing them mustn't redraw anything.
    @ObservationIgnored var cardFrames: [String: CGRect] = [:]
    @ObservationIgnored var spans: [String: Int] = [:]
    @ObservationIgnored var zones: [TaskStatus: DropZone] = [:]
    @ObservationIgnored var gridColumns: [TaskStatus: Int] = [:]
    @ObservationIgnored var gridSpacing: [TaskStatus: CGFloat] = [:]
    @ObservationIgnored private var grab: CGSize = .zero
    @ObservationIgnored private var pending: (target: DropTarget, since: Date)?
    @ObservationIgnored private var last: CGPoint = .zero
    #if os(macOS)
        @ObservationIgnored fileprivate var monitor: Any?
    #endif
    /// What a drop does (set by the store: move, or complete on Done).
    @ObservationIgnored var onDrop: ((String, DropTarget) -> Void)?

    /// The gesture moved: start the drag (first time), move the copy, update the spot.
    func moved(_ id: String, start: CGPoint, location: CGPoint, status: TaskStatus) {
        if self.id == nil {
            guard let frame = cardFrames[id] else { return }
            self.id = id
            grab = CGSize(width: start.x - frame.minX, height: start.y - frame.minY)
            cloneSize = frame.size
            target = DropTarget(status: status, beforeID: id)  // its own slot: nothing moves yet
            #if os(macOS)
                NSCursor.closedHand.push()
                listen(boardPoint: location)
            #endif
        }
        update(location)
    }

    private func update(_ location: CGPoint) {
        last = location
        cloneOrigin = CGPoint(x: location.x - grab.width, y: location.y - grab.height)
        if let spot = spot(at: location) { propose(spot) }
    }

    /// Let go: returns where to drop (where you let go counts, even if the
    /// preview hadn't caught up yet), or nil if nothing should move.
    func ended() -> (id: String, target: DropTarget)? {
        guard let id else { return nil }
        #if DEBUG
            if ProcessInfo.processInfo.arguments.contains("-dragdebug") {
                print("DRAG last", last, "target", target as Any, "spot", spot(at: last) as Any)
                print("DRAG zones", zones.mapValues { ($0.frame, $0.grid as Any) })
                print("DRAG cards", cardFrames.sorted { $0.value.minY < $1.value.minY }.map { ($0.key.prefix(12), $0.value) })
            }
        #endif
        let result = (spot(at: last) ?? target).map { (id, $0) }
        reset()
        guard let result, result.1.beforeID != id else { return nil }
        return result
    }

    /// Esc: put everything back.
    func cancel() {
        reset()
    }

    /// True for a moment after a drag ended: the release that ends a drag
    /// mustn't also open or tick the card under it (the Tauri app swallows that click).
    var swallowsClick: Bool {
        endedAt.map { Date().timeIntervalSince($0) < 0.3 } ?? false
    }
    @ObservationIgnored private var endedAt: Date?

    private func reset() {
        if id != nil { endedAt = Date() }
        if id != nil {
            #if os(macOS)
                NSCursor.pop()
                if let monitor { NSEvent.removeMonitor(monitor) }
                monitor = nil
            #endif
        }
        withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) {
            id = nil
            target = nil
        }
        pending = nil
    }

    /// The spot under the pointer, or nil to keep the current one.
    private func spot(at point: CGPoint) -> DropTarget? {
        guard let id else { return nil }
        let ordered = [TaskStatus.today, .backlog, .done].compactMap { zones[$0] }
        guard let zone = DropRules.zone(at: point.y, in: ordered) else { return nil }
        guard zone.status != .done, let grid = zone.grid else { return DropTarget(status: zone.status) }
        let cols = gridColumns[zone.status] ?? 1
        let cards = cardFrames.compactMap { key, frame -> PlacedCard? in
            // Only cards in this grid (by position), the ghost included.
            guard grid.insetBy(dx: -1, dy: -1).contains(CGPoint(x: frame.midX, y: frame.midY)) else { return nil }
            return PlacedCard(id: key, frame: frame, span: spans[key] ?? 1)
        }
        // In reading order (row by row, left to right), like the page order the
        // Tauri code walks. A dictionary has no order of its own: without this,
        // "the first card" was random and drops landed next to the wrong card.
        .sorted { abs($0.frame.minY - $1.frame.minY) > 1 ? $0.frame.minY < $1.frame.minY : $0.frame.minX < $1.frame.minX }
        let ghostSpan = zone.status == .today ? (spans[id] ?? 1) : 1
        return DropRules.spot(in: grid, status: zone.status, point: point, cards: cards, dragged: id,
                              columns: cols, spacing: gridSpacing[zone.status] ?? 10, ghostSpan: ghostSpan)
    }

    /// Moves the preview only once the pointer has rested on a new spot for
    /// 70ms, so it doesn't jitter while you sweep across the board.
    private func propose(_ t: DropTarget) {
        if t == target {
            pending = nil
            return
        }
        if let p = pending, p.target == t {
            if Date().timeIntervalSince(p.since) >= 0.07 { commit(t) }
        } else {
            pending = (t, Date())
            // Re-check after the delay even if the pointer stops moving.
            Task {
                try? await Task.sleep(for: .milliseconds(75))
                if let p = pending, p.target == t, id != nil { commit(t) }
            }
        }
    }

    private func commit(_ t: DropTarget) {
        pending = nil
        // Other cards slide aside slowly (~400ms, no overshoot), like the Tauri app.
        withAnimation(.timingCurve(0.2, 0.8, 0.3, 1, duration: 0.4)) { target = t }
    }

    /// The list `status` as it should be drawn right now: the dragged card's
    /// slot closed if it moved elsewhere, and the ghost where it will land.
    func displayed(_ ids: [String], status: TaskStatus) -> [String] {
        guard let id, let target, target.status == status, status != .done,
            let p = DropRules.preview(ids: ids, dragged: id, before: target.beforeID)
        else { return ids }
        var list = ids
        var at = p.index
        if p.collapse, let from = list.firstIndex(of: id) {
            list.remove(at: from)
            if from < at { at -= 1 }
        }
        list.insert(DropRules.ghostID, at: at)
        return list
    }
}

#if os(macOS)
    import AppKit

    extension DragController {
        /// Once a drag has started, follow the mouse directly with an AppKit
        /// event monitor instead of the card's gesture. The gesture belongs to
        /// the card's view, and SwiftUI removes that view when its slot closes
        /// (dragging it elsewhere in its own list), which would lose the
        /// "mouse up": the copy stuck on top and nothing moved. The monitor
        /// sees every move, the release and Esc, whatever happens to the views.
        ///
        /// Window points become board points with a fixed offset taken at the
        /// start (the board doesn't scroll during a drag).
        fileprivate func listen(boardPoint: CGPoint) {
            guard let event = NSApp.currentEvent, let window = event.window else { return }
            let height = window.contentView?.bounds.height ?? 0
            // AppKit counts y from the bottom, SwiftUI from the top.
            let windowPoint = CGPoint(x: event.locationInWindow.x, y: height - event.locationInWindow.y)
            let shift = CGSize(width: boardPoint.x - windowPoint.x, height: boardPoint.y - windowPoint.y)
            monitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged, .leftMouseUp, .keyDown]) { [weak self] e in
                guard let self else { return e }
                let p = CGPoint(x: e.locationInWindow.x + shift.width, y: height - e.locationInWindow.y + shift.height)
                switch e.type {
                case .leftMouseDragged:
                    self.update(p)
                    return nil
                case .leftMouseUp:
                    self.update(p)
                    if let drop = self.ended() { self.onDrop?(drop.id, drop.target) }
                    // Passed on, so SwiftUI's own gesture finishes cleanly too;
                    // `swallowsClick` stops it from also clicking a button.
                    return e
                case .keyDown where e.keyCode == 53:  // Esc
                    self.cancel()
                    return nil
                default:
                    return e
                }
            }
        }
    }
#endif
