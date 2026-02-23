---
name: add-feature
description: Plan and implement a new feature for the lidar app
argument-hint: [feature description]
---

Implement the feature: $ARGUMENTS

## Process

1. **Explore**: Read existing code to understand patterns and architecture
2. **Plan**: Identify which files need changes and what the approach is
3. **Implement**: Follow the project conventions below
4. **Build**: Verify with `xcodebuild build -scheme lidar -destination 'platform=iOS Simulator,name=iPhone 17 Pro'`

## Conventions to follow

- **Architecture**: MVVM + Services + Protocols
- **ViewModels**: `@Observable` + `@MainActor`, NO Combine
- **DI**: Via protocolos (`StorageServiceProtocol`, `HapticServiceProtocol`)
- **Constants**: Siempre en `AppConstants` — nunca magic numbers
- **Coordinates**: Normalizadas (0-1) para posiciones 2D offsite
- **Language**: Codigo en ingles, comentarios y UI en espanol
- **Logic**: Toda logica de negocio en ViewModels, vistas solo presentacion
- **New files**: Evitar crear archivos nuevos si se puede editar uno existente
