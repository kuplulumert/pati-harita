import AnimalKit
import CoreLocation
import GoogleMaps
import SwiftUI

/// Kameranın gitmesi istenen konum. Her istek yeni bir `id` taşır; aynı istek iki kez uygulanmaz.
struct CameraRequest: Equatable {
    let id = UUID()
    let target: Coordinate
    var zoom: Float?
}

/// Google Maps SDK'nın `GMSMapView`'ını SwiftUI'a bağlar ve işaretleri senkronize eder.
struct GoogleMapView: UIViewRepresentable {
    static let defaultCenter = Coordinate(latitude: 41.0082, longitude: 28.9784) // İstanbul

    let reports: [Report]
    let selectedID: String?
    let userID: String?
    let now: Date
    let cameraRequest: CameraRequest?
    /// Haritanın üst/alt arayüzün altında kalan kısmı. Kamera hedefi (ve yeni işaret iğnesi)
    /// her zaman kalan görünür alanın ortasındadır; Google logosu da bu alanda kalır.
    let insets: UIEdgeInsets

    var onCameraWillMove: @MainActor () -> Void = {}
    var onCameraMove: @MainActor (Coordinate) -> Void = { _ in }
    var onCameraIdle: @MainActor (_ center: Coordinate, _ visibleRadius: Double) -> Void = { _, _ in }
    var onMarkerTap: @MainActor (_ reportID: String) -> Void = { _ in }
    var onMapTap: @MainActor () -> Void = {}
    var onLongPress: @MainActor (Coordinate) -> Void = { _ in }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> GMSMapView {
        let options = GMSMapViewOptions()
        options.camera = GMSCameraPosition(
            latitude: Self.defaultCenter.latitude,
            longitude: Self.defaultCenter.longitude,
            zoom: 13
        )
        let mapView = GMSMapView(options: options)
        mapView.delegate = context.coordinator
        mapView.isMyLocationEnabled = true
        mapView.settings.myLocationButton = false
        mapView.settings.rotateGestures = false
        mapView.settings.tiltGestures = false
        mapView.settings.compassButton = false
        mapView.paddingAdjustmentBehavior = .never
        mapView.mapStyle = try? GMSMapStyle(jsonString: MapStyle.json)
        return mapView
    }

    func updateUIView(_ mapView: GMSMapView, context: Context) {
        let coordinator = context.coordinator
        coordinator.parent = self

        if mapView.padding != insets {
            UIView.animate(withDuration: 0.25) {
                mapView.padding = insets
            }
        }

        coordinator.syncMarkers(on: mapView)

        if let request = cameraRequest, request.id != coordinator.appliedCameraRequestID {
            coordinator.appliedCameraRequestID = request.id
            let target = CLLocationCoordinate2D(latitude: request.target.latitude, longitude: request.target.longitude)
            mapView.animate(with: GMSCameraUpdate.setTarget(target, zoom: request.zoom ?? mapView.camera.zoom))
        }
    }

    @MainActor
    final class Coordinator: NSObject, GMSMapViewDelegate {
        var parent: GoogleMapView?
        var appliedCameraRequestID: UUID?
        private var markers: [String: GMSMarker] = [:]
        private var markerStyles: [String: MarkerStyle] = [:]
        private var renderedScale: CGFloat = 0
        private let icons = MarkerIconRenderer()

        func syncMarkers(on mapView: GMSMapView) {
            guard let parent else { return }
            let scale = mapView.traitCollection.displayScale
            if scale != renderedScale {
                // Ekran ölçeği ilk çizimden sonra belli olabilir; tüm ikonları yeniden çiz.
                markerStyles.removeAll()
                renderedScale = scale
            }
            var visibleIDs = Set<String>()

            for report in parent.reports {
                visibleIDs.insert(report.id)
                let isSelected = report.id == parent.selectedID
                let style = MarkerStyle(
                    need: report.need,
                    species: report.species,
                    isBeingHelped: report.phase(for: parent.userID, at: parent.now).isBeingHelped,
                    isSelected: isSelected
                )

                let marker = markers[report.id] ?? makeMarker(for: report, on: mapView)
                if markerStyles[report.id] != style {
                    marker.icon = icons.image(for: style, scale: scale)
                    markerStyles[report.id] = style
                }
                // Eski işaretler soluklaşır: hâlâ geçerli mi bilinmiyor.
                marker.opacity = Float(0.5 + 0.5 * report.freshness(at: parent.now))
                marker.zIndex = Int32(report.need.priority + (isSelected ? 100 : 0))
            }

            for (id, marker) in markers where !visibleIDs.contains(id) {
                marker.map = nil
                markers[id] = nil
                markerStyles[id] = nil
            }
        }

        private func makeMarker(for report: Report, on mapView: GMSMapView) -> GMSMarker {
            let marker = GMSMarker(
                position: CLLocationCoordinate2D(latitude: report.coordinate.latitude, longitude: report.coordinate.longitude)
            )
            marker.groundAnchor = CGPoint(x: 0.5, y: 1)
            marker.appearAnimation = .pop
            marker.userData = report.id
            marker.map = mapView
            markers[report.id] = marker
            return marker
        }

        // MARK: GMSMapViewDelegate — SDK bu çağrıları ana iş parçacığında yapar.

        nonisolated func mapView(_ mapView: GMSMapView, willMove gesture: Bool) {
            MainActor.assumeIsolated {
                guard gesture, let parent else { return }
                parent.onCameraWillMove()
            }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didChange position: GMSCameraPosition) {
            MainActor.assumeIsolated {
                guard let parent else { return }
                parent.onCameraMove(Coordinate(position.target))
            }
        }

        nonisolated func mapView(_ mapView: GMSMapView, idleAt position: GMSCameraPosition) {
            MainActor.assumeIsolated {
                let region = mapView.projection.visibleRegion()
                let radius = [region.farLeft, region.farRight, region.nearLeft, region.nearRight]
                    .map { GMSGeometryDistance(position.target, $0) }
                    .max() ?? 0
                guard let parent else { return }
                parent.onCameraIdle(Coordinate(position.target), radius)
            }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didTap marker: GMSMarker) -> Bool {
            MainActor.assumeIsolated {
                guard let parent, let reportID = marker.userData as? String else { return false }
                parent.onMarkerTap(reportID)
                return true
            }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didTapAt coordinate: CLLocationCoordinate2D) {
            MainActor.assumeIsolated {
                guard let parent else { return }
                parent.onMapTap()
            }
        }

        nonisolated func mapView(_ mapView: GMSMapView, didLongPressAt coordinate: CLLocationCoordinate2D) {
            MainActor.assumeIsolated {
                guard let parent else { return }
                parent.onLongPress(Coordinate(coordinate))
            }
        }
    }
}

extension Coordinate {
    init(_ coordinate: CLLocationCoordinate2D) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
