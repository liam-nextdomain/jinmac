import Foundation

/// 포그라운드 앱으로 분류하는 워크로드 카테고리 (F-20).
///
/// 원시값은 `app-categories.json`과 리포트 JSON에 그대로 남는다. 바꾸면 사용자가 고친 매핑과
/// 이전 리포트 비교가 깨진다.
public enum WorkloadCategory: String, Sendable, Hashable, Codable, CaseIterable {
    /// 영상 편집
    case videoEditing = "video_editing"
    /// 사진·디자인
    case photoDesign = "photo_design"
    /// 개발(IDE·컴파일)
    case development
    /// 3D·렌더링
    case rendering3D = "rendering_3d"
    /// 음악 제작
    case musicProduction = "music_production"
    /// 가상머신·컨테이너
    case virtualization
    /// 브라우징·문서
    case browsingDocuments = "browsing_documents"
    /// 게임
    case gaming
    /// AI·머신러닝
    case machineLearning = "machine_learning"
    /// 기타
    case other
}

/// 번들 ID → 카테고리 매핑 (F-21). 앱에 JSON으로 번들하고, 사용자가 고친 값이 그 위에 덮인다.
public struct CategoryMap: Sendable, Equatable, Decodable {
    public let schemaVersion: Int
    public let apps: [String: WorkloadCategory]

    public init(schemaVersion: Int, apps: [String: WorkloadCategory]) {
        self.schemaVersion = schemaVersion
        self.apps = apps
    }

    /// 매핑에 없는 앱은 `other`다.
    public func category(for bundleID: String) -> WorkloadCategory {
        apps[bundleID] ?? .other
    }

    /// 앱에 번들된 기본 매핑.
    public static func bundled() throws -> CategoryMap {
        guard let url = Bundle.module.url(forResource: "app-categories", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(CategoryMap.self, from: Data(contentsOf: url))
    }
}
