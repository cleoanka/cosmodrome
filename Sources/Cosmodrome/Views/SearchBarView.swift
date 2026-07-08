import SwiftUI

/// Launchpad's translucent search pill. There is no focusable field — the
/// OverlayController routes every keystroke here, so it can't lose focus.
struct SearchBarView: View {
    @ObservedObject var state: GridState
    @State private var caretVisible = true

    var body: some View {
        HStack(spacing: 6) {
            if state.query.isEmpty {
                Spacer(minLength: 0)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text("Search")
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.5))
                Spacer(minLength: 0)
            } else {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(state.query)
                    .font(.system(size: 14))
                    .foregroundStyle(.white.opacity(0.95))
                    .lineLimit(1)
                    .truncationMode(.head)

                caret

                Spacer(minLength: 0)

                Button {
                    state.setQuery("")
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .frame(width: 240, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(.white.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .strokeBorder(.white.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.12), radius: 5, y: 1)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.55).repeatForever(autoreverses: true)) {
                caretVisible = false
            }
        }
    }

    private var caret: some View {
        RoundedRectangle(cornerRadius: 1)
            .fill(.white.opacity(caretVisible ? 0.9 : 0))
            .frame(width: 1.5, height: 15)
    }
}
