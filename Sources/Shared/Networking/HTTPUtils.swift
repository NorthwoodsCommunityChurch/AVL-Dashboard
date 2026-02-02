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

    /// Build a minimal HTTP 404 response.
    public static func notFoundResponse() -> Data {
        let response = "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        return Data(response.utf8)
    }
}
