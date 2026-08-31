import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.guzzy711.kunja"

  readonly property var taskService: bar && bar.shell
    ? bar.shell.serviceFor(moduleName) : null
  readonly property var taskDocument: taskService
    ? taskService.document : Model.parseSync("")
  readonly property bool hasWarning: taskService
    && (taskService.overdueCount > 0 || taskService.status === "error" || taskService.status === "stale")
  readonly property bool hasOverdue: Number(taskDocument.overdue_count || 0) > 0
  readonly property string compactIcon: Model.barIcon(taskDocument)
  readonly property string compactTitle: Model.barTitle(taskDocument)
  readonly property string compactBadge: Model.barBadge(taskDocument)
  readonly property bool showTaskTitle: setting("showTaskTitle", true) === true

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true : false

  function open() { if (panelLoader.item) panelLoader.item.open() }
  function close() { if (panelLoader.item) panelLoader.item.close() }
  function toggle() { if (panelLoader.item) panelLoader.item.toggle() }
  function refresh() { if (taskService) taskService.refresh() }
  function toggleShowTaskTitle() {
    var entry = { id: root.moduleName }
    for (var key in root.settings) if (key !== "id") entry[key] = root.settings[key]
    entry.showTaskTitle = !root.showTaskTitle
    root.settings = entry
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function")
      root.bar.shell.updateEntryInline(root.moduleName, entry)
  }
  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    var panel = panelLoader.item
    if (!panel) return
    panel.bar = root.bar
    panel.settings = root.settings
    panel.anchorItem = button
    panel.hostWidget = root
    panel.service = root.taskService
  }

  function syncSettings() {
    if (taskService) taskService.adoptSettings(root.settings)
    injectPanel()
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onBarChanged: syncSettings()
  onSettingsChanged: syncSettings()
  onTaskServiceChanged: syncSettings()
  Component.onCompleted: syncSettings()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("TaskPanel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  IpcHandler {
    target: root.moduleName
    function refresh() { root.refresh() }
    function open() { root.open() }
    function close() { root.close() }
    function show() { root.open() }
    function hide() { root.close() }
    function toggle() { root.toggle() }
  }

  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    labelVisible: false
    hasVisualContent: true
    fixedWidth: root.vertical ? -1 : compactRow.implicitWidth + Style.space(17)
    active: false
    useActiveColor: false
    dimmed: root.taskService ? root.taskService.loading : false
    tooltipText: Model.tooltip(root.taskDocument)
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }

    Row {
      id: compactRow
      anchors.centerIn: parent
      spacing: Style.space(7)

      Rectangle {
        id: iconChip
        visible: root.vertical
        width: Style.space(24)
        height: width
        radius: width / 2
        color: root.hasWarning
          ? Util.alpha(button.activeColor, 0.18)
          : Util.alpha(button.foreground, 0.10)

        Text {
          anchors.centerIn: parent
          text: root.compactIcon
          color: root.hasWarning ? button.activeColor : button.foreground
          font.family: button.fontFamily
          font.pixelSize: Style.font.bodySmall
          renderType: Text.NativeRendering
        }
      }

      Rectangle {
        id: statusPill
        visible: !root.vertical
        implicitWidth: statusContent.implicitWidth + Style.space(16)
        width: implicitWidth
        height: Style.space(26)
        radius: height / 2
        color: root.hasOverdue
          ? Util.alpha(button.activeColor, 0.20)
          : Util.alpha(button.foreground, 0.10)
        border.width: 1
        border.color: root.hasOverdue
          ? Util.alpha(button.activeColor, 0.45)
          : Util.alpha(button.foreground, 0.16)

        Row {
          id: statusContent
          anchors.centerIn: parent
          spacing: Style.space(5)

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.compactIcon
            color: root.hasWarning ? button.activeColor : button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.bodySmall
            renderType: Text.NativeRendering
          }

          Text {
            visible: root.compactBadge !== ""
            anchors.verticalCenter: parent.verticalCenter
            text: root.compactBadge
            color: root.hasOverdue ? button.activeColor : button.foreground
            font.family: button.fontFamily
            font.pixelSize: Style.font.caption
            font.bold: root.hasOverdue
            renderType: Text.NativeRendering
          }
        }
      }

      Text {
        visible: !root.vertical && root.showTaskTitle
        anchors.verticalCenter: parent.verticalCenter
        text: root.compactTitle
        color: button.foreground
        font.family: button.fontFamily
        font.pixelSize: Style.font.bodySmall
        font.weight: Font.Medium
        renderType: Text.NativeRendering
      }

    }
  }
}
