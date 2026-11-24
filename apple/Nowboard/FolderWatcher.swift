// Watches the Tasks folder, so changes made elsewhere (Obsidian, sync, an
// agent, the other device) show up while the app is open (DESIGN.md: "the
// folder is watched and reloaded").
//
// Two ways in, because neither catches everything on its own:
// - NSFilePresenter: Apple's way to hear about coordinated changes, which is
//   how iCloud and other well-behaved apps write.
// - A kernel "vnode" watch on the folder: any file added, removed or renamed
//   in it, including plain atomic saves (write a temp file, rename it in).
// Both call `onChange`, at most once per 0.3s.

import Foundation

final class FolderWatcher: NSObject, NSFilePresenter, @unchecked Sendable {
    // `@unchecked Sendable`: the system calls a presenter from its own queue.
    // We only touch `pending` on that queue, and hop to the main thread for
    // `onChange`, so sharing it between threads is safe.

    let presentedItemURL: URL?
    let presentedItemOperationQueue = OperationQueue()
    private let onChange: @MainActor () -> Void
    private var source: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?
    private let queue = DispatchQueue(label: "nowboard.folder-watcher")

    init(url: URL, onChange: @escaping @MainActor () -> Void) {
        presentedItemURL = url
        self.onChange = onChange
        super.init()
        presentedItemOperationQueue.underlyingQueue = queue
        NSFileCoordinator.addFilePresenter(self)

        // The vnode watch needs an open "file descriptor" for the folder.
        let fd = open(url.path, O_EVTONLY)
        if fd >= 0 {
            let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: queue)
            src.setEventHandler { [weak self] in self?.changed() }
            src.setCancelHandler { close(fd) }
            src.resume()
            source = src
        }
    }

    func stop() {
        NSFileCoordinator.removeFilePresenter(self)
        source?.cancel()
        source = nil
    }

    // NSFilePresenter: something in or under the folder changed.
    func presentedSubitemDidChange(at url: URL) { changed() }
    func presentedItemDidChange() { changed() }
    func presentedSubitem(at oldURL: URL, didMoveTo newURL: URL) { changed() }
    func accommodatePresentedSubitemDeletion(at url: URL, completionHandler: @escaping @Sendable (Error?) -> Void) {
        changed()
        completionHandler(nil)
    }

    /// Waits 0.3s for more changes (a sync often touches several files), then reloads once.
    private func changed() {
        queue.async { [self] in
            pending?.cancel()
            let work = DispatchWorkItem { [onChange] in
                Task { @MainActor in onChange() }
            }
            pending = work
            queue.asyncAfter(deadline: .now() + 0.3, execute: work)
        }
    }
}
