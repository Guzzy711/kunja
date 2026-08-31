.pragma library

var EMPTY_DOCUMENT = {
  schema_version: 1,
  status: "unconfigured",
  fetched_at: "",
  api_version: "",
  endpoint: "",
  task_count: 0,
  overdue_count: 0,
  tasks: [],
  error: { kind: "unconfigured", message: "Run the setup command to connect Vikunja." }
}

function copyEmpty() {
  return {
    schema_version: EMPTY_DOCUMENT.schema_version,
    status: EMPTY_DOCUMENT.status,
    fetched_at: EMPTY_DOCUMENT.fetched_at,
    api_version: EMPTY_DOCUMENT.api_version,
    endpoint: EMPTY_DOCUMENT.endpoint,
    task_count: EMPTY_DOCUMENT.task_count,
    overdue_count: EMPTY_DOCUMENT.overdue_count,
    tasks: [],
    error: {
      kind: EMPTY_DOCUMENT.error.kind,
      message: EMPTY_DOCUMENT.error.message
    }
  }
}

function parseSync(raw) {
  if (!raw) return copyEmpty()
  try {
    var parsed = JSON.parse(String(raw))
    if (!parsed || parsed.schema_version !== 1 || !Array.isArray(parsed.tasks))
      return errorDocument("invalid-data", "The Kunja helper returned an unsupported response.")
    parsed.task_count = Math.max(0, Number(parsed.task_count) || parsed.tasks.length)
    parsed.overdue_count = Math.max(0, Number(parsed.overdue_count) || 0)
    parsed.status = String(parsed.status || "error")
    parsed.error = parsed.error && typeof parsed.error === "object"
      ? parsed.error : { kind: "", message: "" }
    return parsed
  } catch (error) {
    return errorDocument("invalid-data", "The Kunja helper returned invalid JSON.")
  }
}

function errorDocument(kind, message) {
  var doc = copyEmpty()
  doc.status = "error"
  doc.error = { kind: String(kind || "unknown"), message: String(message || "Unknown error") }
  return doc
}

function nextTask(tasks) {
  return tasks && tasks.length > 0 ? tasks[0] : null
}

function compactTitle(title, maximum) {
  var value = String(title || "").replace(/\s+/g, " ").trim()
  var cap = Math.max(8, Number(maximum) || 34)
  return value.length <= cap ? value : value.slice(0, cap - 1).trim() + "…"
}

function barIcon(document) {
  var doc = document || copyEmpty()
  return Number(doc.overdue_count || 0) > 0 ? "󰀦" : "󰄬"
}

function barTitle(document) {
  var doc = document || copyEmpty()
  if (doc.status === "unconfigured") return "Setup"
  if (doc.status === "error" && (!doc.tasks || doc.tasks.length === 0)) return "Offline"
  if (!doc.tasks || doc.tasks.length === 0) return "Clear"
  return compactTitle(nextTask(doc.tasks).title, 22)
}

function barBadge(document) {
  var doc = document || copyEmpty()
  var overdue = Math.max(0, Number(doc.overdue_count) || 0)
  if (overdue > 0) return overdue + " late"
  var count = Math.max(0, Number(doc.task_count) || 0)
  return count > 0 ? String(count) : ""
}

function barText(document, vertical) {
  var doc = document || copyEmpty()
  if (vertical) return barIcon(doc)
  var badge = barBadge(doc)
  return barIcon(doc) + " " + barTitle(doc) + (badge ? " " + badge : "")
}

function tooltip(document) {
  var doc = document || copyEmpty()
  if (doc.status === "unconfigured") return "Kunja needs configuration"
  if (doc.status === "error") return doc.error.message || "Could not refresh Vikunja"
  if (doc.status === "stale") return "Showing cached tasks · " + (doc.error.message || "refresh failed")
  if (!doc.tasks || doc.tasks.length === 0) return "No assigned tasks due in the watch window"
  if (doc.overdue_count > 0)
    return doc.overdue_count + (doc.overdue_count === 1 ? " overdue task" : " overdue tasks")
  return doc.task_count + (doc.task_count === 1 ? " watched task" : " watched tasks")
}

function sectionFor(task) {
  var state = String(task && task.due_state || "upcoming")
  if (state === "overdue") return "Overdue"
  if (state === "today") return "Today"
  return "Upcoming"
}

function panelRows(tasks) {
  var result = []
  var previous = ""
  var source = Array.isArray(tasks) ? tasks : []
  var counts = { Overdue: 0, Today: 0, Upcoming: 0 }
  for (var countIndex = 0; countIndex < source.length; countIndex++)
    counts[sectionFor(source[countIndex])] += 1
  for (var i = 0; i < source.length; i++) {
    var section = sectionFor(source[i])
    if (section !== previous) {
      result.push({ row_type: "header", title: section, count: counts[section] })
      previous = section
    }
    result.push({ row_type: "task", task: source[i] })
  }
  return result
}

function taskRows(rows) {
  var result = []
  var source = Array.isArray(rows) ? rows : []
  for (var i = 0; i < source.length; i++)
    if (source[i] && source[i].row_type === "task") result.push(source[i].task)
  return result
}

function statusLabel(document) {
  var doc = document || copyEmpty()
  if (doc.status === "unconfigured") return "NOT CONNECTED"
  if (doc.status === "error") return "REFRESH FAILED"
  if (doc.status === "stale") return "CACHED · REFRESH FAILED"
  if (doc.status === "loading") return "REFRESHING"
  return doc.api_version ? "CONNECTED · API " + String(doc.api_version).toUpperCase() : "CONNECTED"
}

function safeHttpsUrl(value) {
  var url = String(value || "")
  return /^https:\/\/[A-Za-z0-9.-]+(?::[0-9]+)?(?:\/[^\s]*)?$/.test(url) ? url : ""
}


function dueDateTimeIso(dateText, timeText) {
  var dateMatch = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(dateText || "").trim())
  var timeMatch = /^(\d{2}):(\d{2})$/.exec(String(timeText || "").trim())
  if (!dateMatch || !timeMatch) return ""
  var year = Number(dateMatch[1])
  var month = Number(dateMatch[2])
  var day = Number(dateMatch[3])
  var hour = Number(timeMatch[1])
  var minute = Number(timeMatch[2])
  if (month < 1 || month > 12 || day < 1 || day > 31 || hour > 23 || minute > 59) return ""
  var value = new Date(year, month - 1, day, hour, minute, 0, 0)
  if (isNaN(value.getTime()) || value.getFullYear() !== year || value.getMonth() !== month - 1
      || value.getDate() !== day || value.getHours() !== hour || value.getMinutes() !== minute)
    return ""
  return value.toISOString()
}
