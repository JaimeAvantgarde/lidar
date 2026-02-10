# Changelog - lidar App

## [2.0.0] - 2026-02-10 🏗️ REFACTOR ARQUITECTÓNICO

### 🏗️ Arquitectura MVVM + Services

#### Nueva estructura de carpetas
```
lidar/
├── Constants/        # Todas las constantes centralizadas
├── Models/           # Modelos de dominio separados por responsabilidad
├── Services/         # Capa de servicios con protocolos
├── ViewModels/       # Lógica de presentación separada de vistas
├── AR/               # Capa de ARKit
├── UI/
│   ├── Components/   # Componentes reutilizables
│   └── ...          # Vistas principales
└── Extensions/       # Extensiones Swift
```

#### Servicios creados
- **HapticService**: Feedback háptico centralizado
  - Protocolo `HapticServiceProtocol` para DI
  - `MockHapticService` para tests
  - Elimina 15+ duplicaciones de `UIFeedbackGenerator`
- **StorageService**: Persistencia JSON e imágenes
  - Protocolo `StorageServiceProtocol` para DI
  - `MockStorageService` para tests
  - Maneja FileManager, codificación y thumbnails
  - Logging con `os.log`

#### Constants (`AppConstants`)
- **Layout**: Zonas de exclusión, paddings, corner radius
- **AR**: Tamaños de objetos 3D, umbrales de detección
- **Capture**: Calidad JPEG, tamaños de thumbnail
- **Measurement**: Factores de conversión, rangos de zoom
- **Cuadros**: Rangos de tamaño, aspect ratio
- **OffsiteEditor**: Tamaños normalizados, colores
- **Animation**: Springs, duraciones

**Eliminados 50+ magic numbers** del código

#### ViewModels creados
- **OffsiteCapturesListViewModel**:
  - Gestión de lista de capturas
  - Delegación a `StorageService`
  - Separado de la vista (antes 831 líneas)
- **OffsiteCaptureDetailViewModel**:
  - Lógica de edición de capturas
  - Cálculo de distancias offsite
  - Gestión de herramientas de edición

#### Componentes UI extraídos
- **MeasurementRowView**: Fila de medición reutilizable
- **CuadroRowView**: Fila de cuadro reutilizable
- **DimensionRowView**: Fila de dimensión reutilizable

Antes: Duplicados en cada sección  
Después: Componentes compartidos con accesibilidad

#### Modelos refactorizados
**MeasurementModels.swift**:
- `MeasurementUnit` (extraído de ARSceneManager)
- `ARMeasurement` (renombrado de `Measurement`)
- `PlaneDimensions` (extraído)

**PlacedFrame.swift**:
- Extraído de ARSceneManager a su propio archivo
- Usa `AppConstants.AR.defaultFrameSize`

**OffsiteCapture.swift**:
- `OffsiteCaptureEntry` añadido (antes en view)
- `NormalizedPoint.isValid` validación añadida

#### ARSceneManager refactorizado
- ✅ Tipos extraídos a Models/
- ✅ Inyección de `StorageService`
- ✅ Usa `AppConstants` en lugar de literales
- ✅ Logging con `os.log`
- ✅ Delegación de persistencia a servicio
- Reducción: **653 → 580 líneas** (-11%)

#### ARViewRepresentable refactorizado
- ✅ **Eliminado force unwrap** (`var sceneManager: ARSceneManager?`)
- ✅ **Deprecated API reemplazada**: `hitTest()` → `raycast()`
- ✅ Usa `HapticService` en lugar de generators inline
- ✅ Usa `AppConstants.Layout` para zonas de exclusión
- ✅ Método `performRaycast()` encapsula lógica de raycast

#### ContentView refactorizado
- ✅ Usa `HapticService`
- ✅ Usa `AppConstants.Layout` y `AppConstants.Animation`
- Código más limpio y mantenible

#### Secciones refactorizadas
**MedidasSectionView**:
- Usa `MeasurementRowView` extraído
- Usa `HapticService`
- Usa `AppConstants.Measurement`

**CuadrosSectionView**:
- Usa `CuadroRowView` extraído
- Usa `AppConstants.Cuadros`
- Eliminada duplicación de estructura `CuadroRow`

**PlanosSectionView**:
- Usa `DimensionRowView` extraído
- Componente reutilizable con accesibilidad

#### OffsiteCapturesView refactorizado
- ✅ Usa `OffsiteCapturesListViewModel`
- ✅ Usa `HapticService`
- ✅ Usa `AppConstants.OffsiteEditor`
- ✅ `Color(hex:)` extraído a Extensions/
- Reducción: **831 → ~400 líneas** (-52%)

### 🧪 Testing

#### Tests unitarios creados
- **MeasurementModelsTests**: 8 tests
  - Format meters/feet
  - Value conversion
  - ARMeasurement equality
  - PlaneDimensions equality
- **HapticServiceTests**: 3 tests
  - Mock impact tracking
  - Mock notification tracking
  - Reset functionality
- **StorageServiceTests**: 7 tests
  - Mock load/save/delete
  - Error handling
  - Create capture files
- **OffsiteCaptureTests**: 11 tests
  - NormalizedPoint validation
  - OffsiteMeasurement flags
  - OffsiteFrame defaults
  - OffsiteCaptureEntry hashable
- **AppConstantsTests**: 11 tests
  - Validación de rangos
  - Valores positivos
  - Consistencia de constantes

**Total: 5 suites, 40+ tests**

### 📚 Documentación

#### README actualizado
- ✅ Sección arquitectura MVVM + Services
- ✅ Estructura de carpetas actualizada
- ✅ Sección de testing con comandos
- ✅ Métricas de calidad de código
- ✅ Tabla de mejoras (antes/después)

#### Comentarios y logging
- `os.log` en ARSceneManager
- `os.log` en StorageService
- Comentarios DocC en servicios

### 🔧 Mejoras técnicas

#### Separación de responsabilidades
- **Antes**: Lógica de negocio en vistas (I/O, cálculos)
- **Después**: Vistas puras + ViewModels + Servicios

#### Dependency Injection
- **Antes**: `@State private var sceneManager = ARSceneManager()`
- **Después**: Servicios inyectados via protocolos

#### Testability
- **Antes**: 0 tests, código acoplado a UIKit
- **Después**: Mocks + protocolos, 40+ tests

#### Code quality
- **Magic numbers**: 50+ → 0
- **Force unwraps**: Varios → 0 (producción)
- **Deprecated APIs**: `hitTest()` → `raycast()`
- **Duplicación**: Generators repetidos → Service
- **Archivos largos**: 831 líneas → 400 líneas

### 🎯 Principios SOLID aplicados

| Principio | Implementación |
|---|---|
| **S** Single Responsibility | ViewModels, Services separados |
| **O** Open/Closed | Protocolos permiten extensión sin modificación |
| **L** Liskov Substitution | Mocks intercambiables con implementaciones reales |
| **I** Interface Segregation | Protocolos específicos (HapticServiceProtocol, etc.) |
| **D** Dependency Inversion | Dependencias via protocolos, no implementaciones |

---

## [1.2.0] - 2026-02-09

### ✨ Nuevas características - Edición Offsite

#### Editor completo de capturas
- **Modo edición**: Botón "Editar" en menú de captura para activar modo edición
- **Añadir mediciones**: Toca dos puntos para medir distancias adicionales sobre la foto
  - Usa escala de referencia de mediciones existentes
  - Marcadores visuales naranja/verde
  - Cálculo automático de distancia proporcional
- **Añadir cuadros/marcos**: Coloca rectángulos de colores sobre la imagen
  - Tamaño fijo 15% × 15%
  - 5 colores aleatorios (azul, verde, naranja, rojo, morado)
  - Etiquetas automáticas ("Cuadro 1", "Cuadro 2"...)
- **Anotaciones de texto**: Añade notas y etiquetas en cualquier posición
  - Input de texto con TextField
  - Fondo semitransparente para legibilidad
- **Eliminar elementos**: Botones X en cada elemento cuando estás en modo edición
- **Guardar/Cancelar**: Toolbar con "Guardar" (persiste cambios) o "Cancelar" (descarta)

#### Mejoras de persistencia
- **Campo `lastModified`**: Timestamp de última edición
- **Arrays editables**: `measurements`, `frames`, `textAnnotations` son `var`
- **Pretty JSON**: Formato legible con indentación

#### UX en edición
- **Toolbar inferior**: 3 herramientas (Medir, Cuadro, Texto)
- **Estados visuales**: Herramienta activa con fondo azul
- **Feedback háptico**: Success al añadir, impact al borrar
- **Gestos**: DragGesture para capturar toques sin interferir con scroll

### 🔧 Mejoras UX general

#### Protección de UI
- **Zonas de exclusión**: Toques en barra superior (120px) y panel (400px) NO activan AR
- **Gesture delegate**: Long press respeta zonas de UI
- **Hit testing inteligente**: Solo registra toques en zona AR válida
- **Background transparente**: Captura toques en UI sin mostrar nada

### 📊 Modelo de datos extendido

```swift
struct OffsiteFrame: Codable, Identifiable {
    var id: UUID
    let topLeft: NormalizedPoint
    let width, height: Double  // Normalizado 0-1
    var label: String?
    var color: String  // Hex "#RRGGBB"
}

struct OffsiteTextAnnotation: Codable, Identifiable {
    var id: UUID
    let position: NormalizedPoint
    var text: String
    var color: String
}

struct OffsiteCaptureData: Codable {
    let capturedAt: Date
    var measurements: [OffsiteMeasurement]
    var frames: [OffsiteFrame]
    var textAnnotations: [OffsiteTextAnnotation]
    var lastModified: Date?
}
```

---

## [1.1.0] - 2026-02-09

### ✨ Nuevas características

#### Captura Offsite
- **Captura de escenas AR**: Guarda la vista actual con todas las mediciones para revisión posterior
- **Thumbnails optimizados**: Generación automática de miniaturas para carga rápida en la lista
- **Visor de capturas**: Visualiza capturas guardadas con mediciones superpuestas
- **Compartir capturas**: Exporta imágenes con mediciones via ShareLink
- **Swipe to delete**: Elimina capturas deslizando en la lista

#### Zoom mejorado
- **Zoom visual**: Sistema de zoom por escala de vista (1.0× a 2.5×)
- **Corrección de coordenadas**: Hit testing ajustado para precisión con zoom activo
- **Animación suave**: Transición animada al cambiar nivel de zoom
- **Optimización**: Solo aplica transform cuando el valor cambia

### 🔧 Mejoras

#### Experiencia de usuario
- **Feedback háptico**: Vibraciones contextuales en todas las acciones importantes
  - Success: Al capturar offsite exitosamente
  - Error: Al fallar captura o eliminar mediciones
  - Impact: Al iniciar mediciones o eliminar elementos
- **Accesibilidad mejorada**: Labels, hints y valores para VoiceOver
- **Mensajes descriptivos**: Alertas más claras con conteo de mediciones
- **Botones deshabilitados**: Captura offsite deshabilitada sin mediciones

#### Rendimiento
- **Carga optimizada de thumbnails**: Prioriza miniaturas sobre imágenes completas
- **Pretty JSON**: Formato legible para debugging
- **Estado de zoom**: Evita aplicar transform innecesariamente

#### Robustez
- **Manejo de errores tipado**: `CaptureError` enum con casos específicos
- **Errores localizados**: Mensajes de error claros y específicos
- **Try-catch pattern**: Manejo explícito de errores en lugar de optionals
- **Validación de bounds**: Verifica dimensiones válidas antes de capturar

### 🐛 Correcciones

- **Fix**: CGAffineTransform usa parámetro `y:` en lugar de `scaleY:`
- **Fix**: Coordenadas de toque incorrectas con zoom aplicado
- **Fix**: Transform aplicado innecesariamente en cada update

### 📚 Documentación

- Actualizado README.md con nuevas características
- Añadido CHANGELOG.md para seguimiento de versiones
- Comentarios mejorados en código crítico

---

## [1.0.0] - 2026-02-09

### Funcionalidades iniciales

- Detección de planos con ARKit + LiDAR
- Colocación de cuadros (fotos) en paredes, techos y esquinas
- Sistema de mediciones múltiples con marcadores visuales
- Interfaz Liquid Glass con 3 secciones (Planos, Cuadros, Medidas)
- Unidades métricas e imperiales (m/ft)
- Mover/redimensionar/eliminar cuadros
- Cambiar foto de cuadros desde galería
- Orientación automática según tipo de plano
- UI adaptativa iPad 13"
