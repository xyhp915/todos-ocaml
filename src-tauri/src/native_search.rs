#[cfg(target_os = "macos")]
mod macos {
    use std::ffi::{c_char, c_void, CStr};

    use tauri::WebviewWindow;

    type SearchCallback = extern "C" fn(*mut c_void, *const c_char);

    struct NativeSearchState {
        window: WebviewWindow,
    }

    extern "C" {
        fn todos_native_search_install(
            ns_window: *mut c_void,
            user_data: *mut c_void,
            callback: SearchCallback,
        ) -> bool;
    }

    extern "C" fn search_changed(user_data: *mut c_void, value: *const c_char) {
        if user_data.is_null() || value.is_null() {
            return;
        }

        unsafe {
            let state = &*(user_data as *mut NativeSearchState);
            let query = CStr::from_ptr(value).to_string_lossy();
            if let Ok(serialized) = serde_json::to_string(query.as_ref()) {
                let _ = state.window.eval(&format!(
                    "globalThis.__TODOS_OCAML_NATIVE_SEARCH?.({serialized});"
                ));
            }
        }
    }

    pub fn install(window: &WebviewWindow) -> Result<(), String> {
        let ns_window = window
            .ns_window()
            .map_err(|error| format!("Unable to access NSWindow: {error}"))?
            as *mut c_void;
        let state = Box::into_raw(Box::new(NativeSearchState {
            window: window.clone(),
        }));

        let installed = unsafe {
            todos_native_search_install(ns_window, state as *mut c_void, search_changed)
        };
        if installed {
            Ok(())
        } else {
            unsafe {
                drop(Box::from_raw(state));
            }
            Err("Unable to install native search toolbar".to_string())
        }
    }
}

#[cfg(target_os = "macos")]
pub use macos::install;

#[cfg(not(target_os = "macos"))]
pub fn install(_: &tauri::WebviewWindow) -> Result<(), String> {
    Ok(())
}
