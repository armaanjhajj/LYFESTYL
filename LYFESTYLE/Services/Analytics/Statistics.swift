//
//  Statistics.swift
//  LYFESTYL
//
//  The numerical foundation everything else in the analysis stands on. Pure
//  functions, no state, no UI, no data model, so each one can be reasoned about and
//  checked in isolation.
//
//  Written for the situation this app is actually in: SMALL, NOISY, AUTOCORRELATED
//  personal time series. That shapes every choice here.
//
//    - Robust estimators (median, median absolute deviation, Theil-Sen, Mann-Kendall)
//      sit alongside the classical ones, because one bad night of sensor data should
//      not move a baseline.
//    - Significance is computed properly (exact normal CDF via erf, Student t via the
//      regularized incomplete beta) rather than compared against a memorized
//      critical value.
//    - Autocorrelation is corrected for. Two smoothly drifting series correlate
//      strongly by construction, so a naive Pearson r on daily HRV against daily
//      sleep would look highly significant when it carries almost no information.
//      `effectiveSampleSize` applies the standard variance-inflation correction, and
//      the correlation helpers use it. This is the single most important guard in
//      the file: without it the app would confidently report coincidences.
//
//  References are cited inline at each method.
//

import Foundation

nonisolated extension Comparable {
    /// Clamp into a closed range. Lives here because the numerical code leans on it
    /// constantly to keep values inside their mathematically valid domains.
    func clamped(to limits: ClosedRange<Self>) -> Self {
        min(max(self, limits.lowerBound), limits.upperBound)
    }
}

nonisolated enum Stats {

    // MARK: - Central tendency and spread

    static func mean(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        return values.reduce(0, +) / Double(values.count)
    }

    /// Sample variance, Bessel-corrected (divides by n-1). Needs at least 2 points.
    static func variance(_ values: [Double]) -> Double? {
        guard values.count >= 2, let m = mean(values) else { return nil }
        let ss = values.reduce(0.0) { $0 + ($1 - m) * ($1 - m) }
        return ss / Double(values.count - 1)
    }

    static func standardDeviation(_ values: [Double]) -> Double? {
        variance(values).map(sqrt)
    }

    /// Coefficient of variation as a fraction. Only meaningful for strictly
    /// positive quantities, so it returns nil when the mean is at or below zero.
    static func coefficientOfVariation(_ values: [Double]) -> Double? {
        guard let m = mean(values), m > 0, let sd = standardDeviation(values) else { return nil }
        return sd / m
    }

    static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        if sorted.count.isMultiple(of: 2) {
            return (sorted[mid - 1] + sorted[mid]) / 2
        }
        return sorted[mid]
    }

    /// Median absolute deviation, scaled by 1.4826 so that for normally distributed
    /// data it estimates the same quantity as the standard deviation.
    ///
    /// The constant is 1 / Phi^-1(0.75), the inverse normal CDF at the third
    /// quartile. It makes MAD a drop-in robust replacement for SD: unlike SD, a
    /// single wild outlier cannot inflate it.
    static let madScale = 1.4826

    static func medianAbsoluteDeviation(_ values: [Double], scaled: Bool = true) -> Double? {
        guard values.count >= 2, let med = median(values) else { return nil }
        let deviations = values.map { abs($0 - med) }
        guard let mad = median(deviations) else { return nil }
        return scaled ? mad * madScale : mad
    }

    /// Percentile by linear interpolation between order statistics (the same
    /// definition NumPy uses by default). `p` is a fraction in 0...1.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        guard sorted.count > 1 else { return sorted[0] }
        let position = p.clamped(to: 0...1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] * (1 - weight) + sorted[upper] * weight
    }

    /// Interquartile range.
    static func iqr(_ values: [Double]) -> Double? {
        guard let q1 = percentile(values, 0.25), let q3 = percentile(values, 0.75) else { return nil }
        return q3 - q1
    }

    // MARK: - Standard scores

    /// Classical z-score against a sample.
    static func zScore(_ value: Double, in values: [Double]) -> Double? {
        guard let m = mean(values), let sd = standardDeviation(values), sd > 0 else { return nil }
        return (value - m) / sd
    }

    /// Robust z-score: deviation from the MEDIAN in units of scaled MAD.
    ///
    /// This is what the app uses to decide "is today unusual for me". A classical
    /// z-score is computed against a mean and SD that the unusual day itself
    /// inflates, which systematically hides anomalies. The median and MAD barely
    /// move, so a genuinely odd day stands out.
    static func robustZScore(_ value: Double, in values: [Double]) -> Double? {
        guard let med = median(values), let mad = medianAbsoluteDeviation(values), mad > 0 else {
            return nil
        }
        return (value - med) / mad
    }

    // MARK: - Exponentially weighted moving average

    /// EWMA over a series, oldest first. `alpha` is the smoothing factor in 0...1;
    /// the returned array is the same length as the input, each element being the
    /// average as of that point.
    static func ewma(_ values: [Double], alpha: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        let a = alpha.clamped(to: 0...1)
        var result: [Double] = []
        result.reserveCapacity(values.count)
        var current = values[0]
        result.append(current)
        for value in values.dropFirst() {
            current = a * value + (1 - a) * current
            result.append(current)
        }
        return result
    }

    /// The smoothing factor for an N-period exponentially weighted average,
    /// alpha = 2 / (N + 1). This is the convention Williams et al. (2017) use for
    /// the exponentially weighted acute:chronic workload ratio.
    static func ewmaAlpha(spanDays n: Double) -> Double {
        guard n > 0 else { return 1 }
        return 2 / (n + 1)
    }

    /// Simple moving average with a trailing window. Positions with fewer than
    /// `minCount` observations return nil rather than a misleading partial average.
    static func movingAverage(_ values: [Double], window: Int, minCount: Int? = nil) -> [Double?] {
        guard window > 0 else { return values.map { $0 } }
        let required = minCount ?? window
        var result: [Double?] = []
        result.reserveCapacity(values.count)
        for i in values.indices {
            let lo = max(0, i - window + 1)
            let slice = Array(values[lo...i])
            result.append(slice.count >= required ? mean(slice) : nil)
        }
        return result
    }

    // MARK: - Ranks (for non-parametric methods)

    /// Fractional ranks, 1-based, with ties receiving the average of the ranks they
    /// span. Correct tie handling matters: personal data is full of repeated
    /// integers (7 hours of sleep, 8000 steps) and mishandling ties biases
    /// Spearman's rho.
    static func ranks(_ values: [Double]) -> [Double] {
        let indexed = values.enumerated().sorted { $0.element < $1.element }
        var result = [Double](repeating: 0, count: values.count)
        var i = 0
        while i < indexed.count {
            var j = i
            while j + 1 < indexed.count, indexed[j + 1].element == indexed[i].element { j += 1 }
            // Ranks i+1 through j+1 all tie; assign their mean.
            let averageRank = Double(i + 1 + j + 1) / 2
            for k in i...j { result[indexed[k].offset] = averageRank }
            i = j + 1
        }
        return result
    }

    /// Counts of each tie group size, used by the Mann-Kendall variance correction.
    static func tieGroupSizes(_ values: [Double]) -> [Int] {
        var counts: [Double: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.values.filter { $0 > 1 }
    }

    // MARK: - Autocorrelation and effective sample size

    /// Lag-k autocorrelation of a series (the sample ACF).
    static func autocorrelation(_ values: [Double], lag: Int = 1) -> Double? {
        guard lag > 0, values.count > lag + 1, let m = mean(values) else { return nil }
        var numerator = 0.0
        var denominator = 0.0
        for i in 0..<values.count {
            let d = values[i] - m
            denominator += d * d
            if i + lag < values.count {
                numerator += d * (values[i + lag] - m)
            }
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }

    /// The number of INDEPENDENT observations a correlated series is really worth.
    ///
    /// For a series with lag-1 autocorrelation r, the variance of the sample mean is
    /// inflated by roughly (1 + r) / (1 - r), so the effective sample size is
    ///
    ///     n_eff = n * (1 - r) / (1 + r)
    ///
    /// (the standard first-order correction, as in Bartlett 1935 and used widely in
    /// hydrology and climatology for serially dependent series).
    ///
    /// This is why it matters here: daily resting heart rate has a lag-1
    /// autocorrelation around 0.6 to 0.8. At r = 0.7, sixty days of data carry the
    /// statistical weight of about ten. Reporting a p-value from n = 60 would
    /// overstate confidence by an enormous margin. Every correlation this app
    /// surfaces is tested against n_eff, not n.
    static func effectiveSampleSize(_ n: Int, autocorrelation r: Double?) -> Double {
        guard let r, r > 0 else { return Double(n) }
        let capped = min(r, 0.95)   // guard the singularity as r approaches 1
        return Double(n) * (1 - capped) / (1 + capped)
    }

    /// Effective sample size for CORRELATING two series.
    ///
    /// For two first-order autoregressive series with lag-1 autocorrelations rx and
    /// ry, the variance of the sample cross-correlation is inflated by
    /// (1 + rx*ry) / (1 - rx*ry), giving
    ///
    ///     n_eff = n * (1 - rx*ry) / (1 + rx*ry)
    ///
    /// This is Bartlett's (1935) result, the form used by Dawdy and Matalas (1964)
    /// and standard in climatology for serially dependent series.
    ///
    /// The PRODUCT matters, not the maximum. If one series is autocorrelated and the
    /// other is essentially white noise, spurious correlation between them is not
    /// actually inflated, so penalising the pair for the slow series alone would
    /// throw away real evidence. Only when BOTH drift slowly does the naive p-value
    /// become untrustworthy.
    static func pairedEffectiveSampleSize(_ x: [Double], _ y: [Double]) -> Double {
        let n = min(x.count, y.count)
        guard n > 3 else { return Double(n) }
        let rx = (autocorrelation(x) ?? 0).clamped(to: 0...0.98)
        let ry = (autocorrelation(y) ?? 0).clamped(to: 0...0.98)
        let product = (rx * ry).clamped(to: 0...0.95)
        guard product > 0 else { return Double(n) }
        return Double(n) * (1 - product) / (1 + product)
    }

    // MARK: - Correlation

    /// A correlation result carrying everything needed to report it honestly.
    struct Correlation: Hashable, Sendable {
        /// The coefficient, -1 to 1.
        var coefficient: Double
        /// Raw number of paired observations.
        var n: Int
        /// Independent-equivalent observations after the autocorrelation correction.
        var effectiveN: Double
        /// Two-tailed p-value computed against `effectiveN`.
        var pValue: Double
        /// Which method produced the coefficient.
        var method: Method
        /// Lag in days applied to the predictor before pairing (0 for same-day).
        var lagDays: Int

        enum Method: String, Hashable, Sendable {
            case pearson, spearman
            var label: String {
                switch self {
                case .pearson:  "linear"
                case .spearman: "rank"
                }
            }
        }

        /// Shared-variance interpretation, only defined for the linear coefficient.
        var rSquared: Double? {
            method == .pearson ? coefficient * coefficient : nil
        }

        var absCoefficient: Double { abs(coefficient) }

        /// A deliberately conservative bar for showing a relationship to the user.
        ///
        /// Requires: at least 14 real pairs, at least 8 independent-equivalent
        /// observations, a two-tailed p below 0.05, AND an absolute coefficient of
        /// at least 0.3. All four, because any one alone produces noise at this
        /// sample size. The magnitude floor matters as much as the p-value: a
        /// statistically detectable r of 0.12 is not something to tell someone
        /// about their body.
        var isReportable: Bool {
            n >= 14 && effectiveN >= 8 && pValue < 0.05 && absCoefficient >= 0.3
        }

        /// Plain-language strength, using the conventional social-science bands.
        /// Never phrased as causal.
        var strengthLabel: String {
            switch absCoefficient {
            case 0.7...:     "strong"
            case 0.5..<0.7:  "moderate"
            case 0.3..<0.5:  "modest"
            default:         "weak"
            }
        }

        var isPositive: Bool { coefficient > 0 }
    }

    /// Pearson product-moment correlation with an autocorrelation-corrected p-value.
    static func pearson(_ x: [Double], _ y: [Double], lagDays: Int = 0) -> Correlation? {
        let n = min(x.count, y.count)
        guard n >= 3 else { return nil }
        let a = Array(x.prefix(n))
        let b = Array(y.prefix(n))
        guard let mx = mean(a), let my = mean(b) else { return nil }

        var sxy = 0.0, sxx = 0.0, syy = 0.0
        for i in 0..<n {
            let dx = a[i] - mx
            let dy = b[i] - my
            sxy += dx * dy
            sxx += dx * dx
            syy += dy * dy
        }
        guard sxx > 0, syy > 0 else { return nil }
        let r = (sxy / sqrt(sxx * syy)).clamped(to: -1...1)

        let effectiveN = pairedEffectiveSampleSize(a, b)
        let p = correlationPValue(r: r, n: effectiveN)
        return Correlation(coefficient: r, n: n, effectiveN: effectiveN,
                           pValue: p, method: .pearson, lagDays: lagDays)
    }

    /// Spearman rank correlation: Pearson on the fractional ranks.
    ///
    /// Preferred over Pearson for most of this app's questions, because personal
    /// health series are not remotely normal (sleep duration is truncated, steps are
    /// skewed by a single long walk) and a rank method is immune to that. It also
    /// detects monotone-but-curved relationships that Pearson misses.
    static func spearman(_ x: [Double], _ y: [Double], lagDays: Int = 0) -> Correlation? {
        let n = min(x.count, y.count)
        guard n >= 3 else { return nil }
        let rx = ranks(Array(x.prefix(n)))
        let ry = ranks(Array(y.prefix(n)))
        guard var result = pearson(rx, ry, lagDays: lagDays) else { return nil }
        // Report the effective n from the ORIGINAL series: ranking does not remove
        // serial dependence, and using the ranks' own autocorrelation would
        // understate it.
        result.effectiveN = pairedEffectiveSampleSize(Array(x.prefix(n)), Array(y.prefix(n)))
        result.pValue = correlationPValue(r: result.coefficient, n: result.effectiveN)
        result.method = .spearman
        return result
    }

    /// Two-tailed p-value for a correlation coefficient, via the exact t transform
    ///     t = r * sqrt((n - 2) / (1 - r^2))    with n - 2 degrees of freedom.
    /// `n` is a Double so a fractional effective sample size can be used directly.
    static func correlationPValue(r: Double, n: Double) -> Double {
        let df = n - 2
        guard df > 0 else { return 1 }
        let rr = min(abs(r), 0.999999)
        let t = rr * sqrt(df / (1 - rr * rr))
        return studentTTwoTailed(t: t, df: df)
    }

    /// Cross-correlate a predictor against an outcome across a range of day lags,
    /// returning the result for each lag. Positive lag means the predictor is shifted
    /// EARLIER, testing "does x from `lag` days ago relate to y today".
    ///
    /// Both series must be aligned to consecutive days with nil for missing values,
    /// so a gap does not silently shift the alignment.
    static func laggedCorrelations(
        predictor: [Double?],
        outcome: [Double?],
        lags: ClosedRange<Int>,
        method: Correlation.Method = .spearman
    ) -> [Correlation] {
        var results: [Correlation] = []
        for lag in lags {
            var xs: [Double] = []
            var ys: [Double] = []
            for i in outcome.indices {
                let predictorIndex = i - lag
                guard predictorIndex >= 0, predictorIndex < predictor.count else { continue }
                guard let px = predictor[predictorIndex], let py = outcome[i] else { continue }
                xs.append(px)
                ys.append(py)
            }
            let correlation = method == .pearson
                ? pearson(xs, ys, lagDays: lag)
                : spearman(xs, ys, lagDays: lag)
            if let correlation { results.append(correlation) }
        }
        return results
    }

    // MARK: - Linear regression

    struct Regression: Hashable, Sendable {
        var slope: Double
        var intercept: Double
        /// Coefficient of determination.
        var rSquared: Double
        /// Standard error of the slope.
        var slopeStandardError: Double
        var n: Int
        var effectiveN: Double
        /// Two-tailed p for the null hypothesis that the slope is zero.
        var pValue: Double

        /// 95 percent confidence interval on the slope, using the t distribution on
        /// the effective sample size.
        var slopeConfidenceInterval: ClosedRange<Double>? {
            let df = effectiveN - 2
            guard df > 0, slopeStandardError > 0 else { return nil }
            let t = Stats.studentTCriticalValue(df: df, twoTailedAlpha: 0.05)
            let margin = t * slopeStandardError
            return (slope - margin)...(slope + margin)
        }

        /// A trend is only claimed when the confidence interval excludes zero and
        /// there is enough independent data behind it.
        var isSignificant: Bool { pValue < 0.05 && effectiveN >= 8 }

        func predicted(at x: Double) -> Double { intercept + slope * x }
    }

    /// Ordinary least squares of y on x.
    static func linearRegression(x: [Double], y: [Double]) -> Regression? {
        let n = min(x.count, y.count)
        guard n >= 3 else { return nil }
        let a = Array(x.prefix(n))
        let b = Array(y.prefix(n))
        guard let mx = mean(a), let my = mean(b) else { return nil }

        var sxx = 0.0, sxy = 0.0, syy = 0.0
        for i in 0..<n {
            let dx = a[i] - mx
            let dy = b[i] - my
            sxx += dx * dx
            sxy += dx * dy
            syy += dy * dy
        }
        guard sxx > 0 else { return nil }

        let slope = sxy / sxx
        let intercept = my - slope * mx
        let rSquared = syy > 0 ? (sxy * sxy) / (sxx * syy) : 0

        // Residual standard error, then the slope's standard error.
        var residuals: [Double] = []
        residuals.reserveCapacity(n)
        var residualSS = 0.0
        for i in 0..<n {
            let residual = b[i] - (intercept + slope * a[i])
            residuals.append(residual)
            residualSS += residual * residual
        }
        let dfForError = max(1.0, Double(n) - 2)
        let residualVariance = residualSS / dfForError

        // Serial dependence is a property of the RESIDUALS, not of the predictor.
        //
        // This distinction is easy to get wrong and badly consequential. When
        // regressing a metric against time, the predictor is 0, 1, 2, ... which is
        // almost perfectly autocorrelated by construction. Correcting for that would
        // report a clear multi-month trend as statistically meaningless. What
        // actually inflates a slope's uncertainty is autocorrelated residuals: if
        // consecutive deviations from the fitted line track each other, the data
        // carries less independent information about the slope than n suggests.
        //
        // So: inflate the slope's standard error by sqrt((1 + r) / (1 - r)) on the
        // lag-1 autocorrelation of the residuals, the first-order correction.
        let residualAutocorrelation = (autocorrelation(residuals) ?? 0).clamped(to: 0...0.95)
        let inflation = sqrt((1 + residualAutocorrelation) / (1 - residualAutocorrelation))
        let slopeSE = sqrt(residualVariance / sxx) * inflation

        let effectiveN = effectiveSampleSize(n, autocorrelation: residualAutocorrelation)
        let df = max(0.0001, Double(n) - 2)
        let t = slopeSE > 0 ? abs(slope) / slopeSE : 0
        let p = studentTTwoTailed(t: t, df: df)

        return Regression(slope: slope, intercept: intercept, rSquared: rSquared,
                          slopeStandardError: slopeSE, n: n, effectiveN: effectiveN, pValue: p)
    }

    /// Regress a series against its own index, the common "is this trending" case.
    static func trend(_ values: [Double]) -> Regression? {
        linearRegression(x: values.indices.map(Double.init), y: values)
    }

    // MARK: - Theil-Sen (robust slope)

    /// Theil-Sen estimator: the MEDIAN of the slopes of all point pairs.
    ///
    /// Chosen for short personal series because it tolerates up to about 29 percent
    /// arbitrarily bad points before breaking down, where least squares can be
    /// derailed by one. Use it whenever a reported slope will be shown to the user.
    ///
    /// Cost is O(n^2), which is irrelevant at the scale of a few hundred days.
    static func theilSenSlope(x: [Double], y: [Double]) -> Double? {
        let n = min(x.count, y.count)
        guard n >= 3 else { return nil }
        var slopes: [Double] = []
        slopes.reserveCapacity(n * (n - 1) / 2)
        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                let dx = x[j] - x[i]
                guard abs(dx) > 1e-12 else { continue }
                slopes.append((y[j] - y[i]) / dx)
            }
        }
        return median(slopes)
    }

    /// Theil-Sen slope plus the matching robust intercept, taken as the median of
    /// the residuals `y_i - slope * x_i`.
    ///
    /// This is the "joint" intercept variant (it matches SciPy's
    /// `theilslopes(..., method: "joint")`). The alternative "separate" variant uses
    /// `median(y) - slope * median(x)`. Joint is preferred here because the intercept
    /// is used to draw a fitted line through the data, and the median of residuals is
    /// the estimate that minimises absolute deviation from the points.
    static func theilSen(x: [Double], y: [Double]) -> (slope: Double, intercept: Double)? {
        guard let slope = theilSenSlope(x: x, y: y) else { return nil }
        let n = min(x.count, y.count)
        let residuals = (0..<n).map { y[$0] - slope * x[$0] }
        guard let intercept = median(residuals) else { return nil }
        return (slope, intercept)
    }

    static func theilSenTrend(_ values: [Double]) -> (slope: Double, intercept: Double)? {
        theilSen(x: values.indices.map(Double.init), y: values)
    }

    // MARK: - Mann-Kendall trend test

    struct TrendTest: Hashable, Sendable {
        /// The Mann-Kendall S statistic: positive means an upward tendency.
        var s: Double
        /// Kendall's tau, S normalized to -1...1, which is the effect size.
        var tau: Double
        var z: Double
        var pValue: Double
        var n: Int
        /// Robust slope in units per sample, from Theil-Sen.
        var slopePerSample: Double?

        enum Direction: String, Sendable { case increasing, decreasing, none }

        var direction: Direction {
            guard pValue < 0.05 else { return .none }
            return s > 0 ? .increasing : .decreasing
        }

        var isSignificant: Bool { pValue < 0.05 && n >= 10 }
    }

    /// Mann-Kendall test for a monotone trend, with the tie correction and the
    /// continuity correction on S.
    ///
    /// Non-parametric, so it makes no assumption that the data or the trend is
    /// linear, only that any trend is monotone. That is the right assumption for
    /// "has my resting heart rate been creeping up".
    ///
    ///     S = sum over i < j of sign(x_j - x_i)
    ///     Var(S) = [ n(n-1)(2n+5) - sum over tie groups p of t_p(t_p-1)(2t_p+5) ] / 18
    ///     z = (S - 1)/sqrt(Var)  for S > 0
    ///         (S + 1)/sqrt(Var)  for S < 0
    ///         0                  for S = 0
    ///
    /// The +/-1 is the continuity correction, which stops small samples from
    /// producing overconfident p-values.
    static func mannKendall(_ values: [Double]) -> TrendTest? {
        let n = values.count
        guard n >= 8 else { return nil }

        var s = 0.0
        for i in 0..<(n - 1) {
            for j in (i + 1)..<n {
                let d = values[j] - values[i]
                s += d > 0 ? 1 : (d < 0 ? -1 : 0)
            }
        }

        let nd = Double(n)
        var variance = nd * (nd - 1) * (2 * nd + 5) / 18
        for t in tieGroupSizes(values) {
            let td = Double(t)
            variance -= td * (td - 1) * (2 * td + 5) / 18
        }
        guard variance > 0 else { return nil }

        let z: Double
        if s > 0 { z = (s - 1) / sqrt(variance) }
        else if s < 0 { z = (s + 1) / sqrt(variance) }
        else { z = 0 }

        let p = 2 * (1 - normalCDF(abs(z)))
        let tau = s / (nd * (nd - 1) / 2)

        return TrendTest(s: s, tau: tau, z: z, pValue: p.clamped(to: 0...1),
                         n: n, slopePerSample: theilSenTrend(values)?.slope)
    }

    // MARK: - Change-point detection

    struct ChangePoint: Hashable, Sendable {
        /// Index in the series where the shift is detected.
        var index: Int
        /// Mean before and after the detected shift.
        var meanBefore: Double
        var meanAfter: Double
        /// Shift size in units of the pre-shift standard deviation.
        var magnitudeInSD: Double
        var isUpward: Bool { meanAfter > meanBefore }
    }

    /// Two-sided CUSUM (cumulative sum) change detection on a standardized series.
    ///
    /// Walks the series accumulating deviations from a reference mean, allowing a
    /// slack of `k` standard deviations, and flags the first point where the running
    /// sum exceeds `h`. The classic parameters are k = 0.5 (half a standard
    /// deviation of slack) and h = 4 or 5, which is tuned to catch a sustained
    /// one-sigma shift quickly without firing on single outliers.
    ///
    /// Preferred over "compare this week to last week" because it accumulates weak
    /// evidence over time: a small but persistent drift is exactly what a personal
    /// baseline shift looks like, and a two-window comparison misses it.
    static func cusumChangePoint(
        _ values: [Double],
        referenceWindow: Int = 14,
        k: Double = 0.5,
        h: Double = 4.0
    ) -> ChangePoint? {
        guard values.count >= referenceWindow + 7 else { return nil }
        let reference = Array(values.prefix(referenceWindow))
        guard let mu = mean(reference), let sd = standardDeviation(reference), sd > 0 else {
            return nil
        }

        var high = 0.0
        var low = 0.0
        for i in referenceWindow..<values.count {
            let z = (values[i] - mu) / sd
            high = max(0, high + z - k)
            low = max(0, low - z - k)
            if high > h || low > h {
                let before = Array(values[0..<i])
                let after = Array(values[i...])
                guard let mb = mean(before), let ma = mean(after) else { return nil }
                return ChangePoint(index: i, meanBefore: mb, meanAfter: ma,
                                   magnitudeInSD: (ma - mb) / sd)
            }
        }
        return nil
    }

    // MARK: - Distributions

    /// Standard normal cumulative distribution function.
    ///
    /// Uses the C library's `erf`, which is accurate to full double precision, in
    /// preference to a polynomial approximation. Phi(x) = (1 + erf(x / sqrt 2)) / 2.
    static func normalCDF(_ x: Double) -> Double {
        0.5 * (1 + erf(x / 1.4142135623730951))
    }

    /// Inverse standard normal CDF, via the Acklam rational approximation refined by
    /// one Halley step against `normalCDF`. Accurate to better than 1e-9, which is
    /// far more than enough for confidence bands.
    static func normalQuantile(_ p: Double) -> Double {
        let pp = p.clamped(to: 1e-12...(1 - 1e-12))

        let a = [-3.969683028665376e+01, 2.209460984245205e+02, -2.759285104469687e+02,
                  1.383577518672690e+02, -3.066479806614716e+01, 2.506628277459239e+00]
        let b = [-5.447609879822406e+01, 1.615858368580409e+02, -1.556989798598866e+02,
                  6.680131188771972e+01, -1.328068155288572e+01]
        let c = [-7.784894002430293e-03, -3.223964580411365e-01, -2.400758277161838e+00,
                 -2.549732539343734e+00, 4.374664141464968e+00, 2.938163982698783e+00]
        let d = [7.784695709041462e-03, 3.224671290700398e-01, 2.445134137142996e+00,
                 3.754408661907416e+00]

        let pLow = 0.02425
        var x: Double
        if pp < pLow {
            let q = sqrt(-2 * log(pp))
            x = (((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
              / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        } else if pp <= 1 - pLow {
            let q = pp - 0.5
            let r = q * q
            x = (((((a[0] * r + a[1]) * r + a[2]) * r + a[3]) * r + a[4]) * r + a[5]) * q
              / (((((b[0] * r + b[1]) * r + b[2]) * r + b[3]) * r + b[4]) * r + 1)
        } else {
            let q = sqrt(-2 * log(1 - pp))
            x = -(((((c[0] * q + c[1]) * q + c[2]) * q + c[3]) * q + c[4]) * q + c[5])
               / ((((d[0] * q + d[1]) * q + d[2]) * q + d[3]) * q + 1)
        }

        // One Halley refinement.
        let e = normalCDF(x) - pp
        let u = e * 2.5066282746310002 * exp(x * x / 2)
        x -= u / (1 + x * u / 2)
        return x
    }

    /// Two-tailed p-value for Student's t with (possibly fractional) `df`.
    ///
    ///     p = I_{df / (df + t^2)}(df/2, 1/2)
    ///
    /// where I is the regularized incomplete beta function. Exact rather than
    /// table-driven, which matters because the effective sample sizes in this app are
    /// fractional and small.
    static func studentTTwoTailed(t: Double, df: Double) -> Double {
        guard df > 0, t.isFinite else { return 1 }
        let tt = abs(t)
        guard tt > 0 else { return 1 }
        let x = df / (df + tt * tt)
        return incompleteBeta(a: df / 2, b: 0.5, x: x).clamped(to: 0...1)
    }

    /// Critical two-tailed t value, found by bisection on `studentTTwoTailed`.
    /// Handles fractional degrees of freedom, which no printed table does.
    static func studentTCriticalValue(df: Double, twoTailedAlpha: Double = 0.05) -> Double {
        guard df > 0 else { return .infinity }
        var lo = 0.0
        var hi = 200.0
        for _ in 0..<200 {
            let mid = (lo + hi) / 2
            if studentTTwoTailed(t: mid, df: df) > twoTailedAlpha { lo = mid } else { hi = mid }
        }
        return (lo + hi) / 2
    }

    /// Regularized incomplete beta function I_x(a, b), by the continued-fraction
    /// expansion with the standard symmetry reflection for fast convergence.
    /// Follows the formulation in Numerical Recipes (betai / betacf).
    static func incompleteBeta(a: Double, b: Double, x: Double) -> Double {
        guard x > 0 else { return 0 }
        guard x < 1 else { return 1 }
        // exp(ln B(a,b)^-1 + a ln x + b ln(1-x)), the prefactor common to both
        // branches. Computed in log space so extreme a or b cannot overflow.
        let logBeta: Double = lgamma(a + b) - lgamma(a) - lgamma(b)
        let logFront: Double = logBeta + a * log(x) + b * log1p(-x)
        let front: Double = exp(logFront)

        // The continued fraction converges quickly only for x < (a+1)/(a+b+2);
        // beyond that use the symmetry I_x(a,b) = 1 - I_{1-x}(b,a).
        let threshold: Double = (a + 1) / (a + b + 2)
        if x < threshold {
            let cf: Double = betaContinuedFraction(a: a, b: b, x: x)
            return front * cf / a
        }
        let cf: Double = betaContinuedFraction(a: b, b: a, x: 1 - x)
        return 1 - front * cf / b
    }

    /// Lentz's modified continued fraction for the incomplete beta.
    private static func betaContinuedFraction(a: Double, b: Double, x: Double) -> Double {
        let tiny = 1e-30
        let epsilon = 3e-14
        let qab = a + b, qap = a + 1, qam = a - 1

        var c = 1.0
        var d = 1 - qab * x / qap
        if abs(d) < tiny { d = tiny }
        d = 1 / d
        var h = d

        for m in 1...300 {
            let md = Double(m)
            let m2 = 2 * md

            // Even step.
            var aa = md * (b - md) * x / ((qam + m2) * (a + m2))
            d = 1 + aa * d
            if abs(d) < tiny { d = tiny }
            c = 1 + aa / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            h *= d * c

            // Odd step.
            aa = -(a + md) * (qab + md) * x / ((a + m2) * (qap + m2))
            d = 1 + aa * d
            if abs(d) < tiny { d = tiny }
            c = 1 + aa / c
            if abs(c) < tiny { c = tiny }
            d = 1 / d
            let delta = d * c
            h *= delta

            if abs(delta - 1) < epsilon { break }
        }
        return h
    }

    // MARK: - Smallest worthwhile change

    /// The smallest change in a personal series worth reacting to.
    ///
    /// Sports-science practice (Hopkins; and specifically Plews and colleagues for
    /// heart-rate variability monitoring) is to treat a change as meaningful only
    /// once it exceeds a fraction of the athlete's own between-day variability,
    /// commonly 0.5 standard deviations. Anything smaller is inside the noise this
    /// person's data produces anyway.
    ///
    /// Using the robust spread (scaled MAD) rather than SD means one anomalous day
    /// does not widen the band and hide a real change.
    static func smallestWorthwhileChange(_ baseline: [Double], multiplier: Double = 0.5) -> Double? {
        guard let spread = medianAbsoluteDeviation(baseline), spread > 0 else {
            return standardDeviation(baseline).map { $0 * multiplier }
        }
        return spread * multiplier
    }

    /// Whether `value` sits meaningfully outside a baseline, and in which direction.
    /// Returns nil when the baseline is too thin to judge against.
    static func meaningfulDeviation(
        value: Double,
        baseline: [Double],
        multiplier: Double = 0.5,
        minimumBaselineCount: Int = 10
    ) -> (isDeviation: Bool, delta: Double, threshold: Double)? {
        guard baseline.count >= minimumBaselineCount,
              let center = median(baseline),
              let threshold = smallestWorthwhileChange(baseline, multiplier: multiplier),
              threshold > 0
        else { return nil }
        let delta = value - center
        return (abs(delta) >= threshold, delta, threshold)
    }

    // MARK: - Misc

    /// Sum with nils skipped, returning nil when nothing was present. Keeps
    /// "unmeasured" from becoming zero.
    static func sumIgnoringNils(_ values: [Double?]) -> Double? {
        let present = values.compactMap { $0 }
        return present.isEmpty ? nil : present.reduce(0, +)
    }

    /// Mean with nils skipped.
    static func meanIgnoringNils(_ values: [Double?]) -> Double? {
        mean(values.compactMap { $0 })
    }

    /// Linear interpolation across interior gaps in a daily series, used only where
    /// a calculation genuinely requires an unbroken series (an exponentially
    /// weighted load model, for instance). Leading and trailing gaps are left nil,
    /// because extrapolating beyond the data would be inventing it. Gaps longer than
    /// `maxGap` are also left alone.
    static func interpolateGaps(_ values: [Double?], maxGap: Int = 3) -> [Double?] {
        var result = values
        var lastKnown: Int?
        for i in values.indices {
            guard values[i] != nil else { continue }
            if let previous = lastKnown, i - previous > 1, i - previous - 1 <= maxGap {
                let a = values[previous]!
                let b = values[i]!
                let steps = i - previous
                for offset in 1..<steps {
                    result[previous + offset] = a + (b - a) * Double(offset) / Double(steps)
                }
            }
            lastKnown = i
        }
        return result
    }
}
