"use client";

import { FloatingWindow } from "@/components/floating-window";
import { TodoList } from "@/components/todo-list";
import styles from "./page.module.scss";

export default function Home() {
  return (
    <div className={styles.scene}>
      <div className={styles.windowContainer}>
        <FloatingWindow>
          <TodoList />
        </FloatingWindow>
      </div>
      <p className={styles.tagline}>
        A tiny floating todo list for macOS — coming soon
      </p>
    </div>
  );
}
