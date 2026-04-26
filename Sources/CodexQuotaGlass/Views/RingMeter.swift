import SwiftUI

struct RingMeter: View {
  var value: Double
  var lineWidth: CGFloat = 8

  var body: some View {
    ZStack {
      Circle()
        .stroke(.quaternary, lineWidth: lineWidth)

      Circle()
        .trim(from: 0, to: min(1, max(0, value)))
        .stroke(
          AngularGradient(
            colors: [.green, .cyan, .blue, .green],
            center: .center
          ),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
        .rotationEffect(.degrees(-90))
        .animation(.snappy(duration: 0.35), value: value)
    }
  }
}
