//
//  ARViewRepresentable.swift
//  lidar
//
//  Integra ARSCNView (ARKit nativo) en SwiftUI.
//

import SwiftUI
import ARKit
import SceneKit

struct ARViewRepresentable: UIViewControllerRepresentable {
    var sceneManager: ARSceneManager
    
    func makeUIViewController(context: Context) -> ARViewController {
        let vc = ARViewController()
        vc.sceneManager = sceneManager
        return vc
    }
    
    func updateUIViewController(_ uiViewController: ARViewController, context: Context) {
        let scale = sceneManager.isMeasurementMode ? CGFloat(sceneManager.measurementZoomScale) : 1.0
        uiViewController.applyZoom(scale: scale)
        
        // Deshabilitar interacción con AR cuando hay UI visible
        uiViewController.arViewInteractionEnabled = true
    }
}

final class ARViewController: UIViewController {
    var sceneManager: ARSceneManager!
    private var arView: ARSCNView!
    private var currentScale: CGFloat = 1.0
    var arViewInteractionEnabled: Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        arView = ARSCNView(frame: view.bounds)
        arView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arView.autoenablesDefaultLighting = true
        arView.debugOptions = []
        view.addSubview(arView)
        sceneManager.setSceneView(arView)
        sceneManager.startSession()
        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = self
        arView.addGestureRecognizer(longPress)
    }

    /// Aplica zoom visual por escala (1.0 = normal). Solo en modo medición se usa escala > 1.
    func applyZoom(scale: CGFloat) {
        guard let arView = arView, scale != currentScale else { return }
        currentScale = scale
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            arView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began, let arView = arView else { return }
        let location = gesture.location(in: arView)
        let hitResults = arView.hitTest(location, options: nil)
        guard let hit = hitResults.first else { return }
        let node = hit.node
        if let frameId = sceneManager.frameId(containing: node) {
            sceneManager.moveModeForFrameId = frameId
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneManager.pauseSession()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard arViewInteractionEnabled else { return }
        guard let touch = touches.first, let arView = arView else { return }
        let originalLocation = touch.location(in: arView)
        
        // Ignorar toques en la zona de la UI (usar coordenadas originales para verificar)
        // Top 120pt y bottom 400pt cuando panel expandido
        if originalLocation.y < 120 || originalLocation.y > arView.bounds.height - 400 {
            return
        }
        
        // Ajustar coordenadas por el zoom/transform aplicado para hit testing
        var location = originalLocation
        if currentScale != 1.0 {
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            location.x = center.x + (originalLocation.x - center.x) / currentScale
            location.y = center.y + (originalLocation.y - center.y) / currentScale
        }
        
        if sceneManager.isMeasurementMode {
            let types: ARHitTestResult.ResultType = [.existingPlaneUsingGeometry, .existingPlaneUsingExtent, .featurePoint]
            let results = arView.hitTest(location, types: types)
            guard let hit = results.first else { return }
            let position = hit.worldTransform.position
            sceneManager.addMeasurementPoint(position)
            
            // Feedback háptico al colocar punto
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        } else {
            let results = arView.hitTest(location, types: [.existingPlaneUsingGeometry, .existingPlaneUsingExtent])
            guard let hit = results.first else { return }
            let anchor = hit.anchor as? ARPlaneAnchor
            let position = hit.worldTransform.position
            if let moveId = sceneManager.moveModeForFrameId {
                sceneManager.moveFrame(id: moveId, to: position, planeAnchor: anchor)
                
                // Feedback háptico al mover cuadro
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
            } else {
                sceneManager.placeFrame(at: position, on: anchor)
                
                // Feedback háptico al colocar cuadro
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()
            }
        }
    }
}

// MARK: - Gesture Delegate

extension ARViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // No procesar gestos si la interacción está deshabilitada
        guard arViewInteractionEnabled else { return false }
        
        let location = touch.location(in: view)
        
        // Ignorar toques en zonas de UI (top bar y panel inferior)
        if location.y < 120 || location.y > view.bounds.height - 400 {
            return false
        }
        
        return true
    }
}

extension matrix_float4x4 {
    var position: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
