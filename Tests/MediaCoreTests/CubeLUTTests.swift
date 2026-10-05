import Foundation
import Testing
@testable import MediaCore

struct CubeLUTTests {
    let entries = "0 0 0\n1 0 0\n0 1 0\n1 1 0\n0 0 1\n1 0 1\n0 1 1\n1 1 1"

    @Test func testIdentityOrderingAndCoreImageBuffer() throws {
        let lut = try CubeLUT(text: "TITLE \"Identity # test\" # comment\nLUT_3D_SIZE 2\n" + entries)
        #expect(lut.title == "Identity # test")
        #expect(lut.dimension == 2)
        let data = lut.rgbaData()
        let values = data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
        #expect(values.count == 32)
        #expect(Array(values[4..<8]) == [1, 0, 0, 1])
        #expect(Array(values[16..<20]) == [0, 0, 1, 1])
    }

    @Test func testCustomDomainAndExtendedValuesArePreserved() throws {
        let lut = try CubeLUT(text: "DOMAIN_MIN -1 -1 -1\nDOMAIN_MAX 2 2 2\nLUT_3D_SIZE 2\n" + entries.replacingOccurrences(of: "1 1 1", with: "1.2 1.3 1.4"))
        #expect(lut.domainMin == [-1, -1, -1])
        #expect(Array(lut.rgb.suffix(3)) == [1.2, 1.3, 1.4])
    }

    @Test func testRejectsMalformedOrUnsupportedTables() {
        let invalid = [
            "LUT_3D_SIZE 2\n0 0 0",
            "LUT_3D_SIZE 2\n" + entries + "\n0 0 0",
            "LUT_3D_SIZE 2\n" + entries.replacingOccurrences(of: "1 1 1", with: "nan 1 1"),
            "LUT_3D_SIZE 2\n" + entries.replacingOccurrences(of: "1 1 1", with: "1e99 1 1"),
            "DOMAIN_MIN 1 0 0\nLUT_3D_SIZE 2\n" + entries,
            "LUT_3D_SIZE 2\nLUT_3D_SIZE 2\n" + entries,
            "LUT_1D_SIZE 2\n0 0 0\n1 1 1",
            "LUT_3D_SIZE 129\n" + entries,
            "LUT_3D_SIZE 2\n" + entries + "\nDOMAIN_MIN 0 0 0"
        ]
        for table in invalid {
            #expect(throws: CubeLUT.ParseError.self) { try CubeLUT(text: table) }
        }
    }
}
