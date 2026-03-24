# FloatyDo Interaction Contract

These behaviors are intentional product decisions, not incidental implementation details.

Do not change them unless the user explicitly asks to change the interaction itself.
When touching these paths, update the matching interaction tests in `/Users/raffichilingaryan/Developer/floaty-do/Tests/FloatyDoTests/`.

## Task List Keyboard Contract

- `Return` on a selected todo item inserts an empty draft row immediately below that item.
- `Return` on the draft commits the draft as a task, then creates a new draft immediately below the inserted task.
- `Up Arrow` from the first todo item moves into an empty draft above the first item. It must not wrap to the bottom.
- `Down Arrow` from the last todo item moves into the default empty draft at the bottom of the list.
- `Down Arrow` / `Tab` / `Return` from the default empty draft at the bottom of the list must keep focus on that draft and provide boundary feedback rather than collapsing the draft upward.
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

## Overflow Keyboard Scrolling Contract

- In an overflowing archive list, keyboard navigation should keep about `1.0` row of context visible above and below the selected row whenever possible.
- In an overflowing task list caused by intentional manual clipping, keyboard navigation should use that same immediate `1.0`-row context rule.
- That keyboard-driven scroll reposition should be immediate/snappy, not animated.
- When the selected archive row reaches the true top or bottom of the list, scrolling should clamp cleanly to that edge.

## Resize Contract

- Manual user window resizing becomes the new floor for live task editing.
- Typing, selection changes, and row refreshes must not snap width or height back down while the user is working.
- Input, deletion, and completion flows may change height, but they must preserve the current window width.
- Structural growth actions that create more visible content may still grow the panel beyond that floor when needed to reveal the new rows.
- Navigation alone must not trigger that growth.
- Task-list height should correspond to `active task rows + 3`, capped at 10 visible rows. The temporary empty draft row does not count toward that height.
- Entering an empty draft with `Return`, `Down Arrow`, or other keyboard navigation must not grow the panel on its own. The panel grows when that draft becomes a real task.
- If an existing task is edited down to an empty draft, the panel may shrink immediately because the active task count has decreased.
- Draft creation, draft collapse, and deletion-driven structural task resizing should happen immediately.
- Completion-driven shrink should animate on the same timing and easing as the rows reflowing upward into place.
- Dragging a resize handle below the minimum width or height should rubber-band the whole panel in the drag direction while the content stays at minimum size.
- Releasing a rubber-banded resize should settle the panel into its true minimum-sized final frame with a short ease-out.
- `cmd+0` is the only keyboard shortcut that should reset the main panel width.
- `cmd+0` resets the main panel to its default size and then snaps it to the nearest screen corner.
