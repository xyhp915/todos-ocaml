#[cfg(target_os = "macos")]
#[allow(unexpected_cfgs)]
mod macos {
    use std::ffi::{c_void, CStr};
    use std::os::raw::c_char;
    use std::sync::Once;

    use objc::declare::ClassDecl;
    use objc::runtime::{Class, Object, Sel, BOOL, NO, YES};
    use objc::{class, msg_send, sel, sel_impl};
    use tauri::WebviewWindow;

    #[link(name = "AppKit", kind = "framework")]
    extern "C" {
        static NSToolbarFlexibleSpaceItemIdentifier: *mut Object;
    }

    const NS_UTF8_STRING_ENCODING: usize = 4;
    const NSTOOLBAR_DISPLAY_MODE_ICON_ONLY: usize = 2;
    const NSWINDOW_TITLE_HIDDEN: usize = 1;
    const NSWINDOW_TOOLBAR_STYLE_UNIFIED_COMPACT: usize = 4;
    const SEARCH_BUTTON_IDENTIFIER: &str = "todos.search.button";
    const SEARCH_FIELD_IDENTIFIER: &str = "todos.search";

    struct NativeSearchState {
        window: WebviewWindow,
    }

    unsafe fn ns_string(value: &str) -> *mut Object {
        let string: *mut Object = msg_send![class!(NSString), alloc];
        let string: *mut Object = msg_send![
            string,
            initWithBytes: value.as_ptr()
            length: value.len()
            encoding: NS_UTF8_STRING_ENCODING
        ];
        let string: *mut Object = msg_send![string, autorelease];
        string
    }

    unsafe fn ns_array(values: &[*mut Object]) -> *mut Object {
        let array: *mut Object = msg_send![class!(NSMutableArray), array];
        for value in values {
            let _: () = msg_send![array, addObject: *value];
        }
        array
    }

    unsafe fn ns_string_equals(value: *mut Object, expected: &str) -> bool {
        let is_equal: BOOL = msg_send![value, isEqualToString: ns_string(expected)];
        is_equal == YES
    }

    unsafe fn toolbar_item_index(toolbar: *mut Object, expected: &str) -> Option<usize> {
        let items: *mut Object = msg_send![toolbar, items];
        let count: usize = msg_send![items, count];
        for index in 0..count {
            let item: *mut Object = msg_send![items, objectAtIndex: index];
            let identifier: *mut Object = msg_send![item, itemIdentifier];
            if ns_string_equals(identifier, expected) {
                return Some(index);
            }
        }
        None
    }

    unsafe fn collapse_search(this: &Object) {
        let toolbar = *this.get_ivar::<*mut Object>("toolbar");
        if toolbar.is_null() || toolbar_item_index(toolbar, SEARCH_BUTTON_IDENTIFIER).is_some() {
            return;
        }

        if let Some(index) = toolbar_item_index(toolbar, SEARCH_FIELD_IDENTIFIER) {
            let _: () = msg_send![toolbar, removeItemAtIndex: index];
            let _: () = msg_send![
                toolbar,
                insertItemWithItemIdentifier: ns_string(SEARCH_BUTTON_IDENTIFIER)
                atIndex: index
            ];
        }
    }

    extern "C" fn begin_search(this: &Object, _: Sel, _: *mut Object) {
        unsafe {
            let toolbar = *this.get_ivar::<*mut Object>("toolbar");
            if toolbar.is_null() {
                return;
            }

            if let Some(index) = toolbar_item_index(toolbar, SEARCH_BUTTON_IDENTIFIER) {
                let _: () = msg_send![toolbar, removeItemAtIndex: index];
                let _: () = msg_send![
                    toolbar,
                    insertItemWithItemIdentifier: ns_string(SEARCH_FIELD_IDENTIFIER)
                    atIndex: index
                ];
            }

            let _: () = msg_send![
                this,
                performSelector: sel!(focusSearch:)
                withObject: std::ptr::null_mut::<Object>()
                afterDelay: 0.0f64
            ];
        }
    }

    extern "C" fn focus_search(this: &Object, _: Sel, _: *mut Object) {
        unsafe {
            let search_item = *this.get_ivar::<*mut Object>("searchItem");
            if search_item.is_null() {
                return;
            }

            let _: () = msg_send![search_item, beginSearchInteraction];
            let search_field: *mut Object = msg_send![search_item, searchField];
            if !search_field.is_null() {
                let field_window: *mut Object = msg_send![search_field, window];
                if !field_window.is_null() {
                    let _: BOOL = msg_send![field_window, makeFirstResponder: search_field];
                }
            }
        }
    }

    extern "C" fn search_changed(this: &Object, _: Sel, sender: *mut Object) {
        unsafe {
            let state_ptr = *this.get_ivar::<*mut c_void>("state");
            if state_ptr.is_null() {
                return;
            }

            let state = &*(state_ptr as *mut NativeSearchState);
            let value: *mut Object = msg_send![sender, stringValue];
            let utf8: *const c_char = msg_send![value, UTF8String];
            if utf8.is_null() {
                return;
            }

            let query = CStr::from_ptr(utf8).to_string_lossy();
            if let Ok(serialized) = serde_json::to_string(query.as_ref()) {
                let _ = state.window.eval(&format!(
                    "globalThis.__TODOS_OCAML_NATIVE_SEARCH?.({serialized});"
                ));
            }
        }
    }

    extern "C" fn search_field_did_end_searching(this: &Object, _: Sel, sender: *mut Object) {
        unsafe {
            let value: *mut Object = msg_send![sender, stringValue];
            let length: usize = msg_send![value, length];
            if length == 0 {
                collapse_search(this);
            }
        }
    }

    unsafe fn search_button(identifier: *mut Object, target: *mut Object) -> *mut Object {
        let item: *mut Object = msg_send![class!(NSToolbarItem), alloc];
        let item: *mut Object = msg_send![item, initWithItemIdentifier: identifier];
        let _: () = msg_send![item, setLabel: ns_string("Search")];
        let _: () = msg_send![item, setPaletteLabel: ns_string("Search Todos")];
        let _: () = msg_send![item, setToolTip: ns_string("Search")];
        let _: () = msg_send![item, setTarget: target];
        let _: () = msg_send![item, setAction: sel!(beginSearch:)];

        let image_class = class!(NSImage);
        let mut image: *mut Object =
            msg_send![image_class, imageNamed: ns_string("NSImageNameTouchBarSearchTemplate")];
        let responds_to_system_symbol: BOOL = msg_send![
            image_class,
            respondsToSelector: sel!(imageWithSystemSymbolName:accessibilityDescription:)
        ];
        if responds_to_system_symbol == YES {
            image = msg_send![
                image_class,
                imageWithSystemSymbolName: ns_string("magnifyingglass")
                accessibilityDescription: ns_string("Search")
            ];
        }
        if !image.is_null() {
            let _: () = msg_send![item, setImage: image];
        }
        let responds_to_bordered: BOOL = msg_send![item, respondsToSelector: sel!(setBordered:)];
        if responds_to_bordered == YES {
            let _: () = msg_send![item, setBordered: YES];
        }

        let item: *mut Object = msg_send![item, autorelease];
        item
    }

    extern "C" fn toolbar_item_for_identifier(
        this: &Object,
        _: Sel,
        _: *mut Object,
        identifier: *mut Object,
        _: BOOL,
    ) -> *mut Object {
        unsafe {
            let target = *this.get_ivar::<*mut Object>("searchTarget");
            if ns_string_equals(identifier, SEARCH_BUTTON_IDENTIFIER) {
                return search_button(identifier, target);
            }

            if !ns_string_equals(identifier, SEARCH_FIELD_IDENTIFIER) {
                return std::ptr::null_mut();
            }
            let Some(search_toolbar_item_class) = Class::get("NSSearchToolbarItem") else {
                return std::ptr::null_mut();
            };

            let item: *mut Object = msg_send![search_toolbar_item_class, alloc];
            let item: *mut Object = msg_send![item, initWithItemIdentifier: identifier];
            let search_field: *mut Object = msg_send![item, searchField];
            let _: () = msg_send![search_field, setPlaceholderString: ns_string("Search")];
            let _: () = msg_send![search_field, setTarget: target];
            let _: () = msg_send![search_field, setAction: sel!(searchChanged:)];
            let _: () = msg_send![search_field, setDelegate: target];
            let _: () = msg_send![search_field, setSendsSearchStringImmediately: YES];
            let _: () = msg_send![item, setLabel: ns_string("Search")];
            let _: () = msg_send![item, setPaletteLabel: ns_string("Search Todos")];
            let responds_to_preferred_width: BOOL =
                msg_send![item, respondsToSelector: sel!(setPreferredWidthForSearchField:)];
            if responds_to_preferred_width == YES {
                let _: () = msg_send![item, setPreferredWidthForSearchField: 240.0f64];
            }
            let _: *mut Object = msg_send![item, retain];
            (*target).set_ivar("searchItem", item);
            let item: *mut Object = msg_send![item, autorelease];
            item
        }
    }

    extern "C" fn toolbar_allowed_identifiers(_: &Object, _: Sel, _: *mut Object) -> *mut Object {
        unsafe {
            ns_array(&[
                NSToolbarFlexibleSpaceItemIdentifier,
                ns_string(SEARCH_BUTTON_IDENTIFIER),
                ns_string(SEARCH_FIELD_IDENTIFIER),
            ])
        }
    }

    extern "C" fn toolbar_default_identifiers(_: &Object, _: Sel, _: *mut Object) -> *mut Object {
        unsafe {
            ns_array(&[
                NSToolbarFlexibleSpaceItemIdentifier,
                ns_string(SEARCH_BUTTON_IDENTIFIER),
            ])
        }
    }

    fn register_classes() {
        static REGISTER: Once = Once::new();
        REGISTER.call_once(|| unsafe {
            if Class::get("TodosNativeSearchTarget").is_none() {
                let superclass = class!(NSObject);
                let mut decl = ClassDecl::new("TodosNativeSearchTarget", superclass).unwrap();
                decl.add_ivar::<*mut c_void>("state");
                decl.add_ivar::<*mut Object>("toolbar");
                decl.add_ivar::<*mut Object>("searchItem");
                decl.add_method(
                    sel!(beginSearch:),
                    begin_search as extern "C" fn(&Object, Sel, *mut Object),
                );
                decl.add_method(
                    sel!(focusSearch:),
                    focus_search as extern "C" fn(&Object, Sel, *mut Object),
                );
                decl.add_method(
                    sel!(searchChanged:),
                    search_changed as extern "C" fn(&Object, Sel, *mut Object),
                );
                decl.add_method(
                    sel!(searchFieldDidEndSearching:),
                    search_field_did_end_searching as extern "C" fn(&Object, Sel, *mut Object),
                );
                decl.register();
            }

            if Class::get("TodosToolbarDelegate").is_none() {
                let superclass = class!(NSObject);
                let mut decl = ClassDecl::new("TodosToolbarDelegate", superclass).unwrap();
                decl.add_ivar::<*mut Object>("searchTarget");
                decl.add_method(
                    sel!(toolbar:itemForItemIdentifier:willBeInsertedIntoToolbar:),
                    toolbar_item_for_identifier
                        as extern "C" fn(
                            &Object,
                            Sel,
                            *mut Object,
                            *mut Object,
                            BOOL,
                        ) -> *mut Object,
                );
                decl.add_method(
                    sel!(toolbarAllowedItemIdentifiers:),
                    toolbar_allowed_identifiers
                        as extern "C" fn(&Object, Sel, *mut Object) -> *mut Object,
                );
                decl.add_method(
                    sel!(toolbarDefaultItemIdentifiers:),
                    toolbar_default_identifiers
                        as extern "C" fn(&Object, Sel, *mut Object) -> *mut Object,
                );
                decl.register();
            }
        });
    }

    pub fn install(window: &WebviewWindow) -> Result<(), String> {
        register_classes();

        unsafe {
            if Class::get("NSSearchToolbarItem").is_none() {
                return Ok(());
            }

            let ns_window = window
                .ns_window()
                .map_err(|error| format!("Unable to access NSWindow: {error}"))?
                as *mut Object;
            let target_class = Class::get("TodosNativeSearchTarget")
                .ok_or_else(|| "Native search target class is not registered".to_string())?;
            let delegate_class = Class::get("TodosToolbarDelegate")
                .ok_or_else(|| "Toolbar delegate class is not registered".to_string())?;

            let state = Box::into_raw(Box::new(NativeSearchState {
                window: window.clone(),
            })) as *mut c_void;

            let target: *mut Object = msg_send![target_class, new];
            (*target).set_ivar("state", state);
            (*target).set_ivar("searchItem", std::ptr::null_mut::<Object>());

            let delegate: *mut Object = msg_send![delegate_class, new];
            (*delegate).set_ivar("searchTarget", target);

            let toolbar: *mut Object = msg_send![class!(NSToolbar), alloc];
            let toolbar: *mut Object =
                msg_send![toolbar, initWithIdentifier: ns_string("todos.toolbar")];
            (*target).set_ivar("toolbar", toolbar);
            let _: () = msg_send![toolbar, setAllowsUserCustomization: NO];
            let _: () = msg_send![toolbar, setAutosavesConfiguration: NO];
            let _: () = msg_send![toolbar, setShowsBaselineSeparator: NO];
            let _: () = msg_send![toolbar, setDisplayMode: NSTOOLBAR_DISPLAY_MODE_ICON_ONLY];
            let _: () = msg_send![toolbar, setDelegate: delegate];
            let responds_to_display_mode_customization: BOOL =
                msg_send![toolbar, respondsToSelector: sel!(setAllowsDisplayModeCustomization:)];
            if responds_to_display_mode_customization == YES {
                let _: () = msg_send![toolbar, setAllowsDisplayModeCustomization: NO];
            }
            let responds_to_centered_items: BOOL =
                msg_send![toolbar, respondsToSelector: sel!(setCenteredItemIdentifiers:)];
            if responds_to_centered_items == YES {
                let empty_set: *mut Object = msg_send![class!(NSSet), set];
                let _: () = msg_send![toolbar, setCenteredItemIdentifiers: empty_set];
            }
            let _: () = msg_send![toolbar, insertItemWithItemIdentifier: NSToolbarFlexibleSpaceItemIdentifier atIndex: 0usize];
            let _: () = msg_send![toolbar, insertItemWithItemIdentifier: ns_string(SEARCH_BUTTON_IDENTIFIER) atIndex: 1usize];

            let _: () = msg_send![ns_window, setTitleVisibility: NSWINDOW_TITLE_HIDDEN];
            let _: () = msg_send![ns_window, setTitlebarAppearsTransparent: YES];
            let _: () = msg_send![ns_window, setToolbar: toolbar];
            let responds_to_toolbar_style: BOOL =
                msg_send![ns_window, respondsToSelector: sel!(setToolbarStyle:)];
            if responds_to_toolbar_style == YES {
                let _: () =
                    msg_send![ns_window, setToolbarStyle: NSWINDOW_TOOLBAR_STYLE_UNIFIED_COMPACT];
            }

            Ok(())
        }
    }
}

#[cfg(target_os = "macos")]
pub use macos::install;

#[cfg(not(target_os = "macos"))]
pub fn install(_: &tauri::WebviewWindow) -> Result<(), String> {
    Ok(())
}
