import QtQuick 2.15
import QtTest 1.3
import "../Model.js" as Model

TestCase {
  name: "KunjaModel"

  function task(id, title, state) {
    return {
      id: id,
      title: title,
      due_state: state,
      frontend_url: "https://vikunja.example.test/tasks/" + id
    }
  }

  function document(tasks, status) {
    return {
      schema_version: 1,
      status: status || "ok",
      fetched_at: "2026-08-30T10:00:00Z",
      api_version: "v2",
      endpoint: "https://vikunja.example.test",
      task_count: tasks.length,
      overdue_count: tasks.filter(function(value) { return value.due_state === "overdue" }).length,
      tasks: tasks,
      error: { kind: "", message: "" }
    }
  }

  function test_parseValidDocument() {
    var source = document([task(1, "Ship release", "today")])
    var parsed = Model.parseSync(JSON.stringify(source))
    compare(parsed.status, "ok")
    compare(parsed.tasks.length, 1)
  }

  function test_invalidDocumentIsError() {
    var parsed = Model.parseSync("not json")
    compare(parsed.status, "error")
    compare(parsed.error.kind, "invalid-data")
  }

  function test_barTextShowsNextTaskAndCount() {
    var source = document([
      task(1, "A deliberately long title that will be shortened for the bar", "overdue"),
      task(2, "Second", "today")
    ])
    var label = Model.barText(source, false)
    verify(label.indexOf("1 late") > 0)
    verify(label.length < 50)
    compare(Model.barText(source, true), "󰀦")
    compare(Model.barIcon(source), "󰀦")
    compare(Model.barBadge(source), "1 late")
  }

  function test_panelRowsAreGrouped() {
    var rows = Model.panelRows([
      task(1, "Late", "overdue"),
      task(2, "Now", "today"),
      task(3, "Later", "upcoming")
    ])
    compare(rows.length, 6)
    compare(rows[0].title, "Overdue")
    compare(rows[0].count, 1)
    compare(rows[2].title, "Today")
    compare(rows[4].title, "Upcoming")
  }

  function test_dueDateTimeRequiresARealLocalDateAndTime() {
    compare(Model.dueDateTimeIso("2026-02-30", "09:00"), "")
    compare(Model.dueDateTimeIso("2026-09-01", "24:00"), "")
    verify(Model.dueDateTimeIso("2026-09-01", "16:30").length > 0)
  }

  function test_onlyHttpsTaskUrlsAreAccepted() {
    compare(Model.safeHttpsUrl("https://vikunja.example.test/tasks/1"), "https://vikunja.example.test/tasks/1")
    compare(Model.safeHttpsUrl("javascript:alert(1)"), "")
    compare(Model.safeHttpsUrl("https://example.test/a b"), "")
  }
}
