# Changelog - lidar App

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
