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
- F-key bindings (F1–F12) configurable from Lisp
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
./build.sh --test       # Build and run test suite
```

Build output goes to `build/`.

## Usage

```bash
# Connect to a MUD server
./build/src/bloom-telnet mud.example.com 4000

# Load TinTin++ macros on connect
./build/src/bloom-telnet --load tintin.lisp mud.example.com 4000

# Multiple load files
./build/src/bloom-telnet -l tintin.lisp -l practice.lisp mud.example.com 4000

# Enable debug logging (module:LEVEL or *:LEVEL for all)
./build/src/bloom-telnet -L 'completion:DEBUG,*:WARN' mud.example.com 4000

# Help / version
./build/src/bloom-telnet --help
./build/src/bloom-telnet --version
```

Note: The `-l`/`--load` option expects just the filename (e.g., `tintin` or `tintin.lisp`), not a path. The `.lisp` extension is added automatically if omitted. The system searches `lisp/` and `lisp/contrib/` automatically.

## Commands

Once running, use these commands (prefixed with `:`):

- `:connect <host> <port>` - Connect to a server
- `:connect <host>:<port>` - Connect (alternate form)
- `:disconnect` - Disconnect from current server
- `:load <file>` - Load a Lisp script
- `:eval <code>` - Evaluate Lisp code and show result
- `:quit` or `:q` - Exit the client
- `:help` - Show command help

## Slash Commands

Slash commands are user-extensible commands typed at the prompt. They start with `/` and are dispatched before any other input processing.

Built-in commands:

- `/help` — list all registered slash commands
- `/help <cmd>` — show detailed help for a specific command
- `/doc` — alias for `/help`

Prefix matching is automatic: `/he` resolves to `/help` if unambiguous, or shows candidates if multiple commands match.

### Creating a Custom Slash Command

```lisp
;; Define a handler — receives everything after the command name
(defun greeter-handler (args)
  (if (string=? args "")
    (telnet-send "say Hello, everyone!")
    (telnet-send (concat "say Hello, " args "!"))))

;; Register it
(register-slash-command "/greet" greeter-handler "Greeter"
  :desc "Send a greeting to the room"
  :aliases '("/hi")
  :usage "/greet — greet everyone\n/greet <name> — greet someone specific")
```

What happens:

- `/greet` → sends `say Hello, everyone!`
- `/greet Bob` → sends `say Hello, Bob!`
- `/hi` → resolves the alias, same as `/greet`
- `/greet help` → shows the command's usage and description

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
;; Add an action trigger via the hash table directly
(hash-set! *tintin-actions* "%0 arrives." '("look" 5))

;; React to server text with a hook
(add-hook 'telnet-input-hook
  (lambda (text)
    (if (string-contains? text "You are hungry")
      (telnet-send "eat bread"))))

;; Add a custom word to tab completion
(add-word-to-store "cast 'magic missile'")
```

### Hooks

Hooks are the primary way to customize bloom-telnet. They let you react to server output, transform user input, intercept keystrokes, and build automation scripts — all from Lisp.

#### Three Hook Types

**Event hooks** (`run-hook`) call every registered handler with the same arguments. Return values are ignored — handlers exist for side effects (logging, triggering actions, collecting data).

**Filter hooks** (`run-filter-hook`) call every handler with the original value. If any handler returns `nil`, the input is consumed and skips further processing. Use for command interception.

**Transform hooks** (`run-transform-hook`) thread a value through handlers in priority order. Each handler receives the previous handler's output and returns a transformed value. Return `nil` to consume/discard the value.

#### Hook API

```lisp
;; Register a handler on a hook. Lower priority = runs first. Default: 50.
(add-hook 'hook-name 'my-handler-fn)
(add-hook 'hook-name 'my-handler-fn 10)   ; priority 10 (runs early)

;; Remove a handler
(remove-hook 'hook-name 'my-handler-fn)

;; Remove all handlers from a hook
(clear-hook 'hook-name)

;; Dispatch (used internally — you rarely call these directly)
(run-hook 'hook-name arg1 arg2 ...)       ; event: call all handlers
(run-filter-hook 'hook-name value)        ; filter: nil from any handler = consumed
(run-transform-hook 'hook-name value)     ; transform: thread value through handlers
```

Handlers are registered by symbol name, not by value. This means if you redefine a function (e.g., by reloading a script), the hook picks up the new definition automatically.

Duplicate detection prevents the same symbol from being registered twice on the same hook.

#### Available Hooks

##### `telnet-input-hook` (event)

Fired when data arrives from the server. Text has ANSI codes stripped.

```lisp
;; Auto-eat when hungry
(defun auto-eat (text)
  (if (string-contains? text "You are hungry")
    (telnet-send "eat bread")))

(add-hook 'telnet-input-hook 'auto-eat)
```

Built-in handler: `default-word-collector` (priority 50) scans server output for words and feeds them into tab completion.

##### `telnet-input-transform-hook` (transform)

Fired when data arrives from the server, before display. Text has ANSI codes preserved. Each handler receives the text and must return the (possibly modified) text.

```lisp
;; Hide lines containing "SPAM"
(defun gag-spam (text)
  (if (string-contains? text "SPAM") "" text))

(add-hook 'telnet-input-transform-hook 'gag-spam)
```

When tintin is loaded, `tintin-telnet-input-transform` (priority 50) applies `#highlight` color rules here.

##### `user-input-hook` (filter)

Fired when the user submits input, before the transform hook. Dispatched via `run-filter-hook` — every handler receives the original text and returns non-nil to pass through or `nil` to consume. If any handler returns `nil`, the input is consumed and never reaches the transform hook or the server.

```lisp
;; Intercept /greet to send a say command, consuming the input
(defun my-command (text)
  (if (string-prefix? "/greet" text)
    (progn (telnet-send "say Hello!") nil)  ; consume
    text))                                   ; pass through

(add-hook 'user-input-hook 'my-command 5)
```

The built-in `practice-user-input-hook` (priority 10) uses this hook to intercept `/p` commands.

##### `user-input-transform-hook` (transform)

Fired when the user submits input, after the filter hook. This is the main pipeline for input processing — alias expansion, speedwalk, command prefixing, and more.

Handlers receive a string and return one of:

- **string** — the transformed input (passed to next handler or sent to server)
- **list of strings** — multiple commands (each sent separately to the server)
- **nil** — consume the input (nothing is sent)

For command interception (dispatching a `/command` and consuming input), use `user-input-hook` instead — it runs before this hook and is designed for that pattern.

```lisp
;; Add a prefix to all outgoing commands
(defun add-prefix (text)
  (if (string=? text "") text (concat "say " text)))

(add-hook 'user-input-transform-hook 'add-prefix 60)
```

Typical priority layout on this hook:

| Priority | Handler                  | Purpose                                 |
| -------- | ------------------------ | --------------------------------------- |
| 50       | `tintin-user-input-hook` | Alias expansion, speedwalk, `#commands` |

Lower priority numbers run first. Use priorities below 50 to intercept input before TinTin++ processes it, or above 50 to transform TinTin++'s output.

##### `fkey-hook` (event)

Fired when the user presses F1–F12. The handler receives the key number as an integer.

Rather than registering on this hook directly, use the convenience functions:

```lisp
;; Bind F2 to send "look"
(bind-fkey 2 (lambda () (send-input "look")))

;; Bind F3 to toggle a mode
(bind-fkey 3 my-toggle-function)

;; Unbind
(unbind-fkey 2)
```

#### List-Aware Transform Hooks

Transform hooks handle lists natively. When a handler returns a list, subsequent handlers receive each element individually:

```
"3n" → tintin-user-input-hook (priority 50)
     → ("n" "n" "n")                         ;; speedwalk expanded to list
     → ("character1 n" "character1 n" "character1 n")  ;; each element prefixed
```

The rules:

- **String in, string out** — normal pass-through
- **String in, list out** — subsequent handlers see individual elements
- **List in** — handler is called once per element; results are collected:
  - Returns a string → kept
  - Returns nil → element is removed (filtering)
  - Returns a list → elements are spliced in (expansion)

This lets you write simple single-command handlers that automatically work on multi-command input:

```lisp
;; This handler works on individual commands, but if TinTin++ already
;; split "3n" into ("n" "n" "n"), it processes each one separately.
(defun my-prefix (text)
  (concat "character1 " text))

(add-hook 'user-input-transform-hook 'my-prefix 60)
```

#### Hook Scoping and Sessions

Each session has its own hook registry. Hooks added via `add-hook` apply only to the current session. When you create a new session, it inherits hooks that were registered during `init.lisp` (before any session existed), but not hooks added later by loaded scripts.

To add hooks to a new session, switch to it first:

```lisp
(telnet-session-switch 2)
(add-hook 'telnet-input-hook 'my-handler)  ; applies to session 2 only
```

### Lisp Files

- `init.lisp` — loaded at startup; completion, timers, hooks, color config, telnet I/O logging, TCP keepalive
- `contrib/tintin.lisp` — TinTin++ command layer (loads sub-modules in dependency order)
- `contrib/practice.lisp` — practice mode automation for Carrion Fields
- `contrib/spell-translator.lisp` — translate ROM 2.4 garbled spell utterances

## Authors

Thomas Christensen

## License

MIT License - see [LICENSE](LICENSE) for details.
