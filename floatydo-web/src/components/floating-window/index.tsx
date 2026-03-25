"use client";

import type { ReactNode } from "react";
import styles from "./floating-window.module.scss";

function FilterIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
      <line x1="2" y1="4" x2="14" y2="4" />
      <line x1="4" y1="8" x2="12" y2="8" />
      <line x1="6" y1="12" x2="10" y2="12" />
    </svg>
  );
}

function ListIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round">
      <line x1="2" y1="4" x2="14" y2="4" />
      <line x1="2" y1="8" x2="14" y2="8" />
      <line x1="2" y1="12" x2="14" y2="12" />
    </svg>
  );
}

function GearIcon() {
  return (
    <svg viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round">
      <circle cx="8" cy="8" r="2" />
      <path d="M8 1.5v1.5M8 13v1.5M1.5 8H3M13 8h1.5M3.05 3.05l1.06 1.06M11.89 11.89l1.06 1.06M3.05 12.95l1.06-1.06M11.89 4.11l1.06-1.06" />
    </svg>
  );
}

interface FloatingWindowProps {
  children: ReactNode;
}

export function FloatingWindow({ children }: FloatingWindowProps) {
  return (
    <div className={styles.window}>
      <div className={styles.titlebar}>
        <div className={styles.trafficLights}>
          <div className={`${styles.trafficLight} ${styles.close}`} />
          <div className={`${styles.trafficLight} ${styles.minimize}`} />
          <div className={`${styles.trafficLight} ${styles.maximize}`} />
        </div>
        <div className={styles.toolbarActions}>
          <button className={styles.toolbarButton} type="button" aria-label="Filter">
            <FilterIcon />
          </button>
          <button className={styles.toolbarButton} type="button" aria-label="List view">
            <ListIcon />
          </button>
          <button className={styles.toolbarButton} type="button" aria-label="Settings">
            <GearIcon />
          </button>
        </div>
      </div>
      <div className={styles.content}>
        {children}
      </div>
    </div>
  );
}
