import Foundation

/// Converts Chinese text into tone-less Latin pinyin candidates plus their
/// initials, so the search field can match queries like "wx" against "微信"
/// without bundling a dictionary.
///
/// `CFStringTransform` picks a single (often context-free) reading for
/// polyphonic characters — "音乐" becomes "yinle" instead of "yinyue" — so a
/// small table of common alternate readings is applied and every combination
/// is produced as a search candidate.
enum Pinyin {
    /// Common polyphonic characters in app names, with alternate tone-less
    /// readings beyond what `CFStringTransform` produces.
    private static let polyphones: [Character: [String]] = [
        "乐": ["yue", "le"],
        "行": ["xing", "hang"],
        "长": ["chang", "zhang"],
        "重": ["zhong", "chong"],
        "会": ["hui", "kuai"],
        "调": ["tiao", "diao"],
        "觉": ["jue", "jiao"],
        "角": ["jiao", "jue"],
        "传": ["chuan", "zhuan"],
        "还": ["hai", "huan"],
        "藏": ["cang", "zang"],
        "便": ["bian", "pian"]
    ]

    /// Maximum number of candidates generated for a single name.
    private static let maxVariants = 256

    static func components(of text: String) -> [(full: String, initials: String)] {
        let runs = splitLetterRuns(text)
        // Per run: a list of candidate word sequences (each syllable stays a
        // separate word so initials are computed per character).
        var runOptions: [[[String]]] = []
        for run in runs {
            if run.allSatisfy(\.isASCII) {
                runOptions.append([[run.lowercased()]])
            } else {
                let readings = run.map { character -> [String] in
                    polyphones[character] ?? [pinyin(of: String(character))]
                }
                runOptions.append(cartesianProduct(readings))
            }
        }

        var variants: [(full: String, initials: String)] = []
        for combo in cartesianProduct(runOptions) {
            let words = combo.flatMap { $0 }
            let full = words.joined()
            let initials = words.compactMap(\.first).map(String.init).joined()
            let pair: (full: String, initials: String) = (full, initials)
            if !variants.contains(where: { $0.full == pair.full && $0.initials == pair.initials }) {
                variants.append(pair)
            }
            if variants.count >= maxVariants {
                break
            }
        }
        return variants
    }

    /// Tone-less pinyin for one character via Core Foundation.
    private static func pinyin(of character: String) -> String {
        let mutable = NSMutableString(string: character)
        CFStringTransform(mutable, nil, kCFStringTransformToLatin, false)
        CFStringTransform(mutable, nil, kCFStringTransformStripCombiningMarks, false)
        return (mutable as String)
            .lowercased()
            .filter(\.isLetter)
    }

    private static func splitLetterRuns(_ text: String) -> [String] {
        var runs: [String] = []
        var current = ""
        for character in text {
            if character.isLetter {
                current.append(character)
            } else if !current.isEmpty {
                runs.append(current)
                current = ""
            }
        }
        if !current.isEmpty {
            runs.append(current)
        }
        return runs
    }

    private static func cartesianProduct<T>(_ arrays: [[T]]) -> [[T]] {
        guard let first = arrays.first else { return [[]] }
        let rest = cartesianProduct(Array(arrays.dropFirst()))
        return first.flatMap { element in
            rest.map { [element] + $0 }
        }
    }
}
