import QtQuick
import Quickshell
import Quickshell.Io
import "Model.js" as Model

Item {
  id: root

  visible: false
  width: 0
  height: 0

  property var shell: null
  property var manifest: null
  readonly property string pluginDir: manifest && manifest.__sourceDir
    ? String(manifest.__sourceDir) : ""
  readonly property string helperPath: pluginDir !== ""
    ? pluginDir + "/bin/kunja" : ""

  property var document: Model.parseSync("")
  property bool loading: false
  property bool refreshPending: false
  property int refreshMinutes: 5
  property int horizonDays: 14
  property int reminderMinutes: 60
  property int maxTasks: 50
  property bool createOptionsLoading: false
  property bool projectUsersLoading: false
  property int projectUsersPendingId: 0
  property bool creationBusy: false
  property var currentUser: ({})
  property var createProjects: []
  property var projectUsers: []
  property var createOptionsError: ({ kind: "", message: "" })
  property var projectUsersError: ({ kind: "", message: "" })
  property var creationResult: ({ status: "", task: ({}), message: "", error: ({}) })

  signal createFinished(var result)

  readonly property var tasks: document && Array.isArray(document.tasks) ? document.tasks : []
  readonly property int taskCount: Number(document && document.task_count || 0)
  readonly property int overdueCount: Number(document && document.overdue_count || 0)
  readonly property string status: String(document && document.status || "unconfigured")
  readonly property string errorMessage: document && document.error
    ? String(document.error.message || "") : ""

  function bounded(value, fallback, minimum, maximum) {
    var parsed = Math.floor(Number(value))
    if (isNaN(parsed)) parsed = fallback
    return Math.max(minimum, Math.min(maximum, parsed))
  }

  function adoptSettings(values) {
    var settings = values || ({})
    var nextRefresh = bounded(settings.refreshMinutes, 5, 1, 60)
    var nextHorizon = bounded(settings.horizonDays, 14, 1, 365)
    var nextReminder = bounded(settings.reminderMinutes, 60, 0, 1440)
    var nextMaximum = bounded(settings.maxTasks, 50, 10, 200)
    var queryChanged = nextHorizon !== horizonDays
      || nextReminder !== reminderMinutes || nextMaximum !== maxTasks
    refreshMinutes = nextRefresh
    horizonDays = nextHorizon
    reminderMinutes = nextReminder
    maxTasks = nextMaximum
    refreshTimer.interval = refreshMinutes * 60 * 1000
    if (queryChanged) Qt.callLater(refresh)
  }

  function refresh() {
    if (syncProcess.running) {
      refreshPending = true
      return
    }
    if (helperPath === "") {
      document = Model.errorDocument("missing-helper", "Could not locate the Kunja helper.")
      return
    }
    loading = true
    syncProcess.command = [
      "python3", helperPath, "sync", "--json", "--notify",
      "--horizon-days", String(horizonDays),
      "--reminder-minutes", String(reminderMinutes),
      "--max-tasks", String(maxTasks)
    ]
    syncProcess.running = true
  }

  function helperDocument(raw, fallback) {
    try {
      var parsed = JSON.parse(String(raw || ""))
      if (parsed && typeof parsed === "object") return parsed
    } catch (error) {}
    return {
      status: "error",
      error: { kind: "helper-failed", message: fallback || "Kunja returned an invalid response." }
    }
  }

  function loadCreateOptions() {
    if (createOptionsProcess.running || helperPath === "") return
    createOptionsLoading = true
    createOptionsError = ({ kind: "", message: "" })
    createOptionsProcess.command = ["python3", helperPath, "create-options", "--json"]
    createOptionsProcess.running = true
  }

  function loadProjectUsers(projectId) {
    var id = Math.floor(Number(projectId))
    projectUsers = []
    projectUsersError = ({ kind: "", message: "" })
    if (id <= 0 || helperPath === "") return
    if (projectUsersProcess.running) {
      projectUsersPendingId = id
      return
    }
    projectUsersPendingId = 0
    projectUsersLoading = true
    projectUsersProcess.command = [
      "python3", helperPath, "project-users", "--project-id", String(id), "--json"
    ]
    projectUsersProcess.running = true
  }

  function createTask(payload) {
    if (creationProcess.running || helperPath === "") return
    creationBusy = true
    creationResult = ({ status: "", task: ({}), message: "", error: ({}) })
    creationProcess.pendingJson = JSON.stringify(payload || ({}))
    creationProcess.command = ["python3", helperPath, "create-task", "--json"]
    creationProcess.running = true
  }

  function setupCommand() {
    return helperPath === "" ? "" : "python3 " + helperPath + " configure"
  }

  function applyOutput(raw, fallbackError) {
    var parsed = Model.parseSync(raw)
    if (parsed.status === "error" && parsed.error.message === "The Kunja helper returned invalid JSON."
        && fallbackError !== "")
      parsed = Model.errorDocument("helper-failed", fallbackError)
    document = parsed
  }

  Timer {
    id: refreshTimer
    interval: root.refreshMinutes * 60 * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Timer {
    interval: 350
    running: true
    onTriggered: root.refresh()
  }

  Process {
    id: syncProcess
    stdout: StdioCollector { id: syncOutput; waitForEnd: true }
    stderr: StdioCollector { id: syncError; waitForEnd: true }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.loading = false
        var fallback = String(syncError.text || "").trim()
        root.applyOutput(syncOutput.text, fallback)
        if (root.refreshPending) {
          root.refreshPending = false
          Qt.callLater(root.refresh)
        }
      })
    }
  }

  Process {
    id: createOptionsProcess
    stdout: StdioCollector { id: createOptionsOutput; waitForEnd: true }
    stderr: StdioCollector { id: createOptionsErrorOutput; waitForEnd: true }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.createOptionsLoading = false
        var parsed = root.helperDocument(createOptionsOutput.text,
          String(createOptionsErrorOutput.text || "").trim())
        if (parsed.status === "ok") {
          root.currentUser = parsed.current_user || ({})
          root.createProjects = Array.isArray(parsed.projects) ? parsed.projects : []
          root.createOptionsError = ({ kind: "", message: "" })
        } else {
          root.createProjects = []
          root.createOptionsError = parsed.error || ({ kind: "unknown", message: "Could not load projects." })
        }
      })
    }
  }

  Process {
    id: projectUsersProcess
    stdout: StdioCollector { id: projectUsersOutput; waitForEnd: true }
    stderr: StdioCollector { id: projectUsersErrorOutput; waitForEnd: true }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.projectUsersLoading = false
        var parsed = root.helperDocument(projectUsersOutput.text,
          String(projectUsersErrorOutput.text || "").trim())
        if (parsed.status === "ok") {
          root.projectUsers = Array.isArray(parsed.users) ? parsed.users : []
          root.projectUsersError = ({ kind: "", message: "" })
        } else {
          root.projectUsers = []
          root.projectUsersError = parsed.error || ({ kind: "unknown", message: "Could not load users." })
        }
        var pendingId = root.projectUsersPendingId
        root.projectUsersPendingId = 0
        if (pendingId > 0) Qt.callLater(function() { root.loadProjectUsers(pendingId) })
      })
    }
  }

  Process {
    id: creationProcess
    property string pendingJson: ""
    stdinEnabled: true
    stdout: StdioCollector { id: creationOutput; waitForEnd: true }
    stderr: StdioCollector { id: creationErrorOutput; waitForEnd: true }
    onStarted: {
      write(pendingJson + "\n")
      pendingJson = ""
    }
    onExited: function(exitCode) {
      Qt.callLater(function() {
        root.creationBusy = false
        var parsed = root.helperDocument(creationOutput.text,
          String(creationErrorOutput.text || "").trim())
        root.creationResult = parsed
        if (parsed.status === "ok" || parsed.status === "partial") root.refresh()
        root.createFinished(parsed)
      })
    }
  }

  IpcHandler {
    target: "io.github.guzzy711.kunja.service"
    function refresh() { root.refresh() }
    function status() { return root.status }
  }
}
