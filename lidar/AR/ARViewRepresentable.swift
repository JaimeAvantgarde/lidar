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
        uiViewController.syncDebugOptions(sceneManager: sceneManager)

        // Deshabilitar interacción con AR cuando hay UI visible
        uiViewController.arViewInteractionEnabled = true
    }
}

final class ARViewController: UIViewController {
    var sceneManager: ARSceneManager?
    private var arView: ARSCNView?
    private var coachingOverlay: ARCoachingOverlayView?
    private var currentScale: CGFloat = 1.0
    var arViewInteractionEnabled: Bool = true
    
    override func viewDidLoad() {
        super.viewDidLoad()
        guard let sceneManager = sceneManager else { return }

        let arSCNView = ARSCNView(frame: view.bounds)
        arSCNView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        arSCNView.autoenablesDefaultLighting = true
        arSCNView.debugOptions = []
        view.addSubview(arSCNView)
        self.arView = arSCNView

        // Coaching overlay — guía visual de Apple para AR
        let coaching = ARCoachingOverlayView()
        coaching.session = arSCNView.session
        coaching.delegate = self
        coaching.goal = .anyPlane
        coaching.activatesAutomatically = true
        coaching.translatesAutoresizingMaskIntoConstraints = false
        arSCNView.addSubview(coaching)
        NSLayoutConstraint.activate([
            coaching.topAnchor.constraint(equalTo: arSCNView.topAnchor),
            coaching.leadingAnchor.constraint(equalTo: arSCNView.leadingAnchor),
            coaching.trailingAnchor.constraint(equalTo: arSCNView.trailingAnchor),
            coaching.bottomAnchor.constraint(equalTo: arSCNView.bottomAnchor)
        ])
        self.coachingOverlay = coaching

        sceneManager.setSceneView(arSCNView)
        sceneManager.startSession()

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.5
        longPress.delegate = self
        arSCNView.addGestureRecognizer(longPress)
    }

    /// Aplica zoom visual por escala (1.0 = normal). Solo en modo medición se usa escala > 1.
    func applyZoom(scale: CGFloat) {
        guard let arView = arView, scale != currentScale else { return }
        currentScale = scale
        UIView.animate(withDuration: 0.2, delay: 0, options: .curveEaseInOut) {
            arView.transform = CGAffineTransform(scaleX: scale, y: scale)
        }
    }

    /// Sincroniza las opciones de debug de la vista AR con el estado del sceneManager.
    func syncDebugOptions(sceneManager: ARSceneManager) {
        guard let arView = arView else { return }
        if sceneManager.showFeaturePoints {
            arView.debugOptions.insert(.showFeaturePoints)
        } else {
            arView.debugOptions.remove(.showFeaturePoints)
        }
    }

    @objc private func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
        guard gesture.state == .began,
              let arView = arView,
              let sceneManager = sceneManager else { return }
        let location = gesture.location(in: arView)
        let hitResults = arView.hitTest(location, options: nil)
        guard let hit = hitResults.first else { return }
        if let frameId = sceneManager.frameId(containing: hit.node) {
            sceneManager.moveModeForFrameId = frameId
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneManager?.pauseSession()
    }
    
    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard arViewInteractionEnabled,
              let touch = touches.first,
              let arView = arView,
              let sceneManager = sceneManager else { return }
        let originalLocation = touch.location(in: arView)

        // Ignorar toques en zonas de UI (top bar y panel inferior)
        if originalLocation.y < AppConstants.Layout.topBarExclusionZone
            || originalLocation.y > arView.bounds.height - AppConstants.Layout.bottomPanelExclusionZone {
            return
        }

        // Ajustar coordenadas por zoom/transform para hit testing
        var location = originalLocation
        if currentScale != 1.0 {
            let center = CGPoint(x: arView.bounds.midX, y: arView.bounds.midY)
            location.x = center.x + (originalLocation.x - center.x) / currentScale
            location.y = center.y + (originalLocation.y - center.y) / currentScale
        }

        if sceneManager.isMeasurementMode {
            // Raycast: intentar planos existentes, luego planos estimados
            if let result = performRaycast(from: location, arView: arView, allowEstimated: true) {
                let position = result.worldTransform.position
                sceneManager.addMeasurementPoint(position)
                HapticService.shared.impact(style: .medium)
            }
        } else {
            // Raycast solo sobre planos existentes
            if let result = performRaycast(from: location, arView: arView, allowEstimated: false) {
                let anchor = result.anchor as? ARPlaneAnchor
                let position = result.worldTransform.position
                if let moveId = sceneManager.moveModeForFrameId {
                    sceneManager.moveFrame(id: moveId, to: position, planeAnchor: anchor)
                    HapticService.shared.notification(type: .success)
                } else if sceneManager.isVinylMode, let wallAnchor = anchor, wallAnchor.alignment == .vertical {
                    sceneManager.placeVinyl(on: wallAnchor)
                    HapticService.shared.notification(type: .success)
                } else {
                    sceneManager.placeFrame(at: position, on: anchor)
                    HapticService.shared.impact(style: .light)
                }
            }
        }
    }

    // MARK: - Raycast Helper

    /// Realiza un raycast desde un punto de pantalla. Usa `ARSession.raycast` en lugar del deprecated `hitTest`.
    private func performRaycast(from location: CGPoint, arView: ARSCNView, allowEstimated: Bool) -> ARRaycastResult? {
        // Intentar planos existentes con geometría
        if let query = arView.raycastQuery(from: location, allowing: .existingPlaneGeometry, alignment: .any) {
            if let result = arView.session.raycast(query).first {
                return result
            }
        }
        // Fallback a planos estimados (para medición)
        if allowEstimated {
            if let query = arView.raycastQuery(from: location, allowing: .estimatedPlane, alignment: .any) {
                return arView.session.raycast(query).first
            }
        }
        return nil
    }
}

// MARK: - Gesture Delegate

extension ARViewController: UIGestureRecognizerDelegate {
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        guard arViewInteractionEnabled else { return false }
        let location = touch.location(in: view)
        // Ignorar toques en zonas de UI (top bar y panel inferior)
        if location.y < AppConstants.Layout.topBarExclusionZone
            || location.y > view.bounds.height - AppConstants.Layout.bottomPanelExclusionZone {
            return false
        }
        return true
    }
}

// MARK: - AR Coaching Overlay Delegate

extension ARViewController: ARCoachingOverlayViewDelegate {
    func coachingOverlayViewWillActivate(_ coachingOverlayView: ARCoachingOverlayView) {
        // Ocultar UI mientras se muestra la guía
        arViewInteractionEnabled = false
    }
    
    func coachingOverlayViewDidDeactivate(_ coachingOverlayView: ARCoachingOverlayView) {
        // Restaurar interacción cuando el tracking es bueno
        arViewInteractionEnabled = true
    }
}

extension matrix_float4x4 {
    var position: SIMD3<Float> {
        SIMD3<Float>(columns.3.x, columns.3.y, columns.3.z)
    }
}
