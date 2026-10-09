import SwiftUI

// MARK: - Общие детали

/// Действия над приложением магазина (правый клик по строке).
struct AppActionsMenu: View {
    var app: ListEntry
    @Environment(AppModel.self) private var model

    var body: some View {
        Button("Скачать") { model.enqueue(app) }
        Button("Получить без загрузки") { Task { await model.purchase([app]) } }
        Divider()
        Button("Скопировать ID") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(app.id, forType: .string)
        }
        Button("Открыть в App Store") {
            NSWorkspace.shared.open(URL(string: "https://apps.apple.com/app/id\(app.id)")!)
        }
    }
}

/// Строка приложения: иконка, название, подпись и кнопка загрузки.
struct AppRow: View {
    var app: ListEntry
    var detail: String?
    @Environment(AppModel.self) private var model

    private var isDownloaded: Bool { model.myDownloaded.contains { $0.id == app.id } }

    var body: some View {
        HStack(spacing: 12) {
            AppIcon(id: app.id, name: app.name, size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text(app.name).font(.system(size: 15, weight: .medium)).lineLimit(1)
                if let detail, !detail.isEmpty {
                    Text(detail).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            Spacer(minLength: 6)
            if isDownloaded {
                Image(systemName: "checkmark").font(.caption).foregroundStyle(.tertiary).toolTip("Уже скачивали")
            }
            RowCapsule {
                Button { model.enqueue(app) } label: { Label("Скачать", systemImage: "arrow.down") }
                    .toolTip("Скачать последнюю версию")
            }
        }
        .padding(.vertical, 5)
        .contextMenu { AppActionsMenu(app: app) }
    }
}

// MARK: - Поиск

struct SearchView: View {
    @Environment(AppModel.self) private var model
    @State private var art = Artwork.shared
    @State private var query = ""
    @State private var lastQuery = ""
    @State private var results: [StoreApp] = []
    @State private var searching = false
    @State private var error: String?

    var body: some View {
        VStack(spacing: 0) {
            // Поле всегда на одном месте в иерархии — иначе при появлении
            // результатов оно пересоздаётся и теряет фокус посреди набора.
            if results.isEmpty { Spacer() }
            field
                .frame(maxWidth: results.isEmpty ? 460 : .infinity)
                .padding(.horizontal, 14).padding(.vertical, 10)
            if results.isEmpty {
                status
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(minHeight: 44)
                Spacer()
                warning
            } else {
                Divider()
                List(results) { app in
                    AppRow(app: entry(app), detail: detail(app, art.byID[app.id]))
                }
            }
        }
        .animation(.smooth(duration: 0.3), value: results.isEmpty)
        // Поиск сам запускается, когда набор затих.
        .task(id: query) {
            guard query.trimmingCharacters(in: .whitespaces).count >= 2 else {
                if query.isEmpty { results = []; error = nil; lastQuery = "" }
                return
            }
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            await search(force: false)
        }
    }

    private var field: some View {
        SearchField(text: $query, prompt: "Название или ID", autofocus: true) {
            Task { await search(force: true) }
        }
    }

    @ViewBuilder private var status: some View {
        if searching {
            ProgressView().controlSize(.small)
        } else if let error {
            Text(error)
        } else if !lastQuery.isEmpty, lastQuery == query.trimmingCharacters(in: .whitespaces) {
            Text("Ничего не найдено")
        } else {
            Text(" ")
        }
    }

    @ViewBuilder private var warning: some View {
        if !model.warning.isEmpty {
            Text(model.warning)
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.bottom, 14)
        }
    }

    private func entry(_ app: StoreApp) -> ListEntry {
        ListEntry(id: app.id, name: model.displayName(for: app.id) ?? app.name)
    }

    private func detail(_ app: StoreApp, _ info: Artwork.Info?) -> String {
        let version = app.version.isEmpty ? (info?.version ?? "") : app.version
        return [info?.seller, version.isEmpty ? nil : version,
                info?.size.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) }]
            .compactMap { $0 }.joined(separator: " · ")
    }

    private func search(force: Bool) async {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty, force || q != lastQuery || error != nil else { return }
        lastQuery = q
        searching = true; error = nil
        defer { searching = false }

        let parts = q.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if !parts.isEmpty, parts.allSatisfy({ $0.count >= 6 && $0.allSatisfy(\.isNumber) }) {
            await art.fetch(ids: parts)
            guard q == query.trimmingCharacters(in: .whitespaces) else { return }
            results = parts.map { id in
                let i = art.byID[id]
                return StoreApp(id: id, name: model.displayName(for: id) ?? i?.name ?? id,
                                bundleID: i?.bundle ?? "", version: i?.version ?? "")
            }
            return
        }

        // Свои списки (там и снятые с витрины — VK, Авито), потом App Store.
        var found: [StoreApp] = []
        let local = (model.customList + model.mainList).filter { $0.name.localizedCaseInsensitiveContains(q) }
        found += local.map { StoreApp(id: $0.id, name: $0.name) }
        var failure: String?
        do { found += try await IPATool.search(q) } catch { failure = error.localizedDescription }
        // Пока ipatool искал, запрос могли поменять — старый ответ не нужен.
        guard q == query.trimmingCharacters(in: .whitespaces) else { return }
        var seen = Set<String>()
        results = found.filter { seen.insert($0.id).inserted }
        if results.isEmpty { error = failure }
    }
}

/// Поле поиска в стеклянной капсуле — той же высоты, что кнопки шапки.
struct SearchField: View {
    @Binding var text: String
    var prompt: String
    var autofocus = false
    var onSubmit: () -> Void = {}
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 15))
                .focused($focused)
                .onSubmit { if !text.isEmpty { onSubmit() } }
            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 36)
        .glassBackground(Capsule(), interactive: true)
        .contentShape(.capsule)
        .onTapGesture { focused = true }
        .onAppear { if autofocus { focused = true } }
    }
}
