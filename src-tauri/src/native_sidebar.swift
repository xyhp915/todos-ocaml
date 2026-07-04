import AppKit
import ObjectiveC

private var sidebarAssociationKey: UInt8 = 0

private final class TodosNativeSidebarController: NSObject {
    private let window: NSWindow
    private let tauriContentView: NSView
    private let splitViewController = NSSplitViewController()
    private let activeLabel = NSTextField(labelWithString: "0 active")
    private let completedLabel = NSTextField(labelWithString: "0 completed")
    private var installed = false

    init(window: NSWindow, webView: NSView) {
        self.window = window
        self.tauriContentView = webView
    }

    func install() {
        if installed {
            return
        }
        installed = true

        let sidebarView = NSVisualEffectView()
        sidebarView.material = .sidebar
        sidebarView.blendingMode = .behindWindow
        sidebarView.state = .active

        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = NSTextField(labelWithString: "Todos")
        title.font = .systemFont(ofSize: 30, weight: .bold)
        title.textColor = .labelColor

        activeLabel.font = .systemFont(ofSize: 17, weight: .regular)
        completedLabel.font = .systemFont(ofSize: 17, weight: .regular)
        completedLabel.textColor = .secondaryLabelColor

        stack.addArrangedSubview(title)
        stack.setCustomSpacing(34, after: title)
        stack.addArrangedSubview(activeLabel)
        stack.addArrangedSubview(completedLabel)

        sidebarView.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: sidebarView.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 64),
        ])

        let sidebarViewController = NSViewController()
        sidebarViewController.view = sidebarView

        let detailView = makeDetailView()

        let detailViewController = NSViewController()
        detailViewController.view = detailView

        let sidebarItem = NSSplitViewItem(sidebarWithViewController: sidebarViewController)
        sidebarItem.minimumThickness = 220
        sidebarItem.maximumThickness = 300
        sidebarItem.canCollapse = false

        let detailItem = NSSplitViewItem(viewController: detailViewController)
        detailItem.canCollapse = false

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(detailItem)
        splitViewController.splitView.dividerStyle = .thin

        let rootView = window.contentView ?? tauriContentView
        let splitView = splitViewController.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: rootView.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])
    }

    func update(activeCount: UInt64, completedCount: UInt64) {
        activeLabel.stringValue = "\(activeCount) active"
        completedLabel.stringValue = "\(completedCount) completed"
    }

    private func makeDetailView() -> NSView {
        let detailView = NSView()
        detailView.translatesAutoresizingMaskIntoConstraints = false

        let hostedViews: [NSView]
        if window.contentView === tauriContentView {
            hostedViews = tauriContentView.subviews
        } else {
            hostedViews = [tauriContentView]
        }

        for hostedView in hostedViews {
            hostedView.removeFromSuperview()
            hostedView.translatesAutoresizingMaskIntoConstraints = false
            detailView.addSubview(hostedView)
            NSLayoutConstraint.activate([
                hostedView.leadingAnchor.constraint(equalTo: detailView.leadingAnchor),
                hostedView.trailingAnchor.constraint(equalTo: detailView.trailingAnchor),
                hostedView.topAnchor.constraint(equalTo: detailView.topAnchor),
                hostedView.bottomAnchor.constraint(equalTo: detailView.bottomAnchor),
            ])
        }

        return detailView
    }
}

@_cdecl("todos_native_sidebar_install")
public func todosNativeSidebarInstall(
    _ nsWindowPointer: UnsafeMutableRawPointer?,
    _ webViewPointer: UnsafeMutableRawPointer?
) -> Bool {
    guard let nsWindowPointer, let webViewPointer else {
        return false
    }

    let window = Unmanaged<NSWindow>.fromOpaque(nsWindowPointer).takeUnretainedValue()
    if objc_getAssociatedObject(window, &sidebarAssociationKey) != nil {
        return true
    }

    let webView = Unmanaged<NSView>.fromOpaque(webViewPointer).takeUnretainedValue()
    let controller = TodosNativeSidebarController(window: window, webView: webView)
    objc_setAssociatedObject(
        window,
        &sidebarAssociationKey,
        controller,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
    DispatchQueue.main.async {
        controller.install()
    }
    return true
}

@_cdecl("todos_native_sidebar_update")
public func todosNativeSidebarUpdate(
    _ nsWindowPointer: UnsafeMutableRawPointer?,
    _ activeCount: UInt64,
    _ completedCount: UInt64
) -> Bool {
    guard let nsWindowPointer else {
        return false
    }

    let window = Unmanaged<NSWindow>.fromOpaque(nsWindowPointer).takeUnretainedValue()
    guard let controller = objc_getAssociatedObject(
        window,
        &sidebarAssociationKey
    ) as? TodosNativeSidebarController else {
        return false
    }

    controller.update(activeCount: activeCount, completedCount: completedCount)
    return true
}
