//
//  OffsiteCapturesView.swift
//  lidar
//
//  Lista de capturas offsite y vista detalle: imagen con mediciones superpuestas + modo edición.
//

import SwiftUI

/// Entrada de una captura offsite (imagen + JSON con mismo nombre base).
struct OffsiteCaptureEntry: Identifiable, Hashable {
    let id: String
    let imageURL: URL
    let jsonURL: URL
    let capturedAt: Date
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    static func == (lhs: OffsiteCaptureEntry, rhs: OffsiteCaptureEntry) -> Bool {
        lhs.id == rhs.id
    }
}

/// Lista de capturas guardadas en Documents/OffsiteCaptures/
struct OffsiteCapturesListView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var entries: [OffsiteCaptureEntry] = []

    var body: some View {
        NavigationStack {
            Group {
                if entries.isEmpty {
                    ContentUnavailableView(
                        "Sin capturas offsite",
                        systemImage: "camera.viewfinder",
                        description: Text("Usa «Capturar para offsite» en la barra superior para guardar una foto con las mediciones.")
                    )
                } else {
                    List {
                        ForEach(entries) { entry in
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
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(.vertical, 4)
                            }
                        }
                        .onDelete(perform: deleteEntries)
                    }
                }
            }
            .navigationTitle("Capturas offsite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cerrar") { dismiss() }
                }
                if !entries.isEmpty {
                    ToolbarItem(placement: .primaryAction) {
                        EditButton()
                    }
                }
            }
            .onAppear { loadEntries() }
            .navigationDestination(for: OffsiteCaptureEntry.self) { entry in
                OffsiteCaptureDetailView(entry: entry)
            }
        }
    }

    private func thumbnail(for entry: OffsiteCaptureEntry) -> some View {
        Group {
            // Intentar cargar thumbnail optimizado primero
            let thumbURL = entry.imageURL.deletingLastPathComponent()
                .appendingPathComponent(entry.imageURL.deletingPathExtension().lastPathComponent + "_thumb.jpg")
            
            if let img = UIImage(contentsOfFile: thumbURL.path) {
                Image(uiImage: img)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else if let img = UIImage(contentsOfFile: entry.imageURL.path) {
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
    
    private func deleteEntries(at offsets: IndexSet) {
        let fileManager = FileManager.default
        for index in offsets {
            let entry = entries[index]
            // Eliminar imagen, JSON y thumbnail
            try? fileManager.removeItem(at: entry.imageURL)
            try? fileManager.removeItem(at: entry.jsonURL)
            let thumbURL = entry.imageURL.deletingLastPathComponent()
                .appendingPathComponent(entry.imageURL.deletingPathExtension().lastPathComponent + "_thumb.jpg")
            try? fileManager.removeItem(at: thumbURL)
        }
        entries.remove(atOffsets: offsets)
        
        // Feedback háptico
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }

    private func loadEntries() {
        let fileManager = FileManager.default
        guard let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        let dir = docs.appendingPathComponent("OffsiteCaptures", isDirectory: true)
        guard let contents = try? fileManager.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.contentModificationDateKey], options: .skipsHiddenFiles) else { return }
        let jpgURLs = contents.filter { $0.pathExtension.lowercased() == "jpg" && !$0.lastPathComponent.contains("_thumb") }
        var list: [OffsiteCaptureEntry] = []
        for imageURL in jpgURLs {
            let base = imageURL.deletingPathExtension().lastPathComponent
            let jsonURL = imageURL.deletingLastPathComponent().appendingPathComponent("\(base).json")
            guard fileManager.fileExists(atPath: jsonURL.path) else { continue }
            let date = (try? fileManager.attributesOfItem(atPath: imageURL.path)[.modificationDate] as? Date) ?? Date()
            list.append(OffsiteCaptureEntry(id: base, imageURL: imageURL, jsonURL: jsonURL, capturedAt: date))
        }
        list.sort { $0.capturedAt > $1.capturedAt }
        entries = list
    }
}

/// Vista detalle: imagen con líneas y etiquetas de mediciones superpuestas + modo edición.
struct OffsiteCaptureDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let entry: OffsiteCaptureEntry
    @State private var image: UIImage?
    @State private var data: OffsiteCaptureData?
    @State private var unit: MeasurementUnit = .meters
    @State private var isEditMode: Bool = false
    @State private var editTool: EditTool = .none
    @State private var pendingMeasurementPoint: CGPoint?
    @State private var pendingMeasurementNormalizedPoint: NormalizedPoint?
    @State private var pendingFrameStart: CGPoint?
    @State private var showTextInput: Bool = false
    @State private var newTextPosition: CGPoint?
    @State private var pendingTextNormalizedPoint: NormalizedPoint?
    @State private var newTextContent: String = ""
    
    enum EditTool {
        case none, measure, frame, text
    }

    var body: some View {
        GeometryReader { fullGeo in
            ZStack {
                Color.black.ignoresSafeArea()
                
                if let image = image {
                    ZStack(alignment: .topLeading) {
                        Image(uiImage: image)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                        if let data = data {
                            overlaysView(data: data, viewSize: fullGeo.size, imageSize: image.size)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onEnded { value in
                                if isEditMode {
                                    handleEditTap(at: value.location, viewSize: fullGeo.size, imageSize: image.size)
                                }
                            }
                    )
                } else {
                    ProgressView("Cargando…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(isEditMode)
        .persistentSystemOverlays(isEditMode ? .hidden : .automatic)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(isEditMode)
        .toolbar(isEditMode ? .hidden : .visible, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button(isEditMode ? "Cancelar" : "Cerrar") {
                    if isEditMode {
                        cancelEdit()
                    } else {
                        dismiss()
                    }
                }
            }
            
            if !isEditMode {
                ToolbarItem(placement: .primaryAction) {
                    Picker("Unidad", selection: $unit) {
                        Text("m").tag(MeasurementUnit.meters)
                        Text("ft").tag(MeasurementUnit.feet)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 80)
                    .accessibilityLabel("Unidad de medida")
                }
                
                ToolbarItem(placement: .secondaryAction) {
                    Menu {
                        Button {
                            isEditMode = true
                        } label: {
                            Label("Editar", systemImage: "pencil")
                        }
                        ShareLink(item: entry.imageURL, preview: SharePreview("Captura \(entry.capturedAt.formatted(date: .abbreviated, time: .shortened))", image: Image(systemName: "photo"))) {
                            Label("Compartir", systemImage: "square.and.arrow.up")
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
            } else {
                ToolbarItem(placement: .primaryAction) {
                    Button("Guardar") {
                        saveChanges()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
            .overlay(alignment: .topTrailing) {
                if isEditMode && editTool != .none {
                    editHint
                }
            }
            .safeAreaInset(edge: .bottom) {
                if isEditMode {
                    editToolbar
                }
            }
            .background(isEditMode ? Color.black.opacity(0.3) : Color.clear)
            .animation(.easeInOut(duration: 0.3), value: isEditMode)
            .alert("Añadir texto", isPresented: $showTextInput) {
                TextField("Escribe aquí", text: $newTextContent)
                Button("Cancelar", role: .cancel) {
                    newTextContent = ""
                    newTextPosition = nil
                }
                Button("Añadir") {
                    addTextAnnotation()
                }
            } message: {
                Text("Añade una anotación de texto en esta posición")
            }
            .onAppear {
                image = UIImage(contentsOfFile: entry.imageURL.path)
                loadData()
            }
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
            
            // Info adicional para mediciones
            if editTool == .measure {
                VStack(alignment: .trailing, spacing: 4) {
                    if let arMeasurements = data?.measurements.filter({ $0.isFromAR }), !arMeasurements.isEmpty {
                        Label("Escala: \(arMeasurements.count) medición\(arMeasurements.count == 1 ? "" : "es") AR", systemImage: "checkmark.circle.fill")
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
        switch editTool {
        case .measure: return pendingMeasurementPoint == nil ? "1.circle.fill" : "2.circle.fill"
        case .frame: return "rectangle.dashed"
        case .text: return "text.bubble.fill"
        case .none: return ""
        }
    }
    
    private var hintText: String {
        switch editTool {
        case .measure:
            return pendingMeasurementPoint == nil ? "Toca el primer punto" : "Toca el segundo punto"
        case .frame:
            return "Toca para colocar cuadro"
        case .text:
            return "Toca para añadir texto"
        case .none:
            return ""
        }
    }
    
    // MARK: - Edit Toolbar
    
    private var editToolbar: some View {
        VStack(spacing: 16) {
            // Leyenda de colores
            if !isEditMode {
                EmptyView()
            } else {
                HStack(spacing: 20) {
                    Label("AR precisa", systemImage: "checkmark.seal.fill")
                        .font(.caption2)
                        .foregroundStyle(.green)
                    Label("Offsite aprox.", systemImage: "wave.3.right")
                        .font(.caption2)
                        .foregroundStyle(.cyan)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.5), in: Capsule())
            }
            
            HStack(spacing: 16) {
                ForEach([
                    (EditTool.measure, "ruler", "Medir", Color.green),
                    (EditTool.frame, "rectangle.dashed", "Cuadro", Color.blue),
                    (EditTool.text, "text.bubble", "Texto", Color.purple)
                ], id: \.0) { tool, icon, label, color in
                    Button {
                        withAnimation(.spring(response: 0.3)) {
                            editTool = editTool == tool ? .none : tool
                            pendingMeasurementPoint = nil
                            pendingMeasurementNormalizedPoint = nil
                            pendingFrameStart = nil
                            pendingTextNormalizedPoint = nil
                        }
                        let generator = UIImpactFeedbackGenerator(style: .medium)
                        generator.impactOccurred()
                    } label: {
                        VStack(spacing: 6) {
                            ZStack {
                                Circle()
                                    .fill(editTool == tool ? color : Color.gray.opacity(0.3))
                                    .frame(width: 56, height: 56)
                                Image(systemName: icon)
                                    .font(.title2)
                                    .foregroundStyle(editTool == tool ? .white : .primary)
                            }
                            Text(label)
                                .font(.caption)
                                .fontWeight(editTool == tool ? .bold : .regular)
                                .foregroundStyle(editTool == tool ? color : .secondary)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
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
    
    // MARK: - Overlays
    
    @ViewBuilder
    private func overlaysView(data: OffsiteCaptureData, viewSize: CGSize, imageSize: CGSize) -> some View {
        let scale = scaleToFit(imageSize: imageSize, in: viewSize)
        let offset = offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)
        
        ForEach(data.measurements) { m in
            measurementOverlay(m, scale: scale, offset: offset, imageSize: imageSize)
        }
        
        ForEach(data.frames) { frame in
            frameOverlay(frame, scale: scale, offset: offset, imageSize: imageSize)
        }
        
        ForEach(data.textAnnotations) { annotation in
            textAnnotationOverlay(annotation, scale: scale, offset: offset, imageSize: imageSize)
        }
        
        if let point = pendingMeasurementPoint {
            ZStack {
                Circle()
                    .fill(Color.orange)
                    .frame(width: 20, height: 20)
                Circle()
                    .stroke(Color.orange, lineWidth: 3)
                    .frame(width: 32, height: 32)
                    .opacity(0.5)
            }
            .position(point)
            .transition(.scale.combined(with: .opacity))
        }
    }
    
    @ViewBuilder
    private func measurementOverlay(_ m: OffsiteMeasurement, scale: CGFloat, offset: CGPoint, imageSize: CGSize) -> some View {
        let pA = CGPoint(
            x: m.pointA.x * imageSize.width * scale + offset.x,
            y: m.pointA.y * imageSize.height * scale + offset.y
        )
        let pB = CGPoint(
            x: m.pointB.x * imageSize.width * scale + offset.x,
            y: m.pointB.y * imageSize.height * scale + offset.y
        )
        
        // Color según tipo: verde brillante = AR (precisa), cyan = offsite (aproximada)
        let lineColor = m.isFromAR ? Color.green : Color.cyan
        let labelBg = m.isFromAR ? Color.black.opacity(0.8) : Color.blue.opacity(0.6)
        
        ZStack {
            Path { path in
                path.move(to: pA)
                path.addLine(to: pB)
            }
            .stroke(lineColor, lineWidth: m.isFromAR ? 2 : 3)
            
            Circle()
                .fill(Color.orange)
                .frame(width: 10, height: 10)
                .position(pA)
            
            Circle()
                .fill(lineColor)
                .frame(width: 10, height: 10)
                .position(pB)
            
            VStack(spacing: 2) {
                Text(unit.format(distanceMeters: Float(m.distanceMeters)))
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                if !m.isFromAR {
                    Text("≈ aproximada")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.8))
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(labelBg, in: RoundedRectangle(cornerRadius: 6))
            .position(x: (pA.x + pB.x) / 2, y: (pA.y + pB.y) / 2 - 20)
            
            if isEditMode {
                Button {
                    deleteMeasurement(id: m.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.red)
                        .background(Circle().fill(.white))
                }
                .position(x: (pA.x + pB.x) / 2 + 40, y: (pA.y + pB.y) / 2 - 20)
            }
        }
    }
    
    @ViewBuilder
    private func frameOverlay(_ frame: OffsiteFrame, scale: CGFloat, offset: CGPoint, imageSize: CGSize) -> some View {
        let x = frame.topLeft.x * imageSize.width * scale + offset.x
        let y = frame.topLeft.y * imageSize.height * scale + offset.y
        let w = frame.width * imageSize.width * scale
        let h = frame.height * imageSize.height * scale
        
        ZStack {
            Rectangle()
                .strokeBorder(Color(hex: frame.color), lineWidth: 3)
                .background(Color(hex: frame.color).opacity(0.1))
                .frame(width: w, height: h)
                .position(x: x + w/2, y: y + h/2)
            
            if let label = frame.label {
                Text(label)
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color(hex: frame.color), in: RoundedRectangle(cornerRadius: 4))
                    .position(x: x + w/2, y: y - 8)
            }
            
            if isEditMode {
                Button {
                    deleteFrame(id: frame.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .background(Circle().fill(.white))
                }
                .position(x: x + w - 8, y: y + 8)
            }
        }
    }
    
    @ViewBuilder
    private func textAnnotationOverlay(_ annotation: OffsiteTextAnnotation, scale: CGFloat, offset: CGPoint, imageSize: CGSize) -> some View {
        let pos = CGPoint(
            x: annotation.position.x * imageSize.width * scale + offset.x,
            y: annotation.position.y * imageSize.height * scale + offset.y
        )
        
        ZStack {
            Text(annotation.text)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(Color(hex: annotation.color))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6))
                .position(pos)
            
            if isEditMode {
                Button {
                    deleteTextAnnotation(id: annotation.id)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.red)
                        .background(Circle().fill(.white))
                        .font(.caption)
                }
                .position(x: pos.x + 40, y: pos.y - 10)
            }
        }
    }
    
    // MARK: - Edit Handlers
    
    private func handleEditTap(at location: CGPoint, viewSize: CGSize, imageSize: CGSize) {
        guard data != nil else { return }
        
        let scale = scaleToFit(imageSize: imageSize, in: viewSize)
        let offset = offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)
        
        let normalizedX = (location.x - offset.x) / (imageSize.width * scale)
        let normalizedY = (location.y - offset.y) / (imageSize.height * scale)
        
        guard normalizedX >= 0 && normalizedX <= 1 && normalizedY >= 0 && normalizedY <= 1 else { return }
        
        let normalizedPoint = NormalizedPoint(x: normalizedX, y: normalizedY)
        
        switch editTool {
        case .measure:
            handleMeasureTap(point: normalizedPoint, screenPoint: location, viewSize: viewSize, imageSize: imageSize)
        case .frame:
            handleFrameTap(point: normalizedPoint)
        case .text:
            handleTextTap(point: normalizedPoint, screenPoint: location, viewSize: viewSize, imageSize: imageSize)
        case .none:
            break
        }
    }
    
    private func handleMeasureTap(point: NormalizedPoint, screenPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) {
        guard var currentData = data else { return }
        
        if let firstPointScreen = pendingMeasurementPoint, let firstPointNorm = pendingMeasurementNormalizedPoint {
            // Calcular distancia basada en mediciones AR de referencia
            let distance = calculateDistance(from: firstPointScreen, to: screenPoint, viewSize: viewSize, imageSize: imageSize)
            
            let newMeasurement = OffsiteMeasurement(
                distanceMeters: distance,
                pointA: firstPointNorm,
                pointB: point,
                isFromAR: false  // Medición añadida offsite
            )
            currentData.measurements.append(newMeasurement)
            data = currentData
            pendingMeasurementPoint = nil
            pendingMeasurementNormalizedPoint = nil
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        } else {
            pendingMeasurementPoint = screenPoint
            pendingMeasurementNormalizedPoint = point
            let generator = UIImpactFeedbackGenerator(style: .medium)
            generator.impactOccurred()
        }
    }
    
    private func handleFrameTap(point: NormalizedPoint) {
        guard var currentData = data else { return }
        
        let newFrame = OffsiteFrame(
            topLeft: point,
            width: 0.15,
            height: 0.15,
            label: "Cuadro \(currentData.frames.count + 1)",
            color: ["#3B82F6", "#10B981", "#F59E0B", "#EF4444", "#8B5CF6"].randomElement() ?? "#3B82F6"
        )
        currentData.frames.append(newFrame)
        data = currentData
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func handleTextTap(point: NormalizedPoint, screenPoint: CGPoint, viewSize: CGSize, imageSize: CGSize) {
        pendingTextNormalizedPoint = point
        newTextPosition = screenPoint
        showTextInput = true
    }
    
    private func addTextAnnotation() {
        guard let normalizedPoint = pendingTextNormalizedPoint, !newTextContent.isEmpty, var currentData = data else { return }
        
        let annotation = OffsiteTextAnnotation(
            position: normalizedPoint,
            text: newTextContent
        )
        currentData.textAnnotations.append(annotation)
        data = currentData
        newTextContent = ""
        newTextPosition = nil
        pendingTextNormalizedPoint = nil
        
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
    }
    
    private func calculateDistance(from pointA: CGPoint, to pointB: CGPoint, viewSize: CGSize, imageSize: CGSize) -> Double {
        let dx = pointB.x - pointA.x
        let dy = pointB.y - pointA.y
        let pixelDistance = sqrt(dx*dx + dy*dy)
        
        // Buscar mediciones AR de referencia (isFromAR = true)
        if let currentData = data,
           let arMeasurement = currentData.measurements.first(where: { $0.isFromAR }) {
            
            let scale = scaleToFit(imageSize: imageSize, in: viewSize)
            let offset = offsetToCenter(imageSize: imageSize, in: viewSize, scale: scale)
            
            let refA = CGPoint(
                x: arMeasurement.pointA.x * imageSize.width * scale + offset.x,
                y: arMeasurement.pointA.y * imageSize.height * scale + offset.y
            )
            let refB = CGPoint(
                x: arMeasurement.pointB.x * imageSize.width * scale + offset.x,
                y: arMeasurement.pointB.y * imageSize.height * scale + offset.y
            )
            let refDx = refB.x - refA.x
            let refDy = refB.y - refA.y
            let refPixelDistance = sqrt(refDx*refDx + refDy*refDy)
            
            // Calcular proporción basada en medición AR precisa
            let metersPerPixel = arMeasurement.distanceMeters / refPixelDistance
            return pixelDistance * metersPerPixel
        }
        
        // Sin referencia AR: distancia arbitraria (muy aproximada)
        return pixelDistance * 0.01
    }
    
    // MARK: - Delete Actions
    
    private func deleteMeasurement(id: UUID) {
        guard var currentData = data else { return }
        currentData.measurements.removeAll { $0.id == id }
        data = currentData
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func deleteFrame(id: UUID) {
        guard var currentData = data else { return }
        currentData.frames.removeAll { $0.id == id }
        data = currentData
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    private func deleteTextAnnotation(id: UUID) {
        guard var currentData = data else { return }
        currentData.textAnnotations.removeAll { $0.id == id }
        data = currentData
        
        let generator = UIImpactFeedbackGenerator(style: .light)
        generator.impactOccurred()
    }
    
    // MARK: - Save & Cancel
    
    private func saveChanges() {
        guard var currentData = data else { return }
        currentData.lastModified = Date()
        
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            try encoder.encode(currentData).write(to: entry.jsonURL)
            
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            
            isEditMode = false
            editTool = .none
            pendingMeasurementPoint = nil
            pendingMeasurementNormalizedPoint = nil
            pendingFrameStart = nil
            pendingTextNormalizedPoint = nil
        } catch {
            print("Error guardando cambios: \(error)")
        }
    }
    
    private func cancelEdit() {
        loadData()
        isEditMode = false
        editTool = .none
        pendingMeasurementPoint = nil
        pendingMeasurementNormalizedPoint = nil
        pendingFrameStart = nil
        pendingTextNormalizedPoint = nil
    }
    
    private func loadData() {
        if let d = try? Data(contentsOf: entry.jsonURL) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let c = try decoder.singleValueContainer()
                let s = try c.decode(String.self)
                let f = ISO8601DateFormatter()
                f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let date = f.date(from: s) { return date }
                f.formatOptions = [.withInternetDateTime]
                return f.date(from: s) ?? Date()
            }
            if let decoded = try? decoder.decode(OffsiteCaptureData.self, from: d) {
                data = decoded
            }
        }
    }
    
    // MARK: - Helpers
    
    func scaleToFit(imageSize: CGSize, in viewSize: CGSize) -> CGFloat {
        guard imageSize.width > 0, imageSize.height > 0 else { return 1 }
        let sx = viewSize.width / imageSize.width
        let sy = viewSize.height / imageSize.height
        return min(sx, sy)
    }

    func offsetToCenter(imageSize: CGSize, in viewSize: CGSize, scale: CGFloat) -> CGPoint {
        let w = imageSize.width * scale
        let h = imageSize.height * scale
        return CGPoint(x: (viewSize.width - w) / 2, y: (viewSize.height - h) / 2)
    }
}

// MARK: - Color from Hex

extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let r, g, b: UInt64
        switch hex.count {
        case 6:
            (r, g, b) = ((int >> 16) & 0xFF, (int >> 8) & 0xFF, int & 0xFF)
        default:
            (r, g, b) = (0, 0, 0)
        }
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255
        )
    }
}
