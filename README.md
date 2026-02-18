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

## Guia de uso

### Paso 1: Escaneo inicial (30-60 segundos)

La calidad de todo lo que hagas despues depende de un buen escaneo. Dedica tiempo a esta fase.

1. Abre la app y **mueve el dispositivo lentamente** apuntando al **suelo** primero — esto establece el tracking base
2. Luego **escanea las paredes** con un movimiento horizontal suave, de izquierda a derecha, cubriendo toda la superficie
3. Manten el dispositivo a **1-2 metros** de la pared. Demasiado cerca o lejos reduce la precision
4. **No te muevas rapido** — movimientos bruscos degradan el tracking y generan mesh de baja calidad
5. Espera a que aparezcan los contadores de planos en el badge superior

**Tips de escaneo:**
- Empieza siempre por el suelo, luego paredes, luego techo
- Las esquinas (donde dos paredes se juntan) requieren escaneo mas lento para que se detecten bien
- Si un plano no aparece, alejate un poco y vuelve a apuntar

### Paso 2: Verificar la deteccion

Antes de medir o colocar cuadros, verifica que la app ha entendido el espacio.

1. Ve a la pestana **Planos**
2. Activa **"Planos"** (toggle azul) — veras rectangulos semitransparentes sobre las superficies detectadas
3. Si tienes LiDAR, activa **"Malla 3D"** (toggle cyan) — veras el wireframe completo de la reconstruccion 3D. Donde hay malla, hay datos precisos
4. Activa **"Puntos de tracking"** (toggle naranja) — los puntos amarillos indican donde ARKit tiene buena referencia visual. Si hay zonas sin puntos, escanealas mas
5. Revisa la lista de planos detectados: comprueba que las dimensiones (ancho x alto) tienen sentido

**Indicadores de buena deteccion:**
- Paredes cubiertas con overlay azul
- Esquinas detectadas (aparecen en la seccion de esquinas con angulo ~90°)
- Malla 3D densa y uniforme (sin huecos grandes)

### Paso 3: Medir distancias

1. Ve a la pestana **Medidas** → toca **"Medir distancia"**
2. La app entra en modo medicion (hint flotante lo indica)
3. Apunta al primer punto y **toca la pantalla** — aparece un marcador naranja
4. Apunta al segundo punto y **toca** — aparece la linea verde con la distancia
5. La medicion queda guardada en la lista inferior

**Precision maxima:**
- Activa **"Snap a bordes"** en la seccion Planos — los puntos se ajustan automaticamente a bordes y esquinas de los planos detectados (marcador amarillo = esquina, cyan = borde)
- Usa el **slider de zoom** (1.0x a 2.5x) para apuntar con mas precision a puntos lejanos
- Con LiDAR la precision es ~1cm, sin LiDAR ~5cm

### Paso 4: Colocar cuadros y vinilos

**Cuadro normal (foto enmarcada en la pared):**
1. Ve a la pestana **Cuadros**
2. Toca **"Elegir foto"** y selecciona una imagen de la galeria
3. Toca directamente en una pared en la vista AR — el cuadro se coloca ahi
4. Usa el **slider de tamano** para ajustar
5. **Long-press** sobre el cuadro para activar modo mover → toca la nueva posicion

**Vinilo (imagen que cubre toda la pared):**
1. Selecciona una foto de galeria
2. Toca **"Cubrir pared"**
3. Toca la pared en AR — la imagen se estira cubriendo toda la superficie detectada
4. El modo se desactiva automaticamente despues de colocar

**Cuadros en esquina (L):**
- Si tocas cerca de donde dos paredes se juntan, la app automaticamente crea un cuadro en L que se adapta a ambas superficies

### Paso 5: Capturar para edicion offsite

Cuando tengas todo preparado (mediciones + cuadros + planos):

1. Pulsa el **icono de camara** (arriba a la derecha)
2. Se guarda: imagen alta resolucion + todos los datos 3D en JSON + thumbnail
3. Aparece un resumen con lo que se ha capturado

### Paso 6: Edicion offsite (sin AR)

En la oficina o en casa, sin necesidad de volver al sitio:

1. Toca el icono **"Ver capturas"** (arriba a la derecha)
2. Selecciona una captura de la lista
3. Toca **"Editar"** para activar las herramientas:
   - **Seleccionar**: Toca y arrastra mediciones, cuadros o texto
   - **Medir**: Anade mediciones nuevas (usa la escala AR de referencia)
   - **Cuadro**: Anade marcos rectangulares de colores
   - **Colocar en pared**: Coloca cuadros con perspectiva sobre paredes detectadas
   - **Texto**: Anade anotaciones de texto
4. **Undo/Redo** con los botones de la barra inferior (hasta 20 niveles)
5. **Guarda** los cambios o **cancela** para restaurar el estado original

### Consejos avanzados

**Iluminacion:**
- Interior con luz uniforme es ideal
- Evita luz directa del sol sobre el sensor LiDAR (en la parte trasera del dispositivo)
- Superficies muy brillantes o espejos pueden confundir el tracking

**Superficies dificiles:**
- Paredes lisas y completamente blancas son mas dificiles de detectar — activa "Puntos de tracking" para verificar
- Superficies transparentes (cristal, vidrio) no se detectan bien
- Superficies muy oscuras o absorbentes reducen la calidad del LiDAR

**Rendimiento:**
- Si la app va lenta, desactiva la malla 3D y los feature points (son solo para verificacion)
- Los overlays de planos tambien consumen recursos — desactivalos cuando no los necesites
- Con muchas mediciones (>20), el render puede ralentizarse ligeramente

**Flujo de trabajo recomendado:**
1. Escaneo completo de la habitacion (1-2 minutos)
2. Verificar deteccion con malla 3D y planos
3. Desactivar visualizaciones de debug
4. Realizar todas las mediciones necesarias
5. Colocar cuadros/vinilos donde se necesiten
6. Capturar para offsite
7. Editar y anotar en la oficina

## Casos de uso

### Medicion en obra
1. Abre la app en tablet iPad 13" con LiDAR
2. Escanea el espacio siguiendo los pasos anteriores
3. Mide todas las distancias necesarias con snap a bordes
4. Captura para offsite → lleva las mediciones a la oficina

### Decoracion y planificacion de arte
1. Escanea la habitacion
2. Selecciona fotos de cuadros/arte de tu galeria
3. Coloca en las paredes para visualizar como quedarian
4. Usa "Cubrir pared" para probar vinilos decorativos
5. Ajusta tamano hasta que se vea bien
6. Captura la escena para presentar al cliente

### Revision y documentacion offsite
1. Captura la escena en obra
2. En la oficina, abre la captura
3. Anade mediciones adicionales que hayas olvidado
4. Anota con texto las observaciones importantes
5. Marca areas de interes con cuadros de colores
6. Comparte con el equipo

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
