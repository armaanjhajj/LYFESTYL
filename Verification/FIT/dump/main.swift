import Foundation
// Emit mesgNum -> fieldNum -> {n, sum} as JSON for differential comparison.
let path = CommandLine.arguments[1]
guard let data = FileManager.default.contents(atPath: path),
      let file = try? FITDecoder.decode(data) else { print("{}"); exit(1) }

var out: [String: [String: Any]] = [:]
for (mesgNum, msgs) in file.messages {
    var group: [String: Any] = ["__count": msgs.count]
    var stats: [UInt8: (n: Int, sum: Double)] = [:]
    for m in msgs {
        for (fnum, value) in m.fields {
            let values: [Double]
            switch value {
            case .array(let a):    values = a
            case .integer(let v):  values = [Double(v)]
            case .unsigned(let v): values = [Double(v)]
            case .floating(let v): values = [v]
            case .bytes(let b):    values = b.map(Double.init)
            case .string:          values = []
            }
            guard !values.isEmpty else { continue }
            var s = stats[fnum] ?? (0, 0)
            s.n += values.count
            s.sum += values.reduce(0, +)
            stats[fnum] = s
        }
    }
    for (fnum, s) in stats { group[String(fnum)] = ["n": s.n, "sum": s.sum] }
    out[String(mesgNum)] = group
}
let json = try! JSONSerialization.data(withJSONObject: out, options: [])
print(String(data: json, encoding: .utf8)!)
