import sqlite3InitModule from "@sqlite.org/sqlite-wasm";

let dbPromise = null;

function openDatabase() {
  if (dbPromise !== null) {
    return dbPromise;
  }

  dbPromise = sqlite3InitModule({
    print: () => {},
    printErr: console.error,
  }).then((sqlite3) => {
    const Db = sqlite3.oo1.OpfsDb || sqlite3.oo1.DB;
    const db = new Db("/todos-ocaml.sqlite3", "ct");

    db.exec(`
      create table if not exists kvs (
        key text primary key not null,
        payload text not null
      );
    `);

    return {
      load() {
        let payload = "";
        db.exec({
          sql: "select payload from kvs where key = 'todos' limit 1;",
          rowMode: "array",
          callback(row) {
            payload = String(row[0] ?? "");
          },
        });
        return payload;
      },
      save(payload) {
        db.exec({
          sql: "insert or replace into kvs (key, payload) values ('todos', ?);",
          bind: [payload],
        });
      },
    };
  });

  return dbPromise;
}

export function installTodoWorker(handleMessage) {
  self.onmessage = (event) => handleMessage(String(event.data ?? ""));
}

export function postTodoWorkerMessage(message) {
  self.postMessage(message);
}

export function loadStoredPayload(onLoaded, onError) {
  openDatabase()
    .then((db) => onLoaded(db.load()))
    .catch((error) => onError(String(error?.message ?? error)));
}

export function saveStoredPayload(payload, onSaved, onError) {
  openDatabase()
    .then((db) => {
      db.save(payload);
      onSaved(payload);
    })
    .catch((error) => onError(String(error?.message ?? error)));
}
