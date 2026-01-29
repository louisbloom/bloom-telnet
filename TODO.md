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
