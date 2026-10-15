import Foundation

/// Files reports on spamblock-data, which puts them on the shared list.
///
/// Each report becomes an issue titled "Spam report:" and the number. The
/// repository's workflow runs on it and lists the numbers in the open issues
/// its owner filed; closing the issue takes the number off again. Issues
/// rather than a file: the token needs no access to the repository's
/// contents, and the reports can be read and closed on github.com too.
struct GitHubReports {

    static let repository = "Pimpcats/spamblock-data"
    /// Must match REPORT_TITLE in spamblock-data's ftc_spamlist.py.
    static let titlePrefix = "Spam report:"

    let token: String
    var session: URLSession = .shared

    enum Failure: LocalizedError, Equatable {
        case tokenRejected
        case noAccess
        case unexpected(status: Int)

        var errorDescription: String? {
            switch self {
            case .tokenRejected:
                return "GitHub didn’t accept the token. It may have expired: make a new one and paste it in. Your reports are kept until then."
            case .noAccess:
                return "The token can’t file issues on spamblock-data. Make one with access to that repository and Issues set to Read and write."
            case .unexpected(let status):
                return "GitHub answered with an error (\(status)). SpamBlock will try again later."
            }
        }
    }

    // MARK: - Requests

    static func fileRequest(for report: SpamReport, token: String) -> URLRequest {
        let date = report.reportedAt.formatted(date: .abbreviated, time: .shortened)
        let body: [String: String] = [
            "title": "\(titlePrefix) \(report.formatted)",
            "body": "Reported from SpamBlock on \(date), after a call from this number got through.\n\nClose this issue to take the number off the shared list.",
        ]
        return request("issues", method: "POST", body: body, token: token)
    }

    static func closeRequest(issue: Int, token: String) -> URLRequest {
        request("issues/\(issue)", method: "PATCH",
                body: ["state": "closed", "state_reason": "not_planned"], token: token)
    }

    /// Lists at most one issue: the cheapest call that needs the same access
    /// as filing, for checking a token when it's pasted in.
    static func checkRequest(token: String) -> URLRequest {
        request("issues?per_page=1", method: "GET", body: nil, token: token)
    }

    private static func request(_ path: String, method: String, body: [String: String]?, token: String) -> URLRequest {
        var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(repository)/\(path)")!,
                                 timeoutInterval: 30)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONEncoder().encode(body)
        }
        return request
    }

    /// Turns an HTTP status into the failure it means, or nil for success.
    static func failure(forStatus status: Int) -> Failure? {
        switch status {
        case 200..<300: return nil
        case 401: return .tokenRejected
        case 403, 404: return .noAccess
        default: return .unexpected(status: status)
        }
    }

    // MARK: - Calls

    /// Files `report` and returns the new issue's number.
    func file(_ report: SpamReport) async throws -> Int {
        let data = try await send(Self.fileRequest(for: report, token: token))
        struct Created: Decodable { let number: Int }
        return try JSONDecoder().decode(Created.self, from: data).number
    }

    func close(issue: Int) async throws {
        do {
            _ = try await send(Self.closeRequest(issue: issue, token: token))
        } catch let failure as Failure where failure == .unexpected(status: 410) {
            // Deleted on github.com, which takes the number off just the same.
        }
    }

    func check() async throws {
        _ = try await send(Self.checkRequest(token: token))
    }

    private func send(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if let failure = Self.failure(forStatus: status) {
            throw failure
        }
        return data
    }
}
