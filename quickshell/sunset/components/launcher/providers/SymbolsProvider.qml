// SymbolsProvider.qml — static emoji/symbol picker for the Launcher.
//
// Contract:
//   root is QtObject; function search(q: string, limit: int): var -> JS
//     array of row objects; signal resultsChanged(); property var
//     latestRows: []; function activate(row: var): void (Launcher closes
//     BEFORE calling activate, so this only acts).
// Row shape: {kind:"symbol", name: char+" "+primaryName,
//   detail:"Copy symbol — Enter to copy", icon:null, score:100,
//   section:"Symbols", data:{char}}.
//   icon is null: no symbol glyph is claimed from
//   quickshell/sunset/assets/icons/ (listing verified).
// search(): substring match on names (case-insensitive); empty q returns
//   the first `limit` entries. Typing the character itself also matches
//   (additive: char substring check alongside the contracted names check).
// activate(): copies data.char via `printf | wl-copy` with single-quote
//   escaping — same technique as CalcProvider.qml's activate (uses
//   Quickshell.execDetached rather than a Process element).
// Sync fast path only: latestRows is mirrored on every search;
// resultsChanged is never emitted (nothing completes asynchronously —
// same convention as RunnerProvider/WindowsProvider/WebProvider).
// No colors/fonts, no UI.

import QtQuick
import Quickshell

QtObject {
    id: root

    signal resultsChanged()
    property var latestRows: []

    // ~68 entries: {char, names:[primary, alias...]}. names[0] is primary.
    readonly property var entries: [
        { "char": "→", "names": ["arrow right", "rightarrow", "right arrow"] },
        { "char": "←", "names": ["arrow left", "leftarrow", "left arrow"] },
        { "char": "↑", "names": ["arrow up", "uparrow", "up arrow"] },
        { "char": "↓", "names": ["arrow down", "downarrow", "down arrow"] },
        { "char": "↔", "names": ["left right arrow", "leftrightarrow", "bidirectional arrow"] },
        { "char": "⇒", "names": ["double arrow right", "Rightarrow", "implies"] },
        { "char": "⇔", "names": ["double arrow", "iff", "if and only if", "Leftrightarrow"] },
        { "char": "↵", "names": ["enter", "return arrow", "carriage return"] },
        { "char": "↩", "names": ["return left", "undo arrow", "back arrow"] },
        { "char": "±", "names": ["plus minus", "plusminus"] },
        { "char": "×", "names": ["multiply", "times", "multiplication sign"] },
        { "char": "÷", "names": ["divide", "division sign", "obelus"] },
        { "char": "≠", "names": ["not equal", "notequal", "unequal"] },
        { "char": "≈", "names": ["approximately", "approx", "almost equal"] },
        { "char": "∞", "names": ["infinity", "infinite"] },
        { "char": "√", "names": ["square root", "sqrt", "radical"] },
        { "char": "∑", "names": ["sum", "sigma", "summation"] },
        { "char": "π", "names": ["pi"] },
        { "char": "λ", "names": ["lambda"] },
        { "char": "α", "names": ["alpha"] },
        { "char": "β", "names": ["beta"] },
        { "char": "θ", "names": ["theta"] },
        { "char": "μ", "names": ["mu", "micro"] },
        { "char": "Ω", "names": ["omega", "ohm"] },
        { "char": "°", "names": ["degree"] },
        { "char": "²", "names": ["squared", "superscript two"] },
        { "char": "³", "names": ["cubed", "superscript three"] },
        { "char": "½", "names": ["one half", "half"] },
        { "char": "≤", "names": ["less than or equal", "lessequal"] },
        { "char": "≥", "names": ["greater than or equal", "greaterequal"] },
        { "char": "∧", "names": ["logical and", "wedge", "and"] },
        { "char": "∨", "names": ["logical or", "vee", "or"] },
        { "char": "¬", "names": ["not", "negation"] },
        { "char": "∅", "names": ["empty set"] },
        { "char": "∈", "names": ["element of", "in set"] },
        { "char": "∫", "names": ["integral"] },
        { "char": "—", "names": ["em dash", "emdash"] },
        { "char": "–", "names": ["en dash", "endash"] },
        { "char": "…", "names": ["ellipsis", "dots", "horizontal ellipsis"] },
        { "char": "•", "names": ["bullet", "bullet point"] },
        { "char": "·", "names": ["middle dot", "interpunct", "middot"] },
        { "char": "«", "names": ["left guillemet", "guillemet left", "french quote left"] },
        { "char": "»", "names": ["right guillemet", "guillemet right", "french quote right"] },
        { "char": "©", "names": ["copyright"] },
        { "char": "®", "names": ["registered"] },
        { "char": "™", "names": ["trademark", "tm"] },
        { "char": "§", "names": ["section", "section sign"] },
        { "char": "¶", "names": ["paragraph", "pilcrow"] },
        { "char": "†", "names": ["dagger", "obelisk"] },
        { "char": "‡", "names": ["double dagger"] },
        { "char": "✓", "names": ["check", "checkmark", "tick"] },
        { "char": "✗", "names": ["cross", "x mark", "ballot x"] },
        { "char": "★", "names": ["black star", "star"] },
        { "char": "♥", "names": ["heart", "black heart", "love"] },
        { "char": "♦", "names": ["diamond"] },
        { "char": "€", "names": ["euro"] },
        { "char": "£", "names": ["pound", "pound sterling"] },
        { "char": "¥", "names": ["yen", "yuan"] },
        { "char": "¢", "names": ["cent"] },
        { "char": "😀", "names": ["grinning face", "grinning", "smiley", "smile"] },
        { "char": "😂", "names": ["joy", "laugh", "tears of joy", "lol"] },
        { "char": "😍", "names": ["heart eyes", "love eyes", "in love"] },
        { "char": "🤔", "names": ["thinking", "thinking face", "hmm"] },
        { "char": "👍", "names": ["thumbs up", "thumbsup", "like", "plus one"] },
        { "char": "🎉", "names": ["party", "tada", "celebration", "party popper"] },
        { "char": "🔥", "names": ["fire", "hot", "lit"] },
        { "char": "✨", "names": ["sparkles", "sparkle", "shiny"] },
        { "char": "🚀", "names": ["rocket", "ship it", "launch"] },
        { "char": "❤️", "names": ["red heart", "heart emoji", "love"] }
    ]

    function makeRow(e): var {
        return {
            "kind": "symbol",
            "name": e.char + " " + e.names[0],
            "detail": "Copy symbol — Enter to copy",
            "icon": null,
            "score": 100,
            "section": "Symbols",
            "data": { "char": e.char }
        };
    }

    function matches(e, needle: string): bool {
        if (e.char.toLowerCase().indexOf(needle) !== -1)
            return true;
        for (let i = 0; i < e.names.length; ++i) {
            if (String(e.names[i]).toLowerCase().indexOf(needle) !== -1)
                return true;
        }
        return false;
    }

    function search(q: string, limit: int): var {
        const cap = (limit > 0) ? limit : 50;
        const needle = (q ? String(q) : "").trim().toLowerCase();
        let out = [];
        for (let i = 0; i < entries.length; ++i) {
            if (needle !== "" && !matches(entries[i], needle))
                continue;
            out.push(makeRow(entries[i]));
            if (out.length >= cap)
                break;
        }
        latestRows = out;
        return out;
    }

    function activate(row: var): void {
        if (!row || !row.data || !row.data.char)
            return;
        // Shell-safe single-quote escaping (CalcProvider.qml precedent).
        const safe = String(row.data.char).replace(/'/g, "'\\''");
        Quickshell.execDetached(["sh", "-c", "printf '%s' '" + safe + "' | wl-copy"]);
    }
}
