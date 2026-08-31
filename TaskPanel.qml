import QtQuick
import QtQuick.Controls
import QtQuick.Controls as QQC
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

Panel {
  id: root
  moduleName: "io.github.guzzy711.kunja"
  ipcTarget: "io.github.guzzy711.kunja"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var service: null
  readonly property var barIdentity: hostWidget || root
  readonly property bool showTaskTitle: hostWidget ? hostWidget.showTaskTitle : true
  readonly property var document: service ? service.document : Model.parseSync("")
  readonly property var tasks: service ? service.tasks : []
  readonly property var rows: Model.panelRows(tasks)
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  property int cursorIndex: tasks.length > 0 ? 0 : -1
  property string viewMode: "tasks"
  property string selectedProjectId: ""
  property string selectedAssigneeId: ""
  property bool assigneeChoiceMade: false
  property string formError: ""

  function projectOptions() {
    var result = []
    var source = service && Array.isArray(service.createProjects) ? service.createProjects : []
    for (var i = 0; i < source.length; i++) result.push({
      value: String(source[i].id),
      label: String(source[i].label || source[i].title || "Untitled project"),
      description: String(source[i].identifier || "")
    })
    return result
  }

  function assigneeOptions() {
    var result = [{ value: "", label: "Unassigned", description: "No assignee" }]
    var source = service && Array.isArray(service.projectUsers) ? service.projectUsers : []
    for (var i = 0; i < source.length; i++) result.push({
      value: String(source[i].id),
      label: String(source[i].display_name || source[i].name || source[i].username || "User"),
      description: String(source[i].username || source[i].email || "")
    })
    return result
  }

  function assigneeLabel(value) {
    var wanted = String(value || "")
    var options = assigneeOptions()
    for (var i = 0; i < options.length; i++)
      if (String(options[i].value) === wanted) return String(options[i].label)
    return wanted === "" ? "Unassigned" : "Selected user"
  }

  function startCreate() {
    if (!service || document.status === "unconfigured") return
    viewMode = "create"
    formError = ""
    titleField.text = ""
    dueDateField.text = ""
    dueTimeField.text = ""
    priorityDropdown.value = "0"
    descriptionField.text = ""
    selectedProjectId = ""
    selectedAssigneeId = ""
    assigneeChoiceMade = false
    service.loadCreateOptions()
    Qt.callLater(function() { titleField.forceActiveFocus() })
  }

  function cancelCreate() {
    viewMode = "tasks"
    formError = ""
    keyCatcher.forceActiveFocus()
  }

  function chooseDefaultProject() {
    if (viewMode !== "create" || selectedProjectId !== "" || !service
        || !Array.isArray(service.createProjects) || service.createProjects.length === 0) return
    selectedProjectId = String(service.createProjects[0].id)
    service.loadProjectUsers(selectedProjectId)
  }

  function chooseDefaultAssignee() {
    if (viewMode !== "create" || !service || assigneeChoiceMade) return
    var currentId = String(service.currentUser && service.currentUser.id || "")
    var users = Array.isArray(service.projectUsers) ? service.projectUsers : []
    for (var i = 0; i < users.length; i++) {
      if (String(users[i].id) === currentId) {
        selectedAssigneeId = currentId
        return
      }
    }
  }

  function submitCreate() {
    formError = ""
    var title = String(titleField.text || "").trim()
    if (title === "") { formError = "Add a title before creating the task."; titleField.forceActiveFocus(); return }
    var projectId = String(projectDropdown.value || "")
    var assigneeId = String(assigneeDropdown.value || "")
    if (projectId === "") { formError = "Choose a project for the task."; return }
    var dueDate = Model.dueDateTimeIso(dueDateField.text, dueTimeField.text)
    if (dueDate === "") { formError = "Use a valid due date and time, for example 2026-09-01 and 16:30."; dueDateField.forceActiveFocus(); return }
    service.createTask({
      title: title,
      project_id: Number(projectId),
      assignee_id: assigneeId === "" ? null : Number(assigneeId),
      assignee_label: assigneeLabel(assigneeId),
      due_date: dueDate,
      priority: Number(priorityDropdown.value || 0),
      description: String(descriptionField.text || "").trim()
    })
  }

  function open() {
    root.controller.show()
    if (service) service.refresh()
  }

  function close() {
    viewMode = "tasks"
    root.controller.hide()
  }
  function toggle() { root.opened ? root.close() : root.open() }

  function closeForPopoutSwitch() {
    root.popoutSwitchClosing = true
    root.close()
    Qt.callLater(function() { root.popoutSwitchClosing = false })
  }

  function switchPanel(direction) {
    if (bar && typeof bar.switchPanelFrom === "function")
      return bar.switchPanelFrom(barIdentity, direction)
    return false
  }

  function moveCursor(delta) {
    if (tasks.length === 0) { cursorIndex = -1; return }
    cursorIndex = Math.max(0, Math.min(tasks.length - 1, cursorIndex + delta))
    taskFlick.contentY = Math.max(0, Math.min(taskFlick.contentHeight - taskFlick.height,
      cursorIndex * Style.space(66)))
  }

  function openTask(task) {
    var url = Model.safeHttpsUrl(task && task.frontend_url)
    if (url === "") return
    Qt.openUrlExternally(url)
    root.close()
  }

  function activateCursor() {
    if (cursorIndex >= 0 && cursorIndex < tasks.length) openTask(tasks[cursorIndex])
  }

  function launchConfigure() {
    if (!service || service.helperPath === "") return
    Quickshell.execDetached(["xdg-terminal-exec", "python3", service.helperPath, "configure"])
  }

  function toggleShowTaskTitle() {
    if (hostWidget && typeof hostWidget.toggleShowTaskTitle === "function")
      hostWidget.toggleShowTaskTitle()
  }

  onTasksChanged: {
    if (tasks.length === 0) cursorIndex = -1
    else cursorIndex = Math.max(0, Math.min(cursorIndex, tasks.length - 1))
  }

  Connections {
    target: root.service
    function onCreateProjectsChanged() { root.chooseDefaultProject() }
    function onProjectUsersChanged() { root.chooseDefaultAssignee() }
    function onCreateFinished(result) {
      if (result.status === "ok" || result.status === "partial") {
        root.viewMode = "success"
        Qt.callLater(function() { successOpenButton.forceActiveFocus() })
      } else {
        root.formError = String(result && result.error ? result.error.message : "Could not create the task.")
      }
    }
  }

  Shortcut {
    sequence: "N"
    context: Qt.WindowShortcut
    enabled: root.opened && root.viewMode === "tasks"
      && root.document.status !== "unconfigured"
    onActivated: root.startCreate()
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.barIdentity
    bar: root.bar
    open: root.opened
    centerOnBar: true
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(470))
    contentHeight: panel.fittedContentHeight(contentColumn.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      blocked: root.viewMode !== "tasks"
      onMoveRequested: function(dx, dy) {
        if (dy !== 0) root.moveCursor(dy > 0 ? 1 : -1)
      }
      onActivateRequested: root.activateCursor()
      onCloseRequested: root.viewMode === "tasks" ? root.close() : root.cancelCreate()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(text) {
        if (text === "r" || text === "R") { if (root.service) root.service.refresh() }
        else if (text === "o" || text === "O") root.activateCursor()
        else if (text === "n" || text === "N") root.startCreate()
        else if ((text === "s" || text === "S") && root.document.status === "unconfigured")
          root.launchConfigure()
      }

      Column {
        id: contentColumn
        width: parent.width
        spacing: Style.space(12)

        PanelHero {
          width: parent.width
          title: "Kunja"
          meta: Model.statusLabel(root.document)
          detail: root.service && root.service.loading
            ? "SYNCING"
            : (root.document.overdue_count > 0
              ? String(root.document.overdue_count) + " OVERDUE · " + String(root.tasks.length) + " TASKS"
              : String(root.tasks.length) + (root.tasks.length === 1 ? " TASK" : " TASKS"))
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            Text {
              text: "󰄬"
              color: root.document.overdue_count > 0 ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.display
            }
          }
        }

        Text {
          visible: root.viewMode === "tasks"
            && (root.document.status === "error" || root.document.status === "stale")
          width: parent.width
          text: root.document.error ? String(root.document.error.message || "") : ""
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Rectangle {
          visible: root.viewMode === "tasks" && root.document.status === "unconfigured"
          width: parent.width
          implicitHeight: setupColumn.implicitHeight + Style.space(28)
          radius: Style.cornerRadius
          color: Style.normalFillFor(root.foreground, Color.accent, root.urgent)

          Column {
            id: setupColumn
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(14)
            spacing: Style.space(8)

            Text {
              width: parent.width
              text: "Set up Kunja"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "The guided setup takes about a minute and keeps your API token in the desktop keyring."
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              width: parent.width
              text: "1   Enter your Vikunja address\n2   Create a scoped token in Vikunja\n3   Paste it securely and connect"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              lineHeight: 1.35
              wrapMode: Text.WordWrap
            }

            Rectangle {
              width: setupLabel.implicitWidth + Style.space(20)
              height: setupLabel.implicitHeight + Style.space(10)
              radius: Style.cornerRadius
              color: setupMouse.containsMouse
                ? Style.hoverFillFor(root.foreground, Color.accent, root.urgent)
                : "transparent"
              border.width: 1
              border.color: root.dim

              Text {
                id: setupLabel
                anchors.centerIn: parent
                text: "START SETUP  S"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }
              MouseArea {
                id: setupMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.launchConfigure()
              }
            }
          }
        }

        Text {
          visible: root.viewMode === "tasks"
            && root.document.status !== "unconfigured" && root.tasks.length === 0
          width: parent.width
          text: root.service && root.service.loading
            ? "Checking Vikunja…"
            : "No assigned tasks are due in the next " + String(root.service ? root.service.horizonDays : 14) + " days."
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.WordWrap
          topPadding: Style.space(18)
          bottomPadding: Style.space(18)
        }

        Flickable {
          id: taskFlick
          visible: root.viewMode === "tasks" && root.tasks.length > 0
          width: parent.width
          height: Math.min(taskColumn.implicitHeight, Style.space(470))
          contentWidth: width
          contentHeight: taskColumn.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Column {
            id: taskColumn
            width: taskFlick.width
            spacing: Style.space(5)

            Repeater {
              model: root.rows

              Loader {
                required property var modelData
                required property int index
                width: taskColumn.width
                sourceComponent: modelData.row_type === "header" ? sectionComponent : taskComponent
                property var rowData: modelData
              }
            }
          }
        }

        Flickable {
          id: createFlick
          visible: root.viewMode === "create"
          width: parent.width
          height: Math.min(createContent.implicitHeight, Style.space(470))
          contentWidth: width
          contentHeight: createContent.implicitHeight
          clip: true
          interactive: contentHeight > height
          boundsBehavior: Flickable.StopAtBounds
          flickableDirection: Flickable.VerticalFlick
          ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

          Keys.onEscapePressed: function(event) {
            root.cancelCreate()
            event.accepted = true
          }

          Column {
            id: createContent
            width: createFlick.width
            spacing: Style.space(10)

            Row {
              width: parent.width
              spacing: Style.space(8)

              Text {
                width: parent.width - cancelTop.width - parent.spacing
                anchors.verticalCenter: parent.verticalCenter
                text: "New task"
                color: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.subtitle
                font.bold: true
              }

              PanelActionButton {
                id: cancelTop
                iconText: "󰅖"
                tooltipText: "Cancel"
                foreground: root.foreground
                focusable: true
                onClicked: root.cancelCreate()
                Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
              }
            }

            TextField {
              id: titleField
              width: parent.width
              foreground: root.foreground
              placeholderText: "Task title"
              maximumLength: 250
              Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
            }

            SearchableDropdown {
              id: projectDropdown
              width: parent.width
              label: "Project"
              value: root.selectedProjectId
              options: root.projectOptions()
              placeholderText: "Search projects…"
              emptyText: root.service && root.service.createOptionsLoading
                ? "Loading projects…" : "No writable projects found"
              foreground: root.foreground
              background: Color.background
              accent: Color.accent
              fontFamily: root.fontFamily
              onChanged: function(value) {
                root.selectedProjectId = value
                root.selectedAssigneeId = ""
                root.assigneeChoiceMade = false
                if (root.service) root.service.loadProjectUsers(value)
              }
            }

            SearchableDropdown {
              id: assigneeDropdown
              width: parent.width
              label: "Assignee"
              value: root.selectedAssigneeId
              options: root.assigneeOptions()
              placeholderText: "Search project members…"
              emptyText: root.service && root.service.projectUsersLoading
                ? "Loading members…" : "No project members found"
              foreground: root.foreground
              background: Color.background
              accent: Color.accent
              fontFamily: root.fontFamily
              onChanged: function(value) {
                root.assigneeChoiceMade = true
                root.selectedAssigneeId = value
              }
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Column {
                width: Math.floor((parent.width - parent.spacing) * 0.58)
                spacing: Style.space(4)
                Text {
                  text: "DUE DATE"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                TextField {
                  id: dueDateField
                  width: parent.width
                  foreground: root.foreground
                  placeholderText: "YYYY-MM-DD"
                  inputMethodHints: Qt.ImhDate
                  Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
                }
              }

              Column {
                width: parent.width - x
                spacing: Style.space(4)
                Text {
                  text: "TIME"
                  color: root.dim
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                  font.bold: true
                }
                TextField {
                  id: dueTimeField
                  width: parent.width
                  foreground: root.foreground
                  placeholderText: "HH:MM"
                  inputMethodHints: Qt.ImhTime
                  Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
                }
              }
            }

            Dropdown {
              id: priorityDropdown
              width: parent.width
              label: "Priority"
              value: "0"
              options: [
                { value: "0", label: "Unset" },
                { value: "1", label: "Low" },
                { value: "2", label: "Medium" },
                { value: "3", label: "High" },
                { value: "4", label: "Urgent" },
                { value: "5", label: "Do now" }
              ]
              foreground: root.foreground
              background: Color.background
              accent: Color.accent
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(4)

              Text {
                text: "DESCRIPTION"
                color: root.dim
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
                font.bold: true
              }

              QQC.TextArea {
                id: descriptionField
                width: parent.width
                implicitHeight: Style.space(96)
                placeholderText: "Optional notes…"
                wrapMode: TextEdit.Wrap
                color: root.foreground
                placeholderTextColor: root.dim
                selectionColor: Style.selectionFillFor(root.foreground, Color.accent)
                selectedTextColor: root.foreground
                font.family: root.fontFamily
                font.pixelSize: Style.font.body
                leftPadding: Style.spacing.controlPaddingX
                rightPadding: Style.spacing.controlPaddingX
                topPadding: Style.spacing.controlPaddingY
                bottomPadding: Style.spacing.controlPaddingY
                background: BorderSurface {
                  color: Style.controlFill(descriptionField.activeFocus,
                    descriptionField.hovered, root.foreground, Color.accent)
                  borderSpec: Border.controlSpec(descriptionField.activeFocus
                    ? "focus" : (descriptionField.hovered ? "hover-cursor" : "normal"),
                    root.foreground, Color.accent)
                  radius: Style.cornerRadius
                }
                Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
              }
            }

            Text {
              visible: root.formError !== ""
              width: parent.width
              text: root.formError
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Text {
              visible: root.service && root.service.createOptionsError
                && String(root.service.createOptionsError.message || "") !== ""
              width: parent.width
              text: String(root.service && root.service.createOptionsError
                ? root.service.createOptionsError.message || "" : "")
              color: root.urgent
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }

            Row {
              width: parent.width
              spacing: Style.space(8)

              Button {
                width: Math.floor((parent.width - parent.spacing) * 0.35)
                text: "Cancel"
                foreground: root.foreground
                bordered: true
                focusable: true
                onClicked: root.cancelCreate()
                Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
              }

              Button {
                width: parent.width - x
                text: root.service && root.service.creationBusy ? "Creating…" : "Create task"
                iconText: root.service && root.service.creationBusy ? "󰑓" : "󰐕"
                iconSpinning: root.service && root.service.creationBusy
                foreground: root.foreground
                active: true
                focusable: true
                enabled: root.service && !root.service.creationBusy
                  && !root.service.createOptionsLoading
                onClicked: root.submitCreate()
                Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
              }
            }
          }
        }

        BorderSurface {
          visible: root.viewMode === "success"
          width: parent.width
          implicitHeight: successContent.implicitHeight + Style.space(28)
          radius: Style.cornerRadius
          color: Style.controlFill(false, false, root.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

          Column {
            id: successContent
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: Style.space(14)
            spacing: Style.space(9)

            Text {
              text: root.service && root.service.creationResult.status === "partial" ? "Task created with a warning" : "Task created"
              color: root.service && root.service.creationResult.status === "partial" ? root.urgent : root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.subtitle
              font.bold: true
            }
            Text {
              width: parent.width
              text: String(root.service && root.service.creationResult.task
                ? root.service.creationResult.task.title || "" : "")
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.body
              font.bold: true
              wrapMode: Text.WordWrap
            }
            Text {
              width: parent.width
              text: "Assignee · " + String(root.service && root.service.creationResult.task
                ? root.service.creationResult.task.assignee_label || "Unassigned" : "Unassigned")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
            Text {
              visible: root.service && root.service.creationResult.status === "partial"
              width: parent.width
              text: String(root.service ? root.service.creationResult.message || "" : "")
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
              wrapMode: Text.WordWrap
            }
            Row {
              width: parent.width
              spacing: Style.space(8)
              Button {
                width: Math.floor((parent.width - parent.spacing) * 0.45)
                text: "Back to tasks"
                foreground: root.foreground
                bordered: true
                focusable: true
                onClicked: root.cancelCreate()
                Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
              }
              Button {
                id: successOpenButton
                width: parent.width - x
                text: "Open in Vikunja"
                iconText: "󰏌"
                foreground: root.foreground
                active: true
                focusable: true
                enabled: Model.safeHttpsUrl(root.service && root.service.creationResult.task
                  ? root.service.creationResult.task.frontend_url : "") !== ""
                onClicked: root.openTask(root.service.creationResult.task)
                Keys.onEscapePressed: function(event) { root.cancelCreate(); event.accepted = true }
              }
            }
          }
        }

        Row {
          visible: root.viewMode === "tasks" && root.document.status !== "unconfigured"
          width: parent.width
          spacing: Style.space(10)

          Text {
            width: parent.width - newTaskButton.width - titleToggleButton.width - refreshButton.width - parent.spacing * 3
            anchors.verticalCenter: parent.verticalCenter
            text: root.document.fetched_at
              ? "Updated " + Qt.formatDateTime(new Date(root.document.fetched_at), "HH:mm")
              : "Ready"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Button {
            id: newTaskButton
            iconText: "󰐕"
            text: "New task"
            tooltipText: "New task (N)"
            foreground: root.foreground
            fontSize: Style.font.bodySmall
            horizontalPadding: Style.space(8)
            verticalPadding: Style.space(4)
            bordered: true
            focusable: true
            enabled: root.service && !root.service.loading
            onClicked: root.startCreate()
          }

          PanelActionButton {
            id: titleToggleButton
            iconText: root.showTaskTitle ? "󰈈" : "󰈉"
            tooltipText: root.showTaskTitle ? "Hide task title" : "Show task title"
            foreground: root.foreground
            enabled: root.hostWidget !== null
            onClicked: root.toggleShowTaskTitle()
          }

          PanelActionButton {
            id: refreshButton
            iconText: "󰑐"
            tooltipText: "Refresh tasks"
            foreground: root.foreground
            enabled: root.service && !root.service.loading
            onClicked: if (root.service) root.service.refresh()
          }
        }
      }
    }
  }

  Component {
    id: sectionComponent
    PanelSectionHeader {
      width: parent ? parent.width : implicitWidth
      text: String(parent && parent.rowData ? parent.rowData.title : "").toUpperCase()
        + " · " + String(parent && parent.rowData ? parent.rowData.count || 0 : 0)
      foreground: parent && parent.rowData && parent.rowData.title === "Overdue"
        ? root.urgent : root.foreground
      fontFamily: root.fontFamily
      topPadding: Style.space(7)
    }
  }

  Component {
    id: taskComponent
    Rectangle {
      id: taskRow
      property var rowData: parent && parent.rowData ? parent.rowData : ({ task: ({}) })
      readonly property var task: rowData.task
      readonly property int taskIndex: {
        for (var i = 0; i < root.tasks.length; i++)
          if (Number(root.tasks[i].id) === Number(task.id)) return i
        return -1
      }
      width: parent ? parent.width : Style.space(420)
      implicitHeight: taskLabels.implicitHeight + Style.space(18)
      radius: Style.cornerRadius
      color: taskMouse.containsMouse || root.cursorIndex === taskIndex
        ? Style.hoverFillFor(root.foreground, Color.accent, root.urgent)
        : (task.due_state === "overdue" ? Util.alpha(root.urgent, 0.08) : "transparent")

      Rectangle {
        visible: task.due_state === "overdue"
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        width: Style.space(3)
        radius: width / 2
        color: root.urgent
      }

      Column {
        id: taskLabels
        anchors.left: parent.left
        anchors.right: dueColumn.left
        anchors.leftMargin: Style.space(task.due_state === "overdue" ? 13 : 10)
        anchors.rightMargin: Style.space(12)
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(3)

        Text {
          width: parent.width
          text: String(task.title || "Untitled task")
          color: task.due_state === "overdue" ? root.urgent : root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: true
          elide: Text.ElideRight
        }
        Text {
          width: parent.width
          text: String(task.identifier || "") + " · " + String(task.project_title || "Unknown project")
            + (Number(task.priority || 0) > 0 ? " · P" + String(task.priority) : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Column {
        id: dueColumn
        anchors.right: openButton.left
        anchors.rightMargin: Style.space(7)
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(108)
        spacing: Style.space(1)

        Text {
          visible: task.due_state === "overdue"
          width: parent.width
          text: "OVERDUE"
          color: root.urgent
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
          horizontalAlignment: Text.AlignRight
        }
        Text {
          width: parent.width
          text: String(task.relative_due || "")
          color: task.due_state === "overdue" ? root.urgent : root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: task.due_state === "overdue"
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideRight
        }
      }

      MouseArea {
        id: taskMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: if (taskRow.taskIndex >= 0) root.cursorIndex = taskRow.taskIndex
        onClicked: root.openTask(taskRow.task)
      }

      PanelActionButton {
        id: openButton
        anchors.right: parent.right
        anchors.rightMargin: Style.space(7)
        anchors.verticalCenter: parent.verticalCenter
        iconText: "󰏌"
        tooltipText: "Open in Vikunja"
        foreground: task.due_state === "overdue" ? root.urgent : root.foreground
        enabled: Model.safeHttpsUrl(task.frontend_url) !== ""
        onClicked: root.openTask(taskRow.task)
      }
    }
  }
}
