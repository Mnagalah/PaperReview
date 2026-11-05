import Foundation

public enum ModelError: LocalizedError, Sendable {
    case localOnly, invalidConfiguration, invalidResponse(String), http(Int), emptyOCR, truncated, unavailable(String)
    public var errorDescription: String? {
        switch self {
        case .localOnly: "服务地址必须是本机 http://127.0.0.1、localhost 或 [::1]，不含路径、账号或查询参数。"
        case .invalidConfiguration: "请检查 Jev 重试阈值和重试次数。"
        case .invalidResponse(let reason): "模型返回的数据无法使用：\(reason)"
        case .http(let status): "本机模型服务返回 HTTP \(status)。请查看模型运行日志后重试。"
        case .emptyOCR: "OCR 没有识别出文字。请检查照片是否清楚、作文区域是否完整。"
        case .truncated: "识别输出达到长度上限，已保留部分文字。请重试识别或分开导入页面。"
        case .unavailable(let name): "无法连接 \(name)。请先在“模型设置”中启动模型，再重试。"
        }
    }
}

public struct OCRResponse: Sendable {
    public let text: String
    public let truncated: Bool
    public init(text: String, truncated: Bool) {
        self.text = text; self.truncated = truncated
    }
}
