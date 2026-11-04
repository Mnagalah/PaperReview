import SwiftUI

struct ModelDownloadView: View {
    let progress: ModelDownloadProgress
    let retry: () -> Void
    let retryDisabled: Bool
    @State private var showingFiles = false
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(progress.title).fontWeight(.medium)
                Spacer()
                Text("\(Int(progress.fraction * 100))%").monospacedDigit()
            }
            ProgressView(value: progress.fraction).tint(.primary.opacity(0.7))
                .accessibilityLabel("模型下载进度")
            HStack {
                Text("\(bytes(progress.received)) / \(bytes(progress.total))")
                Spacer()
                if progress.phase == .downloading {
                    Text("\(bytes(Int64(progress.bytesPerSecond)))/s")
                }
            }.monospacedDigit()
            if progress.phase != .complete {
                HStack {
                    Text("剩余 \(bytes(progress.remaining))")
                    Spacer()
                    Text(remainingTime)
                }.foregroundStyle(.secondary).monospacedDigit()
            }
            if progress.phase == .failed {
                Text(progress.failure).foregroundStyle(.red).textSelection(.enabled)
                    .lineLimit(3)
                Button("重试续传", action: retry).disabled(retryDisabled)
            }
            SettingsDisclosure(title: "下载详情", isExpanded: $showingFiles) {
                VStack(spacing: 12) {
                    ForEach(progress.items) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(item.file.title)
                                Spacer()
                                Text(item.status).foregroundStyle(item.stage == .failed ? .red : .secondary)
                                Text("\(Int(item.fraction * 100))%")
                                    .monospacedDigit().frame(width: 42, alignment: .trailing)
                            }
                            ProgressView(value: item.fraction).tint(.primary.opacity(0.55))
                        }
                    }
                }.padding(.top, 6)
            }
        }
        .font(.callout)
        .onChange(of: progress.phase) { _, phase in if phase == .failed { showingFiles = true } }
    }
    private func bytes(_ count: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .decimal; formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: count)
    }
    private var remainingTime: String {
        guard let seconds = progress.secondsRemaining else {
            return progress.phase == .failed ? "可继续下载" : "预计时间计算中"
        }
        if seconds < 60 { return "预计剩余 \(max(1, Int(ceil(seconds)))) 秒" }
        if seconds < 3600 { return "预计剩余 \(Int(ceil(seconds / 60))) 分钟" }
        return "预计剩余 \(Int(seconds / 3600)) 小时 \(Int(seconds.truncatingRemainder(dividingBy: 3600) / 60)) 分钟"
    }
}
