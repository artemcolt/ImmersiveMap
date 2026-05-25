//
//  TreeMeshResource.swift
//  ImmersiveMapFramework
//

import Foundation
import Metal
import simd

enum TreeMeshResourceError: Error {
    case missingResource(String)
    case invalidMesh(String)
}

struct TreeMeshSubmesh {
    let materialSlot: TreeMaterialSlot
    let vertexBuffer: MTLBuffer
    let indexBuffer: MTLBuffer
    let indexCount: Int
}

final class TreeMeshResource {
    static let baseName = "classic_lite_lowpoly"

    let submeshes: [TreeMeshSubmesh]

    init(device: MTLDevice,
         bundle: Bundle = .module) throws {
        guard let objURL = bundle.url(forResource: Self.baseName, withExtension: "obj") else {
            throw TreeMeshResourceError.missingResource("\(Self.baseName).obj")
        }
        let meshData = try Self.loadMeshData(from: objURL)
        self.submeshes = try meshData.map { entry in
            guard entry.indices.isEmpty == false else {
                throw TreeMeshResourceError.invalidMesh("Tree submesh has no indices.")
            }
            guard let vertexBuffer = device.makeBuffer(bytes: entry.vertices,
                                                       length: entry.vertices.count * MemoryLayout<TreePipeline.VertexIn>.stride),
                  let indexBuffer = device.makeBuffer(bytes: entry.indices,
                                                      length: entry.indices.count * MemoryLayout<UInt32>.stride) else {
                throw TreeMeshResourceError.invalidMesh("Failed to allocate tree mesh buffers.")
            }
            return TreeMeshSubmesh(materialSlot: entry.materialSlot,
                                   vertexBuffer: vertexBuffer,
                                   indexBuffer: indexBuffer,
                                   indexCount: entry.indices.count)
        }
    }

    private static func loadMeshData(from url: URL) throws -> [(materialSlot: TreeMaterialSlot, vertices: [TreePipeline.VertexIn], indices: [UInt32])] {
        let source = try String(contentsOf: url, encoding: .utf8)

        var positions: [SIMD3<Float>] = []
        var normals: [SIMD3<Float>] = []
        var groupedVertices: [TreeMaterialSlot: [TreePipeline.VertexIn]] = [:]
        var groupedIndices: [TreeMaterialSlot: [UInt32]] = [:]
        var currentMaterial: TreeMaterialSlot = .trunk

        for rawLine in source.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard line.isEmpty == false, line.hasPrefix("#") == false else {
                continue
            }

            if line.hasPrefix("v ") {
                let values = line.split(separator: " ").dropFirst().compactMap { Float($0) }
                guard values.count == 3 else {
                    continue
                }
                positions.append(SIMD3<Float>(values[0], values[1], values[2]))
                continue
            }

            if line.hasPrefix("vn ") {
                let values = line.split(separator: " ").dropFirst().compactMap { Float($0) }
                guard values.count == 3 else {
                    continue
                }
                normals.append(SIMD3<Float>(values[0], values[1], values[2]))
                continue
            }

            if line.hasPrefix("usemtl ") {
                let name = String(line.split(separator: " ", maxSplits: 1)[1])
                currentMaterial = name == "trunk_bark" ? .trunk : .crown
                continue
            }

            if line.hasPrefix("f ") == false {
                continue
            }

            let faceTokens = line.split(separator: " ").dropFirst()
            guard faceTokens.count >= 3 else {
                continue
            }

            let parsedFace = try faceTokens.map { token -> TreePipeline.VertexIn in
                let parts = token.split(separator: "/", omittingEmptySubsequences: false)
                guard let vertexIndexRaw = Int(parts[0]),
                      vertexIndexRaw > 0,
                      vertexIndexRaw <= positions.count else {
                    throw TreeMeshResourceError.invalidMesh("OBJ face references missing vertex index.")
                }
                let normalIndexRaw: Int
                if parts.count >= 3, let parsedNormal = Int(parts[2]), parsedNormal > 0, parsedNormal <= normals.count {
                    normalIndexRaw = parsedNormal
                } else {
                    normalIndexRaw = 0
                }

                let position = positions[vertexIndexRaw - 1]
                let normal = normalIndexRaw > 0 ? normals[normalIndexRaw - 1] : SIMD3<Float>(0, 1, 0)
                return TreePipeline.VertexIn(position: position, normal: normal)
            }

            var vertices = groupedVertices[currentMaterial, default: []]
            var indices = groupedIndices[currentMaterial, default: []]
            let baseVertex = UInt32(vertices.count)

            for triangleIndex in 1..<(parsedFace.count - 1) {
                vertices.append(parsedFace[0])
                vertices.append(parsedFace[triangleIndex])
                vertices.append(parsedFace[triangleIndex + 1])
                indices.append(baseVertex + UInt32((triangleIndex - 1) * 3 + 0))
                indices.append(baseVertex + UInt32((triangleIndex - 1) * 3 + 1))
                indices.append(baseVertex + UInt32((triangleIndex - 1) * 3 + 2))
            }

            groupedVertices[currentMaterial] = vertices
            groupedIndices[currentMaterial] = indices
        }

        let orderedSlots = TreeMaterialSlot.allCases.filter { groupedIndices[$0]?.isEmpty == false }
        guard orderedSlots.isEmpty == false else {
            throw TreeMeshResourceError.invalidMesh("Tree OBJ did not yield any renderable submeshes.")
        }

        return orderedSlots.map { slot in
            (materialSlot: slot,
             vertices: groupedVertices[slot] ?? [],
             indices: groupedIndices[slot] ?? [])
        }
    }
}
