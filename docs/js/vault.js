// Zero-knowledge encryption vault — WebCrypto only, no dependencies.
//
// • Master password → AES-256-GCM key via PBKDF2-SHA256 (210k iterations).
// • The key lives in memory only; it is NEVER stored or sent anywhere.
// • Notes are encrypted at rest (IndexedDB) and stay encrypted when synced to
//   GitHub, so anyone with access to the storage/repo sees only ciphertext.
// • A small "verifier" lets us check the password without storing it.

const enc = new TextEncoder();
const dec = new TextDecoder();
const ITER = 210000;
const VERIFIER_PLAINTEXT = 'NOTEX_VAULT_OK';

let _key = null; // CryptoKey, memory-only

const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

async function deriveKey(password, salt) {
  const base = await crypto.subtle.importKey(
    'raw', enc.encode(password), 'PBKDF2', false, ['deriveKey']
  );
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt, iterations: ITER, hash: 'SHA-256' },
    base,
    { name: 'AES-GCM', length: 256 },
    false,
    ['encrypt', 'decrypt']
  );
}

async function encStr(key, plain) {
  const iv = crypto.getRandomValues(new Uint8Array(12));
  const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(plain));
  return b64(iv) + ':' + b64(ct);
}

async function decStr(key, payload) {
  const [ivB, ctB] = payload.split(':');
  const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(ivB) }, key, unb64(ctB));
  return dec.decode(pt);
}

export const vault = {
  exists() { return !!localStorage.getItem('notex.vault'); },
  isUnlocked() { return !!_key; },
  lock() { _key = null; },

  /** First-time setup: create the vault from a new master password. */
  async setup(password) {
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const key = await deriveKey(password, salt);
    const verifier = await encStr(key, VERIFIER_PLAINTEXT);
    localStorage.setItem('notex.vault', JSON.stringify({ salt: b64(salt), verifier, iter: ITER }));
    _key = key;
  },

  /** Unlock an existing vault. Returns true on the correct password. */
  async unlock(password) {
    const meta = JSON.parse(localStorage.getItem('notex.vault'));
    try {
      const key = await deriveKey(password, unb64(meta.salt));
      const check = await decStr(key, meta.verifier);
      if (check !== VERIFIER_PLAINTEXT) return false;
      _key = key;
      return true;
    } catch {
      return false; // GCM auth failure = wrong password
    }
  },

  /** Encrypt an arbitrary object (e.g. notebook/tag) → { id, c }. */
  async encryptObject(id, obj) {
    return { id, c: await encStr(_key, JSON.stringify(obj)) };
  },

  /** Decrypt a { id, c } record back into { id, ...obj }. null on failure. */
  async decryptObject(rec) {
    try {
      const obj = JSON.parse(await decStr(_key, rec.c));
      return { id: rec.id, ...obj };
    } catch {
      return null;
    }
  },

  /** Plaintext in-memory note → encrypted record for storage/sync. */
  async encryptNote(note) {
    const payload = JSON.stringify({
      title: note.title || '',
      content: note.content || '',
      format: note.format || 'md',
      notebookId: note.notebookId || null,
      tagIds: note.tagIds || [],
    });
    return {
      id: note.id,
      c: await encStr(_key, payload),
      // non-secret metadata kept in clear for filtering/sorting without decrypting
      isPinned: !!note.isPinned,
      isFavorite: !!note.isFavorite,
      isArchived: !!note.isArchived,
      isTrashed: !!note.isTrashed,
      createdAt: note.createdAt,
      updatedAt: note.updatedAt,
    };
  },

  /** Encrypted record → plaintext in-memory note. null if it can't be decrypted. */
  async decryptNote(rec) {
    // Backward-compat: records created before encryption are plaintext.
    if (rec.c == null && (rec.title != null || rec.content != null)) {
      return { ...rec, format: rec.format || 'md' };
    }
    try {
      const obj = JSON.parse(await decStr(_key, rec.c));
      return {
        id: rec.id,
        title: obj.title,
        content: obj.content,
        format: obj.format || 'md',
        notebookId: obj.notebookId || null,
        tagIds: obj.tagIds || [],
        isPinned: rec.isPinned,
        isFavorite: rec.isFavorite,
        isArchived: rec.isArchived,
        isTrashed: rec.isTrashed,
        createdAt: rec.createdAt,
        updatedAt: rec.updatedAt,
      };
    } catch {
      return null;
    }
  },
};
