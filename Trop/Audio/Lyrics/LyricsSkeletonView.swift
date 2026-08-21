//
//  LyricsSkeletonView.swift
//  Trop
//
//  Created by 686udjie on 21/08/2026.
//

import SwiftUI

struct LyricsSkeletonView: View {
    @Environment(SettingsStore.self) private var settings
    @State private var isAnimating = false

    private let lineWidthMultipliers: [CGFloat] = [
        0.75, 0.45, 0.85, 0.60, 0.35, 0.70, 0.90, 0.50, 0.65, 0.40
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: settings.lyricsAlignment.textAlignment.horizontal, spacing: 22) {
                Spacer().frame(height: 24)

                ForEach(0..<lineWidthMultipliers.count, id: \.self) { index in
                    GeometryReader { geo in
                        let width = max(60, geo.size.width * lineWidthMultipliers[index])
                        ZStack(alignment: settings.lyricsAlignment.textAlignment) {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(
                                    LinearGradient(
                                        colors: [
                                            .white.opacity(isAnimating ? 0.35 : 0.12),
                                            .white.opacity(isAnimating ? 0.15 : 0.05)
                                        ],
                                        startPoint: isAnimating ? .topLeading : .bottomTrailing,
                                        endPoint: isAnimating ? .bottomTrailing : .topLeading
                                    )
                                )
                                .frame(width: width, height: max(16, settings.lyricsFontSize + 4))
                                .shadow(color: .white.opacity(isAnimating ? 0.15 : 0), radius: 6, x: 0, y: 0)
                        }
                        .frame(maxWidth: .infinity, alignment: settings.lyricsAlignment.textAlignment)
                    }
                    .frame(height: max(16, settings.lyricsFontSize + 4))
                    .padding(.horizontal, 24)
                }

                Spacer().frame(height: 24)
            }
            .padding(.vertical, 8)
        }
        .scrollDisabled(true)
        .onAppear {
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                isAnimating = true
            }
        }
    }
}

private extension Alignment {
    var horizontal: HorizontalAlignment {
        switch self {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }
}
