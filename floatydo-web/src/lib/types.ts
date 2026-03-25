export interface TodoItem {
  id: string;
  text: string;
  isDone: boolean;
}

export type TodoRowKind = "taskItem" | "archiveItem" | "taskDraft" | "filler";

export interface TodoRowModel {
  id: string;
  kind: TodoRowKind;
  text: string;
  isDone: boolean;
  isEditable: boolean;
  isSelectable: boolean;
  canComplete: boolean;
  canDrag: boolean;
  circleOpacity: number;
  textOpacity: number;
  showsStrikethrough: boolean;
  itemId?: string;
}
