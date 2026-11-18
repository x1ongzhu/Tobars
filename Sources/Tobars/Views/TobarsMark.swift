import SwiftUI

/// Tobars 的三根柱状标记。菜单栏用单色，标题与图标用彩色。
/// 用 Canvas 而不是 GeometryReader：MenuBarExtra 的 label 不会给 GeometryReader
/// 提议尺寸，后者会缩成 0，导致菜单栏里看不到图标。
struct TobarsMark: View {
    var colored = false

    private let palette: [Color] = [.teal, .green, .mint]
    private let ratios: [CGFloat] = [0.46, 0.68, 1.0]

    var body: some View {
        Canvas { context, size in
            let gap = size.width * 0.14
            let barWidth = (size.width - gap * 2) / 3
            for index in 0..<3 {
                let height = size.height * ratios[index]
                let rect = CGRect(
                    x: CGFloat(index) * (barWidth + gap),
                    y: size.height - height,
                    width: barWidth,
                    height: height
                )
                let path = Path(roundedRect: rect, cornerRadius: barWidth / 2)
                context.fill(path, with: .color(colored ? palette[index] : .primary))
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

struct MenuBarLabel: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            TobarsMark()
                .frame(width: 14, height: 14)
            Text(text)
                .monospacedDigit()
        }
    }
}
