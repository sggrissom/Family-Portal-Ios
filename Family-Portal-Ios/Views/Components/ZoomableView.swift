import SwiftUI

struct ZoomableView<Content: View>: View {
    private let content: Content
    private let minScale: CGFloat = 1
    private let maxScale: CGFloat = 4
    @Binding private var isZoomed: Bool
    @State private var scale: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastScale: CGFloat = 1
    @State private var lastOffset: CGSize = .zero

    init(isZoomed: Binding<Bool> = .constant(false), @ViewBuilder content: () -> Content) {
        self.content = content()
        _isZoomed = isZoomed
    }

    var body: some View {
        GeometryReader { proxy in
            content
                .frame(width: proxy.size.width, height: proxy.size.height)
                .scaleEffect(scale)
                .offset(offset)
                .gesture(magnificationGesture(in: proxy.size).simultaneously(with: dragGesture(in: proxy.size)))
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: scale)
                .animation(.spring(response: 0.35, dampingFraction: 0.85), value: offset)
                .onChange(of: scale) { _, newValue in
                    isZoomed = newValue > minScale
                    if newValue == minScale {
                        offset = .zero
                        lastOffset = .zero
                    } else {
                        offset = clampedOffset(offset, in: proxy.size)
                    }
                }
        }
    }

    private func magnificationGesture(in size: CGSize) -> some Gesture {
        MagnificationGesture()
            .onChanged { value in
                let delta = value / lastScale
                scale = clampedScale(scale * delta)
                lastScale = value
                offset = clampedOffset(offset, in: size)
            }
            .onEnded { _ in
                scale = clampedScale(scale)
                lastScale = 1
                isZoomed = scale > minScale
                if scale == minScale {
                    offset = .zero
                    lastOffset = .zero
                } else {
                    offset = clampedOffset(offset, in: size)
                }
            }
    }

    private func dragGesture(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard scale > minScale else { return }
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, in: size)
            }
            .onEnded { _ in
                guard scale > minScale else { return }
                let clamped = clampedOffset(offset, in: size)
                offset = clamped
                lastOffset = clamped
            }
    }

    private func clampedScale(_ value: CGFloat) -> CGFloat {
        min(max(value, minScale), maxScale)
    }

    private func clampedOffset(_ value: CGSize, in size: CGSize) -> CGSize {
        guard scale > minScale else { return .zero }
        let maxOffsetX = max((scale - 1) * size.width / 2, 0)
        let maxOffsetY = max((scale - 1) * size.height / 2, 0)
        return CGSize(
            width: min(max(value.width, -maxOffsetX), maxOffsetX),
            height: min(max(value.height, -maxOffsetY), maxOffsetY)
        )
    }
}
