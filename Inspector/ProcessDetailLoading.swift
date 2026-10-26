import Foundation

/// What a detail screen is opened with: the data it must draw on its first
/// frame, or the sentence explaining why there is none. A screen is never
/// pushed without one, so it can't come up blank and fill itself in a moment
/// later.
struct PreparedDetail {
    let snapshot: ProcessDetailSnapshot?
    let failure: String?

    /// Nothing has been read yet; the screen loads for itself.
    static let pending = PreparedDetail(snapshot: nil, failure: nil)

    var isPending: Bool { snapshot == nil && failure == nil }
}

extension ProcessListModel {
    /// Reads one screen's data before the screen exists, and turns a refusal
    /// into the sentence that screen would otherwise have shown a moment
    /// later.
    func prepare(_ kind: ProcessDetailKind, for identity: ProcessIdentity) async -> PreparedDetail {
        do {
            let result = try await details(kind, for: identity)
            switch result.status {
            case .available, .partial:
                return PreparedDetail(snapshot: result, failure: nil)
            case .processExited:
                return PreparedDetail(snapshot: nil, failure: String(localized: "This process has ended."))
            case .permissionDenied:
                return PreparedDetail(
                    snapshot: nil,
                    failure: String(
                        localized: "This app isn’t allowed to read that (error \(Int(result.errorCode)))."
                    )
                )
            case .unsupported:
                return PreparedDetail(
                    snapshot: nil,
                    failure: String(localized: "This isn’t available on this device.")
                )
            case .failed:
                return PreparedDetail(
                    snapshot: nil,
                    failure: String(
                        localized: "Couldn’t read this data (error \(Int(result.errorCode)))."
                    )
                )
            }
        } catch {
            return PreparedDetail(snapshot: nil, failure: InspectorErrorText.describe(error))
        }
    }
}
