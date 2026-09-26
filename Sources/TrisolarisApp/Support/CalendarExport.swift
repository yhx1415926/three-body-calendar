import Foundation
import SimulationCore

enum CalendarExport {
    static func csv(_ result: CalendarResult, annualDetails: Bool = false) -> String {
        var rows: [String]
        if annualDetails {
            rows = ["年份,纪元,已完成,恒纪元占比,最低模型温度_C,最高模型温度_C,最低辐照_地球倍数,最高辐照_地球倍数,标准年_日"]
            rows += result.years.map {
                let label = $0.isComplete ? ($0.kind == .stable ? "恒纪元" : "乱纪元") : "未完成"
                return "\($0.year),\(label),\($0.isComplete),\($0.stableFraction),\($0.minimumTemperatureC),\($0.maximumTemperatureC),\($0.minimumFluxEarth),\($0.maximumFluxEarth),\(result.standardYearDays)"
            }
        } else {
            rows = ["纪元,起点_标准年,终点_标准年,持续_标准年,起点_日,终点_日,标准年_日,计算状态"]
            rows += result.intervals.map {
                "\($0.kind == .stable ? "恒纪元" : "乱纪元"),\($0.startDays/result.standardYearDays),\($0.endDays/result.standardYearDays),\(($0.endDays-$0.startDays)/result.standardYearDays),\($0.startDays),\($0.endDays),\(result.standardYearDays),\(result.progress.status.rawValue)"
            }
        }
        return "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
    }
}
