import Foundation

/// Shared HTTP utilities for the raw HTTP protocol used between agent and dashboard.
public enum HTTPUtils {
    /// Extract the body from a raw HTTP response (everything after \r\n\r\n).
    public static func extractBody(from data: Data) -> Data? {
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        guard let range = data.range(of: separator) else { return nil }
        return data.subdata(in: range.upperBound..<data.endIndex)
    }

    /// Build a minimal HTTP GET request string.
    public static func getRequest(path: String) -> Data {
        let request = "GET \(path) HTTP/1.1\r\nHost: local\r\nConnection: close\r\n\r\n"
        return Data(request.utf8)
    }

    /// Build a minimal HTTP 200 response with JSON body.
    public static func jsonResponse(body: Data) -> Data {
        let header = "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    /// Build a minimal HTTP POST request with binary body.
    public static func postRequest(path: String, body: Data, contentType: String = "application/octet-stream") -> Data {
        let header = "POST \(path) HTTP/1.1\r\nHost: local\r\nContent-Type: \(contentType)\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var request = Data(header.utf8)
        request.append(body)
        return request
    }

    /// Build a minimal HTTP 404 response.
    public static func notFoundResponse() -> Data {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        return Data(response.utf8)
    }

    /// Build a minimal HTTP error response with status code and message.
    public static func errorResponse(status: Int, message: String) -> Data {
        let body = Data(message.utf8)
        let header = "HTTP/1.1 \(status) Error\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    /// Build a minimal HTTP 200 OK response with text body.
    public static func okResponse(message: String = "OK") -> Data {
        let body = Data(message.utf8)
        let header = "HTTP/1.1 200 OK\r\nContent-Type: text/plain\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n"
        var response = Data(header.utf8)
        response.append(body)
        return response
    }

    /// Maximum allowed Content-Length value (100 MB). Requests claiming larger bodies are rejected.
    public static let maxContentLength = 100 * 1024 * 1024

    /// Parse Content-Length from raw HTTP request data.
    /// Returns nil for missing, negative, or excessively large (> 100 MB) values.
    public static func parseContentLength(from data: Data) -> Int? {
        // Only convert the header portion — the body may contain binary data that isn't valid UTF-8.
        let separator = Data([0x0D, 0x0A, 0x0D, 0x0A]) // \r\n\r\n
        let searchArea = data.prefix(4096)
        guard let sepRange = searchArea.range(of: separator) else { return nil }
        let headerData = data.prefix(upTo: sepRange.lowerBound)
        guard let str = String(data: headerData, encoding: .utf8) else { return nil }
        for line in str.split(separator: "\r\n") {
            if line.lowercased().hasPrefix("content-length:") {
                let value = line.dropFirst("content-length:".count).trimmingCharacters(in: .whitespaces)
                guard let length = Int(value) else { return nil }
                // Reject negative or excessively large values
                guard length >= 0, length <= maxContentLength else { return nil }
                return length
            }
        }
        return nil
    }

    /// Parse the HTTP method from raw request data.
    /// Only reads up to the first CRLF to avoid binary body data.
    public static func parseMethod(from data: Data) -> String? {
        guard let firstLine = extractFirstLine(from: data) else { return nil }
        return firstLine.split(separator: " ").first.map(String.init)
    }

    /// Parse the request path from raw request data.
    /// Only reads up to the first CRLF to avoid binary body data.
    public static func parsePath(from data: Data) -> String? {
        guard let firstLine = extractFirstLine(from: data) else { return nil }
        let parts = firstLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }
        return String(parts[1])
    }

    /// Extract just the first line (request line) from raw HTTP data, stopping at CRLF
    /// to avoid attempting UTF-8 conversion on binary body data.
    private static func extractFirstLine(from data: Data) -> String? {
        let crlf = Data([0x0D, 0x0A])
        let searchArea = data.prefix(256)
        let endIndex: Data.Index
        if let range = searchArea.range(of: crlf) {
            endIndex = range.lowerBound
        } else {
            endIndex = searchArea.endIndex
        }
        return String(data: data[data.startIndex..<endIndex], encoding: .utf8)
    }
}
