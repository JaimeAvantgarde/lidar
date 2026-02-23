---
name: review-code
description: Review recent code changes for bugs, edge cases, and convention violations
context: fork
agent: Explore
---

Review the recent code changes in this project:

## Check for

1. **Geometry bugs**: Coordenadas normalizadas sin convertir a pixeles, intrinsicos sin rotar landscape→portrait
2. **Memory leaks**: Timers sin invalidar, caches sin limite, closures con strong self
3. **Edge cases**: Puntos fuera de pantalla (>1 o <0), arrays vacios, nil optionals
4. **Convention violations**: Magic numbers (deben estar en AppConstants), logica en vistas (debe estar en ViewModels)
5. **AR-specific**: `sceneView.projectPoint()` usado donde deberia ser `ARCamera.projectPoint()`, `drawHierarchy` en vez de `capturedImage`

## How to review

1. Run `git diff` to see recent changes
2. Read each changed file
3. Check against the rules above
4. Report findings with file:line references
