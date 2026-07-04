import {
  GlassMaterialVariant,
  isGlassSupported,
  setLiquidGlassEffect,
} from "tauri-plugin-liquid-glass-api";
import { getCurrentWindow } from "@tauri-apps/api/window";

export function isTauriRuntime() {
  return typeof globalThis.__TAURI__?.core?.invoke === "function";
}

export function setupLiquidGlass() {
  if (!isTauriRuntime()) {
    return;
  }

  document.documentElement.classList.add("tauri-runtime");
  setupWindowDrag();
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

function setupWindowDrag() {
  if (globalThis.__TODOS_OCAML_WINDOW_DRAG_INSTALLED) {
    return;
  }

  globalThis.__TODOS_OCAML_WINDOW_DRAG_INSTALLED = true;
  document.addEventListener("pointerdown", (event) => {
    if (event.button !== 0) {
      return;
    }

    const target = event.target;
    if (!(target instanceof Element)) {
      return;
    }

    if (
      target.closest(
        "button, input, textarea, select, a, [role='button'], .todo-row",
      )
    ) {
      return;
    }

    if (target.closest(".app-shell, .sidebar, .workspace")) {
      getCurrentWindow().startDragging().catch(() => {});
    }
  });
}

export function setupNativeSearch(onChange) {
  globalThis.__TODOS_OCAML_NATIVE_SEARCH = (value) => {
    onChange(String(value ?? ""));
  };
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
