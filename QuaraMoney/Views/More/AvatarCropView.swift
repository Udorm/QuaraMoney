import SwiftUI

/// Contacts-style "Move and Scale" cropper for the profile photo.
///
/// The photo starts aspect-filled to the crop circle; the user can pinch to
/// zoom (1×–6×) and drag to reposition. Offsets are clamped so the photo
/// always covers the whole circle, and the final square is rendered from the
/// original pixels (never a screenshot), capped at 1024 px.
struct AvatarCropView: View {
    private let image: UIImage
    private let onComplete: (UIImage?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var lastZoom: CGFloat = 1
    @State private var offset: CGSize = .zero
    @State private var lastOffset: CGSize = .zero

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 6

    init(image: UIImage, onComplete: @escaping (UIImage?) -> Void) {
        // Normalize orientation up front so CGImage cropping and the on-screen
        // preview share the same coordinate space.
        self.image = Self.normalizedOrientation(image)
        self.onComplete = onComplete
    }

    var body: some View {
        GeometryReader { geo in
            let diameter = cropDiameter(in: geo.size)
            let fill = fillScale(for: diameter)
            let displaySize = CGSize(
                width: image.size.width * fill * zoom,
                height: image.size.height * fill * zoom
            )

            ZStack {
                Color.black
                    .ignoresSafeArea()

                Image(uiImage: image)
                    .resizable()
                    .frame(width: displaySize.width, height: displaySize.height)
                    .offset(offset)

                dimmingOverlay(diameter: diameter)
                    .allowsHitTesting(false)
            }
            .contentShape(Rectangle())
            .gesture(dragGesture(diameter: diameter).simultaneously(with: zoomGesture(diameter: diameter)))
            .onTapGesture(count: 2) {
                withAnimation(.snappy) { resetFraming() }
            }
            .overlay(alignment: .top) {
                Text("profile.moveAndScale".localized)
                    .font(.app(.headline, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.top, 16)
            }
            .overlay(alignment: .bottom) {
                controlBar(diameter: diameter)
            }
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Chrome

    private func dimmingOverlay(diameter: CGFloat) -> some View {
        ZStack {
            Color.black.opacity(0.55)
                .mask {
                    ZStack {
                        Rectangle()
                        Circle()
                            .frame(width: diameter, height: diameter)
                            .blendMode(.destinationOut)
                    }
                    .compositingGroup()
                }

            Circle()
                .strokeBorder(.white.opacity(0.6), lineWidth: 0.75)
                .frame(width: diameter, height: diameter)
        }
        .ignoresSafeArea()
    }

    private func controlBar(diameter: CGFloat) -> some View {
        HStack {
            Button(L10n.Common.cancel) {
                onComplete(nil)
                dismiss()
            }
            .buttonStyle(.glass)

            Spacer()

            Button("profile.usePhoto".localized) {
                onComplete(renderCropped(diameter: diameter))
                dismiss()
            }
            .buttonStyle(.glassProminent)
        }
        .font(.app(.body, weight: .semibold))
        .padding(.horizontal, 24)
        .padding(.bottom, 12)
    }

    // MARK: - Geometry

    private func cropDiameter(in size: CGSize) -> CGFloat {
        min(min(size.width, size.height) - 48, 340)
    }

    /// Scale factor that aspect-fills the image to the crop circle at 1× zoom.
    private func fillScale(for diameter: CGFloat) -> CGFloat {
        let side = min(image.size.width, image.size.height)
        guard side > 0 else { return 1 }
        return diameter / side
    }

    private func clampedOffset(_ proposed: CGSize, zoom: CGFloat, diameter: CGFloat) -> CGSize {
        let fill = fillScale(for: diameter)
        let maxX = max(0, (image.size.width * fill * zoom - diameter) / 2)
        let maxY = max(0, (image.size.height * fill * zoom - diameter) / 2)
        return CGSize(
            width: min(maxX, max(-maxX, proposed.width)),
            height: min(maxY, max(-maxY, proposed.height))
        )
    }

    private func resetFraming() {
        zoom = 1
        lastZoom = 1
        offset = .zero
        lastOffset = .zero
    }

    // MARK: - Gestures

    private func dragGesture(diameter: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                let proposed = CGSize(
                    width: lastOffset.width + value.translation.width,
                    height: lastOffset.height + value.translation.height
                )
                offset = clampedOffset(proposed, zoom: zoom, diameter: diameter)
            }
            .onEnded { _ in
                lastOffset = offset
            }
    }

    private func zoomGesture(diameter: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                // Allow slight overshoot while pinching for a natural feel…
                zoom = min(maxZoom * 1.15, max(minZoom * 0.85, lastZoom * value.magnification))
                offset = clampedOffset(offset, zoom: zoom, diameter: diameter)
            }
            .onEnded { _ in
                // …then settle back into the hard limits.
                withAnimation(.snappy) {
                    zoom = min(maxZoom, max(minZoom, zoom))
                    offset = clampedOffset(offset, zoom: zoom, diameter: diameter)
                }
                lastZoom = zoom
                lastOffset = offset
            }
    }

    // MARK: - Rendering

    private func renderCropped(diameter: CGFloat) -> UIImage {
        let fill = fillScale(for: diameter)
        let pointsPerScreenPoint = 1 / (fill * zoom)

        // The circle's center back-projected into image point coordinates.
        let side = diameter * pointsPerScreenPoint
        let centerX = image.size.width / 2 - offset.width * pointsPerScreenPoint
        let centerY = image.size.height / 2 - offset.height * pointsPerScreenPoint

        let pixelScale = image.scale
        let cropRect = CGRect(
            x: (centerX - side / 2) * pixelScale,
            y: (centerY - side / 2) * pixelScale,
            width: side * pixelScale,
            height: side * pixelScale
        ).integral

        guard let cgImage = image.cgImage,
              let cropped = cgImage.cropping(to: cropRect) else {
            return image
        }

        let result = UIImage(cgImage: cropped, scale: 1, orientation: .up)

        // Avatars never need more than ~1K — keeps the synced file small.
        let maxSide: CGFloat = 1024
        guard result.size.width > maxSide else { return result }

        let target = CGSize(width: maxSide, height: maxSide)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            result.draw(in: CGRect(origin: .zero, size: target))
        }
    }

    private static func normalizedOrientation(_ image: UIImage) -> UIImage {
        guard image.imageOrientation != .up else { return image }
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        return UIGraphicsImageRenderer(size: image.size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: image.size))
        }
    }
}

#Preview {
    AvatarCropView(
        image: UIImage(systemName: "photo")!.withTintColor(.systemTeal)
    ) { _ in }
}
