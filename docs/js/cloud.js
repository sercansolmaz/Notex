// Recoverable account + separate encryption password (Standard Notes / Joplin model).
//
//   • Account password  → standard Supabase email/password login. Recoverable
//     via Supabase's built-in "reset password" email. Account access is never lost.
//   • Encryption password (2nd) → derives the AES-256-GCM key that encrypts ALL
//     notes. NEVER sent to the server, so notes stay ciphertext (operator can't
//     read them). Survives an account-password reset. Forgetting it loses notes.
//
// The encryption salt + a verifier are kept in the account's user_metadata
// (not secret) so the key can be re-derived on any device. No SDK, fetch only.

const SUPABASE_URL = 'https://giifusgpxnhviqqdzdfn.supabase.co';
const SUPABASE_KEY = 'sb_publishable_2LKzETymKX7Lna7vNTVmmg_MUbdoJYc';
const PBKDF2_ITER = 200000;
const VERIFIER = 'NOTEX_ENC_OK';

const enc = new TextEncoder();
const dec = new TextDecoder();
const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));
const unb64 = (s) => Uint8Array.from(atob(s), (c) => c.charCodeAt(0));

// ── Encryption-key derivation (2nd password) ──
async function deriveEncKey(password, salt) {
  const base = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveKey']);
  // extractable:true so the key can be cached on-device for the "ask periodically"
  // flow (still never leaves the device / never reaches the server).
  return crypto.subtle.deriveKey(
    { name: 'PBKDF2', salt, iterations: PBKDF2_ITER, hash: 'SHA-256' },
    base, { name: 'AES-GCM', length: 256 }, true, ['encrypt', 'decrypt']
  );
}

async function exportKeyB64(key) { return b64(await crypto.subtle.exportKey('raw', key)); }
async function importKeyB64(keyB64) {
  return crypto.subtle.importKey('raw', unb64(keyB64), { name: 'AES-GCM' }, true, ['encrypt', 'decrypt']);
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

function jwtSub(token) {
  try { return JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/'))).sub; }
  catch { return null; }
}
function restHeaders(token) {
  return { apikey: SUPABASE_KEY, Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };
}
function authErr(d) {
  return d.msg || d.error_description || d.error || (d.code ? `Hata: ${d.code}` : 'İşlem başarısız');
}

export const cloud = {
  jwtSub,
  deriveEncKey,
  exportKeyB64,
  importKeyB64,

  /** Register: standard account + stash the encryption salt/verifier in metadata. */
  async signup(email, accountPassword, encPassword) {
    const salt = crypto.getRandomValues(new Uint8Array(16));
    const key = await deriveEncKey(encPassword, salt);
    const verifier = await encStr(key, VERIFIER);
    const r = await fetch(`${SUPABASE_URL}/auth/v1/signup`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({
        email: email.trim().toLowerCase(),
        password: accountPassword,
        data: { encSalt: b64(salt), encVerifier: verifier },
      }),
    });
    const d = await r.json();
    if (!r.ok) return { ok: false, error: authErr(d) };
    // If the project auto-confirms, a session comes back immediately.
    if (d.access_token) {
      return { ok: true, needsConfirm: false, token: d.access_token, userId: jwtSub(d.access_token), encKey: key };
    }
    return { ok: true, needsConfirm: true };
  },

  /** Log in with the account password. Returns token + the stored enc salt/verifier. */
  async login(email, accountPassword) {
    const r = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.trim().toLowerCase(), password: accountPassword }),
    });
    const d = await r.json();
    if (!r.ok || !d.access_token) return { ok: false, error: authErr(d) };
    const meta = (d.user && d.user.user_metadata) || {};
    return {
      ok: true, token: d.access_token, userId: jwtSub(d.access_token),
      encSalt: meta.encSalt || null, encVerifier: meta.encVerifier || null,
    };
  },

  /** Verify the encryption password against the stored salt/verifier → AES key or null. */
  async unlockEnc(encPassword, encSaltB64, encVerifier) {
    if (!encSaltB64 || !encVerifier) return null;
    const key = await deriveEncKey(encPassword, unb64(encSaltB64));
    try {
      const v = await decStr(key, encVerifier);
      return v === VERIFIER ? key : null;
    } catch { return null; }
  },

  /** Trigger Supabase's built-in account-password reset email. */
  async requestPasswordReset(email) {
    await fetch(`${SUPABASE_URL}/auth/v1/recover`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.trim().toLowerCase() }),
    });
    return true; // always succeeds silently (don't reveal whether the email exists)
  },

  // ── Encrypted sync ──
  async pull(token) {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/items?select=id,kind,ciphertext,updated_at,deleted`, {
      headers: restHeaders(token),
    });
    if (!r.ok) throw new Error('pull failed: ' + r.status);
    return r.json();
  },
  async push(token, rows) {
    if (!rows.length) return true;
    const r = await fetch(`${SUPABASE_URL}/rest/v1/items?on_conflict=id`, {
      method: 'POST',
      headers: { ...restHeaders(token), Prefer: 'resolution=merge-duplicates,return=minimal' },
      body: JSON.stringify(rows),
    });
    if (!r.ok) throw new Error('push failed: ' + r.status + ' ' + (await r.text()));
    return true;
  },
};
