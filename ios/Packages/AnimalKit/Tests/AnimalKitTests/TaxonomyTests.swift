import XCTest
@testable import AnimalKit

/// Tür ve ihtiyaç listesi, ekrandaki adları ve "Bu işareti bildir" nedenleri.
final class TaxonomyTests: XCTestCase {
    func testOnlyCatsAndDogs() {
        XCTAssertEqual(Species.allCases, [.cat, .dog])
        XCTAssertEqual(Species.allCases.map(\.title), ["Kedi", "Köpek"])
    }

    /// Izgaranın sırası değişmez (acil yardım üstte tam genişlikte ayrıca çizilir).
    func testNeedOrderIsUnchanged() {
        XCTAssertEqual(Need.allCases, [.food, .injured, .shelter, .babies, .vet, .emergency])
    }

    /// Başlıklar sağlıklı hayvanı değil yardım ihtiyacını anlatır; ham değerler (kurallar) aynı kalır.
    func testNeedTitlesAskAboutNeed() {
        let titles = Dictionary(uniqueKeysWithValues: Need.allCases.map { ($0, $0.title) })
        XCTAssertEqual(titles, [
            .food: "Aç ve zayıf",
            .injured: "Yaralı / hasta",
            .shelter: "Terk edilmiş / bakıma muhtaç",
            .babies: "Yavrular tehlikede",
            .vet: "Veteriner desteği",
            .emergency: "Acil yardım",
        ])
        XCTAssertEqual(Need.food.rawValue, "food")
        XCTAssertEqual(Need.shelter.rawValue, "shelter")
        XCTAssertEqual(Need.babies.rawValue, "babies")
    }

    func testEveryNeedHasItsOwnDefinition() {
        let definitions = Need.allCases.map(\.definition)
        XCTAssertFalse(definitions.contains { $0.isEmpty })
        XCTAssertEqual(Set(definitions).count, Need.allCases.count)
        XCTAssertEqual(Need.food.definition, "Çok zayıf, günlerdir beslenmiyor ya da su bulamıyor")
        XCTAssertEqual(Need.emergency.definition, "Hayati tehlike: ağır yaralı, sıkışmış, zehirlenmiş")
    }

    /// Yalnızca mama hafiftir: bütçeden 1 puan, 60 gündüz dakikası, haritada küçük ve "düşük öncelikli".
    func testOnlyFoodIsLight() {
        XCTAssertEqual(Need.allCases.filter { !$0.isSerious }, [.food])
        for need in Need.allCases {
            XCTAssertEqual(need.closeCost, need == .food ? 1 : 2, need.rawValue)
            XCTAssertEqual(need.demoteMinutes, need == .food ? 60 : 120, need.rawValue)
        }
        XCTAssertEqual(Need.allCases.filter(\.allowsUnneeded), [.food])
        // Haritada mama her ağır ihtiyacın altında çizilir; acil yardım en üstte.
        for need in Need.allCases where need.isSerious {
            XCTAssertGreaterThan(need.priority, Need.food.priority, need.rawValue)
        }
        XCTAssertEqual(Need.allCases.max { $0.priority < $1.priority }, .emergency)
    }

    func testFlagReasons() {
        XCTAssertEqual(FlagReason.allCases, [.fake, .unsafe, .misuse])
        XCTAssertEqual(FlagReason.fake.title, "Burada yardım bekleyen hayvan yok (sahte işaret)")
        XCTAssertEqual(CollectionName.flagDocumentID(reportID: "r1", userID: "u1"), "r1_u1")
    }

    func testOnlyExpiredCannotBeProposed() {
        XCTAssertEqual(ClosedReason.allCases.filter { !$0.canBeProposed }, [.expired])
    }
}
