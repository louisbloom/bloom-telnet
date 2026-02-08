# bloom-telnet

A terminal-based telnet client with Lisp scripting support, designed for MUD gaming.

## Features

- RFC 854 compliant telnet client
- TUI interface with readline-style input (history, tab completion)
- Lisp scripting via bloom-lisp integration
- TinTin++ compatible MUD scripting macros
- ANSI color support

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

# With custom init script
./src/bloom-telnet --load myconfig.lisp mud.example.com 4000

# Help
./src/bloom-telnet --help
```

## Commands

Once connected, use these commands (prefixed with `:`):

- `:connect <host> <port>` - Connect to a server
- `:disconnect` - Disconnect from current server
- `:load <file>` - Load a Lisp script
- `:quit` or `:q` - Exit the client
- `:help` - Show command help

## Lisp Scripting

bloom-telnet uses bloom-lisp for scripting. See the `lisp/` directory for examples:

- `init.lisp` - Main initialization (hooks, timers, completion, config, startup banner)
- `tintin.lisp` - TinTin++ compatible macros
- `contrib/` - Additional utility scripts

## License

MIT License - see COPYING for details.

## Author

Thomas Christensen <thomasc1971@hotmail.com>
