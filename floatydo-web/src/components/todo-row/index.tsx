"use client";

import { useRef, useEffect, useState, useCallback } from "react";
import { motion, useMotionValue, useSpring, animate } from "motion/react";
import styles from "./todo-row.module.scss";

// Balanced motion profile from macOS app
const MOTION = {
  completionSweep: 0.25,
  checkSwapDelay: 0.1,
  completionSettle: 0.6,
  collapse: 0.35,
  reflow: 0.22,
  hoverFade: 0.14,
} as const;

// Boundary shake keyframes from macOS app
const SHAKE_KEYFRAMES = [0, -2.5, 2, -1.25, 0.75, 0];
const SHAKE_TIMES = [0, 0.18, 0.42, 0.68, 0.86, 1.0];
const SHAKE_DURATION = 0.24;

export interface TodoRowProps {
  id: string;
  kind: "taskItem" | "archiveItem" | "taskDraft" | "filler";
  text: string;
  isDone: boolean;
  isSelected: boolean;
  onComplete?: () => void;
  onRestore?: () => void;
  onTextChange?: (text: string) => void;
  onKeyDown?: (e: React.KeyboardEvent) => void;
  onSelect?: () => void;
  autoFocus?: boolean;
  onPointerDownOnRow?: (e: React.PointerEvent) => void;
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
  onKeyDown,
  onSelect,
  autoFocus,
  onPointerDownOnRow,
}: TodoRowProps) {
  const inputRef = useRef<HTMLInputElement>(null);
  const rowRef = useRef<HTMLDivElement>(null);

  // --- Completion animation state ---
  const [completing, setCompleting] = useState(false);
  const textOpacity = useMotionValue(1);
  const strikethroughScaleX = useMotionValue(0);
  const circleScale = useSpring(1, { stiffness: 200, damping: 15 });
  const [showCheckmark, setShowCheckmark] = useState(false);
  const rowOpacity = useMotionValue(1);

  // --- Selection fill animation ---
  const bgOpacity = useMotionValue(0);
  const prevSelected = useRef(false);

  useEffect(() => {
    if (isSelected && !prevSelected.current) {
      animate(bgOpacity, 1, {
        duration: MOTION.collapse,
        ease: [0.42, 0, 0.58, 1],
      });
    } else if (!isSelected && prevSelected.current) {
      animate(bgOpacity, 0, {
        duration: MOTION.hoverFade,
        ease: "easeOut",
      });
    }
    prevSelected.current = isSelected;
  }, [isSelected, bgOpacity]);

  // --- Boundary shake ---
  const shakeX = useMotionValue(0);

  // Expose shake on the DOM element
  useEffect(() => {
    const el = rowRef.current;
    if (el) {
      (el as HTMLDivElement & { __shake?: () => void }).__shake = () => {
        animate(shakeX, SHAKE_KEYFRAMES, {
          duration: SHAKE_DURATION,
          times: SHAKE_TIMES,
          ease: "easeOut",
        });
      };
    }
  });

  // --- Focus management ---
  useEffect(() => {
    if ((autoFocus || isSelected) && inputRef.current) {
      inputRef.current.focus();
    }
  }, [autoFocus, isSelected]);

  // --- Completion sequence (4 steps matching macOS) ---
  const handleComplete = useCallback(() => {
    if (kind !== "taskItem" || !onComplete || completing) return;
    setCompleting(true);

    // Step 1: Strikethrough sweep + text fade
    animate(textOpacity, 0.3, {
      duration: MOTION.completionSweep,
      ease: [0.42, 0, 0.58, 1],
    });
    animate(strikethroughScaleX, 1, {
      duration: MOTION.completionSweep,
      ease: [0.42, 0, 0.58, 1],
    });

    // Step 2: Circle shrink → swap → grow
    setTimeout(() => {
      circleScale.set(0);
      setTimeout(() => {
        setShowCheckmark(true);
        circleScale.set(1);
      }, 80);
    }, MOTION.checkSwapDelay * 1000);

    // Step 3: Row fade out
    const removalDelay =
      (MOTION.completionSweep +
        MOTION.checkSwapDelay +
        MOTION.completionSettle * 0.5) *
      1000;
    const removalDuration = MOTION.collapse * 0.75;
    setTimeout(() => {
      animate(rowOpacity, 0, {
        duration: removalDuration,
        ease: "easeOut",
        onComplete: () => {
          // Step 4: Archive and reflow
          onComplete();
          setCompleting(false);
          textOpacity.set(1);
          strikethroughScaleX.set(0);
          circleScale.set(1);
          setShowCheckmark(false);
          rowOpacity.set(1);
        },
      });
    }, removalDelay);
  }, [
    kind,
    onComplete,
    completing,
    textOpacity,
    strikethroughScaleX,
    circleScale,
    rowOpacity,
  ]);

  // ==================== FILLER ====================
  if (kind === "filler") {
    return (
      <div className={styles.row} data-kind="filler">
        <div className={styles.fillerCircle} />
      </div>
    );
  }

  // ==================== ARCHIVE ITEM ====================
  if (kind === "archiveItem") {
    return (
      <div className={styles.row} onPointerDown={onSelect}>
        <motion.div style={{ opacity: bgOpacity }} className={styles.rowBackground} />
        <motion.div
          className={styles.circle}
          style={{
            borderColor: "var(--floaty-text-secondary)",
            background: "var(--floaty-selection-overlay)",
          }}
          whileTap={{ scale: 0.92 }}
          onPointerUp={onRestore}
        >
          <svg className={styles.checkmarkVisible} viewBox="0 0 10 10">
            <path
              d="M2 5.5L4 7.5L8 3"
              stroke="var(--floaty-text-primary)"
              strokeWidth="1.8"
              strokeLinecap="round"
              strokeLinejoin="round"
              fill="none"
            />
          </svg>
        </motion.div>
        <span className={styles.archiveText}>{text}</span>
      </div>
    );
  }

  // ==================== DRAFT ROW ====================
  if (kind === "taskDraft") {
    return (
      <motion.div
        ref={rowRef}
        className={styles.row}
        data-row-id="draft"
        onPointerDown={onSelect}
        style={{ x: shakeX }}
      >
        <motion.div style={{ opacity: bgOpacity }} className={styles.rowBackground} />
        <div className={styles.draftCircle} />
        <input
          ref={inputRef}
          className={styles.input}
          type="text"
          value={text}
          placeholder=""
          onChange={(e) => onTextChange?.(e.target.value)}
          onKeyDown={onKeyDown}
          autoFocus={autoFocus}
        />
      </motion.div>
    );
  }

  // ==================== TASK ITEM ====================
  return (
    <motion.div
      ref={rowRef}
      className={styles.row}
      data-completing={completing || undefined}
      data-id={id}
      style={{ opacity: rowOpacity, x: shakeX }}
      onPointerDown={(e) => {
        if (completing) return;
        onSelect?.();
        onPointerDownOnRow?.(e);
      }}
    >
      <motion.div style={{ opacity: bgOpacity }} className={styles.rowBackground} />

      {/* Circle */}
      <motion.div
        className={styles.circle}
        style={{
          scale: completing ? circleScale : 1,
          borderColor: showCheckmark ? "var(--floaty-text-secondary)" : undefined,
          background: showCheckmark ? "var(--floaty-selection-overlay)" : undefined,
        }}
        whileTap={{ scale: 0.92 }}
        onPointerUp={(e) => {
          e.stopPropagation();
          handleComplete();
        }}
        onPointerDown={(e) => e.stopPropagation()}
      >
        {showCheckmark ? (
          <svg className={styles.checkmarkVisible} viewBox="0 0 10 10">
            <path
              d="M2 5.5L4 7.5L8 3"
              stroke="var(--floaty-text-primary)"
              strokeWidth="1.8"
              strokeLinecap="round"
              strokeLinejoin="round"
              fill="none"
            />
          </svg>
        ) : (
          <svg className={styles.checkmark} viewBox="0 0 10 10">
            <path d="M2 5.5L4 7.5L8 3" />
          </svg>
        )}
      </motion.div>

      {/* Text / Input */}
      {completing ? (
        <div className={styles.completingText}>
          <motion.span
            className={styles.text}
            style={{ opacity: textOpacity }}
          >
            {text}
          </motion.span>
          <motion.div
            className={styles.strikethroughLine}
            style={{ scaleX: strikethroughScaleX }}
          />
        </div>
      ) : isSelected ? (
        <input
          ref={inputRef}
          className={styles.input}
          type="text"
          value={text}
          onChange={(e) => onTextChange?.(e.target.value)}
          onKeyDown={onKeyDown}
        />
      ) : (
        <span className={styles.text}>{text}</span>
      )}
    </motion.div>
  );
}

export function shakeRow(el: HTMLElement | null) {
  const target = el?.querySelector?.("[data-row-id='draft']") ?? el;
  if (target && (target as HTMLElement & { __shake?: () => void }).__shake) {
    (target as HTMLElement & { __shake?: () => void }).__shake!();
  }
}
