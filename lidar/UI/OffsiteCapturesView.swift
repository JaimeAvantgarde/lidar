//
//  OffsiteCapturesView.swift
//  lidar
//
//  Lista de capturas offsite y vista detalle: imagen con mediciones superpuestas + modo edición.
//  OffsiteCaptureEntry → Models/OffsiteCapture.swift
//  Color(hex:) → Extensions/Color+Hex.swift
//

import SwiftUI

// OffsiteCaptureEntry está definido en Models/OffsiteCapture.swift

/// Lista de capturas guardadas en Documents/OffsiteCaptures/
struct OffsiteCapturesListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel = OffsiteCapturesListViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        "Sin capturas offsite",
                        systemImage: "camera.viewfinder",
                        description: Text("Usa «Capturar para offsite» en la barra superior para guardar una foto con las mediciones.")
                    )
                } else {
                    List {
                        ForEach(viewModel.entries) { entry in
                            NavigationLink(value: entry) {
                                HStack(spacing: 12) {
                                    thumbnail(for: entry)
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.capturedAt, style: .date)
                                            .font(.subheadline)
                                            .fontWeight(.medium)
                                        Text(entry.capturedAt, style: .time)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                        
                                        // Mostrar información de contenido
                                        if let preview = viewModel.preview(for: entry) {
                                            HStack(spacing: 8) {
                                                if preview.measurementCount > 0 {
                                                    Label("\(preview.measurementCount)", systemImage: "ruler")
                                                        .font(.caption2)
                                                }
                                                if preview.frameCount > 0 {
                                                    Label("\(preview.frameCount)", systemImage: "photo.artframe")
                                                        .font(.caption2)
                                                }
                                            }
                                            .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: viewModel.deleteEntries)
                    }
                }
            }
            .navigationTitle("Capturas offsite")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if !viewModel.entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                    }
                }
            }
            .onAppear { viewModel.loadEntries() }
            .navigationDestination(for: OffsiteCaptureEntry.self) { entry in
                OffsiteCaptureDetailView(entry: entry)
            }
        }
    }
    

    private func thumbnail(for entry: OffsiteCaptureEntry) -> some View {
        Group {
            let thumbURL = viewModel.thumbnailURL(for: entry)
            let thumbSize = CGSize(width: 112, height: 112) // 56pt * 2x

            if let img = UIImage(contentsOfFile: thumbURL.path) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let img = UIImage(contentsOfFile: entry.imageURL.path)?
                .preparingThumbnail(of: thumbSize) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                Rectangle()
                    .fill(Color.gray.opacity(0.3))
            }
        }
        .frame(width: 56, height: 56)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
    
    // Lógica de deleteEntries y loadEntries delegada a OffsiteCapturesListViewModel
}

/// Vista detalle: imagen con líneas y etiquetas de mediciones superpuestas + modo edición.
struct OffsiteCaptureDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var viewModel: OffsiteCaptureDetailViewModel

    // MARK: - Local UI State
    @State private var showFloorPlan = false
    @State private var showImagePicker = false
    @State private var selectedImage: UIImage?
    @State private var frameIdForPhotoPicker: UUID?
    @State private var showPlaneOverlays: Bool = AppConstants.OffsiteEditor.defaultShowPlaneOverlays
    @State private var showCornerMarkers: Bool = AppConstants.OffsiteEditor.defaultShowCornerMarkers
    @State private var showWallDimensions: Bool = AppConstants.OffsiteEditor.defaultShowWallDimensions
    @State private var showPerspectiveFrames: Bool = AppConstants.OffsiteEditor.defaultShowPerspectiveFrames
    @State private var selectedPlaneId: String?
    @State private var overlayOpacity: Double = 1.0
    @State private var showDeleteConfirmation = false
    @State private var shareItem: URL?
    @State private var zoomScale: CGFloat = 1.0
    @State private var lastZoomScale: CGFloat = 1.0
    @State private var panOffset: CGSize = .zero
    @State private var lastPanOffset: CGSize = .zero
    @State private var currentFingerPosition: CGPoint?
    @State private var activeTouchPosition: CGPoint?
    @State private var activeTouchNormalized: CGPoint?

    init(entry: OffsiteCaptureEntry) {
        _viewModel = State(initialValue: OffsiteCaptureDetailViewModel(entry: entry))
    }

    var body: some View {
        GeometryReader { fullGeo in
            ZStack {
                Color.black.ignoresSafeArea()

                if let image = viewModel.image {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let data = viewModel.data {
                            overlaysView(data: data, viewSize: fullGeo.size, imageSize: image.size, zoomScale: zoomScale)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .scaleEffect(zoomScale)
                    .offset(panOffset)
                    .contentShape(Rectangle())
                    .gesture(editGesture(viewSize: fullGeo.size, imageSize: image.size))
                    .gesture(zoomGesture)
                    .gesture(panGesture)
                    .onTapGesture(count: 2) { resetZoom() }
                } else {
                    ProgressView("Cargando\u{2026}")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }

                // Magnifier lens (fuera del ZStack con zoom para que no escale)
                if viewModel.isEditMode,
                   let touchPos = activeTouchPosition,
                   let touchNorm = activeTouchNormalized,
                   let sourceImage = viewModel.image {
                    let magnifierY = max(
                        AppConstants.OffsiteEditor.magnifierDiameter / 2 + 10,
                        touchPos.y - AppConstants.OffsiteEditor.magnifierOffsetY
                    )
                    MagnifierLensView(
                        sourceImage: sourceImage,
                        touchNormalized: touchNorm
                    )
                    .position(x: touchPos.x, y: magnifierY)
                    .allowsHitTesting(false)
                    .transition(.opacity)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(viewModel.isEditMode)
        .persistentSystemOverlays(viewModel.isEditMode ? .hidden : .automatic)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(viewModel.isEditMode)
        .toolbar(viewModel.isEditMode ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(viewModel.isEditMode ? "Cancelar" : "Cerrar") {
                    if viewModel.isEditMode {
                        viewModel.cancelEdit()
                    } else {
                        dismiss()
                    }
                }
            }

            if !viewModel.isEditMode {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Unidad", selection: $viewModel.unit) {
                        Text("m").tag(MeasurementUnit.meters)
                        Text("ft").tag(MeasurementUnit.feet)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                    .accessibilityLabel("Unidad de medida")
                }

                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.enterEditMode()
                    } label: {
                        Label("Editar", systemImage: "pencil")
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        if let shareURL = viewModel.renderedImageForSharing() {
                            shareItem = shareURL
                        }
                    } label: {
                        Label("Compartir", systemImage: "square.and.arrow.up")
                    }
                }

                ToolbarItem(placement: .secondaryAction) {
                    if let snapshot = viewModel.data?.sceneSnapshot,
                       snapshot.planes.contains(where: { $0.isVertical }) {
                        Button {
                            showFloorPlan = true
                        } label: {
                            Label("Plano 2D", systemImage: "map")
                        }
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("Guardar") {
                        viewModel.saveChanges()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .overlay(alignment: .topLeading) {
            if !viewModel.isEditMode {
                VStack(alignment: .leading, spacing: 8) {
                    if let snapshot = viewModel.data?.sceneSnapshot {
                        OffsiteSceneInfoPanel(snapshot: snapshot)

                        // Indicador de escala AR
                        if snapshot.metersPerPixelScale != nil {
                            Label("Escala AR disponible", systemImage: "checkmark.seal.fill")
                                .font(.caption2)
                                .foregroundStyle(.green)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        } else if !snapshot.measurements.isEmpty {
                            Label("Mediciones AR guardadas", systemImage: "ruler")
                                .font(.caption2)
                                .foregroundStyle(.cyan)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
                        }

                        // Capas 3D toggleables en modo vista
                        layersToggle
                    } else if let metadata = viewModel.data?.lidarMetadata {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack(spacing: 6) {
                                Image(systemName: metadata.isLiDARAvailable ? "sensor.fill" : "sensor")
                                    .font(.caption)
                                    .foregroundStyle(metadata.isLiDARAvailable ? .green : .secondary)
                                Text(metadata.isLiDARAvailable ? "LiDAR" : "AR")
                                    .font(.caption2)
                                    .fontWeight(.medium)
                            }
                            if metadata.planeCount > 0 {
                                Text("\(metadata.planeCount) planos detectados")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                    }
                }
                .padding(.top, 60)
                .padding(.leading, 16)
            }
        }
        .overlay(alignment: .topTrailing) {
            if viewModel.isEditMode {
                editHint
            }
        }
        .overlay(alignment: .bottom) {
            if viewModel.isEditMode && viewModel.selectedItem != nil {
                contextActionBar
                    .padding(.bottom, 200)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .safeAreaInset(edge: .bottom) {
            if viewModel.isEditMode {
                editToolbar
            }
        }
        .background(viewModel.isEditMode ? Color.black.opacity(0.3) : Color.clear)
        .animation(.easeInOut(duration: 0.3), value: viewModel.isEditMode)
        .animation(.spring(response: 0.3), value: viewModel.selectedItem)
        .alert("Anadir texto", isPresented: $viewModel.showTextInput) {
            TextField("Escribe aqui", text: $viewModel.newTextContent)
            Button("Cancelar", role: .cancel) {
                viewModel.newTextContent = ""
            }
            Button("Anadir") {
                viewModel.addTextAnnotation()
            }
        } message: {
            Text("Anade una anotacion de texto en esta posicion")
        }
        .confirmationDialog(
            "Eliminar \(viewModel.selectedItemName ?? "elemento")",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Eliminar", role: .destructive) {
                viewModel.deleteSelectedItem()
            }
            Button("Cancelar", role: .cancel) {}
        } message: {
            Text("Esta accion no se puede deshacer.")
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedImage)
        }
        .sheet(isPresented: $showFloorPlan) {
            if let snapshot = viewModel.data?.sceneSnapshot {
                FloorPlanView(floorPlanData: FloorPlanGenerator.generate(from: snapshot.planes, corners: snapshot.corners))
            }
        }
        .sheet(isPresented: Binding(
            get: { shareItem != nil },
            set: { if !$0 { shareItem = nil } }
        )) {
            if let url = shareItem {
                ShareSheet(activityItems: [url])
            }
        }
        .onChange(of: selectedImage) { _, newImage in
            if let image = newImage, let frameId = frameIdForPhotoPicker {
                viewModel.updateFrameImage(id: frameId, image: image)
                selectedImage = nil
                frameIdForPhotoPicker = nil
            }
        }
        .onAppear {
            viewModel.loadContent()
        }
    }
    
    // MARK: - Gestures

    /// Transforma coordenadas de pantalla compensando zoom y pan.
    private func adjustedLocation(_ location: CGPoint, viewSize: CGSize) -> CGPoint {
        let cx = viewSize.width / 2
        let cy = viewSize.height / 2
        return CGPoint(
            x: (location.x - cx - panOffset.width) / zoomScale + cx,
            y: (location.y - cy - panOffset.height) / zoomScale + cy
        )
    }

    private func editGesture(viewSize: CGSize, imageSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                guard viewModel.isEditMode else { return }
                let adjustedCurrent = adjustedLocation(value.location, viewSize: viewSize)

                if viewModel.editTool == .select {
                    let dist = sqrt(value.translation.width * value.translation.width + value.translation.height * value.translation.height)
                    let adjustedStart = adjustedLocation(value.startLocation, viewSize: viewSize)
                    if !viewModel.isDragging && dist > AppConstants.OffsiteEditor.minDragDistance && viewModel.selectedItem != nil {
                        viewModel.handleDragStart(at: adjustedStart, viewSize: viewSize, imageSize: imageSize)
                    }
                    if viewModel.isDragging {
                        viewModel.handleDragChanged(to: adjustedCurrent, viewSize: viewSize, imageSize: imageSize)
                    }
                }

                // Preview de medición en tiempo real
                if viewModel.editTool == .measure && viewModel.pendingMeasurementNormalizedPoint != nil {
                    currentFingerPosition = adjustedCurrent
                }

                // Magnifier: trackear toque activo para todos los tools
                let scale = viewModel.scaleToFit(imageSize: imageSize, in: viewSize)
                let offset = viewModel.offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)
                let normX = (adjustedCurrent.x - offset.x) / (imageSize.width * scale)
                let normY = (adjustedCurrent.y - offset.y) / (imageSize.height * scale)
                if (0...1).contains(normX) && (0...1).contains(normY) {
                    activeTouchPosition = value.location // posición en coordenadas de pantalla
                    activeTouchNormalized = CGPoint(x: normX, y: normY)
                } else {
                    activeTouchPosition = nil
                    activeTouchNormalized = nil
                }
            }
            .onEnded { value in
                guard viewModel.isEditMode else { return }
                currentFingerPosition = nil
                activeTouchPosition = nil
                activeTouchNormalized = nil
                let adjusted = adjustedLocation(value.location, viewSize: viewSize)
                if viewModel.editTool == .select {
                    if viewModel.isDragging {
                        viewModel.handleDragEnded()
                    } else {
                        viewModel.handleEditTap(at: adjusted, viewSize: viewSize, imageSize: imageSize)
                    }
                } else {
                    viewModel.handleEditTap(at: adjusted, viewSize: viewSize, imageSize: imageSize)
                }
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let newScale = lastZoomScale * value.magnification
                zoomScale = min(max(newScale, AppConstants.OffsiteEditor.minZoomScale), AppConstants.OffsiteEditor.maxZoomScale)
            }
            .onEnded { _ in
                lastZoomScale = zoomScale
            }
    }

    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 5)
            .onChanged { value in
                guard zoomScale > 1.0, !viewModel.isEditMode else { return }
                panOffset = CGSize(
                    width: lastPanOffset.width + value.translation.width,
                    height: lastPanOffset.height + value.translation.height
                )
            }
            .onEnded { _ in
                lastPanOffset = panOffset
            }
    }

    private func resetZoom() {
        withAnimation(.spring(response: 0.3)) {
            zoomScale = 1.0
            lastZoomScale = 1.0
            panOffset = .zero
            lastPanOffset = .zero
        }
    }

    // MARK: - Context Action Bar

    private var contextActionBar: some View {
        HStack(spacing: 12) {
            Image(systemName: viewModel.selectedItemIcon)
                .font(.title3)
                .foregroundStyle(.yellow)

            Text(viewModel.selectedItemName ?? "")
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(.white)
                .lineLimit(1)

            Spacer()

            if viewModel.selectedItemIsFrame {
                Button {
                    frameIdForPhotoPicker = viewModel.selectedFrameId
                    showImagePicker = true
                } label: {
                    Label("Foto", systemImage: "photo")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue, in: Capsule())
                }
            }

            if viewModel.selectedItemIsMeasurement {
                Button {
                    viewModel.duplicateSelectedMeasurement()
                } label: {
                    Label("Duplicar", systemImage: "doc.on.doc")
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.orange, in: Capsule())
                }
            }

            if viewModel.selectedItemSupportsColor {
                HStack(spacing: 4) {
                    ForEach(AppConstants.OffsiteEditor.availableColors, id: \.self) { hex in
                        Circle()
                            .fill(Color(hex: hex))
                            .frame(width: 24, height: 24)
                            .overlay(
                                viewModel.selectedItemColor == hex
                                    ? Circle().strokeBorder(Color.white, lineWidth: 2)
                                    : nil
                            )
                            .onTapGesture {
                                viewModel.updateItemColor(hex)
                            }
                    }
                }
            }

            Button {
                showDeleteConfirmation = true
            } label: {
                Label("Eliminar", systemImage: "trash")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.red, in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 16)
    }

    // MARK: - Edit Hint

    private var editHint: some View {
        VStack(alignment: .trailing, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: hintIcon)
                    .font(.title3)
                Text(hintText)
                    .font(.subheadline)
                    .fontWeight(.semibold)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .background(
                .ultraThinMaterial,
                in: RoundedRectangle(cornerRadius: 16)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .strokeBorder(Color.white.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.3), radius: 10)

            if viewModel.editTool == .measure {
                VStack(alignment: .trailing, spacing: 4) {
                    if let arMeasurements = viewModel.data?.measurements.filter({ $0.isFromAR }), !arMeasurements.isEmpty {
                        Label("Escala: \(arMeasurements.count) medicion\(arMeasurements.count == 1 ? "" : "es") AR", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.green)
                    } else {
                        Label("Sin escala AR - medidas estimadas", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
            }
        }
        .padding(.top, 60)
        .padding(.trailing, 16)
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    private var hintIcon: String {
        switch viewModel.editTool {
        case .select where viewModel.isDragging: return "hand.draw.fill"
        case .select where viewModel.selectedItem != nil: return "arrow.up.and.down.and.arrow.left.and.right"
        case .select: return "hand.point.up.left.fill"
        case .measure: return viewModel.pendingMeasurementNormalizedPoint == nil ? "1.circle.fill" : "2.circle.fill"
        case .frame: return "rectangle.dashed"
        case .placeFrame: return "photo.artframe"
        case .text: return "text.bubble.fill"
        case .none: return ""
        }
    }

    private var hintText: String {
        switch viewModel.editTool {
        case .select where viewModel.isDragging:
            return "Arrastrando... suelta para colocar"
        case .select where viewModel.selectedItem != nil:
            return "Arrastra para mover"
        case .select:
            return "Toca un elemento para seleccionarlo"
        case .measure:
            return viewModel.pendingMeasurementNormalizedPoint == nil ? "Toca el primer punto" : "Toca el segundo punto"
        case .frame:
            return "Toca para colocar cuadro"
        case .placeFrame:
            return selectedPlaneId != nil ? "Toca en la pared para colocar" : "Selecciona una pared y toca para colocar"
        case .text:
            return "Toca para anadir texto"
        case .none:
            return ""
        }
    }
    
    // MARK: - Edit Toolbar

    private var layersToggle: some View {
        DisclosureGroup("Capas 3D") {
            HStack(spacing: 12) {
                OverlayToggle(icon: "rectangle.dashed", label: "Planos", isOn: $showPlaneOverlays, color: .blue)
                OverlayToggle(icon: "angle", label: "Esquinas", isOn: $showCornerMarkers, color: .yellow)
                OverlayToggle(icon: "ruler", label: "Cotas", isOn: $showWallDimensions, color: .orange)
                OverlayToggle(icon: "cube", label: "Cuadros 3D", isOn: $showPerspectiveFrames, color: .purple)
            }
            .padding(.top, 4)
        }
        .font(.caption)
        .foregroundStyle(.white)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color.black.opacity(0.5), in: RoundedRectangle(cornerRadius: 12))
    }

    private var editToolbar: some View {
        VStack(spacing: 12) {
            layersToggle

            HStack(spacing: 12) {
                // Undo/Redo
                Button { viewModel.undo() } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.title3)
                        .foregroundStyle(viewModel.canUndo ? .white : .gray)
                }
                .disabled(!viewModel.canUndo)

                Button { viewModel.redo() } label: {
                    Image(systemName: "arrow.uturn.forward")
                        .font(.title3)
                        .foregroundStyle(viewModel.canRedo ? .white : .gray)
                }
                .disabled(!viewModel.canRedo)

                Divider().frame(height: 30)

                toolButton(.select, icon: "hand.point.up.left", label: "Mover", color: .yellow)
                toolButton(.measure, icon: "ruler", label: "Medir", color: .green)
                toolButton(.placeFrame, icon: "photo.artframe", label: "En pared", color: .purple)
                toolButton(.frame, icon: "rectangle.dashed", label: "Cuadro", color: .blue)
                toolButton(.text, icon: "text.bubble", label: "Texto", color: .purple)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
        .background(
            .regularMaterial,
            in: RoundedRectangle(cornerRadius: 24)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Color.primary.opacity(0.1), lineWidth: 1)
        )
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
        .shadow(color: .black.opacity(0.1), radius: 10, y: -5)
    }

    private func toolButton(_ tool: OffsiteCaptureDetailViewModel.EditTool, icon: String, label: String, color: Color) -> some View {
        Button {
            withAnimation(.spring(response: 0.3)) {
                viewModel.toggleEditTool(tool)
            }
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    Circle()
                        .fill(viewModel.editTool == tool ? color : Color.gray.opacity(0.3))
                        .frame(width: 50, height: 50)
                    Image(systemName: icon)
                        .font(.title3)
                        .foregroundStyle(viewModel.editTool == tool ? .white : .primary)
                }
                Text(label)
                    .font(.caption2)
                    .fontWeight(viewModel.editTool == tool ? .bold : .regular)
                    .foregroundStyle(viewModel.editTool == tool ? color : .secondary)
            }
            .frame(maxWidth: .infinity)
        }
    }
    
    // MARK: - Overlays

    @ViewBuilder
    private func overlaysView(data: OffsiteCaptureData, viewSize: CGSize, imageSize: CGSize, zoomScale: CGFloat = 1.0) -> some View {
        let scale = viewModel.scaleToFit(imageSize: imageSize, in: viewSize)
        let offset = viewModel.offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)
        let overlayScale = 1.0 / sqrt(zoomScale)

        // === Plane overlays ===
        if showPlaneOverlays, let snapshot = data.sceneSnapshot {
            ForEach(snapshot.planes) { plane in
                PlaneOverlayView(
                    plane: plane,
                    isSelected: selectedPlaneId == plane.id,
                    imageSize: imageSize,
                    scale: scale,
                    offset: offset,
                    showDimensions: true,
                    overlayScale: overlayScale,
                    onTap: {
                        selectedPlaneId = selectedPlaneId == plane.id ? nil : plane.id
                        HapticService.shared.impact(style: .light)
                    }
                )
                .opacity(overlayOpacity)
            }
        }

        // === Wall dimensions ===
        if showWallDimensions, let snapshot = data.sceneSnapshot {
            ForEach(snapshot.wallDimensions) { wall in
                WallDimensionOverlayView(
                    wall: wall,
                    imageSize: imageSize,
                    scale: scale,
                    offset: offset,
                    unit: viewModel.unit,
                    overlayScale: overlayScale
                )
                .opacity(overlayOpacity)
            }
        }

        // === Corner markers ===
        if showCornerMarkers, let snapshot = data.sceneSnapshot {
            ForEach(snapshot.corners) { corner in
                CornerOverlayView(
                    corner: corner,
                    imageSize: imageSize,
                    scale: scale,
                    offset: offset,
                    overlayScale: overlayScale
                )
                .opacity(overlayOpacity)
            }
        }

        // === Perspective frames ===
        if showPerspectiveFrames, let snapshot = data.sceneSnapshot {
            ForEach(snapshot.perspectiveFrames) { frame in
                let isSelected = viewModel.selectedItem == .perspectiveFrame(frame.id)
                PerspectiveFrameOverlayView(
                    frame: frame,
                    imageSize: imageSize,
                    scale: scale,
                    offset: offset,
                    isSelected: isSelected,
                    isEditMode: viewModel.isEditMode,
                    loadedImage: viewModel.loadFrameImage(filename: frame.imageFilename, base64: frame.imageBase64),
                    overlayScale: overlayScale,
                    onDelete: {
                        viewModel.deletePerspectiveFrame(id: frame.id)
                    }
                )
            }
        }

        // === Standard measurements ===
        ForEach(data.measurements) { m in
            let isSelected = isItemSelected(item: .measurement(m.id))
                || isItemSelected(item: .measurementEndpointA(m.id))
                || isItemSelected(item: .measurementEndpointB(m.id))
            EnhancedMeasurementOverlay(
                measurement: m,
                imageSize: imageSize,
                scale: scale,
                offset: offset,
                unit: viewModel.unit,
                isEditMode: viewModel.isEditMode,
                isSelected: isSelected,
                overlayScale: overlayScale,
                onDelete: { viewModel.deleteMeasurement(id: m.id) }
            )
        }

        // === Standard frames ===
        ForEach(data.frames) { frame in
            let isSelected = viewModel.selectedItem?.itemId == frame.id && (
                viewModel.selectedItem == .frame(frame.id) || viewModel.selectedItem == .frameResizeBottomRight(frame.id)
            )
            frameOverlay(frame, scale: scale, offset: offset, imageSize: imageSize, isSelected: isSelected, overlayScale: overlayScale)
        }

        // === Text annotations ===
        ForEach(data.textAnnotations) { annotation in
            let isSelected = viewModel.selectedItem == .textAnnotation(annotation.id)
            textAnnotationOverlay(annotation, scale: scale, offset: offset, imageSize: imageSize, isSelected: isSelected, overlayScale: overlayScale)
        }

        // === Pending measurement point + live preview ===
        if let normPoint = viewModel.pendingMeasurementNormalizedPoint {
            let screenPoint = CGPoint(
                x: normPoint.x * imageSize.width * scale + offset.x,
                y: normPoint.y * imageSize.height * scale + offset.y
            )
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 20, height: 20)
                Circle()
                    .stroke(Color.orange, lineWidth: 3)
                    .frame(width: 32, height: 32)
                    .opacity(0.5)
            }
            .position(screenPoint)
            .transition(.scale.combined(with: .opacity))

            // Línea de preview en tiempo real hacia el dedo
            if let fingerPos = currentFingerPosition {
                let fingerNormX = (fingerPos.x - offset.x) / (imageSize.width * scale)
                let fingerNormY = (fingerPos.y - offset.y) / (imageSize.height * scale)
                let fingerNorm = NormalizedPoint(x: fingerNormX, y: fingerNormY)

                // Línea discontinua naranja semitransparente
                Path { path in
                    path.move(to: screenPoint)
                    path.addLine(to: fingerPos)
                }
                .stroke(Color.orange.opacity(0.6), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))

                // Crosshair en la posición del dedo
                ZStack {
                    Circle()
                        .stroke(Color.orange, lineWidth: 2)
                        .frame(width: 24, height: 24)
                    Path { path in
                        path.move(to: CGPoint(x: -8, y: 0))
                        path.addLine(to: CGPoint(x: 8, y: 0))
                        path.move(to: CGPoint(x: 0, y: -8))
                        path.addLine(to: CGPoint(x: 0, y: 8))
                    }
                    .stroke(Color.orange, lineWidth: 1.5)
                }
                .position(fingerPos)

                // Label con distancia estimada en el midpoint
                if let dist = viewModel.estimateDistance(
                    pointA: normPoint,
                    pointB: fingerNorm,
                    imageSize: imageSize,
                    viewSize: viewSize
                ) {
                    let mid = CGPoint(
                        x: (screenPoint.x + fingerPos.x) / 2,
                        y: (screenPoint.y + fingerPos.y) / 2 - 22
                    )
                    Text(viewModel.unit.format(distanceMeters: Float(dist)))
                        .font(.caption)
                        .fontWeight(.bold)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.8), in: RoundedRectangle(cornerRadius: 6))
                        .position(mid)
                }
            }
        }
    }

    private func isItemSelected(item: SelectableItemType) -> Bool {
        viewModel.selectedItem == item
    }
    
    @ViewBuilder
    private func frameOverlay(_ frame: OffsiteFrame, scale: CGFloat, offset: CGPoint, imageSize: CGSize, isSelected: Bool, overlayScale: CGFloat = 1.0) -> some View {
        let x = frame.topLeft.x * imageSize.width * scale + offset.x
        let y = frame.topLeft.y * imageSize.height * scale + offset.y
        let w = frame.width * imageSize.width * scale
        let h = frame.height * imageSize.height * scale
        let borderWidth = (isSelected ? AppConstants.OffsiteEditor.selectionBorderWidth : 3.0) * overlayScale

        ZStack {
            if let frameImage = viewModel.loadFrameImage(filename: frame.imageFilename, base64: frame.imageBase64) {
                Image(uiImage: frameImage)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: w, height: h)
                    .clipShape(Rectangle())
                    .overlay(
                        Rectangle()
                            .strokeBorder(Color(hex: frame.color), lineWidth: borderWidth)
                    )
                    .position(x: x + w/2, y: y + h/2)
            } else {
                Rectangle()
                    .strokeBorder(Color(hex: frame.color), lineWidth: borderWidth)
                    .background(Color(hex: frame.color).opacity(0.1))
                    .frame(width: w, height: h)
                    .position(x: x + w/2, y: y + h/2)
            }

            if let widthM = frame.widthMeters, let heightM = frame.heightMeters {
                VStack(spacing: 2) {
                    if let label = frame.label {
                        Text(label)
                            .font(.system(size: 12 * overlayScale))
                            .fontWeight(.semibold)
                    }
                    Text(String(format: "%.2f x %.2f m", widthM, heightM))
                        .font(.system(size: 10 * overlayScale))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 6 * overlayScale)
                .padding(.vertical, 3 * overlayScale)
                .background(Color(hex: frame.color).opacity(0.9), in: RoundedRectangle(cornerRadius: 4))
                .position(x: x + w/2, y: y - 12 * overlayScale)
            } else if let label = frame.label {
                Text(label)
                    .font(.system(size: 12 * overlayScale))
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6 * overlayScale)
                    .padding(.vertical, 2 * overlayScale)
                    .background(Color(hex: frame.color), in: RoundedRectangle(cornerRadius: 4))
                    .position(x: x + w/2, y: y - 8 * overlayScale)
            }

            // Selection highlight
            if isSelected {
                Rectangle()
                    .strokeBorder(Color.yellow, lineWidth: AppConstants.OffsiteEditor.selectionBorderWidth * overlayScale)
                    .frame(width: w + 8, height: h + 8)
                    .position(x: x + w/2, y: y + h/2)

                DragHandleView(overlayScale: overlayScale)
                    .position(x: x + w/2, y: y + h/2)

                // Resize handle en esquina inferior derecha
                ResizeHandleView(overlayScale: overlayScale)
                    .position(x: x + w, y: y + h)
            }
        }
    }

    @ViewBuilder
    private func textAnnotationOverlay(_ annotation: OffsiteTextAnnotation, scale: CGFloat, offset: CGPoint, imageSize: CGSize, isSelected: Bool, overlayScale: CGFloat = 1.0) -> some View {
        let pos = CGPoint(
            x: annotation.position.x * imageSize.width * scale + offset.x,
            y: annotation.position.y * imageSize.height * scale + offset.y
        )

        ZStack {
            Text(annotation.text)
                .font(.system(size: 15 * overlayScale))
                .fontWeight(.medium)
                .foregroundStyle(Color(hex: annotation.color))
                .padding(.horizontal, 8 * overlayScale)
                .padding(.vertical, 4 * overlayScale)
                .background(
                    isSelected ? Color.yellow.opacity(0.3) : Color.black.opacity(0.7),
                    in: RoundedRectangle(cornerRadius: 6)
                )
                .overlay(
                    isSelected ? RoundedRectangle(cornerRadius: 6).strokeBorder(Color.yellow, lineWidth: 2) : nil
                )
                .position(pos)

            if isSelected {
                DragHandleView()
                    .position(x: pos.x + 50, y: pos.y)
            }
        }
    }
}

// MARK: - Overlay Toggle

struct OverlayToggle: View {
    let icon: String
    let label: String
    @Binding var isOn: Bool
    let color: Color
    
    var body: some View {
        Button {
            isOn.toggle()
            HapticService.shared.impact(style: .light)
        } label: {
            VStack(spacing: 2) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundStyle(isOn ? color : .gray)
                Text(label)
                    .font(.system(size: 8))
                    .foregroundStyle(isOn ? .white : .gray)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
            .background(isOn ? color.opacity(0.2) : Color.clear, in: RoundedRectangle(cornerRadius: 8))
        }
    }
}

// MARK: - Image Picker

import PhotosUI

struct ImagePicker: UIViewControllerRepresentable {
    @Binding var selectedImage: UIImage?
    @Environment(\.dismiss) private var dismiss
    
    func makeUIViewController(context: Context) -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator
        return picker
    }
    
    func updateUIViewController(_ uiViewController: PHPickerViewController, context: Context) {}
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: ImagePicker
        
        init(_ parent: ImagePicker) {
            self.parent = parent
        }
        
        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            picker.dismiss(animated: true)
            
            guard let provider = results.first?.itemProvider else { return }
            
            if provider.canLoadObject(ofClass: UIImage.self) {
                provider.loadObject(ofClass: UIImage.self) { image, _ in
                    DispatchQueue.main.async {
                        self.parent.selectedImage = image as? UIImage
                    }
                }
            }
        }
    }
}

// ShareSheet → definido en MedidasSectionView.swift
// Color(hex:) → Extraído a Extensions/Color+Hex.swift
