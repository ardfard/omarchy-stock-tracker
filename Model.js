// Model helpers for stock tracker - pure JS, testable outside QML
function defaultSymbols() {
  // Mix of US + IDX covering both exchanges and indices
  return ["AAPL", "NVDA", "^GSPC", "^IXIC", "BBCA.JK", "BBRI.JK", "^JKSE", "GOTO.JK"]
}

function presets() {
  return [
    { id: "us-tech", label: "US Tech", symbols: ["AAPL","MSFT","NVDA","GOOGL","META","TSLA"] },
    { id: "us-indices", label: "US Indices", symbols: ["^GSPC","^IXIC","^DJI","^RUT"] },
    { id: "idx-bluechip", label: "IDX Blue Chip", symbols: ["BBCA.JK","BBRI.JK","BMRI.JK","TLKM.JK","ASII.JK","GOTO.JK"] },
    { id: "idx-indices", label: "IDX Indices", symbols: ["^JKSE","^JK.LQ45"] },
    { id: "mixed", label: "US + IDX Mix", symbols: defaultSymbols() }
  ]
}

function normalizeSymbol(raw) {
  if (!raw) return ""
  var s = String(raw).trim().toUpperCase().replace(/\s+/g,"")
  // allow ^GSPC etc, keep caret
  if (s === "") return ""
  // Yahoo IDX suffix is .JK - normalize variations like .JK, .IDX
  if (s.endsWith(".IDX")) s = s.replace(/\.IDX$/,".JK")
  return s
}

function parseSymbols(input, fallback) {
  var src = input
  if (src === undefined || src === null || src === "") src = fallback || defaultSymbols()
  if (typeof src === "string") {
    src = src.split(/[,;\n]+/)
  }
  if (!Array.isArray(src)) return defaultSymbols()
  var out = []
  var seen = {}
  for (var i=0;i<src.length;i++) {
    var n = normalizeSymbol(src[i])
    if (!n) continue
    if (seen[n]) continue
    seen[n]=true
    out.push(n)
  }
  if (out.length===0) return defaultSymbols()
  // limit to avoid Yahoo URL too long
  if (out.length > 20) out = out.slice(0,20)
  return out
}

function symbolsToQuery(symbols) {
  return symbols.map(function(s){ return encodeURIComponent(s)}).join(",")
}

function yahooQuoteUrl(symbols) {
  // v7 quote is lightweight and returns price + change
  return "https://query1.finance.yahoo.com/v7/finance/quote?symbols=" + symbolsToQuery(symbols)
}

function yahooSparkUrl(symbols) {
  return "https://query1.finance.yahoo.com/v8/finance/spark?symbols=" + symbolsToQuery(symbols) + "&interval=1d&range=1d"
}

function isIdxSymbol(sym) {
  if (!sym) return false
  var s = String(sym).toUpperCase()
  if (s === "^JKSE" || s === "^JK.LQ45" || s === "JKSE") return true
  return s.endsWith(".JK")
}
function isIndexSymbol(sym) {
  if (!sym) return false
  return String(sym).charAt(0) === "^"
}

function marketLabel(sym) {
  if (isIdxSymbol(sym)) return "IDX"
  if (isIndexSymbol(sym)) return "US IDX"
  // heuristic: .JK is IDX equity, otherwise US
  if (String(sym).indexOf(".JK") !== -1) return "IDX"
  if (String(sym).charAt(0) === "^") return "INDEX"
  return "US"
}

function formatPrice(value, symbol) {
  if (value === null || value === undefined || value === "") return "--"
  var n = Number(value)
  if (isNaN(n)) return String(value)
  var isIdx = isIdxSymbol(symbol)
  if (isIdx && !isIndexSymbol(symbol)) {
    // IDR - no decimals for stocks, except indices show 2 decimals
    if (Math.abs(n) >= 1000) return "Rp" + Math.round(n).toLocaleString("id-ID")
    return "Rp" + n.toLocaleString("id-ID")
  }
  if (isIndexSymbol(symbol)) {
    return n.toLocaleString("en-US", {minimumFractionDigits: 2, maximumFractionDigits: 2})
  }
  // US stock - 2 decimals
  return "$" + n.toLocaleString("en-US", {minimumFractionDigits: 2, maximumFractionDigits: 2})
}

function formatChange(change, pct) {
  var c = Number(change)
  var p = Number(pct)
  var cStr = isNaN(c) ? "" : (c >= 0 ? "+" + c.toFixed(2) : c.toFixed(2))
  var pStr = isNaN(p) ? "" : (p >= 0 ? "+" + p.toFixed(2) + "%" : p.toFixed(2) + "%")
  if (cStr && pStr) return cStr + " (" + pStr + ")"
  return pStr || cStr || "--"
}

function formatPercent(pct) {
  var p = Number(pct)
  if (isNaN(p)) return "--"
  return (p >= 0 ? "+" : "") + p.toFixed(2) + "%"
}

function changeColor(change, pct) {
  var v = !isNaN(Number(pct)) ? Number(pct) : Number(change)
  if (isNaN(v) || v === 0) return "neutral"
  return v > 0 ? "up" : "down"
}

function normalizeQuote(q) {
  if (!q || typeof q !== "object") return null
  var sym = q.symbol || q.Symbol || ""
  if (!sym) return null
  return {
    symbol: String(sym),
    shortName: q.shortName || q.longName || String(sym),
    price: q.regularMarketPrice !== undefined ? q.regularMarketPrice : (q.bid !== undefined ? q.bid : null),
    change: q.regularMarketChange,
    changePercent: q.regularMarketChangePercent,
    previousClose: q.regularMarketPreviousClose,
    open: q.regularMarketOpen,
    high: q.regularMarketDayHigh,
    low: q.regularMarketDayLow,
    volume: q.regularMarketVolume,
    marketState: q.marketState || q.exchangeState || "",
    currency: q.currency || (isIdxSymbol(sym) ? "IDR" : "USD"),
    exchange: q.fullExchangeName || q.exchange || "",
    quoteType: q.quoteType || "",
    marketCap: q.marketCap,
    sparkline: q.sparkline || null
  }
}

function normalizeSparkMeta(m) {
  if (!m || typeof m !== "object") return null
  var sym = m.symbol || ""
  if (!sym) return null
  var price = m.regularMarketPrice
  var prev = m.chartPreviousClose !== undefined ? m.chartPreviousClose : m.previousClose
  var change = (price !== undefined && prev !== undefined && !isNaN(price) && !isNaN(prev)) ? (price - prev) : null
  var pct = (change !== null && prev) ? (change / prev * 100) : null
  return {
    symbol: String(sym),
    shortName: m.shortName || m.longName || String(sym),
    price: price,
    change: change,
    changePercent: pct,
    previousClose: prev,
    open: null,
    high: m.regularMarketDayHigh,
    low: m.regularMarketDayLow,
    volume: m.regularMarketVolume,
    marketState: "",
    currency: m.currency || (isIdxSymbol(sym) ? "IDR" : "USD"),
    exchange: m.fullExchangeName || m.exchangeName || "",
    quoteType: m.instrumentType || "",
    sparkline: null
  }
}

function parseYahooSparkResponse(raw) {
  try {
    var data = JSON.parse(String(raw||""))
    var spark = data && data.spark && data.spark.result
    if (!spark || !Array.isArray(spark)) return []
    var out = []
    for (var i=0;i<spark.length;i++) {
      var entry = spark[i]
      if (!entry || !entry.response || !entry.response[0]) continue
      var meta = entry.response[0].meta
      if (!meta) continue
      // ensure symbol is entry.symbol if meta.symbol missing
      if (!meta.symbol) meta.symbol = entry.symbol
      var n = normalizeSparkMeta(meta)
      if (n) out.push(n)
    }
    return out
  } catch(e) { return [] }
}

function parseYahooQuoteResponse(raw) {
  try {
    var data = JSON.parse(String(raw||""))
    var results = data && data.quoteResponse && data.quoteResponse.result
    if (!results || !Array.isArray(results)) return []
    var out = []
    for (var i=0;i<results.length;i++) {
      var n = normalizeQuote(results[i])
      if (n) out.push(n)
    }
    return out
  } catch(e) { return [] }
}

function mergeQuotes(requestedSymbols, quotes) {
  // keep order of requestedSymbols, fill missing with placeholder
  var map = {}
  for (var i=0;i<quotes.length;i++) map[quotes[i].symbol.toUpperCase()] = quotes[i]
  var out = []
  for (var j=0;j<requestedSymbols.length;j++) {
    var sym = requestedSymbols[j]
    var q = map[sym.toUpperCase()]
    if (q) out.push(q)
    else out.push({ symbol: sym, shortName: sym, price: null, change: null, changePercent: null, marketState: "UNKNOWN", currency: isIdxSymbol(sym)?"IDR":"USD", exchange: "", quoteType: "", missing: true })
  }
  return out
}

function tickerLabel(quotes, maxItems) {
  if (!quotes || quotes.length===0) return "Stocks"
  var n = Math.min(maxItems||3, quotes.length)
  var parts=[]
  for (var i=0;i<n;i++) {
    var q = quotes[i]
    var pct = formatPercent(q.changePercent)
    parts.push(q.symbol + " " + pct)
  }
  return parts.join("  •  ")
}

function refreshIntervalMinutes(raw, fallback) {
  var v = parseInt(String(raw||""),10)
  if (isNaN(v)) return fallback||2
  if (v < 1) return 1
  if (v > 60) return 60
  return v
}

if (typeof module !== "undefined") {
  module.exports = {
    defaultSymbols: defaultSymbols,
    presets: presets,
    normalizeSymbol: normalizeSymbol,
    parseSymbols: parseSymbols,
    symbolsToQuery: symbolsToQuery,
    yahooQuoteUrl: yahooQuoteUrl,
    yahooSparkUrl: yahooSparkUrl,
    isIdxSymbol: isIdxSymbol,
    isIndexSymbol: isIndexSymbol,
    marketLabel: marketLabel,
    formatPrice: formatPrice,
    formatChange: formatChange,
    formatPercent: formatPercent,
    changeColor: changeColor,
    normalizeQuote: normalizeQuote,
    parseYahooQuoteResponse: parseYahooQuoteResponse,
    parseYahooSparkResponse: parseYahooSparkResponse,
    normalizeSparkMeta: normalizeSparkMeta,
    mergeQuotes: mergeQuotes,
    tickerLabel: tickerLabel,
    refreshIntervalMinutes: refreshIntervalMinutes
  }
}
