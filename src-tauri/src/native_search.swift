import AppKit
import ObjectiveC

public typealias SearchCallback = @convention(c) (UnsafeMutableRawPointer?, UnsafePointer<CChar>) -> Void

@_silgen_name("todos_native_sidebar_toggle")
private func todosNativeSidebarToggle(_ nsWindowPointer: UnsafeMutableRawPointer?) -> Bool

private let sidebarToggleIdentifier = NSToolbarItem.Identifier("todos.sidebar.toggle")
private let searchButtonIdentifier = NSToolbarItem.Identifier("todos.search.button")
private let searchFieldIdentifier = NSToolbarItem.Identifier("todos.search")
private var controllerAssociationKey: UInt8 = 0

private final class TodosNativeSearchController: NSObject, NSToolbarDelegate, NSSearchFieldDelegate {
    private let window: NSWindow
    private let userData: UnsafeMutableRawPointer?
    private let callback: SearchCallback
    private var toolbar: NSToolbar?
    private var searchItem: NSSearchToolbarItem?

    init(window: NSWindow, userData: UnsafeMutableRawPointer?, callback: @escaping SearchCallback) {
        self.window = window
        self.userData = userData
        self.callback = callback
    }

    func install() {
        let toolbar = NSToolbar(identifier: "todos.toolbar")
        toolbar.allowsUserCustomization = false
        toolbar.autosavesConfiguration = false
        toolbar.showsBaselineSeparator = false
        toolbar.displayMode = .iconOnly
        toolbar.delegate = self

        if #available(macOS 15.0, *) {
            toolbar.allowsDisplayModeCustomization = false
        }
        if #available(macOS 13.0, *) {
            toolbar.centeredItemIdentifiers = []
        }

        toolbar.insertItem(withItemIdentifier: sidebarToggleIdentifier, at: 0)
        toolbar.insertItem(withItemIdentifier: .flexibleSpace, at: 1)
        toolbar.insertItem(withItemIdentifier: searchButtonIdentifier, at: 2)

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.toolbar = toolbar
        if #available(macOS 11.0, *) {
            window.toolbarStyle = .unifiedCompact
        }

        self.toolbar = toolbar
    }

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [sidebarToggleIdentifier, .flexibleSpace, searchButtonIdentifier, searchFieldIdentifier]
    }

    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] {
        [sidebarToggleIdentifier, .flexibleSpace, searchButtonIdentifier]
    }

    func toolbar(
        _ toolbar: NSToolbar,
        itemForItemIdentifier itemIdentifier: NSToolbarItem.Identifier,
        willBeInsertedIntoToolbar flag: Bool
    ) -> NSToolbarItem? {
        switch itemIdentifier {
        case sidebarToggleIdentifier:
            return makeSidebarToggle()
        case searchButtonIdentifier:
            return makeSearchButton()
        case searchFieldIdentifier:
            return makeSearchField()
        default:
            return nil
        }
    }

    @objc private func beginSearch(_ sender: Any?) {
        guard let toolbar else {
            return
        }

        if let index = itemIndex(in: toolbar, identifier: searchButtonIdentifier) {
            toolbar.removeItem(at: index)
            toolbar.insertItem(withItemIdentifier: searchFieldIdentifier, at: index)
        }

        DispatchQueue.main.async { [weak self] in
            guard let self, let searchItem = self.searchItem else {
                return
            }

            searchItem.beginSearchInteraction()
            self.window.makeFirstResponder(searchItem.searchField)
        }
    }

    @objc private func toggleSidebar(_ sender: Any?) {
        let windowPointer = Unmanaged.passUnretained(window).toOpaque()
        _ = todosNativeSidebarToggle(windowPointer)
    }

    @objc private func searchChanged(_ sender: NSSearchField) {
        sender.stringValue.withCString { value in
            callback(userData, value)
        }
    }

    func searchFieldDidEndSearching(_ sender: NSSearchField) {
        if sender.stringValue.isEmpty {
            collapseSearch()
        }
    }

    private func makeSearchButton() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: searchButtonIdentifier)
        item.label = "Search"
        item.paletteLabel = "Search Todos"
        item.toolTip = "Search"
        item.target = self
        item.action = #selector(beginSearch(_:))
        item.image =
            NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Search")
            ?? NSImage(named: NSImage.touchBarSearchTemplateName)
        item.isBordered = true
        return item
    }

    private func makeSidebarToggle() -> NSToolbarItem {
        let item = NSToolbarItem(itemIdentifier: sidebarToggleIdentifier)
        item.label = "Sidebar"
        item.paletteLabel = "Toggle Sidebar"
        item.toolTip = "Toggle Sidebar"
        item.target = self
        item.action = #selector(toggleSidebar(_:))
        item.image =
            NSImage(systemSymbolName: "sidebar.left", accessibilityDescription: "Toggle Sidebar")
            ?? NSImage(named: NSImage.touchBarSidebarTemplateName)
        item.isBordered = true
        return item
    }

    private func makeSearchField() -> NSSearchToolbarItem {
        let item = NSSearchToolbarItem(itemIdentifier: searchFieldIdentifier)
        let searchField = item.searchField
        searchField.placeholderString = "Search"
        searchField.target = self
        searchField.action = #selector(searchChanged(_:))
        searchField.delegate = self
        searchField.sendsSearchStringImmediately = true
        item.label = "Search"
        item.paletteLabel = "Search Todos"
        item.preferredWidthForSearchField = 240
        searchItem = item
        return item
    }

    private func collapseSearch() {
        guard let toolbar, itemIndex(in: toolbar, identifier: searchButtonIdentifier) == nil else {
            return
        }

        if let index = itemIndex(in: toolbar, identifier: searchFieldIdentifier) {
            toolbar.removeItem(at: index)
            toolbar.insertItem(withItemIdentifier: searchButtonIdentifier, at: index)
        }
    }

    private func itemIndex(in toolbar: NSToolbar, identifier: NSToolbarItem.Identifier) -> Int? {
        toolbar.items.firstIndex { $0.itemIdentifier == identifier }
    }
}

@_cdecl("todos_native_search_install")
public func todosNativeSearchInstall(
    _ nsWindowPointer: UnsafeMutableRawPointer?,
    _ userData: UnsafeMutableRawPointer?,
    _ callback: SearchCallback?
) -> Bool {
    guard let nsWindowPointer, let callback else {
        return false
    }

    let window = Unmanaged<NSWindow>.fromOpaque(nsWindowPointer).takeUnretainedValue()
    let controller = TodosNativeSearchController(
        window: window,
        userData: userData,
        callback: callback
    )
    controller.install()
    objc_setAssociatedObject(
        window,
        &controllerAssociationKey,
        controller,
        .OBJC_ASSOCIATION_RETAIN_NONATOMIC
    )
    return true
}
