pragma Singleton
import QtQuick
import Quickshell

// Theme.qml — Sunset Orange AMOLED tokens (taste.md, verbatim).
// Single source of truth for colors / font / radius.
// All other QML must use Theme.* — no per-file hex literals.
Singleton {
    id: root

    // --bg: page / bar background
    readonly property color bg: "#000000"
    // --panel: cards, bar section containers
    readonly property color panel: "#0a0a0a"
    // --row: buttons, list rows
    readonly property color row: "#141010"
    // --border: faint borders, slider tracks
    readonly property color border: "#1a1210"
    // --border-strong: card borders, button borders
    readonly property color borderStrong: "#3D2B24"
    // --accent: primary actions, today/selected, active states
    readonly property color accent: "#E85D2F"
    // --accent-hover: hover text, highlights
    readonly property color accentHover: "#FF8B4A"
    // --text: body text
    readonly property color text: "#F7C7A1"
    // --muted: secondary text, hints, device names
    readonly property color muted: "#7C8A6A"
    // --dim: overflow days, disabled, placeholder
    readonly property color dim: "#555555"
    // --danger: wrong-password, destructive confirm
    readonly property color danger: "#c30505"

    // Typography: JetBrainsMono Nerd Font everywhere (bar, popups, menus).
    readonly property string fontFamily: "JetBrainsMono Nerd Font"

    // Shape: sharp rectangles on bar and popup cards.
    readonly property int radius: 0

    // Glow (taste.md): resting + hover/active. Kept here so builders
    // reuse these instead of inventing new shadows.
    readonly property string shadowResting: "0 0 15px rgba(232, 93, 47, 0.15)"
    readonly property string glowHover: "0 0 6px rgba(255,139,74,.9), 0 0 18px rgba(255,139,74,.6), 0 0 35px rgba(232,93,47,.35)"
}
