import Foundation

public struct ObservedSystemSource: Identifiable, Sendable, Hashable {
    public let id: String
    public let title: String
    public let url: URL
    public let coverage: String
    public let notes: String
}

public enum StellarObservationKind: String, Codable, CaseIterable, Sendable {
    case positionAngle = "相对方位角"
    case separation = "相对角距"
    case radialVelocity = "径向速度"
    case relativeRadialVelocity = "相对径向速度"
}

/// A published scalar measurement. A position angle and separation at one epoch
/// are two scalar rows, not two independently observed epochs. Original times,
/// instruments, corrections and reference tags are retained in `detail`.
public struct StellarObservation: Identifiable, Codable, Sendable, Hashable {
    public let id: String
    public let epochJulianYear: Double
    public let component: String
    public let kind: StellarObservationKind
    public let value: Double
    public let uncertainty: Double?
    public let unit: String
    public let detail: String
    public let sourceID: String

    public init(id: String, epochJulianYear: Double, component: String,
                kind: StellarObservationKind, value: Double, uncertainty: Double?,
                unit: String, detail: String, sourceID: String) {
        self.id = id; self.epochJulianYear = epochJulianYear; self.component = component
        self.kind = kind; self.value = value; self.uncertainty = uncertainty
        self.unit = unit; self.detail = detail; self.sourceID = sourceID
    }
}

public enum ObservedSystemError: Error, LocalizedError {
    case missingResource(String)
    case invalidRecord(String, Int)
    public var errorDescription: String? {
        switch self {
        case .missingResource(let name): return "缺少观测数据文件：\(name)"
        case .invalidRecord(let name, let line): return "观测数据文件 \(name) 第 \(line) 行格式错误。"
        }
    }
}
