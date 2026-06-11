import SwiftUI

/// A slider with an oversized thumb and thick track for users with limited
/// dexterity or vision. The whole row is draggable, not just the thumb.
struct BigThumbSlider: View {
    @Binding var value: Float
    let range: ClosedRange<Float>
    var step: Float = 0.5

    private let thumbSize: CGFloat = 60
    private let trackHeight: CGFloat = 16

    var body: some View {
        GeometryReader { geo in
            let travel = geo.size.width - thumbSize
            let fraction = CGFloat((value - range.lowerBound) / (range.upperBound - range.lowerBound))
            let thumbX = fraction * travel

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(.systemGray4))
                    .frame(height: trackHeight)
                Capsule()
                    .fill(.blue)
                    .frame(width: thumbX + thumbSize / 2, height: trackHeight)
                Circle()
                    .fill(.white)
                    .overlay(Circle().strokeBorder(Color(.systemGray3), lineWidth: 1))
                    .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
                    .frame(width: thumbSize, height: thumbSize)
                    .offset(x: thumbX)
            }
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        let f = min(max((gesture.location.x - thumbSize / 2) / travel, 0), 1)
                        let raw = range.lowerBound + Float(f) * (range.upperBound - range.lowerBound)
                        value = (raw / step).rounded() * step
                    }
            )
        }
        .frame(height: 72)
        .accessibilityElement()
        .accessibilityLabel("Volume")
        .accessibilityValue(String(format: "%.1f decibels", value))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + step * 2, range.upperBound)
            case .decrement: value = max(value - step * 2, range.lowerBound)
            @unknown default: break
            }
        }
    }
}
