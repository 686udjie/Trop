//
//  ShimmerLoadingView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct ShimmerLoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ForEach(0..<3, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color(.systemGray5))
                        .frame(width: 140, height: 16)

                    HStack(spacing: 12) {
                        ForEach(0..<4, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(.systemGray6))
                                .frame(width: 140, height: 140)
                        }
                    }
                }
                .padding(.horizontal, 16)
            }
        }
        .padding(.top, 16)
    }
}
