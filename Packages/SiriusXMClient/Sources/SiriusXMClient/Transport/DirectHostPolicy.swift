import Foundation

/// Validates the only native destinations that may carry an authorization value.
enum DirectHostPolicy {
    static func isContractRequest(_ request: URLRequest) -> Bool {
        guard let url = request.url,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              components.scheme?.lowercased() == "https",
              components.host?.lowercased() == SiriusXMRequestContract.host,
              components.port == nil,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              request.httpBody == nil,
              let operation = SiriusXMRequestContract.all.first(where: {
                  $0.isTransportMaterializable
                      && $0.pathTemplate == components.path
                      && $0.method == (request.httpMethod ?? "GET")
              })
        else {
            return false
        }

        return operation.accept == request.value(forHTTPHeaderField: "Accept")
    }

    static func isAuthorizedRequest(_ request: URLRequest) -> Bool {
        guard isContractRequest(request),
              let authorization = request.value(forHTTPHeaderField: "Authorization"),
              authorization.hasPrefix("Bearer "),
              authorization.count > "Bearer ".count
        else {
            return false
        }
        return true
    }
}
