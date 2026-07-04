import AppKit
import ObjectiveC

private var sidebarAssociationKey: UInt8 = 0

private final class TodosSidebarSplitView: NSSplitView {
    var isUserDraggingDivider = false
    var onFinishedDraggingDivider: (() -> Void)?

    override var dividerColor: NSColor {
        .clear
    }

    override func mouseDown(with event: NSEvent) {
        isUserDraggingDivider = true
        super.mouseDown(with: event)
        isUserDraggingDivider = false
        onFinishedDraggingDivider?()
    }

    override func drawDivider(in rect: NSRect) {}
}

private final class TodosSidebarSplitViewController: NSSplitViewController {
    override func splitView(_ splitView: NSSplitView, canCollapseSubview subview: NSView) -> Bool {
        let canCollapse = super.splitView(splitView, canCollapseSubview: subview)
        if (splitView as? TodosSidebarSplitView)?.isUserDraggingDivider == true {
            return false
        }
        return canCollapse
    }
}

private final class TodosNativeSidebarController: NSObject {
    private let sidebarMinimumWidth: CGFloat = 220
    private let sidebarMaximumWidth: CGFloat = 300
    private let sidebarCollapseThreshold: CGFloat = 130
    private let window: NSWindow
    private let tauriContentView: NSView
    private let splitViewController = TodosSidebarSplitViewController()
    private let activeLabel = NSTextField(labelWithString: "0 active")
    private let completedLabel = NSTextField(labelWithString: "0 completed")
    private var sidebarItem: NSSplitViewItem?
    private var isSettlingSidebar = false
    private var installed = false

    init(window: NSWindow, webView: NSView) {
        self.window = window
        self.tauriContentView = webView
        super.init()

        let splitView = TodosSidebarSplitView()
        splitView.isVertical = true
        splitView.onFinishedDraggingDivider = { [weak self] in
            self?.settleSidebarAfterUserDrag()
        }
        splitViewController.splitView = splitView
    }

    func install() {
        if installed {
            return
        }
        installed = true

        let sidebarView = NSView()

        let sidebarPanel = NSVisualEffectView()
        sidebarPanel.material = .popover
        sidebarPanel.blendingMode = .behindWindow
        sidebarPanel.state = .active
        sidebarPanel.alphaValue = 0.72
        sidebarPanel.translatesAutoresizingMaskIntoConstraints = false
        sidebarPanel.wantsLayer = true
        sidebarPanel.layer?.cornerRadius = 18
        sidebarPanel.layer?.masksToBounds = true

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

        sidebarView.addSubview(sidebarPanel)
        sidebarPanel.addSubview(stack)
        NSLayoutConstraint.activate([
            sidebarPanel.leadingAnchor.constraint(equalTo: sidebarView.leadingAnchor, constant: 10),
            sidebarPanel.trailingAnchor.constraint(equalTo: sidebarView.trailingAnchor, constant: -10),
            sidebarPanel.topAnchor.constraint(equalTo: sidebarView.topAnchor, constant: 10),
            sidebarPanel.bottomAnchor.constraint(equalTo: sidebarView.bottomAnchor, constant: -10),
            stack.leadingAnchor.constraint(equalTo: sidebarPanel.leadingAnchor, constant: 28),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: sidebarPanel.trailingAnchor, constant: -18),
            stack.topAnchor.constraint(equalTo: sidebarPanel.topAnchor, constant: 54),
        ])

        let sidebarViewController = NSViewController()
        sidebarViewController.view = sidebarView

        let detailView = makeDetailView()

        let detailViewController = NSViewController()
        detailViewController.view = detailView

        let sidebarItem = NSSplitViewItem(viewController: sidebarViewController)
        sidebarItem.minimumThickness = 0
        sidebarItem.maximumThickness = sidebarMaximumWidth
        sidebarItem.canCollapse = true
        sidebarItem.collapseBehavior = .preferResizingSiblingsWithFixedSplitView
        self.sidebarItem = sidebarItem

        let detailItem = NSSplitViewItem(viewController: detailViewController)
        detailItem.canCollapse = false

        splitViewController.addSplitViewItem(sidebarItem)
        splitViewController.addSplitViewItem(detailItem)
        splitViewController.splitView.isVertical = true
        splitViewController.splitView.dividerStyle = .thin

        let rootView = window.contentView ?? tauriContentView
        let splitView = splitViewController.view
        splitView.translatesAutoresizingMaskIntoConstraints = false
        rootView.addSubview(splitView)
        NSLayoutConstraint.activate([
            splitView.leadingAnchor.constraint(equalTo: rootView.leadingAnchor),
            splitView.trailingAnchor.constraint(equalTo: rootView.trailingAnchor),
            splitView.topAnchor.constraint(equalTo: rootView.safeAreaLayoutGuide.topAnchor),
            splitView.bottomAnchor.constraint(equalTo: rootView.bottomAnchor),
        ])

        DispatchQueue.main.async { [weak self] in
            self?.restoreSidebarWidthIfNeeded(animated: false)
        }
    }

    func update(activeCount: UInt64, completedCount: UInt64) {
        activeLabel.stringValue = "\(activeCount) active"
        completedLabel.stringValue = "\(completedCount) completed"
    }

    func toggle() {
        guard let sidebarItem else {
            return
        }

        setSidebarCollapsed(!sidebarItem.isCollapsed)
    }

    private func settleSidebarAfterUserDrag() {
        guard
            !isSettlingSidebar,
            let sidebarItem,
            !sidebarItem.isCollapsed,
            let sidebarView = splitViewController.splitView.arrangedSubviews.first
        else {
            return
        }

        let sidebarWidth = sidebarView.frame.width
        if sidebarWidth <= sidebarCollapseThreshold {
            setSidebarCollapsed(true)
        } else if sidebarWidth < sidebarMinimumWidth {
            animateSidebarWidth(sidebarMinimumWidth)
        }
    }

    private func setSidebarCollapsed(_ collapsed: Bool) {
        guard let sidebarItem, sidebarItem.isCollapsed != collapsed else {
            return
        }

        isSettlingSidebar = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            context.allowsImplicitAnimation = true
            sidebarItem.animator().isCollapsed = collapsed
        } completionHandler: { [weak self] in
            guard let self else {
                return
            }

            if collapsed {
                self.isSettlingSidebar = false
            } else {
                self.restoreSidebarWidthIfNeeded(animated: true)
            }
        }
    }

    private func animateSidebarWidth(_ width: CGFloat) {
        isSettlingSidebar = true
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            context.allowsImplicitAnimation = true
            splitViewController.splitView.animator().setPosition(width, ofDividerAt: 0)
        } completionHandler: { [weak self] in
            self?.isSettlingSidebar = false
        }
    }

    private func restoreSidebarWidthIfNeeded(animated: Bool) {
        guard
            let sidebarItem,
            !sidebarItem.isCollapsed,
            let sidebarView = splitViewController.splitView.arrangedSubviews.first,
            sidebarView.frame.width < sidebarMinimumWidth
        else {
            isSettlingSidebar = false
            return
        }

        if animated {
            animateSidebarWidth(sidebarMinimumWidth)
        } else {
            splitViewController.splitView.setPosition(sidebarMinimumWidth, ofDividerAt: 0)
            isSettlingSidebar = false
        }
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

@_cdecl("todos_native_sidebar_toggle")
public func todosNativeSidebarToggle(_ nsWindowPointer: UnsafeMutableRawPointer?) -> Bool {
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

    controller.toggle()
    return true
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
