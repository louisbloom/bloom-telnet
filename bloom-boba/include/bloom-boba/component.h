/* component.h - Component interface for bloom-boba TUI library
 *
 * Components follow the Elm Architecture pattern:
 * - init: Create initial model state
 * - update: Handle messages and update state
 * - view: Render current state to output buffer
 * - free: Cleanup resources
 */

#ifndef BLOOM_BOBA_COMPONENT_H
#define BLOOM_BOBA_COMPONENT_H

#include "cmd.h"
#include "dynamic_buffer.h"
#include "msg.h"

/* Forward declaration for model base type */
typedef struct TuiModel TuiModel;

/* Base model structure - all component models should "inherit" from this */
struct TuiModel {
  int type; /* Component type identifier */
};

/* Update result - returned by update function */
typedef struct {
  TuiCmd *cmd; /* Command to execute (NULL for no command) */
} TuiUpdateResult;

/* Component interface - virtual function table */
typedef struct TuiComponent {
  /* Initialize and return new model instance */
  TuiModel *(*init)(void *config);

  /* Update model with message, return optional command */
  TuiUpdateResult (*update)(TuiModel *model, TuiMsg msg);

  /* Render model state to output buffer */
  void (*view)(const TuiModel *model, DynamicBuffer *out);

  /* Free model and associated resources */
  void (*free)(TuiModel *model);
} TuiComponent;

/* Helper macro to define component type ID */
#define TUI_COMPONENT_TYPE_BASE 100

/* Helper to create an update result with no command */
static inline TuiUpdateResult tui_update_result_none(void) {
  TuiUpdateResult result = {.cmd = NULL};
  return result;
}

/* Helper to create an update result with a command */
static inline TuiUpdateResult tui_update_result(TuiCmd *cmd) {
  TuiUpdateResult result = {.cmd = cmd};
  return result;
}

#endif /* BLOOM_BOBA_COMPONENT_H */
