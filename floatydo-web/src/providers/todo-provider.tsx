"use client";

import {
  createContext,
  useContext,
  useReducer,
  useCallback,
  type ReactNode,
} from "react";
import type { TodoItem } from "@/lib/types";

const MAX_ITEMS = 10;

interface TodoState {
  items: TodoItem[];
  archivedItems: TodoItem[];
  draftText: string;
  selectedId: string | null;
  activeTab: "tasks" | "archive";
}

type TodoAction =
  | { type: "ADD_ITEM"; text: string }
  | { type: "INSERT_ITEM"; text: string; index: number }
  | { type: "UPDATE_TEXT"; id: string; text: string }
  | { type: "ARCHIVE_ITEM"; id: string }
  | { type: "RESTORE_ITEM"; id: string }
  | { type: "DELETE_ITEM"; id: string }
  | { type: "DELETE_ARCHIVED"; id: string }
  | { type: "REORDER_ITEM"; id: string; destinationIndex: number }
  | { type: "SET_DRAFT_TEXT"; text: string }
  | { type: "SET_SELECTED"; id: string | null }
  | { type: "SET_TAB"; tab: "tasks" | "archive" };

function generateId(): string {
  return crypto.randomUUID();
}

function todoReducer(state: TodoState, action: TodoAction): TodoState {
  switch (action.type) {
    case "ADD_ITEM": {
      const text = action.text.trim();
      if (!text || state.items.length >= MAX_ITEMS) return state;
      const newItem: TodoItem = { id: generateId(), text, isDone: false };
      return {
        ...state,
        items: [...state.items, newItem],
        draftText: "",
      };
    }

    case "INSERT_ITEM": {
      const text = action.text.trim();
      if (!text || state.items.length >= MAX_ITEMS) return state;
      const newItem: TodoItem = { id: generateId(), text, isDone: false };
      const items = [...state.items];
      const idx = Math.max(0, Math.min(action.index, items.length));
      items.splice(idx, 0, newItem);
      return { ...state, items };
    }

    case "UPDATE_TEXT": {
      return {
        ...state,
        items: state.items.map((item) =>
          item.id === action.id ? { ...item, text: action.text } : item
        ),
      };
    }

    case "ARCHIVE_ITEM": {
      const item = state.items.find((i) => i.id === action.id);
      if (!item) return state;
      return {
        ...state,
        items: state.items.filter((i) => i.id !== action.id),
        archivedItems: [
          { ...item, isDone: true },
          ...state.archivedItems,
        ],
      };
    }

    case "RESTORE_ITEM": {
      const item = state.archivedItems.find((i) => i.id === action.id);
      if (!item || state.items.length >= MAX_ITEMS) return state;
      return {
        ...state,
        archivedItems: state.archivedItems.filter((i) => i.id !== action.id),
        items: [...state.items, { ...item, isDone: false }],
      };
    }

    case "DELETE_ITEM": {
      return {
        ...state,
        items: state.items.filter((i) => i.id !== action.id),
      };
    }

    case "DELETE_ARCHIVED": {
      return {
        ...state,
        archivedItems: state.archivedItems.filter((i) => i.id !== action.id),
      };
    }

    case "REORDER_ITEM": {
      const idx = state.items.findIndex((i) => i.id === action.id);
      if (idx === -1) return state;
      const items = [...state.items];
      const [moved] = items.splice(idx, 1);
      const dest = Math.max(0, Math.min(action.destinationIndex, items.length));
      items.splice(dest, 0, moved);
      return { ...state, items };
    }

    case "SET_DRAFT_TEXT": {
      return { ...state, draftText: action.text };
    }

    case "SET_SELECTED": {
      return { ...state, selectedId: action.id };
    }

    case "SET_TAB": {
      return { ...state, activeTab: action.tab, selectedId: null };
    }

    default:
      return state;
  }
}

const INITIAL_STATE: TodoState = {
  items: [
    { id: "demo-1", text: "Try typing a new todo below", isDone: false },
    { id: "demo-2", text: "Click the circle to complete", isDone: false },
  ],
  archivedItems: [],
  draftText: "",
  selectedId: null,
  activeTab: "tasks",
};

interface TodoContextValue {
  state: TodoState;
  addItem: (text: string) => void;
  insertItem: (text: string, index: number) => void;
  updateText: (id: string, text: string) => void;
  archiveItem: (id: string) => void;
  restoreItem: (id: string) => void;
  deleteItem: (id: string) => void;
  deleteArchived: (id: string) => void;
  reorderItem: (id: string, destinationIndex: number) => void;
  setDraftText: (text: string) => void;
  setSelected: (id: string | null) => void;
  setTab: (tab: "tasks" | "archive") => void;
  canAddMore: boolean;
}

const TodoContext = createContext<TodoContextValue | null>(null);

export function TodoProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(todoReducer, INITIAL_STATE);

  const addItem = useCallback(
    (text: string) => dispatch({ type: "ADD_ITEM", text }),
    []
  );
  const insertItem = useCallback(
    (text: string, index: number) =>
      dispatch({ type: "INSERT_ITEM", text, index }),
    []
  );
  const updateText = useCallback(
    (id: string, text: string) => dispatch({ type: "UPDATE_TEXT", id, text }),
    []
  );
  const archiveItem = useCallback(
    (id: string) => dispatch({ type: "ARCHIVE_ITEM", id }),
    []
  );
  const restoreItem = useCallback(
    (id: string) => dispatch({ type: "RESTORE_ITEM", id }),
    []
  );
  const deleteItem = useCallback(
    (id: string) => dispatch({ type: "DELETE_ITEM", id }),
    []
  );
  const deleteArchived = useCallback(
    (id: string) => dispatch({ type: "DELETE_ARCHIVED", id }),
    []
  );
  const reorderItem = useCallback(
    (id: string, destinationIndex: number) =>
      dispatch({ type: "REORDER_ITEM", id, destinationIndex }),
    []
  );
  const setDraftText = useCallback(
    (text: string) => dispatch({ type: "SET_DRAFT_TEXT", text }),
    []
  );
  const setSelected = useCallback(
    (id: string | null) => dispatch({ type: "SET_SELECTED", id }),
    []
  );
  const setTab = useCallback(
    (tab: "tasks" | "archive") => dispatch({ type: "SET_TAB", tab }),
    []
  );

  return (
    <TodoContext.Provider
      value={{
        state,
        addItem,
        insertItem,
        updateText,
        archiveItem,
        restoreItem,
        deleteItem,
        deleteArchived,
        reorderItem,
        setDraftText,
        setSelected,
        setTab,
        canAddMore: state.items.length < MAX_ITEMS,
      }}
    >
      {children}
    </TodoContext.Provider>
  );
}

export function useTodo() {
  const ctx = useContext(TodoContext);
  if (!ctx) throw new Error("useTodo must be used within TodoProvider");
  return ctx;
}
