---
name: fix-bug
description: Investigate and fix a bug in the lidar app. Use when the user reports unexpected behavior, crashes, or incorrect measurements.
argument-hint: [description of the bug]
---

Fix the reported bug: $ARGUMENTS

## Process

1. **Understand**: Read the relevant files to understand the current behavior
2. **Locate**: Use Grep/Glob to find the exact code causing the issue
3. **Analyze**: Trace the data flow to identify the root cause
4. **Fix**: Make the minimal change needed to fix the bug
5. **Verify**: Build with `xcodebuild build -scheme lidar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

## Critical rules for this codebase

- Coordenadas normalizadas (0-1) — SIEMPRE convertir a pixeles antes de calcular distancias
- Intrínsecos ARKit son landscape-left — rotar para portrait: `portrait_fx = native_fy`
- Proyecciones para capturedImage usan `ARCamera.projectPoint()`, NO `sceneView.projectPoint()`
- Constantes en `AppConstants` — nunca magic numbers
- Al mover medición entera NO recalcular distancia
