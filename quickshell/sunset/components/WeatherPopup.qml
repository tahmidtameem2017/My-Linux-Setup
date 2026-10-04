// WeatherPopup.qml — current conditions card + location search.
//
// Hero (temp / condition / place) → 4 stat cells → divider → city+country
// row. No form labels, no dot-separated sentence stats, no duplicated
// location line: the place is the hero's third line instead of a separate
// row, and the fields carry placeholders only.
//
// Shell contract (landed sunset pattern, cf. VolumePopup/CalendarPopup):
//   - exclusiveKeyboardFocus == WlrLayershell.keyboardFocus Exclusive.
//   - Esc closes; outside-click closes; Bar re-click toggles via IPC.
//   - Card width 400 (sibling popups), height is content-driven.
// IPC: `qs -c sunset ipc call weather toggle` (also: open, close)

import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.services

Scope {
    id: root

    readonly property color cAccent: Theme.accent
    readonly property color cAccentHover: Theme.accentHover
    readonly property color cBg: Theme.bg
    readonly property color cBorder: Theme.border
    readonly property color cBorderStrong: Theme.borderStrong
    readonly property color cDim: Theme.dim
    readonly property string cFont: Theme.fontFamily
    readonly property color cMuted: Theme.muted
    readonly property color cPanel: Theme.panel
    readonly property int cRadius: Theme.radius
    readonly property color cRow: Theme.row
    readonly property color cText: Theme.text

    property bool isOpen: false

    // Keep the last reading on screen while a refresh is in flight — only
    // the one-line status below the hero changes, nothing blanks out.
    readonly property bool hasData: WeatherService.current !== null
    readonly property bool hasError: WeatherService.lastError !== ""

    readonly property string heroTemp: hasData ? WeatherService.temperature : "--°"
    readonly property string heroCondition: hasData ? WeatherService.condition(WeatherService.current.weather_code) : (WeatherService.city !== "" ? "No reading yet" : "No location set")
    readonly property string heroPlace: WeatherService.city !== "" ? WeatherService.city + ", " + WeatherService.country : ""

    readonly property string statusText: WeatherService.loading ? "Fetching forecast…" : (hasError ? WeatherService.lastError : (hasData ? "" : "Pick a city and country below."))

    // Four equal cells; keeps the digits from reflowing the card.
    readonly property var stats: {
        if (!hasData)
            return [];
        const c = WeatherService.current;
        const d = WeatherService.daily;
        const out = [ { label: "FEELS", value: Math.round(c.apparent_temperature) + "°" }, { label: "HUMIDITY", value: Math.round(c.relative_humidity_2m) + "%" }, { label: "WIND", value: Math.round(c.wind_speed_10m) + " km/h" } ];
        if (d)
            out.push({ label: "HIGH / LOW", value: Math.round(d.temperature_2m_max[0]) + "° / " + Math.round(d.temperature_2m_min[0]) + "°" });
        else
            out.push({ label: "HIGH / LOW", value: "--" });
        return out;
    }

    function open(): void {
        isOpen = true;
        WeatherService.refresh();
        focusTimer.restart();
    }
    function close(): void {
        isOpen = false;
    }
    function toggle(): void {
        if (isOpen)
            close();
        else
            open();
    }

    function save(): void {
        WeatherService.saveLocation(cityInput.text, countryInput.text);
    }

    Timer {
        id: focusTimer
        interval: 60
        repeat: false
        onTriggered: keys.forceActiveFocus()
    }

    PanelWindow {
        id: win
        visible: root.isOpen
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
        WlrLayershell.namespace: "sunset-weather"

        MouseArea {
            anchors.fill: parent
            onClicked: root.close()
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            implicitWidth: Math.min(400, parent.width - 32)
            implicitHeight: Math.min(col.implicitHeight + 32, parent.height - 48)
            width: implicitWidth
            height: implicitHeight
            color: root.cPanel
            border.width: 1
            border.color: root.cBorderStrong
            radius: root.cRadius
            // Same entrance as the sibling popups (VolumePopup parity).
            transformOrigin: Item.Center
            scale: root.isOpen ? 1.0 : 0.96
            opacity: root.isOpen ? 1 : 0
            transform: Translate {
                y: root.isOpen ? 0 : -6
                Behavior on y {
                    NumberAnimation {
                        duration: 150
                        easing.type: Easing.OutCubic
                    }
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: 180
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true
                Keys.onEscapePressed: root.close()
                // Enter saves from anywhere in the card (fields handle it
                // too, via onAccepted).
                Keys.onReturnPressed: root.save()
                Keys.onEnterPressed: root.save()

                Column {
                    id: col
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 0

                    // ---- hero ----
                    Text {
                        id: heroTemp
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: root.heroTemp
                        font.family: root.cFont
                        font.pixelSize: 44
                        font.bold: true
                        color: root.hasData ? root.cText : root.cDim
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideRight
                        text: root.heroCondition
                        font.family: root.cFont
                        font.pixelSize: 13
                        color: root.hasData ? root.cAccent : root.cMuted
                    }
                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        elide: Text.ElideMiddle
                        text: root.heroPlace
                        font.family: root.cFont
                        font.pixelSize: 11
                        color: root.cMuted
                    }

                    Item {
                        width: parent.width
                        height: 14
                    }

                    // ---- stats ----
                    Row {
                        id: statsRow
                        width: parent.width
                        visible: root.hasData && !root.hasError
                        spacing: 8
                        Repeater {
                            model: root.stats
                            delegate: Column {
                                id: statCell
                                required property var modelData
                                required property int index
                                width: (statsRow.width - 3 * statsRow.spacing) / 4
                                x: index * (width + statsRow.spacing)
                                spacing: 4
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: modelData.label
                                    font.family: root.cFont
                                    font.pixelSize: 10
                                    color: root.cMuted
                                }
                                Text {
                                    width: parent.width
                                    horizontalAlignment: Text.AlignHCenter
                                    elide: Text.ElideRight
                                    text: modelData.value
                                    font.family: root.cFont
                                    font.pixelSize: 13
                                    color: root.cText
                                }
                            }
                        }
                    }
                    Text {
                        width: parent.width
                        visible: root.statusText !== ""
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.Wrap
                        text: root.statusText
                        font.family: root.cFont
                        font.pixelSize: 11
                        color: root.hasError ? root.cAccentHover : root.cDim
                    }

                    Item {
                        width: parent.width
                        height: 14
                    }

                    Rectangle {
                        width: parent.width
                        height: 1
                        color: root.cBorder
                    }

                    Item {
                        width: parent.width
                        height: 14
                    }

                    // ---- location: placeholders only, no field labels ----
                    Row {
                        width: parent.width
                        spacing: 6
                        TextField {
                            id: cityInput
                            width: (parent.width - 64 - 12) / 2
                            height: 30
                            padding: 6
                            placeholderText: "City"
                            text: WeatherService.city
                            font.family: root.cFont
                            font.pixelSize: 11
                            color: root.cText
                            placeholderTextColor: root.cDim
                            selectByMouse: true
                            selectionColor: root.cAccent
                            selectedTextColor: root.cBg
                            onAccepted: root.save()
                            background: Rectangle {
                                color: root.cRow
                                border.width: 1
                                border.color: cityInput.activeFocus ? root.cAccent : root.cBorderStrong
                                radius: root.cRadius
                            }
                        }
                        TextField {
                            id: countryInput
                            width: (parent.width - 64 - 12) / 2
                            height: 30
                            padding: 6
                            placeholderText: "Country"
                            text: WeatherService.country
                            font.family: root.cFont
                            font.pixelSize: 11
                            color: root.cText
                            placeholderTextColor: root.cDim
                            selectByMouse: true
                            selectionColor: root.cAccent
                            selectedTextColor: root.cBg
                            onAccepted: root.save()
                            background: Rectangle {
                                color: root.cRow
                                border.width: 1
                                border.color: countryInput.activeFocus ? root.cAccent : root.cBorderStrong
                                radius: root.cRadius
                            }
                        }
                        Rectangle {
                            id: saveBtn
                            width: 64
                            height: 30
                            radius: root.cRadius
                            color: saveMouse.pressed ? root.cAccentHover : root.cAccent
                            Behavior on color {
                                ColorAnimation {
                                    duration: 120
                                }
                            }
                            Text {
                                anchors.centerIn: parent
                                text: "Save"
                                font.family: root.cFont
                                font.pixelSize: 11
                                font.bold: true
                                color: root.cBg
                            }
                            MouseArea {
                                id: saveMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.save()
                            }
                        }
                    }

                    Text {
                        width: parent.width
                        horizontalAlignment: Text.AlignHCenter
                        text: "Enter save · Esc close"
                        font.family: root.cFont
                        font.pixelSize: 10
                        color: root.cMuted
                        topPadding: 12
                    }
                }
            }
        }
    }

    IpcHandler {
        target: "weather"
        function toggle(): void { root.toggle(); }
        function open(): void { root.open(); }
        function close(): void { root.close(); }
    }
}