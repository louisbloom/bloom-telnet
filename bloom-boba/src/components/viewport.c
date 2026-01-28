/* viewport.c - Software-scrolling viewport implementation
 *
 * Implements Bubbletea-style software scrolling:
 * - Lines stored in memory
 * - Visible lines calculated from y_offset
 * - Rendering uses absolute cursor positioning
 * - No ANSI scroll regions
 */

#include <bloom-boba/components/viewport.h>
#include <bloom-boba/ansi_sequences.h>
#include <stdlib.h>
#include <string.h>
#include <stdio.h>

#define VIEWPORT_TYPE_ID (TUI_COMPONENT_TYPE_BASE + 20)
#define INITIAL_LINE_CAPACITY 64
#define INITIAL_PENDING_CAPACITY 256

/* Calculate display width of a string (excluding ANSI sequences) */
static size_t calc_display_width(const char *text, size_t len) {
  size_t width = 0;
  int in_escape = 0;

  for (size_t i = 0; i < len; i++) {
    if (in_escape) {
      /* End of CSI sequence */
      if ((text[i] >= 'A' && text[i] <= 'Z') ||
          (text[i] >= 'a' && text[i] <= 'z')) {
        in_escape = 0;
      }
    } else if (text[i] == '\033' && i + 1 < len && text[i + 1] == '[') {
      in_escape = 1;
      i++; /* Skip '[' */
    } else if ((unsigned char)text[i] >= 0x20) {
      /* Printable character (simplified - doesn't handle wide chars) */
      width++;
    }
  }

  return width;
}

/* Add a line to the viewport */
static int add_line(TuiViewport *vp, const char *text, size_t len) {
  /* Grow array if needed */
  if (vp->line_count >= vp->line_capacity) {
    size_t new_cap = vp->line_capacity * 2;
    TuiViewportLine *new_lines =
        realloc(vp->lines, new_cap * sizeof(TuiViewportLine));
    if (!new_lines)
      return -1;
    vp->lines = new_lines;
    vp->line_capacity = new_cap;
  }

  /* Allocate and copy line text */
  char *line_text = malloc(len + 1);
  if (!line_text)
    return -1;
  memcpy(line_text, text, len);
  line_text[len] = '\0';

  /* Add to array */
  TuiViewportLine *line = &vp->lines[vp->line_count];
  line->text = line_text;
  line->len = len;
  line->display_width = calc_display_width(text, len);
  vp->line_count++;

  return 0;
}

/* Trim old lines if exceeding max_lines */
static void trim_old_lines(TuiViewport *vp) {
  if (vp->max_lines <= 0 || vp->line_count <= (size_t)vp->max_lines)
    return;

  size_t to_remove = vp->line_count - vp->max_lines;

  /* Free old lines */
  for (size_t i = 0; i < to_remove; i++) {
    free(vp->lines[i].text);
  }

  /* Shift remaining lines */
  memmove(vp->lines, vp->lines + to_remove,
          (vp->line_count - to_remove) * sizeof(TuiViewportLine));
  vp->line_count -= to_remove;

  /* Adjust y_offset */
  if (vp->y_offset >= to_remove) {
    vp->y_offset -= to_remove;
  } else {
    vp->y_offset = 0;
  }
}

/* Create a new viewport */
TuiViewport *tui_viewport_create(void) {
  TuiViewport *vp = calloc(1, sizeof(TuiViewport));
  if (!vp)
    return NULL;

  vp->base.type = VIEWPORT_TYPE_ID;

  /* Allocate line array */
  vp->lines = malloc(INITIAL_LINE_CAPACITY * sizeof(TuiViewportLine));
  if (!vp->lines) {
    free(vp);
    return NULL;
  }
  vp->line_capacity = INITIAL_LINE_CAPACITY;
  vp->line_count = 0;

  /* Allocate pending buffer */
  vp->pending = malloc(INITIAL_PENDING_CAPACITY);
  if (!vp->pending) {
    free(vp->lines);
    free(vp);
    return NULL;
  }
  vp->pending_cap = INITIAL_PENDING_CAPACITY;
  vp->pending_len = 0;

  /* Defaults */
  vp->width = 80;
  vp->height = 24;
  vp->y_offset = 0;
  vp->auto_scroll = 1;
  vp->max_lines = 10000; /* Reasonable default */
  vp->render_row = 1;
  vp->render_col = 1;

  return vp;
}

/* Free viewport */
void tui_viewport_free(TuiViewport *vp) {
  if (!vp)
    return;

  /* Free all lines */
  for (size_t i = 0; i < vp->line_count; i++) {
    free(vp->lines[i].text);
  }
  free(vp->lines);
  free(vp->pending);
  free(vp);
}

/* Append text to the viewport */
void tui_viewport_append(TuiViewport *vp, const char *text, size_t len) {
  if (!vp || !text || len == 0)
    return;

  int was_at_bottom = tui_viewport_at_bottom(vp);

  const char *start = text;
  const char *end = text + len;

  while (start < end) {
    /* Find next newline */
    const char *nl = memchr(start, '\n', end - start);

    if (nl) {
      /* Found newline - add pending + this segment as a complete line */
      size_t seg_len = nl - start;

      /* Handle \r\n by stripping \r */
      if (seg_len > 0 && start[seg_len - 1] == '\r') {
        seg_len--;
      }

      if (vp->pending_len > 0) {
        /* Append segment to pending, then add as line */
        size_t total = vp->pending_len + seg_len;
        if (total > vp->pending_cap) {
          size_t new_cap = total * 2;
          char *new_pending = realloc(vp->pending, new_cap);
          if (new_pending) {
            vp->pending = new_pending;
            vp->pending_cap = new_cap;
          }
        }
        memcpy(vp->pending + vp->pending_len, start, seg_len);
        add_line(vp, vp->pending, total);
        vp->pending_len = 0;
      } else {
        /* Add segment directly as line */
        add_line(vp, start, seg_len);
      }

      start = nl + 1;
    } else {
      /* No newline - add to pending buffer */
      size_t seg_len = end - start;
      size_t needed = vp->pending_len + seg_len;

      if (needed > vp->pending_cap) {
        size_t new_cap = needed * 2;
        char *new_pending = realloc(vp->pending, new_cap);
        if (new_pending) {
          vp->pending = new_pending;
          vp->pending_cap = new_cap;
        }
      }

      memcpy(vp->pending + vp->pending_len, start, seg_len);
      vp->pending_len += seg_len;
      break;
    }
  }

  /* Trim old lines if needed */
  trim_old_lines(vp);

  /* Auto-scroll to bottom if enabled and was at bottom */
  if (vp->auto_scroll && was_at_bottom) {
    tui_viewport_scroll_to_bottom(vp);
  }
}

/* Clear all content */
void tui_viewport_clear(TuiViewport *vp) {
  if (!vp)
    return;

  for (size_t i = 0; i < vp->line_count; i++) {
    free(vp->lines[i].text);
  }
  vp->line_count = 0;
  vp->pending_len = 0;
  vp->y_offset = 0;
}

/* Scroll up by N lines */
void tui_viewport_scroll_up(TuiViewport *vp, int lines) {
  if (!vp || lines <= 0)
    return;

  if ((size_t)lines > vp->y_offset) {
    vp->y_offset = 0;
  } else {
    vp->y_offset -= lines;
  }
}

/* Scroll down by N lines */
void tui_viewport_scroll_down(TuiViewport *vp, int lines) {
  if (!vp || lines <= 0)
    return;

  vp->y_offset += lines;

  /* Clamp to valid range */
  size_t max_offset = 0;
  if (vp->line_count > (size_t)vp->height) {
    max_offset = vp->line_count - vp->height;
  }
  if (vp->y_offset > max_offset) {
    vp->y_offset = max_offset;
  }
}

/* Page up */
void tui_viewport_page_up(TuiViewport *vp) {
  if (vp) {
    tui_viewport_scroll_up(vp, vp->height);
  }
}

/* Page down */
void tui_viewport_page_down(TuiViewport *vp) {
  if (vp) {
    tui_viewport_scroll_down(vp, vp->height);
  }
}

/* Scroll to bottom */
void tui_viewport_scroll_to_bottom(TuiViewport *vp) {
  if (!vp)
    return;

  if (vp->line_count > (size_t)vp->height) {
    vp->y_offset = vp->line_count - vp->height;
  } else {
    vp->y_offset = 0;
  }
}

/* Check if at bottom */
int tui_viewport_at_bottom(const TuiViewport *vp) {
  if (!vp)
    return 1;

  if (vp->line_count <= (size_t)vp->height) {
    return 1;
  }

  return vp->y_offset >= vp->line_count - vp->height;
}

/* Set viewport size */
void tui_viewport_set_size(TuiViewport *vp, int width, int height) {
  if (!vp)
    return;

  vp->width = width > 0 ? width : 1;
  vp->height = height > 0 ? height : 1;

  /* Re-clamp y_offset */
  if (vp->line_count > (size_t)vp->height) {
    size_t max_offset = vp->line_count - vp->height;
    if (vp->y_offset > max_offset) {
      vp->y_offset = max_offset;
    }
  } else {
    vp->y_offset = 0;
  }
}

/* Set render position */
void tui_viewport_set_render_position(TuiViewport *vp, int row, int col) {
  if (!vp)
    return;

  vp->render_row = row > 0 ? row : 1;
  vp->render_col = col > 0 ? col : 1;
}

/* Set max lines */
void tui_viewport_set_max_lines(TuiViewport *vp, int max) {
  if (!vp)
    return;

  vp->max_lines = max;
  trim_old_lines(vp);
}

/* Set auto scroll */
void tui_viewport_set_auto_scroll(TuiViewport *vp, int enabled) {
  if (vp) {
    vp->auto_scroll = enabled ? 1 : 0;
  }
}

/* Get line count */
size_t tui_viewport_line_count(const TuiViewport *vp) {
  return vp ? vp->line_count : 0;
}

/* Render viewport to output buffer */
void tui_viewport_view(const TuiViewport *vp, DynamicBuffer *out) {
  if (!vp || !out)
    return;

  char buf[64];

  /* Render each row of the viewport */
  for (int row = 0; row < vp->height; row++) {
    size_t line_idx = vp->y_offset + row;
    int screen_row = vp->render_row + row;

    /* Position cursor */
    snprintf(buf, sizeof(buf), CSI "%d;%dH", screen_row, vp->render_col);
    dynamic_buffer_append_str(out, buf);

    /* Clear line */
    dynamic_buffer_append_str(out, CSI "K");

    /* Render line content if it exists */
    if (line_idx < vp->line_count) {
      TuiViewportLine *line = &vp->lines[line_idx];
      /* TODO: truncate to width if needed */
      dynamic_buffer_append(out, line->text, line->len);
    }
  }

  /* If we have pending content and are at bottom, show it on last row */
  if (vp->pending_len > 0 && tui_viewport_at_bottom(vp)) {
    int last_row = vp->render_row + vp->height - 1;

    /* If we have fewer lines than height, pending goes after last line */
    if (vp->line_count < (size_t)vp->height) {
      last_row = vp->render_row + vp->line_count;
    }

    snprintf(buf, sizeof(buf), CSI "%d;%dH", last_row, vp->render_col);
    dynamic_buffer_append_str(out, buf);
    dynamic_buffer_append_str(out, CSI "K");
    dynamic_buffer_append(out, vp->pending, vp->pending_len);
  }
}

/* Component interface wrappers */
static TuiInitResult viewport_init(void *config) {
  (void)config;
  TuiModel *model = (TuiModel *)tui_viewport_create();
  return tui_init_result_none(model);
}

static TuiUpdateResult viewport_update(TuiModel *model, TuiMsg msg) {
  (void)model;
  (void)msg;
  /* Viewport doesn't handle messages directly - content is added via append */
  return tui_update_result_none();
}

static void viewport_view(const TuiModel *model, DynamicBuffer *out) {
  tui_viewport_view((const TuiViewport *)model, out);
}

static void viewport_free(TuiModel *model) {
  tui_viewport_free((TuiViewport *)model);
}

static const TuiComponent viewport_component_instance = {
    .init = viewport_init,
    .update = viewport_update,
    .view = viewport_view,
    .free = viewport_free,
};

const TuiComponent *tui_viewport_component(void) {
  return &viewport_component_instance;
}
