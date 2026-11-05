"""Menjalankan sql/05_analisis_bisnis.sql, menyimpan hasil ke CSV, membuat grafik, dan uji statistik.

Jalankan dari folder project (venv aktif):
    python src/run_analysis.py
Opsional: argumen ke-1 = lokasi database lain.

Keluaran:
    reports/tables/*.csv           hasil tiap query
    reports/tables/uji_statistik.txt
    reports/figures/*.png          grafik untuk laporan dan README
"""
import re
import sys
import textwrap
from pathlib import Path

import duckdb
import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import pandas as pd
from scipy import stats

ROOT = Path(__file__).resolve().parent.parent
DB = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "olist.duckdb"
TABLES = ROOT / "reports" / "tables"
FIGS = ROOT / "reports" / "figures"
TABLES.mkdir(parents=True, exist_ok=True)
FIGS.mkdir(parents=True, exist_ok=True)

# --- Palet (referensi dataviz: seri 1 biru, seri 2 oranye, kutub negatif merah) ---
BLUE, ORANGE, RED = "#2a78d6", "#eb6834", "#e34948"
SURFACE, INK, INK2, MUTED, GRID, AXIS = "#fcfcfb", "#0b0b0b", "#52514e", "#898781", "#e1e0d9", "#c3c2b7"

plt.rcParams.update({
    "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
    "font.family": "sans-serif", "font.size": 10,
    "text.color": INK, "axes.labelcolor": INK2, "xtick.color": MUTED, "ytick.color": MUTED,
    "axes.edgecolor": AXIS, "axes.spines.top": False, "axes.spines.right": False,
    "axes.grid": True, "grid.color": GRID, "grid.linewidth": 0.6, "axes.axisbelow": True,
})


def rupiah_juta(x, _=None):
    return f"{x / 1e6:.1f} jt"


def judul(ax, teks, sub=None):
    teks = textwrap.fill(teks, 70)          # judul panjang dibungkus agar tidak melebar
    ax.set_title(teks, loc="left", fontsize=13, fontweight="bold", color=INK, pad=22 if sub else 10)
    if sub:
        ax.text(0, 1.03, sub, transform=ax.transAxes, fontsize=9.5, color=INK2, va="bottom")


def simpan(fig, nama):
    fig.savefig(FIGS / nama, dpi=150, bbox_inches="tight")
    plt.close(fig)
    print("  grafik:", nama)


# ------------------------------------------------------------------ 1. jalankan SQL
sql_text = (ROOT / "sql" / "05_analisis_bisnis.sql").read_text(encoding="utf-8")
parts = re.split(r"^-- ---------- (Q\w+)\. [^\n]*\n", sql_text, flags=re.M)
blocks = dict(zip(parts[1::2], parts[2::2]))      # {"Q1": "SELECT ...", ...}

con = duckdb.connect(str(DB), read_only=True)
ada = {r[0] for r in con.execute("SELECT table_name FROM information_schema.tables").fetchall()}
if "clean_orders" not in ada:
    sys.exit("Tabel clean_* belum ada. Jalankan dulu: python src/build_clean.py")
res = {}
nama_csv = {"Q1": "q1_tren_bulanan", "Q2": "q2_top10_kategori", "Q3a": "q3a_ringkasan_keterlambatan",
            "Q3b": "q3b_distribusi_keterlambatan", "Q4": "q4_skor_tepat_waktu_vs_terlambat",
            "Q4b": "q4b_skor_per_bucket_keterlambatan", "Q5": "q5_per_negara_bagian",
            "Q6": "q6_pelanggan_repeat", "Q6b": "q6b_repeat_vs_skor_order_pertama"}
print("Menjalankan query:")
for k, sql in blocks.items():
    res[k] = con.execute(sql).df()
    res[k].to_csv(TABLES / f"{nama_csv[k]}.csv", index=False)
    print(f"  {k:<4} {len(res[k]):>3} baris -> {nama_csv[k]}.csv")

# ------------------------------------------------------------------ 2. uji statistik
skor = con.execute("""
    SELECT o.is_late, r.review_score
    FROM clean_orders o JOIN clean_order_reviews r USING (order_id)
    WHERE o.is_analysis_scope
""").df()
telat = skor.loc[skor.is_late, "review_score"].to_numpy()
tepat = skor.loc[~skor.is_late, "review_score"].to_numpy()
u, p_mw = stats.mannwhitneyu(telat, tepat, alternative="two-sided")
t, p_t = stats.ttest_ind(telat, tepat, equal_var=False)
sp = np.sqrt(((len(telat) - 1) * telat.var(ddof=1) + (len(tepat) - 1) * tepat.var(ddof=1)) / (len(telat) + len(tepat) - 2))
d = (telat.mean() - tepat.mean()) / sp
rank_biserial = 1 - 2 * u / (len(telat) * len(tepat))

b6 = con.execute("""
    WITH urutan AS (
        SELECT c.customer_unique_id, o.order_id,
               ROW_NUMBER() OVER (PARTITION BY c.customer_unique_id ORDER BY o.order_purchase_timestamp, o.order_id) AS urutan_order,
               COUNT(*) OVER (PARTITION BY c.customer_unique_id) AS total_order
        FROM clean_orders o JOIN customers c USING (customer_id)
        WHERE o.order_status NOT IN ('canceled', 'unavailable'))
    SELECT r.review_score, (u.total_order > 1) AS repeat
    FROM urutan u JOIN clean_order_reviews r USING (order_id) WHERE u.urutan_order = 1
""").df()
chi2, p_chi, dof, _ = stats.chi2_contingency(pd.crosstab(b6.review_score, b6.repeat))

def fmt_p(p):
    return "< 1e-300 (di bawah batas ketelitian komputer)" if p == 0 else f"{p:.3g}"


teks = f"""UJI STATISTIK (dihitung oleh src/run_analysis.py)

A. Skor review: order terlambat vs tepat waktu (ruang lingkup pengiriman)
   n terlambat = {len(telat):,} | n tepat waktu = {len(tepat):,}
   rata-rata skor: terlambat {telat.mean():.3f} vs tepat waktu {tepat.mean():.3f} (selisih {telat.mean() - tepat.mean():+.3f})
   Mann-Whitney U (dua sisi): p {('= ' + fmt_p(p_mw)) if p_mw else fmt_p(p_mw)}
   Welch t-test: t = {t:.1f}, p {('= ' + fmt_p(p_t)) if p_t else fmt_p(p_t)}
   Ukuran efek: Cohen's d = {d:.2f} | |rank-biserial| = {abs(rank_biserial):.2f} (efek besar bila > 0,5; skor terlambat lebih rendah)
   Catatan: dengan n sebesar ini p-value hampir pasti sangat kecil. Yang menentukan makna adalah ukuran efek.

B. Pembelian ulang vs skor review order pertama (uji chi-kuadrat independensi)
   chi2 = {chi2:.2f}, dof = {dof}, p = {p_chi:.3g}
   pct repeat per skor: {', '.join(f'{int(s)}: {v * 100:.2f}%' for s, v in b6.groupby('review_score').repeat.mean().items())}
"""
(TABLES / "uji_statistik.txt").write_text(teks, encoding="utf-8")
print("\n" + teks)

# ------------------------------------------------------------------ 3. grafik
print("Membuat grafik:")

# --- Gambar 1: tren bulanan (3 panel, tiap panel satu sumbu)
q1 = res["Q1"]
x = np.arange(len(q1))
fig, axs = plt.subplots(3, 1, figsize=(11, 9), sharex=True, gridspec_kw={"height_ratios": [3, 2, 2]})
ax = axs[0]
ax.plot(x, q1.pendapatan, color=BLUE, lw=2)
ax.fill_between(x, q1.pendapatan, color=BLUE, alpha=0.08)
ax.yaxis.set_major_formatter(rupiah_juta)
ax.set_ylabel("Pendapatan (BRL)")
ax.set_ylim(0, q1.pendapatan.max() * 1.1)
i_max = int(q1.pendapatan.idxmax())
ax.annotate(f"Puncak {q1.bulan[i_max]}\n{q1.pendapatan[i_max] / 1e6:.2f} jt", (i_max, q1.pendapatan[i_max]),
            xytext=(i_max - 3.6, q1.pendapatan[i_max] * 0.96), fontsize=9, color=INK2,
            arrowprops=dict(arrowstyle="-", color=MUTED))
judul(ax, "Pendapatan naik sekitar 7 kali lipat sejak Jan 2017, lalu mendatar sejak awal 2018",
      "Pendapatan dan jumlah order bulanan, Jan 2017 - Agu 2018 (tanpa order canceled/unavailable). Jan 2017 tidak punya pembanding MoM")
ax = axs[1]
ax.plot(x, q1.jumlah_order, color=BLUE, lw=2)
ax.set_ylabel("Jumlah order")
ax.set_ylim(0, q1.jumlah_order.max() * 1.1)
ax = axs[2]
mom = q1.mom_pendapatan_pct.fillna(0)
ax.bar(x, mom, color=[BLUE if v >= 0 else RED for v in mom], width=0.6)
ax.axhline(0, color=AXIS, lw=1)
ax.set_ylabel("MoM pendapatan (%)")
ax.set_xticks(x[::2])
ax.set_xticklabels(q1.bulan[::2], rotation=45, ha="right")
simpan(fig, "fig1_tren_bulanan.png")

# --- Gambar 2: top 10 kategori
q2 = res["Q2"].iloc[::-1]
fig, ax = plt.subplots(figsize=(10, 5.6))
ax.barh(q2.kategori, q2.pendapatan, color=BLUE, height=0.62)
ax.xaxis.set_major_formatter(rupiah_juta)
ax.grid(axis="y", visible=False)
for yi, (v, pct) in enumerate(zip(q2.pendapatan, q2.pct_total)):
    ax.text(v + q2.pendapatan.max() * 0.01, yi, f"{v / 1e6:.2f} jt  ({pct:.1f}%)", va="center", fontsize=9, color=INK2)
ax.set_xlim(0, q2.pendapatan.max() * 1.22)
ax.set_xlabel("Pendapatan (BRL)")
kum = res["Q2"].pct_kumulatif.iloc[-1]
judul(ax, f"10 kategori menyumbang {kum:.0f}% pendapatan, tanpa satu kategori yang dominan",
      "Pendapatan per kategori produk (angka dalam kurung = persen dari total semua kategori)")
simpan(fig, "fig2_top10_kategori.png")

# --- Gambar 3: distribusi keterlambatan
q3a, q3b = res["Q3a"].iloc[0], res["Q3b"]
fig, ax = plt.subplots(figsize=(9, 5))
lab = [s.split(". ", 1)[1] for s in q3b.bucket_keterlambatan]
ax.bar(lab, q3b.jumlah_order, color=BLUE, width=0.6)
ax.grid(axis="x", visible=False)
for xi, (n, pct) in enumerate(zip(q3b.jumlah_order, q3b.pct_dari_order_terlambat)):
    ax.text(xi, n + q3b.jumlah_order.max() * 0.015, f"{n:,}\n({pct:.1f}%)", ha="center", fontsize=9, color=INK2)
ax.set_ylim(0, q3b.jumlah_order.max() * 1.18)
ax.set_ylabel("Jumlah order terlambat")
judul(ax, f"{q3a.pct_terlambat:.1f}% order terlambat, dan 4 dari 10 di antaranya terlambat lebih dari 1 minggu",
      f"Distribusi hari keterlambatan terhadap estimasi ({int(q3a.order_terlambat):,} dari {int(q3a.order_dalam_scope):,} order). Median terlambat {q3a.median_hari_terlambat} hari")
simpan(fig, "fig3_distribusi_keterlambatan.png")

# --- Gambar 4: skor vs keterlambatan
q4b = res["Q4b"]
fig, ax = plt.subplots(figsize=(10, 5.2))
lab = [textwrap.fill(s.split(". ", 1)[1], 16) for s in q4b.kelompok]
ax.bar(lab, q4b.rata2_skor, color=BLUE, width=0.6)
ax.grid(axis="x", visible=False)
for xi, (v, n) in enumerate(zip(q4b.rata2_skor, q4b.order_ber_review)):
    ax.text(xi, v + 0.06, f"{v:.2f}", ha="center", fontsize=10, fontweight="bold", color=INK)
    ax.text(xi, 0.15, f"n={n:,}", ha="center", fontsize=8.5, color="#ffffff")
ax.set_ylim(0, 5)
ax.set_ylabel("Rata-rata review score (1-5)")
plt.setp(ax.get_xticklabels(), fontsize=9)
q4 = res["Q4"].set_index("status_pengiriman")
judul(ax, f"Keterlambatan menurunkan skor dari {q4.loc['Tepat waktu', 'rata2_skor']:.2f} menjadi {q4.loc['Terlambat', 'rata2_skor']:.2f}, dan jatuh tajam setelah 3 hari",
      "Rata-rata review score menurut lamanya keterlambatan (n = jumlah order ber-review)")
simpan(fig, "fig4_skor_vs_keterlambatan.png")

# --- Gambar 5: negara bagian
q5 = res["Q5"].dropna(subset=["pct_terlambat"])
fig, ax = plt.subplots(figsize=(10.5, 6.2))
ax.scatter(q5.pct_terlambat, q5.pendapatan, s=46, color=BLUE, edgecolor=SURFACE, linewidth=1.2, zorder=3)
ax.set_yscale("log")
ax.yaxis.set_major_formatter(lambda v, _: f"{v / 1e6:g} jt" if v >= 1e6 else f"{v / 1e3:g} rb")
ax.axvline(q3a.pct_terlambat, color=MUTED, lw=1, ls="--")
ax.text(q3a.pct_terlambat + 0.2, q5.pendapatan.min() * 1.1, f"rata-rata nasional {q3a.pct_terlambat:.1f}%", fontsize=8.5, color=INK2)
label = set(q5.nlargest(9, "pendapatan").negara_bagian) | set(q5.nlargest(4, "pct_terlambat").negara_bagian)
for _, r in q5.iterrows():
    if r.negara_bagian in label:
        ax.annotate(r.negara_bagian, (r.pct_terlambat, r.pendapatan), xytext=(6, 4), textcoords="offset points", fontsize=9, color=INK2)
ax.set_xlabel("Order terlambat (%)")
ax.set_ylabel("Pendapatan (BRL, skala log)")
judul(ax, "SP besar dan tepat waktu. RJ dan BA besar tetapi sering terlambat, AL dan MA paling lambat",
      "Pendapatan vs persentase keterlambatan per negara bagian pembeli (27 titik)")
simpan(fig, "fig5_negara_bagian.png")

# --- Gambar 6: pembelian ulang
q6, q6b = res["Q6"], res["Q6b"]
utama = q6[q6.definisi_order.str.contains("utama")].iloc[0]
fig, ax = plt.subplots(figsize=(8.5, 5))
ax.bar(q6b.skor_order_pertama.astype(str), q6b.pct_repeat, color=BLUE, width=0.6)
ax.grid(axis="x", visible=False)
for xi, v in enumerate(q6b.pct_repeat):
    ax.text(xi, v - 0.12, f"{v:.2f}%", ha="center", va="top", fontsize=10, fontweight="bold", color="#ffffff")
ax.axhline(utama.pct_repeat, color=MUTED, lw=1, ls="--", zorder=4)
ax.set_xlim(-0.5, 5.6)
ax.text(4.5, utama.pct_repeat, f"rata-rata\n{utama.pct_repeat:.2f}%", fontsize=9, color=INK2, ha="left", va="center")
ax.set_ylim(0, 5)
ax.set_xlabel("Skor review pada order pertama")
ax.set_ylabel("Pelanggan yang order lagi (%)")
judul(ax, f"Hanya {utama.pct_repeat:.1f}% pelanggan membeli lagi, dan skor order pertama hampir tidak memengaruhinya",
      "Persentase pelanggan dengan lebih dari 1 order menurut skor review order pertama")
simpan(fig, "fig6_pembelian_ulang.png")
con.close()
print("\nSelesai.")
