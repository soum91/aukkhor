import Foundation

struct EmojiEntry {
    let glyph: String
    let name: String
    let group: String
}

enum EmojiCatalog {
    static let groups = ["Faces", "People", "Animals", "Food", "Travel", "Symbols"]
    static let entries: [EmojiEntry] = [
        .init(glyph: "😀", name: "grinning happy smile", group: "Faces"),
        .init(glyph: "😂", name: "laugh tears joy", group: "Faces"),
        .init(glyph: "🥹", name: "teary touched emotional", group: "Faces"),
        .init(glyph: "😍", name: "heart eyes love", group: "Faces"),
        .init(glyph: "🥰", name: "love hearts", group: "Faces"),
        .init(glyph: "😭", name: "cry sob", group: "Faces"),
        .init(glyph: "😎", name: "cool sunglasses", group: "Faces"),
        .init(glyph: "🤔", name: "think thinking", group: "Faces"),
        .init(glyph: "😴", name: "sleep tired", group: "Faces"),
        .init(glyph: "😡", name: "angry mad", group: "Faces"),
        .init(glyph: "🥳", name: "party celebrate", group: "Faces"),
        .init(glyph: "😅", name: "sweat nervous smile", group: "Faces"),
        .init(glyph: "👍", name: "thumbs up yes", group: "People"),
        .init(glyph: "👎", name: "thumbs down no", group: "People"),
        .init(glyph: "👏", name: "clap applause", group: "People"),
        .init(glyph: "🙏", name: "thanks pray please", group: "People"),
        .init(glyph: "🤝", name: "handshake agreement", group: "People"),
        .init(glyph: "🫂", name: "hug", group: "People"),
        .init(glyph: "👋", name: "wave hello goodbye", group: "People"),
        .init(glyph: "💪", name: "strong muscle", group: "People"),
        .init(glyph: "🫶", name: "heart hands love", group: "People"),
        .init(glyph: "🐱", name: "cat", group: "Animals"),
        .init(glyph: "🐶", name: "dog puppy", group: "Animals"),
        .init(glyph: "🐦", name: "bird", group: "Animals"),
        .init(glyph: "🦋", name: "butterfly", group: "Animals"),
        .init(glyph: "🐼", name: "panda", group: "Animals"),
        .init(glyph: "🦁", name: "lion", group: "Animals"),
        .init(glyph: "🍕", name: "pizza", group: "Food"),
        .init(glyph: "🍔", name: "burger", group: "Food"),
        .init(glyph: "☕", name: "coffee tea", group: "Food"),
        .init(glyph: "🍎", name: "apple fruit", group: "Food"),
        .init(glyph: "🎂", name: "cake birthday", group: "Food"),
        .init(glyph: "🍚", name: "rice", group: "Food"),
        .init(glyph: "🚗", name: "car", group: "Travel"),
        .init(glyph: "✈️", name: "plane flight", group: "Travel"),
        .init(glyph: "🚀", name: "rocket", group: "Travel"),
        .init(glyph: "🏠", name: "house home", group: "Travel"),
        .init(glyph: "🌎", name: "earth world", group: "Travel"),
        .init(glyph: "📱", name: "phone", group: "Travel"),
        .init(glyph: "❤️", name: "red heart love", group: "Symbols"),
        .init(glyph: "💙", name: "blue heart love", group: "Symbols"),
        .init(glyph: "🔥", name: "fire", group: "Symbols"),
        .init(glyph: "✨", name: "sparkles", group: "Symbols"),
        .init(glyph: "✅", name: "check yes done", group: "Symbols"),
        .init(glyph: "❌", name: "cross no error", group: "Symbols"),
        .init(glyph: "🇧🇩", name: "bangladesh flag", group: "Symbols"),
        .init(glyph: "🇨🇦", name: "canada flag", group: "Symbols")
    ]

    static func search(_ query: String, group: String) -> [EmojiEntry] {
        if query.isEmpty { return entries.filter { $0.group == group } }
        return entries.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }
}

