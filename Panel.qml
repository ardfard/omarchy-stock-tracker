import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.ardfard.stock-tracker"
  ipcTarget: "io.github.ardfard.stock-tracker"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  readonly property var barIdentity: hostWidget || root

  // Data - mirrored from BarWidget but panel can also manage its own
  property var watchlist: Model.parseSymbols(setting("symbols", null), Model.defaultSymbols())
  property var quotes: []
  property string lastUpdated: ""
  property bool loading: false
  property string errorMsg: ""
  property string filter: "all" // all | us | idx

  readonly property int refreshMinutes: Model.refreshIntervalMinutes(setting("refreshMinutes", 2), 2)
  readonly property var filteredQuotes: {
    if (filter === "us") return quotes.filter(function(q){ return !Model.isIdxSymbol(q.symbol) })
    if (filter === "idx") return quotes.filter(function(q){ return Model.isIdxSymbol(q.symbol) })
    return quotes
  }

  function open() {
    refresh()
    root.controller.show()
    Qt.callLater(function(){
      if (root.opened) setCenterHoverRevealSuppressed(true)
    })
  }
  function close() {
    setCenterHoverRevealSuppressed(false)
    root.controller.hide()
  }
  function toggle() { if (root.opened) close(); else open() }
  function closeForPopoutSwitch() { close() }
  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.barIdentity, direction)
    return false
  }
  function setCenterHoverRevealSuppressed(v) {
    if (root.bar && "centerHoverRevealSuppressed" in root.bar) root.bar.centerHoverRevealSuppressed = v
  }

  function refresh() {
    if (watchlist.length === 0) return
    loading = true
    errorMsg = ""
    var url = Model.yahooSparkUrl(watchlist)
    fetchProc.command = ["curl","-fsS","--max-time","8","-H","User-Agent: Mozilla/5.0","-H","Accept: application/json", url]
    fetchProc.running = true
  }

  function persistSymbols(newSymbols) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry.symbols = newSymbols
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
    // update local watchlist immediately
    root.watchlist = Model.parseSymbols(newSymbols, Model.defaultSymbols())
  }

  function addSymbol(raw) {
    var s = Model.normalizeSymbol(raw)
    if (!s) return false
    var cur = watchlist.slice()
    // dedup
    for (var i=0;i<cur.length;i++) if (cur[i].toUpperCase()===s.toUpperCase()) return false
    if (cur.length >= 20) { errorMsg = "Max 20 symbols"; return false }
    cur.push(s)
    persistSymbols(cur)
    Qt.callLater(refresh)
    return true
  }

  function removeSymbol(sym) {
    var cur = watchlist.filter(function(v){ return v.toUpperCase() !== String(sym).toUpperCase() })
    if (cur.length === 0) { errorMsg = "Keep at least 1 symbol"; return }
    persistSymbols(cur)
    Qt.callLater(refresh)
  }

  function applyPreset(symbols) {
    persistSymbols(symbols)
    Qt.callLater(refresh)
  }

  function updateRefreshMinutes(v) {
    var entry = { id: root.moduleName }
    for (var k in root.settings) if (k !== "id") entry[k] = root.settings[k]
    entry.refreshMinutes = v
    root.settings = entry
    if (root.hostWidget && "settings" in root.hostWidget) root.hostWidget.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }

  // Keep quotes in sync when BarWidget fetches
  onWatchlistChanged: {
    // if watchlist changed externally and panel is open, refresh
    if (root.opened) Qt.callLater(refresh)
  }

  Process {
    id: fetchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.loading = false
        var raw = String(text||"").trim()
        if (!raw) { root.errorMsg = "Network error"; retryTimer.restart(); return }
        try {
          var parsed = Model.parseYahooSparkResponse(raw)
          if (parsed.length === 0) parsed = Model.parseYahooQuoteResponse(raw)
          var merged = Model.mergeQuotes(root.watchlist, parsed)
          root.quotes = merged
          root.lastUpdated = Qt.formatTime(new Date(), "HH:mm:ss")
          root.errorMsg = ""
          // also push to bar widget if available
          if (root.hostWidget && "quotes" in root.hostWidget) root.hostWidget.quotes = merged
        } catch(e) {
          root.errorMsg = "Parse error"
          retryTimer.restart()
        }
      }
    }
    onExited: function(code){
      if (code!==0) { root.loading=false; root.errorMsg = "Fetch failed ("+code+")"; retryTimer.restart() }
    }
  }
  Timer { id: retryTimer; interval: 15000; onTriggered: root.refresh() }

  // Auto refresh while open
  Timer {
    id: autoTimer
    interval: Math.max(60000, refreshMinutes*60*1000)
    running: root.opened
    repeat: true
    onTriggered: root.refresh()
  }

  readonly property color upColor: "#22c55e"
  readonly property color downColor: "#ef4444"
  readonly property color neutralColor: bar ? bar.foreground : Color.foreground

  SystemClock { id: clock; precision: SystemClock.Minutes }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(dir){ root.switchPanel(dir) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: content.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: content
          width: parent.width
          spacing: Style.space(12)

          // Header
          Row {
            width: parent.width
            spacing: Style.space(8)
            Text {
              text: "Stock Tracker"
              color: root.neutralColor
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: Style.font.title
              font.bold: true
              anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: Style.space(8); height: 1; anchors.verticalCenter: parent.verticalCenter }
            Text {
              text: root.loading ? "◷ loading…" : (root.lastUpdated ? "• " + root.lastUpdated : "")
              color: Color.alpha(root.neutralColor, 0.6)
              font.pixelSize: Style.font.caption
              anchors.verticalCenter: parent.verticalCenter
            }
            Item { width: parent.width - headerRowWidth; height: 1 }
          }
          property real headerRowWidth: 0

          Row {
            id: headerActions
            width: parent.width
            spacing: Style.space(6)
            // Refresh button
            Rectangle {
              width: refreshBtn.implicitWidth + 18
              height: 28
              radius: 14
              color: refreshMouse.pressed ? Color.alpha(Style.accent, 0.3) : (refreshMouse.containsMouse ? Color.alpha(Style.accent, 0.15) : Color.alpha(root.neutralColor, 0.07))
              border.color: Color.alpha(root.neutralColor, 0.12)
              Text { id: refreshBtn; anchors.centerIn: parent; text: root.loading ? "⟳" : "↻ Refresh"; color: root.neutralColor; font.pixelSize: Style.font.caption; font.bold: true }
              MouseArea {
                id: refreshMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                onClicked: root.refresh()
              }
            }
            // Filter tabs
            Repeater {
              model: [{k:"all",l:"All"}, {k:"us",l:"US"}, {k:"idx",l:"IDX"}]
              delegate: Rectangle {
                required property var modelData
                width: tabTxt.implicitWidth + 16
                height: 28
                radius: 14
                color: root.filter === modelData.k ? Style.accent : Color.alpha(root.neutralColor, 0.06)
                border.color: root.filter === modelData.k ? Style.accent : Color.alpha(root.neutralColor, 0.10)
                Text { id: tabTxt; anchors.centerIn: parent; text: modelData.l; color: root.filter === modelData.k ? Style.onAccent : root.neutralColor; font.pixelSize: Style.font.caption; font.bold: root.filter===modelData.k }
                MouseArea { anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.filter = modelData.k }
              }
            }
            Item { width: Style.space(6); height: 1 }
            Text {
              text: watchlist.length + " symbols"
              color: Color.alpha(root.neutralColor, 0.5)
              font.pixelSize: Style.font.small
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          // Error banner
          Rectangle {
            visible: root.errorMsg !== ""
            width: parent.width
            height: visible ? errTxt.implicitHeight + 14 : 0
            radius: 8
            color: Color.alpha(root.downColor, 0.12)
            border.color: Color.alpha(root.downColor, 0.25)
            Text { id: errTxt; anchors.centerIn: parent; width: parent.width - 20; wrapMode: Text.WordWrap; text: root.errorMsg; color: root.downColor; font.pixelSize: Style.font.caption; horizontalAlignment: Text.AlignHCenter }
          }

          // Quotes list
          Column {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: root.filteredQuotes
              delegate: Rectangle {
                required property var modelData
                required property int index
                width: parent.width
                height: 56
                radius: 10
                color: Color.alpha(root.neutralColor, 0.06)
                border.color: Color.alpha(root.neutralColor, 0.08)

                Row {
                  anchors.fill: parent
                  anchors.margins: 10
                  spacing: Style.space(10)

                  // Symbol + market badge
                  Column {
                    width: 90
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      text: modelData.symbol
                      color: root.neutralColor
                      font.pixelSize: Style.font.body
                      font.bold: true
                      font.family: Style.font.monoFamily || Style.font.family
                    }
                    Rectangle {
                      width: badgeTxt.implicitWidth + 8
                      height: 14
                      radius: 7
                      color: Model.isIdxSymbol(modelData.symbol) ? Color.alpha("#f59e0b", 0.18) : Color.alpha("#3b82f6", 0.15)
                      border.color: Model.isIdxSymbol(modelData.symbol) ? Color.alpha("#f59e0b",0.30) : Color.alpha("#3b82f6",0.30)
                      Text {
                        id: badgeTxt
                        anchors.centerIn: parent
                        text: Model.marketLabel(modelData.symbol)
                        color: Model.isIdxSymbol(modelData.symbol) ? "#f59e0b" : "#3b82f6"
                        font.pixelSize: 9
                        font.bold: true
                      }
                    }
                  }

                  // Name + price
                  Column {
                    width: 150
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      width: parent.width
                      text: modelData.shortName || modelData.symbol
                      color: root.neutralColor
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      maximumLineCount: 1
                    }
                    Text {
                      text: Model.formatPrice(modelData.price, modelData.symbol)
                      color: root.neutralColor
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                  }

                  // Change
                  Column {
                    width: 110
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter
                    Text {
                      text: Model.formatPercent(modelData.changePercent)
                      color: Model.changeColor(modelData.change, modelData.changePercent) === "up" ? root.upColor : (Model.changeColor(modelData.change, modelData.changePercent)==="down" ? root.downColor : Color.alpha(root.neutralColor,0.6))
                      font.pixelSize: Style.font.body
                      font.bold: true
                    }
                    Text {
                      text: modelData.change !== null && modelData.change !== undefined ? (Number(modelData.change) >=0 ? "+"+Number(modelData.change).toFixed(2) : Number(modelData.change).toFixed(2)) : "--"
                      color: Color.alpha(root.neutralColor, 0.55)
                      font.pixelSize: Style.font.small
                    }
                  }

                  Item { width: Style.space(4); height: 1 }

                  // Actions
                  Row {
                    spacing: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    // Open Yahoo
                    Rectangle {
                      width: 26; height: 26; radius: 13
                      color: openArea.containsMouse ? Color.alpha(root.neutralColor, 0.12) : "transparent"
                      border.color: Color.alpha(root.neutralColor, 0.10)
                      Text { anchors.centerIn: parent; text: "↗"; color: root.neutralColor; font.pixelSize: 12 }
                      MouseArea { id: openArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: { if (root.bar) root.bar.run("xdg-open 'https://finance.yahoo.com/quote/" + encodeURIComponent(modelData.symbol) + "'") } }
                    }
                    // Remove
                    Rectangle {
                      width: 26; height: 26; radius: 13
                      color: delArea.containsMouse ? Color.alpha(root.downColor,0.18) : Color.alpha(root.neutralColor,0.06)
                      border.color: Color.alpha(root.neutralColor,0.10)
                      Text { anchors.centerIn: parent; text: "×"; color: delArea.containsMouse ? root.downColor : Color.alpha(root.neutralColor,0.7); font.pixelSize: 14; font.bold: true }
                      MouseArea { id: delArea; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.removeSymbol(modelData.symbol) }
                    }
                  }
                }
              }
            }
            // Empty state
            Text {
              visible: root.filteredQuotes.length === 0
              width: parent.width
              text: root.quotes.length===0 ? "No data yet — check network or try Refresh" : "No symbols match filter"
              color: Color.alpha(root.neutralColor, 0.5)
              font.pixelSize: Style.font.caption
              wrapMode: Text.WordWrap
              horizontalAlignment: Text.AlignHCenter
            }
          }

          // Add symbol row
          Rectangle {
            width: parent.width
            height: 44
            radius: 10
            color: Color.alpha(root.neutralColor, 0.04)
            border.color: Color.alpha(root.neutralColor, 0.10)
            Row {
              anchors.fill: parent
              anchors.margins: 6
              spacing: Style.space(6)
              // Text field fallback: use Rectangle + TextInput
              Rectangle {
                width: parent.width - addBtn.width - Style.space(12) - 6
                height: 32
                radius: 8
                color: Color.alpha(root.neutralColor, 0.06)
                border.color: addInput.activeFocus ? Style.accent : Color.alpha(root.neutralColor,0.10)
                TextInput {
                  id: addInput
                  anchors.fill: parent
                  anchors.margins: 8
                  verticalAlignment: TextInput.AlignVCenter
                  color: root.neutralColor
                  font.pixelSize: Style.font.body
                  font.family: Style.font.monoFamily || Style.font.family
                  clip: true
                  onAccepted: { if (root.addSymbol(text)) text="" }
                  // placeholder
                  property string placeholder: "Add symbol e.g. AAPL, BBCA.JK, ^JKSE"
                  Text {
                    visible: addInput.text === "" && !addInput.activeFocus
                    text: addInput.placeholder
                    color: Color.alpha(root.neutralColor, 0.35)
                    font.pixelSize: Style.font.caption
                    anchors.verticalCenter: parent.verticalCenter
                  }
                }
              }
              Rectangle {
                id: addBtn
                width: 64
                height: 32
                radius: 8
                color: addMouse.pressed ? Color.alpha(Style.accent,0.8) : (addMouse.containsMouse ? Style.accent : Color.alpha(Style.accent,0.9))
                Text { anchors.centerIn: parent; text: "Add"; color: Style.onAccent; font.bold: true; font.pixelSize: Style.font.caption }
                MouseArea {
                  id: addMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor
                  onClicked: { if (root.addSymbol(addInput.text)) addInput.text="" }
                }
              }
            }
          }

          // Presets
          Text {
            text: "Quick presets"
            color: Color.alpha(root.neutralColor, 0.6)
            font.pixelSize: Style.font.caption
            font.bold: true
          }
          Flow {
            width: parent.width
            spacing: Style.space(6)
            Repeater {
              model: Model.presets()
              delegate: Rectangle {
                required property var modelData
                width: presetTxt.implicitWidth + 18
                height: 26
                radius: 13
                color: presetMouse.containsMouse ? Color.alpha(Style.accent,0.15) : Color.alpha(root.neutralColor,0.06)
                border.color: Color.alpha(root.neutralColor,0.10)
                Text { id: presetTxt; anchors.centerIn: parent; text: modelData.label; color: root.neutralColor; font.pixelSize: Style.font.small }
                MouseArea { id: presetMouse; anchors.fill: parent; hoverEnabled: true; cursorShape: Qt.PointingHandCursor; onClicked: root.applyPreset(modelData.symbols) }
              }
            }
          }

          // Settings row
          Rectangle {
            width: parent.width
            height: 38
            radius: 10
            color: Color.alpha(root.neutralColor, 0.04)
            border.color: Color.alpha(root.neutralColor, 0.08)
            Row {
              anchors.fill: parent
              anchors.margins: 10
              spacing: Style.space(10)
              Text { text: "Refresh"; color: Color.alpha(root.neutralColor,0.7); font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              Repeater {
                model: [1,2,5,10]
                delegate: Rectangle {
                  required property var modelData
                  width: 36; height: 22; radius: 11
                  color: root.refreshMinutes === modelData ? Style.accent : Color.alpha(root.neutralColor,0.08)
                  border.color: Color.alpha(root.neutralColor,0.10)
                  Text { anchors.centerIn: parent; text: modelData+"m"; color: root.refreshMinutes===modelData ? Style.onAccent : root.neutralColor; font.pixelSize: 11; font.bold: root.refreshMinutes===modelData }
                  MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: root.updateRefreshMinutes(modelData) }
                }
              }
              Item { width: Style.space(8); height:1 }
              Text {
                text: "↻ " + refreshMinutes + " min"
                color: Color.alpha(root.neutralColor,0.5)
                font.pixelSize: Style.font.small
                anchors.verticalCenter: parent.verticalCenter
              }
            }
          }

          // Footer hints
          Column {
            width: parent.width
            spacing: Style.space(4)
            Text {
              width: parent.width
              text: "US: AAPL, NVDA, MSFT, ^GSPC, ^IXIC  •  IDX: BBCA.JK, BBRI.JK, BMRI.JK, GOTO.JK, ^JKSE"
              color: Color.alpha(root.neutralColor, 0.45)
              font.pixelSize: Style.font.small
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: "Left-click bar to toggle • Right-click to refresh • Middle-click to open Yahoo for first symbol"
              color: Color.alpha(root.neutralColor, 0.40)
              font.pixelSize: 10
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: "Data by Yahoo Finance (no API key). IDX symbols use .JK suffix, e.g. BBCA.JK. Indices: ^JKSE (IHSG), ^GSPC (S&P 500)."
              color: Color.alpha(root.neutralColor, 0.40)
              font.pixelSize: 10
              wrapMode: Text.WordWrap
            }
          }
        }
      }
    }
  }
}
