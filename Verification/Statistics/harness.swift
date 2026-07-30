import Foundation

// Fixed pseudo-random series so Swift and Python see identical inputs.
func series(_ seed: UInt64, _ n: Int) -> [Double] {
    var state = seed
    var out: [Double] = []
    for _ in 0..<n {
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let bits = (state >> 11) & 0x1FFFFFFFFFFFFF
        out.append(Double(bits) / Double(0x1FFFFFFFFFFFFF))
    }
    return out
}

let x = series(42, 40).map { $0 * 10 }
let y = series(7, 40).map { $0 * 5 + 2 }
// A series with a real trend plus noise.
let trended = (0..<40).map { Double($0) * 0.3 + series(99, 40)[$0] * 4 }
// Ties, to exercise rank correction.
let tied: [Double] = [5,5,5,7,7,8,9,9,9,9,10,11,11,12,3,3,4,4,4,6]

func p(_ label: String, _ v: Double?) {
    if let v { print("\(label)\t\(String(format: "%.16f", v))") } else { print("\(label)\tnil") }
}

print("### inputs")
print("x\t" + x.map { String(format: "%.16f", $0) }.joined(separator: ","))
print("y\t" + y.map { String(format: "%.16f", $0) }.joined(separator: ","))
print("trended\t" + trended.map { String(format: "%.16f", $0) }.joined(separator: ","))
print("tied\t" + tied.map { String(format: "%.1f", $0) }.joined(separator: ","))

print("### basics")
p("mean_x", Stats.mean(x))
p("var_x", Stats.variance(x))
p("sd_x", Stats.standardDeviation(x))
p("median_x", Stats.median(x))
p("mad_scaled_x", Stats.medianAbsoluteDeviation(x))
p("mad_raw_x", Stats.medianAbsoluteDeviation(x, scaled: false))
p("p25_x", Stats.percentile(x, 0.25))
p("p75_x", Stats.percentile(x, 0.75))
p("p90_x", Stats.percentile(x, 0.90))
p("iqr_x", Stats.iqr(x))
p("cv_x", Stats.coefficientOfVariation(x))

print("### ranks (ties)")
print("ranks_tied\t" + Stats.ranks(tied).map { String(format: "%.1f", $0) }.joined(separator: ","))

print("### distributions")
for v in [-3.0, -1.5, -0.5, 0.0, 0.5, 1.0, 1.96, 2.5, 3.0] {
    p("normalCDF(\(v))", Stats.normalCDF(v))
}
for v in [0.001, 0.025, 0.1, 0.5, 0.9, 0.975, 0.999] {
    p("normalQuantile(\(v))", Stats.normalQuantile(v))
}
for (t, df) in [(2.0, 10.0), (1.5, 5.0), (3.2, 25.0), (2.0, 8.5), (0.7, 13.0), (4.0, 3.0)] {
    p("t2tail(t=\(t),df=\(df))", Stats.studentTTwoTailed(t: t, df: df))
}
for df in [5.0, 10.0, 8.5, 25.0, 100.0] {
    p("tcrit(df=\(df))", Stats.studentTCriticalValue(df: df))
}
for (a, b, xx) in [(2.0, 3.0, 0.4), (0.5, 5.0, 0.2), (5.0, 0.5, 0.9), (12.5, 0.5, 0.7)] {
    p("ibeta(a=\(a),b=\(b),x=\(xx))", Stats.incompleteBeta(a: a, b: b, x: xx))
}

print("### correlation")
if let c = Stats.pearson(x, y) {
    p("pearson_r", c.coefficient); p("pearson_n", Double(c.n))
    p("pearson_effN", c.effectiveN); p("pearson_p", c.pValue)
}
if let c = Stats.spearman(x, y) {
    p("spearman_r", c.coefficient); p("spearman_effN", c.effectiveN); p("spearman_p", c.pValue)
}
if let c = Stats.pearson(x, trended) { p("pearson_x_trended", c.coefficient) }
if let c = Stats.spearman(tied, tied.reversed().map { $0 }) { p("spearman_tied_rev", c.coefficient) }

print("### autocorrelation")
p("acf1_x", Stats.autocorrelation(x, lag: 1))
p("acf2_x", Stats.autocorrelation(x, lag: 2))
p("acf1_trended", Stats.autocorrelation(trended, lag: 1))
p("effN_40_r0.7", Stats.effectiveSampleSize(40, autocorrelation: 0.7))

print("### regression")
if let r = Stats.linearRegression(x: x.indices.map(Double.init), y: trended) {
    p("reg_slope", r.slope); p("reg_intercept", r.intercept)
    p("reg_r2", r.rSquared); p("reg_slopeSE", r.slopeStandardError)
    p("reg_p", r.pValue); p("reg_effN", r.effectiveN)
}
p("theilsen_trended", Stats.theilSenTrend(trended)?.slope)
p("theilsen_int_trended", Stats.theilSenTrend(trended)?.intercept)
p("theilsen_x_y", Stats.theilSenSlope(x: x, y: y))

print("### mann-kendall")
if let mk = Stats.mannKendall(trended) {
    p("mk_s", mk.s); p("mk_tau", mk.tau); p("mk_z", mk.z); p("mk_p", mk.pValue)
}
if let mk = Stats.mannKendall(x) {
    p("mk_s_x", mk.s); p("mk_tau_x", mk.tau); p("mk_p_x", mk.pValue)
}
if let mk = Stats.mannKendall(tied) {
    p("mk_s_tied", mk.s); p("mk_z_tied", mk.z); p("mk_p_tied", mk.pValue)
}

print("### ewma")
let e = Stats.ewma(x, alpha: Stats.ewmaAlpha(spanDays: 7))
p("ewma_alpha7", Stats.ewmaAlpha(spanDays: 7))
print("ewma_last3\t" + e.suffix(3).map { String(format: "%.16f", $0) }.joined(separator: ","))

print("### swc")
p("swc_x", Stats.smallestWorthwhileChange(x))

print("### interpolate")
let gapped: [Double?] = [nil, 1, nil, nil, 4, nil, 6, nil, nil, nil, nil, 11, nil]
print("interp\t" + Stats.interpolateGaps(gapped, maxGap: 3).map { $0 == nil ? "nil" : String(format: "%.4f", $0!) }.joined(separator: ","))

print("### cusum")
let shifted = Array(series(3, 20).map { $0 * 2 + 10 }) + Array(series(4, 20).map { $0 * 2 + 15 })
if let cp = Stats.cusumChangePoint(shifted) {
    p("cusum_index", Double(cp.index)); p("cusum_before", cp.meanBefore)
    p("cusum_after", cp.meanAfter); p("cusum_sd", cp.magnitudeInSD)
} else { print("cusum\tnil") }
