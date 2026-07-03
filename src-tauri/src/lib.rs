use std::io::{BufRead, BufReader, Write};
use std::path::{Path, PathBuf};
use std::process::{Child, ChildStdin, Command, Stdio};
use std::sync::Mutex;

use tauri::Manager;

fn tauri_store_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    if let Some(path) = std::env::var_os("TODOS_OCAML_TAURI_STORE") {
        return Ok(PathBuf::from(path));
    }

    let dev_path = Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("..")
        .join("_build")
        .join("default")
        .join("app")
        .join("tauri_store.exe");
    if dev_path.exists() {
        return Ok(dev_path);
    }

    let exe_dir = std::env::current_exe()
        .map_err(|error| format!("Unable to locate Tauri executable: {error}"))?
        .parent()
        .map(Path::to_path_buf)
        .ok_or_else(|| "Unable to locate Tauri executable directory".to_string())?;
    let bundled_path = exe_dir.join("tauri_store");
    if bundled_path.exists() {
        return Ok(bundled_path);
    }

    if let Ok(resource_dir) = app.path().resource_dir() {
        let resource_path = resource_dir.join("tauri_store");
        if resource_path.exists() {
            return Ok(resource_path);
        }
    }

    Err(format!(
        "Unable to locate OCaml Tauri store process. Set TODOS_OCAML_TAURI_STORE or build {}",
        dev_path.display()
    ))
}

fn db_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    let app_data_dir = app
        .path()
        .app_data_dir()
        .map_err(|error| format!("Unable to locate app data directory: {error}"))?;
    std::fs::create_dir_all(&app_data_dir)
        .map_err(|error| format!("Unable to create app data directory: {error}"))?;
    Ok(app_data_dir.join("todos-ocaml.sqlite3"))
}

fn protocol_unescape(value: &str) -> String {
    let mut result = String::with_capacity(value.len());
    let mut chars = value.chars();
    while let Some(ch) = chars.next() {
        if ch == '\\' {
            match chars.next() {
                Some('\\') => result.push('\\'),
                Some('t') => result.push('\t'),
                Some('n') => result.push('\n'),
                Some('r') => result.push('\r'),
                Some(other) => result.push(other),
                None => result.push('\\'),
            }
        } else {
            result.push(ch);
        }
    }
    result
}

struct TauriStoreDaemon {
    _child: Child,
    child_stdin: ChildStdin,
    stdout: BufReader<std::process::ChildStdout>,
}

impl TauriStoreDaemon {
    fn spawn(app: &tauri::AppHandle) -> Result<Self, String> {
        let mut child = Command::new(tauri_store_path(app)?)
            .arg(db_path(app)?)
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::inherit())
            .spawn()
            .map_err(|error| format!("Unable to start OCaml Tauri store daemon: {error}"))?;
        let child_stdin = child
            .stdin
            .take()
            .ok_or_else(|| "Unable to open OCaml Tauri store stdin".to_string())?;
        let child_stdout = child
            .stdout
            .take()
            .ok_or_else(|| "Unable to open OCaml Tauri store stdout".to_string())?;
        Ok(Self {
            _child: child,
            child_stdin,
            stdout: BufReader::new(child_stdout),
        })
    }

    fn send_command(&mut self, command: String) -> Result<String, String> {
        writeln!(self.child_stdin, "{command}")
            .and_then(|_| self.child_stdin.flush())
            .map_err(|error| format!("Unable to write to OCaml Tauri store: {error}"))?;

        let mut response = String::new();
        let bytes = self
            .stdout
            .read_line(&mut response)
            .map_err(|error| format!("Unable to read from OCaml Tauri store: {error}"))?;
        if bytes == 0 {
            return Err("OCaml Tauri store daemon exited".to_string());
        }

        let response = response.trim_end_matches(['\r', '\n']);
        if let Some(payload) = response.strip_prefix("ok\t") {
            Ok(payload.to_string())
        } else if let Some(message) = response.strip_prefix("err\t") {
            Err(protocol_unescape(message))
        } else {
            Err(format!("Invalid OCaml Tauri store response: {response}"))
        }
    }
}

#[tauri::command]
fn ocaml_request(
    state: tauri::State<'_, Mutex<TauriStoreDaemon>>,
    payload: String,
) -> Result<String, String> {
    state
        .lock()
        .map_err(|_| "OCaml Tauri store daemon lock is poisoned".to_string())?
        .send_command(payload)
}

pub fn run() {
    tauri::Builder::default()
        .setup(|app| {
            let daemon = TauriStoreDaemon::spawn(app.handle()).map_err(|message| {
                Box::<dyn std::error::Error>::from(std::io::Error::new(
                    std::io::ErrorKind::Other,
                    message,
                ))
            })?;
            app.manage(Mutex::new(daemon));
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![ocaml_request])
        .run(tauri::generate_context!())
        .expect("error while running Tauri application");
}
