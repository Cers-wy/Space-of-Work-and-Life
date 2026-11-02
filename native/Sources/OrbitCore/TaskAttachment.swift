import Foundation

/// Bytes live inside the task payload, so snapshots, undo and sync stay self contained.
public struct TaskAttachment: Codable, Equatable, Identifiable {
    public static let maximumFileBytes = 10 * 1024 * 1024
    public static let maximumTaskBytes = 20 * 1024 * 1024
    public static let maximumCount = 20
    public let id: String
    public let name: String
    public let typeIdentifier: String
    public let data: Data

    public init(id: String = UUID().uuidString, name: String, typeIdentifier: String, data: Data) {
        self.id = id; self.name = name; self.typeIdentifier = typeIdentifier; self.data = data
    }

    public static func validate(_ attachments: [TaskAttachment]) throws {
        guard attachments.count <= maximumCount else { throw OrbitError.invalid("每项任务最多添加20个附件。") }
        guard Set(attachments.map(\.id)).count == attachments.count else { throw OrbitError.invalid("附件标识重复。") }
        var total = 0
        for attachment in attachments {
            guard !attachment.id.isEmpty, attachment.id.utf8.count <= 200,
                  !attachment.name.isEmpty, attachment.name.utf16.count <= 255,
                  !attachment.name.contains("/"), !attachment.name.contains("\\"),
                  attachment.name != ".", attachment.name != "..",
                  !attachment.name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
                  !attachment.typeIdentifier.isEmpty, attachment.typeIdentifier.utf8.count <= 200 else {
                throw OrbitError.invalid("附件名称或类型无效。")
            }
            guard attachment.data.count <= maximumFileBytes else { throw OrbitError.invalid("单个附件不能超过10 MB。") }
            total += attachment.data.count
        }
        guard total <= maximumTaskBytes else { throw OrbitError.invalid("每项任务的附件合计不能超过20 MB。") }
    }
}
