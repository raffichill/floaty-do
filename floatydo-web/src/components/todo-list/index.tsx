"use client";

import { useCallback, useMemo } from "react";
import { AnimatePresence } from "motion/react";
import { useTodo } from "@/providers/todo-provider";
import { TodoRow } from "@/components/todo-row";
import styles from "./todo-list.module.scss";

const VISIBLE_ROWS = 6;

export function TodoList() {
  const {
    state,
    addItem,
    updateText,
    archiveItem,
    restoreItem,
    setDraftText,
    setSelected,
  } = useTodo();

  const { items, archivedItems, draftText, selectedId, activeTab } = state;

  const handleSubmitDraft = useCallback(
    (text: string) => {
      const trimmed = text.trim();
      if (!trimmed) return;
      addItem(trimmed);
    },
    [addItem]
  );

  const handleNavigateUp = useCallback(
    (currentIndex: number) => {
      if (activeTab === "archive") {
        if (currentIndex > 0) {
          setSelected(archivedItems[currentIndex - 1].id);
        }
        return;
      }
      if (currentIndex > 0) {
        setSelected(items[currentIndex - 1].id);
      }
    },
    [items, archivedItems, activeTab, setSelected]
  );

  const handleNavigateDown = useCallback(
    (currentIndex: number) => {
      if (activeTab === "archive") {
        if (currentIndex < archivedItems.length - 1) {
          setSelected(archivedItems[currentIndex + 1].id);
        }
        return;
      }
      if (currentIndex < items.length - 1) {
        setSelected(items[currentIndex + 1].id);
      } else {
        setSelected("draft");
      }
    },
    [items, archivedItems, activeTab, setSelected]
  );

  const fillerCount = useMemo(() => {
    if (activeTab === "archive") return 0;
    const used = items.length + 1; // +1 for draft
    return Math.max(0, VISIBLE_ROWS - used);
  }, [items.length, activeTab]);

  if (activeTab === "archive") {
    return (
      <div className={styles.list}>
        {archivedItems.length === 0 ? (
          <div className={styles.emptyState}>No archived items</div>
        ) : (
          <AnimatePresence mode="popLayout">
            {archivedItems.map((item, i) => (
              <TodoRow
                key={item.id}
                id={item.id}
                kind="archiveItem"
                text={item.text}
                isDone={true}
                isSelected={selectedId === item.id}
                onRestore={() => restoreItem(item.id)}
                onSelect={() => setSelected(item.id)}
                onNavigateUp={() => handleNavigateUp(i)}
                onNavigateDown={() => handleNavigateDown(i)}
              />
            ))}
          </AnimatePresence>
        )}
      </div>
    );
  }

  return (
    <div className={styles.list}>
      <AnimatePresence mode="popLayout">
        {items.map((item, i) => (
          <TodoRow
            key={item.id}
            id={item.id}
            kind="taskItem"
            text={item.text}
            isDone={item.isDone}
            isSelected={selectedId === item.id}
            onComplete={() => archiveItem(item.id)}
            onTextChange={(text) => updateText(item.id, text)}
            onSelect={() => setSelected(item.id)}
            onNavigateUp={() => handleNavigateUp(i)}
            onNavigateDown={() => handleNavigateDown(i)}
          />
        ))}
      </AnimatePresence>

      <TodoRow
        id="draft"
        kind="taskDraft"
        text={draftText}
        isDone={false}
        isSelected={selectedId === "draft" || selectedId === null}
        onTextChange={setDraftText}
        onSubmit={handleSubmitDraft}
        onSelect={() => setSelected("draft")}
        onNavigateUp={() => {
          if (items.length > 0) {
            setSelected(items[items.length - 1].id);
          }
        }}
        onNavigateDown={() => {}}
        autoFocus
      />

      {Array.from({ length: fillerCount }, (_, i) => (
        <TodoRow
          key={`filler-${i}`}
          id={`filler-${i}`}
          kind="filler"
          text=""
          isDone={false}
          isSelected={false}
        />
      ))}
    </div>
  );
}
