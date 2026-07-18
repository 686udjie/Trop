//
//  PlayerComponents.swift
//  Trop
//
//  Created by 686udjie on 13/07/2026.
//

import SwiftUI
import AVKit

// MARK: - ProgressBar
struct ProgressBar: View {
    @Binding var progress: Float
    let accentColor: Color
    let isPlaying: Bool
    let onEditingChanged: (Bool) -> Void
    
    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let elapsedWidth = max(0, min(width, width * CGFloat(progress)))
            
            ZStack(alignment: .leading) {
                // Remaining track (unwatched)
                Capsule()
                    .fill(.white.opacity(0.15))
                    .frame(height: 6)
                
                // Elapsed track (watched, marked)
                Capsule()
                    .fill(.white.opacity(0.8))
                    .frame(width: elapsedWidth, height: 6)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onEditingChanged(true)
                        let loc = value.location.x
                        let percent = max(0, min(1, loc / width))
                        progress = Float(percent)
                    }
                    .onEnded { value in
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 12)
    }
}

// MARK: - PlaybackControlsRow
struct PlaybackControlsRow: View {
    let isPlaying: Bool
    let hasPrevious: Bool
    let hasNext: Bool
    
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    
    var body: some View {
        HStack(spacing: 0) {
            Button(action: onPrevious) {
                Image(systemName: "backward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(!hasPrevious)
            .opacity(hasPrevious ? 1 : 0.3)
            .frame(maxWidth: .infinity)
            
            Button(action: onPlayPause) {
                Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 42))
                    .foregroundStyle(.white)
                    .contentTransition(.symbolEffect(.replace))
            }
            .frame(width: 80, height: 80)
            .frame(maxWidth: .infinity)
            
            Button(action: onNext) {
                Image(systemName: "forward.fill")
                    .font(.title)
                    .foregroundStyle(.white)
            }
            .disabled(!hasNext)
            .opacity(hasNext ? 1 : 0.3)
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - SecondaryActionsRow
struct SecondaryActionsRow: View {
    @Binding var showLyrics: Bool
    @Binding var showQueue: Bool
    @Binding var isRepeatOn: Bool
    let onRepeat: () -> Void
    @State private var lyricsState = LyricsState.shared

    var body: some View {
        HStack(spacing: 0) {

            Button {
                showLyrics.toggle()
            } label: {
                Image(systemName: "quote.bubble")
                    .font(.title3)
                    .foregroundStyle(showLyrics ? .white : .white.opacity(0.7))
                    .padding(10)
                    .background(showLyrics ? Circle().fill(.white.opacity(0.15)) : Circle().fill(.clear))
            }
            .disabled(!lyricsState.isAvailable)
            .opacity(lyricsState.isAvailable ? 1 : 0.3)
            .frame(maxWidth: .infinity)
            
            Button {
                // airplay, handled by overlay
            } label: {
                Image(systemName: "airplayaudio")
                    .font(.title3)
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(10)
            }
            .frame(maxWidth: .infinity)
            .overlay(AirPlayButton())
            
            // Queue + Repeat stacked like Apple Music
            ZStack(alignment: .topTrailing) {
                Button {
                    showQueue.toggle()
                } label: {
                    Image(systemName: "list.bullet")
                        .font(.title3)
                        .foregroundStyle(showQueue ? .white : .white.opacity(0.7))
                        .padding(10)
                        .background(showQueue ? Circle().fill(.white.opacity(0.15)) : Circle().fill(.clear))
                }
                
                if !showQueue {
                    Button {
                        isRepeatOn.toggle()
                        onRepeat()
                    } label: {
                        Image(systemName: isRepeatOn ? "repeat.1" : "repeat")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(isRepeatOn ? .white : .white.opacity(0.7))
                            .padding(4)
                    }
                    .offset(x: 2, y: -2)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.vertical, 16)
    }
}

// MARK: - AirPlayButton
struct AirPlayButton: UIViewRepresentable {
    func makeUIView(context: UIViewRepresentableContext<Self>) -> AVRoutePickerView {
        let picker = AVRoutePickerView()
        picker.tintColor = UIColor.clear
        picker.activeTintColor = UIColor.clear
        picker.prioritizesVideoDevices = false
        return picker
    }

    func updateUIView(_ uiView: AVRoutePickerView, context: UIViewRepresentableContext<Self>) {}
}
