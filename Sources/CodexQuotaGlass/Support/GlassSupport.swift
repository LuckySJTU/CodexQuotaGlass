import SwiftUI

extension View {
  @ViewBuilder
  func quotaGlass(cornerRadius: CGFloat = 18, interactive: Bool = false) -> some View {
    let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)

    if #available(macOS 26.0, *) {
      if interactive {
        self.glassEffect(.regular.interactive(), in: shape)
      } else {
        self.glassEffect(.regular, in: shape)
      }
    } else {
      self
        .background(.regularMaterial, in: shape)
        .overlay {
          shape.stroke(.quaternary, lineWidth: 1)
        }
    }
  }
}
