import SwiftUI

struct ContentView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            VStack(spacing: 0) {
                page
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(alignment: .bottom) { ToastStack() }
                Divider()
                StatusBar()
            }
            .background(alignment: .top) { HeaderStrip() }
            .navigationTitle(model.section.title)
            .hiddenToolbarTitle()
            .modifier(MainToolbar())
            .toolbarBackground(.hidden, for: .windowToolbar)
        }
        .sheet(isPresented: $model.showLogin) {
            LoginSheet()
        }
    }

    @ViewBuilder
    private var page: some View {
        switch model.section {
        case .search: needsAccount { SearchView() }
        case .library: LibraryView()
        }
    }

    @ViewBuilder
    private func needsAccount<V: View>(@ViewBuilder _ content: () -> V) -> some View {
        if model.account != nil {
            content()
        } else if model.checkingAuth {
            ProgressView()
        } else {
            VStack(spacing: 10) {
                Text("Нет входа в Apple ID").font(.headline)
                Text("Войдите аккаунтом, которым покупались приложения.")
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                Button("Войти…") { model.showLogin = true }
                    .glassButton(prominent: true)
                    .controlSize(.large)
                    .padding(.top, 4)
            }
            .padding(24)
        }
    }
}

// MARK: - Полоса состояния

/// Внизу окна всегда: что подключено и сколько лежит в папке.
struct StatusBar: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: model.device == nil ? "iphone.slash" : "iphone")
                .frame(width: 14)
            Text(model.device.map { "\($0.name), iOS \($0.iOS)" } ?? "iPhone не подключён")
            Spacer()
            Text(summary).foregroundStyle(.tertiary)
            Button { NSWorkspace.shared.open(Paths.apps) } label: { Image(systemName: "folder") }
                .buttonStyle(.borderless)
                .toolTip("Открыть папку с .ipa")
        }
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
        .lineLimit(1)
        .padding(.horizontal, 14)
        .frame(height: 32)
    }

    private var summary: String {
        let total = model.library.reduce(Int64(0)) { $0 + $1.size }
        return "\(model.library.count) · \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))"
    }
}

// MARK: - Кнопки панели

struct DownloadsButton: View {
    @Environment(AppModel.self) private var model
    @State private var shown = false

    var body: some View {
        Button { shown.toggle() } label: {
            if let p = model.overallProgress {
                ProgressView(value: p)
                    .progressViewStyle(.circular)
                    .controlSize(.small)
            } else {
                Label("Загрузки", systemImage: "arrow.down.circle")
            }
        }
        .toolTip(model.overallProgress.map { "Загрузки — \(Int($0 * 100)) %" } ?? "Загрузки")
        .popover(isPresented: $shown, arrowEdge: .bottom) { DownloadsPopover() }
    }
}

/// Панель окна: слева разделы, справа капсула с загрузками и настройками.
/// В macOS 26 капсуле отключают системное стекло (у неё своё) и отодвигают
/// её вправо ToolbarSpacer — до macOS 26 этих API нет, и они не нужны.
private struct MainToolbar: ViewModifier {
    @Environment(AppModel.self) private var model

    func body(content: Content) -> some View {
        if #available(macOS 26, *) {
            content.toolbar {
                ToolbarItem(placement: .navigation) { sections }
                ToolbarSpacer(.flexible)
                ToolbarItem(placement: .primaryAction) { buttons }
                    .sharedBackgroundVisibility(.hidden)
            }
        } else {
            content.toolbar {
                ToolbarItem(placement: .navigation) { sections }
                ToolbarItem(placement: .primaryAction) { buttons }
            }
        }
    }

    // Переключатель разделов — иконками, одним сегментом.
    private var sections: some View {
        Picker("Раздел", selection: Bindable(model).section) {
            ForEach(Section.allCases, id: \.self) { s in
                Label(s.title, systemImage: s.symbol).tag(s)
            }
        }
        .pickerStyle(.segmented)
        .labelStyle(.iconOnly)
        .labelsHidden()
        .fixedSize()
    }

    private var buttons: some View {
        ToolbarCapsule {
            if !model.jobs.isEmpty { DownloadsButton() }
            SettingsLink {
                Label("Настройки", systemImage: "gearshape")
            }
            .toolTip("Настройки")
        }
    }
}

/// Капсула кнопок-иконок, как в Copy Hunter и Почте: своё стекло,
/// у кнопок — подсветка под курсором.
struct ToolbarCapsule<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        HStack(spacing: 0) { content }
            .buttonStyle(CapsuleIconButtonStyle())
            .labelStyle(.iconOnly)
            .padding(.horizontal, 4)
            .frame(height: 36)
            .fixedSize()
            .glassBackground(Capsule(), interactive: true)
    }
}

struct CapsuleIconButtonStyle: ButtonStyle {
    var size: CGFloat = 16
    var width: CGFloat = 38
    var height: CGFloat = 30
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        CapsuleIconButton(configuration: configuration, size: size, width: width, height: height, selected: selected)
    }

    private struct CapsuleIconButton: View {
        let configuration: ButtonStyleConfiguration
        let size: CGFloat, width: CGFloat, height: CGFloat
        let selected: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hover = false

        var body: some View {
            configuration.label
                .font(.system(size: size, weight: .regular))
                .foregroundStyle(selected ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
                .frame(width: width, height: height)
                .background(
                    Capsule().fill(.primary.opacity(configuration.isPressed ? 0.16 : (selected ? 0.12 : (hover ? 0.08 : 0))))
                )
                .contentShape(Capsule())
                .opacity(isEnabled ? 1 : 0.35)
                .onHover { hover = $0 && isEnabled }
        }
    }
}

/// Капсула действий в строке — того же размера, что в шапке.
typealias RowCapsule = ToolbarCapsule

/// Серая полоса шапки окна (52 pt — высота полосы инструментов macOS 26)
/// с линией снизу. Фон растягивается под шапку через ignoresSafeArea.
struct HeaderStrip: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Color.primary.opacity(0.07))
                .frame(height: 52)
            Divider()
            Spacer(minLength: 0)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

extension View {
    /// Подсказка AppKit: SwiftUI .help у кнопок в одной капсуле панели
    /// показывает подпись первой кнопки над любой (грабля из Copy Hunter).
    func toolTip(_ text: String) -> some View {
        overlay(ToolTipView(text: text))
    }
}

private struct ToolTipView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> TipView { TipView() }

    func updateNSView(_ view: TipView, context: Context) {
        view.toolTip = text
    }

    final class TipView: NSView {
        // Клики проходят к кнопке под ним.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            for item in window?.toolbar?.items ?? [] where item.view.map(isDescendant(of:)) == true {
                item.toolTip = nil
            }
            var parent = superview
            while let view = parent {
                view.toolTip = nil
                parent = view.superview
            }
        }
    }
}

// MARK: - Уведомления

struct ToastStack: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 6) {
            ForEach(model.toasts) { t in
                Label(t.text, systemImage: t.symbol)
                    .font(.callout)
                    .lineLimit(3)
                    .foregroundStyle(t.isError ? AnyShapeStyle(.orange) : AnyShapeStyle(.primary))
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .glassBackground(Capsule())
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .allowsHitTesting(false)
    }
}

// MARK: - Вход

struct LoginSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var email = ""
    @State private var password = ""
    @State private var code = ""
    @State private var needsCode = false
    @State private var busy = false
    @State private var error: String?
    @FocusState private var focus: Field?

    enum Field { case email, password, code }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(needsCode ? "Код подтверждения" : "Вход в Apple ID").font(.headline)
            Text(needsCode
                 ? "Нажмите «Разрешить» на iPhone и введите код. Если код не пришёл: Настройки → Apple ID → Вход и безопасность → Получить код проверки."
                 : "Почта и пароль уходят только в Apple, через ipatool.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if needsCode {
                TextField("Код из 6 цифр", text: $code)
                    .focused($focus, equals: .code)
                    .onChange(of: code) { _, v in code = String(v.filter(\.isNumber).prefix(6)) }
                    .onSubmit(submit)
            } else {
                TextField("Почта", text: $email)
                    .textContentType(.username)
                    .focused($focus, equals: .email)
                    .onSubmit { focus = .password }
                SecureField("Пароль", text: $password)
                    .textContentType(.password)
                    .focused($focus, equals: .password)
                    .onSubmit(submit)
            }

            if let error {
                Text(error).font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack {
                if busy { ProgressView().controlSize(.small) }
                Spacer()
                Button("Отмена") { dismiss(); Task { await model.cancelLogin() } }
                    .keyboardShortcut(.cancelAction)
                    .glassButton()
                Button(needsCode ? "Подтвердить" : "Войти", action: submit)
                    .keyboardShortcut(.defaultAction)
                    .glassButton(prominent: true)
                    .disabled(busy || !valid)
            }
        }
        .textFieldStyle(.roundedBorder)
        .padding(20)
        .frame(width: 360)
        .onAppear { focus = .email }
    }

    private var valid: Bool {
        needsCode ? code.count == 6 : (email.contains("@") && !password.isEmpty)
    }

    private func submit() {
        guard valid, !busy else { return }
        busy = true; error = nil
        Task {
            let outcome = await model.login(email: email.trimmingCharacters(in: .whitespaces), password: password,
                                            code: needsCode ? code : nil)
            busy = false
            switch outcome {
            case .success: dismiss()
            case .needsCode:
                if needsCode { error = "Код не подошёл, попробуйте ещё раз."; code = "" }
                needsCode = true
                focus = .code
            case .failure(let msg):
                error = msg.isEmpty ? "Вход не выполнен." : msg
            }
        }
    }
}
