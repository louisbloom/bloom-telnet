/* textinput.c - Multi-line text input component implementation */

#include <bloom-boba/components/textinput.h>
#include <bloom-boba/ansi_sequences.h>
#include <bloom-boba/cmd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TEXTINPUT_INITIAL_CAP 256
#define TEXTINPUT_TYPE_ID (TUI_COMPONENT_TYPE_BASE + 1)

/* UTF-8 helper: Get byte length of UTF-8 character starting at ptr */
static int utf8_char_len(const char *ptr) {
  unsigned char c = (unsigned char)*ptr;
  if ((c & 0x80) == 0)
    return 1;
  if ((c & 0xE0) == 0xC0)
    return 2;
  if ((c & 0xF0) == 0xE0)
    return 3;
  if ((c & 0xF8) == 0xF0)
    return 4;
  return 1; /* Invalid, treat as single byte */
}

/* UTF-8 helper: Get previous character start position */
static size_t utf8_prev_char(const char *text, size_t pos) {
  if (pos == 0)
    return 0;
  pos--;
  while (pos > 0 && ((unsigned char)text[pos] & 0xC0) == 0x80) {
    pos--;
  }
  return pos;
}

/* Count lines and find cursor position */
static void recalculate_cursor_position(TuiTextInput *input) {
  input->cursor_row = 0;
  input->cursor_col = 0;

  size_t col = 0;
  for (size_t i = 0; i < input->cursor_byte && i < input->text_len; i++) {
    if (input->text[i] == '\n') {
      input->cursor_row++;
      col = 0;
    } else {
      col++;
    }
  }
  input->cursor_col = col;
}

/* Ensure text buffer has enough capacity */
static int ensure_capacity(TuiTextInput *input, size_t needed) {
  if (input->text_cap >= needed)
    return 0;

  size_t new_cap = input->text_cap;
  if (new_cap == 0)
    new_cap = TEXTINPUT_INITIAL_CAP;
  while (new_cap < needed)
    new_cap *= 2;

  char *new_text = (char *)realloc(input->text, new_cap);
  if (!new_text)
    return -1;

  input->text = new_text;
  input->text_cap = new_cap;
  return 0;
}

/* Insert text at cursor position */
static int insert_text(TuiTextInput *input, const char *text, size_t len) {
  if (len == 0)
    return 0;

  if (ensure_capacity(input, input->text_len + len + 1) < 0)
    return -1;

  /* Move text after cursor */
  if (input->cursor_byte < input->text_len) {
    memmove(input->text + input->cursor_byte + len,
            input->text + input->cursor_byte,
            input->text_len - input->cursor_byte);
  }

  /* Insert new text */
  memcpy(input->text + input->cursor_byte, text, len);
  input->text_len += len;
  input->cursor_byte += len;
  input->text[input->text_len] = '\0';

  recalculate_cursor_position(input);
  return 0;
}

/* Insert a single UTF-8 codepoint */
static int insert_codepoint(TuiTextInput *input, uint32_t cp) {
  char buf[5];
  int len;

  if (cp < 0x80) {
    buf[0] = (char)cp;
    len = 1;
  } else if (cp < 0x800) {
    buf[0] = (char)(0xC0 | (cp >> 6));
    buf[1] = (char)(0x80 | (cp & 0x3F));
    len = 2;
  } else if (cp < 0x10000) {
    buf[0] = (char)(0xE0 | (cp >> 12));
    buf[1] = (char)(0x80 | ((cp >> 6) & 0x3F));
    buf[2] = (char)(0x80 | (cp & 0x3F));
    len = 3;
  } else {
    buf[0] = (char)(0xF0 | (cp >> 18));
    buf[1] = (char)(0x80 | ((cp >> 12) & 0x3F));
    buf[2] = (char)(0x80 | ((cp >> 6) & 0x3F));
    buf[3] = (char)(0x80 | (cp & 0x3F));
    len = 4;
  }
  buf[len] = '\0';

  return insert_text(input, buf, len);
}

/* Delete character before cursor (backspace) */
static void delete_before(TuiTextInput *input) {
  if (input->cursor_byte == 0)
    return;

  size_t prev = utf8_prev_char(input->text, input->cursor_byte);
  size_t del_len = input->cursor_byte - prev;

  memmove(input->text + prev, input->text + input->cursor_byte,
          input->text_len - input->cursor_byte);
  input->text_len -= del_len;
  input->cursor_byte = prev;
  input->text[input->text_len] = '\0';

  recalculate_cursor_position(input);
}

/* Delete character at cursor (delete key) */
static void delete_at(TuiTextInput *input) {
  if (input->cursor_byte >= input->text_len)
    return;

  int char_len = utf8_char_len(input->text + input->cursor_byte);
  size_t del_end = input->cursor_byte + char_len;
  if (del_end > input->text_len)
    del_end = input->text_len;

  memmove(input->text + input->cursor_byte, input->text + del_end,
          input->text_len - del_end);
  input->text_len -= (del_end - input->cursor_byte);
  input->text[input->text_len] = '\0';
}

/* Move cursor left by one character */
static void cursor_left(TuiTextInput *input) {
  if (input->cursor_byte > 0) {
    input->cursor_byte = utf8_prev_char(input->text, input->cursor_byte);
    recalculate_cursor_position(input);
  }
}

/* Move cursor right by one character */
static void cursor_right(TuiTextInput *input) {
  if (input->cursor_byte < input->text_len) {
    input->cursor_byte += utf8_char_len(input->text + input->cursor_byte);
    if (input->cursor_byte > input->text_len)
      input->cursor_byte = input->text_len;
    recalculate_cursor_position(input);
  }
}

/* Move cursor to start of current line */
static void cursor_home(TuiTextInput *input) {
  while (input->cursor_byte > 0 && input->text[input->cursor_byte - 1] != '\n') {
    input->cursor_byte--;
  }
  recalculate_cursor_position(input);
}

/* Move cursor to end of current line */
static void cursor_end(TuiTextInput *input) {
  while (input->cursor_byte < input->text_len &&
         input->text[input->cursor_byte] != '\n') {
    input->cursor_byte++;
  }
  recalculate_cursor_position(input);
}

/* Find line start position for given line number */
static size_t find_line_start(const char *text, size_t len, int line) {
  if (line <= 0)
    return 0;

  int current_line = 0;
  for (size_t i = 0; i < len; i++) {
    if (text[i] == '\n') {
      current_line++;
      if (current_line == line)
        return i + 1;
    }
  }
  return len;
}

/* Find line length (without newline) */
static size_t line_length(const char *text, size_t len, size_t start) {
  size_t end = start;
  while (end < len && text[end] != '\n') {
    end++;
  }
  return end - start;
}

/* Move cursor up one line */
static void cursor_up(TuiTextInput *input) {
  if (input->cursor_row == 0)
    return;

  /* Find previous line start */
  size_t prev_line_start = find_line_start(input->text, input->text_len,
                                           (int)input->cursor_row - 1);
  size_t prev_line_len = line_length(input->text, input->text_len, prev_line_start);

  /* Move to same column or end of line if shorter */
  size_t col = input->cursor_col;
  if (col > prev_line_len)
    col = prev_line_len;

  input->cursor_byte = prev_line_start + col;
  recalculate_cursor_position(input);
}

/* Move cursor down one line */
static void cursor_down(TuiTextInput *input) {
  /* Find next line */
  size_t next_line_start = input->cursor_byte;
  while (next_line_start < input->text_len &&
         input->text[next_line_start] != '\n') {
    next_line_start++;
  }
  if (next_line_start >= input->text_len)
    return; /* No next line */
  next_line_start++; /* Skip newline */

  size_t next_line_len = line_length(input->text, input->text_len, next_line_start);

  /* Move to same column or end of line if shorter */
  size_t col = input->cursor_col;
  if (col > next_line_len)
    col = next_line_len;

  input->cursor_byte = next_line_start + col;
  recalculate_cursor_position(input);
}

/* Free completion list */
static void free_completions(TuiTextInput *input) {
  if (input->completions) {
    for (int i = 0; i < input->completion_count; i++) {
      free(input->completions[i]);
    }
    free(input->completions);
    input->completions = NULL;
    input->completion_count = 0;
    input->completion_index = 0;
  }
}

/* Navigate to previous history entry (Up arrow) */
static void history_prev(TuiTextInput *input) {
  if (!input->history || input->history_count == 0)
    return;

  /* Save current input if we're at position -1 */
  if (input->history_pos == -1) {
    if (input->saved_input)
      free(input->saved_input);
    input->saved_input = strdup(input->text);
  }

  /* Move to previous history entry */
  if (input->history_pos < input->history_count - 1) {
    input->history_pos++;
    tui_textinput_set_text(input, input->history[input->history_pos]);
  }
}

/* Navigate to next history entry (Down arrow) */
static void history_next(TuiTextInput *input) {
  if (input->history_pos < 0)
    return;

  input->history_pos--;

  if (input->history_pos == -1) {
    /* Restore saved input */
    if (input->saved_input) {
      tui_textinput_set_text(input, input->saved_input);
      free(input->saved_input);
      input->saved_input = NULL;
    } else {
      tui_textinput_clear(input);
    }
  } else {
    tui_textinput_set_text(input, input->history[input->history_pos]);
  }
}

/* Handle tab completion */
static void handle_tab_completion(TuiTextInput *input) {
  if (!input->completer)
    return;

  /* If we already have completions, cycle through them */
  if (input->completions && input->completion_count > 0) {
    input->completion_index =
        (input->completion_index + 1) % input->completion_count;
    tui_textinput_set_text(input, input->completions[input->completion_index]);
    return;
  }

  /* Get new completions */
  char **completions =
      input->completer(input->text, (int)input->cursor_byte, input->completer_data);
  if (!completions || !completions[0]) {
    /* No completions */
    if (completions)
      free(completions);
    return;
  }

  /* Count completions */
  int count = 0;
  while (completions[count])
    count++;

  input->completions = completions;
  input->completion_count = count;
  input->completion_index = 0;

  /* Apply first completion */
  tui_textinput_set_text(input, input->completions[0]);
}

/* Create a new text input component */
TuiTextInput *tui_textinput_create(const TuiTextInputConfig *config) {
  TuiTextInput *input = (TuiTextInput *)malloc(sizeof(TuiTextInput));
  if (!input)
    return NULL;

  memset(input, 0, sizeof(TuiTextInput));
  input->base.type = TEXTINPUT_TYPE_ID;

  /* Allocate initial text buffer */
  input->text_cap = TEXTINPUT_INITIAL_CAP;
  input->text = (char *)malloc(input->text_cap);
  if (!input->text) {
    free(input);
    return NULL;
  }
  input->text[0] = '\0';
  input->text_len = 0;
  input->focused = 1;      /* Focused by default */
  input->multiline = 0;
  input->show_prompt = 1;  /* Show prompt by default */
  input->history_pos = -1; /* -1 means we're at current input */

  /* Apply config if provided */
  if (config) {
    input->prompt = config->prompt;
    if (input->prompt) {
      input->prompt_len = (int)strlen(input->prompt);
    }
    input->width = config->width;
    input->height = config->height;
    input->multiline = config->multiline;
  }

  return input;
}

/* Free text input component */
void tui_textinput_free(TuiTextInput *input) {
  if (!input)
    return;
  if (input->text)
    free(input->text);
  if (input->saved_input)
    free(input->saved_input);
  if (input->history) {
    for (int i = 0; i < input->history_count; i++) {
      free(input->history[i]);
    }
    free(input->history);
  }
  free_completions(input);
  free(input);
}

/* Update text input with message */
TuiUpdateResult tui_textinput_update(TuiTextInput *input, TuiMsg msg) {
  if (!input || !input->focused)
    return tui_update_result_none();

  if (msg.type == TUI_MSG_FOCUS) {
    input->focused = 1;
    return tui_update_result_none();
  }

  if (msg.type == TUI_MSG_BLUR) {
    input->focused = 0;
    return tui_update_result_none();
  }

  if (msg.type != TUI_MSG_KEY_PRESS)
    return tui_update_result_none();

  TuiKeyMsg key = msg.data.key;

  /* Handle special keys */
  switch (key.key) {
  case TUI_KEY_LEFT:
    cursor_left(input);
    break;

  case TUI_KEY_RIGHT:
    cursor_right(input);
    break;

  case TUI_KEY_UP:
    if (input->multiline) {
      cursor_up(input);
    } else {
      /* Single-line: navigate history */
      history_prev(input);
      free_completions(input);
    }
    break;

  case TUI_KEY_DOWN:
    if (input->multiline) {
      cursor_down(input);
    } else {
      /* Single-line: navigate history */
      history_next(input);
      free_completions(input);
    }
    break;

  case TUI_KEY_TAB:
    if (!input->multiline) {
      handle_tab_completion(input);
    } else {
      insert_codepoint(input, '\t');
    }
    break;

  case TUI_KEY_HOME:
    cursor_home(input);
    break;

  case TUI_KEY_END:
    cursor_end(input);
    break;

  case TUI_KEY_BACKSPACE:
    delete_before(input);
    break;

  case TUI_KEY_DELETE:
    delete_at(input);
    break;

  case TUI_KEY_ENTER:
    if (input->multiline) {
      insert_codepoint(input, '\n');
    } else {
      /* Single-line: submit the line */
      char *line = strdup(input->text);
      tui_textinput_clear(input);
      input->history_pos = -1; /* Reset history navigation */
      if (input->saved_input) {
        free(input->saved_input);
        input->saved_input = NULL;
      }
      free_completions(input);
      return tui_update_result(tui_cmd_line_submit(line));
    }
    break;

  case TUI_KEY_NONE:
    /* Regular character */
    if (key.rune >= 0x20 || key.rune == '\t') {
      /* Skip control characters with Ctrl modifier (except Tab) */
      if ((key.mods & TUI_MOD_CTRL) && key.rune != '\t') {
        /* Handle Ctrl+key shortcuts */
        if (key.rune == 'a' || key.rune == 'A') {
          /* Ctrl+A: Move to start of line */
          cursor_home(input);
        } else if (key.rune == 'e' || key.rune == 'E') {
          /* Ctrl+E: Move to end of line */
          cursor_end(input);
        } else if (key.rune == 'k' || key.rune == 'K') {
          /* Ctrl+K: Delete to end of line */
          size_t end = input->cursor_byte;
          while (end < input->text_len && input->text[end] != '\n') {
            end++;
          }
          if (end > input->cursor_byte) {
            memmove(input->text + input->cursor_byte, input->text + end,
                    input->text_len - end);
            input->text_len -= (end - input->cursor_byte);
            input->text[input->text_len] = '\0';
          }
        } else if (key.rune == 'u' || key.rune == 'U') {
          /* Ctrl+U: Delete to start of line */
          size_t start = input->cursor_byte;
          while (start > 0 && input->text[start - 1] != '\n') {
            start--;
          }
          if (start < input->cursor_byte) {
            size_t del_len = input->cursor_byte - start;
            memmove(input->text + start, input->text + input->cursor_byte,
                    input->text_len - input->cursor_byte);
            input->text_len -= del_len;
            input->cursor_byte = start;
            input->text[input->text_len] = '\0';
            recalculate_cursor_position(input);
          }
        } else if (key.rune == 'd' || key.rune == 'D') {
          /* Ctrl+D: EOF on empty line, delete char otherwise */
          if (input->text_len == 0 && !input->multiline) {
            return tui_update_result(tui_cmd_quit());
          } else {
            delete_at(input);
          }
        }
      } else {
        insert_codepoint(input, key.rune);
        free_completions(input); /* Clear completions on any character input */
      }
    }
    break;

  default:
    break;
  }

  return tui_update_result_none();
}

/* Render a horizontal divider line */
static void render_divider(DynamicBuffer *out, int width) {
  /* Use Unicode box-drawing character ─ (U+2500) */
  const char *line_char = "\xe2\x94\x80"; /* UTF-8 encoding of ─ */
  dynamic_buffer_append_str(out, "\r");
  dynamic_buffer_append_str(out, EL_TO_END);
  dynamic_buffer_append_str(out, SGR_DIM); /* Dim color for divider */
  for (int i = 0; i < width; i++) {
    dynamic_buffer_append_str(out, line_char);
  }
  dynamic_buffer_append_str(out, SGR_RESET);
  dynamic_buffer_append_str(out, "\r\n");
}

/* Render text input to output buffer
 *
 * For single-line mode, uses ANSI sequences:
 * - Carriage return to start of line
 * - Clear to end of line
 * - Print prompt (if show_prompt is set)
 * - Print text content
 * - Position cursor at correct location
 */
void tui_textinput_view(const TuiTextInput *input, DynamicBuffer *out) {
  if (!input || !out)
    return;

  int term_width = input->terminal_width > 0 ? input->terminal_width : 80;

  if (!input->multiline) {
    /* Single-line mode: use ANSI sequences for in-place update */

    /* Render top divider if enabled */
    if (input->show_dividers) {
      render_divider(out, term_width);
    }

    /* Move to start of line */
    dynamic_buffer_append_str(out, "\r");
    /* Clear to end of line */
    dynamic_buffer_append_str(out, EL_TO_END);

    /* Output prompt if set and shown */
    if (input->show_prompt && input->prompt && input->prompt_len > 0) {
      dynamic_buffer_append_str(out, input->prompt);
    }

    /* Output text content */
    if (input->text_len > 0) {
      dynamic_buffer_append(out, input->text, input->text_len);
    }

    /* Render bottom divider if enabled */
    if (input->show_dividers) {
      dynamic_buffer_append_str(out, "\r\n");
      render_divider(out, term_width);
      /* Move cursor back up to input line (up 2 lines) */
      dynamic_buffer_append_str(out, CSI "2A");
    }

    /* Position cursor */
    if (input->focused) {
      int prompt_width =
          (input->show_prompt && input->prompt) ? input->prompt_len : 0;
      int cursor_visual_col = prompt_width + (int)input->cursor_col;

      /* Move cursor to correct position */
      /* Use \r then move forward to avoid issues with line wrapping */
      dynamic_buffer_append_str(out, "\r");
      if (cursor_visual_col > 0) {
        char move_buf[16];
        snprintf(move_buf, sizeof(move_buf), CSI "%dC", cursor_visual_col);
        dynamic_buffer_append_str(out, move_buf);
      }
    }
  } else {
    /* Multi-line mode: simpler rendering (used for text areas) */
    /* Output prompt if set and shown */
    if (input->show_prompt && input->prompt && input->prompt_len > 0) {
      dynamic_buffer_append_str(out, input->prompt);
    }

    /* Output text content */
    if (input->text_len > 0) {
      for (size_t i = 0; i < input->text_len; i++) {
        if (input->text[i] == '\n') {
          dynamic_buffer_append_str(out, "\r\n");
          /* Add prompt indentation on continued lines */
          if (input->show_prompt && input->prompt && input->prompt_len > 0) {
            for (int j = 0; j < input->prompt_len; j++) {
              dynamic_buffer_append(out, " ", 1);
            }
          }
        } else {
          dynamic_buffer_append(out, &input->text[i], 1);
        }
      }
    }
  }
}

/* Get current text content */
const char *tui_textinput_text(const TuiTextInput *input) {
  return input ? input->text : NULL;
}

/* Get text length */
size_t tui_textinput_len(const TuiTextInput *input) {
  return input ? input->text_len : 0;
}

/* Set text content */
void tui_textinput_set_text(TuiTextInput *input, const char *text) {
  if (!input)
    return;

  if (!text || *text == '\0') {
    tui_textinput_clear(input);
    return;
  }

  size_t len = strlen(text);
  if (ensure_capacity(input, len + 1) < 0)
    return;

  memcpy(input->text, text, len);
  input->text[len] = '\0';
  input->text_len = len;
  input->cursor_byte = len;
  recalculate_cursor_position(input);
}

/* Clear text content */
void tui_textinput_clear(TuiTextInput *input) {
  if (!input)
    return;
  input->text_len = 0;
  input->cursor_byte = 0;
  input->cursor_row = 0;
  input->cursor_col = 0;
  if (input->text)
    input->text[0] = '\0';
}

/* Set focus state */
void tui_textinput_set_focus(TuiTextInput *input, int focused) {
  if (input)
    input->focused = focused;
}

/* Check if focused */
int tui_textinput_is_focused(const TuiTextInput *input) {
  return input ? input->focused : 0;
}

/* Get cursor position */
size_t tui_textinput_cursor(const TuiTextInput *input) {
  return input ? input->cursor_byte : 0;
}

/* Set cursor position */
void tui_textinput_set_cursor(TuiTextInput *input, size_t pos) {
  if (!input)
    return;
  if (pos > input->text_len)
    pos = input->text_len;
  input->cursor_byte = pos;
  recalculate_cursor_position(input);
}

/* Get number of lines */
int tui_textinput_line_count(const TuiTextInput *input) {
  if (!input || input->text_len == 0)
    return 1;

  int count = 1;
  for (size_t i = 0; i < input->text_len; i++) {
    if (input->text[i] == '\n')
      count++;
  }
  return count;
}

/* Set maximum history size */
void tui_textinput_set_history_size(TuiTextInput *input, int size) {
  if (!input || size < 0)
    return;

  /* Free existing history if shrinking */
  if (input->history && size < input->history_count) {
    for (int i = size; i < input->history_count; i++) {
      free(input->history[i]);
    }
    input->history_count = size;
  }

  /* Reallocate or allocate history array */
  if (size == 0) {
    free(input->history);
    input->history = NULL;
  } else {
    char **new_history = (char **)realloc(input->history, size * sizeof(char *));
    if (new_history) {
      input->history = new_history;
    }
  }
  input->history_size = size;
  input->history_pos = -1;
}

/* Add a line to history */
void tui_textinput_history_add(TuiTextInput *input, const char *line) {
  if (!input || !line || !line[0] || input->history_size == 0)
    return;

  /* Allocate history array if needed */
  if (!input->history) {
    input->history = (char **)calloc(input->history_size, sizeof(char *));
    if (!input->history)
      return;
  }

  /* Don't add duplicate of most recent entry */
  if (input->history_count > 0 && input->history[0] &&
      strcmp(input->history[0], line) == 0) {
    return;
  }

  /* Make room for new entry at position 0 */
  if (input->history_count >= input->history_size) {
    /* Free oldest entry */
    free(input->history[input->history_size - 1]);
    input->history_count = input->history_size - 1;
  }

  /* Shift existing entries down */
  for (int i = input->history_count; i > 0; i--) {
    input->history[i] = input->history[i - 1];
  }

  /* Add new entry at position 0 */
  input->history[0] = strdup(line);
  if (input->history[0]) {
    input->history_count++;
  }

  /* Reset history position */
  input->history_pos = -1;
}

/* Set completion callback */
void tui_textinput_set_completer(TuiTextInput *input, TuiCompletionCallback cb,
                                 void *data) {
  if (!input)
    return;
  input->completer = cb;
  input->completer_data = data;
  free_completions(input);
}

/* Set whether to show the prompt */
void tui_textinput_set_show_prompt(TuiTextInput *input, int show) {
  if (input)
    input->show_prompt = show;
}

/* Set the prompt string */
void tui_textinput_set_prompt(TuiTextInput *input, const char *prompt) {
  if (!input)
    return;
  input->prompt = prompt;
  input->prompt_len = prompt ? (int)strlen(prompt) : 0;
}

/* Set whether to show dividers above/below the input */
void tui_textinput_set_show_dividers(TuiTextInput *input, int show) {
  if (input)
    input->show_dividers = show;
}

/* Set terminal width for divider rendering */
void tui_textinput_set_terminal_width(TuiTextInput *input, int width) {
  if (input)
    input->terminal_width = width;
}

/* Component interface wrappers */
static TuiModel *textinput_init(void *config) {
  return (TuiModel *)tui_textinput_create((const TuiTextInputConfig *)config);
}

static TuiUpdateResult textinput_update(TuiModel *model, TuiMsg msg) {
  return tui_textinput_update((TuiTextInput *)model, msg);
}

static void textinput_view(const TuiModel *model, DynamicBuffer *out) {
  tui_textinput_view((const TuiTextInput *)model, out);
}

static void textinput_free(TuiModel *model) {
  tui_textinput_free((TuiTextInput *)model);
}

/* Static component interface instance */
static const TuiComponent textinput_component = {
    .init = textinput_init,
    .update = textinput_update,
    .view = textinput_view,
    .free = textinput_free,
};

/* Get component interface for text input */
const TuiComponent *tui_textinput_component(void) {
  return &textinput_component;
}
