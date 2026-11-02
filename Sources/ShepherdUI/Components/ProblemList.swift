import SwiftUI

/// Problems, each behind an orange triangle, then quiet status lines: the panel's footer and the
/// palette's Status page.
struct ProblemList: View {
    let problems: [String]
    let lines: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            ForEach(problems, id: \.self) { problem in
                Label {
                    Text(problem).fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                .font(.system(size: 11))
            }
            ForEach(lines, id: \.self) { line in
                Text(line)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
        }
    }
}
