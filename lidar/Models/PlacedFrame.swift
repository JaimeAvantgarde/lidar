//
//  PlacedFrame.swift
//  lidar
//
//  Modelo que representa un cuadro/objeto colocado en la escena AR.
//

import ARKit
import SceneKit
import UIKit

/// Representa un cuadro/objeto colocado en la escena AR (foto de galería sobre pared o esquina).
final class PlacedFrame: Identifiable {
    let id: UUID
    var node: SCNNode
    var planeAnchor: ARPlaneAnchor?
    var size: CGSize
    var image: UIImage?
    /// Si true, el cuadro tiene dos caras (esquina en L).
    var isCornerFrame: Bool

    init(
        id: UUID = UUID(),
        node: SCNNode,
        planeAnchor: ARPlaneAnchor? = nil,
        size: CGSize = AppConstants.AR.defaultFrameSize,
        image: UIImage? = nil,
        isCornerFrame: Bool = false
    ) {
        self.id = id
        self.node = node
        self.planeAnchor = planeAnchor
        self.size = size
        self.image = image
        self.isCornerFrame = isCornerFrame
    }
}
