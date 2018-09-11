//
//  APIClient.swift
//  Endpoints
//
//  Created by martindaum on 06/26/2018.
//

import Alamofire
import RxSwift

public enum APIError: Error {
    case responseError
    case serverError(statusCode: HTTPStatusCode, message: String)
    case validationError(message: String, property: String?)
}

extension APIError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .responseError:
            return "response error"
        case .validationError(let message, let property):
            return "\(message) (\(property ?? ""))"
        case .serverError(let statusCode, let message):
            return "\(message) (\(statusCode))"
        }
    }
}

public final class APIClient {
    private let manager: Alamofire.SessionManager
    private let baseURL: URL
    private let queue = DispatchQueue(label: "com.martindaum.APIClient")
    private var headers: [String: String] = [:]
    private var logger: NetworkLogger?
    private var errorHandler: APIErrorHandler?
    
    public init(baseURL: URL, configuration: URLSessionConfiguration = URLSessionConfiguration.default, headers: [String: String] = [:], logger: NetworkLogger? = nil, errorHandler: APIErrorHandler? = nil) {
        self.baseURL = baseURL
        self.manager = Alamofire.SessionManager(configuration: configuration)
        self.headers = headers
        self.logger = logger
        self.errorHandler = errorHandler
    }
    
    public func setLogger(_ logger: NetworkLogger) {
        self.logger = logger
    }
    
    public func setHeader(_ value: String, for key: String) {
        headers[key] = value
    }
    
    public func removeHeader(for key: String) {
        headers.removeValue(forKey: key)
    }
    
    public func clearHeaders() {
        headers = [:]
    }
    
    public func request<Response>(_ endpoint: Endpoint<Response>) -> Single<Response> {
        return Single<Response>.create { observer in
            let request = self.manager.request(self.url(path: endpoint.path), method: endpoint.method.httpMethod, parameters: endpoint.parameters, encoding: endpoint.encoding.encoding, headers: self.headers)
            request
                .log(with: self.logger, parameters: endpoint.parameters)
                .customValidate(self.errorHandler)
                .responseData(queue: self.queue) { response in
                    self.logger?.logResponse(response)
                    let result = response.result.flatMap(endpoint.decode)
                    switch result {
                    case let .success(value):
                        observer(.success(value))
                    case let .failure(error):
                        observer(.error(error))
                    }
            }
            return Disposables.create {
                request.cancel()
            }
        }
    }
    
    private func url(path: String) -> URL {
        return baseURL.appendingPathComponent(path)
    }
}

extension DataRequest {
    public func log(with logger: NetworkLogger?, parameters: [String: Any]?) -> DataRequest {
        logger?.logRequest(self, parameters: parameters)
        return self
    }
}

extension DataRequest {
    public func customValidate(_ errorHandler: APIErrorHandler?) -> Self {
        guard let errorHandler = errorHandler, errorHandler.usesCustomValidation else {
            return validate()
        }
        
        return validate { _, response, data in
            let statusCode = response.httpStatusCode
            if let error = errorHandler.validate(statusCode: statusCode, json: data) {
                return .failure(error)
            }
            return .success
        }
    }
}
