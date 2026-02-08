# TODO

## Terminal-probed Unicode width detection

The UTF-8 continuation byte fix handles the immediate breakage (box-drawing chars counted as 3 columns instead of 1), but doesn't solve the general problem: knowing how many cells an arbitrary Unicode codepoint or sequence occupies in the user's terminal. This depends on the terminal emulator, its font, and its Unicode version support.

### Problem space

- **CJK characters**: 2 cells wide. `wcwidth()` handles these but may be outdated.
- **Emoji**: Usually 2 cells, but varies by terminal and presentation selector (U+FE0F vs U+FE0E).
- **ZWJ sequences** (e.g., family emoji): Could render as 1 composed glyph (2 cells) or as N separate emoji (2xN cells). Entirely terminal-dependent.
- **Ambiguous-width characters**: Some terminals render them as 1 cell, others as 2 (CJK locale dependent).

### Approach: cursor position probing at startup

The only reliable way to know what a terminal does is to ask it:

1. **At startup** (in `terminal_caps.c` alongside existing capability detection):
   - Save cursor position
   - Move cursor to column 1 of an off-screen or cleared line
   - Write a test character/sequence
   - Query cursor position with `ESC[6n` (Device Status Report)
   - Terminal responds with `ESC[<row>;<col>R`
   - `display_width = col - 1`
   - Restore cursor / erase the test output

2. **What to probe** -- a small representative set:
   - A CJK character (e.g., U+4E16) -- expect 2
   - An emoji without ZWJ (e.g., U+1F600) -- expect 2, but some terminals show 1
   - A ZWJ family sequence -- 2 if composed, 8 if decomposed
   - An ambiguous-width char (e.g., U+00A7) -- 1 or 2 depending on locale settings

3. **Cache results** in a session-level struct (extend `TerminalCaps` or similar). Use probed results to parameterize width calculation in the viewport.

4. **Fallback**: If DSR response times out (pipe, non-interactive, screen), fall back to `wcwidth()` or a static Unicode table.

### Implementation considerations

- The DSR query is async -- write `ESC[6n`, then read the response from stdin. This naturally fits into the existing terminal detection phase before the main event loop starts.
- Probing adds ~10-50ms of startup latency (one round-trip per probe).
- Some terminals (kitty) support extended width query protocols that could be detected via existing `terminal_caps.c` DA2/XTVERSION responses.
- The viewport's `calc_display_width()` would need to consult a width lookup rather than the current byte-level check. This could be a function pointer or a lookup table populated from probe results + `wcwidth()` baseline.

## Scripting architecture

Lisp is the scripting environment. Each connection has a Lisp environment that holds all session state — aliases, actions, highlights, variables, and triggers are all stored in Lisp hash tables. This is the source of truth, and everything saved to disk is Lisp code.

TinTin++ commands (`#act`, `#alias`, `#var`, `#highlight`, etc.) are prompt-level sugar. They exist because `#alias go north` is quick to type at a MUD prompt. But Lisp equivalents don't have to be verbose — e.g. `(alias "go" "north")`. And Lisp shines when things get conditional:

```lisp
(action "* arrives from the *."
  (lambda (mob dir)
    (when (string=? mob "goblin")
      "kill goblin")))
```

Compare the TinTin++ equivalent:

```
#act {%0 arrives from the %1.} {#if {"%0" == "goblin"} {kill goblin}}
```

The `#if` with string-based conditionals is its own mini-language duplicating what Lisp does natively. So the TinTin++ layer is mainly about familiarity. The underlying data structures are Lisp — currently hash tables, though the exact representation hasn't been deeply considered and may evolve.

This split is intentional:

- **`#save`** writes Lisp. The output is a `.lisp` file of `hash-set!` calls that reconstructs the session state. There is no TinTin++ config format.
- **`#load`** evaluates Lisp. Loading a saved session just evaluates the Lisp file, which populates the hash tables.
- **`#read`** bridges TinTin++ config files into the Lisp environment. It parses TinTin++ command syntax and translates each line into the equivalent Lisp operation. This lets users bring existing TinTin++ configs without rewriting them by hand.

### Future directions

- Better Lisp integration at the prompt — make it easy to drop into Lisp expressions without needing the TinTin++ layer.
- Reduce reliance on TinTin++ string interpretation. The current TinTin++ parser does its own variable substitution, pattern matching, and flow control (`#if`/`#else`), all of which duplicate what Lisp already does natively. Over time, make Lisp the natural choice for anything beyond simple one-liners.
- TinTin++ config transpiler — an offline batch tool that reads a full TinTin++ config file and emits equivalent Lisp code, producing clean, idiomatic output. `#read` handles this at runtime already; the transpiler would be a standalone version for migration. Could later expand to support importing from zMUD, CMUD, and Mudlet config formats as well.
