//
//  PDFReportService.swift
//  lidar
//
//  Genera informes PDF profesionales con mediciones, planos detectados y cuadros colocados.
//

import UIKit
import PDFKit

/// Servicio para generar informes PDF con los datos de la escena AR.
final class PDFReportService {
    
    // MARK: - Public API
    
    /// Genera un PDF con los datos de la escena y devuelve la URL del archivo temporal.
    static func generateReport(
        sceneImage: UIImage?,
        measurements: [(index: Int, distance: Float, unit: MeasurementUnit)],
        planes: [(classification: String, width: Float, height: Float)],
        corners: Int,
        frames: Int,
        isLiDAR: Bool,
        roomSummary: RoomSummary?
    ) -> URL? {
        let pageWidth: CGFloat = 595.28  // A4
        let pageHeight: CGFloat = 841.89
        let margin: CGFloat = 40
        let contentWidth = pageWidth - margin * 2
        
        let pdfMetaData = [
            kCGPDFContextCreator: "LiDAR Scanner",
            kCGPDFContextAuthor: "LiDAR App",
            kCGPDFContextTitle: "Informe de Mediciones AR"
        ]
        
        let format = UIGraphicsPDFRendererFormat()
        format.documentInfo = pdfMetaData as [String: Any]
        
        let renderer = UIGraphicsPDFRenderer(
            bounds: CGRect(x: 0, y: 0, width: pageWidth, height: pageHeight),
            format: format
        )
        
        let data = renderer.pdfData { context in
            // === PÁGINA 1: Portada + Imagen + Resumen ===
            context.beginPage()
            var yPos: CGFloat = margin
            
            // Header con marca
            yPos = drawHeader(at: yPos, width: contentWidth, margin: margin, isLiDAR: isLiDAR)
            
            // Fecha y hora
            let dateFormatter = DateFormatter()
            dateFormatter.dateStyle = .long
            dateFormatter.timeStyle = .short
            dateFormatter.locale = Locale(identifier: "es_ES")
            let dateStr = "Generado: \(dateFormatter.string(from: Date()))"
            yPos = drawText(dateStr, at: yPos, margin: margin, width: contentWidth,
                           font: .systemFont(ofSize: 10), color: .gray)
            yPos += 16
            
            // Imagen de la escena
            if let image = sceneImage {
                yPos = drawSceneImage(image, at: yPos, margin: margin, contentWidth: contentWidth)
                yPos += 16
            }
            
            // Resumen de habitación (si disponible)
            if let room = roomSummary {
                yPos = drawRoomSummary(room, at: yPos, margin: margin, contentWidth: contentWidth)
                yPos += 12
            }
            
            // Resumen rápido
            yPos = drawQuickSummary(
                measurements: measurements.count,
                planes: planes.count,
                corners: corners,
                frames: frames,
                at: yPos, margin: margin, contentWidth: contentWidth
            )
            
            // Footer
            drawFooter(pageNumber: 1, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
            
            // === PÁGINA 2: Mediciones detalladas ===
            if !measurements.isEmpty {
                context.beginPage()
                yPos = margin
                
                yPos = drawSectionTitle("📏 Mediciones", at: yPos, margin: margin, contentWidth: contentWidth)
                yPos += 8
                
                // Tabla de mediciones
                yPos = drawMeasurementsTable(measurements, at: yPos, margin: margin, contentWidth: contentWidth)
                yPos += 16
                
                // Total / perímetro
                let totalDistance = measurements.reduce(Float(0)) { $0 + $1.distance }
                let unit = measurements.first?.unit ?? .meters
                let totalStr = unit.format(distanceMeters: totalDistance)
                yPos = drawText("Distancia total acumulada: \(totalStr)",
                               at: yPos, margin: margin, width: contentWidth,
                               font: .boldSystemFont(ofSize: 13), color: .darkGray)
                
                drawFooter(pageNumber: 2, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
            }
            
            // === PÁGINA 3: Planos detectados ===
            if !planes.isEmpty {
                context.beginPage()
                yPos = margin
                
                yPos = drawSectionTitle("🏗️ Superficies Detectadas", at: yPos, margin: margin, contentWidth: contentWidth)
                yPos += 8
                
                yPos = drawPlanesTable(planes, at: yPos, margin: margin, contentWidth: contentWidth)
                
                // Área total
                let totalArea = planes.reduce(Float(0)) { $0 + $1.width * $1.height }
                yPos += 16
                yPos = drawText("Área total de superficies: \(String(format: "%.2f m²", totalArea))",
                               at: yPos, margin: margin, width: contentWidth,
                               font: .boldSystemFont(ofSize: 13), color: .darkGray)
                
                drawFooter(pageNumber: 3, pageWidth: pageWidth, pageHeight: pageHeight, margin: margin)
            }
        }
        
        // Guardar PDF temporal
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Informe_LiDAR_\(Int(Date().timeIntervalSince1970)).pdf")
        
        do {
            try data.write(to: tempURL)
            return tempURL
        } catch {
            return nil
        }
    }
    
    // MARK: - Drawing Helpers
    
    private static func drawHeader(at y: CGFloat, width: CGFloat, margin: CGFloat, isLiDAR: Bool) -> CGFloat {
        var yPos = y
        
        // Título principal
        let titleFont = UIFont.systemFont(ofSize: 24, weight: .bold)
        let title = "Informe de Mediciones AR"
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)
        ]
        let titleRect = CGRect(x: margin, y: yPos, width: width, height: 34)
        (title as NSString).draw(in: titleRect, withAttributes: titleAttr)
        yPos += 36
        
        // Subtítulo
        let subtitleFont = UIFont.systemFont(ofSize: 12, weight: .medium)
        let sensor = isLiDAR ? "Sensor LiDAR ✓" : "AR estándar"
        let subtitle = "Generado con LiDAR Scanner · \(sensor)"
        let subtitleAttr: [NSAttributedString.Key: Any] = [
            .font: subtitleFont,
            .foregroundColor: UIColor.gray
        ]
        let subtitleRect = CGRect(x: margin, y: yPos, width: width, height: 18)
        (subtitle as NSString).draw(in: subtitleRect, withAttributes: subtitleAttr)
        yPos += 22
        
        // Línea separadora
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: margin, y: yPos))
        linePath.addLine(to: CGPoint(x: margin + width, y: yPos))
        UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.6).setStroke()
        linePath.lineWidth = 2
        linePath.stroke()
        yPos += 12
        
        return yPos
    }
    
    private static func drawText(_ text: String, at y: CGFloat, margin: CGFloat, width: CGFloat,
                                  font: UIFont, color: UIColor) -> CGFloat {
        let attr: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
        let size = (text as NSString).boundingRect(
            with: CGSize(width: width, height: .greatestFiniteMagnitude),
            options: .usesLineFragmentOrigin, attributes: attr, context: nil
        )
        let rect = CGRect(x: margin, y: y, width: width, height: size.height)
        (text as NSString).draw(in: rect, withAttributes: attr)
        return y + size.height + 4
    }
    
    private static func drawSceneImage(_ image: UIImage, at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let aspectRatio = image.size.height / image.size.width
        let imageWidth = contentWidth
        let imageHeight = min(imageWidth * aspectRatio, 300)
        
        // Borde redondeado
        let imageRect = CGRect(x: margin, y: y, width: imageWidth, height: imageHeight)
        let path = UIBezierPath(roundedRect: imageRect, cornerRadius: 8)
        path.addClip()
        image.draw(in: imageRect)
        
        // Restaurar estado gráfico
        UIGraphicsGetCurrentContext()?.resetClip()
        
        // Borde
        UIColor.lightGray.setStroke()
        let borderPath = UIBezierPath(roundedRect: imageRect, cornerRadius: 8)
        borderPath.lineWidth = 0.5
        borderPath.stroke()
        
        return y + imageHeight
    }
    
    private static func drawRoomSummary(_ room: RoomSummary, at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        var yPos = y
        
        // Caja de resumen
        let boxHeight: CGFloat = 70
        let boxRect = CGRect(x: margin, y: yPos, width: contentWidth, height: boxHeight)
        let boxPath = UIBezierPath(roundedRect: boxRect, cornerRadius: 8)
        UIColor(red: 0.93, green: 0.95, blue: 1.0, alpha: 1).setFill()
        boxPath.fill()
        UIColor(red: 0.2, green: 0.5, blue: 0.9, alpha: 0.3).setStroke()
        boxPath.lineWidth = 1
        boxPath.stroke()
        
        // Icono + título
        let titleFont = UIFont.systemFont(ofSize: 14, weight: .semibold)
        let titleAttr: [NSAttributedString.Key: Any] = [
            .font: titleFont,
            .foregroundColor: UIColor(red: 0.15, green: 0.15, blue: 0.3, alpha: 1)
        ]
        ("📐 Dimensiones estimadas de la habitación" as NSString).draw(
            in: CGRect(x: margin + 12, y: yPos + 10, width: contentWidth - 24, height: 20),
            withAttributes: titleAttr
        )
        
        // Dimensiones
        let dimsFont = UIFont.monospacedDigitSystemFont(ofSize: 18, weight: .bold)
        let dimsStr = String(format: "%.1f × %.1f × %.1f m", room.width, room.length, room.height)
        let dimsAttr: [NSAttributedString.Key: Any] = [
            .font: dimsFont,
            .foregroundColor: UIColor(red: 0.1, green: 0.3, blue: 0.7, alpha: 1)
        ]
        (dimsStr as NSString).draw(
            in: CGRect(x: margin + 12, y: yPos + 34, width: contentWidth / 2, height: 24),
            withAttributes: dimsAttr
        )
        
        // Área
        let areaStr = String(format: "Área: %.1f m²  ·  Vol: %.1f m³", room.area, room.volume)
        let areaAttr: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: UIColor.gray
        ]
        (areaStr as NSString).draw(
            in: CGRect(x: margin + contentWidth / 2, y: yPos + 38, width: contentWidth / 2 - 12, height: 18),
            withAttributes: areaAttr
        )
        
        return yPos + boxHeight
    }
    
    private static func drawQuickSummary(measurements: Int, planes: Int, corners: Int, frames: Int,
                                          at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        var yPos = y + 8
        
        let items = [
            ("📏 Mediciones", "\(measurements)"),
            ("🧱 Superficies", "\(planes)"),
            ("📐 Esquinas", "\(corners)"),
            ("🖼️ Cuadros", "\(frames)")
        ]
        
        let colWidth = contentWidth / CGFloat(items.count)
        
        for (i, item) in items.enumerated() {
            let x = margin + CGFloat(i) * colWidth
            
            // Número grande
            let numFont = UIFont.monospacedDigitSystemFont(ofSize: 22, weight: .bold)
            let numAttr: [NSAttributedString.Key: Any] = [
                .font: numFont,
                .foregroundColor: UIColor(red: 0.15, green: 0.15, blue: 0.3, alpha: 1)
            ]
            (item.1 as NSString).draw(
                in: CGRect(x: x, y: yPos, width: colWidth, height: 28),
                withAttributes: numAttr
            )
            
            // Etiqueta
            let labelFont = UIFont.systemFont(ofSize: 9, weight: .medium)
            let labelAttr: [NSAttributedString.Key: Any] = [
                .font: labelFont,
                .foregroundColor: UIColor.gray
            ]
            (item.0 as NSString).draw(
                in: CGRect(x: x, y: yPos + 26, width: colWidth, height: 14),
                withAttributes: labelAttr
            )
        }
        
        return yPos + 50
    }
    
    private static func drawSectionTitle(_ title: String, at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        let font = UIFont.systemFont(ofSize: 18, weight: .bold)
        let attr: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: UIColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1)
        ]
        let rect = CGRect(x: margin, y: y, width: contentWidth, height: 26)
        (title as NSString).draw(in: rect, withAttributes: attr)
        
        // Línea
        let linePath = UIBezierPath()
        linePath.move(to: CGPoint(x: margin, y: y + 28))
        linePath.addLine(to: CGPoint(x: margin + contentWidth, y: y + 28))
        UIColor.lightGray.setStroke()
        linePath.lineWidth = 0.5
        linePath.stroke()
        
        return y + 32
    }
    
    private static func drawMeasurementsTable(_ measurements: [(index: Int, distance: Float, unit: MeasurementUnit)],
                                               at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        var yPos = y
        let rowHeight: CGFloat = 28
        let col1Width: CGFloat = 60     // #
        let col2Width: CGFloat = 200    // Distancia
        
        // Header
        let headerFont = UIFont.systemFont(ofSize: 10, weight: .bold)
        let headerAttr: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: UIColor.gray]
        
        let headerRect = CGRect(x: margin, y: yPos, width: contentWidth, height: rowHeight)
        UIColor(white: 0.95, alpha: 1).setFill()
        UIBezierPath(roundedRect: headerRect, cornerRadius: 4).fill()
        
        ("#" as NSString).draw(in: CGRect(x: margin + 8, y: yPos + 7, width: col1Width, height: 14), withAttributes: headerAttr)
        ("Distancia" as NSString).draw(in: CGRect(x: margin + col1Width, y: yPos + 7, width: col2Width, height: 14), withAttributes: headerAttr)
        yPos += rowHeight
        
        // Filas
        let rowFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .regular)
        let numFont = UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold)
        
        for (i, m) in measurements.enumerated() {
            if i % 2 == 1 {
                UIColor(white: 0.97, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: yPos, width: contentWidth, height: rowHeight))
            }
            
            let indexAttr: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: UIColor.gray]
            let distAttr: [NSAttributedString.Key: Any] = [
                .font: numFont,
                .foregroundColor: UIColor(red: 0.1, green: 0.4, blue: 0.2, alpha: 1)
            ]
            
            ("\(m.index)" as NSString).draw(in: CGRect(x: margin + 8, y: yPos + 7, width: col1Width, height: 14), withAttributes: indexAttr)
            
            let distStr = m.unit.format(distanceMeters: m.distance)
            (distStr as NSString).draw(in: CGRect(x: margin + col1Width, y: yPos + 7, width: col2Width, height: 14), withAttributes: distAttr)
            
            yPos += rowHeight
        }
        
        return yPos
    }
    
    private static func drawPlanesTable(_ planes: [(classification: String, width: Float, height: Float)],
                                         at y: CGFloat, margin: CGFloat, contentWidth: CGFloat) -> CGFloat {
        var yPos = y
        let rowHeight: CGFloat = 28
        
        // Header
        let headerFont = UIFont.systemFont(ofSize: 10, weight: .bold)
        let headerAttr: [NSAttributedString.Key: Any] = [.font: headerFont, .foregroundColor: UIColor.gray]
        
        let headerRect = CGRect(x: margin, y: yPos, width: contentWidth, height: rowHeight)
        UIColor(white: 0.95, alpha: 1).setFill()
        UIBezierPath(roundedRect: headerRect, cornerRadius: 4).fill()
        
        ("Tipo" as NSString).draw(in: CGRect(x: margin + 8, y: yPos + 7, width: 120, height: 14), withAttributes: headerAttr)
        ("Ancho" as NSString).draw(in: CGRect(x: margin + 140, y: yPos + 7, width: 100, height: 14), withAttributes: headerAttr)
        ("Alto" as NSString).draw(in: CGRect(x: margin + 260, y: yPos + 7, width: 100, height: 14), withAttributes: headerAttr)
        ("Área" as NSString).draw(in: CGRect(x: margin + 380, y: yPos + 7, width: 100, height: 14), withAttributes: headerAttr)
        yPos += rowHeight
        
        let rowFont = UIFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        let typeFont = UIFont.systemFont(ofSize: 11, weight: .medium)
        
        for (i, p) in planes.enumerated() {
            if i % 2 == 1 {
                UIColor(white: 0.97, alpha: 1).setFill()
                UIRectFill(CGRect(x: margin, y: yPos, width: contentWidth, height: rowHeight))
            }
            
            let typeAttr: [NSAttributedString.Key: Any] = [.font: typeFont, .foregroundColor: UIColor.darkGray]
            let numAttr: [NSAttributedString.Key: Any] = [.font: rowFont, .foregroundColor: UIColor.darkGray]
            
            (p.classification as NSString).draw(in: CGRect(x: margin + 8, y: yPos + 7, width: 120, height: 14), withAttributes: typeAttr)
            (String(format: "%.2f m", p.width) as NSString).draw(in: CGRect(x: margin + 140, y: yPos + 7, width: 100, height: 14), withAttributes: numAttr)
            (String(format: "%.2f m", p.height) as NSString).draw(in: CGRect(x: margin + 260, y: yPos + 7, width: 100, height: 14), withAttributes: numAttr)
            (String(format: "%.2f m²", p.width * p.height) as NSString).draw(in: CGRect(x: margin + 380, y: yPos + 7, width: 100, height: 14), withAttributes: numAttr)
            
            yPos += rowHeight
        }
        
        return yPos
    }
    
    private static func drawFooter(pageNumber: Int, pageWidth: CGFloat, pageHeight: CGFloat, margin: CGFloat) {
        let footerFont = UIFont.systemFont(ofSize: 8, weight: .regular)
        let footerAttr: [NSAttributedString.Key: Any] = [.font: footerFont, .foregroundColor: UIColor.lightGray]
        
        let leftText = "LiDAR Scanner · Informe automático"
        let rightText = "Página \(pageNumber)"
        
        (leftText as NSString).draw(
            in: CGRect(x: margin, y: pageHeight - 30, width: 200, height: 12),
            withAttributes: footerAttr
        )
        
        let rightWidth: CGFloat = 60
        (rightText as NSString).draw(
            in: CGRect(x: pageWidth - margin - rightWidth, y: pageHeight - 30, width: rightWidth, height: 12),
            withAttributes: footerAttr
        )
    }
}

// MARK: - Room Summary Model

/// Resumen de las dimensiones estimadas de la habitación.
struct RoomSummary {
    let width: Float    // metros
    let length: Float
    let height: Float
    
    var area: Float { width * length }
    var volume: Float { width * length * height }
    
    var description: String {
        String(format: "%.1f × %.1f × %.1f m", width, length, height)
    }
}
