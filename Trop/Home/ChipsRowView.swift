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
        FilterChipBar(
            items: chips,
            id: \.title,
            title: \.title,
            isSelected: { selectedChip?.title == $0.title },
            onTap: onChipTap
        )
    }
}
