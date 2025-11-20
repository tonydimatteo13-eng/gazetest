import XCTest
@testable import FireFlyCore

final class ScorerTests: XCTestCase {
    func testTypicalFixtureProducesLowASDProbability() throws {
        let fixture = try loadFixture(named: "score_typical")
        let result = Scorer.bayesASDLike(stopAcc: fixture.stopAccuracy, slowingMs: fixture.slowing)
        XCTAssertLessThanOrEqual(result.p, 0.30)
    }

    func testASDLikeFixtureProducesHighProbability() throws {
        let fixture = try loadFixture(named: "score_asdlike")
        let result = Scorer.bayesASDLike(stopAcc: fixture.stopAccuracy, slowingMs: fixture.slowing)
        XCTAssertGreaterThanOrEqual(result.p, 0.70)
    }

    private func loadFixture(named name: String) throws -> (stopAccuracy: Double, slowing: Double) {
        guard let url = Bundle(for: type(of: self)).url(forResource: name, withExtension: "json") else {
            XCTFail("Missing fixture \(name)")
            throw NSError(domain: "Fixture", code: 1)
        }
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Double]
        guard let stop = json?["stop_accuracy_pct"], let slowing = json?["go_rt_slowing_ms"] else {
            throw NSError(domain: "Fixture", code: 0)
        }
        return (stop, slowing)
    }
}
