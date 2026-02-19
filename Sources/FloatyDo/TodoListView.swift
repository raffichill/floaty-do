import SwiftUI

struct TodoListView: View {
    @ObservedObject var store: TodoStore
    @State private var newText = ""
    @FocusState private var focusedRow: Int?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<TodoStore.maxItems, id: \.self) { index in
                if index < store.items.count {
                    FilledRow(item: store.items[index], store: store)
                } else if index == store.items.count {
                    // First empty row is the input
                    InputRow(text: $newText, focusedRow: $focusedRow, index: index) {
                        store.add(newText)
                        newText = ""
                    }
                } else {
                    EmptyRow()
                }
            }
        }
        .padding(.vertical, 8)
        .frame(width: 260)
        .background(.ultraThinMaterial)
        .onAppear { focusedRow = store.items.count }
    }
}

private struct FilledRow: View {
    let item: TodoItem
    @ObservedObject var store: TodoStore

    var body: some View {
        HStack(spacing: 8) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.toggle(item)
                }
            } label: {
                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(item.isDone ? .green : .secondary)
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)

            Text(item.text)
                .font(.system(size: 13))
                .strikethrough(item.isDone)
                .foregroundStyle(item.isDone ? .tertiary : .primary)
                .lineLimit(1)

            Spacer()

            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.delete(item)
                }
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
            .opacity(0.5)
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .overlay(alignment: .bottom) {
            Divider().padding(.horizontal, 12)
        }
    }
}

private struct InputRow: View {
    @Binding var text: String
    var focusedRow: FocusState<Int?>.Binding
    let index: Int
    let onSubmit: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "circle")
                .foregroundStyle(.quaternary)
                .font(.system(size: 14))

            TextField("", text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(.primary)
                .focused(focusedRow, equals: index)
                .onSubmit {
                    onSubmit()
                    focusedRow.wrappedValue = index
                }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .overlay(alignment: .bottom) {
            Divider().padding(.horizontal, 12)
        }
    }
}

private struct EmptyRow: View {
    var body: some View {
        Color.clear
            .frame(height: 32)
            .overlay(alignment: .bottom) {
                Divider().padding(.horizontal, 12)
            }
    }
}
