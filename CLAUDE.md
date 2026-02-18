# CLAUDE.md — lidar (iOS ARKit App)

## Proyecto
App iOS nativa para iPad/iPhone con **ARKit + LiDAR**. Mide distancias, detecta planos/esquinas, coloca cuadros en paredes, y captura todo para edición offsite.

## Build & Run
```bash
# Build (no funciona en simulador, necesita dispositivo real para AR)
xcodebuild build -scheme lidar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'

# Tests
xcodebuild test -scheme lidar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```
- **Target**: iOS 18.0+ (Liquid Glass requiere iOS 26+)
- **Sin CocoaPods/SPM** — todo nativo (ARKit, SceneKit, SwiftUI)

## Arquitectura

**MVVM + Services + Protocols**

```
lidar/
├── ContentView.swift              # Vista principal AR + barra Liquid Glass
├── Constants/AppConstants.swift   # TODAS las constantes (0 magic numbers)
├── Models/
│   ├── MeasurementModels.swift    # MeasurementUnit, ARMeasurement
│   ├── PlacedFrame.swift          # Cuadro colocado en escena AR (SCNNode)
│   ├── OffsiteCapture.swift       # Modelos offsite: NormalizedPoint, OffsiteMeasurement,
│   │                              #   OffsiteFrame, OffsiteTextAnnotation, SelectableItemType
│   └── SceneExportModels.swift    # OffsiteSceneSnapshot, OffsiteCameraData,
│                                  #   OffsitePlaneData, OffsiteCornerData, OffsiteFramePerspective
├── Services/
│   ├── StorageService.swift       # Persistencia JSON/imágenes (protocolo + implementación)
│   └── HapticService.swift        # Feedback háptico (protocolo + implementación)
├── ViewModels/
│   └── OffsiteCapturesViewModel.swift  # ListViewModel + DetailViewModel
├── AR/
│   ├── ARSceneManager.swift       # Sesión ARKit, planos, cuadros, medidas, captureForOffsite()
│   └── ARViewRepresentable.swift  # ARSCNView wrapper para SwiftUI
├── UI/
│   ├── OffsiteCapturesView.swift  # Lista + detalle + editor offsite
│   ├── Components/
│   │   └── OffsiteSceneRenderer.swift  # Overlays: planos, esquinas, mediciones, cuadros, drag handles
│   └── GlassModifiers.swift       # Estilo Liquid Glass
└── Extensions/
    └── Color+Hex.swift
```

## Convenciones

- **@Observable + @MainActor** para ViewModels (no Combine)
- **Dependency Injection** via protocolos (`StorageServiceProtocol`, `HapticServiceProtocol`)
- **Constantes** siempre en `AppConstants` — nunca magic numbers en código
- **Coordenadas normalizadas** (0-1) para posiciones 2D en capturas offsite
- **Idioma**: código en inglés, comentarios y UI en español
- Toda la lógica de negocio en ViewModels, las vistas son solo presentación

## Sistema Offsite — Flujo Completo

### Captura (on-site)
`ContentView` → botón cámara → `ARSceneManager.captureForOffsite()`:

1. Captura screenshot del ARSCNView a resolución retina
2. Proyecta todas las mediciones 3D a coordenadas 2D normalizadas (`projectPoint()`)
3. Proyecta los 4 corners de cada cuadro para perspectiva real
4. Exporta todos los planos con vértices proyectados, clasificación, transforms
5. Detecta y exporta esquinas (intersecciones de planos)
6. Guarda datos de cámara (intrínsecos + transform) para reconstrucción
7. Calcula dimensiones de paredes
8. Empaqueta todo en `OffsiteSceneSnapshot` → `OffsiteCaptureData`
9. Guarda: `.jpg` (imagen) + `.json` (datos completos) + `_thumb.jpg`

### Almacenamiento
```
Documents/OffsiteCaptures/
├── capture_YYYYMMDD_HHmmss.jpg        # Imagen alta resolución
├── capture_YYYYMMDD_HHmmss_thumb.jpg  # Thumbnail 200x200
└── capture_YYYYMMDD_HHmmss.json       # OffsiteCaptureData completo
```

### Editor Offsite (off-site)
`OffsiteCapturesListView` → `OffsiteCaptureDetailView` + `OffsiteCaptureDetailViewModel`:

**Herramientas** (enum `EditTool`):
- `.select` — Seleccionar + arrastrar elementos (default al editar)
- `.measure` — Añadir mediciones (2 taps)
- `.frame` — Añadir cuadros simples
- `.placeFrame` — Colocar cuadro en pared detectada (con perspectiva)
- `.text` — Añadir anotaciones de texto

**Funcionalidades**:
- Hit testing con 5 niveles de prioridad (endpoints > texto > cuadros > perspectiva > líneas)
- Drag & drop de todos los elementos (mediciones, cuadros, texto)
- Recálculo automático de distancia al mover endpoints (solo mediciones no-AR)
- Fotos en cuadros (standard + perspectiva) via PhotosPicker
- Capas 3D toggleables: planos, esquinas, cotas de paredes, cuadros perspectiva
- Snapshot para undo (cancelar restaura estado original)
- Barra de acciones contextual con "Foto" y "Eliminar" (con confirmación)

## Geometría de Escala — Importante

Las coordenadas normalizadas NO son isométricas (x=0.1 ≠ y=0.1 en pixeles reales por el aspect ratio).

**`metersPerPixelScale`** (`SceneExportModels.swift`):
- Calcula metros/pixel REAL usando `camera.imageWidth/Height`
- Convierte coords normalizadas a pixeles antes de dividir
- Fórmula: `distancia_metros_AR / sqrt((dx*imgW)² + (dy*imgH)²)`

**`recalculateDistance`** (`OffsiteCapturesViewModel.swift`):
- Usa `camera.imageWidth/Height` si están disponibles (consistente con escala)
- Fallback a `imageSize` (UIImage.size en puntos) si no hay datos de cámara
- Prioridad: snapshot.metersPerPixelScale > medición AR directa > estimación

**Nunca** calcular distancias con `sqrt(dx² + dy²)` sin convertir a pixeles primero.

## Modelos Clave

```swift
// Coordenada 2D normalizada (0-1) sobre la imagen
struct NormalizedPoint: Codable { x: Double, y: Double }

// Medición con origen AR o offsite
struct OffsiteMeasurement: Codable {
    var distanceMeters: Double
    var pointA, pointB: NormalizedPoint
    let isFromAR: Bool  // true = precisa AR, false = estimada offsite
}

// Elemento seleccionable en editor
enum SelectableItemType: Equatable {
    case measurement(UUID), measurementEndpointA(UUID), measurementEndpointB(UUID)
    case frame(UUID), perspectiveFrame(UUID), textAnnotation(UUID)
    var itemId: UUID  // UUID compartido para todas las variantes del mismo item
}

// Snapshot completo de la escena 3D
struct OffsiteSceneSnapshot: Codable {
    let camera: OffsiteCameraData?     // Intrínsecos + transform
    var planes: [OffsitePlaneData]     // Planos con vértices proyectados
    var corners: [OffsiteCornerData]   // Esquinas detectadas
    var wallDimensions: [OffsiteWallDimension]
    var measurements: [OffsiteMeasurement]
    var perspectiveFrames: [OffsiteFramePerspective]  // Cuadros con 4 corners 2D
    var metersPerPixelScale: Double?   // Calculado desde mediciones AR
}
```

## Testing

- Tests en `lidarTests/` — modelos, servicios (con mocks), constantes
- Mocks: `MockStorageService`, `MockHapticService`
- Build en simulador funciona, pero AR necesita dispositivo real
