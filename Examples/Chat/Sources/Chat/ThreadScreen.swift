//
//  ThreadScreen.swift
//  Chat
//
//  One conversation: the messages over the composer. Laid out above the
//  on-screen keyboard, the composer sits right on it and the messages fill
//  what is left; the wallpaper reaches under the keyboard instead, so it
//  stays where it is as the keyboard comes and goes.
//

import NucleantUI

@View
struct ThreadScreen {
    let conversation: Conversation

    var body: some View {
        VStack(spacing: 0) {
            MessageList(conversation: conversation)
            Composer(conversation: conversation)
        }
        .background {
            Wallpaper(color: conversation.color)
                .ignoresSafeArea(.keyboard)
        }
        .navigationTitle(conversation.name)
        .onAppear { conversation.open() }
        .onDisappear { conversation.close() }
    }
}

/// The messages, newest at the bottom, kept there as messages arrive and
/// as the keyboard makes the list shorter.
@View
struct MessageList {
    let conversation: Conversation

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 6) {
                ForEach(conversation.messages) { message in
                    Bubble(message: message, color: conversation.color)
                }
                if conversation.isTyping {
                    TypingBubble()
                        .transition(.opacity)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
        }
        .defaultScrollAnchor(.bottom)
        .scrollDismissesKeyboard(.interactively)
    }
}

/// One message: mine on the right in the conversation's color, theirs on
/// the left, the time under it.
@View
struct Bubble {
    let message: Message
    let color: Color

    private var alignment: Alignment { message.isMine ? .trailing : .leading }

    var body: some View {
        VStack(alignment: message.isMine ? .trailing : .leading, spacing: 2) {
            Group {
                if message.isMine {
                    Text(message.text)
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 18).fill(color))
                } else {
                    Text(message.text)
                        .foregroundStyle(Theme.ink)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.bubble))
                }
            }
            .frame(maxWidth: 280, alignment: alignment)
            Text(message.time)
                .font(.caption)
                .foregroundStyle(Theme.faint)
                .padding(.horizontal, 6)
        }
        .frame(maxWidth: .infinity, alignment: alignment)
    }
}

/// The other person writing: three dots in a bubble of theirs.
@View
struct TypingBubble {
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3) { _ in
                Circle().fill(Theme.faint).frame(width: 7, height: 7)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 18).fill(Theme.bubble))
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Where a message is written: a field that grows to five lines, and the
/// button that sends it.
@View
struct Composer {
    @Bindable var conversation: Conversation

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Message", text: $conversation.draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(RoundedRectangle(cornerRadius: 19).fill(Theme.field))
            Button { conversation.send() } label: {
                SendArrow()
                    .stroke(Color.white, lineWidth: 2.2)
                    .frame(width: 14, height: 16)
                    .frame(width: 38, height: 38)
                    .background(Circle().fill(conversation.canSend ? conversation.color : Color(white: 0.6, opacity: 0.5)))
            }
            .disabled(!conversation.canSend)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Theme.chrome)
    }
}

/// An arrow pointing up.
@View
struct SendArrow: Shape {
    func path(in rect: Rect) -> Path {
        var path = Path()
        path.move(to: Point(x: rect.midX, y: rect.maxY))
        path.addLine(to: Point(x: rect.midX, y: rect.minY))
        path.move(to: Point(x: rect.minX, y: rect.minY + rect.width / 2))
        path.addLine(to: Point(x: rect.midX, y: rect.minY))
        path.addLine(to: Point(x: rect.maxX, y: rect.minY + rect.width / 2))
        return path
    }
}

/// The conversation's color washed down the window, over the background.
@View
struct Wallpaper {
    let color: Color

    var body: some View {
        ZStack {
            Rectangle().fill(Theme.background)
            Rectangle().fill(LinearGradient(
                colors: [color.opacity(0.22), color.opacity(0.04)],
                startPoint: .top,
                endPoint: .bottom
            ))
        }
    }
}
