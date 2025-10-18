def format_scan_to_md(res: dict)->str:
    L=[]; L.append(f"📊 扫描完成 {res['ts']}"); L.append(f"基础池样本：{res['pool_size']}"); L.append("Top：")
    for r in res["top"]:
        L.append(f"• {r['symbol']} | Trend {r['score_trend']:.0f} / Struct {r['score_struct']:.0f} / Flow {r['score_flow']:.0f} → {r['score_total']:.2f}")
    if res["a_plus"]:
        L.append("✅ A+ 候选：")
        for r in res["a_plus"]:
            L.append(f"  - {r['symbol']} | {r['score_total']:.2f} | Gates=Y")
    else:
        L.append("❎ 本轮无 A+（≥90 且四闸全过）")
    return "\n".join(L)