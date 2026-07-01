//
//  ChipsRowView.swift
//  Trop
//
//  Created by 686udjie on 01/07/2026.
//

import SwiftUI

struct ChipsRowView: View {
    var chips: [HomePage.Chip]
    var selectedChip: HomePage.Chip?
    var onChipTap: (HomePage.Chip) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(chips, id: \.title) { chip in
                    Button(
                        action: { onChipTap(chip) },
                        label: {
                            Text(chip.title)
                                .font(.subheadline)
                                .fontWeight(.medium)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    Capsule()
                                        .fill(selectedChip?.title == chip.title
                                            ? Color.accentColor
                                            : Color(.systemGray5))
                                )
                                .foregroundColor(selectedChip?.title == chip.title
                                    ? .white
                                    : .primary)
                        }
                    )
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
    }
}
