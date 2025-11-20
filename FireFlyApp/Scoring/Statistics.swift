import Foundation

public enum Statistics {
    static func mean(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return .nan }
        return values.reduce(0, +) / Double(values.count)
    }

    static func stddev(_ values: [Double]) -> Double {
        guard values.count > 1 else { return .nan }
        let m = mean(values)
        let variance = values.reduce(0) { $0 + pow($1 - m, 2) } / Double(values.count - 1)
        return sqrt(variance)
    }

    static func percentile(_ values: [Double], percentile: Double) -> Double {
        precondition(percentile >= 0 && percentile <= 1, "Percentile must be in [0,1]")
        guard !values.isEmpty else { return .nan }
        let sorted = values.sorted()
        let rank = percentile * Double(sorted.count - 1)
        let lower = Int(floor(rank))
        let upper = Int(ceil(rank))
        guard lower != upper else { return sorted[lower] }
        let weight = rank - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    static func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }

    static func zScore(value: Double, mean: Double, sd: Double) -> Double {
        guard sd > 0 else { return 0 }
        return (value - mean) / sd
    }
}

public struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64

    public init(seed: UInt64) {
        precondition(seed != 0, "Seed must be non-zero")
        self.state = seed
    }

    public mutating func next() -> UInt64 {
        // Xoroshiro64*
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 2685821657736338717
    }
}

extension SeededGenerator {
    public mutating func nextDouble() -> Double {
        Double(next()) / Double(UInt64.max)
    }
}
