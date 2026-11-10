import PhotosUI
import SwiftUI
import UIKit

// MARK: - Storage

/// Durable on-disk store for the owner's portrait. Lives in Application
/// Support (survives updates, excluded from iCloud by default). Kept outside
/// `GameStore` so the save file stays pure game state.
@MainActor
@Observable
final class AvatarStore {
    static let shared = AvatarStore()

    private(set) var image: UIImage?

    private var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("portrait.rvty.jpg")
    }

    private init() {
        if let data = try? Data(contentsOf: fileURL),
           let img = UIImage(data: data) {
            image = img
        }
    }

    func update(_ raw: UIImage) {
        let squared = raw.croppedToSquare().scaled(maxDimension: 512)
        image = squared
        if let data = squared.jpegData(compressionQuality: 0.82) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func clear() {
        image = nil
        try? FileManager.default.removeItem(at: fileURL)
    }
}

// MARK: - Badge button

/// Round portrait placeholder that invites a tap when empty. The action sheet
/// is wired by the caller — this view only renders the mark.
struct AvatarBadge: View {
    var image: UIImage?
    var diameter: CGFloat = 86

    var body: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [Theme.panelHi, Theme.panel],
                        startPoint: .top, endPoint: .bottom
                    )
                )
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle().stroke(
                        LinearGradient(
                            colors: [Theme.gold, Theme.goldDeep.opacity(0.4)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 2
                    )
                )

            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: diameter - 6, height: diameter - 6)
                    .clipShape(Circle())
            } else {
                Image(systemName: "person.crop.circle.badge.plus")
                    .font(.system(size: diameter * 0.44, weight: .regular))
                    .foregroundStyle(Theme.gold)
            }

            // Small camera glyph bottom-right.
            Circle()
                .fill(Theme.gold)
                .frame(width: diameter * 0.30, height: diameter * 0.30)
                .overlay(
                    Image(systemName: "camera.fill")
                        .font(.system(size: diameter * 0.15, weight: .bold))
                        .foregroundStyle(.black)
                )
                .offset(
                    x: diameter * 0.32,
                    y: diameter * 0.32
                )
        }
        .frame(width: diameter, height: diameter)
    }
}

// MARK: - Camera (UIImagePickerController)

/// Native camera capture. Requires `NSCameraUsageDescription`.
struct CameraCapture: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let vc = UIImagePickerController()
        vc.sourceType = .camera
        vc.allowsEditing = true
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func imagePickerController(
            _ picker: UIImagePickerController,
            didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]
        ) {
            let chosen = (info[.editedImage] as? UIImage) ?? (info[.originalImage] as? UIImage)
            picker.dismiss(animated: true) { [onPicked] in
                if let chosen { onPicked(chosen) }
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}

// MARK: - Photo library (PHPickerViewController, permission-free)

/// Picks a single photo via the modern `PHPickerViewController`. No photo
/// library permission entry is required — the picker runs out of process.
struct LibraryCapture: UIViewControllerRepresentable {
    var onPicked: (UIImage) -> Void

    func makeUIViewController(context: Context) -> PHPickerViewController {
        var cfg = PHPickerConfiguration()
        cfg.filter = .images
        cfg.selectionLimit = 1
        let vc = PHPickerViewController(configuration: cfg)
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ vc: PHPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onPicked: onPicked) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let onPicked: (UIImage) -> Void
        init(onPicked: @escaping (UIImage) -> Void) { self.onPicked = onPicked }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            guard let provider = results.first?.itemProvider,
                  provider.canLoadObject(ofClass: UIImage.self) else { return }
            provider.loadObject(ofClass: UIImage.self) { [onPicked] obj, _ in
                guard let img = obj as? UIImage else { return }
                DispatchQueue.main.async { onPicked(img) }
            }
        }
    }
}

// MARK: - Image helpers

private extension UIImage {
    /// Centre-crop to a square, in pixels, preserving orientation.
    func croppedToSquare() -> UIImage {
        let side = min(size.width, size.height)
        let origin = CGPoint(x: (size.width - side) / 2, y: (size.height - side) / 2)
        let rect = CGRect(origin: origin, size: CGSize(width: side, height: side))
        guard let cg = cgImage?.cropping(to: rect.applying(CGAffineTransform(scaleX: scale, y: scale)))
        else { return self }
        return UIImage(cgImage: cg, scale: scale, orientation: imageOrientation)
    }

    /// Downsize so the longer edge equals `maxDimension` (in points). JPEG
    /// compression later keeps storage under a few hundred kB.
    func scaled(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension else { return self }
        let factor = maxDimension / longest
        let newSize = CGSize(width: size.width * factor, height: size.height * factor)
        let renderer = UIGraphicsImageRenderer(size: newSize)
        return renderer.image { _ in draw(in: CGRect(origin: .zero, size: newSize)) }
    }
}
