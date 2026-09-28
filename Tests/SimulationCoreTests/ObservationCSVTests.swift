import Foundation
import Testing
@testable import SimulationCore

@Suite("观测 CSV 与来源")
struct ObservationCSVTests {
    @Test("导出再导入保留数值、误差、来源及带引号换行的说明")
    func roundTrip() throws {
        var records = Array(try AlphaCentauriCatalog.observations().prefix(3))
        records.append(.init(id: "external", epochJulianYear: 2025.5, component: "α Cen A", kind: .radialVelocity,
                             value: -22.51, uncertainty: nil, unit: "km/s", detail: "说明, \"引文\"\n第二行", sourceID: "https://example.org/observation"))
        let decoded = try ObservationCSV.decode(ObservationCSV.encode(records))
        #expect(decoded.count == records.count)
        for (expected, actual) in zip(records, decoded) {
            #expect(expected.epochJulianYear == actual.epochJulianYear)
            #expect(expected.component == actual.component)
            #expect(expected.kind == actual.kind)
            #expect(expected.value == actual.value)
            #expect(expected.uncertainty == actual.uncertainty)
            #expect(expected.unit == actual.unit)
            #expect(expected.detail == actual.detail)
            #expect(actual.sourceID.hasPrefix("https://"))
        }
    }

    @Test("拒绝没有来源、非有限值、错误单位及破损引号")
    func rejectInvalidMeasurements() {
        let invalid = [
            "2020,A,radialVelocity,1,0.1,km/s,,说明",
            "2020,A,radialVelocity,nan,0.1,km/s,https://example.org,说明",
            "2020,A,separation,-1,0.1,arcsec,https://example.org,说明",
            "2020,A,positionAngle,1,0.1,km/s,https://example.org,说明",
            "2020,A,radialVelocity,1,-0.1,km/s,https://example.org,说明",
            "2020,A,radialVelocity,1,0.1,km/s,file:///tmp/source,说明",
            "2020,A,radialVelocity,1,0.1,km/s,https://example.org,\"未闭合",
            "2020,A,radialVelocity,1,0.1,km/s,https://example.org,\"闭合\"多余"
        ]
        for row in invalid {
            #expect(throws: (any Error).self) { try ObservationCSV.decode(ObservationCSV.header + "\n" + row) }
        }
    }

    @Test("接受 UTF-8 BOM 与 Windows 换行，空误差保持未知")
    func compatibleLineEndings() throws {
        let csv = "\u{FEFF}" + ObservationCSV.header + "\r\n2020,A,separation,2,,mas,https://example.org,说明\r\n\r\n"
        let row = try #require(ObservationCSV.decode(csv).first)
        #expect(row.uncertainty == nil)
        #expect(row.unit == "mas")
        #expect(row.value == 2)
    }
}
