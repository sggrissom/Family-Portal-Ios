import SwiftUI

struct ZoomableView<Content: View>: View {
    private let content: Content
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .scaleEffect(scale)
            .offset(offset)
            .gesture(magnificationGesture.simultaneously(with: dragGesture))
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: scale)
            .animation(.spring(response: 0.35, dampingFraction: 0.85), value: offset)
            .onChange(of: scale) { _, newValue in
                if newValue == minScale {
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var magnificationGesture: some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                scale = clampedScale(scale * delta)
                lastScale = value
            }
            .onEnded { _ in
                scale = clampedScale(scale)
                lastScale = 1
                if scale == minScale {
                    offset = .zero
                    lastOffset = .zero
                }
            }
    }

    private var dragGesture: some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                offset = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                guard scale > minScale else { return }
                lastOffset = offset
            }
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }
}
