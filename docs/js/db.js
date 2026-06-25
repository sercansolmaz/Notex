// Minimal IndexedDB wrapper — local-first storage, zero dependencies.
// Stores: notes, notebooks, tags (all hold encrypted records).
const DB_NAME = 'notex';
const DB_VERSION = 2;
const STORES = ['notes', 'notebooks', 'tags'];

let _db = null;

function open() {
  if (_db) return Promise.resolve(_db);
  return new Promise((resolve, reject) => {
    const req = indexedDB.open(DB_NAME, DB_VERSION);
    req.onupgradeneeded = () => {
      const db = req.result;
      for (const name of STORES) {
        if (!db.objectStoreNames.contains(name)) {
          db.createObjectStore(name, { keyPath: 'id' });
        }
      }
    };
    req.onsuccess = () => { _db = req.result; resolve(_db); };
    req.onerror = () => reject(req.error);
  });
}

function reqP(req) {
  return new Promise((resolve, reject) => {
    req.onsuccess = () => resolve(req.result);
    req.onerror = () => reject(req.error);
  });
}

export const db = {
  async getAll(store = 'notes') {
    const d = await open();
    return reqP(d.transaction(store).objectStore(store).getAll());
  },
  async get(store, id) {
    const d = await open();
    return reqP(d.transaction(store).objectStore(store).get(id));
  },
  async put(store, obj) {
    const d = await open();
    return reqP(d.transaction(store, 'readwrite').objectStore(store).put(obj));
  },
  async remove(store, id) {
    const d = await open();
    return reqP(d.transaction(store, 'readwrite').objectStore(store).delete(id));
  },
};
