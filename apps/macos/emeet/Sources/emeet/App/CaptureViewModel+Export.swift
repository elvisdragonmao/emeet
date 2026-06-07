import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension CaptureViewModel {
    func exportMeetingRecords() {
        let panel = NSSavePanel()
        panel.title = "Export Meeting Record"
        panel.nameFieldStringValue = "meeting-record-\(fileTimestamp()).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
            appendLog("Meeting record exported: \(url.lastPathComponent)")
        } catch {
            appendLog("Export failed: \(error.localizedDescription)")
        }
    }

    func exportMarkdown() -> String {
        var lines: [String] = []
        lines.append("# Meeting Record")
        lines.append("")
        lines.append("- Exported: \(displayTimestamp())")
        lines.append("- STT endpoint: \(transcriptionEndpointLabel)")
        lines.append("- Assistant provider: \(assistantProviderID)")
        lines.append("- Assistant model: \(assistantModel)")
        lines.append("")
        lines.append("## Meeting Notes")
        lines.append("")
        if noteDrafts.isEmpty {
            lines.append("_No meeting notes yet._")
        } else {
            for note in noteDrafts {
                lines.append("### \(note.title)")
                lines.append(note.detail)
                lines.append("")
            }
        }

        lines.append("## Next Actions")
        lines.append("")
        if actionDrafts.isEmpty {
            lines.append("_No next actions yet._")
        } else {
            for action in actionDrafts {
                lines.append("- [ ] \(action.title)  ")
                lines.append("  Owner: \(action.owner)  ")
                lines.append("  State: \(action.state)")
            }
        }

        lines.append("")
        lines.append("## AI Suggestions")
        lines.append("")
        if assistantDrafts.isEmpty {
            lines.append("_No assistant suggestions yet._")
        } else {
            for draft in assistantDrafts {
                lines.append("### \(draft.title)")
                lines.append("- Badge: \(draft.badge)")
                lines.append("- Suggestion: \(draft.detail)")
                lines.append("")
            }
        }

        lines.append("## Transcript")
        lines.append("")
        let exportTranscript = finalTranscriptArchive.isEmpty ? transcriptLines : finalTranscriptArchive
        if exportTranscript.isEmpty {
            lines.append("_No transcript yet._")
        } else {
            for line in exportTranscript {
                let status = line.isFinal ? "Final" : "Partial"
                lines.append("- `\(line.timeRangeLabel)` **\(line.sourceLabel)** (\(status), \(line.provider)): \(line.text)")
            }
        }

        lines.append("")
        return lines.joined(separator: "\n")
    }

    func shortTimeLabel() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: Date())
    }

    func displayTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: Date())
    }

    func fileTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter.string(from: Date())
    }

}
