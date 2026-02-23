//
//  MagnifierLensView.swift
//  lidar
//
//  Lupa de magnificación para colocación precisa de puntos en el editor offsite.
//

import SwiftUI

/// Lupa circular que muestra la zona bajo el dedo con magnificación.
struct MagnifierLensView: View {
    let sourceImage: UIImage
    /// Posición normalizada (0-1) del toque sobre la imagen
    let touchNormalized: CGPoint

    private let magnification = AppConstants.OffsiteEditor.magnifierZoom
    private let diameter = AppConstants.OffsiteEditor.magnifierDiameter

    var body: some View {
        ZStack {
            // Imagen recortada y magnificada
            if let cropped = croppedImage() {
                Image(uiImage: cropped)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: diameter, height: diameter)
                    .clipShape(Circle())
            } else {
                Circle()
                    .fill(Color.black.opacity(0.5))
                    .frame(width: diameter, height: diameter)
            }

            // Borde exterior
            Circle()
                .strokeBorder(Color.white, lineWidth: 3)
                .frame(width: diameter, height: diameter)
                .shadow(color: .black.opacity(0.5), radius: 4, y: 2)

            // Crosshair central
            Path { path in
                let center = diameter / 2
                let halfLen: CGFloat = 12
                path.move(to: CGPoint(x: center - halfLen, y: center))
                path.addLine(to: CGPoint(x: center + halfLen, y: center))
                path.move(to: CGPoint(x: center, y: center - halfLen))
                path.addLine(to: CGPoint(x: center, y: center + halfLen))
            }
            .stroke(Color.red.opacity(0.8), lineWidth: 1)
            .frame(width: diameter, height: diameter)
        }
    }

    private func croppedImage() -> UIImage? {
        guard let cgImage = sourceImage.cgImage else { return nil }
        let imgW = CGFloat(cgImage.width)
        let imgH = CGFloat(cgImage.height)

        // Tamaño de la zona a recortar (en pixeles de la imagen)
        let cropSize = min(imgW, imgH) / magnification
        let cropX = touchNormalized.x * imgW - cropSize / 2
        let cropY = touchNormalized.y * imgH - cropSize / 2

        let cropRect = CGRect(
            x: max(0, min(cropX, imgW - cropSize)),
            y: max(0, min(cropY, imgH - cropSize)),
            width: min(cropSize, imgW),
            height: min(cropSize, imgH)
        )

        guard let croppedCG = cgImage.cropping(to: cropRect) else { return nil }
        return UIImage(cgImage: croppedCG)
    }
}
