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

// Draft state matching macOS TaskListStructurePolicy
interface DraftState {
  insertionIndex: number;
  text: string;
  // Structural drafts are created by keyboard (Return on task, Up from first)
  // They collapse when navigating away if empty
  isStructural: boolean;
}

export interface TodoState {
  items: TodoItem[];
  archivedItems: TodoItem[];
  draft: DraftState;
  selectedId: string | null; // item id, "draft", or null
}

export type TodoAction =
  | { type: "ADD_ITEM"; text: string }
  | { type: "INSERT_ITEM"; text: string; index: number }
  | { type: "UPDATE_TEXT"; id: string; text: string }
  | { type: "ARCHIVE_ITEM"; id: string }
  | { type: "RESTORE_ITEM"; id: string }
  | { type: "DELETE_ITEM"; id: string }
  | { type: "REORDER_ITEM"; id: string; destinationIndex: number }
  | { type: "SET_DRAFT"; draft: Partial<DraftState> }
  | { type: "SET_SELECTED"; id: string | null }
  // Keyboard-driven draft operations
  | { type: "ACTIVATE_DRAFT"; insertionIndex: number }
  | { type: "PROMOTE_DRAFT" }
  | { type: "COLLAPSE_DRAFT"; direction: -1 | 1 }
  | { type: "RESET_DRAFT" };

function generateId(): string {
  return crypto.randomUUID();
}

function defaultDraft(itemCount: number): DraftState {
  return { insertionIndex: itemCount, text: "", isStructural: false };
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
        draft: defaultDraft(state.items.length + 1),
        selectedId: "draft",
      };
    }

    case "INSERT_ITEM": {
      const text = action.text.trim();
      if (!text || state.items.length >= MAX_ITEMS) return state;
      const newItem: TodoItem = { id: generateId(), text, isDone: false };
      const items = [...state.items];
      const idx = Math.max(0, Math.min(action.index, items.length));
      items.splice(idx, 0, newItem);
      return {
        ...state,
        items,
        draft: defaultDraft(items.length),
      };
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
      const itemIndex = state.items.indexOf(item);
      const newItems = state.items.filter((i) => i.id !== action.id);

      // Select next item or draft
      let nextSelected: string | null = "draft";
      if (newItems.length > 0) {
        const nextIdx = Math.min(itemIndex, newItems.length - 1);
        nextSelected = newItems[nextIdx].id;
      }

      return {
        ...state,
        items: newItems,
        archivedItems: [{ ...item, isDone: true }, ...state.archivedItems],
        draft: defaultDraft(newItems.length),
        selectedId: nextSelected,
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
      const newItems = state.items.filter((i) => i.id !== action.id);
      return {
        ...state,
        items: newItems,
        draft: defaultDraft(newItems.length),
      };
    }

    case "REORDER_ITEM": {
      const idx = state.items.findIndex((i) => i.id === action.id);
      if (idx === -1) return state;
      const items = [...state.items];
      const [moved] = items.splice(idx, 1);
      const dest = Math.max(0, Math.min(action.destinationIndex, items.length));
      items.splice(dest, 0, moved);
      return { ...state, items, draft: defaultDraft(items.length) };
    }

    case "SET_DRAFT": {
      return {
        ...state,
        draft: { ...state.draft, ...action.draft },
      };
    }

    case "SET_SELECTED": {
      return { ...state, selectedId: action.id };
    }

    // Create structural draft at a specific insertion index
    case "ACTIVATE_DRAFT": {
      return {
        ...state,
        draft: {
          insertionIndex: action.insertionIndex,
          text: "",
          isStructural: true,
        },
        selectedId: "draft",
      };
    }

    // Promote non-empty draft to a real task item
    case "PROMOTE_DRAFT": {
      const text = state.draft.text.trim();
      if (!text || state.items.length >= MAX_ITEMS) return state;
      const newItem: TodoItem = { id: generateId(), text, isDone: false };
      const items = [...state.items];
      const idx = Math.max(
        0,
        Math.min(state.draft.insertionIndex, items.length)
      );
      items.splice(idx, 0, newItem);
      // New draft goes right below the just-inserted item
      return {
        ...state,
        items,
        draft: {
          insertionIndex: idx + 1,
          text: "",
          isStructural: true,
        },
        selectedId: "draft",
      };
    }

    // Collapse empty structural draft back to default
    case "COLLAPSE_DRAFT": {
      if (!state.draft.isStructural || state.draft.text.trim() !== "") {
        return state;
      }
      const draftIdx = state.draft.insertionIndex;
      // Select adjacent item based on direction
      let nextSelected: string | null = "draft";
      if (action.direction < 0 && draftIdx > 0 && state.items.length > 0) {
        // Collapsing upward: select item above draft position
        const targetIdx = Math.min(draftIdx - 1, state.items.length - 1);
        nextSelected = state.items[targetIdx].id;
      } else if (action.direction > 0 && state.items.length > 0) {
        // Collapsing downward: select item below draft position
        const targetIdx = Math.min(draftIdx, state.items.length - 1);
        nextSelected = state.items[targetIdx].id;
      }
      return {
        ...state,
        draft: defaultDraft(state.items.length),
        selectedId: nextSelected,
      };
    }

    case "RESET_DRAFT": {
      return {
        ...state,
        draft: defaultDraft(state.items.length),
      };
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
  draft: { insertionIndex: 2, text: "", isStructural: false },
  selectedId: "draft",
};

interface TodoContextValue {
  state: TodoState;
  dispatch: React.Dispatch<TodoAction>;
  addItem: (text: string) => void;
  updateText: (id: string, text: string) => void;
  archiveItem: (id: string) => void;
  restoreItem: (id: string) => void;
  reorderItem: (id: string, destinationIndex: number) => void;
  setDraftText: (text: string) => void;
  setSelected: (id: string | null) => void;
  activateDraft: (insertionIndex: number) => void;
  promoteDraft: () => void;
  collapseDraft: (direction: -1 | 1) => void;
  canAddMore: boolean;
  isDraftDefault: boolean;
  isDraftStructuralEmpty: boolean;
}

const TodoContext = createContext<TodoContextValue | null>(null);

export function TodoProvider({ children }: { children: ReactNode }) {
  const [state, dispatch] = useReducer(todoReducer, INITIAL_STATE);

  const addItem = useCallback(
    (text: string) => dispatch({ type: "ADD_ITEM", text }),
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
  const reorderItem = useCallback(
    (id: string, destinationIndex: number) =>
      dispatch({ type: "REORDER_ITEM", id, destinationIndex }),
    []
  );
  const setDraftText = useCallback(
    (text: string) => dispatch({ type: "SET_DRAFT", draft: { text } }),
    []
  );
  const setSelected = useCallback(
    (id: string | null) => dispatch({ type: "SET_SELECTED", id }),
    []
  );
  const activateDraft = useCallback(
    (insertionIndex: number) =>
      dispatch({ type: "ACTIVATE_DRAFT", insertionIndex }),
    []
  );
  const promoteDraft = useCallback(() => dispatch({ type: "PROMOTE_DRAFT" }), []);
  const collapseDraft = useCallback(
    (direction: -1 | 1) => dispatch({ type: "COLLAPSE_DRAFT", direction }),
    []
  );

  const isDraftDefault =
    !state.draft.isStructural &&
    state.draft.insertionIndex === state.items.length;
  const isDraftStructuralEmpty =
    state.draft.isStructural && state.draft.text.trim() === "";

  return (
    <TodoContext.Provider
      value={{
        state,
        dispatch,
        addItem,
        updateText,
        archiveItem,
        restoreItem,
        reorderItem,
        setDraftText,
        setSelected,
        activateDraft,
        promoteDraft,
        collapseDraft,
        canAddMore: state.items.length < MAX_ITEMS,
        isDraftDefault,
        isDraftStructuralEmpty,
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
