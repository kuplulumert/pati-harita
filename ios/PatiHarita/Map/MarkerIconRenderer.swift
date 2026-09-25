import SwiftUI
import UIKit

/// `MarkerPin` görünümünü harita işareti (`MKAnnotationView`) için bitmap'e çevirir. Olası görünüm sayısı az
/// (7 ihtiyaç × 4 tür × durum × gören sayısı rozeti) olduğundan her biri bir kez çizilip önbellekte tutulur.
final class MarkerIconRenderer {
    private var cache: [MarkerStyle: UIImage] = [:]
    private var cacheScale: CGFloat = 0

    @MainActor
    func image(for style: MarkerStyle, scale: CGFloat) -> UIImage {
        let scale = scale > 0 ? scale : 3
        if scale != cacheScale {
            cache.removeAll()
            cacheScale = scale
        }
        if let cached = cache[style] {
            return cached
        }
        let renderer = ImageRenderer(content: MarkerPin(style: style))
        renderer.scale = scale
        let image = renderer.uiImage ?? UIImage()
        cache[style] = image
        return image
    }
}
