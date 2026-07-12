import SwiftUI

/// Contacts-style "Move and Scale" cropper for the profile photo.
///
/// The photo starts aspect-filled to the crop circle; the user can pinch to
/// zoom (1×–6×, anchored at the pinch point) and drag to reposition with
/// UIScrollView-style rubber-banding at the edges. Double-tap toggles between
/// fit and 2.5× at the tapped spot. The final square is rendered from the
/// source pixels (never a screenshot), capped at 1024 px.
struct AvatarCropView: View {
    private let image: UIImage
    private let onComplete: (UIImage?) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var zoom: CGFloat = 1
    @State private var offset: CGSize = .zero

    // Per-gesture baselines; nil when the gesture is not active.
    @State private var pinchStartZoom: CGFloat?
    @State private var lastDragTranslation: CGSize = .zero
    @State private var isDragging = false

    private let minZoom: CGFloat = 1
    private let maxZoom: CGFloat = 6

    init(image: UIImage, onComplete: @escaping (UIImage?) -> Void) {
        // Normalize orientation and cap resolution up front so CGImage
        // cropping and the on-screen preview share the same coordinate
        // space, and huge camera photos don't cost decode/memory spikes.
        self.image = Self.preparedForCropping(image)
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
                    .position(
                        x: geo.size.width / 2 + offset.width,
                        y: geo.size.height / 2 + offset.height
                    )

                dimmingOverlay(diameter: diameter)
                    .allowsHitTesting(false)
            }
            // Pin the canvas to the screen so an oversized photo can't
            // inflate the layout and shift the crop circle off-center.
            .frame(width: geo.size.width, height: geo.size.height)
            .contentShape(Rectangle())
            .gesture(
                dragGesture(diameter: diameter)
                    .simultaneously(with: zoomGesture(in: geo.size, diameter: diameter))
            )
            .gesture(doubleTapGesture(in: geo.size, diameter: diameter))
            .overlay(alignment: .top) {
                Text("profile.moveAndScale".localized)
                    .appFont(.headline, weight: .semibold)
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
        .appFont(.body, weight: .semibold)
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

    /// Largest allowed |offset| per axis so the photo still covers the circle.
    private func offsetLimits(zoom: CGFloat, diameter: CGFloat) -> CGSize {
        let fill = fillScale(for: diameter)
        return CGSize(
            width: max(0, (image.size.width * fill * zoom - diameter) / 2),
            height: max(0, (image.size.height * fill * zoom - diameter) / 2)
        )
    }

    private func clampedOffset(_ proposed: CGSize, zoom: CGFloat, diameter: CGFloat) -> CGSize {
        let limits = offsetLimits(zoom: zoom, diameter: diameter)
        return CGSize(
            width: min(limits.width, max(-limits.width, proposed.width)),
            height: min(limits.height, max(-limits.height, proposed.height))
        )
    }

    /// UIScrollView-style resistance once the photo is pulled past its limits.
    private func rubberBanded(_ proposed: CGSize, zoom: CGFloat, diameter: CGFloat) -> CGSize {
        let limits = offsetLimits(zoom: zoom, diameter: diameter)

        func band(_ value: CGFloat, limit: CGFloat) -> CGFloat {
            guard abs(value) > limit else { return value }
            let excess = abs(value) - limit
            // Classic scroll-view curve: c = 0.55, dimension = crop circle.
            let damped = (1 - 1 / (excess * 0.55 / diameter + 1)) * diameter
            return (limit + damped) * (value < 0 ? -1 : 1)
        }

        return CGSize(
            width: band(proposed.width, limit: limits.width),
            height: band(proposed.height, limit: limits.height)
        )
    }

    /// Zoom with gentle overshoot past the hard limits while pinching.
    private func softClampedZoom(_ proposed: CGFloat) -> CGFloat {
        if proposed > maxZoom { return maxZoom + (proposed - maxZoom) * 0.25 }
        if proposed < minZoom { return minZoom - (minZoom - proposed) * 0.35 }
        return proposed
    }

    /// Animate zoom/offset back inside the hard limits after a gesture ends.
    private func settle(diameter: CGFloat) {
        let targetZoom = min(maxZoom, max(minZoom, zoom))
        let targetOffset = clampedOffset(offset, zoom: targetZoom, diameter: diameter)
        guard targetZoom != zoom || targetOffset != offset else { return }
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            zoom = targetZoom
            offset = targetOffset
        }
    }

    // MARK: - Gestures

    private func dragGesture(diameter: CGFloat) -> some Gesture {
        DragGesture()
            .onChanged { value in
                if !isDragging {
                    isDragging = true
                    lastDragTranslation = .zero
                }
                // Incremental deltas so panning composes with a simultaneous
                // pinch instead of overwriting its offset.
                let delta = CGSize(
                    width: value.translation.width - lastDragTranslation.width,
                    height: value.translation.height - lastDragTranslation.height
                )
                lastDragTranslation = value.translation
                let proposed = CGSize(
                    width: offset.width + delta.width,
                    height: offset.height + delta.height
                )
                offset = rubberBanded(proposed, zoom: zoom, diameter: diameter)
            }
            .onEnded { _ in
                isDragging = false
                lastDragTranslation = .zero
                settle(diameter: diameter)
            }
    }

    private func zoomGesture(in size: CGSize, diameter: CGFloat) -> some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let startZoom = pinchStartZoom ?? zoom
                if pinchStartZoom == nil { pinchStartZoom = zoom }

                let newZoom = softClampedZoom(startZoom * value.magnification)
                guard zoom > 0 else { return }

                // Keep the content under the fingers fixed: scale the current
                // offset about the pinch anchor by the incremental ratio.
                let anchor = CGPoint(
                    x: (value.startAnchor.x - 0.5) * size.width,
                    y: (value.startAnchor.y - 0.5) * size.height
                )
                let ratio = newZoom / zoom
                let proposed = CGSize(
                    width: anchor.x - (anchor.x - offset.width) * ratio,
                    height: anchor.y - (anchor.y - offset.height) * ratio
                )
                zoom = newZoom
                offset = rubberBanded(proposed, zoom: newZoom, diameter: diameter)
            }
            .onEnded { _ in
                pinchStartZoom = nil
                settle(diameter: diameter)
            }
    }

    private func doubleTapGesture(in size: CGSize, diameter: CGFloat) -> some Gesture {
        SpatialTapGesture(count: 2)
            .onEnded { value in
                HapticManager.shared.impact(style: .light)
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    if zoom > minZoom * 1.01 {
                        zoom = minZoom
                        offset = clampedOffset(offset, zoom: minZoom, diameter: diameter)
                    } else {
                        let targetZoom: CGFloat = 2.5
                        let anchor = CGPoint(
                            x: value.location.x - size.width / 2,
                            y: value.location.y - size.height / 2
                        )
                        let ratio = targetZoom / zoom
                        let proposed = CGSize(
                            width: anchor.x - (anchor.x - offset.width) * ratio,
                            height: anchor.y - (anchor.y - offset.height) * ratio
                        )
                        zoom = targetZoom
                        offset = clampedOffset(proposed, zoom: targetZoom, diameter: diameter)
                    }
                }
            }
    }

    // MARK: - Rendering

    private func renderCropped(diameter: CGFloat) -> UIImage {
        // Render from settled values even if a gesture was mid-flight.
        let safeZoom = min(maxZoom, max(minZoom, zoom))
        let safeOffset = clampedOffset(offset, zoom: safeZoom, diameter: diameter)

        let fill = fillScale(for: diameter)
        let pointsPerScreenPoint = 1 / (fill * safeZoom)

        // The circle's center back-projected into image point coordinates.
        let side = diameter * pointsPerScreenPoint
        let centerX = image.size.width / 2 - safeOffset.width * pointsPerScreenPoint
        let centerY = image.size.height / 2 - safeOffset.height * pointsPerScreenPoint

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

    /// Bakes orientation into the pixels and caps the long side at 4096 px so
    /// even 48 MP camera shots stay cheap to render and pan while cropping
    /// (the final avatar is capped at 1024 px anyway).
    private static func preparedForCropping(_ image: UIImage) -> UIImage {
        let maxSide: CGFloat = 4096
        let pixelSize = CGSize(
            width: image.size.width * image.scale,
            height: image.size.height * image.scale
        )
        let longest = max(pixelSize.width, pixelSize.height)
        let needsResize = longest > maxSide
        let needsNormalize = image.imageOrientation != .up || image.scale != 1

        guard needsResize || needsNormalize else { return image }

        let factor = needsResize ? maxSide / longest : 1
        let target = CGSize(
            width: max(1, (pixelSize.width * factor).rounded()),
            height: max(1, (pixelSize.height * factor).rounded())
        )
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}

#Preview {
    AvatarCropView(
        image: UIImage(systemName: "photo")!.withTintColor(.systemTeal)
    ) { _ in }
}
