import { db } from './db.js';
import { renderMarkdown, htmlToMarkdown } from './markdown.js';
import { vault } from './vault.js';
import { cloud } from './cloud.js';
import { backup } from './backup.js';

let cloudSession = null; // { token, userId, email } when signed into a cloud account
let authMode = 'login';  // 'login' | 'register'

const stripTags = (s) => (s || '').replace(/<[^>]+>/g, ' ');

// ── State ──
const state = {
  notes: [],
  notebooks: [],
  tags: [],
  currentId: null,
  view: 'all',        // 'all' | 'favorites' | 'trash' | 'nb:<id>' | 'tag:<id>'
  query: '',
  mode: 'edit',       // 'edit' | 'preview' | 'split'
};

const PALETTE = ['#6366f1', '#e0524d', '#f59e0b', '#10b981', '#0ea5e9', '#a855f7', '#ec4899', '#14b8a6'];
function colorFor(id) {
  let h = 0;
  for (const ch of (id || '')) h = (h * 31 + ch.charCodeAt(0)) >>> 0;
  return PALETTE[h % PALETTE.length];
}

let saveTimer = null;

// ── Helpers ──
const $ = (sel) => document.querySelector(sel);
const uid = () =>
  (crypto.randomUUID ? crypto.randomUUID()
    : 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
        const r = (Math.random() * 16) | 0;
        return (c === 'x' ? r : (r & 0x3) | 0x8).toString(16);
      }));

function now() { return Date.now(); }

function relDate(ts) {
  if (!ts) return '';
  const d = new Date(ts);
  const today = new Date();
  const sameDay = d.toDateString() === today.toDateString();
  if (sameDay) return d.toLocaleTimeString('tr-TR', { hour: '2-digit', minute: '2-digit' });
  return d.toLocaleDateString('tr-TR', { day: 'numeric', month: 'short' });
}

function firstLine(text) {
  const t = (text || '').trim().split('\n')[0].replace(/^#+\s*/, '');
  return t.slice(0, 80);
}

function noteTitle(n) {
  const t = (n.title || '').trim();
  if (t) return t;
  const c = n.format === 'rich' ? stripTags(n.content) : (n.content || '');
  return firstLine(c) || 'Başlıksız';
}

// ── Data ops ──
async function loadAll() {
  const [noteRecs, nbRecs, tagRecs] = await Promise.all([
    db.getAll('notes'), db.getAll('notebooks'), db.getAll('tags'),
  ]);
  state.notes = (await Promise.all(noteRecs.map((r) => vault.decryptNote(r)))).filter(Boolean);
  state.notebooks = (await Promise.all(nbRecs.map((r) => vault.decryptObject(r)))).filter(Boolean);
  state.tags = (await Promise.all(tagRecs.map((r) => vault.decryptObject(r)))).filter(Boolean);
  if (state.notes.length === 0) {
    await createNote(WELCOME);
  }
}

async function persist(note) {
  note.updatedAt = now();
  await db.put('notes', await vault.encryptNote(note));
}

// Drop a note that was left completely empty (no title, no content) — keeps
// repeated "+ Yeni" clicks from accumulating blank notes (Apple Notes behavior).
async function discardIfEmpty(id) {
  const n = state.notes.find((x) => x.id === id);
  if (!n) return;
  if ((n.title || '').trim() === '' && (n.content || '').trim() === '') {
    state.notes = state.notes.filter((x) => x.id !== id);
    await db.remove('notes', id);
  }
}

// User-driven navigation to another note: discard the current one if it's blank.
async function navigateTo(id) {
  if (state.currentId && state.currentId !== id) await discardIfEmpty(state.currentId);
  selectNote(id);
}

async function createNote(content = '') {
  if (state.currentId) await discardIfEmpty(state.currentId);
  const note = {
    id: uid(),
    title: '',
    content,
    format: 'md',
    notebookId: null,
    tagIds: [],
    isPinned: false,
    isFavorite: false,
    isArchived: false,
    isTrashed: false,
    createdAt: now(),
    updatedAt: now(),
  };
  // Inherit the current scope so a note made inside a notebook/tag lands there.
  if (state.view.startsWith('nb:')) note.notebookId = state.view.slice(3);
  else if (state.view.startsWith('tag:')) note.tagIds = [state.view.slice(4)];
  else state.view = 'all';

  state.notes.push(note);
  await db.put('notes', await vault.encryptNote(note));
  selectNote(note.id);
  renderFilters();
  renderSidebar();
  renderList();
  $('#title').focus();
  return note;
}

function currentNote() {
  return state.notes.find((n) => n.id === state.currentId) || null;
}

// ── Filtering ──
function visibleNotes() {
  let list = state.notes.filter((n) => {
    if (state.view === 'trash') return n.isTrashed;
    if (n.isTrashed) return false;
    if (state.view === 'favorites') return n.isFavorite;
    if (state.view.startsWith('nb:')) return n.notebookId === state.view.slice(3);
    if (state.view.startsWith('tag:')) return (n.tagIds || []).includes(state.view.slice(4));
    return true;
  });
  const q = state.query.trim().toLowerCase();
  if (q) {
    const terms = q.split(/\s+/);
    list = list.filter((n) => {
      const hay = (noteTitle(n) + ' ' + (n.content || '')).toLowerCase();
      return terms.every((t) => hay.includes(t));
    });
  }
  return list.sort((a, b) => {
    if (!!b.isPinned !== !!a.isPinned) return (b.isPinned ? 1 : 0) - (a.isPinned ? 1 : 0);
    return (b.updatedAt || 0) - (a.updatedAt || 0);
  });
}

// ── Rendering ──
function renderList() {
  const ul = $('#note-list');
  const notes = visibleNotes();
  ul.innerHTML = '';
  for (const n of notes) {
    const li = document.createElement('li');
    li.className = 'note-item' + (n.id === state.currentId ? ' active' : '');
    li.dataset.id = n.id;
    const star = n.isFavorite ? '★ ' : '';
    const pin = n.isPinned ? '<span class="pin-dot">●</span> ' : '';
    li.innerHTML =
      `<div class="ni-title">${pin}${escapeHTML(star + noteTitle(n))}</div>` +
      `<div class="ni-preview">${escapeHTML(firstBodyLine(n))}</div>` +
      `<div class="ni-date">${relDate(n.updatedAt)}</div>`;
    li.addEventListener('click', () => navigateTo(n.id));
    ul.appendChild(li);
  }
  $('#count').textContent = `${notes.length} not`;
}

function firstBodyLine(n) {
  let body;
  if (n.format === 'rich') {
    body = stripTags(n.content);
  } else {
    body = (n.content || '').trim().split('\n').slice(1).join(' ').trim()
      || (n.title ? (n.content || '') : '');
  }
  return body.replace(/[#*`>\-\[\]]/g, '').replace(/\s+/g, ' ').slice(0, 80).trim();
}

function renderFilters() {
  document.querySelectorAll('.filter').forEach((b) =>
    b.classList.toggle('active', b.dataset.view === state.view));
}

function selectNote(id) {
  state.currentId = id;
  const n = currentNote();
  const pane = $('#editor-pane');
  const empty = $('#empty-state');
  if (!n) { pane.hidden = true; empty.hidden = false; return; }
  empty.hidden = true; pane.hidden = false;

  $('#title').value = n.title || '';
  renderEditorMeta(n);

  const isRich = n.format === 'rich';
  if (isRich) {
    $('#rich').innerHTML = n.content || '';
    $('.editor-body').dataset.mode = 'rich';
    $('#rich-toolbar').hidden = false;
    $('#btn-mode').hidden = true;
    $('#btn-format').textContent = '✦ Zengin';
    $('#btn-format').classList.add('on');
  } else {
    $('#body').value = n.content || '';
    $('.editor-body').dataset.mode = state.mode;
    $('#rich-toolbar').hidden = true;
    $('#btn-mode').hidden = false;
    $('#btn-format').textContent = 'M↓ Markdown';
    $('#btn-format').classList.remove('on');
    updatePreview();
  }
  updateWordCount();
  $('#btn-fav').textContent = n.isFavorite ? '★' : '☆';
  $('#btn-fav').classList.toggle('on', !!n.isFavorite);

  // Trash vs normal actions
  const trashed = !!n.isTrashed;
  $('#btn-trash').hidden = trashed;
  $('#btn-restore').hidden = !trashed;
  $('#btn-delete').hidden = !trashed;
  $('#title').disabled = trashed;
  $('#body').disabled = trashed;
  $('#rich').contentEditable = trashed ? 'false' : 'true';

  document.getElementById('app').classList.add('show-editor');
  renderList();
}

function updatePreview() {
  $('#preview').innerHTML = renderMarkdown($('#body').value);
}

function updateWordCount() {
  const n = currentNote();
  const raw = n && n.format === 'rich' ? ($('#rich').innerText || '') : $('#body').value;
  const text = raw.trim();
  const words = text ? text.split(/\s+/).length : 0;
  $('#words').textContent = `${words} kelime`;
}

function escapeHTML(s) {
  return (s || '').replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ── Notebooks & Tags: sidebar + editor meta ──
function activeNoteCount(pred) {
  return state.notes.filter((n) => !n.isTrashed && pred(n)).length;
}

function renderSidebar() {
  const nbUl = $('#notebook-list');
  nbUl.innerHTML = '';
  for (const nb of [...state.notebooks].sort((a, b) => a.name.localeCompare(b.name))) {
    const count = activeNoteCount((n) => n.notebookId === nb.id);
    const li = document.createElement('li');
    li.className = 'nav-item' + (state.view === 'nb:' + nb.id ? ' active' : '');
    li.innerHTML =
      `<span class="nav-dot" style="background:${colorFor(nb.id)}"></span>` +
      `<span class="nav-name">${escapeHTML(nb.name)}</span>` +
      `<span class="nav-count">${count || ''}</span>`;
    li.addEventListener('click', () => setView('nb:' + nb.id));
    li.addEventListener('dblclick', () => renameNotebook(nb));
    li.addEventListener('contextmenu', (e) => { e.preventDefault(); deleteNotebook(nb); });
    li.title = 'Tıkla: filtrele · Çift tık: yeniden adlandır · Sağ tık: sil';
    nbUl.appendChild(li);
  }
  $('#nb-empty').hidden = state.notebooks.length > 0;

  const tagUl = $('#tag-list');
  tagUl.innerHTML = '';
  for (const tag of [...state.tags].sort((a, b) => a.name.localeCompare(b.name))) {
    const count = activeNoteCount((n) => (n.tagIds || []).includes(tag.id));
    const li = document.createElement('li');
    li.className = 'nav-item' + (state.view === 'tag:' + tag.id ? ' active' : '');
    li.innerHTML =
      `<span class="nav-dot" style="background:${tag.color || colorFor(tag.id)}"></span>` +
      `<span class="nav-name">#${escapeHTML(tag.name)}</span>` +
      `<span class="nav-count">${count || ''}</span>`;
    li.addEventListener('click', () => setView('tag:' + tag.id));
    li.addEventListener('contextmenu', (e) => { e.preventDefault(); deleteTag(tag.id, tag.name); });
    li.title = 'Tıkla: filtrele · Sağ tık: sil';
    tagUl.appendChild(li);
  }
  $('#tag-empty').hidden = state.tags.length > 0;
}

function setView(v) {
  state.view = v;
  renderFilters();
  renderSidebar();
  renderList();
}

function renderEditorMeta(n) {
  const sel = $('#note-notebook');
  sel.innerHTML = '<option value="">📁 Defter yok</option>' +
    [...state.notebooks].sort((a, b) => a.name.localeCompare(b.name))
      .map((nb) => `<option value="${nb.id}">${escapeHTML(nb.name)}</option>`).join('');
  sel.value = n.notebookId || '';
  sel.disabled = !!n.isTrashed;

  const wrap = $('#note-tags');
  wrap.innerHTML = '';
  for (const tid of (n.tagIds || [])) {
    const tag = state.tags.find((t) => t.id === tid);
    if (!tag) continue;
    const chip = document.createElement('span');
    chip.className = 'tag-chip';
    chip.style.setProperty('--chip', tag.color || colorFor(tag.id));
    chip.innerHTML = `#${escapeHTML(tag.name)} <button class="chip-x" title="Kaldır">×</button>`;
    chip.querySelector('.chip-x').addEventListener('click', () => removeTagFromNote(n.id, tid));
    wrap.appendChild(chip);
  }
  $('#add-note-tag').hidden = !!n.isTrashed;
}

// ── Notebook / Tag CRUD (all encrypted) ──
async function createNotebook() {
  const name = (prompt('Yeni defter adı:') || '').trim();
  if (!name) return;
  const nb = { id: uid(), name, createdAt: now() };
  state.notebooks.push(nb);
  await db.put('notebooks', await vault.encryptObject(nb.id, { name: nb.name, createdAt: nb.createdAt }));
  setView('nb:' + nb.id);
}

async function renameNotebook(nb) {
  const name = (prompt('Yeni defter adı:', nb.name) || '').trim();
  if (!name) return;
  nb.name = name;
  await db.put('notebooks', await vault.encryptObject(nb.id, { name: nb.name, createdAt: nb.createdAt }));
  renderSidebar();
  renderList();
  const cur = currentNote(); if (cur) renderEditorMeta(cur);
}

async function deleteNotebook(nb) {
  if (!confirm(`"${nb.name}" defteri silinecek. İçindeki notlar silinmez, "Defter yok" olur. Devam?`)) return;
  for (const n of state.notes.filter((x) => x.notebookId === nb.id)) {
    n.notebookId = null;
    await persist(n);
  }
  state.notebooks = state.notebooks.filter((x) => x.id !== nb.id);
  await db.remove('notebooks', nb.id);
  if (state.view === 'nb:' + nb.id) state.view = 'all';
  renderFilters();
  renderSidebar();
  renderList();
  const cur = currentNote(); if (cur) renderEditorMeta(cur);
}

async function getOrCreateTag(name) {
  const existing = state.tags.find((t) => t.name.toLowerCase() === name.toLowerCase());
  if (existing) return existing;
  const tag = { id: uid(), name, color: PALETTE[state.tags.length % PALETTE.length], createdAt: now() };
  state.tags.push(tag);
  await db.put('tags', await vault.encryptObject(tag.id, { name: tag.name, color: tag.color, createdAt: tag.createdAt }));
  return tag;
}

async function createTag() {
  const name = (prompt('Yeni etiket adı:') || '').trim().replace(/^#/, '');
  if (!name) return;
  await getOrCreateTag(name);
  renderSidebar();
}

async function deleteTag(tagId, tagName) {
  if (!confirm(`"#${tagName}" etiketi tüm notlardan kaldırılacak. Devam?`)) return;
  for (const n of state.notes.filter((x) => (x.tagIds || []).includes(tagId))) {
    n.tagIds = n.tagIds.filter((t) => t !== tagId);
    await persist(n);
  }
  state.tags = state.tags.filter((t) => t.id !== tagId);
  await db.remove('tags', tagId);
  if (state.view === 'tag:' + tagId) state.view = 'all';
  renderFilters();
  renderSidebar();
  renderList();
  const cur = currentNote(); if (cur) renderEditorMeta(cur);
}

async function setNoteNotebook(value) {
  const n = currentNote(); if (!n) return;
  n.notebookId = value || null;
  await persist(n);
  renderSidebar();
  renderList();
}

async function addTagToCurrentNote() {
  const n = currentNote(); if (!n || n.isTrashed) return;
  const name = (prompt('Etiket adı:') || '').trim().replace(/^#/, '');
  if (!name) return;
  const tag = await getOrCreateTag(name);
  n.tagIds = n.tagIds || [];
  if (!n.tagIds.includes(tag.id)) n.tagIds.push(tag.id);
  await persist(n);
  renderEditorMeta(n);
  renderSidebar();
  renderList();
}

async function removeTagFromNote(noteId, tagId) {
  const n = state.notes.find((x) => x.id === noteId); if (!n) return;
  n.tagIds = (n.tagIds || []).filter((t) => t !== tagId);
  await persist(n);
  renderEditorMeta(n);
  renderSidebar();
  renderList();
}

// ── Autosave ──
function scheduleSave() {
  const n = currentNote();
  if (!n || n.isTrashed) return;
  n.title = $('#title').value;
  if (n.format === 'rich') {
    n.content = $('#rich').innerHTML;
  } else {
    n.content = $('#body').value;
    updatePreview();
  }
  updateWordCount();
  $('#saved').textContent = 'kaydediliyor…';
  clearTimeout(saveTimer);
  saveTimer = setTimeout(async () => {
    await persist(n);
    $('#saved').textContent = 'kaydedildi ✓';
    renderList();
  }, 400);
}

// ── Actions ──
async function toggleFavorite() {
  const n = currentNote(); if (!n) return;
  n.isFavorite = !n.isFavorite;
  await persist(n);
  selectNote(n.id);
}

// Switch a note between Markdown and rich text, converting its content.
async function toggleFormat() {
  const n = currentNote(); if (!n || n.isTrashed) return;
  if (n.format === 'rich') {
    n.content = htmlToMarkdown($('#rich').innerHTML);
    n.format = 'md';
  } else {
    n.content = renderMarkdown($('#body').value);
    n.format = 'rich';
  }
  await persist(n);
  selectNote(n.id);
}

// Rich toolbar command (execCommand on the focused contenteditable).
function richCommand(btn) {
  $('#rich').focus();
  if (btn.dataset.cmd) document.execCommand(btn.dataset.cmd, false, null);
  else if (btn.dataset.block) document.execCommand('formatBlock', false, btn.dataset.block);
  scheduleSave();
}

async function trashNote() {
  const n = currentNote(); if (!n) return;
  n.isTrashed = true; n.isPinned = false;
  await persist(n);
  state.currentId = null;
  $('#editor-pane').hidden = true; $('#empty-state').hidden = false;
  renderList();
}

async function restoreNote() {
  const n = currentNote(); if (!n) return;
  n.isTrashed = false;
  await persist(n);
  selectNote(n.id);
}

async function deleteForever() {
  const n = currentNote(); if (!n) return;
  if (!confirm('Bu not kalıcı olarak silinecek. Emin misiniz?')) return;
  await db.remove('notes', n.id);
  state.notes = state.notes.filter((x) => x.id !== n.id);
  state.currentId = null;
  $('#editor-pane').hidden = true; $('#empty-state').hidden = false;
  renderList();
}

function cycleMode() {
  const cur = currentNote();
  if (cur && cur.format === 'rich') return; // preview modes are markdown-only
  state.mode = state.mode === 'edit' ? 'preview' : state.mode === 'preview' ? 'split' : 'edit';
  const labels = { edit: '👁 Önizle', preview: '⊟ Bölünmüş', split: '✎ Düzenle' };
  $('.editor-body').dataset.mode = state.mode;
  $('#btn-mode').textContent = labels[state.mode];
  $('#btn-mode').classList.toggle('on', state.mode !== 'edit');
  if (state.mode !== 'edit') updatePreview();
}

function setTheme(theme) {
  if (theme) { document.documentElement.dataset.theme = theme; localStorage.setItem('notex.theme', theme); }
}
function toggleTheme() {
  const cur = document.documentElement.dataset.theme
    || (matchMedia('(prefers-color-scheme: dark)').matches ? 'dark' : 'light');
  setTheme(cur === 'dark' ? 'light' : 'dark');
}

// Navigate via [[title]] / {{uuid}} links inside the preview.
function handleLinkClick(e) {
  const wiki = e.target.closest('a.wikilink');
  const uuidL = e.target.closest('a.uuidlink');
  if (!wiki && !uuidL) return;
  e.preventDefault();
  let target = null;
  if (uuidL) target = state.notes.find((n) => n.id === uuidL.dataset.uuid && !n.isTrashed);
  if (wiki) {
    const name = wiki.dataset.link.toLowerCase();
    target = state.notes.find((n) => !n.isTrashed && noteTitle(n).toLowerCase() === name);
  }
  if (target) { state.view = 'all'; renderFilters(); navigateTo(target.id); }
  else if (wiki) { createNote('# ' + wiki.dataset.link + '\n\n'); } // create-on-click
}

// ── Encrypted backup file (export / import) ──
async function downloadBackup() {
  if (!vault.hasKey()) { alert('Önce giriş yap / kasayı aç.'); return; }
  const pw = prompt('Yedek parolası belirle (bu parolayla şifrelenir; geri yüklerken gerekir):');
  if (pw == null) return;
  if (pw.length < 8) { alert('Yedek parolası en az 8 karakter olmalı.'); return; }

  const data = {
    notes: state.notes,
    notebooks: state.notebooks,
    tags: state.tags,
    exportedAt: new Date().toISOString(),
  };
  const envelope = await backup.encrypt(data, pw);
  const blob = new Blob([JSON.stringify(envelope)], { type: 'application/json' });
  const a = document.createElement('a');
  a.href = URL.createObjectURL(blob);
  a.download = `notex-yedek-${new Date().toISOString().slice(0, 10)}.json`;
  document.body.appendChild(a); a.click(); a.remove();
  URL.revokeObjectURL(a.href);
}

async function restoreFromFile(file) {
  if (!file) return;
  if (!vault.hasKey()) { alert('Önce giriş yap / kasayı aç.'); return; }
  let envelope;
  try { envelope = JSON.parse(await file.text()); } catch { alert('Dosya okunamadı (geçersiz).'); return; }
  if (envelope.type !== 'encrypted-backup') { alert('Bu bir Notex yedek dosyası değil.'); return; }

  const pw = prompt('Yedek parolasını gir:');
  if (pw == null) return;
  let data;
  try { data = await backup.decrypt(envelope, pw); }
  catch { alert('Parola hatalı veya dosya bozuk.'); return; }

  let added = 0;
  // Tags + notebooks: add any that are missing (by id).
  for (const t of data.tags || []) {
    if (!state.tags.some((x) => x.id === t.id)) {
      state.tags.push(t);
      await db.put('tags', await vault.encryptObject(t.id, { name: t.name, color: t.color, createdAt: t.createdAt }));
    }
  }
  for (const nb of data.notebooks || []) {
    if (!state.notebooks.some((x) => x.id === nb.id)) {
      state.notebooks.push(nb);
      await db.put('notebooks', await vault.encryptObject(nb.id, { name: nb.name, createdAt: nb.createdAt }));
    }
  }
  // Notes: add new, or overwrite when the backup copy is newer (last-write-wins).
  for (const n of data.notes || []) {
    const local = state.notes.find((x) => x.id === n.id);
    if (!local) { state.notes.push(n); await db.put('notes', await vault.encryptNote(n)); added++; }
    else if ((n.updatedAt || 0) > (local.updatedAt || 0)) {
      Object.assign(local, n); await db.put('notes', await vault.encryptNote(local)); added++;
    }
  }

  renderSidebar();
  renderList();
  alert(`Geri yüklendi ✓ (${(data.notes || []).length} not işlendi, ${added} eklendi/güncellendi).`);
}

// ── Wiring ──
function wire() {
  $('#btn-new').addEventListener('click', () => createNote(''));
  $('#btn-fav').addEventListener('click', toggleFavorite);
  $('#btn-format').addEventListener('click', toggleFormat);
  $('#btn-mode').addEventListener('click', cycleMode);

  // Rich editor: autosave on input; toolbar keeps focus in the surface.
  $('#rich').addEventListener('input', scheduleSave);
  const tb = $('#rich-toolbar');
  tb.addEventListener('mousedown', (e) => { if (e.target.closest('button')) e.preventDefault(); });
  tb.addEventListener('click', (e) => {
    const btn = e.target.closest('button');
    if (btn) richCommand(btn);
  });
  $('#btn-trash').addEventListener('click', trashNote);
  $('#btn-restore').addEventListener('click', restoreNote);
  $('#btn-delete').addEventListener('click', deleteForever);
  $('#btn-theme').addEventListener('click', toggleTheme);
  $('#btn-lock').addEventListener('click', () => { vault.lock(); location.reload(); });
  $('#btn-backup').addEventListener('click', downloadBackup);
  $('#btn-restore-backup').addEventListener('click', () => $('#restore-file').click());
  $('#restore-file').addEventListener('change', (e) => {
    const f = e.target.files[0];
    e.target.value = '';
    restoreFromFile(f);
  });

  $('#title').addEventListener('input', scheduleSave);
  $('#body').addEventListener('input', scheduleSave);
  $('#preview').addEventListener('click', handleLinkClick);

  $('#search').addEventListener('input', (e) => { state.query = e.target.value; renderList(); });

  document.querySelectorAll('.filter').forEach((b) =>
    b.addEventListener('click', () => setView(b.dataset.view)));

  // Notebooks & tags
  $('#add-notebook').addEventListener('click', createNotebook);
  $('#add-tag').addEventListener('click', createTag);
  $('#note-notebook').addEventListener('change', (e) => setNoteNotebook(e.target.value));
  $('#add-note-tag').addEventListener('click', addTagToCurrentNote);

  document.addEventListener('keydown', (e) => {
    const mod = e.metaKey || e.ctrlKey;
    if (mod && e.key.toLowerCase() === 'n') { e.preventDefault(); createNote(''); }
    else if (mod && e.key.toLowerCase() === 'f') { e.preventDefault(); $('#search').focus(); }
    else if (mod && e.key.toLowerCase() === 'e') { e.preventDefault(); cycleMode(); }
    else if (mod && e.key.toLowerCase() === 's') { e.preventDefault(); /* autosave already */ }
  });
}

// ── Boot ──
const WELCOME = `# Notex'e hoş geldiniz 👋

Bu, **local-first** bir web not uygulaması. Notlarınız yalnızca bu cihazın
tarayıcısında (IndexedDB) saklanır — sunucu yok, takip yok.

## Hızlı başlangıç
- **⌘/Ctrl + N** ile yeni not
- **⌘/Ctrl + F** ile ara
- **⌘/Ctrl + E** ile önizleme/bölünmüş görünüm
- Markdown yazın: **kalın**, *italik*, \`kod\`
- Görev listesi:
  - [x] İlk notu oluştur
  - [ ] GitHub senkronunu bekle
- Not bağlama: [[Notex'e hoş geldiniz 👋]]

> Ana macOS uygulamasındaki notlarınızı yedekten (Markdown) buraya taşıyabilirsiniz.
`;

async function main() {
  document.getElementById('lock').style.display = 'none';
  document.getElementById('app').hidden = false;
  wire();
  await loadAll();
  renderFilters();
  renderSidebar();
  renderList();
  const first = visibleNotes()[0];
  if (first) selectNote(first.id);
}

// ── Lock screen (master-password gate) ──
function showLock() {
  const setup = !vault.exists();
  $('#lock-sub').textContent = setup
    ? 'İlk kez: kasanız için bir ana parola oluşturun.'
    : 'Kasanızı açmak için ana parolanızı girin.';
  $('#lock-pass2').hidden = !setup;
  $('#lock-warn').hidden = !setup;
  $('#lock-btn').textContent = setup ? 'Kasayı Oluştur' : 'Aç';
  $('#lock').style.display = 'flex';
  $('#lock-pass').focus();
}

async function attemptUnlock(e) {
  if (e) e.preventDefault();
  const setup = !vault.exists();
  const pass = $('#lock-pass').value;
  const err = $('#lock-err');
  const btn = $('#lock-btn');
  err.textContent = '';

  // Validate before the (deliberately slow) key derivation.
  if (setup) {
    if (pass.length < 6) { err.textContent = 'Parola en az 6 karakter olmalı.'; return; }
    if (pass !== $('#lock-pass2').value) { err.textContent = 'Parolalar eşleşmiyor.'; return; }
  }

  const label = btn.textContent;
  btn.disabled = true;
  btn.textContent = setup ? 'Oluşturuluyor…' : 'Açılıyor…';
  try {
    if (setup) {
      await vault.setup(pass);
    } else {
      const ok = await vault.unlock(pass);
      if (!ok) { err.textContent = 'Hatalı parola.'; $('#lock-pass').select(); return; }
    }
    $('#lock-pass').value = ''; $('#lock-pass2').value = '';
    await main();
  } catch (ex) {
    err.textContent = 'Bir hata oluştu: ' + (ex && ex.message ? ex.message : ex);
  } finally {
    btn.disabled = false;
    btn.textContent = label;
  }
}

// ── Encryption-key cache (ask the 2nd password only periodically) ──
const KEY_CACHE_DAYS = 30;
async function cacheEncKey(email, key) {
  try {
    const keyB64 = await cloud.exportKeyB64(key);
    localStorage.setItem('notex.keyCache', JSON.stringify({
      email, keyB64, expiresAt: Date.now() + KEY_CACHE_DAYS * 86400000,
    }));
  } catch { /* caching is best-effort */ }
}
async function getCachedKey(email) {
  try {
    const c = JSON.parse(localStorage.getItem('notex.keyCache') || 'null');
    if (!c || c.email !== email || Date.now() > c.expiresAt) return null;
    return await cloud.importKeyB64(c.keyB64);
  } catch { return null; }
}
function clearKeyCache() { localStorage.removeItem('notex.keyCache'); }

// ── Cloud account: recoverable login (account password) + encryption password ──
function setAuthMode(mode) {
  authMode = mode;
  $('#tab-login').classList.toggle('active', mode === 'login');
  $('#tab-register').classList.toggle('active', mode === 'register');
  $('#auth-enc2').hidden = mode !== 'register';
  $('#auth-warn').hidden = mode !== 'register';
  $('#auth-btn').textContent = mode === 'register' ? 'Kayıt Ol' : 'Giriş Yap';
  $('#auth-enc').placeholder = mode === 'register'
    ? 'Şifreleme parolası (notları korur)'
    : 'Şifreleme parolası (ilk giriş / periyodik)';
  const msg = $('#auth-msg'); msg.textContent = ''; msg.classList.remove('ok');
}

async function submitAuth(e) {
  if (e) e.preventDefault();
  const email = $('#auth-email').value.trim();
  const accountPass = $('#auth-pass').value;
  const encPass = $('#auth-enc').value;
  const msg = $('#auth-msg');
  const btn = $('#auth-btn');
  msg.textContent = ''; msg.classList.remove('ok');

  if (!/.+@.+\..+/.test(email)) { msg.textContent = 'Geçerli bir e-posta girin.'; return; }
  if (accountPass.length < 6) { msg.textContent = 'Hesap parolası en az 6 karakter olmalı.'; return; }
  if (encPass.length < 8) { msg.textContent = 'Şifreleme parolası en az 8 karakter olmalı.'; return; }
  if (authMode === 'register' && encPass !== $('#auth-enc2').value) {
    msg.textContent = 'Şifreleme parolaları eşleşmiyor.'; return;
  }

  const label = btn.textContent;
  btn.disabled = true;
  btn.textContent = authMode === 'register' ? 'Kayıt olunuyor…' : 'Giriş yapılıyor…';
  try {
    if (authMode === 'register') {
      const r = await cloud.signup(email, accountPass, encPass);
      if (!r.ok) { msg.textContent = r.error; return; }
      if (r.needsConfirm) {
        msg.classList.add('ok');
        msg.textContent = '✓ Onay e-postası gönderildi. E-postanı onayla, sonra giriş yap.';
        setAuthMode('login');
        return;
      }
      await enterCloud({ token: r.token, userId: r.userId, email, encKey: r.encKey });
    } else {
      const r = await cloud.login(email, accountPass);
      if (!r.ok) {
        msg.textContent = /confirm/i.test(r.error)
          ? 'Önce e-postanı onaylaman gerekiyor (gelen kutunu kontrol et).'
          : r.error;
        return;
      }
      // Periodic 2nd password: reuse the on-device cached key while it's valid.
      let encKey = await getCachedKey(email);
      if (!encKey) {
        if (!encPass) { msg.textContent = 'Şifreleme parolası gerekli (ilk giriş veya süre doldu).'; return; }
        encKey = await cloud.unlockEnc(encPass, r.encSalt, r.encVerifier);
        if (!encKey) { msg.textContent = 'Şifreleme parolası hatalı.'; return; }
      }
      await enterCloud({ token: r.token, userId: r.userId, email, encKey });
    }
  } catch (ex) {
    msg.textContent = 'Hata: ' + (ex && ex.message ? ex.message : ex);
  } finally {
    btn.disabled = false;
    btn.textContent = label;
  }
}

async function forgotPassword() {
  const email = $('#auth-email').value.trim();
  const msg = $('#auth-msg');
  if (!/.+@.+\..+/.test(email)) { msg.textContent = 'Önce e-posta alanına adresini yaz.'; return; }
  await cloud.requestPasswordReset(email);
  msg.classList.add('ok');
  msg.textContent = '✓ Sıfırlama bağlantısı gönderildi (varsa). Not: yeni hesap parolasıyla girersin, şifreleme parolan değişmez.';
}

async function enterCloud({ token, userId, email, encKey }) {
  cloudSession = { token, userId, email };
  localStorage.setItem('notex.lastEmail', email);
  await cacheEncKey(email, encKey); // remember the key so the 2nd password is periodic
  vault.setKey(encKey);
  $('#auth-pass').value = ''; $('#auth-enc').value = ''; $('#auth-enc2').value = '';
  await main();
  // Encrypted sync (pull + push) is wired in the next step.
}

function boot() {
  // Local-only vault wiring (existing)
  $('#lock-form').addEventListener('submit', attemptUnlock);
  // Cloud auth wiring
  $('#tab-login').addEventListener('click', () => setAuthMode('login'));
  $('#tab-register').addEventListener('click', () => setAuthMode('register'));
  $('#auth-form').addEventListener('submit', submitAuth);
  $('#forgot-pass').addEventListener('click', (e) => { e.preventDefault(); forgotPassword(); });
  $('#use-local').addEventListener('click', (e) => {
    e.preventDefault();
    $('#auth-cloud').hidden = true; $('#auth-local').hidden = false; showLock();
  });
  $('#use-cloud').addEventListener('click', (e) => {
    e.preventDefault();
    $('#auth-local').hidden = true; $('#auth-cloud').hidden = false; $('#auth-email').focus();
  });

  // Cloud login is the default screen.
  setAuthMode('login');
  const lastEmail = localStorage.getItem('notex.lastEmail');
  if (lastEmail) $('#auth-email').value = lastEmail;
  $('#lock').style.display = 'flex';
  ($('#auth-email').value ? $('#auth-pass') : $('#auth-email')).focus();
}

boot();
