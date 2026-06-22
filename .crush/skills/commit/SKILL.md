---
name: commit
description: Use when the user asks to format and commit changes. Runs format, tests, and commits with a clear imperative-mood message.
---

# Commit

Format, test, and commit all current changes.

## Steps

1. Run `(cd build && make format)` to format all source files
2. Run `(cd build && make check)` to build and run the test suite. If tests fail, fix the issue before continuing.
3. Run `git status` (never use `-uall`), `git diff`, and `git log --oneline -5` to understand the changes and match the existing commit message style
4. Stage the relevant changed files by name (do NOT use `git add -A` or `git add .`)
5. Commit with a clear imperative-mood message. Use a HEREDOC for the message:
   ```
   git commit -m "$(cat <<'EOF'
   Message here
   EOF
   )"
   ```
6. Run `git status` to verify

## Commit message rules

- Imperative mood, sentence case (e.g., "Add user-input-hook for observing user input")
- 1-2 sentences focusing on the "why" not the "what"
- Do NOT use conventional commits (no `feat:`, `fix:`, etc.)
- Do NOT push unless explicitly asked

If the user provides guidance for the commit message, use it.
