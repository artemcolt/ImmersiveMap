// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Foundation

class TileDownloader {
    enum DownloadFailure: Equatable {
        case missingAuthorizationToken
        case nonHTTPResponse
        case unauthorized
        case forbidden
        case notFound
        case gone
        case rateLimited(retryAfter: TimeInterval?)
        case server(statusCode: Int)
        case client(statusCode: Int)
        case emptyBody
        case network
    }

    enum DownloadResult: Equatable {
        case success(Data)
        case failure(DownloadFailure)
    }

    private let mapTileDownloader: GetMapTileDownloadUrl
    private let authorizationToken: String?
    private let authorizationMode: ImmersiveMapSettings.TileSettings.NetworkSettings.AuthorizationMode
    private let session: URLSession

    init(config: ImmersiveMapSettings) {
        let configuration = URLSessionConfiguration.default
        configuration.tlsMaximumSupportedProtocolVersion = .TLSv12
        let network = config.tiles.network
        authorizationToken = network.authorizationToken
        authorizationMode = network.authorizationMode
        self.mapTileDownloader = BackendTileURLProvider(
            baseURL: network.tileBaseURL,
            queryItemsProvider: Self.queryItemsProvider(token: network.authorizationToken,
                                                        mode: network.authorizationMode)
        )
        self.session = URLSession(configuration: configuration)
    }

    init(mapTileDownloader: GetMapTileDownloadUrl, session: URLSession, authorizationToken: String?) {
        self.mapTileDownloader = mapTileDownloader
        self.session = session
        self.authorizationToken = authorizationToken
        self.authorizationMode = .bearerHeader
    }

    private static func queryItemsProvider(token: String?,
                                           mode: ImmersiveMapSettings.TileSettings.NetworkSettings.AuthorizationMode) -> (() -> [URLQueryItem])? {
        guard let token else {
            return nil
        }

        switch mode {
        case .bearerHeader:
            return nil
        case let .accessTokenQuery(parameterName):
            return {
                [URLQueryItem(name: parameterName, value: token)]
            }
        }
    }
    
    func download(tile: Tile) async -> Data? {
        let result = await downloadResult(tile: tile)
        if case let .success(data) = result {
            return data
        }
        return nil
    }

    func downloadResult(tile: Tile) async -> DownloadResult {
        let zoom = tile.z
        let x = tile.x
        let y = tile.y
        
        let tileURL = mapTileDownloader.get(tileX: x, tileY: y, tileZ: zoom)
        var request = URLRequest(url: tileURL)
        if let authorizationToken, authorizationMode == .bearerHeader {
            request.setValue("Bearer \(authorizationToken)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                #if DEBUG
                print("Tile download returned non-HTTP response \(tile)")
                #endif
                return .failure(.nonHTTPResponse)
            }
            let statusCode = httpResponse.statusCode
            guard (200...299).contains(statusCode) else {
                #if DEBUG
                print("Tile download failed with status \(statusCode) \(tile)")
                #endif
                switch statusCode {
                case 401:
                    return .failure(.unauthorized)
                case 403:
                    return .failure(.forbidden)
                case 404:
                    return .failure(.notFound)
                case 410:
                    return .failure(.gone)
                case 429:
                    let retryAfterHeader = httpResponse.value(forHTTPHeaderField: "Retry-After")
                    let retryAfter = retryAfterHeader.flatMap(TimeInterval.init)
                    return .failure(.rateLimited(retryAfter: retryAfter))
                case 500...599:
                    return .failure(.server(statusCode: statusCode))
                default:
                    return .failure(.client(statusCode: statusCode))
                }
            }
            guard data.isEmpty == false else {
                #if DEBUG
                print("Tile download returned empty body \(tile)")
                #endif
                return .failure(.emptyBody)
            }

            return .success(data)
        } catch {
            #if DEBUG
            print("Downloading tile failed \(tile): \(error)")
            #endif
            return .failure(.network)
        }
    }
}
