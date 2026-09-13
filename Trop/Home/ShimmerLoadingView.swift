//
//  ShimmerLoadingView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

// MARK: - Shimmer fill

struct ShimmerFill: View {
    var radius: CGFloat = 8

    private let phases: [CGFloat] = [-1, 1]

    var body: some View {
        Color(.systemGray5)
            .overlay(
                GeometryReader { geo in
                    let w = geo.size.width
                    let h = geo.size.height
                    PhaseAnimator(phases) { phase in
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .white.opacity(0.5), location: 0.5),
                                .init(color: .clear, location: 1)
                            ],
                            startPoint: .leading,
                            endPoint: .trailing
                        )
                        .frame(width: w * 2, height: h)
                        .offset(x: phase * w)
                        .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: phase)
                    }
                }
            )
            .clipShape(RoundedRectangle(cornerRadius: radius))
    }
}

// MARK: - Placeholder primitive

struct ShimmerBlock: View {
    var width: CGFloat
    var height: CGFloat
    var radius: CGFloat = 8

    var body: some View {
        ShimmerFill(radius: radius)
            .frame(width: width, height: height)
    }
}

// MARK: - Shared skeleton primitives

/// Section title placeholder with standard section padding.
struct ShimmerSectionTitle: View {
    var width: CGFloat = 160

    var body: some View {
        ShimmerBlock(width: width, height: 22, radius: 6)
            .padding(.horizontal, DesignTokens.screenHPadding)
            .padding(.vertical, 8)
    }
}

/// Media card placeholder: square artwork + title + optional subtitle line.
struct ShimmerCard: View {
    var size: CGFloat = 160
    var titleWidth: CGFloat = 130
    var subtitleWidth: CGFloat = 90
    var showsSubtitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: DesignTokens.cardInnerSpacing) {
            ShimmerBlock(width: size, height: size, radius: DesignTokens.cardRadius)
            ShimmerBlock(width: titleWidth, height: 14, radius: 4)
            if showsSubtitle {
                ShimmerBlock(width: subtitleWidth, height: 12, radius: 4)
            }
        }
    }
}

/// Song row placeholder: 48pt artwork + two text lines.
struct ShimmerRow: View {
    var titleWidth: CGFloat = 180
    var subtitleWidth: CGFloat = 120

    var body: some View {
        HStack(spacing: DesignTokens.rowSpacing) {
            ShimmerBlock(width: DesignTokens.thumbMedium, height: DesignTokens.thumbMedium, radius: DesignTokens.thumbRadius)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerBlock(width: titleWidth, height: 14, radius: 4)
                ShimmerBlock(width: subtitleWidth, height: 12, radius: 4)
            }
            Spacer()
        }
    }
}

/// Filter chip placeholders in a horizontal scroll row.
struct ShimmerChips: View {
    var count = 6
    var width: CGFloat = 80

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<count, id: \.self) { _ in
                    ShimmerBlock(width: width, height: 34, radius: 17)
                }
            }
            .padding(.horizontal, DesignTokens.screenHPadding)
            .padding(.vertical, 8)
        }
    }
}

// MARK: - ShimmerLoadingView

struct ShimmerLoadingView: View {
    private enum Section: Hashable { case list, squares }
    private let sections: [Section] = [.list, .squares, .squares, .squares]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                chipsRow
                ForEach(sections, id: \.self) { section in
                    switch section {
                    case .list: listSection
                    case .squares: squaresSection
                    }
                }
            }
        }
        .scrollIndicators(.hidden)
    }

    private func section<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ShimmerSectionTitle()
            content()
        }
        .padding(.top, 8)
    }

    private var squaresSection: some View {
        section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in ShimmerCard(showsSubtitle: false) }
                }
                .padding(.horizontal, DesignTokens.screenHPadding)
            }
        }
    }

    private var listSection: some View {
        section {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in
                    ShimmerRow(titleWidth: 200, subtitleWidth: 140)
                }
            }
            .padding(.horizontal, DesignTokens.screenHPadding)
        }
    }

    private var chipsRow: some View {
        ShimmerChips()
    }
}
