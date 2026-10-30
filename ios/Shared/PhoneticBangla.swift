import Foundation

/// Small, independent transliterator. It intentionally does not claim Avro compatibility.
enum PhoneticBangla {
    private static let commonWords: [String: String] = [
        "ami": "আমি", "tumi": "তুমি", "bangla": "বাংলা", "bhalo": "ভালো",
        "shubho": "শুভ", "shokal": "সকাল", "dhonnobad": "ধন্যবাদ",
        "okkhor": "অক্ষর", "akkhor": "অক্ষর", "aukkhor": "অক্ষর", "akshor": "অক্ষর"
    ]
    private static let consonants: [(String, String)] = [
        ("kksh", "ক্ষ"), ("kkh", "ক্ষ"), ("ksh", "ক্ষ"),
        ("ng", "ং"), ("kh", "খ"), ("gh", "ঘ"), ("chh", "ছ"), ("ch", "চ"),
        ("jh", "ঝ"), ("th", "থ"), ("dh", "ধ"), ("ph", "ফ"), ("bh", "ভ"),
        ("sh", "শ"), ("ss", "ষ"), ("rr", "ড়"), ("ny", "ঞ"), ("tt", "ট"),
        ("dd", "ড"), ("k", "ক"), ("g", "গ"), ("c", "ক"), ("j", "জ"),
        ("t", "ত"), ("d", "দ"), ("n", "ন"), ("p", "প"), ("f", "ফ"),
        ("b", "ব"), ("m", "ম"), ("r", "র"), ("l", "ল"), ("s", "স"),
        ("h", "হ"), ("y", "য"), ("w", "ও"), ("v", "ভ"), ("z", "জ")
    ].sorted { $0.0.count > $1.0.count }

    private static let vowels: [(String, String, String)] = [
        ("aa", "আ", "া"), ("ee", "ঈ", "ী"), ("ii", "ঈ", "ী"),
        ("uu", "ঊ", "ূ"), ("oo", "উ", "ু"), ("oi", "ঐ", "ৈ"),
        ("ou", "ঔ", "ৌ"), ("a", "আ", "া"), ("i", "ই", "ি"),
        ("u", "উ", "ু"), ("e", "এ", "ে"), ("o", "অ", "ো")
    ].sorted { $0.0.count > $1.0.count }

    static func transliterate(_ raw: String) -> String {
        let input = raw.lowercased()
        if let common = commonWords[input] { return common }
        var result = ""
        var index = input.startIndex
        var previousConsonant = false
        while index < input.endIndex {
            let rest = input[index...]
            if let (latin, independent, dependent) = vowels.first(where: { rest.hasPrefix($0.0) }) {
                result += previousConsonant ? dependent : independent
                previousConsonant = false
                index = input.index(index, offsetBy: latin.count)
            } else if let (latin, bengali) = consonants.first(where: { rest.hasPrefix($0.0) }) {
                if previousConsonant && bengali != "ং" { result += "্" }
                result += bengali
                previousConsonant = bengali != "ং"
                index = input.index(index, offsetBy: latin.count)
            } else {
                result.append(input[index])
                previousConsonant = false
                index = input.index(after: index)
            }
        }
        return result
    }
}

