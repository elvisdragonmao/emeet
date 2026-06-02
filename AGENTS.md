我這學期要做一個畢業專題，是要做出一個會議輔助工具。預計以 macOS App 的方式做到。

功能包括：
* 生成即時的逐字稿
* 即時對話輔助： 在通話或線上會議中，AI 會即時聆聽對話內容。分析對方提出的問題，並自動生成自然的回應建議或話術。
* 會議筆記與下一步行動：除了應答之外，它也能在通話中同步記錄重點，並歸納出後續的執行步驟。
* 有即時的對話框可以問 AI
*可以點擊按鈕：What should I say?, Follow-up questions
* 模型要能夠自己選擇，可以串自己的 API 如 GitHub Copilot, Codex。


## Commit And PR Guidance

Use Linux kernel/Git-style commit subjects with an area, subsystem, or component prefix:

```text
area: concise patch summary
sub/sys: concise patch summary
```

The prefix should name the repository area changed, such as a directory, package, file, subsystem, or component. The summary after the colon should briefly describe what the patch does, because it becomes the first line shown in the git changelog. Keep it short, imperative, and specific. Use lowercase for the first word after the colon unless it is a proper noun, and do not end the subject with a period.

Examples:

```text
docs: clarify Storybook build ownership
web/routes: split route-level chunks
ui/field: fix select menu positioning
server/auth: validate session cookie
githooks.txt: improve the intro section
```

PRs should describe the changed area, list validation commands run, link related issues, and include screenshots for visible web UI changes.


