/*
 * SwitchTail Board — a Plasma 6 panel widget over the `stail` CLI.
 *
 *   panel heading : `stail active --json`  -> the focused lab (or "SwitchTail" off-board)
 *   popup list    : `stail list --json`    -> every lab + running state
 *   patch a board  : select labs / a custom dir, set a per-row session count, then
 *                    `stail patch lab=…*N dir=…*N …` -> ONE window, panes packed 5-per-tab
 *   raise running  : `stail switch <lab>`  -> jump to an already-running board
 *
 * Accessibility: the running/idle distinction is carried by TEXT ("running"/"idle") and
 * lightness/weight — never by red<->green — so it reads correctly on a daltonized/colour-
 * vision-deficient setup. Selection is a standard multi-select checkbox per row.
 * Every action is icon + text.
 */
import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents
import org.kde.kirigami as Kirigami

PlasmoidItem {
    id: root

    // ---- configuration (works even without a config schema, via the fallbacks) ----
    readonly property string stailCmd: (Plasmoid.configuration.stailCommand && Plasmoid.configuration.stailCommand.length > 0)
        ? Plasmoid.configuration.stailCommand
        : "$HOME/.local/bin/stail"
    readonly property int pollIntervalMs: Math.max(1000, Plasmoid.configuration.pollIntervalMs || 2000)
    // Panes-per-tab cap; mirrors the CLI's SWITCHTAIL_TAB_SIZE (default 5). The CLI re-clamps
    // each row to this server-side, so the per-row spinbox just shares the same ceiling.
    readonly property int tabSize: Math.max(1, Plasmoid.configuration.tabSize || 5)

    // ---- live state ----
    property string activeLab: ""      // focused lab key; "" when not on a board
    property string activeDisplay: ""  // its PascalCase display name (from `active --json`)
    property bool activeExchange: false  // focused window is the exchange (all-labs) board
    property bool ready: false         // a list result has come back at least once

    // The cart model: one entry per selectable row (a lab, or an added custom dir).
    // { key, display, dir, isLab, running, selected, count }. Held here (NOT in the recycled
    // delegate) so scrolling can't lose a row's checkbox/count. Mutators reassign the array so
    // bindings re-evaluate.
    property var rows: []

    readonly property int runningCount: {
        var n = 0;
        for (var i = 0; i < rows.length; ++i) if (rows[i].running) ++n;
        return n;
    }
    readonly property int selectedPanes: {
        var n = 0;
        for (var i = 0; i < rows.length; ++i) if (rows[i].selected) n += rows[i].count;
        return n;
    }
    readonly property int tabCount: selectedPanes > 0 ? Math.ceil(selectedPanes / tabSize) : 0

    preferredRepresentation: compactRepresentation
    Plasmoid.icon: "utilities-terminal"

    toolTipMainText: i18n("SwitchTail Board")
    toolTipSubText: activeLab !== ""
        ? i18n("Focused: %1  ·  %2 running", activeDisplay, runningCount)
        : i18n("Not on a board  ·  %1 running", runningCount)

    RunStail { id: stail }

    // ---- row model maintenance ----
    // Merge a fresh `stail list --json` result into rows: update each lab's running flag, add
    // any new labs (selected=false, count=1), and preserve every row's selected/count + any
    // custom-dir rows the user added.
    function mergeLabs(labArr) {
        var next = [];
        var byKey = {};
        for (var i = 0; i < rows.length; ++i) byKey[rows[i].key] = rows[i];
        // labs first, in the CLI's order
        for (var j = 0; j < labArr.length; ++j) {
            var l = labArr[j];
            var prev = byKey["lab:" + l.lab];
            next.push({
                key: "lab:" + l.lab,
                display: l.display,
                dir: "",                 // a lab resolves to ~/JangLabs/<lab> server-side
                isLab: true,
                lab: l.lab,
                running: !!l.running,
                selected: prev ? prev.selected : false,
                count: prev ? prev.count : 1
            });
        }
        // then keep custom-dir rows (not in the lab list) in their existing order
        for (var k = 0; k < rows.length; ++k) {
            if (!rows[k].isLab) next.push(rows[k]);
        }
        root.rows = next;
    }

    function setRowSelected(index, value) {
        if (index < 0 || index >= rows.length) return;
        var copy = rows.slice();
        copy[index] = Object.assign({}, copy[index], { selected: value });
        root.rows = copy;
    }
    function setRowCount(index, value) {
        if (index < 0 || index >= rows.length) return;
        var c = Math.max(1, Math.min(root.tabSize, Math.floor(Number(value) || 1)));
        var copy = rows.slice();
        copy[index] = Object.assign({}, copy[index], { count: c });
        root.rows = copy;
    }
    function addCustomDir(path) {
        var p = String(path || "").trim();
        if (p.length === 0) return;
        // de-dupe by path; if already present, just select it
        for (var i = 0; i < rows.length; ++i) {
            if (!rows[i].isLab && rows[i].dir === p) { setRowSelected(i, true); return; }
        }
        var copy = rows.slice();
        copy.push({
            key: "dir:" + p,
            display: p.replace(/\/+$/, "").split("/").pop() || p,
            dir: p,
            isLab: false,
            lab: "",
            running: false,
            selected: true,
            count: 1
        });
        root.rows = copy;
    }
    function removeRow(index) {
        if (index < 0 || index >= rows.length) return;
        var copy = rows.slice();
        copy.splice(index, 1);
        root.rows = copy;
    }

    // ---- stail calls ----
    function refreshActive() {
        stail.exec(stailCmd + " active --json", function (r) {
            try {
                var d = JSON.parse(r.stdout);
                root.activeLab = d && d.lab ? String(d.lab) : "";
                root.activeDisplay = d && d.display ? String(d.display) : "";
                root.activeExchange = !!(d && d.exchange);
            } catch (e) {
                root.activeLab = "";
                root.activeDisplay = "";
                root.activeExchange = false;
            }
        });
    }

    function refreshList() {
        stail.exec(stailCmd + " list --json", function (r) {
            root.ready = true;  // a result came back -> stop the busy spinner either way
            try {
                var arr = JSON.parse(r.stdout);
                if (Array.isArray(arr)) root.mergeLabs(arr);
            } catch (e) {
                // malformed/empty output (e.g. stail missing) -> keep the prior rows
            }
        });
    }

    function refreshAll() { refreshActive(); refreshList(); }

    function switchTo(lab) {
        stail.exec(stailCmd + " switch " + lab, function () {
            settleTimer.restart();
        });
    }

    // Assemble `lab=…*N` / `dir=…*N` tokens for the selected rows and patch one tabbed board.
    // Lab names come from the CLI-validated list; the custom dir path is single-quoted so spaces
    // and shell metacharacters in it are inert; the count is clamped to [1, tabSize] per row. The
    // CLI re-validates + re-clamps everything regardless.
    function patchBoard() {
        var toks = [];
        for (var i = 0; i < rows.length; ++i) {
            var r = rows[i];
            if (!r.selected) continue;
            var n = Math.max(1, Math.min(root.tabSize, Math.floor(Number(r.count) || 1)));
            if (r.isLab) {
                toks.push("lab=" + r.lab + "*" + n);
            } else {
                toks.push("dir='" + r.dir.replace(/'/g, "'\\''") + "'*" + n);
            }
        }
        if (toks.length === 0) return;
        stail.exec(stailCmd + " patch " + toks.join(" "), function () {
            settleTimer.restart();
        });
    }

    Timer {
        id: settleTimer
        interval: 350
        onTriggered: root.refreshAll()
    }

    Timer {
        id: pollTimer
        interval: root.pollIntervalMs
        running: true
        repeat: true
        triggeredOnStart: true
        // Always track the focused lab cheaply; only fetch the full list while the popup is open.
        onTriggered: {
            root.refreshActive();
            if (root.expanded) root.refreshList();
        }
    }

    onExpandedChanged: if (expanded) refreshList()
    Component.onCompleted: refreshAll()

    // ======================= COMPACT (in the panel) =======================
    compactRepresentation: MouseArea {
        id: compact
        hoverEnabled: true
        readonly property bool showLabel: Plasmoid.formFactor !== PlasmaCore.Types.Vertical
        Layout.minimumWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        Layout.preferredWidth: compactRow.implicitWidth + Kirigami.Units.smallSpacing * 2
        onClicked: root.expanded = !root.expanded
        Accessible.role: Accessible.Button
        Accessible.name: root.activeLab !== ""
            ? i18n("SwitchTail Board, focused lab %1, %2 running", root.activeLab, root.runningCount)
            : i18n("SwitchTail Board, not on a board, %1 running", root.runningCount)

        RowLayout {
            id: compactRow
            anchors.centerIn: parent
            spacing: Kirigami.Units.smallSpacing

            Kirigami.Icon {
                source: "utilities-terminal"
                Layout.preferredHeight: Math.min(compact.height, Kirigami.Units.iconSizes.smallMedium)
                Layout.preferredWidth: Layout.preferredHeight
                opacity: root.activeLab !== "" ? 1.0 : 0.55
            }
            PlasmaComponents.Label {
                text: root.activeLab !== "" ? root.activeDisplay : i18n("SwitchTail")
                font.bold: root.activeLab !== ""
                opacity: root.activeLab !== "" ? 1.0 : 0.7
                visible: compact.showLabel
            }
        }
    }

    // ======================= FULL (the popup) =======================
    fullRepresentation: ColumnLayout {
        Layout.minimumWidth: Kirigami.Units.gridUnit * 17
        Layout.minimumHeight: Kirigami.Units.gridUnit * 18
        Layout.preferredWidth: Kirigami.Units.gridUnit * 19
        Layout.preferredHeight: Kirigami.Units.gridUnit * 24
        spacing: Kirigami.Units.smallSpacing

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            Kirigami.Icon {
                source: "utilities-terminal"
                Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                PlasmaComponents.Label {
                    text: i18n("SwitchTail Board")
                    font.bold: true
                    font.pointSize: Kirigami.Theme.defaultFont.pointSize + 1
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                PlasmaComponents.Label {
                    text: root.activeLab === "" ? i18n("Not on a board")
                        : root.activeExchange ? i18n("Focused: %1 (exchange)", root.activeDisplay)
                        : i18n("Focused: %1", root.activeDisplay)
                    opacity: 0.7
                    font.pointSize: Kirigami.Theme.smallFont.pointSize
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
            }
            PlasmaComponents.ToolButton {
                icon.name: "view-refresh"
                display: PlasmaComponents.AbstractButton.IconOnly
                text: i18n("Refresh")
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: root.refreshAll()
            }
        }

        PlasmaComponents.Label {
            Layout.fillWidth: true
            text: i18n("Tick labs (or add a folder), set how many sessions each, then patch one board.")
            opacity: 0.7
            font.pointSize: Kirigami.Theme.smallFont.pointSize
            wrapMode: Text.WordWrap
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ---- selectable row list (labs + custom dirs) ----
        PlasmaComponents.ScrollView {
            Layout.fillWidth: true
            Layout.fillHeight: true
            contentWidth: availableWidth

            ListView {
                id: rowList
                model: root.rows
                clip: true
                spacing: 0
                boundsBehavior: Flickable.StopAtBounds

                delegate: PlasmaComponents.ItemDelegate {
                    id: row
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    highlighted: modelData.isLab && modelData.lab === root.activeLab
                    hoverEnabled: true
                    // clicking the row body toggles selection (the checkbox is the explicit handle,
                    // but the whole row is a comfortable target)
                    onClicked: root.setRowSelected(index, !modelData.selected)
                    Accessible.name: i18n("%1, %2%3, %4, %5 session%6",
                        modelData.display,
                        modelData.isLab ? (modelData.running ? i18n("running") : i18n("idle")) : i18n("folder"),
                        (modelData.isLab && modelData.lab === root.activeLab) ? i18n(", focused") : "",
                        modelData.selected ? i18n("selected") : i18n("not selected"),
                        modelData.count, modelData.count === 1 ? "" : "s")

                    contentItem: RowLayout {
                        spacing: Kirigami.Units.smallSpacing

                        // selection control: a checkbox — the cart is MULTI-select, so ticking one
                        // never clears the others, and a ticked row can be un-ticked.
                        PlasmaComponents.CheckBox {
                            checked: row.modelData.selected
                            onToggled: root.setRowSelected(row.index, checked)
                            Accessible.name: i18n("Select %1", row.modelData.display)
                        }
                        // focused marker (shape, not colour) — only meaningful for labs
                        PlasmaComponents.Label {
                            text: (row.modelData.isLab && row.modelData.lab === root.activeLab) ? "▸" : " "
                            font.bold: true
                            opacity: 0.9
                        }
                        // a folder glyph for custom-dir rows (so they read as not-a-lab at a glance)
                        Kirigami.Icon {
                            visible: !row.modelData.isLab
                            source: "folder"
                            Layout.preferredHeight: Kirigami.Units.iconSizes.small
                            Layout.preferredWidth: Kirigami.Units.iconSizes.small
                        }
                        PlasmaComponents.Label {
                            text: row.modelData.display
                            font.bold: row.modelData.isLab && row.modelData.lab === root.activeLab
                            Layout.fillWidth: true
                            elide: Text.ElideMiddle
                            PlasmaComponents.ToolTip.text: row.modelData.isLab ? row.modelData.display : row.modelData.dir
                            PlasmaComponents.ToolTip.visible: row.hovered && !row.modelData.isLab
                            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        // redundant running/idle text cue (labs only)
                        PlasmaComponents.Label {
                            visible: row.modelData.isLab
                            text: row.modelData.running ? i18n("running") : i18n("idle")
                            opacity: 0.8
                            font.pointSize: Kirigami.Theme.smallFont.pointSize
                        }
                        // raise an already-running lab board directly (no need to patch)
                        PlasmaComponents.ToolButton {
                            visible: row.modelData.isLab && row.modelData.running
                            icon.name: "go-jump"
                            display: PlasmaComponents.AbstractButton.IconOnly
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            opacity: (hovered || row.hovered) ? 1.0 : 0.55
                            text: i18n("Raise the running %1 board", row.modelData.display)
                            Accessible.name: text
                            PlasmaComponents.ToolTip.text: text
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                            onClicked: root.switchTo(row.modelData.lab)
                        }
                        // per-row session count (1..tabSize). A spinbox inside the delegate consumes
                        // its own input, so adjusting it does NOT toggle the row. Fixed width so it
                        // can't grow and shove the trailing remove button past the row edge.
                        PlasmaComponents.SpinBox {
                            from: 1
                            to: root.tabSize
                            value: row.modelData.count
                            Layout.preferredWidth: Kirigami.Units.gridUnit * 5
                            onValueModified: root.setRowCount(row.index, value)
                            Accessible.name: i18n("Sessions for %1, 1 to %2", row.modelData.display, root.tabSize)
                            PlasmaComponents.ToolTip.text: i18n("Sessions (panes) to open for this row")
                            PlasmaComponents.ToolTip.visible: hovered
                            PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                        }
                        // trailing remove slot — a fixed-width holder so the SpinBox column lines up
                        // between lab rows (no remove) and custom-dir rows (removable).
                        Item {
                            Layout.preferredWidth: Kirigami.Units.iconSizes.smallMedium
                            Layout.preferredHeight: Kirigami.Units.iconSizes.smallMedium
                            PlasmaComponents.ToolButton {
                                anchors.fill: parent
                                visible: !row.modelData.isLab
                                icon.name: "list-remove"
                                display: PlasmaComponents.AbstractButton.IconOnly
                                opacity: (hovered || row.hovered) ? 1.0 : 0.55
                                text: i18n("Remove %1", row.modelData.display)
                                Accessible.name: text
                                PlasmaComponents.ToolTip.text: text
                                PlasmaComponents.ToolTip.visible: hovered
                                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                                onClicked: root.removeRow(row.index)
                            }
                        }
                    }
                }

                PlasmaComponents.Label {
                    anchors.centerIn: parent
                    width: parent.width - Kirigami.Units.largeSpacing * 2
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.WordWrap
                    opacity: 0.6
                    visible: root.ready && rowList.count === 0
                    text: i18n("No labs found.\nIs stail installed and is ~/JangLabs populated?")
                }
                PlasmaComponents.BusyIndicator {
                    anchors.centerIn: parent
                    running: visible
                    visible: !root.ready
                }
            }
        }

        // ---- add a custom work directory ----
        RowLayout {
            Layout.fillWidth: true
            spacing: Kirigami.Units.smallSpacing
            PlasmaComponents.TextField {
                id: dirField
                Layout.fillWidth: true
                placeholderText: i18n("Add a folder path, e.g. ~/projects/foo")
                onAccepted: { root.addCustomDir(text); text = ""; }
                Accessible.name: i18n("Custom work directory path")
            }
            PlasmaComponents.ToolButton {
                icon.name: "list-add"
                display: PlasmaComponents.AbstractButton.IconOnly
                enabled: dirField.text.trim().length > 0
                text: i18n("Add folder")
                Accessible.name: text
                PlasmaComponents.ToolTip.text: text
                PlasmaComponents.ToolTip.visible: hovered
                PlasmaComponents.ToolTip.delay: Kirigami.Units.toolTipDelay
                onClicked: { root.addCustomDir(dirField.text); dirField.text = ""; }
            }
        }

        Kirigami.Separator { Layout.fillWidth: true }

        // ---- patch the assembled board ----
        PlasmaComponents.Button {
            Layout.fillWidth: true
            icon.name: "media-playback-start"
            enabled: root.selectedPanes > 0
            // Build the count phrases separately (each a well-formed single-%1 plural), then
            // compose — avoids the nested-i18np arg-count pitfall that produced
            // I18N_EXCESS_ARGUMENTS_SUPPLIED when the outer call got an extra argument.
            readonly property string panePhrase: i18np("%1 pane", "%1 panes", root.selectedPanes)
            readonly property string tabPhrase: i18np("%1 tab", "%1 tabs", root.tabCount)
            text: root.selectedPanes > 0
                ? i18n("Patch board — %1, %2", panePhrase, tabPhrase)
                : i18n("Patch board — nothing selected")
            Accessible.name: text
            onClicked: root.patchBoard()
        }
    }
}
