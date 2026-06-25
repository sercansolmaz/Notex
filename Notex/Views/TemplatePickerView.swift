import SwiftUI

// MARK: - NoteTemplate

/// Built-in note templates (user-facing text in Turkish).
enum NoteTemplate: String, CaseIterable, Identifiable {
    case empty = "Boş Not"
    case meeting = "Toplantı Notu"
    case journal = "Günlük"
    case todo = "Yapılacaklar"
    case project = "Proje Planı"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .empty: return "doc.text"
        case .meeting: return "person.3"
        case .journal: return "book"
        case .todo: return "checklist"
        case .project: return "rectangle.3.group"
        }
    }

    var subtitle: String {
        switch self {
        case .empty: return "Boş bir notla başla"
        case .meeting: return "Tarih, yer, gündem, aksiyonlar"
        case .journal: return "Günlük düşünceler ve planlar"
        case .todo: return "Bugün ve bu hafta yapılacaklar"
        case .project: return "Hedef, süreç, deadline"
        }
    }

    /// Pre-filled content for the template. Journal inserts today's date.
    var content: String {
        switch self {
        case .empty:
            return ""
        case .meeting:
            return "📅 Tarih:\n📍 Yer:\n👥 Katılımcılar:\n\n📋 Gündem:\n\n📝 Notlar:\n\n✓ Aksiyon Maddeleri:\n☐ \n☐ \n"
        case .journal:
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "tr_TR")
            formatter.dateStyle = .long
            let today = formatter.string(from: Date())
            return "📅 \(today)\n\nDüşünceler:\n\nBugün yapılanlar:\n☐ \n\nYarın için:\n☐ \n"
        case .todo:
            return "Bugün:\n☐ \n☐ \n☐ \n\nBu Hafta:\n☐ \n☐ \n"
        case .project:
            return "Hedef:\n\nSüreç:\n1. \n2. \n3. \n\nDeadline:\n\nNotlar:\n"
        }
    }
}

// MARK: - TemplatePickerView

/// Sheet that lets the user choose a template when creating a new note.
struct TemplatePickerView: View {
    /// Called with the chosen template (`.empty` = blank note).
    let onSelect: (NoteTemplate) -> Void
    /// Called when the user cancels the sheet.
    let onCancel: () -> Void

    @EnvironmentObject private var themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Yeni Not")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(themeManager.textColor)
                    Text("Bir şablon seçin")
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.secondaryText)
                }
                Spacer()
                Button {
                    onCancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18))
                        .foregroundColor(themeManager.secondaryText)
                }
                .buttonStyle(.plain)
                .help("İptal")
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 12)

            Divider()

            // Template grid
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(NoteTemplate.allCases) { template in
                        templateCard(template)
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 460, height: 420)
        .background(themeManager.backgroundColor)
    }

    // MARK: - Card

    @ViewBuilder
    private func templateCard(_ template: NoteTemplate) -> some View {
        Button {
            onSelect(template)
        } label: {
            VStack(spacing: 10) {
                ZStack {
                    Circle()
                        .fill(themeManager.accentColor.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Image(systemName: template.iconName)
                        .font(.system(size: 19))
                        .foregroundColor(themeManager.accentColor)
                }

                Text(template.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(themeManager.textColor)

                Text(template.subtitle)
                    .font(.system(size: 10))
                    .foregroundColor(themeManager.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 18)
            .background(themeManager.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(themeManager.accentColor.opacity(0.18), lineWidth: 1)
            )
            .cornerRadius(12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
