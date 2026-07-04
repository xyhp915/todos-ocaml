#[cfg(target_os = "macos")]
mod macos {
    use std::ffi::c_void;

    use tauri::WebviewWindow;

    extern "C" {
        fn todos_native_sidebar_install(ns_window: *mut c_void, web_view: *mut c_void) -> bool;
        fn todos_native_sidebar_update(
            ns_window: *mut c_void,
            active_count: u64,
            completed_count: u64,
        ) -> bool;
    }

    pub fn install(window: &WebviewWindow) -> Result<(), String> {
        let ns_window = window
            .ns_window()
            .map_err(|error| format!("Unable to access NSWindow: {error}"))?
            as *mut c_void;
        let web_view = window
            .ns_view()
            .map_err(|error| format!("Unable to access Tauri NSView: {error}"))?
            as *mut c_void;

        if unsafe { todos_native_sidebar_install(ns_window, web_view) } {
            Ok(())
        } else {
            Err("Unable to install native sidebar".to_string())
        }
    }

    pub fn update_counts(window: &WebviewWindow, active_count: u64, completed_count: u64) {
        if let Ok(ns_window) = window.ns_window() {
            unsafe {
                todos_native_sidebar_update(ns_window as *mut c_void, active_count, completed_count);
            }
        }
    }
}

#[cfg(target_os = "macos")]
pub use macos::{install, update_counts};

#[cfg(not(target_os = "macos"))]
pub fn install(_: &tauri::WebviewWindow) -> Result<(), String> {
    Ok(())
}

#[cfg(not(target_os = "macos"))]
pub fn update_counts(_: &tauri::WebviewWindow, _: u64, _: u64) {}
