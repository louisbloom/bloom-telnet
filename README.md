# bloom-telnet

A terminal-based telnet client with Lisp scripting support, designed for MUD gaming.

## Features

- RFC 854 compliant telnet client with NAWS and I/O logging
- TUI interface with readline-style input, history, and tab completion cycling
- Lisp scripting via bloom-lisp integration
- TinTin++ compatible MUD scripting (`#alias`, `#action`, `#highlight`, `#var`, `#if`/`#else`/`#elseif`)
- Multi-session support with per-session hook registries and telnet connections
- ANSI color support with truecolor detection
- Statusbar with mode display and notifications
- Speedwalk shorthand (e.g., `3n2e` expands to `n;n;n;e;e`)
- Configurable log filtering by module and level

## Dependencies

- bloom-lisp (installed to `~/.local`, auto-detected via pkg-config)
- Boehm GC (via bloom-lisp)
- PCRE2 (via bloom-lisp)

## Building

```bash
./build.sh              # Full build (debug mode by default)
./build.sh --format     # Format all source files
./build.sh --bear       # Generate compile_commands.json for clangd
./build.sh --install    # Install to ~/.local
./build.sh --no-debug   # Release build
```

Build output goes to `build/`.

## Usage

```bash
# Connect to a MUD server
./build/src/bloom-telnet mud.example.com 4000

# Load TinTin++ macros on connect
./build/src/bloom-telnet --load tintin.lisp mud.example.com 4000

# Multiple load files
./build/src/bloom-telnet -l tintin.lisp -l contrib/practice.lisp mud.example.com 4000

# Enable debug logging (module:LEVEL or *:LEVEL for all)
./build/src/bloom-telnet -L 'completion:DEBUG,*:WARN' mud.example.com 4000

# Help / version
./build/src/bloom-telnet --help
./build/src/bloom-telnet --version
```

Note: The `-l`/`--load` option expects just the filename (e.g., `tintin.lisp`), not a path. The system searches `lisp/` automatically.

## Commands

Once running, use these commands (prefixed with `:`):

- `:connect <host> <port>` - Connect to a server
- `:connect <host>:<port>` - Connect (alternate form)
- `:disconnect` - Disconnect from current server
- `:load <file>` - Load a Lisp script
- `:eval <code>` - Evaluate Lisp code and show result
- `:quit` or `:q` - Exit the client
- `:help` - Show command help

## TinTin++ Scripting

When loaded with `--load tintin.lisp`, you get TinTin++ style commands at the prompt:

```
#alias {k} {kill %0}              Create an alias ("k goblin" sends "kill goblin")
#unalias {k}                      Remove an alias
#action {%0 arrives.} {look}      Trigger on server text
#unaction {%0 arrives.}           Remove an action
#highlight {bold red} {dragon}    Color-highlight matching text
#unhighlight {dragon}             Remove a highlight
#var {target} {goblin}            Set a variable ($target expands in commands)
#save {mysession}                 Save session state to a file
#load {mysession}                 Restore a saved session
#read {config.tin}                Import a TinTin++ config file
#if {$hp < 100} {flee}            Conditional execution
#if {$hp < 100} {flee} {fight}    Conditional with else branch
#elseif {$hp < 200} {heal}       Chained conditional
#else {wait}                      Default branch
```

## Sessions

bloom-telnet supports multiple sessions, each with its own telnet connection and hook registry. A default session is created on startup. All sessions share a single Lisp environment (the base environment loaded from `init.lisp`), so variables and functions are global. Hooks registered during `init.lisp` are automatically applied to each new session.

Manage sessions via `:eval` or from Lisp scripts:

```lisp
;; Create a new session
(telnet-session-create "alt-char")   ; => session id

;; List all sessions as (id . "name") pairs
(telnet-session-list)                ; => ((1 . "default") (2 . "alt-char"))

;; Check which session is active
(telnet-session-current)             ; => 1

;; Switch to another session
(telnet-session-switch 2)

;; Get a session's name (no args = current session)
(telnet-session-name)                ; => "alt-char"
(telnet-session-name 1)              ; => "default"

;; Destroy a session (cannot destroy the current session)
(telnet-session-switch 1)
(telnet-session-destroy 2)
```

Each session has its own hook registry — hooks added via `add-hook` apply only to the current session. The Lisp environment (variables, functions, macros) is shared across all sessions.

### Saving and Restoring

`#save` / `#load` saves and restores TinTin++ state — aliases, actions, highlights, variables, and settings:

```
#save {~/my-mud}              Save TinTin++ state to ~/my-mud
#load {~/my-mud}              Restore it later
```

The saved file contains `hash-set!` calls that repopulate the alias, action, highlight, and variable tables. Settings like speedwalk mode are also included. Loading merges into the current session — existing entries with the same keys are overwritten, but other entries are kept.

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

### Hooks

The hook system (C builtins: `add-hook`, `remove-hook`, `run-hook`, `run-filter-hook`) drives the data flow between telnet, user input, and the display:

- `telnet-input-hook` — called with ANSI-stripped text from the server (e.g., for word collection)
- `telnet-input-filter-hook` — transform server output before display (filter hook: return modified text)
- `user-input-hook` — transform user input before sending to the server
- `completion-hook` — provide tab completion candidates for the current input prefix

### Lisp Files

- `init.lisp` — loaded at startup; completion, timers, hooks, color config, telnet I/O logging, TCP keepalive
- `tintin.lisp` — TinTin++ command layer (loads sub-modules in dependency order)
- `contrib/practice.lisp` — practice mode automation for Carrion Fields
- `contrib/spell-translator.lisp` — translate ROM 2.4 garbled spell utterances

## Authors

Thomas Christensen

## License

MIT License - see [LICENSE](LICENSE) for details.
