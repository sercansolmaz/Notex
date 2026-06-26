// Zero-knowledge multi-user cloud sync via Supabase — fetch only, no SDK.
//
// One master password, split client-side into two independent values:
//   • authSecret → sent to Supabase as the login "password" (server can verify
//     identity but cannot decrypt anything)
//   • encKey     → AES-GCM key, NEVER leaves the device, encrypts every item
// Supabase therefore stores only ciphertext; the operator cannot read notes.

const SUPABASE_URL = 'https://giifusgpxnhviqqdzdfn.supabase.co';
const SUPABASE_KEY = 'sb_publishable_2LKzETymKX7Lna7vNTVmmg_MUbdoJYc';
const PBKDF2_ITER = 200000;

const enc = new TextEncoder();
const b64 = (buf) => btoa(String.fromCharCode(...new Uint8Array(buf)));

// ── Key derivation (password → {encKey, authSecret}) ──
async function deriveKeys(email, password) {
  const e = email.trim().toLowerCase();
  const baseKey = await crypto.subtle.importKey('raw', enc.encode(password), 'PBKDF2', false, ['deriveBits']);
  // Master key: PBKDF2 with the email as salt (deterministic on any device).
  const mkBits = await crypto.subtle.deriveBits(
    { name: 'PBKDF2', salt: enc.encode('notex:' + e), iterations: PBKDF2_ITER, hash: 'SHA-256' },
    baseKey, 256
  );
  const mk = await crypto.subtle.importKey('raw', mkBits, 'HKDF', false, ['deriveBits']);
  // Two domain-separated outputs from the master key.
  const hkdf = (info) => crypto.subtle.deriveBits(
    { name: 'HKDF', hash: 'SHA-256', salt: new Uint8Array(0), info: enc.encode(info) }, mk, 256
  );
  const encBits = await hkdf('notex-enc');
  const authBits = await hkdf('notex-auth');
  const encKey = await crypto.subtle.importKey('raw', encBits, { name: 'AES-GCM' }, false, ['encrypt', 'decrypt']);
  return { encKey, authSecret: b64(authBits) };
}

// ── REST helpers ──
function jwtSub(token) {
  try {
    const p = JSON.parse(atob(token.split('.')[1].replace(/-/g, '+').replace(/_/g, '/')));
    return p.sub;
  } catch { return null; }
}

function restHeaders(token) {
  return {
    apikey: SUPABASE_KEY,
    Authorization: `Bearer ${token}`,
    'Content-Type': 'application/json',
  };
}

export const cloud = {
  deriveKeys,
  jwtSub,

  /** Register a new account. Returns { ok, error }. */
  async signup(email, password) {
    const { encKey, authSecret } = await deriveKeys(email, password);
    const r = await fetch(`${SUPABASE_URL}/auth/v1/signup`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.trim().toLowerCase(), password: authSecret }),
    });
    const data = await r.json();
    if (!r.ok) return { ok: false, error: data.msg || data.error_description || data.error || 'Kayıt başarısız' };
    return { ok: true, encKey, session: data.access_token ? data : null, needsConfirm: !data.access_token };
  },

  /** Log in. Returns { ok, token, userId, encKey, error }. */
  async login(email, password) {
    const { encKey, authSecret } = await deriveKeys(email, password);
    const r = await fetch(`${SUPABASE_URL}/auth/v1/token?grant_type=password`, {
      method: 'POST',
      headers: { apikey: SUPABASE_KEY, 'Content-Type': 'application/json' },
      body: JSON.stringify({ email: email.trim().toLowerCase(), password: authSecret }),
    });
    const data = await r.json();
    if (!r.ok || !data.access_token) {
      const msg = data.error_description || data.msg || 'Giriş başarısız (e-posta/parola hatalı)';
      return { ok: false, error: msg };
    }
    return { ok: true, token: data.access_token, userId: jwtSub(data.access_token), encKey };
  },

  /** Pull all of this user's encrypted rows. */
  async pull(token) {
    const r = await fetch(`${SUPABASE_URL}/rest/v1/items?select=id,kind,ciphertext,updated_at,deleted`, {
      headers: restHeaders(token),
    });
    if (!r.ok) throw new Error('pull failed: ' + r.status);
    return r.json();
  },

  /** Upsert encrypted rows (push). `rows`: [{id,user_id,kind,ciphertext,updated_at,deleted}] */
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
