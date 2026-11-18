import AppKit
import SwiftUI
import TobarsCore

/// 供应商官方图标。不做白底、不加内边距，统一裁成同样的圆角方形，
/// 避免每家图标外面多出一圈不同宽度的白边。
struct ProviderLogo: View {
    let provider: ProviderID
    var size: CGFloat = 26

    private var assetName: String {
        switch provider {
        case .openCodeGo: return "opencode-go"
        case .commandCode: return "command-code"
        case .openDesign: return "open-design"
        }
    }

    private var image: NSImage? {
        guard let url = Bundle.module.url(forResource: assetName, withExtension: "png") else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
    }

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                Text(provider.shortName)
                    .font(.system(size: size * 0.35, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color.primary.opacity(0.08))
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .help(provider.displayName)
    }
}
