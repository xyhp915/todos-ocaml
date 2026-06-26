export function createTodoStore(onMessage) {
  const worker = new Worker(new URL("./todos_db_worker.js", import.meta.url), {
    type: "module",
  });

  worker.onmessage = (event) => onMessage(String(event.data ?? ""));

  return {
    post(message) {
      worker.postMessage(message);
    },
  };
}
