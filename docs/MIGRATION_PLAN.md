# Notex — Native macOS → Local-First Web/PWA Göç Planı

> Durum: **Taslak / karar bekliyor**
> Hedef: Tek geliştirici tarafından sürdürülebilir, her platformdan erişilebilen,
> local-first (veri kullanıcıda) bir Notex. Karar verilen yön: **önce bu plan**.
> Kesinleşen özellik: **GitHub repo senkronizasyonu**.

---

## 1. Karar Çerçevesi

| Hedef | Native macOS bugün | Local-first Web/PWA |
|---|---|---|
| Platform erişimi | Yalnız Mac | Tarayıcı + kurulabilir PWA (mobil/masaüstü) + opsiyonel Tauri |
| Solo-dev maliyeti | Her platform ayrı native = sürdürülemez | **Tek kod tabanı** |
| Veri sahipliği | Local (Core Data) | Local (IndexedDB) + opsiyonel GitHub senkron |
| Gizlilik | Yüksek | Yüksek (sunucu notları görmez) |
| "Online erişim" | Yok | URL + PWA + GitHub üzerinden her cihaz |

**Sonuç:** Web/PWA pivotu, belirtilen iki hedefi de karşılayan tek tutarlı yol.
"Online" = **sunucu-merkezli SaaS değil**, local-first web + opsiyonel senkron.

---

## 2. Ne Taşınır, Ne Yeniden Yazılır

Mevcut ~7.500 satır Swift'in **kodu** taşınmaz; ama **tasarımı ve mantığı**
(spesifikasyon olarak) doğrudan taşınır. Aşağıdaki tablo her modülün kaderini gösterir.

| Mevcut Swift modülü | Kader | Web karşılığı |
|---|---|---|
| `Models/*` (Note, Notebook, Tag, NoteLink, NoteTag) | ♻️ Spec taşınır | TypeScript arabirimleri + Dexie (IndexedDB) şeması |
| `PersistenceController` (Core Data) | 🔁 Yeniden yaz | Dexie.js (IndexedDB) |
| `FTS5Manager` (SQLite FTS5) | 🔁 Yeniden yaz | FlexSearch/MiniSearch **veya** SQLite-WASM (FTS5 bilgisi birebir taşınır) |
| `BacklinkService` (`[[ ]]` / `{{uuid}}`) | ♻️ Regex taşınır | TS reimplementasyon |
| `VersionHistoryService` (JSON snapshot) | ♻️ Mantık taşınır | IndexedDB `versions` tablosu |
| `BackupService` (Markdown + manifest) | ⭐ **Göç köprüsü** | Aynı format = web import girişi |
| `ImportService` / `ENEXParser` / `ENMLConverter` | 🔁 Yeniden yaz (**daha kolay**) | `DOMParser` + Readability — regex hack'leri gerekmez |
| `WebClipperService` | 🔁 Yeniden yaz (⚠️ CORS) | `fetch` + `DOMParser`; tarayıcıda CORS engeli → Tauri/proxy gerekir |
| Editör (`NSTextView` zengin metin) | 🔁 Yeniden yaz (**felsefi değişim**) | CodeMirror 6 (plain-text/Markdown) |
| `ExportService` (PDF/RTF/HTML/MD) | 🔁 Yeniden yaz | MD native, HTML kolay, PDF=pdf-lib/print, RTF=opsiyonel |
| `AttachmentService` + Vision OCR | 🔁 Yeniden yaz | Blob → IndexedDB; OCR=Tesseract.js (opsiyonel, ağır) |
| `PDFService` (PDFKit) | 🔁 Yeniden yaz | pdf.js |
| Apple Notes importer (JXA, Python) | 🖥️ Masaüstü-only | Tek seferlik CLI/Tauri yardımcı olarak kalır |

**Kilit içgörü:** `content` alanı bugün arşivlenmiş `NSAttributedString` (ikili, zengin).
Plain-text/Markdown modelinde `content` **düz Markdown string** olur →
daha basit, git-diff'lenebilir, GitHub senkronuna doğrudan uygun. Bu bir *sadeleşme*.

---

## 3. Önerilen Teknoloji Yığını

| Katman | Öneri | Gerekçe |
|---|---|---|
| Çatı | **React + TypeScript** (alternatif: Svelte 5) | TakeNote ile aynı çizgi; geniş ekosistem |
| Durum | Zustand | Redux'tan hafif |
| Editör | **CodeMirror 6** | multi-cursor, Markdown modu, New Moon teması, kısayollar |
| Depolama | **Dexie.js (IndexedDB)** | localStorage'ın aksine GB ölçeği, indeksli sorgu |
| Arama | FlexSearch/MiniSearch (basit) **veya** SQLite-WASM+FTS5 (ileri) | FTS5 semantiğimizi birebir koruma seçeneği |
| Markdown | markdown-it (önizleme) + Prettier/standalone (formatla) | İstenen "Markdown preview + Prettify" |
| Paketleme | Vite + `vite-plugin-pwa` | Offline + kurulabilir PWA |
| Masaüstü (ops.) | **Tauri** (~3–10 MB) | Aynı web build → macOS/Win/Linux; ayrıca **CORS'suz web clipper** ve dosya erişimi |
| Senkron | **Octokit** (GitHub REST) veya isomorphic-git | Sunucu yok |

---

## 4. Veri Modeli Eşlemesi (Core Data → TS / Dexie)

```ts
interface Note {
  id: string;            // uuid (mevcut Note.uuid)
  title: string;
  content: string;       // Markdown (eski: arşivli NSAttributedString) — SADELEŞME
  notebookId?: string;
  tagIds: string[];
  isPinned: boolean;
  isFavorite: boolean;
  isArchived: boolean;
  isTrashed: boolean;
  createdAt: number;     // epoch ms
  updatedAt: number;
}

interface Notebook {
  id: string;
  name: string;
  parentId?: string;     // iç içe defter / yığın (mevcut parent/children)
  icon?: string;
  createdAt: number; updatedAt: number;
}

interface Tag { id: string; name: string; color: string; createdAt: number; }

// NoteLink türetilir: content içindeki {{uuid}} / [[başlık]] ayrıştırılarak hesaplanır.
interface NoteVersion { id: string; noteId: string; date: number; title: string; content: string; }
```

```ts
// Dexie şeması
db.version(1).stores({
  notes:     'id, notebookId, updatedAt, isTrashed, isArchived, isFavorite, isPinned, *tagIds',
  notebooks: 'id, parentId, name',
  tags:      'id, name',
  versions:  'id, noteId, date',
});
```

Mevcut Core Data `deletionRule` davranışları korunur: defter silinince notlar **çöpe**
taşınır (bu turda native tarafta uyguladığımız güvenli akışın aynısı).

---

## 5. GitHub Senkronizasyon Mimarisi (kesinleşen özellik)

**Format — her not = bir Markdown dosyası (YAML frontmatter ile):**

```
repo/
  notebooks/<defter-adı>/<uuid>.md
  notes/<uuid>.md            # deftersiz notlar
```

```md
---
id: 7c1f...­
title: Toplantı Notları
notebook: Proje X
tags: [iş, toplantı]
created: 2026-06-25T10:00:00Z
updated: 2026-06-25T11:30:00Z
favorite: false
---

# Toplantı Notları
İçerik buraya... {{uuid-of-another-note}}
```

Bu format Obsidian/Logseq ile de uyumlu (kaçış / vendor lock-in yok).

**Senkron motoru (aşamalı):**
1. **Kimlik:** Fine-grained GitHub PAT (en basit) veya OAuth device-flow.
2. **Pull:** repo ağacını çek → dosya SHA'larını yerel `updatedAt` ile karşılaştır.
3. **Push:** değişen dosyaları commit'le (Octokit `contents` API).
4. **Çakışma çözümü (zor kısım, en sona):**
   - V1: `updatedAt` ile **last-write-wins** + çakışmada `<uuid>.conflict.md` koru (veri kaybı yok).
   - V2: isomorphic-git ile 3-yönlü birleştirme.
5. **Tetikleme:** manuel + aralıklı + değişiklikte debounce.

**Kazanımlar:** online erişim + her cihaz + otomatik yedek + **git tabanlı sürüm
geçmişi** (mevcut snapshot servisini büyük ölçüde gereksizleştirir) + sıfır sunucu maliyeti.
**Mahremiyet:** private repo; veri senin sunucundan hiç geçmez.
**Uyarı:** Saf tarayıcıda Octokit REST CORS'a takılmaz; ama isomorphic-git `clone`
için proxy ister → Octokit `contents` API ile başla.

---

## 6. Özellik Parite Matrisi (mevcut Notex → web)

| Mevcut özellik | Web planı | Faz |
|---|---|---|
| Not/defter/etiket CRUD | Dexie + React | 1 |
| İç içe defter + yığın | `parentId` ağacı | 1 |
| Çöp kutusu + geri yükleme + 30g temizlik | `isTrashed` + zamanlayıcı | 1 |
| Pin / favori / arşiv | bool alanlar | 1 |
| FTS arama + canlı arama | FlexSearch/SQLite-WASM | 1 |
| Markdown editör | CodeMirror 6 | 1 |
| Markdown önizleme | markdown-it | 2 |
| `[[ ]]` / `{{uuid}}` bağlantı + backlinks | TS parser | 2 |
| Sürüm geçmişi | IndexedDB `versions` (+ ileride git) | 2 |
| Kısayollar / drag-drop (favori/çöp) | CodeMirror + dnd-kit | 2 |
| Multi-cursor / syntax highlight / Prettier | CodeMirror 6 native | 2 |
| Tema (gündüz/gece/New Moon) | CSS değişkenleri + CM teması | 2 |
| **GitHub senkron** | Octokit + .md/frontmatter | **3** |
| Dışa aktarma (MD/HTML/PDF) | native/markdown-it/pdf-lib | 3 |
| ENEX / Markdown / TXT / HTML import | `DOMParser` | 3 |
| Web clipper | fetch+Readability (Tauri/proxy) | 4 |
| OCR / PDF önizleme | Tesseract.js / pdf.js (opsiyonel) | 4 |
| **Mevcut Notex notlarını taşıma** | `BackupService` MD export → import | **5** |

---

## 7. Aşamalı Yol Haritası

- **Faz 0 — İskelet:** Vite + React/TS + Dexie + CodeMirror skeleton; veri modeli + Dexie şeması; CI/PWA temel.
- **Faz 1 — Çekirdek local-first MVP:** Not/defter/etiket CRUD, iç içe defter, çöp kutusu, pin/favori/arşiv, Markdown editör, FTS arama. *(Günlük kullanılabilir parite.)*
- **Faz 2 — Güç özellikleri:** Markdown önizleme, backlinks (`[[ ]]`/`{{uuid}}`), sürüm geçmişi, kısayollar, drag-drop (favori/çöp), multi-cursor, Prettier, temalar (New Moon).
- **Faz 3 — GitHub senkron (istenen):** dosya formatı + push/pull + LWW çakışma + dışa/içe aktarma.
- **Faz 4 — Dağıtım & ekstralar:** PWA cilası (offline/install), Tauri masaüstü paketleri, web clipper (Tauri/proxy ile), opsiyonel OCR.
- **Faz 5 — Veri köprüsü:** Mevcut macOS Notex'ten `BackupService` ile Markdown export → web'e import (kullanıcının notları kaybolmaz).

**Akıllı sıralama:** Faz 5 köprüsü `BackupService` zaten hazır olduğundan **Faz 1
biter bitmez** test edilebilir; böylece kendi notlarınla erken dogfooding yapılır.

---

## 8. Kabaca Eforlandırma (göreli)

Saat sözü vermeden, göreli büyüklük: **Faz 1 ≈ projenin %35'i** (kritik kütle),
Faz 2 ≈ %25, Faz 3 (senkron) ≈ %20 (çakışma çözümü en riskli), Faz 4 ≈ %15,
Faz 5 ≈ %5. Solo-dev için **Faz 1+3** ilk değer dilimidir (kullanılabilir + senkronlu).

---

## 9. Riskler ve Ödünleşmeler

| Risk | Etki | Azaltma |
|---|---|---|
| Native cila kaybı (zengin metin, OCR, PDFKit, Share Sheet) | Orta | Markdown'a geçiş bilinçli tercih; eksikler Tauri/JS lib ile kapatılır |
| Web clipper CORS | Orta | Tauri native fetch veya küçük proxy; tarayıcı-only sürümde sınırlı |
| Senkron çakışma karmaşıklığı | Yüksek | V1 last-write-wins + `.conflict` kopya (veri kaybı yok), git'i sonraya bırak |
| Zengin not → Markdown dönüşümü kayıplı (tablo/inline görsel) | Orta | Köprüde HTML→MD (turndown) + ekleri ayrı dosya olarak taşı |
| Tarayıcı depolama tahliyesi/limit | Düşük-Orta | `navigator.storage.persist()` + GitHub senkron = yedek |

---

## 10. Öneri ve Sonraki Adım

**Öneri:** Bu planı onayla → **Faz 0 + Faz 1 iskeleti** ile başlayalım
(Vite/React/TS/Dexie/CodeMirror + temel CRUD + Markdown editör + arama).
GitHub senkronu (Faz 3) erken bir dikey dilim olarak da öne çekilebilir,
çünkü senin asıl "online erişim" ihtiyacını o karşılıyor.

**Açık kararlar (başlamadan netleştirilecek):**
1. Çatı: React mı, Svelte mi?
2. Arama: basit (FlexSearch) mı, FTS5-WASM (mevcut bilgiyi koru) mu?
3. Masaüstü paketi (Tauri) ilk sürümde mi, sonra mı?
4. Senkron kimliği: PAT (hızlı) mı, OAuth device-flow (cilalı) mı?
