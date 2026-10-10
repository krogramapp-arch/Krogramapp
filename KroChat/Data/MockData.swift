import Foundation

/// Placeholder data for Phase 1. Everything here is fictional.
enum MockData {
    static let workFolder = ChatFolder(id: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!, name: "العمل", symbol: "briefcase")
    static let familyFolder = ChatFolder(id: UUID(uuidString: "10000000-0000-0000-0000-000000000002")!, name: "العائلة", symbol: "house")
    static let folders = [workFolder, familyFolder]

    static let contacts: [Contact] = [
        Contact(id: 1, name: "سارة", username: "sara_demo", isOnline: true),
        Contact(id: 2, name: "أحمد", username: "ahmed_demo", isOnline: false),
        Contact(id: 3, name: "ليلى", username: nil, isOnline: true),
        Contact(id: 4, name: "Omar", username: "omar_demo", isOnline: false),
        Contact(id: 5, name: "Noor", username: "noor_demo", isOnline: false)
    ]

    private static func ago(minutes: Int) -> Date {
        Date().addingTimeInterval(TimeInterval(-minutes * 60))
    }

    static func chats() -> [Chat] {
        let replyTarget = Message(text: "هل أرسلت لك ملف التصميم؟", date: ago(minutes: 50), isOutgoing: false)
        return [
            Chat(id: 1, title: "سارة", kind: .direct, isOnline: true, unread: 2, isPinned: true,
                 folderIDs: [familyFolder.id],
                 messages: [
                    Message(text: "صباح الخير! جاهزة للاجتماع؟", date: ago(minutes: 120), isOutgoing: false),
                    Message(text: "صباح النور، نعم جاهز", date: ago(minutes: 110), isOutgoing: true, state: .read),
                    replyTarget,
                    Message(text: "نعم وصلني، شكرًا. التفاصيل هنا: https://example.com/design", date: ago(minutes: 45), isOutgoing: true, state: .read, replyToID: replyTarget.id),
                    Message(text: "ممتاز 👌", date: ago(minutes: 12), isOutgoing: false, reactions: ["👍"]),
                    Message(text: "سأرسل المراجعة قبل الظهر", date: ago(minutes: 3), isOutgoing: false)
                 ]),
            Chat(id: 2, title: "فريق المشروع", kind: .group, unread: 5, isPinned: true,
                 folderIDs: [workFolder.id],
                 messages: [
                    Message(text: "تم دمج التعديلات في الفرع الرئيسي", date: ago(minutes: 200), isOutgoing: false),
                    Message(text: "رائع، سأجرّب البناء الآن", date: ago(minutes: 190), isOutgoing: true, state: .sent),
                    Message(text: "نجح البناء على المحاكي", date: ago(minutes: 30), isOutgoing: false)
                 ]),
            Chat(id: 3, title: "أحمد", kind: .direct, unread: 0,
                 folderIDs: [familyFolder.id],
                 messages: [
                    Message(text: "هل نلتقي نهاية الأسبوع؟", date: ago(minutes: 60 * 26), isOutgoing: false),
                    Message(text: "أكيد، أخبرني بالوقت", date: ago(minutes: 60 * 25), isOutgoing: true, state: .read)
                 ]),
            Chat(id: 4, title: "أخبار التقنية", kind: .channel, unread: 12, isMuted: true,
                 messages: [
                    Message(text: "إطلاق تحديث جديد لأدوات المطورين هذا الأسبوع", date: ago(minutes: 90), isOutgoing: false)
                 ]),
            Chat(id: 5, title: "Weather Bot", kind: .bot, unread: 0,
                 messages: [
                    Message(text: "/forecast", date: ago(minutes: 60 * 5), isOutgoing: true, state: .read),
                    Message(text: "اليوم مشمس، 31°", date: ago(minutes: 60 * 5), isOutgoing: false)
                 ]),
            Chat(id: 6, title: "ليلى", kind: .direct, isOnline: true, unread: 1,
                 messages: [
                    Message(text: "شفت الصور اللي أرسلتها؟", date: ago(minutes: 60 * 30), isOutgoing: false)
                 ]),
            Chat(id: 7, title: "Omar", kind: .direct, isArchived: true,
                 messages: [
                    Message(text: "Thanks for the update!", date: ago(minutes: 60 * 24 * 12), isOutgoing: false)
                 ]),
            Chat(id: 8, title: "Noor", kind: .direct, isHidden: true,
                 messages: [
                    Message(text: "see you tomorrow", date: ago(minutes: 60 * 24 * 3), isOutgoing: false)
                 ])
        ]
    }
}
