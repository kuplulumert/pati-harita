import XCTest
@testable import AnimalKit

/// Alan ızgarasının dosya biçimi ve araması, testte kurulan 3 × 5'lik küçük bir ızgarayla.
final class AreaGridTests: XCTestCase {
    private let south = 35.75
    private let west = 25.5
    /// 3 satır × 5 sütun, satır satır ve güneyden başlayarak; komşu hücreler farklı.
    private let cells: [AreaClass] = [
        .allowed, .water, .forest, .remote, .allowed,
        .forest, .remote, .allowed, .water, .water,
        .remote, .forest, .water, .allowed, .forest,
    ]

    private func littleEndian<T: FixedWidthInteger>(_ value: T) -> [UInt8] {
        (0..<(T.bitWidth / 8)).map { UInt8(truncatingIfNeeded: value >> ($0 * 8)) }
    }

    private func header(
        magic: String = "PHAG",
        version: UInt8 = 1,
        cellsPerDegree: UInt8 = 240,
        rows: UInt16 = 3,
        cols: UInt16 = 5,
        south: Int32 = 35_750_000,
        west: Int32 = 25_500_000,
        dataVersion: UInt32 = 20_261_001
    ) -> [UInt8] {
        var bytes = Array(magic.utf8)
        bytes.append(version)
        bytes.append(cellsPerDegree)
        bytes += littleEndian(rows)
        bytes += littleEndian(cols)
        bytes += littleEndian(UInt16(0))
        bytes += littleEndian(south)
        bytes += littleEndian(west)
        bytes += littleEndian(dataVersion)
        return bytes
    }

    /// Bir baytta dört hücre, hücre i `2 * (i % 4)` bitinden başlar.
    private func payload(_ cells: [AreaClass]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: (cells.count + 3) / 4)
        for (index, cell) in cells.enumerated() {
            bytes[index / 4] |= cell.rawValue << ((index % 4) * 2)
        }
        return bytes
    }

    private func makeGrid() throws -> AreaGrid {
        try XCTUnwrap(AreaGrid(data: Data(header() + payload(cells))))
    }

    /// Hücrenin ortası.
    private func centre(row: Int, col: Int) -> Coordinate {
        Coordinate(latitude: south + (Double(row) + 0.5) / 240, longitude: west + (Double(col) + 0.5) / 240)
    }

    // MARK: Başlık

    func testHeaderParses() throws {
        let grid = try makeGrid()
        XCTAssertEqual(grid.rows, 3)
        XCTAssertEqual(grid.cols, 5)
        XCTAssertEqual(grid.south, 35.75)
        XCTAssertEqual(grid.west, 25.5)
        XCTAssertEqual(grid.north, 35.7625, accuracy: 1e-12)
        XCTAssertEqual(grid.east, 25.5 + 5.0 / 240, accuracy: 1e-12)
        XCTAssertEqual(grid.dataVersionNumber, 20_261_001)
        XCTAssertEqual(grid.dataVersion, "2026-10-01")
        XCTAssertEqual(AreaGrid.headerSize, 24)
        XCTAssertEqual(AreaGrid.cellsPerDegree, 240)
    }

    func testDataVersionFormat() throws {
        let grid = try XCTUnwrap(AreaGrid(data: Data(header(dataVersion: 20_270_105) + payload(cells))))
        XCTAssertEqual(grid.dataVersion, "2027-01-05")
    }

    func testRejectsBadHeader() {
        let body = payload(cells)
        XCTAssertNotNil(AreaGrid(data: Data(header() + body)))
        XCTAssertNil(AreaGrid(data: Data(header(magic: "PHAX") + body)))
        XCTAssertNil(AreaGrid(data: Data(header(version: 2) + body)))
        XCTAssertNil(AreaGrid(data: Data(header(version: 0) + body)))
        XCTAssertNil(AreaGrid(data: Data(header(cellsPerDegree: 120) + body)))
        XCTAssertNil(AreaGrid(data: Data(header(rows: 0, cols: 0))))
        // Kutu dünyanın dışına taşıyor.
        XCTAssertNil(AreaGrid(data: Data(header(south: 89_995_000) + body)))
    }

    func testRejectsWrongSize() {
        let full = header() + payload(cells)
        XCTAssertNil(AreaGrid(data: Data()))
        XCTAssertNil(AreaGrid(data: Data(header())))
        XCTAssertNil(AreaGrid(data: Data(full.dropLast())))
        XCTAssertNil(AreaGrid(data: Data(full + [0])))
        // Başlık başka boyut söylüyor.
        XCTAssertNil(AreaGrid(data: Data(header(rows: 4) + payload(cells))))
        XCTAssertNil(AreaGrid(data: Data(Array(full.prefix(23)))))
    }

    func testProductionSizeIsExact() {
        // 1560 × 4680 hücre, baytta dört: 24 + 1 825 200 = 1 825 224 bayt.
        XCTAssertEqual(AreaGrid.headerSize + (1560 * 4680 + 3) / 4, 1_825_224)
    }

    // MARK: Arama

    func testBitOrder() throws {
        // 1 × 5: ilk bayt 0b00_11_10_01 → hücre 0 allowed (01), 1 water (10), 2 forest (11), 3 remote (00);
        // ikinci baytın en düşük iki biti hücre 4 (10: water), kalan bitler kullanılmaz.
        let data = Data(header(rows: 1, cols: 5) + [0b00_11_10_01, 0b1111_11_10])
        let grid = try XCTUnwrap(AreaGrid(data: data))
        let expected: [AreaClass] = [.allowed, .water, .forest, .remote, .water]
        for (col, cell) in expected.enumerated() {
            XCTAssertEqual(grid.areaClass(at: centre(row: 0, col: col)), cell, "sütun \(col)")
        }
    }

    func testCellCentres() throws {
        let grid = try makeGrid()
        for row in 0..<3 {
            for col in 0..<5 {
                XCTAssertEqual(grid.areaClass(at: centre(row: row, col: col)), cells[row * 5 + col], "\(row), \(col)")
            }
        }
    }

    func testRowZeroIsSouthernmost() throws {
        let grid = try makeGrid()
        let tiny = 1e-7
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: south + tiny, longitude: west + tiny)), .allowed)
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: grid.north - tiny, longitude: west + tiny)), .remote)
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: south + tiny, longitude: grid.east - tiny)), .allowed)
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: grid.north - tiny, longitude: grid.east - tiny)), .forest)
    }

    func testSouthAndWestEdgesAreInsideNorthAndEastOutside() throws {
        let grid = try makeGrid()
        let north = 35.7625
        let east = 25.5 + 5.0 / 240
        let midLat = south + 1.5 / 240
        let midLon = west + 2.5 / 240
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: south, longitude: west)), .allowed)
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: south, longitude: midLon)), .forest)
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: midLat, longitude: west)), .forest)
        XCTAssertNil(grid.areaClass(at: Coordinate(latitude: north, longitude: midLon)))
        XCTAssertNil(grid.areaClass(at: Coordinate(latitude: midLat, longitude: east)))
        XCTAssertNil(grid.areaClass(at: Coordinate(latitude: south - 1e-9, longitude: midLon)))
        XCTAssertNil(grid.areaClass(at: Coordinate(latitude: midLat, longitude: west - 1e-9)))
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: north - 1e-9, longitude: midLon)), .water)
        XCTAssertEqual(grid.areaClass(at: Coordinate(latitude: midLat, longitude: east - 1e-9)), .water)
    }

    func testInvalidAndFarAwayPointsAreUnknown() throws {
        let grid = try makeGrid()
        let points = [
            Coordinate(latitude: .nan, longitude: west),
            Coordinate(latitude: south, longitude: .nan),
            Coordinate(latitude: .infinity, longitude: west),
            Coordinate(latitude: south, longitude: -.infinity),
            Coordinate(latitude: 0, longitude: 0),
            Coordinate(latitude: 41, longitude: 50),
            Coordinate(latitude: 1e300, longitude: 1e300),
            Coordinate(latitude: -1e300, longitude: -1e300),
        ]
        for point in points {
            XCTAssertNil(grid.areaClass(at: point), "\(point)")
        }
    }

    func testDataSliceWithOffsetStartIndex() throws {
        // Data dilimlerinde ilk indis 0 değildir.
        let padded = Data([9, 9, 9] + header() + payload(cells))
        let slice = padded.dropFirst(3)
        XCTAssertEqual(slice.startIndex, 3)
        let grid = try XCTUnwrap(AreaGrid(data: slice))
        XCTAssertEqual(grid.areaClass(at: centre(row: 2, col: 4)), .forest)
        XCTAssertEqual(grid.areaClass(at: centre(row: 0, col: 1)), .water)
    }

    func testReadsFromFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("area-grid-test-\(UUID().uuidString).bin")
        try Data(header() + payload(cells)).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let grid = try XCTUnwrap(AreaGrid(contentsOf: url))
        XCTAssertEqual(grid.areaClass(at: centre(row: 1, col: 3)), .water)
        XCTAssertNil(AreaGrid(contentsOf: url.appendingPathExtension("yok")))
    }

    func testGateUsesPinArea() throws {
        let grid = try makeGrid()
        let pin = centre(row: 1, col: 3)
        let now = Date(timeIntervalSince1970: 1_790_000_000)
        let fix = LocationFix(coordinate: pin.offset(north: 40), timestamp: now, horizontalAccuracy: 5)
        let verdict = PlacementGate.verdict(
            pin: pin,
            fix: fix,
            access: .full,
            rejectsSimulated: true,
            area: grid.areaClass(at: pin),
            locatingSince: now,
            at: now
        )
        XCTAssertEqual(verdict, .water)
    }

    // MARK: Sınıflar

    func testAreaClassNames() {
        XCTAssertEqual(AreaClass.allCases.map(\.rawValue), [0, 1, 2, 3])
        XCTAssertEqual(AreaClass.allCases.map(\.name), ["remote", "allowed", "water", "forest"])
        for area in AreaClass.allCases {
            XCTAssertEqual(AreaClass(name: area.name), area)
        }
        XCTAssertNil(AreaClass(name: "sea"))
        XCTAssertNil(AreaClass(name: "Forest"))
    }

    func testFixedClassifier() {
        let forest: any AreaClassifying = FixedAreaClassifier(.forest)
        XCTAssertEqual(forest.areaClass(at: centre(row: 0, col: 0)), .forest)
        XCTAssertEqual(forest.areaClass(at: Coordinate(latitude: 0, longitude: 0)), .forest)
        XCTAssertNil(forest.dataVersion)
        let unknown: any AreaClassifying = FixedAreaClassifier(nil)
        XCTAssertNil(unknown.areaClass(at: centre(row: 0, col: 0)))
        XCTAssertEqual(FixedAreaClassifier(.allowed, dataVersion: "2026-10-01").dataVersion, "2026-10-01")
    }
}
