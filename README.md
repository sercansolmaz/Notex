# Notex 📝

macOS için modern, yerel-öncelikli (local-first) not alma uygulaması. Swift 6 + SwiftUI + Core Data ile geliştirildi.

## Özellikler

### Editör
- 📝 Zengin metin editörü (bold, italic, underline, strikethrough)
- ✅ Tıklanabilir checkbox'lar (☐/☑)
- 🖍️ 6 renkli vurgu (highlight)
- 💬 Alıntı bloğu + kod bloğu
- 📊 Tablo ekleme (satır/sütun)
- ⌨️ Markdown kısayolları (`## ` → H2, `- [ ] ` → checkbox)
- 🔍 Bul & Değiştir (⌘F)
- 🔗 `[[wiki-link]]` ile notlar arası bağlantı + backlinks
- 📎 Dosya ekleme (JPG/PNG/PDF) + önizleme + OCR
- 📄 PDF önizleme (PDFKit)

### Organizasyon
- 📁 İç içe defterler + yığın (stack) desteği
- 🏷️ Renkli etiketler (sıralanabilir, not sayısı gösterilir)
- 📌 Pin'leme (önemli notlar üstte)
- ⭐ Favoriler
- 📦 Arşiv
- 🗑️ Çöp kutusu (geri yükleme + 30 gün otomatik temizlik)

### Görünüm
- 🌓 4 tema modu: Otomatik / Gündüz / Gece / Sepia
- 📋 Grid / Liste görünümü
- 🎯 Odak modu (⌘⇧F) — sadece yazı görünür
- ✨ Açılış logosu (splash screen)
- 🪟 Çoklu pencere (çift tık → ayrı pencere)

### Arama
- 🔍 FTS5 tam metin arama
- 🟡 Arama sonuçlarında highlight
- 📊 Canlı arama (debounced)

### İçe / Dışa Aktarma
- 📥 Apple Notes'tan içe aktarma (JXA ile, ilerleme göstergeli)
- 📥 Evernote (.enex) içe aktarma (defter bazında)
- 📥 Markdown / TXT toplu içe aktarma
- 📥 Sürükle-bırak import zone
- 📤 PDF / RTF (Word) / HTML / Markdown dışa aktarma
- 💾 Otomatik yedekleme (iCloud / Dropbox / Google Drive / lokal)

### Yönetim
- ✓ Çoklu seçim + toplu sil/geri yükle
- 📋 Not şablonları (Toplantı, Günlük, Yapılacaklar, Proje)
- 🕐 Sürüm geçmişi + geri yükleme
- ↕️ Sıralama (tarih/oluşturulma/alfabe/boyut)
- 🧹 İlişkisiz etiket temizleme
- 📤 macOS Share Sheet ile paylaşma

## Teknoloji Yığını

| Bileşen | Teknoloji |
|---------|-----------|
| Dil | Swift 6 |
| UI Framework | SwiftUI |
| Editör | NSTextView (AppKit) |
| Veritabanı | Core Data (NSPersistentContainer) |
| Arama | SQLite FTS5 |
| PDF | PDFKit |
| OCR | Vision Framework |
| Proje Yönetimi | xcodegen |

## Gereksinimler

- macOS 14.0+
- Xcode 16+
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Kurulum

```bash
# Repository'yi klonla
git clone https://github.com/sercansolmaz/Notex.git
cd Notex

# Xcode projesini oluştur
xcodegen generate

# Derle ve çalıştır
xcodebuild -project Notex.xcodeproj -scheme Notex -configuration Debug build
open ~/Library/Developer/Xcode/DerivedData/Notex-*/Build/Products/Debug/Notex.app
```

## Klavye Kısayolları

| Kısayol | Eylem |
|---------|-------|
| ⌘N | Yeni Not (şablon seçici) |
| ⌘B | Kalın |
| ⌘I | İtalik |
| ⌘U | Altı Çizili |
| ⌘F | Bul |
| ⌥⌘F | Bul ve Değiştir |
| ⌘⇧F | Odak Modu |
| ⌘⇧T | Tema Değiştir |
| ⌘⇧N | Yeni Defter |

## Lisans

© 2026 Sercan Solmaz. Tüm hakları saklıdır.
