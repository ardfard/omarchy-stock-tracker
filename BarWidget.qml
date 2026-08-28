import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget: compact ticker + loader for the detail panel.
// Supports US (NYSE/NASDAQ) and IDX (.JK / ^JKSE) via Yahoo Finance.
BarWidget {
  id: root
  moduleName: "io.github.ardfard.stock-tracker"

  // Settings stored in shell.json under this id
  readonly property var watchlist: Model.parseSymbols(setting("symbols", null), Model.defaultSymbols())
  readonly property int refreshMinutes: Model.refreshIntervalMinutes(setting("refreshMinutes", 2), 2)
  readonly property int barMaxItems: Math.max(1, Math.min(4, parseInt(setting("barMaxItems", 3),10) || 3))
  readonly property bool showBarChange: setting("showBarChange", true) !== false
  readonly property string compactMode: String(setting("compactMode", "change")) // change | price | both

  // Live quotes for bar
  property var quotes: []
  property string lastUpdatedLabel: ""
  property bool loading: false

  readonly property string tickerText: {
    if (loading && quotes.length === 0) return "◷ Loading…"
    if (quotes.length === 0) return "Stocks"
    // Build compact ticker for barMaxItems
    var parts = []
    for (var i=0; i < Math.min(barMaxItems, quotes.length); i++) {
      var q = quotes[i]
      if (!q) continue
      var sym = q.symbol
      // strip .JK for brevity? keep for IDX distinction
      var shortSym = sym
      if (compactMode === "price" || compactMode === "both") {
        var price = Model.formatPrice(q.price, sym)
        if (compactMode === "both" && q.changePercent !== null && q.changePercent !== undefined) {
          parts.push(shortSym + " " + price + " " + Model.formatPercent(q.changePercent))
        } else if (compactMode === "price") {
          parts.push(shortSym + " " + price)
        } else {
          parts.push(shortSym + " " + Model.formatPercent(q.changePercent))
        }
      } else {
        parts.push(shortSym + " " + Model.formatPercent(q.changePercent))
      }
    }
    return parts.join("  •  ")
  }

  readonly property bool hasUp: {
    for (var i=0;i<quotes.length;i++) if (Model.changeColor(quotes[i].change, quotes[i].changePercent)==="up") return true
    return false
  }
  readonly property bool hasDown: {
    for (var i=0;i<quotes.length;i++) if (Model.changeColor(quotes[i].change, quotes[i].changePercent)==="down") return true
    return false
  }

  // Panel plumbing - mirrors clock/weather pattern
  readonly property bool opened: panelLoader.item ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
  function refresh() {
    if (panelLoader.item && panelLoader.item.refresh) panelLoader.item.refresh()
    else fetchQuotes()
  }

  function injectPanel() {
    var t = panelLoader.item
    if (!t) return
    if ("bar" in t) t.bar = root.bar
    if ("settings" in t) t.settings = root.settings
    if ("anchorItem" in t) t.anchorItem = button
    if ("hostWidget" in t) t.hostWidget = root
  }

  onBarChanged: injectPanel()
  onSettingsChanged: {
    injectPanel()
    // symbols changed outside? refetch
    Qt.callLater(fetchQuotes)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Component.onCompleted: fetchQuotes()

  // Auto refresh timer for bar (even when panel closed)
  Timer {
    id: barRefreshTimer
    interval: Math.max(60000, root.refreshMinutes * 60 * 1000)
    running: true
    repeat: true
    triggeredOnStart: false
    onTriggered: root.fetchQuotes()
  }
  onRefreshMinutesChanged: {
    barRefreshTimer.interval = Math.max(60000, refreshMinutes * 60 * 1000)
    barRefreshTimer.restart()
  }

  function fetchQuotes() {
    if (watchlist.length === 0) return
    var url = Model.yahooSparkUrl(watchlist)
    // Use curl via Process to avoid CORS and get reliable headers (Yahoo needs User-Agent)
    quoteProc.command = ["curl","-fsS","--max-time","8","-H","User-Agent: Mozilla/5.0","-H","Accept: application/json", url]
    quoteProc.running = true
    loading = true
  }

  Process {
    id: quoteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        var raw = String(text||"").trim()
        if (!raw) {
          // keep stale quotes, show error via lastUpdatedLabel
          root.lastUpdatedLabel = "offline"
          retryTimer.restart()
          return
        }
        try {
          var parsed = Model.parseYahooSparkResponse(raw)
          if (parsed.length === 0) parsed = Model.parseYahooQuoteResponse(raw)
          var merged = Model.mergeQuotes(root.watchlist, parsed)
          root.quotes = merged
          // push to panel if loaded
          if (panelLoader.item && "quotes" in panelLoader.item) panelLoader.item.quotes = merged
          root.lastUpdatedLabel = Qt.formatTime(new Date(), "HH:mm")
        } catch(e) {
          root.lastUpdatedLabel = "error"
          retryTimer.restart()
        }
      }
    }
    onExited: function(code) {
      if (code !== 0) {
        root.loading = false
        root.lastUpdatedLabel = "error"
        retryTimer.restart()
      }
    }
  }

  Timer {
    id: retryTimer
    interval: 15000
    repeat: false
    onTriggered: root.fetchQuotes()
  }

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      // sync initial quotes to panel
      if ("quotes" in item) item.quotes = root.quotes
      if ("watchlist" in item) item.watchlist = root.watchlist
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: "io.github.ardfard.stock-tracker"
    function refresh() { root.refresh() }
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    function show() { root.open() }
    function hide() { root.close() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Ticker text with optional color hint via tooltip
    text: root.tickerText
    tooltipText: watchlist.join(", ") + (root.lastUpdatedLabel ? " • " + root.lastUpdatedLabel : "")
    // subtle tint: greenish when any up, reddish when any down - via foreground? keep neutral, rely on panel for colors
    onPressed: function(b) {
      if (b === Qt.RightButton) {
        // right click refreshes
        root.fetchQuotes()
      } else if (b === Qt.MiddleButton) {
        // middle opens Yahoo finance for first symbol
        if (root.watchlist.length>0 && root.bar) {
          var sym = root.watchlist[0]
          var url = "https://finance.yahoo.com/quote/" + encodeURIComponent(sym)
          root.bar.run("xdg-open '" + url + "'")
        }
      } else {
        root.toggle()
      }
    }
  }
}
