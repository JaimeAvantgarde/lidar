# lidar — iOS ARKit (LiDAR) nativo

App iOS nativa para tablet (13") que usa **ARKit** en Swift. Arquitectura **MVVM** con servicios inyectables, testeable y preparada para conectarse con Flutter mediante un puente (Method Channel / módulo nativo).

## 🏗️ Arquitectura

### Patrón: MVVM + Services + Protocols

- **Models**: Estructuras de datos inmutables y `Codable`
- **ViewModels**: Lógica de presentación reactiva con `@Observable`
- **Views**: SwiftUI puro, sin lógica de negocio
- **Services**: Capa de infraestructura (Storage, Haptics) con protocolos para testing
- **AR Layer**: Gestión de ARKit separada del resto

### Principios aplicados

✅ **Single Responsibility**: Cada clase tiene una única responsabilidad  
✅ **Dependency Injection**: Servicios inyectados via protocolos  
✅ **Constants centralizados**: 0 magic numbers en el código  
✅ **Separation of Concerns**: Vistas, lógica, persistencia y AR separados  
✅ **Testability**: Mocks + protocolos permiten tests unitarios completos

## 📁 Estructura del proyecto

```
lidar/
├── lidarApp.swift                    # Punto de entrada
├── ContentView.swift                 # Vista principal: AR + panel Liquid Glass
├── FlutterBridge.swift               # API para conectar con Flutter (futuro)
├── Constants/
│   └── AppConstants.swift            # Todas las constantes centralizadas
├── Models/
│   ├── MeasurementModels.swift       # MeasurementUnit, ARMeasurement, PlaneDimensions
│   ├── PlacedFrame.swift             # Modelo de cuadro colocado en AR
│   └── OffsiteCapture.swift          # Modelos de captura offsite (Codable)
├── Services/
│   ├── HapticService.swift           # Feedback háptico (+ mock para tests)
│   └── StorageService.swift          # Persistencia JSON/imágenes (+ mock)
├── ViewModels/
│   └── OffsiteCapturesViewModel.swift # ViewModels para lista y detalle
├── AR/
│   ├── ARSceneManager.swift          # Sesión ARKit, planos, cuadros, medidas
│   └── ARViewRepresentable.swift     # ARSCNView en SwiftUI + raycast
├── UI/
│   ├── Components/
│   │   ├── MeasurementRowView.swift  # Fila de medición reutilizable
│   │   ├── CuadroRowView.swift       # Fila de cuadro reutilizable
│   │   └── DimensionRowView.swift    # Fila de dimensión reutilizable
│   ├── GlassModifiers.swift          # Estilo Liquid Glass: .glassEffect
│   ├── PlanosSectionView.swift       # Sección Planos: LiDAR, dimensiones
│   ├── CuadrosSectionView.swift      # Sección Cuadros: CRUD completo
│   ├── MedidasSectionView.swift      # Sección Medidas: múltiples + zoom
│   └── OffsiteCapturesView.swift     # Lista + detalle de capturas
└── Extensions/
    └── Color+Hex.swift                # Extensión para colores hexadecimales

lidarTests/
├── lidarTests.swift                   # Suite principal
├── MeasurementModelsTests.swift       # Tests de modelos de medición
├── HapticServiceTests.swift           # Tests del servicio háptico
├── StorageServiceTests.swift          # Tests del servicio de storage
├── OffsiteCaptureTests.swift          # Tests de modelos offsite
└── AppConstantsTests.swift            # Validación de constantes
```

## Requisitos

- Xcode 15+
- iOS 17.0+ (objetivo del proyecto)
- Dispositivo físico con ARKit (iPad con LiDAR recomendado para mesh y medidas)

## ✨ Funcionalidades

### 🎯 Detección AR
- **Detección de planos**: Paredes, techos y suelos con ARKit
- **LiDAR**: Mesh reconstruction y scene depth cuando está disponible
- **Dimensiones en tiempo real**: Ancho × alto de planos detectados (metros)
- **Esquinas en L**: Detección automática de intersecciones de dos paredes

### 🖼️ Cuadros (Frames)
- **Colocar fotos**: Selecciona de galería y coloca en planos detectados
- **Orientación automática**: Vertical en paredes, horizontal en techos/suelos
- **Mover**: Long press + tap en nueva posición
- **Redimensionar**: Slider con preview en tiempo real
- **Eliminar**: Borrado individual con confirmación
- **Cambiar foto**: PhotosPicker integrado para sustituir imagen

### 📏 Mediciones
- **Mediciones múltiples**: Toca dos puntos para medir distancia 3D
- **Marcadores visuales**: 
  - Punto 1: Marcador naranja
  - Punto 2: Esfera verde
  - Línea verde conectando ambos
  - Etiqueta con distancia sobre la línea
- **Zoom visual**: 1.0× a 2.5× para mediciones de precisión
  - Animación suave al cambiar
  - Corrección automática de coordenadas de toque
- **Unidades**: Metros (m) o pies (ft) con cambio en tiempo real
- **Gestión**: Eliminar individual o borrar todas

### 📸 Captura Offsite
- **Guardar escenas**: Captura foto + todas las mediciones con posiciones 2D
- **Thumbnails optimizados**: Miniaturas de 200×200 para carga rápida
- **Visor de capturas**: 
  - Lista con fecha/hora y preview
  - Swipe to delete con feedback háptico
  - Modo edición para eliminar múltiples
- **Detalle interactivo**:
  - Imagen a pantalla completa
  - Mediciones superpuestas con líneas y etiquetas
  - Cambio m/ft en tiempo real
  - Botón compartir integrado
- **Almacenamiento**: Documents/OffsiteCaptures/ (imagen JPEG + JSON)

### ✏️ **Edición Offsite (NUEVO)**
- **Modo edición completo**: Convierte capturas en lienzos editables
- **Añadir mediciones**: 
  - Toca dos puntos para medir distancias adicionales
  - Usa escala de referencia de mediciones AR originales
  - Cálculo proporcional automático
- **Añadir cuadros/marcos**:
  - Coloca rectángulos de colores sobre áreas de interés
  - 5 colores predefinidos aleatorios
  - Etiquetas editables
  - Tamaño fijo 15% × 15% de imagen
- **Anotaciones de texto**:
  - Añade notas y comentarios en cualquier posición
  - TextField integrado
  - Fondo semitransparente
- **Gestión**:
  - Eliminar elementos con botón X en modo edición
  - Guardar cambios o cancelar
  - Timestamp de última modificación
- **Persistencia**: Todos los cambios se guardan en el JSON

### ♿️ Accesibilidad
- Labels descriptivos para VoiceOver
- Hints contextuales en todos los controles
- Valores dinámicos (ej: "2.3 aumentos" en slider zoom)
- Estados deshabilitados claramente indicados

### 🎨 UX/UI
- **Liquid Glass**: Diseño iOS 26 con fallback iOS 18-25
- **Feedback háptico**: Success, error e impact según contexto
- **Mensajes inteligentes**: Conteo dinámico ("1 medición" vs "3 mediciones")
- **Panel adaptativo**: Expandir/colapsar para maximizar vista AR
- **Hints flotantes**: Guías contextuales según modo activo

## Conectar con Flutter

El archivo `FlutterBridge.swift` define:

- **Acciones** que Flutter puede enviar: `place_frame`, `move_frame`, `resize_frame`, `delete_frame`, `replace_frame`, `start_measurement`, `get_plane_dimensions`, `save_scene`, `load_scene`.
- **Eventos** que la app nativa puede enviar a Flutter: `plane_detected`, `frame_placed`, `measurement_result`, `error`.

Para integrar:

1. En el proyecto Flutter, crear un **Method Channel** (o **Event Channel** para eventos).
2. En iOS, registrar el channel en `AppDelegate` / `FlutterAppDelegate` y llamar a los métodos de `ARSceneManager` según el método invocado desde Flutter.
3. Desde nativo, usar el channel para enviar eventos (planos detectados, medidas, etc.) a Flutter.

## Cómo ejecutar

1. Abrir `lidar.xcodeproj` en Xcode.
2. Seleccionar un dispositivo físico (iPad/iPhone con ARKit).
3. Build & Run (⌘R).

**Nota:** ARKit no funciona en simulador; hace falta dispositivo real.

## 🧪 Testing

### Ejecutar tests
```bash
# Desde Xcode: ⌘U (Product > Test)
# Desde terminal:
xcodebuild test -scheme lidar -destination 'platform=iOS Simulator,name=iPad Pro (13-inch)'
```

### Cobertura de tests
- ✅ **MeasurementModelsTests**: Modelos de medición, unidades, conversiones
- ✅ **HapticServiceTests**: Mock del servicio háptico
- ✅ **StorageServiceTests**: Mock del servicio de persistencia
- ✅ **OffsiteCaptureTests**: Modelos de captura offsite, validación
- ✅ **AppConstantsTests**: Validación de rangos y valores de constantes

### Mocks disponibles
```swift
// Para testing
let hapticService = MockHapticService()
let storageService = MockStorageService()

// Uso en tests
await hapticService.impact(style: .light)
#expect(hapticService.impactCallCount == 1)
```

## 📊 Calidad de código

### Métricas
- **0 magic numbers**: Todas las constantes en `AppConstants`
- **0 force unwraps** en código de producción
- **Protocolos + DI**: 100% de servicios inyectables
- **Componentes reutilizables**: 3 vistas extraídas (MeasurementRow, CuadroRow, DimensionRow)
- **Logging centralizado**: `os.log` en ARSceneManager y servicios
- **No deprecated APIs**: Usa `raycast()` en lugar de `hitTest(types:)`

### Mejoras sobre versión anterior
| Antes | Después | Mejora |
|---|---|---|
| 831 líneas en `OffsiteCapturesView` | 400 + ViewModel separado | -53% |
| 653 líneas en `ARSceneManager` | 580 líneas (tipos extraídos) | -11% |
| Magic numbers por todo el código | `AppConstants` centralizado | 100% |
| `UIFeedbackGenerator` repetido 15 veces | `HapticService` | DRY |
| `FileManager` en vistas | `StorageService` | Separación |
| 0 tests | 5 suites, 40+ tests | ∞% |

## Cómo ejecutar

1. Abrir `lidar.xcodeproj` en Xcode.
2. Seleccionar un dispositivo físico (iPad/iPhone con ARKit).
3. Build & Run (⌘R).

**Nota:** ARKit no funciona en simulador; hace falta dispositivo real.

## Casos de uso

### 📐 Medición en obra
1. Abre la app en tablet iPad 13" con LiDAR
2. Apunta a la pared/espacio que quieres medir
3. Ve a sección **Medidas** → **Medir distancia**
4. Ajusta zoom (1.0× a 2.5×) para mayor precisión
5. Toca primer punto (marcador naranja aparece)
6. Toca segundo punto (línea verde + distancia)
7. Repite para múltiples mediciones
8. **Capturar para offsite** → guarda todo

### 📸 Revisión y edición offsite
1. En oficina/casa, abre la app
2. Toca icono **Ver capturas offsite**
3. Selecciona la captura guardada
4. Revisa todas las mediciones sobre la foto
5. **Toca "Editar"** → Modo edición activado
6. **Añade más mediciones**: Herramienta "Medir" → toca dos puntos
7. **Marca áreas**: Herramienta "Cuadro" → toca para colocar marco
8. **Añade notas**: Herramienta "Texto" → toca y escribe
9. **Elimina elementos**: Botón X en cada elemento
10. **Guarda cambios** o cancela
11. Cambia entre m/ft según necesites
12. Comparte imagen con cliente via ShareLink

### 🖼️ Planificación de arte
1. Coloca fotos de cuadros en paredes virtuales
2. Visualiza cómo quedaría el artwork
3. Ajusta tamaño con slider hasta que se vea bien
4. Mueve con long press si necesitas reposicionar
5. Captura la escena completa para presentar al cliente

## Configuración técnica

### Permisos requeridos (Info.plist)
```xml
<key>NSCameraUsageDescription</key>
<string>Necesitamos acceso a la cámara para AR y detección de planos</string>
<key>NSPhotoLibraryUsageDescription</key>
<string>Para seleccionar fotos de cuadros desde tu galería</string>
```

### Capacidades mínimas
- ARKit: Tracking básico (todos los dispositivos iOS 13+)
- LiDAR: Opcional pero recomendado (iPad Pro 2020+, iPhone 12 Pro+)
- iOS 18.0+: Para todas las características
- iOS 26.0+: Para Liquid Glass nativo (.glassEffect)

## Arquitectura de datos

### Modelos principales
```swift
// Medición 3D
struct Measurement {
    let id: UUID
    let pointA, pointB: SIMD3<Float>
    let distance: Float
}

// Captura offsite
struct OffsiteCaptureData: Codable {
    let capturedAt: Date
    let measurements: [OffsiteMeasurement]  // Con posiciones 2D normalizadas
}

// Cuadro colocado
class PlacedFrame {
    let id: UUID
    var node: SCNNode
    var planeAnchor: ARPlaneAnchor?
    var size: CGSize
    var image: UIImage?
    var isCornerFrame: Bool
}
```

### Almacenamiento
```
Documents/OffsiteCaptures/
├── capture_20260209_143022.jpg        # Imagen capturada
├── capture_20260209_143022_thumb.jpg  # Thumbnail 200×200
└── capture_20260209_143022.json       # Mediciones + metadata
```

## Mejoras futuras

- [ ] Exportar mediciones a PDF/CSV con anotaciones
- [ ] Modo AR compartido (múltiples usuarios)
- [ ] Reconocimiento de objetos (puertas, ventanas)
- [ ] Planos arquitectónicos 2D desde mediciones
- [ ] Integración con Flutter via Method Channel
- [ ] Cloud sync de capturas offsite
- [x] ~~Anotaciones de texto sobre capturas~~ ✅ **v1.2.0**
- [ ] Modo "tour virtual" entre capturas
- [ ] Flechas y formas adicionales (círculos, líneas libres)
- [ ] Editar tamaño/color de cuadros existentes
- [ ] Capas y grupos de anotaciones
- [ ] Deshacer/rehacer en modo edición

---

📝 Ver [CHANGELOG.md](./CHANGELOG.md) para historial completo de versiones.
