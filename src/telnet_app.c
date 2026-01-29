/* telnet_app.c - TelnetApp component implementation
 *
 * Implements software-based scrolling (Bubbletea-style):
 * - No ANSI scroll regions
 * - Viewport stores lines in memory
 * - View renders visible lines with absolute positioning
 * - Full control over cursor position
 */

#include "telnet_app.h"
#include <bloom-boba/ansi_sequences.h>
#include <bloom-boba/cmd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define TELNET_APP_TYPE_ID (TUI_COMPONENT_TYPE_BASE + 10)

/* Input area height: top divider + input line + bottom divider */
#define INPUT_AREA_HEIGHT 3

/* Create a new TelnetApp component */
TelnetAppModel *telnet_app_create(const TelnetAppConfig *config) {
  TelnetAppModel *app = (TelnetAppModel *)malloc(sizeof(TelnetAppModel));
  if (!app)
    return NULL;

  memset(app, 0, sizeof(TelnetAppModel));
  app->base.type = TELNET_APP_TYPE_ID;

  /* Set terminal dimensions from config or defaults */
  app->terminal_width =
      config && config->terminal_width > 0 ? config->terminal_width : 80;
  app->terminal_height =
      config && config->terminal_height > 0 ? config->terminal_height : 24;

  /* Create viewport child (server output with software scrolling) */
  app->viewport = tui_viewport_create();
  if (!app->viewport) {
    free(app);
    return NULL;
  }

  /* Configure viewport size and position */
  int viewport_height = app->terminal_height - INPUT_AREA_HEIGHT;
  if (viewport_height < 1)
    viewport_height = 1;
  tui_viewport_set_size(app->viewport, app->terminal_width, viewport_height);
  tui_viewport_set_render_position(app->viewport, 1, 1); /* Start at row 1 */

  /* Create textinput child (user input) */
  app->textinput = tui_textinput_create(NULL);
  if (!app->textinput) {
    tui_viewport_free(app->viewport);
    free(app);
    return NULL;
  }

  /* Configure textinput with absolute positioning */
  tui_textinput_set_terminal_width(app->textinput, app->terminal_width);
  tui_textinput_set_show_dividers(app->textinput, 1);
  /* Input row is terminal_height - 1 (middle of the 3-line input area) */
  int input_row = app->terminal_height - 1;
  tui_textinput_set_terminal_row(app->textinput, input_row);

  if (config) {
    if (config->prompt) {
      tui_textinput_set_prompt(app->textinput, config->prompt);
    }
    tui_textinput_set_show_prompt(app->textinput, config->show_prompt);
    if (config->history_size > 0) {
      tui_textinput_set_history_size(app->textinput, config->history_size);
    }
    if (config->completer) {
      tui_textinput_set_completer(app->textinput, config->completer,
                                  config->completer_data);
    }
  }

  return app;
}

/* Free TelnetApp component */
void telnet_app_free(TelnetAppModel *app) {
  if (!app)
    return;

  if (app->viewport) {
    tui_viewport_free(app->viewport);
  }
  if (app->textinput) {
    tui_textinput_free(app->textinput);
  }
  free(app);
}

/* Update TelnetApp with a message */
TuiUpdateResult telnet_app_update(TelnetAppModel *app, TuiMsg msg) {
  if (!app)
    return tui_update_result_none();

  /* Handle window size message at app level */
  if (msg.type == TUI_MSG_WINDOW_SIZE) {
    telnet_app_set_terminal_size(app, msg.data.size.width,
                                 msg.data.size.height);
    return tui_update_result_none();
  }

  /* Route key messages to textinput (it always has focus in this simple model)
   */
  if (msg.type == TUI_MSG_KEY_PRESS) {
    tui_viewport_scroll_to_bottom(app->viewport);
    return tui_textinput_update(app->textinput, msg);
  }

  return tui_update_result_none();
}

/* Render TelnetApp to output buffer
 *
 * Uses absolute cursor positioning for both viewport and textinput.
 * No scroll regions - full software control of rendering.
 */
void telnet_app_view(const TelnetAppModel *app, DynamicBuffer *out) {
  if (!app || !out)
    return;

  /* Render viewport (rows 1 to terminal_height - INPUT_AREA_HEIGHT) */
  tui_viewport_view(app->viewport, out);

  /* Render textinput (uses absolute positioning via terminal_row) */
  tui_textinput_view(app->textinput, out);
}

/* Echo text to the viewport */
void telnet_app_echo(TelnetAppModel *app, const char *text, size_t len) {
  if (!app || !text || len == 0)
    return;

  /* Append to viewport - it handles line storage and scrolling */
  tui_viewport_append(app->viewport, text, len);
}

/* Set terminal size */
void telnet_app_set_terminal_size(TelnetAppModel *app, int width, int height) {
  if (!app)
    return;

  app->terminal_width = width;
  app->terminal_height = height;

  /* Update viewport size and position */
  if (app->viewport) {
    int viewport_height = height - INPUT_AREA_HEIGHT;
    if (viewport_height < 1)
      viewport_height = 1;
    tui_viewport_set_size(app->viewport, width, viewport_height);
    tui_viewport_set_render_position(app->viewport, 1, 1);
  }

  /* Update textinput */
  if (app->textinput) {
    tui_textinput_set_terminal_width(app->textinput, width);
    /* Input row is height - 1 (middle of 3-line area) */
    int input_row = height - 1;
    tui_textinput_set_terminal_row(app->textinput, input_row);
  }
}

/* Get the textinput component */
TuiTextInput *telnet_app_get_textinput(TelnetAppModel *app) {
  return app ? app->textinput : NULL;
}

/* Get the viewport component */
TuiViewport *telnet_app_get_viewport(TelnetAppModel *app) {
  return app ? app->viewport : NULL;
}

/* Set the prompt string */
void telnet_app_set_prompt(TelnetAppModel *app, const char *prompt) {
  if (app && app->textinput) {
    tui_textinput_set_prompt(app->textinput, prompt);
  }
}

/* Scroll up by N lines */
void telnet_app_scroll_up(TelnetAppModel *app, int lines) {
  if (app && app->viewport) {
    tui_viewport_scroll_up(app->viewport, lines);
  }
}

/* Scroll down by N lines */
void telnet_app_scroll_down(TelnetAppModel *app, int lines) {
  if (app && app->viewport) {
    tui_viewport_scroll_down(app->viewport, lines);
  }
}

/* Page up */
void telnet_app_page_up(TelnetAppModel *app) {
  if (app && app->viewport) {
    tui_viewport_page_up(app->viewport);
  }
}

/* Page down */
void telnet_app_page_down(TelnetAppModel *app) {
  if (app && app->viewport) {
    tui_viewport_page_down(app->viewport);
  }
}

/* Component interface wrappers */
static TuiInitResult telnet_app_init_wrapper(void *config) {
  TuiModel *model =
      (TuiModel *)telnet_app_create((const TelnetAppConfig *)config);
  return tui_init_result_none(model);
}

static TuiUpdateResult telnet_app_update_wrapper(TuiModel *model, TuiMsg msg) {
  return telnet_app_update((TelnetAppModel *)model, msg);
}

static void telnet_app_view_wrapper(const TuiModel *model, DynamicBuffer *out) {
  telnet_app_view((const TelnetAppModel *)model, out);
}

static void telnet_app_free_wrapper(TuiModel *model) {
  telnet_app_free((TelnetAppModel *)model);
}

/* Static component interface instance */
static const TuiComponent telnet_app_component_instance = {
    .init = telnet_app_init_wrapper,
    .update = telnet_app_update_wrapper,
    .view = telnet_app_view_wrapper,
    .free = telnet_app_free_wrapper,
};

/* Get component interface for TelnetApp */
const TuiComponent *telnet_app_component(void) {
  return &telnet_app_component_instance;
}
