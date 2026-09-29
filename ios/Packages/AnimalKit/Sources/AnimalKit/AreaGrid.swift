import Foundation

/// Bir ızgara hücresinin alan sınıfı. Ham değerler dosyadaki 2 bittir.
public enum AreaClass: UInt8, CaseIterable, Sendable {
    /// Yerleşim yeri dışı.
    case remote = 0
    /// İşaret konabilir.
    case allowed = 1
    /// Deniz ya da göl.
    case water = 2
    /// Ormanlık alan.
    case forest = 3

    /// shared/area-golden.json'daki ve `-areaClass` başlatma argümanındaki ad.
    public var name: String {
        switch self {
        case .remote: "remote"
        case .allowed: "allowed"
        case .water: "water"
        case .forest: "forest"
        }
    }

    /// `name`den; tanınmayan adda `nil`.
    public init?(name: String) {
        guard let match = AreaClass.allCases.first(where: { $0.name == name }) else { return nil }
        self = match
    }
}

/// Bir noktanın alan sınıfını veren kaynak. Uygulama ızgarayı ya da sabit bir sınıfı kullanır.
public protocol AreaClassifying: Sendable {
    /// Noktanın alan sınıfı; bilinmiyorsa (kutunun dışı, geçersiz nokta, veri yok) `nil`.
    func areaClass(at coordinate: Coordinate) -> AreaClass?
    /// Verinin sürümü ("2026-10-01"); veri yoksa `nil`.
    var dataVersion: String? { get }
}

/// Uygulamayla gelen, internetsiz ve her yerde aynı sonucu veren 2 bitlik alan ızgarası
/// (shared/area-tr.bin, tools/area-grid ile üretilir). Arama O(1)'dir ve bellek ayırmaz.
///
/// Dosya: 24 baytlık başlık (little-endian) ve satır satır hücreler.
///
///     0  "PHAG"             4 × ASCII
///     4  formatVersion = 1  u8
///     5  cellsPerDegree     u8 (240: 15″)
///     6  rows               u16
///     8  cols               u16
///     10 reserved           u16
///     12 south              i32 (mikroderece)
///     16 west               i32 (mikroderece)
///     20 dataVersion        u32 (YYYYMMDD)
///
/// Satır 0 en güneydekidir. Bir baytta dört hücre: hücre i, `i / 4`. baytın `2 * (i % 4)` bitinden başlar.
public struct AreaGrid: AreaClassifying {
    public static let headerSize = 24
    public static let magic: [UInt8] = Array("PHAG".utf8)
    public static let formatVersion: UInt8 = 1
    /// 15″'lik hücreler: Türkiye'de yaklaşık 464 m (K–G) × 345–375 m (D–B).
    public static let cellsPerDegree = 240

    public let rows: Int
    public let cols: Int
    /// Güney kenarı (derece, dahil).
    public let south: Double
    /// Batı kenarı (derece, dahil).
    public let west: Double
    /// Başlıktaki ham sürüm (YYYYMMDD).
    public let dataVersionNumber: UInt32

    private let data: Data
    /// Güney ve batı kenarı hücre cinsinden (derece × 240). Önce çarpıp sonra çıkarmak kenarlarda
    /// kayan nokta hatasını azaltır.
    private let southCell: Double
    private let westCell: Double

    /// Başlığı ve boyutu doğrular; dosya bozuksa `nil`. Veri kopyalanmaz (`.alwaysMapped` ile okunabilir).
    public init?(data: Data) {
        guard data.count >= AreaGrid.headerSize else { return nil }
        let parsed = data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) -> Header? in
            guard Array(raw[0..<4]) == AreaGrid.magic else { return nil }
            return Header(
                formatVersion: raw[4],
                cellsPerDegree: raw[5],
                rows: UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: 6, as: UInt16.self)),
                cols: UInt16(littleEndian: raw.loadUnaligned(fromByteOffset: 8, as: UInt16.self)),
                southMicro: Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 12, as: Int32.self)),
                westMicro: Int32(littleEndian: raw.loadUnaligned(fromByteOffset: 16, as: Int32.self)),
                dataVersion: UInt32(littleEndian: raw.loadUnaligned(fromByteOffset: 20, as: UInt32.self))
            )
        }
        guard let header = parsed,
              header.formatVersion == AreaGrid.formatVersion,
              Int(header.cellsPerDegree) == AreaGrid.cellsPerDegree,
              header.rows > 0,
              header.cols > 0
        else { return nil }

        let rows = Int(header.rows)
        let cols = Int(header.cols)
        let cpd = Double(AreaGrid.cellsPerDegree)
        let southCell = Double(header.southMicro) * cpd / 1_000_000
        let westCell = Double(header.westMicro) * cpd / 1_000_000
        // Kutu dünyanın içinde olmalı.
        guard southCell >= -90 * cpd, southCell + Double(rows) <= 90 * cpd,
              westCell >= -180 * cpd, westCell + Double(cols) <= 180 * cpd
        else { return nil }
        guard data.count == AreaGrid.headerSize + (rows * cols + 3) / 4 else { return nil }

        self.data = data
        self.rows = rows
        self.cols = cols
        self.southCell = southCell
        self.westCell = westCell
        self.south = Double(header.southMicro) / 1_000_000
        self.west = Double(header.westMicro) / 1_000_000
        self.dataVersionNumber = header.dataVersion
    }

    /// Dosyadan okur; dosya yoksa ya da bozuksa `nil`.
    public init?(contentsOf url: URL) {
        guard let data = try? Data(contentsOf: url, options: .alwaysMapped) else { return nil }
        self.init(data: data)
    }

    /// Kuzey kenarı (derece, hariç).
    public var north: Double { (southCell + Double(rows)) / Double(AreaGrid.cellsPerDegree) }
    /// Doğu kenarı (derece, hariç).
    public var east: Double { (westCell + Double(cols)) / Double(AreaGrid.cellsPerDegree) }

    /// "2026-10-01"
    public var dataVersion: String? {
        let year = dataVersionNumber / 10_000
        let month = dataVersionNumber / 100 % 100
        let day = dataVersionNumber % 100
        return "\(AreaGrid.padded(year, 4))-\(AreaGrid.padded(month, 2))-\(AreaGrid.padded(day, 2))"
    }

    /// Noktanın hücresinin sınıfı. Kutunun dışında ya da geçersiz noktada `nil`; güney ve batı kenarı
    /// dahil, kuzey ve doğu kenarı hariç.
    public func areaClass(at coordinate: Coordinate) -> AreaClass? {
        guard coordinate.latitude.isFinite, coordinate.longitude.isFinite else { return nil }
        let cpd = Double(AreaGrid.cellsPerDegree)
        let row = (coordinate.latitude * cpd - southCell).rounded(.down)
        let col = (coordinate.longitude * cpd - westCell).rounded(.down)
        // Int'e çevirmeden önce denetlenir: çok uzak bir nokta taşmaya yol açmasın.
        guard row >= 0, row < Double(rows), col >= 0, col < Double(cols) else { return nil }
        let index = Int(row) * cols + Int(col)
        let byte = data[data.startIndex + AreaGrid.headerSize + index / 4]
        return AreaClass(rawValue: (byte >> ((index % 4) * 2)) & 0b11)
    }

    private struct Header {
        var formatVersion: UInt8
        var cellsPerDegree: UInt8
        var rows: UInt16
        var cols: UInt16
        var southMicro: Int32
        var westMicro: Int32
        var dataVersion: UInt32
    }

    private static func padded(_ value: UInt32, _ width: Int) -> String {
        let digits = String(value)
        return String(repeating: "0", count: max(0, width - digits.count)) + digits
    }
}

/// Her noktaya aynı sınıfı veren kaynak: arayüz testlerindeki `-areaClass` ve ızgara yokken
/// her yeri serbest bırakan `FixedAreaClassifier(nil)`.
public struct FixedAreaClassifier: AreaClassifying {
    public let value: AreaClass?
    public let dataVersion: String?

    public init(_ value: AreaClass?, dataVersion: String? = nil) {
        self.value = value
        self.dataVersion = dataVersion
    }

    public func areaClass(at coordinate: Coordinate) -> AreaClass? {
        value
    }
}
