import sqlite3InitModule from "@sqlite.org/sqlite-wasm";

let dbPromise = null;
let activeDb = null;
let queuedMessages = [];
let messageHandler = null;

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
      restore(address) {
        let payload = "";
        db.exec({
          sql: "select payload from kvs where key = ? limit 1;",
          bind: [address],
          rowMode: "array",
          callback(row) {
            payload = String(row[0] ?? "");
          },
        });
        return payload;
      },
      store(address, payload) {
        db.exec({
          sql: "insert or replace into kvs (key, payload) values (?, ?);",
          bind: [address, payload],
        });
      },
      listAddresses() {
        const addresses = [];
        db.exec({
          sql: "select key from kvs order by key;",
          rowMode: "array",
          callback(row) {
            addresses.push(String(row[0] ?? ""));
          },
        });
        return addresses;
      },
      delete(address) {
        db.exec({
          sql: "delete from kvs where key = ?;",
          bind: [address],
        });
      },
    };
  });

  return dbPromise;
}

function dispatch(message) {
  if (activeDb === null) {
    queuedMessages.push(message);
    return;
  }
  messageHandler(message);
}

export function installTodoWorker(handleMessage) {
  messageHandler = handleMessage;
  self.onmessage = (event) => dispatch(String(event.data ?? ""));
  openDatabase()
    .then((db) => {
      activeDb = db;
      const messages = queuedMessages;
      queuedMessages = [];
      messages.forEach((message) => messageHandler(message));
    })
    .catch((error) => self.postMessage(`failed:${String(error?.message ?? error)}`));
}

export function postTodoWorkerMessage(message) {
  self.postMessage(message);
}

function requireDatabase() {
  if (activeDb === null) {
    throw new Error("SQLite storage is not ready");
  }
  return activeDb;
}

export function storeStoragePayload(address, payload) {
  requireDatabase().store(address, payload);
}

export function restoreStoragePayload(address) {
  return requireDatabase().restore(address);
}

export function listStorageAddresses() {
  return requireDatabase().listAddresses();
}

export function deleteStoragePayload(address) {
  requireDatabase().delete(address);
}
