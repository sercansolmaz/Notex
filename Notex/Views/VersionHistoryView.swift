import SwiftUI

/// Sheet showing a note's version history: list on the left,
/// preview on the right, with a "Geri Yükle" (Restore) button.
struct VersionHistoryView: View {
    let noteUUID: String
    let noteTitle: String
    var onRestore: () -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var themeManager: ThemeManager

    @State private var snapshots: [VersionHistoryService.Snapshot] = []
    @State private var selected: VersionHistoryService.Snapshot?
    @State private var restoreStatus: String = ""

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Sürüm Geçmişi")
                        .font(.system(size: 16, weight: .bold))
                    Text(noteTitle)
                        .font(.system(size: 12))
                        .foregroundColor(themeManager.secondaryText)
                        .lineLimit(1)
                }
                Spacer()
                Button("Kapat") { dismiss() }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            // Content
            HStack(spacing: 0) {
                // Version list
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(snapshots.reversed(), id: \.timestamp) { snap in
                            versionRow(snap)
                        }
                        if snapshots.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 32))
                                    .foregroundColor(themeManager.secondaryText)
                                Text("Henüz sürüm yok")
                                    .font(.system(size: 12))
                                    .foregroundColor(themeManager.secondaryText)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 40)
                        }
                    }
                }
                .frame(width: 260)

                Divider()

                // Preview
                VStack(alignment: .leading, spacing: 8) {
                    if let snap = selected {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDate(snap.date))
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryText)
                            Text(snap.title)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .padding(.horizontal, 16)
                        .padding(.top, 12)

                        Divider()

                        ScrollView {
                            Text(snap.plainText)
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.textColor)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(16)
                                .textSelection(.enabled)
                        }

                        Divider()

                        HStack {
                            if !restoreStatus.isEmpty {
                                Text(restoreStatus)
                                    .font(.system(size: 11))
                                    .foregroundColor(themeManager.secondaryText)
                            }
                            Spacer()
                            Button("Geri Yükle") { restoreSelected() }
                                .buttonStyle(.borderedProminent)
                                .tint(themeManager.accentColor)
                                .disabled(selected == nil)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    } else {
                        VStack(spacing: 8) {
                            Image(systemName: "doc.text")
                                .font(.system(size: 32))
                                .foregroundColor(themeManager.secondaryText)
                            Text("Bir sürüm seçin")
                                .font(.system(size: 12))
                                .foregroundColor(themeManager.secondaryText)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(width: 680, height: 440)
        .onAppear { loadSnapshots() }
    }

    // MARK: - Row

    @ViewBuilder
    private func versionRow(_ snap: VersionHistoryService.Snapshot) -> some View {
        let active = selected?.timestamp == snap.timestamp
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10))
                    .foregroundColor(active ? themeManager.accentColor : themeManager.secondaryText)
                Text(formatDate(snap.date))
                    .font(.system(size: 11, weight: active ? .semibold : .regular))
                    .foregroundColor(themeManager.textColor)
                Spacer()
            }
            Text(snap.title.isEmpty ? "Başlıksız" : snap.title)
                .font(.system(size: 12))
                .foregroundColor(themeManager.textColor)
                .lineLimit(1)
            Text(snap.plainText.prefix(80))
                .font(.system(size: 10))
                .foregroundColor(themeManager.secondaryText)
                .lineLimit(2)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(active ? themeManager.accentColor.opacity(0.12) : Color.clear)
        .contentShape(Rectangle())
        .onTapGesture { selected = snap }
        .overlay(alignment: .bottom) {
            if snap.timestamp != snapshots.last?.timestamp {
                Divider().opacity(0.3)
            }
        }
    }

    // MARK: - Actions

    private func loadSnapshots() {
        snapshots = VersionHistoryService.shared.loadSnapshots(for: noteUUID)
        selected = snapshots.last
    }

    private func restoreSelected() {
        guard let snap = selected else { return }
        let ok = VersionHistoryService.shared.restoreSnapshot(
            uuid: noteUUID, timestamp: snap.timestamp, context: viewContext)
        if ok {
            restoreStatus = "Geri yüklendi"
            onRestore()
            dismiss()
        } else {
            restoreStatus = "Geri yükleme başarısız"
        }
    }

    private func formatDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "tr_TR")
        f.dateStyle = .medium
        f.timeStyle = .short
        return f.string(from: date)
    }
}
