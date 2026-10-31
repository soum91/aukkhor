import Foundation

enum KeyboardSuggestions {
    private static let english: [String] = ("a about after again all also always am an and another any are as ask at " +
        "back be because been before best better between big book both but by can cannot car change check class close code " +
        "come computer could day did do does done down each email English even every example family far feel find first " +
        "for from get give go good great had has have he hello help her here hi home hope how I if in into is it " +
        "just keep keyboard know language last later learn let like link little long look love made make many may me " +
        "message more most much my name need never new next no not now of off on one only open or other our out " +
        "over people phone please problem project right run say see send she should show simple so some someone something " +
        "start still such sure take test text than thank thanks that the their them then there these they thing think " +
        "this those time to today tomorrow too try two type typing up update use used user very want was way we well " +
        "were what when where which while who why will windows with work working would write yes you your you're").split(separator: " ").map(String.init)

    private static let bangla = ("আমি আমার আমরা আপনি আপনার তুমি তোমার তুই সে তারা আছে আছি আছেন আজ আগামী আগামীকাল " +
        "অনেক আশা আবার আর আসি আসবে ইংরেজি একটা একটু এই এখানে এখন একদিন কেমন করে কেন কোথায় কী কিছু কিন্তু " +
        "কিছুই গিয়ে চাই চলো জানি ঠিক তোমাকে তোমাদের ধন্যবাদ না নেই নাম নিচে নতুন পরে পারি পড়া বাংলা " +
        "বাংলাদেশ ভালো বাড়ি বলতে বলো বলুন বন্ধু মনে মনে হয় মা মানুষ আমার মা মেসেজ সবাই শুধু সবসময় " +
        "সময় সকাল সন্ধ্যা সুন্দর হাই হ্যাঁ হবে হয়েছিল").split(separator: " ").map(String.init)

    private struct CompletionWord {
        let text: String
        let normalized: String
    }
    private static func index(_ words: [String]) -> [String: [CompletionWord]] {
        Dictionary(grouping: words.map { CompletionWord(text: $0, normalized: $0.lowercased()) },
                   by: { String($0.normalized.prefix(1)) })
    }
    private static let englishIndex = index(english)
    private static let banglaIndex = index(bangla)

    private static let corrections = [
        "teh": "the", "adn": "and", "recieve": "receive", "definately": "definitely",
        "thier": "their", "wierd": "weird", "becuase": "because", "langauge": "language",
        "keybaord": "keyboard", "wiht": "with", "dont": "don't", "doesnt": "doesn't"
    ]

    static func complete(_ prefix: String, banglaMode: Bool, replacements: [String: String] = [:]) -> [String] {
        let normalized = prefix.lowercased()
        guard !normalized.isEmpty else { return [] }
        var found: [String] = []
        if let replacement = replacements[normalized] { found.append(replacement) }
        if !banglaMode, let correction = corrections[normalized] { found.append(correction) }
        for word in (banglaMode ? banglaIndex : englishIndex)[String(normalized.prefix(1))] ?? []
            where word.normalized.hasPrefix(normalized) && word.normalized != normalized {
            if !found.contains(word.text) { found.append(word.text) }
            if found.count == 3 { break }
        }
        return Array(found.prefix(3))
    }

    static func correction(_ word: String, replacements: [String: String]) -> String? {
        let lowercase = word.lowercased()
        return replacements[lowercase] ?? corrections[lowercase]
    }

    /// Experimental, local sequence match. This is deliberately not described as Gboard-grade glide recognition.
    static func glideCandidate(for observedKeys: String) -> String? {
        let path = condensed(observedKeys.lowercased())
        guard path.count >= 3, let first = path.first, let last = path.last else { return nil }
        let choices = english.filter { $0.lowercased().first == first && $0.lowercased().last == last }
        guard let result = choices.map({ ($0, distance(path, condensed($0.lowercased()))) })
            .min(by: { $0.1 < $1.1 }), result.1 <= max(3, path.count / 2) else { return nil }
        return result.0
    }

    private static func condensed(_ text: String) -> String {
        var result = ""
        for char in text where char.isLetter {
            if result.last != char { result.append(char) }
        }
        return result
    }

    private static func distance(_ lhs: String, _ rhs: String) -> Int {
        let a = Array(lhs), b = Array(rhs)
        var previous = Array(0...b.count)
        for i in a.indices {
            var current = [i + 1] + Array(repeating: 0, count: b.count)
            for j in b.indices {
                let sub = previous[j] + (a[i] == b[j] ? 0 : 1)
                current[j + 1] = min(previous[j + 1] + 1, current[j] + 1, sub)
            }
            previous = current
        }
        return previous[b.count]
    }
}

