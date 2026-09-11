import Foundation

protocol AlertSource: Sendable {
    var id: String { get }
    var displayName: String { get }
    func validate() async throws -> String
    func fetchOpenProblems() async throws -> [AlertProblem]
}
