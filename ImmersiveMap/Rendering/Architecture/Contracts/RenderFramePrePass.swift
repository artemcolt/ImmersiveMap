// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

import Metal

protocol RenderFramePrePass: AnyObject {
    var name: String { get }

    func prepare(frameContext: FrameContext,
                 attachments: FrameAttachmentStore,
                 resourceRegistry: RenderResourceRegistry)
    func encode(commandBuffer: MTLCommandBuffer,
                frameContext: FrameContext)
    func handleMemoryWarning()
    func evict()
}
