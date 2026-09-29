import XCTest
@testable import AnimalKit

/// shared/area-tr.bin'in shared/area-golden.json'daki bilinen yerleri doğru sınıflandırdığını doğrular
/// (tools/area-grid'in yazmadan önce denetlediği noktaların aynısı). Izgara henüz üretilmediyse atlanır.
final class AreaGridGoldenTests: XCTestCase {
    private struct GoldenPoint: Decodable {
        let name: String
        let lat: Double
        let lon: Double
        /// Kabul edilen sınıflar (`AreaClass.name`), ör. ["forest", "remote"].
        let expect: [String]
    }

    private func sharedGrid() throws -> AreaGrid {
        let url = SharedFixtures.sharedDirectory.appendingPathComponent("area-tr.bin")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw XCTSkip("shared/area-tr.bin yok: tools/area-grid ile üretilince bu test çalışır.")
        }
        return try XCTUnwrap(AreaGrid(contentsOf: url), "shared/area-tr.bin bozuk: başlık ya da boyut tutmuyor.")
    }

    func testGridCoversTurkeyBox() throws {
        let grid = try sharedGrid()
        XCTAssertEqual(grid.rows, 1560)
        XCTAssertEqual(grid.cols, 4680)
        XCTAssertEqual(grid.south, 35.75)
        XCTAssertEqual(grid.west, 25.5)
        XCTAssertEqual(grid.north, 42.25, accuracy: 1e-9)
        XCTAssertEqual(grid.east, 45, accuracy: 1e-9)
        XCTAssertGreaterThanOrEqual(grid.dataVersionNumber, 20_260_101)
    }

    func testGoldenPointsMatch() throws {
        let grid = try sharedGrid()
        let points = try SharedFixtures.load("area-golden.json", as: [GoldenPoint].self)
        XCTAssertFalse(points.isEmpty)
        for point in points {
            let expected = point.expect.compactMap { AreaClass(name: $0) }
            XCTAssertFalse(expected.isEmpty, "\(point.name): sınıf yok")
            XCTAssertEqual(expected.count, point.expect.count, "\(point.name): tanınmayan sınıf \(point.expect)")
            let found = grid.areaClass(at: Coordinate(latitude: point.lat, longitude: point.lon))
            let matches = found.map { expected.contains($0) } ?? false
            XCTAssertTrue(
                matches,
                "\(point.name) (\(point.lat), \(point.lon)): beklenen \(point.expect), bulunan \(found?.name ?? "kutunun dışı")"
            )
        }
    }
}
