import Foundation

struct SubtitleCue {
    let start: TimeInterval
    let end: TimeInterval
    let text: String
}

// swiftlint:disable file_length
enum VTTParser {
    static func parse(_ content: String) -> [SubtitleCue] {
        if content.hasPrefix("<?xml") || content.hasPrefix("<timedtext") {
            return parseXML(content)
        }
        return parseVTT(content)
    }

    // MARK: - XML (YouTube timedtext format 3)

    static func parseXML(_ content: String) -> [SubtitleCue] {
        let parser = XMLSubtitleParser(xml: content)
        return parser.parse()
    }

    // MARK: - WebVTT

    static func parseVTT(_ content: String) -> [SubtitleCue] {
        var raw: [SubtitleCue] = []
        let lines = content.components(separatedBy: .newlines)
        var idx = 0
        while idx < lines.count {
            let line = lines[idx].trimmingCharacters(in: .whitespaces)
            if line.contains("-->") {
                let newCues = parseCueBlock(
                    timeLine: line, lines: lines, after: idx + 1
                )
                for cue in newCues where raw.last?.text != cue.text {
                    raw.append(cue)
                }
            }
            idx += 1
        }
        return fillGaps(raw)
    }

    // MARK: - Cue block parsing

    private static func parseCueBlock(
        timeLine: String,
        lines: [String],
        after start: Int
    ) -> [SubtitleCue] {
        guard let (startT, endT) = parseTimes(from: timeLine) else {
            return []
        }
        var bodyLines: [String] = []
        var idx = start
        while idx < lines.count {
            let ln = lines[idx].trimmingCharacters(in: .whitespaces)
            if ln.isEmpty { break }
            bodyLines.append(ln)
            idx += 1
        }
        return expandCueBody(lines: bodyLines, start: startT, end: endT)
    }

    private static func expandCueBody(
        lines: [String],
        start: TimeInterval,
        end: TimeInterval
    ) -> [SubtitleCue] {
        let timingPattern = #"<\d{2}:\d{2}:\d{2}\.\d+>"#
        var staticLines: [String] = []
        var buildingLine: String?
        for ln in lines {
            if ln.range(of: timingPattern, options: .regularExpression) != nil {
                buildingLine = ln
            } else {
                let clean = stripVTTTags(ln)
                    .trimmingCharacters(in: .whitespaces)
                    .decodingHTMLEntities()
                if !clean.isEmpty { staticLines.append(clean) }
            }
        }
        guard let building = buildingLine else {
            let text = staticLines.joined(separator: "\n")
            guard !text.isEmpty else {
                return []
            }
            return [SubtitleCue(start: start, end: end, text: text)]
        }
        return buildInlineCues(
            prefix: staticLines,
            building: building,
            cueStart: start,
            cueEnd: end
        )
    }

    // swiftlint:disable:next function_body_length
    private static func buildInlineCues(
        prefix: [String],
        building: String,
        cueStart: TimeInterval,
        cueEnd: TimeInterval
    ) -> [SubtitleCue] {
        let (timings, segments) = tokenizeInlineTiming(building)
        guard !timings.isEmpty else {
            let all = (prefix + [stripVTTTags(building)])
                .joined(separator: "\n")
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .decodingHTMLEntities()
            guard !all.isEmpty else {
                return []
            }
            return [SubtitleCue(start: cueStart, end: cueEnd, text: all)]
        }
        let prefixStr = prefix.isEmpty ? "" : prefix.joined(separator: "\n") + "\n"
        var cues: [SubtitleCue] = []
        var accumulated = segments[0]
        for ii in 0..<timings.count {
            let segStart = ii == 0 ? cueStart : timings[ii - 1]
            let segEnd = timings[ii]
            let display = (prefixStr + accumulated)
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .decodingHTMLEntities()
            if !display.isEmpty, cues.last?.text != display {
                cues.append(SubtitleCue(start: segStart, end: segEnd, text: display))
            }
            accumulated += segments[ii + 1]
        }
        let lastStart = timings.last ?? cueStart
        let finalDisplay = (prefixStr + accumulated)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .decodingHTMLEntities()
        if !finalDisplay.isEmpty {
            cues.append(SubtitleCue(start: lastStart, end: cueEnd, text: finalDisplay))
        }
        return cues
    }

    private static func tokenizeInlineTiming(
        _ line: String
    ) -> (timings: [TimeInterval], segments: [String]) {
        let pattern = #"<(\d{2}:\d{2}:\d{2}\.\d+)>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else {
            return ([], [])
        }
        let matches = regex.matches(
            in: line,
            range: NSRange(line.startIndex..., in: line)
        )
        var timings: [TimeInterval] = []
        var segments: [String] = []
        var lastEnd = line.startIndex
        for match in matches {
            guard let matchRange = Range(match.range, in: line),
                  let captureRange = Range(match.range(at: 1), in: line),
                  let time = parseTime(String(line[captureRange]))
            else { continue }
            segments.append(stripVTTTags(String(line[lastEnd..<matchRange.lowerBound])))
            timings.append(time)
            lastEnd = matchRange.upperBound
        }
        segments.append(stripVTTTags(String(line[lastEnd...])))
        return (timings, segments)
    }

    // MARK: - Shared helpers

    private static func fillGaps(_ cues: [SubtitleCue]) -> [SubtitleCue] {
        guard cues.count > 1 else {
            return cues
        }
        var result: [SubtitleCue] = []
        for (pos, cue) in cues.enumerated() {
            let nextStart = pos + 1 < cues.count ? cues[pos + 1].start : cue.end
            result.append(SubtitleCue(
                start: cue.start,
                end: max(cue.end, nextStart),
                text: cue.text
            ))
        }
        return result
    }

    private static func parseTimes(
        from timeLine: String
    ) -> (TimeInterval, TimeInterval)? {
        let parts = timeLine.components(separatedBy: "-->")
        guard parts.count >= 2,
              let startT = parseTime(
                  parts[0].trimmingCharacters(in: .whitespaces)
              ),
              let endT = parseTime(
                  parts[1].trimmingCharacters(in: .whitespaces)
                      .components(separatedBy: " ").first ?? ""
              )
        else { return nil }
        return (startT, endT)
    }

    static func parseTime(_ str: String) -> TimeInterval? {
        let parts = str.components(separatedBy: ":")
        if parts.count == 3 {
            guard let hh = Double(parts[0]),
                  let mm = Double(parts[1]),
                  let ss = Double(parts[2].replacingOccurrences(of: ",", with: "."))
            else { return nil }
            return hh * 3_600 + mm * 60 + ss
        } else if parts.count == 2 {
            guard let mm = Double(parts[0]),
                  let ss = Double(parts[1].replacingOccurrences(of: ",", with: "."))
            else { return nil }
            return mm * 60 + ss
        }
        return nil
    }

    private static func stripVTTTags(_ str: String) -> String {
        var result = str
        while let open = result.range(of: "<"),
              let close = result.range(
                  of: ">", range: open.upperBound..<result.endIndex
              ) {
            result.removeSubrange(open.lowerBound..<close.upperBound)
        }
        return result
    }
}

// MARK: - YouTube XML timedtext format 3 parser

private final class XMLSubtitleParser: NSObject, XMLParserDelegate {
    private let xml: String
    private var cues: [SubtitleCue] = []
    private var currentStart: TimeInterval = 0
    private var currentEnd: TimeInterval = 0
    private var currentText = ""
    private var inParagraph = false

    init(xml: String) { self.xml = xml }

    func parse() -> [SubtitleCue] {
        guard let data = xml.data(using: .utf8) else {
            return []
        }
        let parser = XMLParser(data: data)
        parser.delegate = self
        parser.parse()
        return cues
    }

    func parser(
        _ parser: XMLParser,
        didStartElement element: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        guard element == "p" else {
            return
        }
        let tMs = Double(attributes["t"] ?? "") ?? 0
        let dMs = Double(attributes["d"] ?? "") ?? 0
        currentStart = tMs / 1_000
        currentEnd = (tMs + dMs) / 1_000
        currentText = ""
        inParagraph = true
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inParagraph else {
            return
        }
        currentText += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement element: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        guard element == "p", inParagraph else {
            return
        }
        inParagraph = false
        let decoded = currentText
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .decodingHTMLEntities()
        guard !decoded.isEmpty else {
            return
        }
        if cues.last?.text != decoded {
            cues.append(SubtitleCue(
                start: currentStart, end: currentEnd, text: decoded
            ))
        }
    }
}

// MARK: - HTML entity decoding

private extension String {
    func decodingHTMLEntities() -> String {
        var result = self
        let entities: [(String, String)] = [
            ("&amp;", "&"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&nbsp;", " ")
        ]
        for (entity, char) in entities {
            result = result.replacingOccurrences(of: entity, with: char)
        }
        while let range = result.range(of: #"&#(\d+);"#, options: .regularExpression) {
            let digits = String(result[range]).dropFirst(2).dropLast()
            if let code = UInt32(digits), let scalar = Unicode.Scalar(code) {
                result.replaceSubrange(range, with: String(Character(scalar)))
            } else { break }
        }
        return result
    }
}
