// Portable encrypted backup file — download all notes as one encrypted file you
// can drop into Dropbox / iCloud Drive / Google Drive (or anywhere), and restore
// later. Self-contained: the KDF salt is embedded, so it restores on any device
// with just the backup password. WebCrypto only, no dependencies.

const enc = new TextEncoder();
const dec = new TextDecoder();
const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));
const ITER = 200000;

async function deriveKey(password, salt, iter) {
  const base = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveKey']);
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt, iterations: iter, hash: 'SHA-256' },
    base, { name: 'AES-GCM', length: 256 }, false, ['encrypt', 'decrypt']
  );
}

export const backup = {
  /** Encrypt a data object into a self-contained backup envelope. */
  async encrypt(dataObj, password) {
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const iv = crypto.getRandomValues(new Uint8Array(12));
    const key = await deriveKey(password, salt, ITER);
    const ct = await crypto.subtle.encrypt({ name: 'AES-GCM', iv }, key, enc.encode(JSON.stringify(dataObj)));
    return {
      app: 'Notex',
      type: 'encrypted-backup',
      version: 1,
      createdAt: new Date().toISOString(),
      kdf: { alg: 'PBKDF2-SHA256', iter: ITER, salt: b64(salt) },
      cipher: 'AES-256-GCM',
      data: b64(iv) + ':' + b64(ct),
    };
  },

  /** Decrypt a backup envelope back into the data object (throws on wrong password). */
  async decrypt(envelope, password) {
    const key = await deriveKey(password, unb64(envelope.kdf.salt), envelope.kdf.iter || ITER);
    const [ivB, ctB] = envelope.data.split(':');
    const pt = await crypto.subtle.decrypt({ name: 'AES-GCM', iv: unb64(ivB) }, key, unb64(ctB));
    return JSON.parse(dec.decode(pt));
  },
};
