#[cfg(target_os = "macos")]
fn command_output(command: &mut std::process::Command) -> String {
    let output = command.output().expect("failed to run build helper");
    if !output.status.success() {
        panic!(
            "build helper failed: {}",
            String::from_utf8_lossy(&output.stderr)
        );
    }
    String::from_utf8(output.stdout)
        .expect("build helper returned non-utf8 output")
        .trim()
        .to_string()
}

#[cfg(target_os = "macos")]
fn compile_native_search_swift() {
    use std::path::PathBuf;

    let manifest_dir = PathBuf::from(std::env::var("CARGO_MANIFEST_DIR").unwrap());
    let out_dir = PathBuf::from(std::env::var("OUT_DIR").unwrap());
    let source = manifest_dir.join("src/native_search.swift");
    let object = out_dir.join("native_search_swift.o");
    let target = std::env::var("TARGET").unwrap();
    let arch = if target.starts_with("aarch64") {
        "arm64"
    } else if target.starts_with("x86_64") {
        "x86_64"
    } else {
        panic!("unsupported macOS target for Swift helper: {target}");
    };
    let deployment_target = std::env::var("MACOSX_DEPLOYMENT_TARGET")
        .ok()
        .filter(|value| {
            value
                .split('.')
                .next()
                .and_then(|major| major.parse::<u32>().ok())
                .is_some_and(|major| major >= 14)
        })
        .unwrap_or_else(|| "14.0".to_string());
    let swift_target = format!("{arch}-apple-macosx{deployment_target}");
    let swiftc = command_output(std::process::Command::new("xcrun").args(["--find", "swiftc"]));
    let sdk = command_output(
        std::process::Command::new("xcrun").args(["--sdk", "macosx", "--show-sdk-path"]),
    );

    println!("cargo:rerun-if-changed={}", source.display());
    let status = std::process::Command::new(swiftc)
        .args([
            "-target",
            &swift_target,
            "-sdk",
            &sdk,
            "-parse-as-library",
            "-emit-object",
        ])
        .arg(&source)
        .arg("-o")
        .arg(&object)
        .status()
        .expect("failed to run swiftc");
    if !status.success() {
        panic!("failed to compile native_search.swift");
    }

    println!("cargo:rustc-link-arg={}", object.display());
    println!("cargo:rustc-link-lib=framework=AppKit");
    println!("cargo:rustc-link-lib=framework=Foundation");
}

fn main() {
    #[cfg(target_os = "macos")]
    compile_native_search_swift();

    tauri_build::build()
}
