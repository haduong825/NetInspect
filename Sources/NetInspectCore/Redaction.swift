import Foundation

enum Redactor {
    static func url(_ value: URL?, configuration: RedactionConfiguration) -> String? {
        guard let value else { return nil }
        guard !configuration.urlQueryNames.isEmpty,
              var components = URLComponents(url: value, resolvingAgainstBaseURL: false),
              let items = components.queryItems else { return value.absoluteString }
        components.queryItems = items.map { item in
            configuration.urlQueryNames.contains(item.name.lowercased())
                ? URLQueryItem(name: item.name, value: configuration.replacement)
                : item
        }
        return components.url?.absoluteString ?? value.absoluteString
    }

    static func headers(_ headers: [String: String], configuration: RedactionConfiguration) -> [String: String] {
        headers.reduce(into: [:]) { result, item in
            result[item.key] = configuration.headerNames.contains(item.key.lowercased())
                ? configuration.replacement
                : item.value
        }
    }

    static func body(_ body: CapturedBody?, configuration: RedactionConfiguration) -> CapturedBody? {
        guard let body, !configuration.jsonKeys.isEmpty, body.encoding == .utf8,
              let data = body.value.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else { return body }
        let redacted = redactJSON(object, configuration: configuration)
        guard let output = try? JSONSerialization.data(withJSONObject: redacted, options: [.sortedKeys]),
              let string = String(data: output, encoding: .utf8) else { return body }
        return CapturedBody(value: string, encoding: .utf8, isTruncated: body.isTruncated)
    }

    private static func redactJSON(_ value: Any, configuration: RedactionConfiguration) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, item in
                result[item.key] = configuration.jsonKeys.contains(item.key.lowercased())
                    ? configuration.replacement
                    : redactJSON(item.value, configuration: configuration)
            }
        }
        if let array = value as? [Any] {
            return array.map { redactJSON($0, configuration: configuration) }
        }
        return value
    }
}
