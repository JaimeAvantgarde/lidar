# Contexto del Proyecto — lidar

## Decisiones de arquitectura recientes

### Captura offsite: ARFrame.capturedImage (feb 2025)
- `captureForOffsite()` usa `ARFrame.capturedImage` (CVPixelBuffer puro) en vez de `drawHierarchy()`
- La imagen se rota con `.oriented(.right)` de landscape-left a portrait
- Las proyecciones 3D→2D usan `ARCamera.projectPoint(_:orientation:viewportSize:)` con la resolución real de la imagen capturada
- Los intrínsecos de ARKit son landscape-left; al proyectar a portrait se ROTAN: `portrait_fx = native_fy`, `portrait_cx = native_cy`, etc.

### Depth-aware distance (feb 2025)
- `calculateDepthAwareDistance` usa intrínsecos rotados a portrait (NO landscape directo)
- El depth map de ARKit es landscape; `sampleDepth()` transforma portrait→landscape: `lx = point.y, ly = 1 - point.x`
- Al mover una medición ENTERA (no endpoints individuales), la distancia NO se recalcula
- Al rotar una medición, la distancia tampoco se recalcula

### Cache de perspectiva (feb 2025)
- `PerspectiveImageCache` tiene límite LRU de 20 entradas
- Valida que los 4 corners formen un cuadrilátero convexo antes de aplicar `CIPerspectiveTransform`

## Trampas conocidas (NO repetir)
- NUNCA usar `sceneView.projectPoint()` para coordenadas que irán con `capturedImage` → usar `ARCamera.projectPoint()`
- NUNCA calcular distancias con `sqrt(dx² + dy²)` sin convertir a píxeles primero (aspect ratio)
- NUNCA recalcular distancia al mover/rotar medición entera — solo al mover endpoints individuales
- Los intrínsecos de ARKit son SIEMPRE landscape-left, hay que rotarlos para portrait
- `hideAllOverlayNodes()`/`restoreOverlayNodes()` fueron eliminados — ya no son necesarios
