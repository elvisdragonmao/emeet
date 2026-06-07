import SwiftUI

struct EventLogPanel: View {
    let events: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("事件紀錄")
                    .font(.headline)
                Spacer()
                Image(systemName: "list.bullet.rectangle")
                    .foregroundStyle(.secondary)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 9) {
                    ForEach(events, id: \.self) { event in
                        Text(event)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .panelStyle()
    }
}
