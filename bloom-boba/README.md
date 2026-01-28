# bloom-boba

A C library for building terminal user interfaces using the Elm Architecture.

## Why "boba"?

The name pays homage to [Bubbletea](https://github.com/charmbracelet/bubbletea), the
Go library that brought Elm Architecture to terminal applications. Boba are the
tapioca pearls in bubble tea.

## Philosophy

bloom-boba implements the [Elm Architecture](https://guide.elm-lang.org/architecture/),
a pattern for building interactive programs that emerged from the Elm programming
language. The architecture consists of three parts:

- **Model** — the state of your application
- **View** — a way to turn your state into terminal output
- **Update** — a way to update your state based on messages

Data flows in one direction:

    Input → Message → Update(Model, Msg) → Model' → View → Output
                                ↓
                              Command → (async) → Message

This unidirectional flow makes programs predictable and easy to reason about.
The Update function is pure: given the same model and message, it always produces
the same result.

## Adapting for C

Since C lacks garbage collection and sum types, bloom-boba makes pragmatic choices:

- **Mutable models** — Update modifies the model in place rather than returning a copy
- **Tagged unions** — Messages use `enum` + `union` to simulate sum types
- **Explicit memory** — Components provide `init` and `free` functions

## Example

```c
#include <bloom-boba/tui.h>
#include <bloom-boba/components/textinput.h>

int main(void) {
    /* Initialize component */
    TuiTextInput *input = tui_textinput_create(NULL);

    /* Handle a key press */
    TuiMsg msg = tui_msg_key(0, 'H', 0);
    tui_textinput_update(input, msg);

    /* Render */
    DynamicBuffer *out = dynamic_buffer_create(256);
    tui_textinput_view(input, out);
    printf("%s", dynamic_buffer_data(out));

    /* Cleanup */
    tui_textinput_free(input);
    dynamic_buffer_destroy(out);
    return 0;
}
```
