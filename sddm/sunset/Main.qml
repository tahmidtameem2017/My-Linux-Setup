// Sunset Orange AMOLED — SDDM theme for niri-setup
// Tokens: taste.md / Theme.qml — black/orange sharp, JetBrainsMono Nerd Font
// No blue gradient, no rounded corners. Based on maya structure, recolored.
// SPDX-License-Identifier: MIT

import QtQuick 2.0
import SddmComponents 2.0

Rectangle {
    id: sunset_root

    // ── Sunset tokens (taste.md) — config.* overrides fallback to hardcoded AMOLED ─
    property color sunsetBg: config.bg ? config.bg : "#000000"
    property color sunsetPanel: config.panel ? config.panel : "#0a0a0a"
    property color sunsetRow: config.row ? config.row : "#141010"
    property color sunsetBorder: config.border ? config.border : "#1a1210"
    property color sunsetBorderStrong: config.borderStrong ? config.borderStrong : "#3D2B24"
    property color sunsetAccent: config.accent ? config.accent : "#E85D2F"
    property color sunsetAccentHover: config.accentHover ? config.accentHover : "#FF8B4A"
    property color sunsetText: config.text ? config.text : "#F7C7A1"
    property color sunsetMuted: config.muted ? config.muted : "#7C8A6A"
    property color sunsetDim: config.dim ? config.dim : "#555555"
    property color sunsetDanger: config.danger ? config.danger : "#c30505"

    // Legacy maya keys — keep for compat if user edited theme.conf old names
    property color primaryShade: config.primaryShade ? config.primaryShade : sunsetPanel
    property color primaryDark: config.primaryDark ? config.primaryDark : sunsetBg
    property color primaryLight: config.primaryLight ? config.primaryLight : sunsetRow
    property color primaryHue1: config.primaryHue1 ? config.primaryHue1 : sunsetRow
    property color primaryHue2: config.primaryHue2 ? config.primaryHue2 : sunsetPanel
    property color primaryHue3: config.primaryHue3 ? config.primaryHue3 : sunsetBorderStrong
    property color accentShade: config.accentShade ? config.accentShade : sunsetAccent
    property color accentLight: config.accentLight ? config.accentLight : sunsetAccentHover
    property color accentHue1: config.accentHue1 ? config.accentHue1 : sunsetAccentHover
    property color accentHue2: config.accentHue2 ? config.accentHue2 : sunsetAccent
    property color accentHue3: config.accentHue3 ? config.accentHue3 : sunsetAccent
    property color normalText: config.normalText ? config.normalText : sunsetText
    property color successText: config.successText ? config.successText : sunsetMuted
    property color failureText: config.failureText ? config.failureText : sunsetDanger
    property color warningText: config.warningText ? config.warningText : sunsetAccentHover
    property color rebootColor: config.rebootColor ? config.rebootColor : sunsetAccent
    property color powerColor: config.powerColor ? config.powerColor : sunsetDanger

    readonly property color defaultBg: sunsetBg

    // ── sizing / typography ─
    readonly property int spUnit: 64
    readonly property int padSym: spUnit / 8
    readonly property int padAsymH: spUnit / 2
    readonly property int padAsymV: spUnit / 8
    readonly property int spFontNormal: 24
    readonly property int spFontSmall: 16
    readonly property string sunsetFont: "JetBrainsMono Nerd Font"

    // live clock
    property date clockDate: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: sunset_root.clockDate = new Date()
    }

    LayoutMirroring.enabled: Qt.locale().textDirection == Qt.RightToLeft
    LayoutMirroring.childrenInherit: true

    TextConstants {
        id: textConstants
    }

    Connections {
        target: sddm
        onLoginSucceeded: {
            prompt_bg.color = successText
            prompt_txt.text = textConstants.loginSucceeded
            sunset_busy.visible = false
            sunset_busy_anim.stop()
            anim_success.start()
        }
        onLoginFailed: {
            prompt_bg.color = failureText
            prompt_txt.text = textConstants.loginFailed
            sunset_busy.visible = false
            sunset_busy_anim.stop()
            anim_failure.start()
        }
        onInformationMessage: {
            prompt_bg.color = failureText
            prompt_txt.text = message
            sunset_busy.visible = false
            sunset_busy_anim.stop()
            anim_failure.start()
        }
    }

    signal tryLogin()
    onTryLogin: {
        sunset_busy.visible = true
        sunset_busy_anim.start()
        sddm.login(sunset_username.text, sunset_password.text, sunset_session.index)
    }

    // ── background per-screen — solid AMOLED black, no blue gradient ─
    Repeater {
        model: screenModel
        Item {
            Rectangle {
                x: geometry.x
                y: geometry.y
                width: geometry.width
                height: geometry.height
                color: sunsetBg
            }
            // subtle orange glow vignette (taste.md resting shadow 15px)
            Rectangle {
                x: geometry.x
                y: geometry.y
                width: geometry.width
                height: geometry.height
                color: "transparent"
                border.color: sunsetAccent
                border.width: 1
                opacity: 0.06
            }
        }
    }

    // ── centered column: time + login card ─
    Column {
        anchors.centerIn: parent
        spacing: 28

        // Time — 11:50 style, huge, peach
        Column {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 4

            Text {
                id: sunset_time
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(sunset_root.clockDate, "hh:mm")
                color: sunsetText
                font.family: sunsetFont
                font.pixelSize: 72
                font.weight: Font.DemiBold
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                // glow: simulated with 2nd text blur layer
            }

            Text {
                id: sunset_date
                anchors.horizontalCenter: parent.horizontalCenter
                text: Qt.formatDateTime(sunset_root.clockDate, "dddd, dd MMMM yyyy")
                color: sunsetMuted
                font.family: sunsetFont
                font.pixelSize: 16
                horizontalAlignment: Text.AlignHCenter
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: textConstants.welcomeText.arg(sddm.hostName)
                color: sunsetDim
                font.family: sunsetFont
                font.pixelSize: 12
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                width: 400
            }
        }

        // Login card — sharp rectangles (radius 0), panel #0a0a0a, border #3D2B24
        Rectangle {
            id: loginCard
            anchors.horizontalCenter: parent.horizontalCenter
            width: 6 * spUnit
            height: 5.8 * spUnit
            color: sunsetPanel
            border.color: sunsetBorderStrong
            border.width: 1
            radius: 0

            // resting glow outer
            Rectangle {
                anchors.fill: parent
                anchors.margins: -1
                color: "transparent"
                border.color: sunsetAccent
                border.width: 1
                opacity: 0.12
                radius: 0
                z: -1
            }

            // avatar row — sharp square, initial letter
            Row {
                id: avatarRow
                x: padSym
                y: padSym
                width: parent.width - padSym * 2
                height: spUnit * 1.1
                spacing: 12

                Rectangle {
                    width: spUnit * 1.1
                    height: spUnit * 1.1
                    color: sunsetRow
                    border.color: sunsetBorderStrong
                    border.width: 1
                    radius: 0

                    Text {
                        anchors.centerIn: parent
                        text: sunset_username.text.length > 0 ? sunset_username.text.charAt(0).toUpperCase() : (userModel.lastUser ? userModel.lastUser.charAt(0).toUpperCase() : "●")
                        color: sunsetAccent
                        font.family: sunsetFont
                        font.pixelSize: 28
                        font.bold: true
                    }
                }

                Column {
                    width: parent.width - spUnit * 1.1 - 12
                    height: parent.height
                    spacing: 2
                    anchors.verticalCenter: parent.verticalCenter

                    Text {
                        width: parent.width
                        height: 20
                        text: userModel.lastUser ? userModel.lastUser : textConstants.userName
                        color: sunsetText
                        font.family: sunsetFont
                        font.pixelSize: 16
                        font.bold: true
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }

                    Text {
                        width: parent.width
                        height: 16
                        text: sddm.hostName + " — " + (sessionModel.count > 0 ? "niri" : "")
                        color: sunsetDim
                        font.family: sunsetFont
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }

            // username label
            Row {
                x: padSym
                y: avatarRow.y + avatarRow.height + 8
                width: parent.width - padSym * 2
                height: 18

                Text {
                    width: parent.width
                    height: parent.height
                    text: textConstants.userName
                    color: sunsetMuted
                    font.family: sunsetFont
                    font.pixelSize: spFontSmall - 2
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignBottom
                }
            }

            // username field — row #141010, border #3D2B24, focus #E85D2F
            Row {
                x: padSym
                y: avatarRow.y + avatarRow.height + 26
                width: parent.width - padSym * 2
                height: spUnit - padSym * 2

                TextBox {
                    id: sunset_username
                    width: parent.width
                    height: parent.height
                    color: sunsetRow
                    borderColor: sunsetBorderStrong
                    focusColor: sunsetAccent
                    hoverColor: sunsetAccentHover
                    textColor: sunsetText
                    radius: 0
                    font.family: sunsetFont
                    font.pixelSize: spFontSmall
                    text: userModel.lastUser

                    KeyNavigation.tab: sunset_password
                    KeyNavigation.backtab: sunset_layout

                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sunset_root.tryLogin()
                            event.accepted = true
                        }
                    }
                }
            }

            // password label
            Row {
                x: padSym
                y: avatarRow.y + avatarRow.height + 26 + (spUnit - padSym * 2) + 8
                width: parent.width - padSym * 2
                height: 18

                Text {
                    width: parent.width
                    height: parent.height
                    text: textConstants.password
                    color: sunsetMuted
                    font.family: sunsetFont
                    font.pixelSize: spFontSmall - 2
                    horizontalAlignment: Text.AlignLeft
                    verticalAlignment: Text.AlignBottom
                }
            }

            // password field
            Row {
                x: padSym
                y: avatarRow.y + avatarRow.height + 26 + (spUnit - padSym * 2) + 26
                width: parent.width - padSym * 2
                height: spUnit - padSym * 2

                PasswordBox {
                    id: sunset_password
                    width: parent.width
                    height: parent.height
                    color: sunsetRow
                    borderColor: sunsetBorderStrong
                    focusColor: sunsetAccent
                    hoverColor: sunsetAccentHover
                    textColor: sunsetText
                    radius: 0
                    font.family: sunsetFont
                    font.pixelSize: spFontSmall
                    tooltipBG: sunsetPanel
                    tooltipFG: sunsetText

                    KeyNavigation.tab: sunset_login
                    KeyNavigation.backtab: sunset_username

                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sunset_root.tryLogin()
                            event.accepted = true
                        }
                    }
                }
            }

            // session + layout selectors (compact row)
            Row {
                x: padSym
                y: avatarRow.y + avatarRow.height + 26 + (spUnit - padSym * 2) * 2 + 34
                width: parent.width - padSym * 2
                height: 32
                spacing: 8

                ComboBox {
                    id: sunset_session
                    width: (parent.width - 8) * 0.62
                    height: parent.height
                    color: sunsetRow
                    borderColor: sunsetBorder
                    focusColor: sunsetAccent
                    hoverColor: sunsetBorderStrong
                    textColor: sunsetText
                    menuColor: sunsetPanel
                    font.family: sunsetFont
                    font.pixelSize: 12
                    arrowIcon: "images/arrow-down.svg"
                    arrowColor: sunsetBorderStrong
                    model: sessionModel
                    index: sessionModel.lastIndex
                    borderWidth: 1
                    KeyNavigation.tab: sunset_layout
                    KeyNavigation.backtab: sunset_password
                }

                LayoutBox {
                    id: sunset_layout
                    width: (parent.width - 8) * 0.38
                    height: parent.height
                    color: sunsetRow
                    borderColor: sunsetBorder
                    focusColor: sunsetAccent
                    hoverColor: sunsetBorderStrong
                    textColor: sunsetText
                    menuColor: sunsetPanel
                    font.family: sunsetFont
                    font.pixelSize: 12
                    arrowIcon: "images/arrow-down.svg"
                    arrowColor: sunsetBorderStrong
                    KeyNavigation.tab: sunset_username
                    KeyNavigation.backtab: sunset_session
                }
            }

            // login button — accent #E85D2F, black text
            Row {
                x: padSym
                y: parent.height - (spUnit - padSym * 2) - padSym
                width: parent.width - padSym * 2
                height: spUnit - padSym * 2

                Button {
                    id: sunset_login
                    width: parent.width
                    height: parent.height
                    text: textConstants.login
                    color: sunsetAccent
                    textColor: sunsetBg
                    borderColor: sunsetBorderStrong
                    activeColor: sunsetAccentHover
                    pressedColor: sunsetAccentHover
                    font.family: sunsetFont
                    font.pixelSize: spFontNormal
                    font.weight: Font.DemiBold
                    KeyNavigation.tab: sunset_reboot
                    KeyNavigation.backtab: sunset_password
                    onClicked: sunset_root.tryLogin()
                    Keys.onPressed: {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            sunset_root.tryLogin()
                            event.accepted = true
                        }
                    }
                }
            }
        }

        // power row — reboot / shutdown, muted style
        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 12

            Button {
                id: sunset_reboot
                width: 130
                height: 36
                text: textConstants.reboot
                color: sunsetPanel
                textColor: sunsetMuted
                borderColor: sunsetBorder
                activeColor: sunsetRow
                pressedColor: sunsetAccent
                font.family: sunsetFont
                font.pixelSize: 13
                KeyNavigation.tab: sunset_shutdown
                KeyNavigation.backtab: sunset_login
                onClicked: sddm.reboot()
            }

            Button {
                id: sunset_shutdown
                width: 130
                height: 36
                text: textConstants.shutdown
                color: sunsetPanel
                textColor: sunsetMuted
                borderColor: sunsetBorder
                activeColor: sunsetRow
                pressedColor: sunsetDanger
                font.family: sunsetFont
                font.pixelSize: 13
                KeyNavigation.tab: sunset_username
                KeyNavigation.backtab: sunset_reboot
                onClicked: sddm.powerOff()
            }
        }
    }

    // busy indicator (just below card)
    Rectangle {
        id: sunset_busy
        x: (parent.width - 6 * spUnit) / 2
        y: parent.height / 2 + 3 * spUnit + 48
        width: 6 * spUnit
        height: spUnit / 6
        visible: false
        color: "transparent"
        border.color: sunsetAccentHover
        border.width: 1
        radius: 0

        Rectangle {
            id: sunset_busy_indicator
            x: 0
            y: 0
            width: spUnit / 4
            height: parent.height
            color: sunsetAccent
            radius: 0
        }

        SequentialAnimation {
            id: sunset_busy_anim
            running: false
            loops: Animation.Infinite
            NumberAnimation {
                target: sunset_busy_indicator
                property: "x"
                from: 0
                to: 6 * spUnit - spUnit / 4
                duration: 1200
            }
            NumberAnimation {
                target: sunset_busy_indicator
                property: "x"
                to: 0
                duration: 1200
            }
        }
    }

    // prompt — failure in danger #c30505, success in muted
    Rectangle {
        id: prompt_bg
        x: parent.width / 4
        y: parent.height - 3 * spUnit
        width: parent.width / 2
        height: spUnit * 0.8
        color: "transparent"
        radius: 0

        Text {
            id: prompt_txt
            anchors.fill: parent
            anchors.margins: padSym
            color: sunsetText
            text: textConstants.prompt
            font.family: sunsetFont
            font.pixelSize: spFontSmall
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
        }

        SequentialAnimation on color {
            id: anim_success
            running: false
            ColorAnimation {
                from: "transparent"
                to: successText
                duration: 200
            }
        }

        SequentialAnimation on color {
            id: anim_failure
            running: false
            ColorAnimation {
                from: "transparent"
                to: failureText
                duration: 200
            }
            PauseAnimation {
                duration: 600
            }
            ColorAnimation {
                from: failureText
                to: "transparent"
                duration: 400
            }
            onStopped: {
                sunset_password.text = ""
                prompt_txt.text = textConstants.prompt
            }
        }
    }

    Component.onCompleted: {
        if (sunset_username.text === "") {
            sunset_username.focus = true
        } else {
            sunset_password.focus = true
        }
    }
}
