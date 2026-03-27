"use client";

import { useCallback, useMemo, useRef } from "react";
import { useTodo } from "@/providers/todo-provider";
import { TodoRow, shakeRow } from "@/components/todo-row";
import styles from "./todo-list.module.scss";

const VISIBLE_ROWS = 6;

export function TodoList() {
  const {
    state,
    updateText,
    archiveItem,
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

  // ======== HELPERS ========
  const getSelectedItemIndex = useCallback(() => {
    if (!selectedId || selectedId === "draft") return -1;
    return items.findIndex((i) => i.id === selectedId);
  }, [items, selectedId]);

  // ======== KEYBOARD ========
  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      const key = e.key;

      if (key === "Enter" && e.metaKey) {
        e.preventDefault();
        if (selectedId && selectedId !== "draft") archiveItem(selectedId);
        return;
      }
      if (key === "Enter") {
        e.preventDefault();
        if (selectedId === "draft" || selectedId === null) {
          if (draft.text.trim()) {
            promoteDraft();
          } else if (isDraftDefault) {
            const draftEl = listRef.current?.querySelector("[data-row-id='draft']") as HTMLElement | null;
            shakeRow(draftEl);
          }
        } else {
          const idx = getSelectedItemIndex();
          if (idx !== -1) {
            if (draft.isStructural && draft.text.trim()) promoteDraft();
            activateDraft(idx + 1);
          }
        }
        return;
      }
      if (key === "ArrowUp" || (key === "Tab" && e.shiftKey)) {
        e.preventDefault();
        if (selectedId === "draft" || selectedId === null) {
          if (isDraftStructuralEmpty) collapseDraft(-1);
          else if (items.length > 0) {
            const t = Math.min(draft.insertionIndex - 1, items.length - 1);
            if (t >= 0) setSelected(items[t].id);
          }
        } else {
          const idx = getSelectedItemIndex();
          if (idx > 0) setSelected(items[idx - 1].id);
          else if (idx === 0) activateDraft(0);
        }
        return;
      }
      if (key === "ArrowDown" || (key === "Tab" && !e.shiftKey)) {
        e.preventDefault();
        if (selectedId === "draft" || selectedId === null) {
          if (isDraftStructuralEmpty) collapseDraft(1);
          else if (isDraftDefault && !draft.text.trim()) {
            const draftEl = listRef.current?.querySelector("[data-row-id='draft']") as HTMLElement | null;
            shakeRow(draftEl);
          }
        } else {
          const idx = getSelectedItemIndex();
          if (idx < items.length - 1) setSelected(items[idx + 1].id);
          else setSelected("draft");
        }
        return;
      }
      if (key === "Escape") {
        e.preventDefault();
        if ((selectedId === "draft" || selectedId === null) && isDraftStructuralEmpty) collapseDraft(-1);
        return;
      }
      if (key === "Backspace") {
        const target = e.target as HTMLInputElement;
        if (target.value === "") {
          if ((selectedId === "draft" || selectedId === null) && isDraftStructuralEmpty) {
            e.preventDefault(); collapseDraft(-1);
          }
          if (selectedId && selectedId !== "draft") {
            const item = items.find((i) => i.id === selectedId);
            if (item && item.text === "") { e.preventDefault(); archiveItem(item.id); }
          }
        }
      }
    },
    [selectedId, draft, isDraftDefault, isDraftStructuralEmpty, items,
     getSelectedItemIndex, promoteDraft, activateDraft, collapseDraft, setSelected, archiveItem]
  );

  // ======== RENDER ========
  const fillerCount = useMemo(() => Math.max(0, VISIBLE_ROWS - items.length - 1), [items.length]);

  const rows: React.ReactNode[] = [];
  const draftIdx = draft.insertionIndex;
  let draftInserted = false;

  for (let i = 0; i <= items.length; i++) {
    if (i === draftIdx && !draftInserted) {
      draftInserted = true;
      rows.push(
        <TodoRow key="draft" id="draft" kind="taskDraft" text={draft.text} isDone={false}
          isSelected={selectedId === "draft" || selectedId === null}
          onTextChange={setDraftText} onKeyDown={handleKeyDown}
          onSelect={() => setSelected("draft")}
          autoFocus={selectedId === "draft" || selectedId === null} />
      );
    }
    if (i < items.length) {
      const item = items[i];
      rows.push(
        <TodoRow key={item.id} id={item.id} kind="taskItem" text={item.text}
          isDone={item.isDone} isSelected={selectedId === item.id}
          onComplete={() => archiveItem(item.id)}
          onTextChange={(t) => updateText(item.id, t)}
          onKeyDown={handleKeyDown} onSelect={() => setSelected(item.id)} />
      );
    }
  }
  if (!draftInserted) {
    rows.push(
      <TodoRow key="draft" id="draft" kind="taskDraft" text={draft.text} isDone={false}
        isSelected={selectedId === "draft" || selectedId === null}
        onTextChange={setDraftText} onKeyDown={handleKeyDown}
        onSelect={() => setSelected("draft")}
        autoFocus={selectedId === "draft" || selectedId === null} />
    );
  }
  for (let i = 0; i < fillerCount; i++) {
    rows.push(<TodoRow key={`filler-${i}`} id={`filler-${i}`} kind="filler" text="" isDone={false} isSelected={false} />);
  }

  return (
    <div className={styles.list} ref={listRef} onKeyDown={handleKeyDown}>
      {rows}
    </div>
  );
}
