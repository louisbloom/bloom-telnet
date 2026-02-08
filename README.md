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
