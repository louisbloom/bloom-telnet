# bloom-telnet

A terminal-based telnet client with Lisp scripting support, designed for MUD gaming.

## Features

- RFC 854 compliant telnet client with NAWS and I/O logging
- TUI interface with readline-style input, history, and tab completion cycling
- Lisp scripting via bloom-lisp integration
- TinTin++ compatible MUD scripting (`#alias`, `#action`, `#highlight`, `#var`, `#color`)
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

# Load TinTin++ with config files (--tintin / -t)
./build/src/bloom-telnet -l tintin.lisp --tintin ~/cf.tin -t ~/skarrah.tin mud.example.com 4000

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

## TinTin++ Scripting

bloom-telnet includes a mini TinTin++ implementation so you can set up aliases, triggers, highlights, and variables without writing Lisp. Load it with `--load tintin.lisp`:

```
#alias {k} {kill %0}              Create an alias ("k goblin" sends "kill goblin")
#unalias {k}                      Remove an alias
#action {%0 arrives.} {look}      Trigger on server text
#unaction {%0 arrives.}           Remove an action
#highlight {bold red} {dragon}    Color-highlight matching text
#unhighlight {dragon}             Remove a highlight
#var {target} {goblin}            Set a variable ($target expands in commands)
#color {danger} {bold <Ffe3e78>}  Define a named color (use in #highlight specs)
#uncolor {danger}                 Remove a named color
#config {speedwalk} {on|off}      Toggle speedwalk expansion
#write {mysession.tin}            Write state to a TinTin++ config file
#read {mysession.tin}             Read a TinTin++ config file
```

For conditional logic or multi-step automation, write a slash command in Lisp (see [Extending with Lisp](#extending-with-lisp) below).

### Saving and Restoring

`#write` / `#read` saves and restores TinTin++ state — aliases, actions, highlights, variables, and custom colors:

```
#write {~/my-mud.tin}         Write state to a TinTin++ config file
#read {~/my-mud.tin}          Read it back later
```

The written file contains standard TinTin++ commands (`#alias`, `#action`, `#highlight`, `#variable`, `#color`). Reading merges into the current session — existing entries with the same keys are overwritten, but other entries are kept.

## Extending with Lisp

TinTin++ covers the common cases. For conditional logic or multi-step automation, write a slash command in Lisp:

```lisp
;; File: lisp/contrib/my-commands.lisp

;; /heal — cast heal on a target, or yourself if no target set
(defun heal-handler (args)
  (let ((target (if (> (string-length args) 0)
                  args
                  (hash-ref *tintin-variables* "target"))))
    (if target
      (send-input (concat "cast 'heal' " target))
      (send-input "cast 'heal'"))))

(register-slash-command "/heal" heal-handler "Healing"
  :desc "Cast heal on a target"
  :usage "/heal         heal current $target (or self)\n/heal <name>  heal someone specific")
```

Now wire it up from TinTin++ at the prompt:

```
#var {target} {Gandalf}
#alias {h} {/heal $target}
```

Typing `h` expands the alias to `/heal Gandalf`, which invokes the Lisp handler. Changing `$target` changes who gets healed — variables are expanded before the slash command runs.

Load your script with `--load my-commands` or `:load my-commands` at runtime.

### Hooks

Hooks let you react to server output, transform user input, and intercept keystrokes. See `init.lisp` for the full API (`add-hook`, `remove-hook`, `run-hook`, `run-transform-hook`).

| Hook                          | Type      | Purpose                                      |
| ----------------------------- | --------- | -------------------------------------------- |
| `telnet-input-hook`           | event     | React to server text (ANSI stripped)         |
| `telnet-input-transform-hook` | transform | Modify server text before display            |
| `user-input-hook`             | filter    | Intercept user input (return nil to consume) |
| `user-input-transform-hook`   | transform | Modify user input before sending             |
| `fkey-hook`                   | event     | React to F1–F12 key presses                  |

### Slash Commands

Slash commands start with `/` and are dispatched before any other input processing. Built-in: `/help`, `/doc`. Prefix matching is automatic — `/he` resolves to `/help`.

### Sessions

bloom-telnet supports multiple sessions, each with its own telnet connection and hook registry. All sessions share a single Lisp environment. Manage via `telnet-session-create`, `telnet-session-switch`, `telnet-session-list`, `telnet-session-destroy`.

## Authors

Thomas Christensen

## License

MIT License - see [LICENSE](LICENSE) for details.
