//
//  ChatApp.swift
//  Chat
//
//  A messaging app, and what a messaging app needs from the on-screen
//  keyboard: to stay out of the way of what you are writing.
//
//  * Chats — the conversations, searched from a field at the top. While
//    the keyboard is up, the list is laid out above it, so every result can
//    still be scrolled to.
//  * A thread — the composer sits on the keyboard and rides up and down
//    with it, on the keyboard's own animation, growing up to five lines as
//    you write. The messages stay at their newest above it
//    (`.defaultScrollAnchor(.bottom)`), and dragging them down puts the
//    keyboard away (`.scrollDismissesKeyboard(.interactively)`). The
//    wallpaper behind it all ignores the keyboard
//    (`.ignoresSafeArea(.keyboard)`), so it stays still while everything
//    on it moves.
//
//  Everything is laid out inside the window's safe area — clear of the
//  status bar, the sensor housing and the home indicator — while the bar
//  and composer colors run on under them, as style backgrounds do.
//
//  Made for mobile platforms only: it needs an on-screen keyboard to keep
//  clear of. It builds and runs on a desktop, but no keyboard comes up
//  there, so nothing moves.
//

import NucleantUI

enum Theme {
    static let background = DynamicShapeStyle(light: Color(hex: 0xF4F5F7), dark: Color(hex: 0x0E0F12))
    static let chrome = DynamicShapeStyle(light: Color(hex: 0xFFFFFF, opacity: 0.96), dark: Color(hex: 0x1A1B20, opacity: 0.96))
    static let field = DynamicShapeStyle(light: Color(hex: 0xECEEF2), dark: Color(hex: 0x2A2C33))
    static let bubble = DynamicShapeStyle(light: Color.white, dark: Color(hex: 0x24262C))
    static let ink = DynamicShapeStyle(light: Color(hex: 0x15161A), dark: Color(hex: 0xF1F2F5))
    static let faint = DynamicShapeStyle(light: Color(white: 0, opacity: 0.45), dark: Color(white: 1, opacity: 0.45))
    static let rule = DynamicShapeStyle(light: Color(white: 0, opacity: 0.08), dark: Color(white: 1, opacity: 0.1))
    static let accent = Color(hex: 0x3B82F6)
}

@View
struct RootView {
    @State private var inbox = Inbox()
    @Environment(\.colorScheme) private var system

    var body: some View {
        NavigationStack {
            ChatsScreen(inbox: inbox)
        }
        .background(Theme.background)
        .foregroundStyle(Theme.ink)
        .tint(Theme.accent)
        .colorScheme(AppearanceModel.shared.appearance.scheme ?? system)
    }
}

@main
struct ChatApp: NucleantApp {
    var body: some Scene {
        WindowGroup("Chat") {
            RootView()
        }
        .defaultSize(width: 400, height: 780)
        .commands { AppearanceCommands() }
    }
}

// MARK: - Chats

/// The conversations, and a search over them.
@View
struct ChatsScreen {
    let inbox: Inbox

    @State private var query = ""

    private var shown: [Conversation] {
        let query = query.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? inbox.conversations : inbox.conversations.filter { $0.matches(query) }
    }

    var body: some View {
        VStack(spacing: 0) {
            SearchField(query: $query)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(shown) { conversation in
                        NavigationLink(value: conversation.id) {
                            ConversationRow(conversation: conversation)
                        }
                    }
                    if shown.isEmpty {
                        Text("No chats with “\(query)”.")
                            .font(.callout)
                            .foregroundStyle(Theme.faint)
                            .padding(.top, 32)
                    }
                }
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .navigationTitle("Chats")
        .navigationDestination(for: Int.self) { id in
            if let conversation = inbox.conversation(id) {
                ThreadScreen(conversation: conversation)
            }
        }
    }
}

@View
struct SearchField {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 8) {
            MagnifierShape()
                .stroke(Theme.faint, lineWidth: 1.6)
                .frame(width: 14, height: 14)
            TextField("Search", text: $query)
                .textFieldStyle(.plain)
            if !query.isEmpty {
                Button("Clear") { query = "" }
                    .font(.footnote)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.field))
    }
}

/// A conversation in the list: who, the last thing said, and how much is
/// unread.
@View
struct ConversationRow {
    let conversation: Conversation

    var body: some View {
        HStack(spacing: 12) {
            Avatar(conversation: conversation, size: 48)
            VStack(alignment: .leading, spacing: 3) {
                HStack {
                    Text(conversation.name)
                        .font(.system(size: 16, weight: .semibold))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text(conversation.lastMessage?.time ?? "")
                        .font(.caption)
                        .foregroundStyle(Theme.faint)
                }
                HStack(alignment: .top) {
                    Text(preview)
                        .font(.subheadline)
                        .foregroundStyle(Theme.faint)
                        .lineLimit(2)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if conversation.unread > 0 {
                        Text("\(conversation.unread)")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(Color.white)
                            .padding(.horizontal, 7)
                            .frame(minWidth: 20, minHeight: 20)
                            .background(Capsule().fill(Theme.accent))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
        .foregroundStyle(Theme.ink)
    }

    private var preview: String {
        guard let last = conversation.lastMessage else { return "" }
        return last.isMine ? "You: \(last.text)" : last.text
    }
}

/// A person's initials on their color.
@View
struct Avatar {
    let conversation: Conversation
    let size: Double

    var body: some View {
        Text(conversation.initials)
            .font(.system(size: size * 0.38, weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(width: size, height: size)
            .background(Circle().fill(conversation.color))
    }
}

/// A search glass: a ring and its handle.
@View
struct MagnifierShape: Shape {
    func path(in rect: Rect) -> Path {
        var path = Path()
        let radius = min(rect.width, rect.height) * 0.36
        path.addEllipse(in: Rect(x: rect.minX, y: rect.minY, width: radius * 2, height: radius * 2))
        let reach = radius * 0.71
        path.move(to: Point(x: rect.minX + radius + reach, y: rect.minY + radius + reach))
        path.addLine(to: Point(x: rect.maxX, y: rect.maxY))
        return path
    }
}
