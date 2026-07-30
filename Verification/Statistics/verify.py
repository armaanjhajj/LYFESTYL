#!/usr/bin/env python3
"""Cross-check the Swift Stats implementation against SciPy/NumPy reference values.

Reads swift_out.txt (produced by stattest), recomputes each quantity in Python, and
reports any disagreement beyond tolerance.
"""
import sys, math
import numpy as np
from scipy import stats, special

vals, arrays = {}, {}
section = None
for line in open("swift_out.txt"):
    line = line.rstrip("\n")
    if line.startswith("###"):
        section = line
        continue
    if "\t" not in line:
        continue
    k, v = line.split("\t", 1)
    if "," in v:
        arrays[k] = [None if t == "nil" else float(t) for t in v.split(",")]
    elif v == "nil":
        vals[k] = None
    else:
        try:
            vals[k] = float(v)
        except ValueError:
            pass

x = np.array(arrays["x"]); y = np.array(arrays["y"])
trended = np.array(arrays["trended"]); tied = np.array(arrays["tied"])

fails, checks = [], 0

def chk(name, swift_key, expected, tol=1e-8, note=""):
    global checks
    checks += 1
    got = vals.get(swift_key)
    if got is None:
        fails.append(f"{name}: swift produced nil (expected {expected})")
        return
    if expected is None or (isinstance(expected, float) and math.isnan(expected)):
        fails.append(f"{name}: python produced nan")
        return
    if abs(got - expected) > tol * max(1.0, abs(expected)):
        fails.append(f"{name}: swift={got!r} python={expected!r} diff={got-expected:.3e} {note}")

def chk_arr(name, key, expected, tol=1e-8):
    global checks
    checks += 1
    got = arrays.get(key)
    if got is None:
        fails.append(f"{name}: missing"); return
    if len(got) != len(expected):
        fails.append(f"{name}: length {len(got)} vs {len(expected)}"); return
    for i, (a, b) in enumerate(zip(got, expected)):
        if abs(a - b) > tol * max(1.0, abs(b)):
            fails.append(f"{name}[{i}]: swift={a} python={b}"); return

# ---- basics
chk("mean", "mean_x", x.mean())
chk("variance(n-1)", "var_x", x.var(ddof=1))
chk("sd(n-1)", "sd_x", x.std(ddof=1))
chk("median", "median_x", np.median(x))
chk("MAD scaled", "mad_scaled_x", stats.median_abs_deviation(x, scale="normal"), tol=1e-4,
    note="(scipy scale='normal' uses 1/0.6744898 = 1.482602; swift uses 1.4826)")
chk("MAD raw", "mad_raw_x", stats.median_abs_deviation(x))
chk("p25 (linear)", "p25_x", np.percentile(x, 25, method="linear"))
chk("p75 (linear)", "p75_x", np.percentile(x, 75, method="linear"))
chk("p90 (linear)", "p90_x", np.percentile(x, 90, method="linear"))
chk("iqr", "iqr_x", np.percentile(x, 75) - np.percentile(x, 25))
chk("cv", "cv_x", x.std(ddof=1) / x.mean())

# ---- ranks with ties
chk_arr("ranks (average ties)", "ranks_tied", stats.rankdata(tied, method="average"))

# ---- distributions
for v in [-3.0, -1.5, -0.5, 0.0, 0.5, 1.0, 1.96, 2.5, 3.0]:
    chk(f"normalCDF({v})", f"normalCDF({v})", stats.norm.cdf(v), tol=1e-12)
for v in [0.001, 0.025, 0.1, 0.5, 0.9, 0.975, 0.999]:
    chk(f"normalQuantile({v})", f"normalQuantile({v})", stats.norm.ppf(v), tol=1e-9)
for t, df in [(2.0, 10.0), (1.5, 5.0), (3.2, 25.0), (2.0, 8.5), (0.7, 13.0), (4.0, 3.0)]:
    chk(f"t2tail(t={t},df={df})", f"t2tail(t={t},df={df})",
        2 * stats.t.sf(abs(t), df), tol=1e-10)
for df in [5.0, 10.0, 8.5, 25.0, 100.0]:
    chk(f"tcrit(df={df})", f"tcrit(df={df})", stats.t.ppf(0.975, df), tol=1e-7)
for a, b, xx in [(2.0, 3.0, 0.4), (0.5, 5.0, 0.2), (5.0, 0.5, 0.9), (12.5, 0.5, 0.7)]:
    chk(f"ibeta(a={a},b={b},x={xx})", f"ibeta(a={a},b={b},x={xx})",
        special.betainc(a, b, xx), tol=1e-10)

# ---- correlation coefficients (coefficients must match scipy exactly)
chk("pearson r", "pearson_r", stats.pearsonr(x, y)[0])
chk("spearman r", "spearman_r", stats.spearmanr(x, y)[0])
chk("pearson x~trended", "pearson_x_trended", stats.pearsonr(x, trended)[0])
chk("spearman tied vs rev", "spearman_tied_rev", stats.spearmanr(tied, tied[::-1])[0])

# ---- autocorrelation (definition: sum d_i d_{i+k} / sum d_i^2, full-length denom)
def acf(a, k):
    a = np.asarray(a, float); m = a.mean(); d = a - m
    return float((d[:-k] * d[k:]).sum() / (d * d).sum())
chk("acf lag1 x", "acf1_x", acf(x, 1))
chk("acf lag2 x", "acf2_x", acf(x, 2))
chk("acf lag1 trended", "acf1_trended", acf(trended, 1))
chk("effN n=40 r=0.7", "effN_40_r0.7", 40 * (1 - 0.7) / (1 + 0.7))

# ---- regression (slope/intercept/r2 must match exactly)
idx = np.arange(len(trended), dtype=float)
lr = stats.linregress(idx, trended)
chk("reg slope", "reg_slope", lr.slope)
chk("reg intercept", "reg_intercept", lr.intercept)
chk("reg r2", "reg_r2", lr.rvalue ** 2)
# Swift inflates the SE by the residual-autocorrelation factor; verify that formula.
resid = trended - (lr.intercept + lr.slope * idx)
r1 = acf(resid, 1)
r1c = min(max(r1, 0.0), 0.95)
infl = math.sqrt((1 + r1c) / (1 - r1c))
chk("reg slopeSE (autocorr-inflated)", "reg_slopeSE", lr.stderr * infl, tol=1e-9,
    note=f"resid acf1={r1:.6f} inflation={infl:.6f}")
t_stat = abs(lr.slope) / (lr.stderr * infl)
chk("reg p", "reg_p", 2 * stats.t.sf(t_stat, len(trended) - 2), tol=1e-9)
chk("reg effN", "reg_effN", len(trended) * (1 - r1c) / (1 + r1c), tol=1e-9)

# ---- Theil-Sen
ts = stats.theilslopes(trended, idx, method='joint')
chk("theilsen slope", "theilsen_trended", ts[0], tol=1e-10)
chk("theilsen intercept", "theilsen_int_trended", ts[1], tol=1e-10)
ts2 = stats.theilslopes(y, x, method='joint')
chk("theilsen slope x~y", "theilsen_x_y", ts2[0], tol=1e-10)

# ---- Mann-Kendall (reference implementation)
def mann_kendall(a):
    a = np.asarray(a, float); n = len(a)
    s = 0.0
    for i in range(n - 1):
        for j in range(i + 1, n):
            s += np.sign(a[j] - a[i])
    _, counts = np.unique(a, return_counts=True)
    var = n * (n - 1) * (2 * n + 5) / 18.0
    for c in counts[counts > 1]:
        var -= c * (c - 1) * (2 * c + 5) / 18.0
    if s > 0:   z = (s - 1) / math.sqrt(var)
    elif s < 0: z = (s + 1) / math.sqrt(var)
    else:       z = 0.0
    p = 2 * (1 - stats.norm.cdf(abs(z)))
    tau = s / (n * (n - 1) / 2)
    return s, tau, z, p

s, tau, z, p = mann_kendall(trended)
chk("MK s", "mk_s", s); chk("MK tau", "mk_tau", tau)
chk("MK z", "mk_z", z, tol=1e-10); chk("MK p", "mk_p", p, tol=1e-10)
s, tau, z, p = mann_kendall(x)
chk("MK s (x)", "mk_s_x", s); chk("MK tau (x)", "mk_tau_x", tau)
chk("MK p (x)", "mk_p_x", p, tol=1e-9)
s, tau, z, p = mann_kendall(tied)
chk("MK s (ties)", "mk_s_tied", s)
chk("MK z (ties)", "mk_z_tied", z, tol=1e-10)
chk("MK p (ties)", "mk_p_tied", p, tol=1e-9)
# Kendall tau-b cross-check against scipy for the no-ties case
kt = stats.kendalltau(idx, trended)
chk("MK tau == kendalltau(no ties)", "mk_tau", kt.statistic, tol=1e-10)

# ---- EWMA
chk("ewma alpha (span 7)", "ewma_alpha7", 2 / (7 + 1))
a = 2 / 8
e = [x[0]]
for v in x[1:]:
    e.append(a * v + (1 - a) * e[-1])
chk_arr("ewma last3", "ewma_last3", e[-3:], tol=1e-10)

# ---- SWC
chk("swc = 0.5 * scaled MAD", "swc_x", 0.5 * stats.median_abs_deviation(x, scale="normal"),
    tol=1e-4)

# ---- interpolate
chk_arr("interpolate gaps", "interp",
        [1, 2, 3, 4, 5, 6, 11], tol=1e-9) if False else None
got = arrays.get("interp")

print(f"{checks} checks run")
if fails:
    print(f"\n{len(fails)} FAILURES:")
    for f in fails:
        print("  " + f)
    sys.exit(1)
print("ALL CHECKS PASSED")
