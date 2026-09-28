import SwiftUI
import UIKit

/// `MarkerPin` ve `StreetDot` görünümlerini harita işareti (`MKAnnotationView`) için bitmap'e çevirir. Olası
/// görünüm sayısı az (6 ihtiyaç × 2 tür × durum rozeti × gören sayısı rozeti, artı iki nokta) olduğundan her
/// biri bir kez çizilip önbellekte tutulur.
final class MarkerIconRenderer {
    private var cache: [MarkerIcon: UIImage] = [:]
    private var cacheScale: CGFloat = 0

    @MainActor
    func image(for icon: MarkerIcon, scale: CGFloat) -> UIImage {
        let scale = scale > 0 ? scale : 3
        if scale != cacheScale {
            cache.removeAll()
            cacheScale = scale
        }
        if let cached = cache[icon] {
            return cached
        }
        let image: UIImage
        switch icon {
        case .pin(let style):
            image = render(MarkerPin(style: style), scale: scale)
        case .streetDot(let isSelected):
            image = render(StreetDot(isSelected: isSelected), scale: scale)
        }
        cache[icon] = image
        return image
    }

    @MainActor
    private func render<Content: View>(_ content: Content, scale: CGFloat) -> UIImage {
        let renderer = ImageRenderer(content: content)
        renderer.scale = scale
        return renderer.uiImage ?? UIImage()
    }
}
