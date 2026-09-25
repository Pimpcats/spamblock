import Foundation

/// Numbers reported to the FTC as spam, from the list the spamblock-data
/// repository publishes each day.
///
/// A different kind of list from the area codes. Those are ranges SpamBlock
/// expands itself; this is a set of individual numbers, compiled elsewhere
/// from Do Not Call complaints and downloaded. The "SpamBlock — Known spam"
/// extension fetches it itself — the app can't hand data to an extension
/// without an App Group, which a free Apple ID can't provision — and keeps
/// the last good copy for loading offline.
enum KnownSpamList {

    /// One 10-digit number per line, ascending. Rebuilt from FTC complaint
    /// data by the workflow in github.com/Pimpcats/spamblock-data, whose
    /// README documents the format.
    static let listURL = URL(string: "https://raw.githubusercontent.com/Pimpcats/spamblock-data/data/spam-numbers.txt")!

    /// How many numbers the list holds and how it was built. Small, so the
    /// app can describe the list without downloading it.
    static let infoURL = URL(string: "https://raw.githubusercontent.com/Pimpcats/spamblock-data/data/spam-numbers.json")!

    /// A longer list is treated as broken rather than loaded. The FTC data
    /// yields tens of thousands of numbers; this leaves room for growth while
    /// keeping the extension's memory use — the download plus the parsed
    /// numbers — to about ten megabytes at worst.
    static let maximumEntries = 500_000

    /// Info.plist key and value that mark the known-spam extension, so the
    /// app can tell it apart from the parts of the area-code list.
    static let roleKey = "SpamBlockRole"
    static let role = "known-spam"

    static func isKnownSpamExtension(infoDictionary: [String: Any]?) -> Bool {
        infoDictionary?[roleKey] as? String == role
    }

    // MARK: - Parsing

    enum ParseError: Error, Equatable {
        /// A line that isn't a dialable 10-digit North American number, by
        /// 1-based line number.
        case malformedLine(Int)
        case tooManyNumbers(limit: Int)
    }

    /// The numbers in a downloaded list, as CallKit numbers — country code
    /// included — ascending and without duplicates.
    ///
    /// Strict about content: one bad line rejects the whole file, since a list
    /// that is partly garbage is more likely cut off or corrupted than meant,
    /// and the saved copy is the better thing to load. Not trusting about
    /// order: the result is sorted here, because CallKit rejects an entire
    /// list over a single number out of place.
    static func parse(_ data: Data, limit: Int = maximumEntries) throws -> [Int64] {
        var numbers: [Int64] = []
        numbers.reserveCapacity(min(data.count / (NANP.nationalDigits + 1), limit))

        var value: Int64 = 0
        var digits = 0
        var line = 1

        func endLine() throws {
            defer {
                value = 0
                digits = 0
                line += 1
            }
            guard digits > 0 else { return }  // blank, e.g. after the final newline
            guard digits == NANP.nationalDigits else { throw ParseError.malformedLine(line) }

            let npa = Int(value / 10_000_000)
            let nxx = Int(value / 10_000 % 1_000)
            guard NANP.isPlausibleAreaCode(npa), NANP.isAssignableExchange(nxx) else {
                throw ParseError.malformedLine(line)
            }
            guard numbers.count < limit else { throw ParseError.tooManyNumbers(limit: limit) }
            numbers.append(NANP.countryCode * 10_000_000_000 + value)
        }

        for byte in data {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"):
                guard digits < NANP.nationalDigits else { throw ParseError.malformedLine(line) }
                value = value * 10 + Int64(byte - UInt8(ascii: "0"))
                digits += 1
            case UInt8(ascii: "\n"):
                try endLine()
            case UInt8(ascii: "\r"):
                continue
            default:
                throw ParseError.malformedLine(line)
            }
        }
        try endLine()  // a last line with no newline after it

        numbers.sort()
        guard !numbers.isEmpty else { return numbers }
        var kept = 1
        for index in 1..<numbers.count where numbers[index] != numbers[kept - 1] {
            numbers[kept] = numbers[index]
            kept += 1
        }
        numbers.removeLast(numbers.count - kept)
        return numbers
    }

    // MARK: - Blocking

    /// Calls `body` with each of `numbers` that isn't in `exempt`, in order,
    /// and returns how many were skipped. Both must be ascending — the same
    /// single forward walk `NumberPlan.forEachNumber` uses.
    @discardableResult
    static func forEachEntry(in numbers: [Int64], exempt: [Int64], _ body: (Int64) -> Void) -> Int {
        var exemptIndex = 0
        var skipped = 0
        for number in numbers {
            while exemptIndex < exempt.count && exempt[exemptIndex] < number {
                exemptIndex += 1
            }
            if exemptIndex < exempt.count && exempt[exemptIndex] == number {
                skipped += 1
                continue
            }
            body(number)
        }
        return skipped
    }

    // MARK: - Downloading

    /// The list as published. Bypasses the local HTTP cache: a stale copy
    /// from there would look like a successful download.
    static func download(session: URLSession) async throws -> Data {
        let request = URLRequest(url: listURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 30)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return data
    }

    enum Source: Equatable {
        case downloaded
        case saved
    }

    struct Loaded {
        let numbers: [Int64]
        let source: Source
        /// Why the download didn't work, when the saved copy was used instead.
        let downloadError: Error?
    }

    /// The list to block: freshly downloaded if possible, otherwise the last
    /// copy that downloaded and parsed cleanly. Throws only when there is
    /// neither — the first load, with no connection.
    static func load(download: () async throws -> Data, cache: Cache?) async throws -> Loaded {
        do {
            let data = try await download()
            let numbers = try parse(data)
            try? cache?.save(data)
            return Loaded(numbers: numbers, source: .downloaded, downloadError: nil)
        } catch {
            guard let saved = cache?.load(), let numbers = try? parse(saved) else {
                throw unavailable(because: error)
            }
            return Loaded(numbers: numbers, source: .saved, downloadError: error)
        }
    }

    static let errorDomain = "SpamBlock.KnownSpam"

    /// An error that reads sensibly if it reaches the app, which only sees
    /// what CallKit passes back from the extension.
    static func unavailable(because error: Error) -> NSError {
        NSError(domain: errorDomain, code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Couldn’t download the known-spam list, and there’s no saved copy yet. The first load needs an internet connection.",
            NSUnderlyingErrorKey: error as NSError,
        ])
    }

    /// The last list that downloaded and parsed cleanly, in the extension's
    /// own container. iOS reloads the extension when it chooses — after a
    /// restart, or when it's switched on — possibly with no connection.
    struct Cache {
        let fileURL: URL

        /// Application Support rather than Caches: iOS may empty Caches when
        /// storage runs low, and losing this copy means blocking nothing from
        /// the list until the next successful download.
        static var standard: Cache? {
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                .map { Cache(fileURL: $0.appendingPathComponent("KnownSpam/spam-numbers.txt")) }
        }

        func load() -> Data? {
            try? Data(contentsOf: fileURL)
        }

        func save(_ data: Data) throws {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        }
    }

    // MARK: - Describing the list

    /// What spam-numbers.json says about the published list.
    struct Info: Decodable, Equatable {
        let count: Int
        let minReports: Int
        let windowDays: Int
        let generatedAt: Date?

        enum CodingKeys: String, CodingKey {
            case count
            case minReports = "min_reports"
            case windowDays = "window_days"
            case generatedAt = "generated_at"
        }

        init(count: Int, minReports: Int, windowDays: Int, generatedAt: Date?) {
            self.count = count
            self.minReports = minReports
            self.windowDays = windowDays
            self.generatedAt = generatedAt
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            count = try container.decode(Int.self, forKey: .count)
            minReports = try container.decode(Int.self, forKey: .minReports)
            windowDays = try container.decode(Int.self, forKey: .windowDays)
            generatedAt = try container.decodeIfPresent(String.self, forKey: .generatedAt)
                .flatMap(Self.date(from:))
        }

        /// UTC, written with or without a trailing Z.
        static func date(from text: String) -> Date? {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
            return formatter.date(from: text.hasSuffix("Z") ? String(text.dropLast()) : text)
        }
    }

    static func fetchInfo(session: URLSession = .shared) async throws -> Info {
        let request = URLRequest(url: infoURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
        return try JSONDecoder().decode(Info.self, from: data)
    }
}
