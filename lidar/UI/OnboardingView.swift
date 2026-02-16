//
//  OnboardingView.swift
//  lidar
//
//  Pantallas de onboarding para primera vez: explica al usuario cómo usar la app.
//

import SwiftUI

struct OnboardingView: View {
    @Binding var isPresented: Bool
    @State private var currentPage = 0
    
    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "cube.transparent",
            iconColor: .blue,
            title: "Escanea espacios en 3D",
            subtitle: "Apunta la cámara a las paredes, suelo y techo. La app detecta automáticamente las superficies y mide la habitación.",
            hint: "Funciona mejor con LiDAR (iPhone Pro/iPad Pro)"
        ),
        OnboardingPage(
            icon: "ruler",
            iconColor: .green,
            title: "Mide con precisión",
            subtitle: "Toca dos puntos en cualquier superficie para obtener la distancia exacta. Las mediciones se ajustan automáticamente a bordes y esquinas.",
            hint: "Precisión milimétrica con sensor LiDAR"
        ),
        OnboardingPage(
            icon: "photo.artframe",
            iconColor: .purple,
            title: "Coloca cuadros virtuales",
            subtitle: "Visualiza cómo quedarían tus cuadros o fotos en las paredes antes de colgarlos. Se adaptan a la perspectiva real de cada superficie.",
            hint: "También en esquinas, techos y suelos"
        ),
        OnboardingPage(
            icon: "camera.viewfinder",
            iconColor: .orange,
            title: "Captura y exporta",
            subtitle: "Guarda capturas con todas las mediciones y datos 3D. Genera informes PDF profesionales para compartir con tu equipo.",
            hint: "Comparte informes directamente desde la app"
        )
    ]
    
    var body: some View {
        ZStack {
            // Fondo gradiente
            LinearGradient(
                colors: [Color.black, pages[currentPage].iconColor.opacity(0.3), Color.black],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()
            .animation(.easeInOut(duration: 0.5), value: currentPage)
            
            VStack(spacing: 0) {
                Spacer()
                
                // Icono animado
                ZStack {
                    Circle()
                        .fill(pages[currentPage].iconColor.opacity(0.15))
                        .frame(width: 160, height: 160)
                    
                    Circle()
                        .fill(pages[currentPage].iconColor.opacity(0.08))
                        .frame(width: 200, height: 200)
                    
                    Image(systemName: pages[currentPage].icon)
                        .font(.system(size: 64, weight: .light))
                        .foregroundStyle(pages[currentPage].iconColor)
                        .symbolEffect(.pulse, options: .repeating)
                }
                .padding(.bottom, 40)
                
                // Título
                Text(pages[currentPage].title)
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
                
                // Subtítulo
                Text(pages[currentPage].subtitle)
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .padding(.top, 12)
                
                // Hint
                if let hint = pages[currentPage].hint {
                    HStack(spacing: 6) {
                        Image(systemName: "lightbulb.fill")
                            .font(.caption)
                        Text(hint)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundStyle(pages[currentPage].iconColor)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(pages[currentPage].iconColor.opacity(0.15))
                    .clipShape(Capsule())
                    .padding(.top, 20)
                }
                
                Spacer()
                
                // Indicador de página
                HStack(spacing: 8) {
                    ForEach(0..<pages.count, id: \.self) { index in
                        Capsule()
                            .fill(index == currentPage ? pages[currentPage].iconColor : .white.opacity(0.3))
                            .frame(width: index == currentPage ? 24 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentPage)
                    }
                }
                .padding(.bottom, 32)
                
                // Botones
                HStack(spacing: 16) {
                    if currentPage > 0 {
                        Button {
                            withAnimation(.spring(response: 0.35)) {
                                currentPage -= 1
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "chevron.left")
                                Text("Atrás")
                            }
                            .font(.body)
                            .fontWeight(.medium)
                            .foregroundStyle(.white.opacity(0.7))
                            .padding(.horizontal, 24)
                            .padding(.vertical, 14)
                        }
                    }
                    
                    Spacer()
                    
                    if currentPage < pages.count - 1 {
                        // Skip
                        Button {
                            completeOnboarding()
                        } label: {
                            Text("Saltar")
                                .font(.subheadline)
                                .foregroundStyle(.white.opacity(0.5))
                        }
                        
                        Button {
                            withAnimation(.spring(response: 0.35)) {
                                currentPage += 1
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text("Siguiente")
                                Image(systemName: "chevron.right")
                            }
                            .font(.body)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 28)
                            .padding(.vertical, 14)
                            .background(pages[currentPage].iconColor)
                            .clipShape(Capsule())
                        }
                    } else {
                        Button {
                            completeOnboarding()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                Text("Empezar")
                            }
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(pages[currentPage].iconColor)
                            .clipShape(Capsule())
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 50)
                .onEnded { value in
                    if value.translation.width < -50, currentPage < pages.count - 1 {
                        withAnimation(.spring(response: 0.35)) { currentPage += 1 }
                    } else if value.translation.width > 50, currentPage > 0 {
                        withAnimation(.spring(response: 0.35)) { currentPage -= 1 }
                    }
                }
        )
    }
    
    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        withAnimation(.easeInOut(duration: 0.4)) {
            isPresented = false
        }
    }
}

// MARK: - Model

private struct OnboardingPage {
    let icon: String
    let iconColor: Color
    let title: String
    let subtitle: String
    let hint: String?
}

#Preview {
    OnboardingView(isPresented: .constant(true))
}
