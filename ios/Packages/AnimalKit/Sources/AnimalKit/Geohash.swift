import Foundation

/// Firestore'da `geohash >= start && geohash < end` sorgusu için aralık.
public struct GeohashRange: Hashable, Sendable {
    public let start: String
    public let end: String

    public init(start: String, end: String) {
        self.start = start
        self.end = end
    }
}

/// Firestore ile konum sorgusu için geohash.
///
/// Firebase'in resmi `geofire-common` kütüphanesinin birebir Swift karşılığıdır;
/// böylece iOS istemcisi ve olası web/sunucu istemcileri aynı sorgu aralıklarını üretir.
/// Doğruluğu shared/geohash-vectors.json üzerinden test edilir.
public enum Geohash {
    static let base32: [Character] = Array("0123456789bcdefghjkmnpqrstuvwxyz")
    static let bitsPerChar = 5
    static let maximumBitsPrecision = 22 * bitsPerChar
    static let earthMeridionalCircumference = 40_007_860.0
    static let metersPerDegreeLatitude = 110_574.0
    static let earthEquatorialRadius = 6_378_137.0
    static let e2 = 0.00669447819799
    static let epsilon = 1e-12

    public static func encode(_ coordinate: Coordinate, precision: Int = 10) -> String {
        var latitudeRange = (min: -90.0, max: 90.0)
        var longitudeRange = (min: -180.0, max: 180.0)
        var hash = ""
        var hashValue = 0
        var bits = 0
        var even = true

        while hash.count < precision {
            let bit: Int
            if even {
                bit = bisect(coordinate.longitude, &longitudeRange)
            } else {
                bit = bisect(coordinate.latitude, &latitudeRange)
            }
            hashValue = (hashValue << 1) + bit
            even.toggle()
            if bits < 4 {
                bits += 1
            } else {
                bits = 0
                hash.append(base32[hashValue])
                hashValue = 0
            }
        }
        return hash
    }

    /// `center` çevresinde `radiusMeters` yarıçaplı alanı kapsayan geohash aralıkları.
    /// Sonuç, alanın biraz dışını da içerebilir; bu harita için sorun değildir.
    public static func queryBounds(center: Coordinate, radiusMeters radius: Double) -> [GeohashRange] {
        let queryBits = max(1, boundingBoxBits(center, radius))
        let precision = Int((Double(queryBits) / Double(bitsPerChar)).rounded(.up))
        let ranges = boundingBoxCoordinates(center, radius).map {
            query(encode($0, precision: precision), bits: queryBits)
        }
        var unique: [GeohashRange] = []
        for range in ranges where !unique.contains(range) {
            unique.append(range)
        }
        return unique
    }

    // MARK: - geofire-common ile birebir yardımcılar

    private static func bisect(_ value: Double, _ range: inout (min: Double, max: Double)) -> Int {
        let mid = (range.min + range.max) / 2
        if value > mid {
            range.min = mid
            return 1
        } else {
            range.max = mid
            return 0
        }
    }

    /// geofire-common'daki `log2` tanımı (Math.log(x) / Math.log(2)); sonuçların bit bit aynı olması için.
    private static func jsLog2(_ x: Double) -> Double {
        log(x) / log(2.0)
    }

    static func metersToLongitudeDegrees(_ distance: Double, latitude: Double) -> Double {
        let radians = latitude * .pi / 180
        let numerator = cos(radians) * earthEquatorialRadius * .pi / 180
        let denominator = 1 / sqrt(1 - e2 * sin(radians) * sin(radians))
        let deltaDegrees = numerator * denominator
        if deltaDegrees < epsilon {
            return distance > 0 ? 360 : 0
        }
        return min(360, distance / deltaDegrees)
    }

    static func longitudeBitsForResolution(_ resolution: Double, latitude: Double) -> Double {
        let degrees = metersToLongitudeDegrees(resolution, latitude: latitude)
        return abs(degrees) > 0.000001 ? max(1, jsLog2(360 / degrees)) : 1
    }

    static func latitudeBitsForResolution(_ resolution: Double) -> Double {
        min(jsLog2(earthMeridionalCircumference / 2 / resolution), Double(maximumBitsPrecision))
    }

    static func wrapLongitude(_ longitude: Double) -> Double {
        if longitude <= 180 && longitude >= -180 {
            return longitude
        }
        let adjusted = longitude + 180
        if adjusted > 0 {
            return adjusted.truncatingRemainder(dividingBy: 360) - 180
        }
        return 180 - (-adjusted).truncatingRemainder(dividingBy: 360)
    }

    static func boundingBoxBits(_ coordinate: Coordinate, _ size: Double) -> Int {
        let latitudeDelta = size / metersPerDegreeLatitude
        let latitudeNorth = min(90, coordinate.latitude + latitudeDelta)
        let latitudeSouth = max(-90, coordinate.latitude - latitudeDelta)
        let bitsLatitude = Int(latitudeBitsForResolution(size).rounded(.down)) * 2
        let bitsLongitudeNorth = Int(longitudeBitsForResolution(size, latitude: latitudeNorth).rounded(.down)) * 2 - 1
        let bitsLongitudeSouth = Int(longitudeBitsForResolution(size, latitude: latitudeSouth).rounded(.down)) * 2 - 1
        return min(bitsLatitude, bitsLongitudeNorth, bitsLongitudeSouth, maximumBitsPrecision)
    }

    static func boundingBoxCoordinates(_ center: Coordinate, _ radius: Double) -> [Coordinate] {
        let latitudeDegrees = radius / metersPerDegreeLatitude
        let north = min(90, center.latitude + latitudeDegrees)
        let south = max(-90, center.latitude - latitudeDegrees)
        let longitudeDegrees = max(
            metersToLongitudeDegrees(radius, latitude: north),
            metersToLongitudeDegrees(radius, latitude: south)
        )
        let west = wrapLongitude(center.longitude - longitudeDegrees)
        let east = wrapLongitude(center.longitude + longitudeDegrees)
        return [
            Coordinate(latitude: center.latitude, longitude: center.longitude),
            Coordinate(latitude: center.latitude, longitude: west),
            Coordinate(latitude: center.latitude, longitude: east),
            Coordinate(latitude: north, longitude: center.longitude),
            Coordinate(latitude: north, longitude: west),
            Coordinate(latitude: north, longitude: east),
            Coordinate(latitude: south, longitude: center.longitude),
            Coordinate(latitude: south, longitude: west),
            Coordinate(latitude: south, longitude: east),
        ]
    }

    static func query(_ geohash: String, bits: Int) -> GeohashRange {
        let precision = Int((Double(bits) / Double(bitsPerChar)).rounded(.up))
        if geohash.count < precision {
            return GeohashRange(start: geohash, end: geohash + "~")
        }
        let characters = Array(geohash.prefix(precision))
        let base = String(characters.dropLast())
        let lastValue = characters.last.flatMap { base32.firstIndex(of: $0) } ?? 0
        let significantBits = bits - base.count * bitsPerChar
        let unusedBits = bitsPerChar - significantBits
        let startValue = (lastValue >> unusedBits) << unusedBits
        let endValue = startValue + (1 << unusedBits)
        let start = base + String(base32[startValue])
        let end = endValue > 31 ? base + "~" : base + String(base32[endValue])
        return GeohashRange(start: start, end: end)
    }
}
