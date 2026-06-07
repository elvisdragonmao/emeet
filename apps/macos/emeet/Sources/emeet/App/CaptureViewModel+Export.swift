import AppKit
import Foundation
import UniformTypeIdentifiers

@MainActor
extension CaptureViewModel {
    func exportMeetingRecords() {
        let panel = NSSavePanel()
        panel.title = "匯出會議紀錄"
        panel.nameFieldStringValue = "會議紀錄-\(fileTimestamp()).md"
        panel.allowedContentTypes = [UTType(filenameExtension: "md") ?? .plainText]
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return
        }

        do {
            try exportMarkdown().write(to: url, atomically: true, encoding: .utf8)
            appendLog("會議紀錄已匯出：\(url.lastPathComponent)")
        } catch {
            appendLog("匯出失敗：\(error.localizedDescription)")
        }
    }

    func exportMarkdown() -> String {
        var lines: [String] = []
        lines.append("# 會議紀錄")
        lines.append("")
        lines.append("- 匯出時間：\(displayTimestamp())")
        lines.append("- STT 端點：\(transcriptionEndpointLabel)")
        lines.append("- AI 供應商：\(assistantProviderID)")
        lines.append("- AI 模型：\(assistantModel)")
        lines.append("")
        lines.append("## 會議紀錄")
        lines.append("")
        if noteDrafts.isEmpty {
            lines.append("_尚無會議紀錄。_")
        } else {
            for note in noteDrafts {
                lines.append("### \(note.title)")
                lines.append(note.detail)
                lines.append("")
            }
        }

        lines.append("## 下一步行動")
        lines.append("")
        if actionDrafts.isEmpty {
            lines.append("_尚無下一步行動。_")
        } else {
            for action in actionDrafts {
                lines.append("- [ ] \(action.title)  ")
                lines.append("  負責人：\(documentContextActionOwner(action.owner))  ")
                lines.append("  狀態：\(documentContextActionState(action.state))")
            }
        }

        lines.append("")
        lines.append("## AI 建議")
        lines.append("")
        if assistantDrafts.isEmpty {
            lines.append("_尚無 AI 建議。_")
        } else {
            for draft in assistantDrafts {
                lines.append("### \(draft.title)")
                lines.append("- 標籤：\(draft.badge)")
                lines.append("- 建議：\(draft.detail)")
                lines.append("")
            }
        }

        lines.append("## 逐字稿")
        lines.append("")
        let exportTranscript = finalTranscriptArchive.isEmpty ? transcriptLines : finalTranscriptArchive
        if exportTranscript.isEmpty {
            lines.append("_尚無逐字稿。_")
        } else {
            for line in exportTranscript {
                let status = line.isFinal ? "完成" : "即時"
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
