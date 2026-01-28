#!/usr/bin/env python3
"""Test telnet server for bloom-telnet development.

A simple, extensible telnet server for testing. By default, it echoes
all received data back to the client. Can be extended with custom
command handlers for more complex testing scenarios.

Usage:
    python3 tests/test_server.py

Then connect with:
    ./build/src/bloom-telnet localhost 4449
"""

import socket
import select
import sys

PORT = 4449

# Telnet protocol constants (RFC 854)
IAC = 255  # Interpret As Command
DONT = 254
DO = 253
WONT = 252
WILL = 251
SB = 250  # Subnegotiation Begin
SE = 240  # Subnegotiation End

# Telnet options
OPT_ECHO = 1
OPT_SGA = 3  # Suppress Go Ahead
OPT_NAWS = 31  # Negotiate About Window Size


class TelnetConnection:
    """Handles a single telnet client connection."""

    def __init__(self, sock, addr, server):
        self.sock = sock
        self.addr = addr
        self.server = server
        self.buffer = b""

    def send(self, data):
        """Send data to the client."""
        if isinstance(data, str):
            data = data.encode("utf-8")
        try:
            self.sock.sendall(data)
        except (BrokenPipeError, ConnectionResetError):
            pass

    def send_iac(self, command, option):
        """Send an IAC command sequence."""
        self.send(bytes([IAC, command, option]))

    def handle_iac_sequence(self, data, i):
        """Handle an IAC sequence starting at position i.

        Returns (response_bytes, bytes_consumed).
        """
        if i + 1 >= len(data):
            return b"", 1  # Incomplete, consume just IAC

        cmd = data[i + 1]

        # Handle doubled IAC (escaped 255 byte)
        if cmd == IAC:
            return b"", 2

        # Handle WILL/WONT/DO/DONT negotiations
        if cmd in (WILL, WONT, DO, DONT):
            if i + 2 >= len(data):
                return b"", 2  # Incomplete

            opt = data[i + 2]
            response = self.handle_negotiation(cmd, opt)
            return response, 3

        # Handle subnegotiation
        if cmd == SB:
            # Find SE (end of subnegotiation)
            se_pos = data.find(bytes([IAC, SE]), i)
            if se_pos == -1:
                return b"", len(data) - i  # Consume rest, incomplete
            # For now, just acknowledge subnegotiations
            return b"", se_pos - i + 2

        # Other commands: consume the IAC and command byte
        return b"", 2

    def handle_negotiation(self, cmd, opt):
        """Handle telnet option negotiation.

        Returns response bytes to send.
        """
        # We'll accept ECHO, SGA, and NAWS; refuse others
        supported = {OPT_ECHO, OPT_SGA, OPT_NAWS}

        if cmd == DO:
            # Client asks if we will do something
            if opt in supported:
                return bytes([IAC, WILL, opt])
            else:
                return bytes([IAC, WONT, opt])
        elif cmd == DONT:
            # Client tells us not to do something
            return bytes([IAC, WONT, opt])
        elif cmd == WILL:
            # Client offers to do something
            if opt in supported:
                return bytes([IAC, DO, opt])
            else:
                return bytes([IAC, DONT, opt])
        elif cmd == WONT:
            # Client refuses to do something
            return bytes([IAC, DONT, opt])

        return b""

    def process_data(self, data):
        """Process received data, handling IAC sequences.

        Returns the filtered data (with IAC sequences removed).
        """
        result = bytearray()
        i = 0

        while i < len(data):
            if data[i] == IAC:
                response, consumed = self.handle_iac_sequence(data, i)
                if response:
                    self.send(response)
                i += consumed
            else:
                result.append(data[i])
                i += 1

        return bytes(result)

    def handle_data(self, raw_data):
        """Handle incoming data from the client."""
        # Process telnet protocol
        data = self.process_data(raw_data)

        if not data:
            return

        # Pass to server's input handler
        response = self.server.handle_input(data, self)
        if response:
            self.send(response)


class TestServer:
    """Extensible test telnet server."""

    def __init__(self, port=PORT):
        self.port = port
        self.commands = {}  # {"command": handler_function}
        self.running = False
        self.connections = {}  # socket -> TelnetConnection
        self.server_socket = None

    def add_command(self, command, handler, description=""):
        """Add a command handler.

        Args:
            command: The command string to match
            handler: A callable that takes (args, connection) and returns
                    a response string, or just returns a string.
            description: Help text describing the command
        """
        self.commands[command] = (handler, description)

    def handle_input(self, data, connection):
        """Handle input from a client.

        Override this method or use add_command() to customize behavior.
        By default, echoes all input back to the client.

        Args:
            data: The received bytes (with IAC sequences already processed)
            connection: The TelnetConnection object

        Returns:
            Response bytes to send back, or None.
        """
        # Parse command from input
        text = data.decode("utf-8", errors="replace").strip()

        # Check for registered commands
        if text:
            parts = text.split(None, 1)
            cmd = parts[0].lower()
            args = parts[1] if len(parts) > 1 else ""

            if cmd in self.commands:
                handler, _ = self.commands[cmd]
                result = handler(args, connection)
                if result is None:
                    return None
                if isinstance(result, str):
                    result = result.encode("utf-8")
                return result

        # Echo everything else
        return data

    def get_help_text(self):
        """Return formatted help text for all commands."""
        if not self.commands:
            return "No commands available.\r\n"

        lines = ["Available commands:"]
        for cmd, (_, desc) in sorted(self.commands.items()):
            if desc:
                lines.append(f"  {cmd:12} - {desc}")
            else:
                lines.append(f"  {cmd}")
        lines.append("")
        return "\n".join(lines)

    def run(self):
        """Run the server."""
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

        try:
            self.server_socket.bind(("", self.port))
            self.server_socket.listen(5)
            self.server_socket.setblocking(False)
            self.running = True

            print(f"Test server listening on port {self.port}")
            print("Press Ctrl+C to stop")

            while self.running:
                # Build list of sockets to monitor
                read_sockets = [self.server_socket] + list(self.connections.keys())

                try:
                    readable, _, _ = select.select(read_sockets, [], [], 1.0)
                except select.error:
                    break

                for sock in readable:
                    if sock is self.server_socket:
                        # New connection
                        self.accept_connection()
                    else:
                        # Data from existing connection
                        self.handle_client_data(sock)

        except KeyboardInterrupt:
            print("\nShutting down...")
        finally:
            self.shutdown()

    def accept_connection(self):
        """Accept a new client connection."""
        try:
            client_sock, addr = self.server_socket.accept()
            client_sock.setblocking(False)
            connection = TelnetConnection(client_sock, addr, self)
            self.connections[client_sock] = connection
            print(f"Connection from {addr[0]}:{addr[1]}")

            # Send initial telnet negotiations
            # Offer to echo and suppress go-ahead
            connection.send_iac(WILL, OPT_ECHO)
            connection.send_iac(WILL, OPT_SGA)

            # Send colorful welcome banner
            connection.send(self.get_welcome_banner())

        except Exception as e:
            print(f"Error accepting connection: {e}")

    def get_welcome_banner(self):
        """Return a colorful ASCII art welcome banner."""
        # ANSI color codes
        CYAN = "\033[36m"
        MAGENTA = "\033[35m"
        YELLOW = "\033[33m"
        GREEN = "\033[32m"
        BLUE = "\033[34m"
        WHITE = "\033[37m"
        BOLD = "\033[1m"
        RESET = "\033[0m"

        banner = f"""{CYAN}{BOLD}  ____  _                       {MAGENTA} _____         _
{CYAN} | __ )| | ___   ___  _ __ ___  {MAGENTA}|_   _|__  ___| |_
{CYAN} |  _ \\| |/ _ \\ / _ \\| '_ ` _ \\ {MAGENTA}  | |/ _ \\/ __| __|
{CYAN} | |_) | | (_) | (_) | | | | | |{MAGENTA}  | |  __/\\__ \\ |_
{CYAN} |____/|_|\\___/ \\___/|_| |_| |_|{MAGENTA}  |_|\\___||___/\\__|{RESET}

{GREEN}  Welcome to the Bloom Test Server!{RESET}
{YELLOW}  --------------------------------{RESET}
{WHITE}  A test server for bloom-telnet development.
  Unrecognized input is echoed back to you.{RESET}

{BLUE}  Commands:{RESET}
{self.get_help_text()}

"""
        # Convert newlines to CRLF for telnet
        return banner.replace("\n", "\r\n")

    def handle_client_data(self, sock):
        """Handle data from a client socket."""
        connection = self.connections.get(sock)
        if not connection:
            return

        try:
            data = sock.recv(4096)
            if not data:
                # Client disconnected
                self.close_connection(sock)
                return

            connection.handle_data(data)

        except ConnectionResetError:
            self.close_connection(sock)
        except BlockingIOError:
            pass
        except Exception as e:
            print(f"Error handling data: {e}")
            self.close_connection(sock)

    def close_connection(self, sock):
        """Close a client connection."""
        connection = self.connections.pop(sock, None)
        if connection:
            print(f"Disconnected: {connection.addr[0]}:{connection.addr[1]}")
        try:
            sock.close()
        except Exception:
            pass

    def shutdown(self):
        """Shut down the server."""
        self.running = False

        # Close all client connections
        for sock in list(self.connections.keys()):
            self.close_connection(sock)

        # Close server socket
        if self.server_socket:
            try:
                self.server_socket.close()
            except Exception:
                pass
            self.server_socket = None

        print("Server stopped")


def main():
    server = TestServer()

    # Add quit command
    def handle_quit(args, conn):
        conn.send(b"Goodbye!\r\n")
        server.close_connection(conn.sock)
        return None

    server.add_command(
        "help", lambda args, conn: server.get_help_text(), "Show available commands"
    )
    server.add_command("quit", handle_quit, "Disconnect from server")
    server.add_command(
        "orange",
        lambda args, conn: "\033[38;2;255;165;0mThis text is orange!\033[0m\r\n",
        "Display text in orange color",
    )

    server.run()


if __name__ == "__main__":
    main()
