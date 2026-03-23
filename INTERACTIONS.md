# FloatyDo Interaction Contract

These behaviors are intentional product decisions, not incidental implementation details.

Do not change them unless the user explicitly asks to change the interaction itself.
When touching these paths, update the matching tests in `/Users/raffichilingaryan/Developer/floaty-do/Tests/FloatyDoTests/TodoViewControllerInteractionTests.swift`.

## Task List Keyboard Contract

- `Return` on a selected todo item inserts an empty draft row immediately below that item.
- `Return` on the draft commits the draft as a task, then creates a new draft immediately below the inserted task.
- `Up Arrow` from the first todo item moves into an empty draft above the first item. It must not wrap to the bottom.
- `Down Arrow` from the last todo item moves into the default empty draft at the bottom of the list.
- A draft created above or between tasks must keep its explicit insertion position across ordinary redraws and selection updates.
- An empty non-default draft may collapse back into the list when the user navigates away with the matching directional behavior.

## Draft Positioning Contract

- The default draft position is the bottom of the task list.
- A non-default empty draft is valid state. It is not an error to “clean up” during generic refresh.
- Structural cleanup may reset an empty draft to the default position only when the action semantically means “return to the resting list state”.

## Completion And Restore Contract

- Completing a task animates on the task row, then archives it.
- Restoring an archived task animates on the archive row, then removes it from archive.
- Archive restore stays on the archive tab. It must not switch tabs as part of the animation flow.
- Archive restore is unavailable when the active task list is already at max capacity.

## Resize Contract

- Manual user window resizing becomes the new floor for live task editing.
- Typing, selection changes, and row refreshes must not snap width or height back down while the user is working.
