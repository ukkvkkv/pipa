import SwiftUI

// Pipa работает с macOS 14. Liquid Glass есть только в macOS 26 — на
// старых системах вместо стекла материал и обычные кнопки.

extension View {
    /// Стеклянная подложка формы `shape`; до macOS 26 — материал с тонкой кромкой.
    @ViewBuilder
    func glassBackground<S: Shape>(_ shape: S, interactive: Bool = false) -> some View {
        if #available(macOS 26, *) {
            glassEffect(interactive ? .regular.interactive() : .regular, in: shape)
        } else {
            background(.regularMaterial, in: shape)
                .overlay(shape.stroke(Color.primary.opacity(0.10), lineWidth: 0.5))
        }
    }

    /// Стеклянная кнопка (`prominent` — с заливкой акцентом); до macOS 26 — bordered.
    @ViewBuilder
    func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }

    /// Убирает заголовок из панели (macOS 15+; на 14 его прячет AppDelegate).
    @ViewBuilder
    func hiddenToolbarTitle() -> some View {
        if #available(macOS 15, *) {
            toolbar(removing: .title)
        } else {
            self
        }
    }
}
