#!/usr/bin/env bash
set -euo pipefail

repo_root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s "$repo_root/tests" -p 'test_*.py'
qmllint -I /usr/share/omarchy/shell \
  "$repo_root/BarWidget.qml" \
  "$repo_root/Service.qml" \
  "$repo_root/TaskPanel.qml"
env -u QT_QPA_PLATFORMTHEME QT_QPA_PLATFORM=offscreen \
  qmltestrunner -input "$repo_root/tests"
omarchy-plugin-validate "$repo_root"
