// Copyright (c) 2025-2026 Artem Bobkin.
// SPDX-License-Identifier: MIT

protocol AvatarRenderSource: AnyObject {
    var currentAvatarController: ImmersiveMapAvatarsController? { get }
}
