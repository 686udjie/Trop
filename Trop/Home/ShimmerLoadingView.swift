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
                    }
                    .animation(.linear(duration: 1.5).repeatForever(autoreverses: false), value: phases)
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
            ShimmerBlock(width: 160, height: 22, radius: 6)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            content()
        }
        .padding(.top, 8)
    }

    private var squaresSection: some View {
        section {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(0..<5, id: \.self) { _ in ShimmerBlock(width: 160, height: 160, radius: 8) }
                }
                .padding(.horizontal, 16)
            }
        }
    }

    private var listSection: some View {
        section {
            VStack(spacing: 12) {
                ForEach(0..<4, id: \.self) { _ in listItemPlaceholder }
            }
            .padding(.horizontal, 16)
        }
    }

    private var listItemPlaceholder: some View {
        HStack(spacing: 12) {
            ShimmerBlock(width: 48, height: 48, radius: 4)
            VStack(alignment: .leading, spacing: 6) {
                ShimmerBlock(width: 200, height: 14, radius: 4)
                ShimmerBlock(width: 140, height: 12, radius: 4)
            }
            Spacer()
        }
        .frame(width: 280, height: 60, alignment: .leading)
    }

    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(0..<6, id: \.self) { _ in ShimmerBlock(width: 80, height: 34, radius: 17) }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
