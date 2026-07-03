export function isTauriRuntime() {
  return typeof globalThis.__TAURI__?.core?.invoke === "function";
}

export function invokeString(command, args, onSuccess, onError) {
  const invoke = globalThis.__TAURI__?.core?.invoke;
  if (typeof invoke !== "function") {
    onError("Tauri invoke API is not available");
    return;
  }

  invoke(command, args)
    .then((payload) => onSuccess(String(payload ?? "")))
    .catch((error) => onError(String(error?.message ?? error)));
}
