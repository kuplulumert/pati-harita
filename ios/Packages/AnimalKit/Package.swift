// swift-tools-version: 5.9
import PackageDescription

// AnimalKit: uygulamanın saf alan mantığı (model, durum makinesi, geohash, biçimlendirme).
// Firebase'e ve haritaya bağımlı değildir; Mac'te `swift test` ile tek başına test edilir.
let package = Package(
    name: "AnimalKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AnimalKit", targets: ["AnimalKit"]),
    ],
    targets: [
        .target(name: "AnimalKit"),
        .testTarget(name: "AnimalKitTests", dependencies: ["AnimalKit"]),
    ]
)
