import Foundation

/// Explicit units and source URLs are required; imports never become dynamical
/// initial conditions automatically and never masquerade as built-in observations.
public enum ObservationCSV {
    public static let header = "epoch_year,component,kind,value,uncertainty,unit,source_url,detail"
    public static func decode(_ text: String) throws -> [StellarObservation] {
        let rows = try parse(text.replacingOccurrences(of: "\u{FEFF}", with: ""))
        guard rows.first == header.split(separator: ",").map(String.init) else {
            throw SimulationError.invalidScenario(["CSV 表头应为：\(header)"])
        }
        guard rows.count <= 100_001 else { throw SimulationError.invalidScenario(["一次最多导入 100,000 条观测值。"] ) }
        let names: [String: StellarObservationKind] = ["positionAngle": .positionAngle, "separation": .separation,
            "radialVelocity": .radialVelocity, "relativeRadialVelocity": .relativeRadialVelocity]
        let allowedUnits: [StellarObservationKind:Set<String>] = [.positionAngle:["deg"], .separation:["arcsec","mas"],
            .radialVelocity:["km/s","m/s"], .relativeRadialVelocity:["km/s","m/s"]]
        var observations: [StellarObservation] = []
        for (index,row) in rows.dropFirst().enumerated() {
            func invalid() -> SimulationError { .invalidScenario(["CSV 第 \(index+2) 行无效：请检查列数、有限数值、类型、单位和来源网址。"] ) }
            guard row.count == 8, let year = Double(row[0]), year.isFinite, (1...9999).contains(year),
                  !row[1].isEmpty, let kind = names[row[2]] ?? StellarObservationKind(rawValue: row[2]),
                  let value = Double(row[3]), value.isFinite,
                  allowedUnits[kind]?.contains(row[5]) == true,
                  let source = URL(string: row[6]), ["https","http"].contains(source.scheme), source.host != nil,
                  source.user == nil, source.password == nil else { throw invalid() }
            let uncertainty = row[4].isEmpty ? nil : Double(row[4])
            guard row[4].isEmpty || (uncertainty?.isFinite == true && uncertainty! >= 0) else { throw invalid() }
            guard kind != .separation || value >= 0 else { throw invalid() }
            observations.append(.init(id: UUID().uuidString,epochJulianYear: year,component: row[1],kind: kind,
                value: value,uncertainty: uncertainty,unit: row[5],detail: row[7],sourceID: source.absoluteString))
        }
        guard !observations.isEmpty else { throw SimulationError.invalidScenario(["CSV 中没有观测记录。"] ) }
        return observations
    }

    public static func encode(_ records: [StellarObservation]) -> String {
        let sources = Dictionary(uniqueKeysWithValues: AlphaCentauriCatalog.sources.map { ($0.id,$0.url.absoluteString) })
        func field(_ value: String) -> String { "\""+value.replacingOccurrences(of: "\"",with:"\"\"")+"\"" }
        return ([header]+records.map { row in
            [String(row.epochJulianYear),row.component,row.kind.rawValue,String(row.value),row.uncertainty.map { String($0) } ?? "",
             row.unit,sources[row.sourceID] ?? row.sourceID,row.detail].map(field).joined(separator: ",")
        }).joined(separator:"\n")+"\n"
    }

    private static func parse(_ text: String) throws -> [[String]] {
        var rows: [[String]] = [], row: [String] = [], field = "", quoted = false, closed = false
        var cursor = text.startIndex
        func invalid() -> SimulationError { .invalidScenario(["CSV 引号或分隔符格式不正确。"] ) }
        func finishField() { row.append(field); field = ""; closed = false }
        func finishRow() {
            finishField()
            if row.contains(where: { !$0.isEmpty }) { rows.append(row) }
            row = []
        }
        while cursor < text.endIndex {
            let character = text[cursor]
            let next = text.index(after: cursor)
            if quoted {
                if character == "\"" {
                    if next < text.endIndex, text[next] == "\"" { field.append("\""); cursor = text.index(after: next); continue }
                    quoted = false; closed = true
                } else { field.append(character) }
            } else if character == "\"" {
                guard field.isEmpty, !closed else { throw invalid() }
                quoted = true
            } else if character == "," { finishField() }
            else if character == "\n" || character == "\r" || character == "\r\n" { finishRow() }
            else {
                guard !closed else { throw invalid() }
                field.append(character)
            }
            cursor = next
        }
        guard !quoted else { throw invalid() }
        if !field.isEmpty || !row.isEmpty || closed { finishRow() }
        return rows
    }
}
