"use client";

import { useRef, useEffect, useState, useCallback } from "react";
import { motion, AnimatePresence } from "motion/react";
import styles from "./todo-row.module.scss";

interface TodoRowProps {
  id: string;
  kind: "taskItem" | "archiveItem" | "taskDraft" | "filler";
  text: string;
  isDone: boolean;
  isSelected: boolean;
  onComplete?: () => void;
  onRestore?: () => void;
  onTextChange?: (text: string) => void;
  onSubmit?: (text: string) => void;
  onSelect?: () => void;
  onNavigateUp?: () => void;
  onNavigateDown?: () => void;
  autoFocus?: boolean;
}

function CheckmarkSvg() {
  return (
    <svg className={styles.checkmark} viewBox="0 0 10 10">
      <path d="M2 5.5L4 7.5L8 3" />
    </svg>
  );
}

export function TodoRow({
  id,
  kind,
  text,
  isDone,
  isSelected,
  onComplete,
  onRestore,
  onTextChange,
  onSubmit,
  onSelect,
  onNavigateUp,
  onNavigateDown,
  autoFocus,
}: TodoRowProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const [completing, setCompleting] = useState(false);

  useEffect(() => {
    if (autoFocus && inputRef.current) {
      inputRef.current.focus();
    }
  }, [autoFocus]);

  useEffect(() => {
    if (isSelected && inputRef.current) {
      inputRef.current.focus();
    }
  }, [isSelected]);

  const handleCircleClick = useCallback(() => {
    if (kind === "archiveItem" && onRestore) {
      onRestore();
      return;
    }
    if (kind !== "taskItem" || !onComplete) return;
    setCompleting(true);
    setTimeout(() => {
      onComplete();
      setCompleting(false);
    }, 250);
  }, [kind, onComplete, onRestore]);

  const handleKeyDown = useCallback(
    (e: React.KeyboardEvent) => {
      if (e.key === "Enter") {
        e.preventDefault();
        if (kind === "taskDraft" && onSubmit) {
          onSubmit((e.target as HTMLInputElement).value);
        }
      } else if (e.key === "ArrowUp") {
        e.preventDefault();
        onNavigateUp?.();
      } else if (e.key === "ArrowDown") {
        e.preventDefault();
        onNavigateDown?.();
      } else if (e.key === "Backspace") {
        const input = e.target as HTMLInputElement;
        if (input.value === "" && kind === "taskItem") {
          e.preventDefault();
          onComplete?.();
        }
      }
    },
    [kind, onSubmit, onNavigateUp, onNavigateDown, onComplete]
  );

  if (kind === "filler") {
    return (
      <div className={styles.row} data-kind="filler">
        <div className={styles.fillerCircle} />
      </div>
    );
  }

  if (kind === "archiveItem") {
    return (
      <motion.div
        className={styles.row}
        data-selected={isSelected}
        onClick={onSelect}
        layout
        initial={{ opacity: 0, y: -8 }}
        animate={{ opacity: 1, y: 0 }}
        exit={{ opacity: 0, height: 0 }}
        transition={{ duration: 0.22, ease: [0.19, 1, 0.22, 1] }}
      >
        <div className={styles.rowBackground} />
        <div
          className={styles.circle}
          data-done="true"
          onClick={handleCircleClick}
        >
          <CheckmarkSvg />
        </div>
        <span className={styles.archiveText}>{text}</span>
      </motion.div>
    );
  }

  if (kind === "taskDraft") {
    return (
      <div className={styles.row} data-selected={isSelected} onClick={onSelect}>
        <div className={styles.rowBackground} />
        <div className={styles.circle}>
          <CheckmarkSvg />
        </div>
        <input
          ref={inputRef}
          className={styles.input}
          type="text"
          value={text}
          placeholder=""
          onChange={(e) => onTextChange?.(e.target.value)}
          onKeyDown={handleKeyDown}
          onFocus={onSelect}
          autoFocus={autoFocus}
        />
      </div>
    );
  }

  // taskItem
  return (
    <motion.div
      className={styles.row}
      data-selected={isSelected}
      data-completing={completing}
      onClick={onSelect}
      layout
      initial={{ opacity: 0, y: -8 }}
      animate={{ opacity: 1, y: 0 }}
      exit={{ opacity: 0, height: 0, marginTop: 0 }}
      transition={{ duration: 0.22, ease: [0.19, 1, 0.22, 1] }}
    >
      <div className={styles.rowBackground} />
      <div
        className={styles.circle}
        data-done={completing}
        onClick={handleCircleClick}
      >
        <CheckmarkSvg />
      </div>
      {isSelected ? (
        <input
          ref={inputRef}
          className={styles.input}
          type="text"
          value={text}
          onChange={(e) => onTextChange?.(e.target.value)}
          onKeyDown={handleKeyDown}
          onFocus={onSelect}
        />
      ) : (
        <span className={styles.text}>{text}</span>
      )}
    </motion.div>
  );
}
