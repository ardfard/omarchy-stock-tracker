# 📈 Stock Tracker — US + IDX for Omarchy

A Quattro bar-widget plugin that tracks **US (NYSE/NASDAQ)** and **Indonesian (IDX / BEI)** stocks & indices **live in the Omarchy bar**, with a rich detail panel.

> **ID:** `io.github.ardfard.stock-tracker` • **Kind:** `bar-widget` • **Data:** Yahoo Finance (no API key)

![license MIT](https://img.shields.io/badge/license-MIT-green) ![omarchy](https://img.shields.io/badge/omarchy-quattro-black)

---

## ✨ Features

- **US + IDX in one ticker**
  - US: `AAPL`, `NVDA`, `MSFT`, `GOOGL`, `TSLA`, `SPY`, indices `^GSPC` (S&P 500), `^IXIC` (NASDAQ), `^DJI` (Dow)
  - IDX: `BBCA.JK`, `BBRI.JK`, `BMRI.JK`, `TLKM.JK`, `ASII.JK`, `GOTO.JK`, index `^JKSE` (IHSG / IDX Composite), also `^JK.LQ45`
- **Bar widget** — compact ticker (e.g. `AAPL +2.19% • BBCA.JK +0.79% • ^JKSE +0.28%`) with auto-refresh. Shows 1–4 symbols, configurable.
- **Detail panel** — click the bar to open:
  - All / US / IDX filter tabs
  - Price in native currency (`$` for US, `Rp` for IDX), change & percent with green/red
  - Add / remove symbols inline, persists to `shell.json`
  - Quick presets: US Tech, US Indices, IDX Blue Chip, IDX Indices, US+IDX Mix
  - Refresh interval: 1 / 2 / 5 / 10 minutes, manual ↻
  - Opens Yahoo Finance on ↗
- **No API key** — uses Yahoo Finance `v7/spark` (`query1.finance.yahoo.com`) which works anonymously for both exchanges (verified to return IDR & USD in one batch). No `.env` needed.
- **Shell-native** — `Process + curl` (not `XMLHttpRequest`), `Panel`/`KeyboardPanel`/`PanelKeyCatcher`, `IpcHandler` for `omarchy-shell shell summon/hide`, persists via `setting()` + `updateEntryInline`.

---

## 🚀 Quick Start (local dev)

This repo **is** the plugin folder — drop it as-is:

```bash
# 1. Install to your Omarchy config (pick one)
# Option A — clone directly
git clone https://github.com/ardfard/omarchy-stock-tracker ~/.config/omarchy/plugins/io.github.ardfard.stock-tracker

# Option B — copy this folder
cp -r /path/to/omarchy-stock-tracker ~/.config/omarchy/plugins/io.github.ardfard.stock-tracker

# 2. Force discovery (usually auto)
omarchy-shell shell rescanPlugins

# 3. Enable in the bar (if not auto-placed)
# Edit ~/.config/omarchy/shell.json or use the Omarchy bar settings UI to enable
# "Stock Tracker" in the center section.

# 4. Validate (should be silent = OK)
omarchy plugin validate ~/.config/omarchy/plugins/io.github.ardfard.stock-tracker
qmllint -I "$OMARCHY_PATH/shell" ~/.config/omarchy/plugins/io.github.ardfard.stock-tracker/BarWidget.qml ~/.config/omarchy/plugins/io.github.ardfard.stock-tracker/Panel.qml

# 5. Test panel lifecycle
omarchy-shell shell summon io.github.ardfard.stock-tracker '{}'
omarchy-shell shell hide    io.github.ardfard.stock-tracker
```

Already have a clone via `omarchy plugin clone omarchy.clock --edit`? Just replace its `manifest.json`/`BarWidget.qml`/`Panel.qml`/`Model.js` with these files and keep the same ID.

## Remove

```bash
omarchy plugin disable io.github.ardfard.stock-tracker
omarchy plugin remove io.github.ardfard.stock-tracker
# or, if `plugin remove` is unavailable on your Omarchy version:
rm -rf ~/.config/omarchy/plugins/io.github.ardfard.stock-tracker
omarchy shell shell rescanPlugins
```

## License

MIT — see [LICENSE](LICENSE).

---

## ⚙️ Configuration

Stored in `~/.config/omarchy/shell.json` under `io.github.ardfard.stock-tracker`:

```json
{
  "id": "io.github.ardfard.stock-tracker",
  "symbols": ["AAPL","NVDA","^GSPC","BBCA.JK","BBRI.JK","^JKSE","GOTO.JK"],
  "refreshMinutes": 2,
  "barMaxItems": 3,
  "compactMode": "change"
}
```

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `symbols` | `string[]` or CSV string | `defaultSymbols()` (8) | Max 20. US = plain (AAPL), IDX = `.JK` suffix (BBCA.JK), indices = `^` prefix (^JKSE, ^GSPC). Deduped, normalized to upper-case. |
| `refreshMinutes` | int | `2` | Clamped 1–60. Also adjustable in-panel via 1m/2m/5m/10m pills. |
| `barMaxItems` | int | `3` | How many symbols the bar shows (1–4). |
| `compactMode` | string | `"change"` | `change` = `AAPL +1.2%`, `price` = `AAPL $316.83`, `both` = `AAPL $316.83 +1.2%`. |

You can also edit the watchlist live in the panel: type `AAPL, NVDA, BBCA.JK` or `^JKSE` and hit **Add** / Enter.

---

## 🇺🇸 🇮🇩 Symbol Cheat-sheet

**Yahoo Finance suffix matters:**
- US equities/ETFs: no suffix → `AAPL`, `MSFT`, `SPY`, `NVDA`
- US indices: caret → `^GSPC`, `^IXIC`, `^DJI`, `^RUT` (Russell 2000), `^VIX`
- IDX equities: `.JK` → `BBCA.JK` (BCA), `BBRI.JK` (BRI), `BMRI.JK` (Mandiri), `BBNI.JK`, `TLKM.JK` (Telkom), `ASII.JK` (Astra), `GOTO.JK` (GoTo), `UNVR.JK`
- IDX indices: `^JKSE` (IHSG Composite), `^JK.LQ45` (LQ45)

Tips:
- Searching a new IDX stock? In Yahoo Finance search the ticker + `JK` (e.g. "TLKM") and copy the `XXXX.JK` symbol.
- ADRs like `TLK` (Telkom NYSE) are US-listed — track them as `TLK` if you want USD price vs `TLKM.JK` for IDR.

---

## 🧩 Bar Interactions

- **Left click** → toggle detail panel
- **Right click** → instant refresh (bypasses timer)
- **Middle click** → `xdg-open https://finance.yahoo.com/quote/<first-symbol>`
- **Hover** → tooltip = full watchlist + last updated time

---

## 🛠 Architecture

```
~/.config/omarchy/plugins/io.github.ardfard.stock-tracker/
├── manifest.json   # omarchy contract (bar-widget, entryPoints.barWidget)
├── BarWidget.qml   # bar ticker, Timer, Process(curl → spark), Loader(Panel.qml), IpcHandler
├── Panel.qml       # KeyboardPanel + Flickable list, add/remove, presets, refresh pills
└── Model.js        # pure JS: normalize/parse symbols, Yahoo URLs, spark meta → quote, formatting
```

Data flow:
1. `BarWidget` builds `watchlist` from `setting("symbols")`, calls `https://query1.finance.yahoo.com/v7/finance/spark?symbols=…&range=1d&interval=1d` via `Process { curl -H User-Agent: Mozilla/5.0 }`
2. `Model.parseYahooSparkResponse` turns `spark.result[].response[0].meta` into `{symbol, price, change, changePercent, currency, …}` and `mergeQuotes` preserves user order (fills UNKNOWN for missing).
3. `Panel` mirrors `quotes` but can also fetch independently; both share the same `persistSymbols()` path (`settings` + `bar.shell.updateEntryInline`).
4. No second Quickshell process, no privileged ops, no secrets — respects the omarchyplugins.com sandbox note.

**Why `spark` not `quote`?** Yahoo's `v7/quote` now returns `401` anonymously; `v7/spark` and `v8/chart` still serve anonymously with a plain `User-Agent` and return identical `regularMarketPrice` + `chartPreviousClose` (verified for `.JK` & `^JKSE`).

---

## 🎨 Panel Layout

- Header: title + `◷/HH:mm:ss` + error banner
- Action row: `↻ Refresh` + `All/US/IDX` pills + count
- List: each row = badge (blue US / amber IDX) + name + price + percent (green/red) + `↗` + `×`
- Add row: `TextInput` + `Add`
- Presets: `US Tech` `US Indices` `IDX Blue Chip` `IDX Indices` `US+IDX Mix`
- Footer: refresh pills + hints + Yahoo attribution

Colors use `Style.accent`, `Color.alpha`, `Style.space`, `Style.font` — fully theme-aware.

---

## 📦 Publish to omarchyplugins.com

1. Push this repo to `github.com/<you>/omarchy-stock-tracker` (public)
2. Ensure `manifest.json` has a permanent namespaced `id` (already `io.github.ardfard.stock-tracker`) and no `omarchy.clonedFrom`
3. Follow https://omarchyplugins.com/publish.html → submit via GitHub issue `submit-plugin.yml`

Marketplace checks: `schemaVersion/kinds/entryPoints`, file existence, no symlinks, no `omarchy.*` ID, QML lint.

---

## 🔍 Troubleshooting

| Symptom | Fix |
|--------|-----|
| `entry point file not found: BarWidget.qml` | Ensure `manifest.json → entryPoints.barWidget` exactly matches filename case |
| Validates but not listed | `omarchy-shell shell rescanPlugins` then `omarchy plugin list --json \| jq` |
| Listed but not visible | Enable in bar settings; check `qs log -p "$OMARCHY_PATH/shell" --tail 100` for QML errors |
| Panel opens once | Ensure `opened/open()/close()/popoutSwitchClosing/closeForPopoutSwitch` are forwarded from `BarWidget` to `Panel` (already done) |
| `offline` / `Fetch failed` | No network or Yahoo throttled. Panel retries after 15s; bar retries. `curl -H "User-Agent: Mozilla/5.0" "https://query1.finance.yahoo.com/v7/finance/spark?symbols=AAPL"` should return JSON. |
| IDX symbol shows `UNKNOWN` | Check suffix — IDX must be `.JK` and upper-case, e.g. `BBCA.JK` not `BBCA`. |
| Price shows `--` | Market closed / Yahoo returned null; still shows previous close percent once market reopens. |

---

## 📄 License

MIT — see [LICENSE](./LICENSE). Yahoo Finance data is © Yahoo.

---

## 🙏 Credits

Built from the Omarchy clock/weather patterns and the `develop.html` bar-widget contract. Market data by Yahoo Finance — no affiliation.
