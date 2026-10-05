# CHANGELOG-AGENT.md — keep the docs honest

You are updating this repo. This file is your brief for the **documentation**
half of that job: when you add or change a feature, the README and the in-app
help are part of the feature, not a follow-up. Nobody reads a changelog for a
feature that never got one.

Back every claim below with a command. Do not describe a feature you have not
verified by running it.

---

## 1. What to run, when

```bash
python3 scripts/changelog.py verify        # ALWAYS. exit 1 = you are not done.
python3 scripts/changelog.py counts --write  # after editing help/index.html rows
python3 scripts/changelog.py screenshots    # what the README still needs photos of
python3 scripts/changelog.py insert --headline "..." --file path/to/file.qml="what changed"
```

`verify` exits non-zero on the one thing that is genuinely mechanical and
genuinely broken by hand-editing: **`help/index.html` declares a row count per
section**, in the `<span class="n">59</span>` in each section's summary. Add a
row, forget the number, and the page quietly lies about how many shortcuts it
has. This was already true in this repo before the tool existed — the launcher
section claimed 59 while holding 62 rows.

`insert` puts a new entry at the top of `## 📝 Changelog`. It writes a stub
table; **you then rewrite the prose by hand**, because the tool deliberately
does not write prose.

---

## 2. The checklist for every feature

Work down it. Tick every box or say explicitly why you skipped one.

- [ ] **Does the feature have a new keybinding?** Add it to
      `niri/binds.kdl` or `niri/binds-quickshell.kdl`, **and** to the README
      `## ⌨️ Keybindings` tables, **and** to the matching `help/index.html`
      section. All three, or the docs contradict the desktop.
- [ ] **Did a keybinding move or change meaning?** Search for the old chord
      across `README.md`, `help/index.html` and `AGENTS.md` and fix every hit:
      ```bash
      grep -rn 'Ctrl+Space' README.md help/index.html AGENTS.md
      ```
      A moved chord that survives in one file is how you get a help page that
      tells people to press a key that does nothing.
- [ ] **New IPC verb?** It needs a matching shim in `shell.qml`, and the
      header comment in the popup's own file. An IPC verb is not automatically
      a root method — `dispatch()` does `loader.item[fn]`, so a function that
      exists only inside an `IpcHandler` throws and silently does nothing.
- [ ] **New popup / control row?** It changes the launcher's row numbering.
      `help/index.html` has a "rows 1–19" list in the launcher section — a row
      inserted in the middle renumbers everything after it.
- [ ] **Changelog entry** in `README.md`, dated today, headline in the house
      style: `**YYYY-MM-DD — Short headline, sentence case.**` then prose, then
      a `> ` note for anything surprising.
- [ ] **`AGENTS.md`** if you learned a non-obvious trap. That file is a list of
      things that look fine while being wrong. Add the trap, not the summary.
- [ ] **`scripts/changelog.py verify` is clean.**
- [ ] **Tests pass:** `python3 -m unittest discover -s scripts -p 'test_*.py'`

---

## 3. Screenshots — do not skip this

`README.md` has a **"📸 Screenshots still to capture"** table. A feature nobody
can picture does not get believed, and this repo's README is its shop window.

```bash
python3 scripts/changelog.py screenshots   # which files exist, which are todo
```

Rules:
- **New visual feature ⇒ new row in that table**, with the exact filename to
  save it as. Save into `.github/assets/screenshots/`, lowercase-hyphen names
  (`launcher-row-menu.png`, matching `desktop.png` / `volume-mixer.png`).
- The row must say **what to show and why it earns a picture**. "Launcher with
  the row menu open" is useless to someone capturing it six weeks from now.
- **A feature hidden by default needs a screenshot more than a visible one.**
  The performance pill is off until you press `Mod+Alt+P`, so the default
  desktop shot can never show it — that is exactly why it has its own row.
- Tick the box when the file lands. A ticked box with no file is worse than an
  empty one.

---

## 4. Tone — match the repo, do not upgrade it

The README is written for **someone installing a desktop, not someone reading
a changelog**. Read the existing entries before writing one.

- Second person. "Press it, type your query, press Enter."
- Lead with **what the user does**, then the mechanism. Never the mechanism
  first.
- Tables for anything with keys or settings. Prose for the *why*.
- Em-dash asides are the house style; so are `> ` blockquote callouts for the
  surprising bit.
- No marketing adjectives. "Fast", "seamless" and "powerful" are banned — say
  the number instead ("~208 MB → ~177 MB at rest").
- Emoji only in the existing section headings. Never mid-sentence.

---

## 5. What this tool will NOT do for you

- **It will not check that a documented chord exists.** `verify` checks the
  README *shape* and the help row counts. It cannot tell you that
  `Ctrl+Shift+F9` is documented but unbound. Reading the two against
  `niri/binds*.kdl` is still your job.
- **It will not write prose.** `insert` makes a skeleton.
- **It does not validate HTML.** The obvious structural checks were tried and
  **removed**: `help/index.html` leaves two `<details>` without an end tag and
  reports 25 phantom `<div>` imbalances on a tree byte-identical to `HEAD`.
  A checker that fails on a clean checkout gets ignored, so it was cut. If you
  break the markup, run an actual parser, not a tag counter.

---

## 6. Before you commit

```bash
python3 scripts/changelog.py verify && \
python3 -m unittest discover -s scripts -p 'test_*.py' && \
git diff --stat
```

Read the diff of `README.md` and `help/index.html` yourself. Prose that
oversells a feature is the most expensive thing you can ship here, because
someone will take you at your word and press the key.