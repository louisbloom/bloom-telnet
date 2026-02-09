# bloom-telnet

A terminal-based telnet client with Lisp scripting support, designed for MUD gaming.

## Features

- RFC 854 compliant telnet client with NAWS and I/O logging
- TUI interface with readline-style input, history, and tab completion
- Lisp scripting via bloom-lisp integration
- TinTin++ compatible MUD scripting (`#alias`, `#action`, `#highlight`, `#var`, `#if`/`#else`)
- Multi-session support with per-session Lisp environments
- ANSI color support with truecolor detection
- Statusbar with mode display and notifications
- Speedwalk shorthand (e.g., `3n2e` expands to `n;n;n;e;e`)

## Dependencies

- bloom-lisp
- Boehm GC (via bloom-lisp)
- PCRE2 (via bloom-lisp)

## Building

```bash
./autogen.sh
./configure
make
```

## Usage

```bash
# Connect to a MUD server
./src/bloom-telnet mud.example.com 4000

# Load TinTin++ macros on connect
./src/bloom-telnet --load tintin.lisp mud.example.com 4000

# Help
./src/bloom-telnet --help
```

## Commands

Once connected, use these commands (prefixed with `:`):

- `:connect <host> <port>` - Connect to a server
- `:disconnect` - Disconnect from current server
- `:load <file>` - Load a Lisp script
- `:eval <code>` - Evaluate Lisp code and show result
- `:quit` or `:q` - Exit the client
- `:help` - Show command help

## TinTin++ Scripting

When loaded with `--load tintin.lisp`, you get TinTin++ style commands at the prompt:

```
#alias {k} {kill %0}           Create an alias ("k goblin" sends "kill goblin")
#action {%0 arrives.} {look}   Trigger on server text
#highlight {bold red} {dragon}  Color-highlight matching text
#var {target} {goblin}          Set a variable ($target expands in commands)
#save {mysession}               Save session state to a Lisp file
#load {mysession}               Restore a saved session
#read {config.tin}              Import a TinTin++ config file
#if {$hp < 100} {flee}          Conditional execution
```

## Sessions

bloom-telnet supports multiple sessions, each with its own Lisp environment and telnet connection. A default session is created on startup. Manage sessions via `:eval` or from Lisp scripts:

```lisp
;; Create a new session
(session-create "alt-char")   ; => session id

;; List all sessions as (id . "name") pairs
(session-list)                ; => ((1 . "default") (2 . "alt-char"))

;; Check which session is active
(session-current)             ; => 1

;; Switch to another session
(session-switch 2)

;; Get a session's name (no args = current session)
(session-name)                ; => "alt-char"
(session-name 1)              ; => "default"

;; Destroy a session (cannot destroy the current session)
(session-switch 1)
(session-destroy 2)
```

Each session has an isolated Lisp environment — variables, aliases, actions, and hooks defined in one session do not affect others. The base environment (builtins and `init.lisp` definitions) is shared across all sessions.

### Saving and Restoring Sessions

There are two ways to save session state, depending on what you want to preserve:

**TinTin++ state** (`#save` / `#load`) — saves aliases, actions, highlights, variables, and settings. This is the right choice for most MUD players:

```
#save {~/my-mud}              Save TinTin++ state to ~/my-mud
#load {~/my-mud}              Restore it later
```

The saved file contains `hash-set!` calls that repopulate the alias, action, highlight, and variable tables. Settings like speedwalk mode are also included. Loading merges into the current session — existing entries with the same keys are overwritten, but other entries are kept.

**Full Lisp environment** (`save-session`) — saves every user-defined binding in the current session's Lisp environment (variables, functions, macros, hooks) as a loadable Lisp file:

```lisp
(save-session "~/my-session.lisp")   ; Save current session bindings
(load "~/my-session.lisp")           ; Restore into any session
```

The saved file contains `define` and `defmacro` forms for each binding. Non-serializable values like file handles are skipped. This captures more than `#save` — all Lisp-level state including hooks (which are stored in the per-session `*hooks*` hash table), not just TinTin++ tables. Telnet connection state is not included.

## Lisp Scripting

Under the hood, everything is Lisp. TinTin++ commands are sugar over Lisp data structures — aliases, actions, highlights, and variables all live in hash tables in the Lisp environment. You can script directly in Lisp for more power:

```lisp
;; React to server text with pattern matching
(action "^(\\w+) attacks you"
  (lambda (mob)
    (if (string=? mob "dragon")
      "flee"
      (string-append "kill " mob))))

;; Custom tab completion
(add-hook 'completion-hook
  (lambda (prefix)
    (filter (lambda (w) (string-prefix? prefix w))
            '("north" "south" "east" "west"))))
```

See the `lisp/` directory for examples:

- `init.lisp` - Startup config (completion, timers, hooks, colors, logging, TCP keepalive)
- `tintin.lisp` - TinTin++ command layer
- `contrib/` - Additional utility scripts (practice mode, trackers)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Author

Thomas Christensen <thomasc1971@hotmail.com>
