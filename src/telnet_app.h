/* telnet_app.h - TelnetApp component: composes textview + textinput
 *
 * This component demonstrates the Elm Architecture composition pattern:
 * - Embeds child components (textview, textinput) in its model
 * - Routes messages to children in update()
 * - Composes child views with scroll regions in view()
 *
 * This is the main UI component for bloom-telnet.
 */

#ifndef TELNET_APP_H
#define TELNET_APP_H

#include <stddef.h>

#include <bloom-boba/component.h>
#include <bloom-boba/components/textinput.h>
#include <bloom-boba/components/viewport.h>

/* TelnetApp configuration */
typedef struct {
  int terminal_width;
  int terminal_height;
  const char *prompt;              /* Initial prompt string */
  int history_size;                /* Input history size */
  TuiCompletionCallback completer; /* Tab completion callback */
  void *completer_data;            /* Data for completer */
} TelnetAppConfig;

/* TelnetApp model - composes viewport and textinput */
typedef struct {
  TuiModel base; /* Component base type */

  TuiViewport *viewport; /* Child: server output display (software scrolling) */
  TuiTextInput *textinput; /* Child: user input */

  int terminal_width;
  int terminal_height;
} TelnetAppModel;

/* Custom message types for TelnetApp */
typedef enum {
  TELNET_APP_MSG_ECHO = TUI_MSG_CUSTOM_BASE + 100, /* Echo text to textview */
} TelnetAppMsgType;

/* Echo message data */
typedef struct {
  const char *text;
  size_t len;
} TelnetAppEchoData;

/* Create a new TelnetApp component */
TelnetAppModel *telnet_app_create(const TelnetAppConfig *config);

/* Free TelnetApp component */
void telnet_app_free(TelnetAppModel *app);

/* Update TelnetApp with a message */
TuiUpdateResult telnet_app_update(TelnetAppModel *app, TuiMsg msg);

/* Render TelnetApp to output buffer */
void telnet_app_view(const TelnetAppModel *app, DynamicBuffer *out);

/* App-specific API */

/* Echo text to the textview (for terminal-echo builtin)
 * Outputs text to terminal and stores in textview buffer.
 * Converts \n to \r\n for terminal output.
 */
void telnet_app_echo(TelnetAppModel *app, const char *text, size_t len);

/* Set terminal size (call on window resize) */
void telnet_app_set_terminal_size(TelnetAppModel *app, int width, int height);

/* Get the textinput component (for direct access) */
TuiTextInput *telnet_app_get_textinput(TelnetAppModel *app);

/* Get the viewport component (for direct access) */
TuiViewport *telnet_app_get_viewport(TelnetAppModel *app);

/* Set whether textinput shows prompt */
void telnet_app_set_show_prompt(TelnetAppModel *app, int show);

/* Set the prompt string */
void telnet_app_set_prompt(TelnetAppModel *app, const char *prompt);

/* Get component interface for TelnetApp */
const TuiComponent *telnet_app_component(void);

#endif /* TELNET_APP_H */
