"use client";

import { useCallback, useMemo, useRef, useState, useEffect } from "react";
import { useTodo } from "@/providers/todo-provider";
import { TodoRow, shakeRow } from "@/components/todo-row";
import styles from "./todo-list.module.scss";

const VISIBLE_ROWS = 6;
const DRAG_THRESHOLD = 3.5;
const DRAG_SWAP_COVERAGE = 0.33;
const ROW_HEIGHT = 36;

export function TodoList() {
  const {
    state,
    updateText,
    archiveItem,
    restoreItem,
    reorderItem,
    setDraftText,
    setSelected,
    activateDraft,
    promoteDraft,
    collapseDraft,
    isDraftDefault,
    isDraftStructuralEmpty,
  } = useTodo();

  const { items, draft, selectedId } = state;
  const listRef = useRef<HTMLDivElement>(null);

  // ======== DRAG STATE — refs for smooth animation, no re-renders ========
  const [dragId, setDragId] = useState<string | null>(null);
  const dragRef = useRef<{
    id: string;
    startY: number;
    originIndex: number;
    currentOrder: string[];
    element: HTMLElement | null;
  } | null>(null);
  // Pending reorder to apply after drag ends (avoids setState-during-render)
  const pendingReorder = useRef<{ id: string; index: number } | null>(null);

  // Apply pending reorder after drag cleanup
  useEffect(() => {
    if (pendingReorder.current && dragId === null) {
      const { id, index } = pendingReorder.current;
      pendingReorder.current = null;
      reorderItem(id, index);
    }
  }, [dragId, reorderItem]);

  // ======== HELPERS ========
  const getSelectedItemIndex = useCallback(() => {
    if (!selectedId || selectedId === "draft") return -1;
    return items.findIndex((i) => i.id === selectedId);
  }, [items, selectedId]);

  // ======== KEYBOARD HANDLER ========
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      const key = e.key;

      // --- CMD+RETURN: complete selected task ---
      if (key === "Enter" && e.metaKey) {
        e.preventDefault();
        if (selectedId && selectedId !== "draft") {
          archiveItem(selectedId);
        }
        return;
      }

      // --- RETURN ---
      if (key === "Enter") {
        e.preventDefault();

        if (selectedId === "draft" || selectedId === null) {
          if (draft.text.trim()) {
            promoteDraft();
          } else if (isDraftDefault) {
            // Terminal empty draft: shake
            const draftEl = listRef.current?.querySelector(
              "[data-row-id='draft']"
            ) as HTMLElement | null;
            shakeRow(draftEl);
          }
        } else {
          const idx = getSelectedItemIndex();
          if (idx !== -1) {
            if (draft.isStructural && draft.text.trim()) {
              promoteDraft();
            }
            activateDraft(idx + 1);
          }
        }
        return;
      }

      // --- UP / SHIFT+TAB ---
      if (key === "ArrowUp" || (key === "Tab" && e.shiftKey)) {
        e.preventDefault();

        if (selectedId === "draft" || selectedId === null) {
          if (isDraftStructuralEmpty) {
            collapseDraft(-1);
          } else if (items.length > 0) {
            const targetIdx = Math.min(
              draft.insertionIndex - 1,
              items.length - 1
            );
            if (targetIdx >= 0) setSelected(items[targetIdx].id);
          }
        } else {
          const idx = getSelectedItemIndex();
          if (idx > 0) {
            setSelected(items[idx - 1].id);
          } else if (idx === 0) {
            activateDraft(0);
          }
        }
        return;
      }

      // --- DOWN / TAB ---
      if (key === "ArrowDown" || (key === "Tab" && !e.shiftKey)) {
        e.preventDefault();

        if (selectedId === "draft" || selectedId === null) {
          if (isDraftStructuralEmpty) {
            collapseDraft(1);
          } else if (isDraftDefault && !draft.text.trim()) {
            const draftEl = listRef.current?.querySelector(
              "[data-row-id='draft']"
            ) as HTMLElement | null;
            shakeRow(draftEl);
          }
        } else {
          const idx = getSelectedItemIndex();
          if (idx < items.length - 1) {
            setSelected(items[idx + 1].id);
          } else {
            setSelected("draft");
          }
        }
        return;
      }

      // --- ESCAPE ---
      if (key === "Escape") {
        e.preventDefault();
        if (
          (selectedId === "draft" || selectedId === null) &&
          isDraftStructuralEmpty
        ) {
          collapseDraft(-1);
        }
        return;
      }

      // --- BACKSPACE on empty ---
      if (key === "Backspace") {
        const target = e.target as HTMLInputElement;
        if (target.value === "") {
          if (
            (selectedId === "draft" || selectedId === null) &&
            isDraftStructuralEmpty
          ) {
            e.preventDefault();
            collapseDraft(-1);
          }
          if (selectedId && selectedId !== "draft") {
            const item = items.find((i) => i.id === selectedId);
            if (item && item.text === "") {
              e.preventDefault();
              archiveItem(item.id);
            }
          }
        }
      }
    },
    [
      selectedId,
      draft,
      isDraftDefault,
      isDraftStructuralEmpty,
      items,
      getSelectedItemIndex,
      promoteDraft,
      activateDraft,
      collapseDraft,
      setSelected,
      archiveItem,
    ]
  );

  // ======== DRAG-TO-REORDER (ref-based, no React state for position) ========
  const handleDragStart = useCallback(
    (itemId: string, e: React.PointerEvent) => {
      if (e.button !== 0) return;
      const idx = items.findIndex((i) => i.id === itemId);
      if (idx === -1) return;

      // Find the row element
      const rowEl = (e.currentTarget as HTMLElement);
      const startY = e.clientY;

      dragRef.current = {
        id: itemId,
        startY,
        originIndex: idx,
        currentOrder: items.map((i) => i.id),
        element: rowEl,
      };

      // Set the row to be "lifted" via direct style
      rowEl.style.zIndex = "20";
      rowEl.style.position = "relative";
      rowEl.style.transition = "none";

      let activated = false;

      const handleMove = (moveEvent: PointerEvent) => {
        if (!dragRef.current) return;
        const delta = moveEvent.clientY - dragRef.current.startY;

        if (!activated && Math.abs(delta) < DRAG_THRESHOLD) return;
        if (!activated) {
          activated = true;
          setDragId(itemId);
        }

        // Move the element freely — follows the pointer
        rowEl.style.transform = `translateY(${delta}px)`;

        // Check for swap
        const swapThreshold = ROW_HEIGHT * DRAG_SWAP_COVERAGE;
        const order = dragRef.current.currentOrder;
        const currentIdx = order.indexOf(itemId);

        if (delta > swapThreshold && currentIdx < order.length - 1) {
          const next = [...order];
          [next[currentIdx], next[currentIdx + 1]] = [
            next[currentIdx + 1],
            next[currentIdx],
          ];
          dragRef.current.currentOrder = next;
          dragRef.current.startY = moveEvent.clientY;
          rowEl.style.transform = "translateY(0)";
          updateSiblingPositions(next, itemId);
        } else if (delta < -swapThreshold && currentIdx > 0) {
          const next = [...order];
          [next[currentIdx], next[currentIdx - 1]] = [
            next[currentIdx - 1],
            next[currentIdx],
          ];
          dragRef.current.currentOrder = next;
          dragRef.current.startY = moveEvent.clientY;
          rowEl.style.transform = "translateY(0)";
          updateSiblingPositions(next, itemId);
        }
      };

      const handleUp = () => {
        window.removeEventListener("pointermove", handleMove);
        window.removeEventListener("pointerup", handleUp);

        if (!dragRef.current) return;
        const finalOrder = dragRef.current.currentOrder;
        const newIdx = finalOrder.indexOf(itemId);

        // Snap close to target before animating (prevents overshoot)
        // Get current delta and clamp to a small range for the settle
        const currentDelta = parseFloat(
          rowEl.style.transform.replace(/translateY\((.+)px\)/, "$1") || "0"
        );
        const snapDelta = Math.max(-8, Math.min(8, currentDelta));
        rowEl.style.transition = "none";
        rowEl.style.transform = `translateY(${snapDelta}px)`;

        // Force layout, then animate the last few pixels
        void rowEl.offsetHeight;
        rowEl.style.transition = "transform 0.12s ease-out";
        rowEl.style.transform = "translateY(0)";

        // Reset siblings
        resetSiblingPositions();

        setTimeout(() => {
          rowEl.style.zIndex = "";
          rowEl.style.position = "";
          rowEl.style.transition = "";
          rowEl.style.transform = "";

          if (newIdx !== idx) {
            pendingReorder.current = { id: itemId, index: newIdx };
          }
          dragRef.current = null;
          setDragId(null);
        }, 130);
      };

      window.addEventListener("pointermove", handleMove);
      window.addEventListener("pointerup", handleUp);
    },
    [items]
  );

  // Helper: visually shift sibling rows during drag
  const updateSiblingPositions = useCallback(
    (newOrder: string[], dragItemId: string) => {
      const originalOrder = items.map((i) => i.id);
      if (!listRef.current) return;

      originalOrder.forEach((id) => {
        if (id === dragItemId) return;
        const el = listRef.current?.querySelector(
          `[data-id="${id}"]`
        ) as HTMLElement | null;
        if (!el) return;

        const originalIdx = originalOrder.indexOf(id);
        const newIdx = newOrder.indexOf(id);
        const offset = (newIdx - originalIdx) * ROW_HEIGHT;

        el.style.transition = `transform 0.16s cubic-bezier(0.42, 0, 0.58, 1)`;
        el.style.transform = `translateY(${offset}px)`;
      });
    },
    [items]
  );

  const resetSiblingPositions = useCallback(() => {
    if (!listRef.current) return;
    const allRows = listRef.current.querySelectorAll("[data-id]");
    allRows.forEach((el) => {
      (el as HTMLElement).style.transition =
        "transform 0.12s cubic-bezier(0.42, 0, 0.58, 1)";
      (el as HTMLElement).style.transform = "translateY(0)";
      setTimeout(() => {
        (el as HTMLElement).style.transition = "";
        (el as HTMLElement).style.transform = "";
      }, 120);
    });
  }, []);

  // ======== RENDER ========
  const fillerCount = useMemo(() => {
    const used = items.length + 1;
    return Math.max(0, VISIBLE_ROWS - used);
  }, [items.length]);

  // Build interleaved rows: items + draft at insertion index + fillers
  const rows: React.ReactNode[] = [];
  const draftIdx = draft.insertionIndex;
  let draftInserted = false;

  for (let i = 0; i <= items.length; i++) {
    if (i === draftIdx && !draftInserted) {
      draftInserted = true;
      rows.push(
        <TodoRow
          key="draft"
          id="draft"
          kind="taskDraft"
          text={draft.text}
          isDone={false}
          isSelected={selectedId === "draft" || selectedId === null}
          onTextChange={setDraftText}
          onKeyDown={handleKeyDown}
          onSelect={() => setSelected("draft")}
          autoFocus={selectedId === "draft" || selectedId === null}
        />
      );
    }
    if (i < items.length) {
      const item = items[i];
      rows.push(
        <TodoRow
          key={item.id}
          id={item.id}
          kind="taskItem"
          text={item.text}
          isDone={item.isDone}
          isSelected={selectedId === item.id}
          onComplete={() => archiveItem(item.id)}
          onTextChange={(t) => updateText(item.id, t)}
          onKeyDown={handleKeyDown}
          onSelect={() => setSelected(item.id)}
          onPointerDownOnRow={(e) => handleDragStart(item.id, e)}
        />
      );
    }
  }

  // Default bottom draft if not yet inserted
  if (!draftInserted) {
    rows.push(
      <TodoRow
        key="draft"
        id="draft"
        kind="taskDraft"
        text={draft.text}
        isDone={false}
        isSelected={selectedId === "draft" || selectedId === null}
        onTextChange={setDraftText}
        onKeyDown={handleKeyDown}
        onSelect={() => setSelected("draft")}
        autoFocus={selectedId === "draft" || selectedId === null}
      />
    );
  }

  // Fillers
  for (let i = 0; i < fillerCount; i++) {
    rows.push(
      <TodoRow
        key={`filler-${i}`}
        id={`filler-${i}`}
        kind="filler"
        text=""
        isDone={false}
        isSelected={false}
      />
    );
  }

  return (
    <div className={styles.list} ref={listRef} onKeyDown={handleKeyDown}>
      {rows}
    </div>
  );
}
