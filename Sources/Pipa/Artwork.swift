import SwiftUI

/// Иконки и подробности приложений. Источники по очереди:
/// 1. публичный iTunes Lookup (регион аккаунта, США, Россия) — пачками;
/// 2. иконка, вынутая из скачанной .ipa (iTunesArtwork);
/// 3. сам App Store через ipatool: list-versions отдаёт ссылку на иконку
///    600×600 для купленных приложений, даже снятых с витрины;
/// 4. буква на подложке — чтобы иконка была всегда.
/// Найденные ссылки помнятся на диске (icons.json).
@MainActor
@Observable
final class Artwork {
    static let shared = Artwork()

    struct Info: Equatable {
        var name: String?
        var bundle: String?
        var version: String?
        var icon: URL?
        var seller: String?
        var genre: String?
        var size: Int64?
        var minIOS: String?
        var rating: Double?
        var price: Double?
    }

    private(set) var byID: [String: Info] = [:]
    private(set) var byBundle: [String: Info] = [:]
    var country: String = ""

    private var pendingIDs = Set<String>()
    private var pendingBundles = Set<String>()
    private var requested = Set<String>()
    private var flushTask: Task<Void, Never>?

    private var storeQueue: [String] = []
    private var storeRunning = false
    private var storeTried = Set<String>()

    private static var saved: URL { Paths.support.appendingPathComponent("icons.json") }

    init() {
        if let data = try? Data(contentsOf: Self.saved),
           let map = try? JSONDecoder().decode([String: String].self, from: data) {
            for (id, s) in map { byID[id] = Info(icon: URL(string: s)) }
        }
    }

    private func persist(_ id: String, _ url: URL) {
        var map = (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: Self.saved))) ?? [:]
        map[id] = url.absoluteString
        if let data = try? JSONEncoder().encode(map) { try? data.write(to: Self.saved, options: .atomic) }
    }

    /// Иконка из скачанной .ipa.
    func register(id: String?, bundle: String, file: URL) {
        let info = Info(icon: file)
        if !bundle.isEmpty, byBundle[bundle]?.icon == nil { byBundle[bundle] = info }
        if let id, byID[id]?.icon == nil { byID[id] = info }
    }

    /// Подробности сразу, без очереди — для ввода ID в поиске.
    func fetch(ids: [String]) async {
        let fresh = ids.filter { byID[$0]?.name == nil }
        if !fresh.isEmpty { await lookup("id", fresh) }
    }

    func want(id: String) {
        guard !id.isEmpty, byID[id]?.icon == nil, requested.insert("i" + id).inserted else { return }
        pendingIDs.insert(id); schedule()
    }

    func want(bundle: String) {
        guard !bundle.isEmpty, byBundle[bundle]?.icon == nil, requested.insert("b" + bundle).inserted else { return }
        pendingBundles.insert(bundle); schedule()
    }

    private func schedule() {
        guard flushTask == nil else { return }
        flushTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            await flush()
            flushTask = nil
            if !pendingIDs.isEmpty || !pendingBundles.isEmpty { schedule() }
        }
    }

    private func flush() async {
        let ids = Array(pendingIDs.prefix(150)); pendingIDs.subtract(ids)
        let bundles = Array(pendingBundles.prefix(150)); pendingBundles.subtract(bundles)
        if !ids.isEmpty {
            await lookup("id", ids)
            // Чего нет ни в одной витрине — спрашиваем App Store через ipatool.
            for id in ids where byID[id]?.icon == nil { askStore(id) }
        }
        if !bundles.isEmpty { await lookup("bundleId", bundles) }
    }

    private func lookup(_ key: String, _ values: [String]) async {
        var missing = values
        // Регион аккаунта, потом США и Россия: российских приложений в чужих витринах нет.
        var countries: [String] = []
        for c in [country.lowercased(), "", "ru"] where !countries.contains(c) { countries.append(c) }
        for country in countries where !missing.isEmpty {
            var c = URLComponents(string: "https://itunes.apple.com/lookup")!
            c.queryItems = [URLQueryItem(name: key, value: missing.joined(separator: ",")),
                            URLQueryItem(name: "entity", value: "software")]
            if !country.isEmpty { c.queryItems!.append(URLQueryItem(name: "country", value: country)) }
            guard let url = c.url,
                  let (data, _) = try? await URLSession.shared.data(from: url),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let results = obj["results"] as? [[String: Any]] else { continue }
            for r in results {
                let info = Info(
                    name: r["trackName"] as? String,
                    bundle: r["bundleId"] as? String,
                    version: r["version"] as? String,
                    icon: (r["artworkUrl512"] as? String ?? r["artworkUrl100"] as? String).flatMap(URL.init(string:)),
                    seller: r["sellerName"] as? String,
                    genre: r["primaryGenreName"] as? String,
                    size: (r["fileSizeBytes"] as? String).flatMap { Int64($0) },
                    minIOS: r["minimumOsVersion"] as? String,
                    rating: r["averageUserRating"] as? Double,
                    price: r["price"] as? Double)
                if let id = r["trackId"].map({ "\($0)" }) { byID[id] = info }
                if let b = r["bundleId"] as? String { byBundle[b] = info }
            }
            missing.removeAll { key == "id" ? byID[$0]?.icon != nil : byBundle[$0]?.icon != nil }
        }
    }

    // MARK: ipatool

    private func askStore(_ id: String) {
        guard storeTried.insert(id).inserted else { return }
        storeQueue.append(id)
        guard !storeRunning else { return }
        storeRunning = true
        Task {
            // По одному: ipatool делит файл cookies, а запрос занимает ~1–2 с.
            while !storeQueue.isEmpty {
                let next = storeQueue.removeLast()
                if byID[next]?.icon == nil, let url = await Self.storeIcon(next) {
                    var info = byID[next] ?? Info()
                    info.icon = url
                    byID[next] = info
                    persist(next, url)
                }
            }
            storeRunning = false
        }
    }

    /// Ссылка на иконку из ответа App Store. Без --purchase: лицензию не берём,
    /// для чужого приложения Apple просто ничего не вернёт.
    private static func storeIcon(_ id: String) async -> URL? {
        let r = await Tools.run(Tools.ipatool, ["list-versions", "-i", id, "--debug"])
        let text = r.stdout + r.stderr
        let pattern = #"https://is\d-ssl\.mzstatic\.com/image/thumb/[^<"\s]+?/(\d+)x\d+bb\.(?:png|jpg)"#
        guard let re = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = text as NSString
        let matches = re.matches(in: text, range: NSRange(location: 0, length: ns.length))
        // Самая крупная из найденных.
        let best = matches.max { a, b in
            Int(ns.substring(with: a.range(at: 1))) ?? 0 < Int(ns.substring(with: b.range(at: 1))) ?? 0
        }
        return best.flatMap { URL(string: ns.substring(with: $0.range)) }
    }
}

struct AppIcon: View {
    var id: String? = nil
    var bundle: String? = nil
    var name: String = ""
    var size: CGFloat = 44

    @State private var art = Artwork.shared

    private var info: Artwork.Info? {
        if let id, let i = art.byID[id], i.icon != nil { return i }
        if let bundle, let i = art.byBundle[bundle], i.icon != nil { return i }
        return nil
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.225, style: .continuous)
        ZStack {
            if let url = info?.icon {
                if url.isFileURL, let img = NSImage(contentsOf: url) {
                    Image(nsImage: img).resizable().interpolation(.high)
                } else {
                    AsyncImage(url: url, transaction: Transaction(animation: .easeOut(duration: 0.2))) { phase in
                        if let img = phase.image { img.resizable().interpolation(.high) } else { monogram }
                    }
                }
            } else {
                monogram
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay(shape.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5))
        .onAppear {
            if let id { art.want(id: id) }
            if let bundle { art.want(bundle: bundle) }
        }
    }

    /// Первая буква названия — пока иконка грузится или если её нет нигде.
    private var monogram: some View {
        ZStack {
            Rectangle().fill(.quaternary)
            Text(name.first.map { String($0).uppercased() } ?? "")
                .font(.system(size: size * 0.45, weight: .semibold, design: .rounded))
                .foregroundStyle(.secondary)
        }
    }
}
