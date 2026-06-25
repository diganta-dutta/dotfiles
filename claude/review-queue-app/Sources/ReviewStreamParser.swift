// ReviewStreamParser.swift
//
// Standalone (no UI) parser for the `claude -p --output-format stream-json`
// NDJSON event stream produced by `review-queue --run`. Turns each event into a
// render-ready item: streamed assistant text, a tool-call indicator, a tool
// result, or a terminal done/failed signal.
//
// Robustness: input is consumed as raw bytes. Lines are split on the newline
// byte (0x0A) and only *complete* lines are decoded, so a chunk that splits
// mid-line — or mid-UTF8-codepoint — is buffered safely until the rest arrives.
// Malformed complete lines are recorded and skipped, never fatal.
//
// This file is compiled into the Review Queue app (see make-review-queue-app.sh).
// It was validated during development against a real stream-json capture via a
// dedicated self-test (Test A: counts; Test B: 64-byte chunks == single-chunk;
// Test C: malformed + split-line reassembly). That test and its fixture were
// removed before commit because the capture contained proprietary PR content.

import Foundation

// MARK: - Render-ready output

public enum RenderItem: Equatable {
    case assistantText(String)                       // streamed assistant prose
    case toolCall(name: String, id: String, command: String?) // a tool invocation started
    case toolResult(id: String, isError: Bool)       // the matching tool result came back
    case finished(success: Bool, summary: String)    // terminal: review done or failed
}

// MARK: - Wire model (only the fields we render are decoded)

private struct StreamEnvelope: Decodable {
    let type: String
    let subtype: String?
    let message: Message?
    let isError: Bool?
    let result: String?

    enum CodingKeys: String, CodingKey {
        case type, subtype, message, result
        case isError = "is_error"
    }
}

private struct Message: Decodable {
    let role: String?
    let content: [ContentBlock]?
}

// Only the tool_use input fields worth surfacing live (e.g. the gh/git command).
private struct ToolInput: Decodable {
    let command: String?
    let description: String?
}

// Heterogeneous content blocks: text / thinking / tool_use / tool_result / other.
// Decoded leniently so an unknown or slightly-shaped block degrades to `.other`
// instead of throwing the whole line out.
private enum ContentBlock: Decodable {
    case text(String)
    case thinking
    case toolUse(id: String, name: String, command: String?)
    case toolResult(toolUseId: String, isError: Bool)
    case other(String)

    private enum CodingKeys: String, CodingKey {
        case type, text, id, name, input
        case toolUseId = "tool_use_id"
        case isError = "is_error"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let t = (try? c.decode(String.self, forKey: .type)) ?? "unknown"
        switch t {
        case "text":
            self = .text((try? c.decode(String.self, forKey: .text)) ?? "")
        case "thinking":
            self = .thinking
        case "tool_use":
            let input = try? c.decode(ToolInput.self, forKey: .input)
            self = .toolUse(
                id: (try? c.decode(String.self, forKey: .id)) ?? "",
                name: (try? c.decode(String.self, forKey: .name)) ?? "?",
                command: input?.command ?? input?.description)
        case "tool_result":
            // is_error can be false, true, or null in the stream → default false.
            self = .toolResult(
                toolUseId: (try? c.decode(String.self, forKey: .toolUseId)) ?? "",
                isError: (try? c.decode(Bool.self, forKey: .isError)) ?? false)
        default:
            self = .other(t)
        }
    }
}

// MARK: - Parser

public final class ReviewStreamParser {
    /// Complete lines that failed to decode. Empty on a healthy stream.
    public private(set) var malformedLines: [String] = []
    /// True once a terminal `result` event has been seen.
    public private(set) var finished = false

    private var buffer = Data()
    private let decoder = JSONDecoder()
    private static let newline: UInt8 = 0x0A

    public init() {}

    /// Feed an arbitrary byte chunk (may start/end mid-line). Returns the render
    /// items unlocked by any *complete* lines in `chunk` (plus what was buffered).
    public func consume(_ chunk: Data) -> [RenderItem] {
        buffer.append(chunk)
        var items: [RenderItem] = []
        while let r = buffer.range(of: Data([Self.newline])) {
            let lineData = buffer.subdata(in: buffer.startIndex..<r.lowerBound)
            buffer = buffer.subdata(in: r.upperBound..<buffer.endIndex)
            items.append(contentsOf: handle(lineData))
        }
        return items
    }

    /// Convenience for String chunks.
    public func consume(_ chunk: String) -> [RenderItem] { consume(Data(chunk.utf8)) }

    /// Call at EOF to flush a trailing line that had no terminating newline.
    public func flush() -> [RenderItem] {
        guard !buffer.isEmpty else { return [] }
        let lineData = buffer
        buffer = Data()
        return handle(lineData)
    }

    private func handle(_ lineData: Data) -> [RenderItem] {
        // Drop a trailing CR (CRLF streams) and skip blank lines.
        var data = lineData
        if data.last == 0x0D { data = data.dropLast() }
        if data.allSatisfy({ $0 == 0x20 || $0 == 0x09 }) { return [] }

        let env: StreamEnvelope
        do {
            env = try decoder.decode(StreamEnvelope.self, from: data)
        } catch {
            malformedLines.append(String(decoding: data, as: UTF8.self))
            return []
        }
        return render(env)
    }

    private func render(_ env: StreamEnvelope) -> [RenderItem] {
        switch env.type {
        case "assistant":
            return (env.message?.content ?? []).compactMap { block in
                switch block {
                case .text(let s):                  return s.isEmpty ? nil : .assistantText(s)
                case .toolUse(let id, let n, let cmd): return .toolCall(name: n, id: id, command: cmd)
                default:                            return nil   // thinking / other
                }
            }
        case "user":
            return (env.message?.content ?? []).compactMap { block in
                if case .toolResult(let id, let isErr) = block {
                    return .toolResult(id: id, isError: isErr)
                }
                return nil
            }
        case "result":
            finished = true
            return [.finished(success: !(env.isError ?? false), summary: env.result ?? "")]
        default:
            // system (init / thinking_tokens), rate_limit_event → no render item.
            return []
        }
    }
}
