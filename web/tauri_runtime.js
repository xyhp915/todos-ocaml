import {
  GlassMaterialVariant,
  isGlassSupported,
  setLiquidGlassEffect,
} from "tauri-plugin-liquid-glass-api";

export function isTauriRuntime() {
  return typeof globalThis.__TAURI__?.core?.invoke === "function";
}

export function setupLiquidGlass() {
  if (!isTauriRuntime()) {
    return;
  }

  document.documentElement.classList.add("tauri-runtime");
  isGlassSupported()
    .then((supported) => {
      console.info(`[todos-ocaml] Liquid Glass supported: ${supported}`);
      if (!supported) {
        document.documentElement.classList.add("liquid-glass-unsupported");
        return;
      }

      return setLiquidGlassEffect({
        cornerRadius: 0,
        tintColor: "#ffffff10",
        variant: GlassMaterialVariant.Sidebar,
      }).then(() => {
        document.documentElement.classList.add("liquid-glass-supported");
        console.info("[todos-ocaml] Liquid Glass effect applied");
      });
    })
    .catch((error) => {
      document.documentElement.classList.add("liquid-glass-unsupported");
      console.warn("[todos-ocaml] Liquid Glass setup failed", error);
    });
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
