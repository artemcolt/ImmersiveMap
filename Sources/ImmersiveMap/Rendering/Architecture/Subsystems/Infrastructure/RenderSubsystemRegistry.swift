//
//  RenderSubsystemRegistry.swift
//  ImmersiveMapFramework
//

import Metal

final class RenderSubsystemRegistry {
    private let subsystems: [any RenderSubsystem]

    init(subsystems: [any RenderSubsystem]) {
        self.subsystems = subsystems
    }

    var orderedSubsystemNames: [String] {
        subsystems.map(\.name)
    }

    func update(frameContext: FrameContext) {
        for subsystem in subsystems {
            subsystem.update(frameContext: frameContext)
        }
    }

    func prepareGPU(frameContext: FrameContext, resourceRegistry: RenderResourceRegistry) {
        for subsystem in subsystems {
            subsystem.prepareGPU(frameContext: frameContext, resourceRegistry: resourceRegistry)
        }
    }

    func encode(pass: RenderPass, encoder: MTLRenderCommandEncoder, frameContext: FrameContext) {
        for subsystem in subsystems {
            subsystem.encode(pass: pass, encoder: encoder, frameContext: frameContext)
        }
    }

    func handleMemoryWarning() {
        for subsystem in subsystems {
            subsystem.handleMemoryWarning()
        }
    }

    func evict() {
        for subsystem in subsystems {
            subsystem.evict()
        }
    }
}
