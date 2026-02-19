//
//  CuadrosSectionView.swift
//  lidar
//
//  Sección Cuadros: foto de galería, colocar, lista, mover, redimensionar, eliminar, cambiar.
//

import SwiftUI
import PhotosUI

struct CuadrosSectionView: View {
    var sceneManager: ARSceneManager
    @State private var resizeValue: CGFloat = AppConstants.Cuadros.defaultSize
    @State private var selectedPhotoItem: PhotosPickerItem?
    @State private var selectedPhotoForFrame: PhotosPickerItem?
    /// ID del cuadro para el que se abre el sheet "Cambiar foto" (nil = cerrado).
    @State private var frameIdToChangePhoto: UUID?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                // Acciones rápidas arriba (visible sin desplazarse)
                if let selectedId = sceneManager.selectedFrameId,
                   let frame = sceneManager.placedFrames.first(where: { $0.id == selectedId }) {
                    VStack(spacing: 10) {
                        HStack(spacing: 10) {
                            Button(role: .destructive) {
                                sceneManager.deleteFrame(id: frame.id)
                            } label: {
                                Label("Eliminar", systemImage: "trash")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(.red)

                            Button {
                                sceneManager.moveModeForFrameId = frame.id
                            } label: {
                                Label(
                                    sceneManager.moveModeForFrameId == frame.id ? "Toca plano…" : "Mover",
                                    systemImage: "arrow.up.and.down.and.arrow.left.and.right"
                                )
                                .font(.subheadline)
                                .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                            .tint(sceneManager.moveModeForFrameId == frame.id ? .orange : nil)

                            PhotosPicker(selection: $selectedPhotoForFrame, matching: .images, photoLibrary: .shared()) {
                                Label("Foto", systemImage: "photo.badge.plus")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                            }
                            .onChange(of: selectedPhotoForFrame) { _, newItem in
                                guard let frameId = sceneManager.selectedFrameId, let newItem = newItem else { return }
                                Task {
                                    if let data = try? await newItem.loadTransferable(type: Data.self),
                                       let uiImage = UIImage(data: data) {
                                        await MainActor.run {
                                            sceneManager.setFrameImage(id: frameId, image: uiImage)
                                            selectedPhotoForFrame = nil
                                        }
                                    }
                                }
                            }
                            .buttonStyle(.bordered)

                            Button {
                                sceneManager.replaceFrame(id: frame.id, withNewSize: AppConstants.Cuadros.replaceSize)
                                resizeValue = AppConstants.Cuadros.replaceSize.width
                            } label: {
                                Label("Cambiar", systemImage: "arrow.triangle.2.circlepath")
                                    .font(.subheadline)
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                        HStack(spacing: 8) {
                            Text("Tamaño")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Slider(value: $resizeValue, in: AppConstants.Cuadros.minSize...AppConstants.Cuadros.maxSize, step: AppConstants.Cuadros.sizeStep)
                                .onChange(of: resizeValue) { _, newValue in
                                    sceneManager.resizeFrame(id: frame.id, newSize: CGSize(width: newValue, height: newValue * AppConstants.Cuadros.aspectRatio))
                                }
                            Text(String(format: "%.2f m", resizeValue))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 36, alignment: .trailing)
                        }
                    }
                    .padding(12)
                    .glassBackground(cornerRadius: 14)
                }

                // Vinilo: cubrir pared completa
                Button {
                    sceneManager.isVinylMode.toggle()
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "rectangle.inset.filled")
                            .font(.body)
                        Text(sceneManager.isVinylMode ? "Toca una pared…" : "Cubrir pared")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer(minLength: 0)
                        if sceneManager.isVinylMode {
                            Image(systemName: "xmark.circle.fill")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(12)
                    .glassBackground(cornerRadius: 12)
                }
                .buttonStyle(.plain)
                .tint(sceneManager.isVinylMode ? .orange : nil)
                .disabled(sceneManager.selectedFrameImage == nil && !sceneManager.isVinylMode)
                .opacity(sceneManager.selectedFrameImage == nil && !sceneManager.isVinylMode ? 0.5 : 1.0)
                .accessibilityLabel(sceneManager.isVinylMode ? "Cancelar modo vinilo" : "Cubrir pared con imagen")
                .accessibilityHint("Coloca la imagen seleccionada cubriendo toda la pared detectada")

                // Foto para nuevos + contador (compacto)
                HStack(spacing: 10) {
                    PhotosPicker(selection: $selectedPhotoItem, matching: .images, photoLibrary: .shared()) {
                        HStack(spacing: 6) {
                            if let img = sceneManager.selectedFrameImage {
                                Image(uiImage: img)
                                    .resizable()
                                    .scaledToFill()
                                    .frame(width: 36, height: 36)
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                            } else {
                                Image(systemName: "photo.on.rectangle.angled")
                                    .font(.body)
                                    .foregroundStyle(.secondary)
                            }
                            Text(sceneManager.selectedFrameImage == nil ? "Elegir foto" : "Cambiar")
                                .font(.caption)
                        }
                        .padding(8)
                        .glassBackground(cornerRadius: 10)
                    }
                    .onChange(of: selectedPhotoItem) { _, newItem in
                        Task {
                            if let data = try? await newItem?.loadTransferable(type: Data.self),
                               let uiImage = UIImage(data: data) {
                                await MainActor.run { sceneManager.selectedFrameImage = uiImage }
                            }
                        }
                    }
                    Text("Toca pared en AR para colocar · \(sceneManager.placedFrames.count) cuadros")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(10)
                .glassBackground(cornerRadius: 12)

                // Lista de cuadros (compacta)
                if !sceneManager.placedFrames.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Selecciona un cuadro")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        ForEach(sceneManager.placedFrames) { frame in
                            CuadroRowView(
                                frame: frame,
                                isSelected: sceneManager.selectedFrameId == frame.id,
                                onSelect: {
                                    sceneManager.selectedFrameId = frame.id
                                    resizeValue = frame.size.width
                                },
                                onChangePhoto: { frameIdToChangePhoto = frame.id }
                            )
                        }
                    }
                    .padding(10)
                    .glassBackground(cornerRadius: 12)
                }
            }
            .padding(.horizontal)
        }
        .navigationTitle("Cuadros")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: sceneManager.frameGestureUpdateCounter) { _, _ in
            if let selectedId = sceneManager.selectedFrameId,
               let frame = sceneManager.placedFrames.first(where: { $0.id == selectedId }) {
                resizeValue = frame.size.width
            }
        }
        .sheet(isPresented: Binding(
            get: { frameIdToChangePhoto != nil },
            set: { if !$0 { frameIdToChangePhoto = nil } }
        )) {
            if let id = frameIdToChangePhoto {
                ChangeFramePhotoSheet(frameId: id, sceneManager: sceneManager) {
                    frameIdToChangePhoto = nil
                }
            }
        }
    }
}

private struct ChangeFramePhotoSheet: View {
    let frameId: UUID
    var sceneManager: ARSceneManager
    var onDismiss: () -> Void
    @State private var selectedItem: PhotosPickerItem?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Elige una foto para este cuadro")
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding()
                PhotosPicker(selection: $selectedItem, matching: .images, photoLibrary: .shared()) {
                    Label("Elegir de la galería", systemImage: "photo.on.rectangle.angled")
                        .font(.title3)
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                .buttonStyle(.borderedProminent)
                .onChange(of: selectedItem) { _, newItem in
                    guard let newItem = newItem else { return }
                    Task {
                        if let data = try? await newItem.loadTransferable(type: Data.self),
                           let uiImage = UIImage(data: data) {
                            await MainActor.run {
                                sceneManager.setFrameImage(id: frameId, image: uiImage)
                                dismiss()
                                onDismiss()
                            }
                        }
                    }
                }
                Spacer()
            }
            .padding(24)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") {
                        dismiss()
                        onDismiss()
                    }
                }
            }
        }
    }
}

// CuadroRow → Extraído a UI/Components/CuadroRowView.swift
