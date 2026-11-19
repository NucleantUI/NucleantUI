//
//  Inbox.swift
//  Chat
//
//  The conversations and what is said in them. Each conversation is an
//  `@Observable` class of its own, so a thread is rebuilt for its own
//  messages and draft, and the list only for what its rows show.
//

import Foundation
import NucleantUI
import Observation

/// One message in a thread.
struct Message: Identifiable, Equatable {
    let id: Int
    let text: String
    let isMine: Bool
    /// When it was sent, as "9:41".
    let time: String
}

/// A thread with one person: what was said, what is being written, and
/// whether they are writing back.
@MainActor
@Observable
final class Conversation: Identifiable {
    let id: Int
    let name: String
    let color: Color

    private(set) var messages: [Message]
    /// What is written in the composer and not sent yet.
    var draft = ""
    /// The other person is writing a reply.
    private(set) var isTyping = false
    /// Replies that came in while the thread was not open.
    private(set) var unread: Int

    /// What they answer with, in turn.
    private let replies: [String]
    private var nextReply = 0
    private var nextID: Int
    private var isOpen = false

    init(id: Int, name: String, color: Color, unread: Int = 0, replies: [String], messages: [(String, Bool, String)]) {
        self.id = id
        self.name = name
        self.color = color
        self.unread = unread
        self.replies = replies
        self.messages = messages.enumerated().map { index, message in
            Message(id: index, text: message.0, isMine: message.1, time: message.2)
        }
        self.nextID = messages.count
    }

    var initials: String {
        String(name.split(separator: " ").compactMap(\.first).prefix(2))
    }

    var lastMessage: Message? { messages.last }

    /// The draft has something in it to send.
    var canSend: Bool {
        !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Send the draft, and have the other person answer it a moment later.
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        append(text, isMine: true)
        draft = ""
        let reply = replies[nextReply % replies.count]
        nextReply += 1
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.8))
            self?.isTyping = true
            try? await Task.sleep(for: .seconds(1.6))
            guard let self else { return }
            self.isTyping = false
            self.append(reply, isMine: false)
            if !self.isOpen { self.unread += 1 }
        }
    }

    /// The thread is on screen: what came in is read.
    func open() {
        isOpen = true
        unread = 0
    }

    func close() {
        isOpen = false
    }

    /// Whether the name or anything said matches `query`.
    func matches(_ query: String) -> Bool {
        name.localizedCaseInsensitiveContains(query)
            || messages.contains { $0.text.localizedCaseInsensitiveContains(query) }
    }

    private func append(_ text: String, isMine: Bool) {
        messages.append(Message(id: nextID, text: text, isMine: isMine, time: Self.now()))
        nextID += 1
    }

    /// The time of day, as a message shows it.
    private static func now() -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: Date())
        let minute = parts.minute ?? 0
        return "\(parts.hour ?? 0):\(minute < 10 ? "0" : "")\(minute)"
    }
}

/// Every conversation, most recent first.
@MainActor
@Observable
final class Inbox {
    let conversations: [Conversation]

    init() {
        conversations = [
            Conversation(
                id: 1, name: "Maya Lindqvist", color: Color(hex: 0x3B82F6), unread: 2,
                replies: ["Perfect, see you there!", "Haha yes", "I'll bring the snacks", "Sounds good to me"],
                messages: [
                    ("Are we still on for the climbing gym on Saturday?", false, "9:12"),
                    ("Yes! 10 o'clock?", true, "9:14"),
                    ("10 works. I booked the bouldering area until noon.", false, "9:15"),
                    ("Can you bring the spare chalk bag? Mine split open last week and there is still chalk in every pocket of my backpack.", false, "9:15"),
                ]
            ),
            Conversation(
                id: 2, name: "Jonas Weber", color: Color(hex: 0x10B981),
                replies: ["Got it, thanks", "Let me check and get back to you", "That's great news", "👍"],
                messages: [
                    ("The build is green again", false, "Yesterday"),
                    ("Nice, what was it?", true, "Yesterday"),
                    ("A test that only failed when the window was smaller than its content. Fixed the layout and it passes on every platform now.", false, "Yesterday"),
                ]
            ),
            Conversation(
                id: 3, name: "Priya Raman", color: Color(hex: 0xF59E0B), unread: 1,
                replies: ["Oh nice, which one?", "I've been meaning to read that", "Send me a photo!", "Tell me more"],
                messages: [
                    ("Finished the book you lent me", true, "Mon"),
                    ("And?", false, "Mon"),
                    ("The last chapter. I did not see that coming at all.", true, "Mon"),
                    ("Right?! I need the sequel now", false, "Mon"),
                ]
            ),
            Conversation(
                id: 4, name: "Leo Moreau", color: Color(hex: 0xEC4899),
                replies: ["Merci!", "I'll ask my sister", "Yes, Thursday works", "Can't wait"],
                messages: [
                    ("Dinner at ours on Thursday?", false, "Sun"),
                    ("We'd love to. What can we bring?", true, "Sun"),
                ]
            ),
            Conversation(
                id: 5, name: "Sam Okafor", color: Color(hex: 0x8B5CF6),
                replies: ["Ha, classic", "On my way", "Save me a seat", "Who's driving?"],
                messages: [
                    ("Game night moved to 8", false, "Sat"),
                ]
            ),
            Conversation(
                id: 6, name: "Ana Costa", color: Color(hex: 0x14B8A6),
                replies: ["Thank you so much", "Ok, booking it now", "Let's do it", "I'll send the details"],
                messages: [
                    ("The flat in Lisbon is free the second week of June", false, "Fri"),
                    ("Book it before someone else does!", true, "Fri"),
                ]
            ),
        ]
    }

    func conversation(_ id: Int) -> Conversation? {
        conversations.first { $0.id == id }
    }
}
