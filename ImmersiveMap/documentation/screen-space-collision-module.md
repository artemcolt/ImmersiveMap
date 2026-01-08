# Screen-Space Collision Module

This module provides reusable GPU collision detection for screen-space UI elements.
It is independent of label-specific animation logic and can be reused by other UI layers.

## What it does
- Accepts a list of screen-space positions and collision shapes (rect or circle).
- Resolves collisions in input order (earlier items win).
- Outputs a visibility bit per element (1 = visible, 0 = hidden by collision).
- Runs in O(N^2) for now; designed so the input/output contract can stay stable if optimized later.

## What it does NOT do
- No clipping: elements clipped behind the camera or off-screen must be handled elsewhere.
- No animations or state: visibility is a raw collision result only.

## Data flow (GPU)
1) Produce screen-space points (pixel coordinates) into `ScreenPointOutput`.
2) Produce collision inputs (`ScreenCollisionInput`) per element.
3) Run `screenCollisionKernel` to compute visibility.
4) Optional: run any module-specific logic that consumes visibility (e.g., label fade).

## Shader contracts
Shared structs:
- `ImmersiveMapFramework/Shaders/Screen/ScreenCommon.h`
  - `ScreenPointOutput { position, depth, visible }`
- `ImmersiveMapFramework/Shaders/Screen/ScreenCollisionCommon.h`
  - `ScreenCollisionInput { halfSize, radius, shapeType }`
  - `ScreenCollisionParams { count }`

Kernel:
- `ImmersiveMapFramework/Shaders/Screen/ScreenCollision.metal`
  - `screenCollisionKernel(points, visibility, inputs, params)`

### Buffer layout (screenCollisionKernel)
- buffer(0): `ScreenPointOutput* points`
- buffer(1): `uint* visibility`
- buffer(2): `ScreenCollisionInput* inputs`
- buffer(3): `ScreenCollisionParams params`

### Shape types
- `ScreenCollisionShapeRect` (0): uses `halfSize` in pixels.
- `ScreenCollisionShapeCircle` (1): uses `radius` in pixels.
- For rect/circle overlap, rect is treated as an axis-aligned bounding box.

## Swift APIs
Types:
- `ImmersiveMapFramework/Map/ScreenCollisionTypes.swift`
  - `ScreenCollisionShapeType`
  - `ScreenCollisionInput`

Pipeline and calculator:
- `ImmersiveMapFramework/Map/ScreenCollisionPipeline.swift`
- `ImmersiveMapFramework/Map/ScreenCollisionCalculator.swift`

### Swift usage (minimal)
```swift
let pipeline = ScreenCollisionPipeline(metalDevice: device, library: library)
let calculator = ScreenCollisionCalculator(pipeline: pipeline, metalDevice: device)

// Prepare MTLBuffers:
// - screenPointsBuffer: [ScreenPointOutput]
// - collisionInputsBuffer: [ScreenCollisionInput]
// - visibilityBuffer: handled by calculator.outputBuffer

calculator.ensureOutputCapacity(count: count)
calculator.run(commandBuffer: commandBuffer,
               inputsCount: count,
               screenPointsBuffer: screenPointsBuffer,
               inputsBuffer: collisionInputsBuffer)

// Read visibility from calculator.outputBuffer (shared storage).
```

## Label integration (existing)
Labels currently use the module via:
- `ImmersiveMapFramework/Map/LabelScreenBuffers.swift` (builds collision inputs from label size)
- `ImmersiveMapFramework/Map/LabelScreenCompute.swift` (runs collision + label state update)
- `ImmersiveMapFramework/Shaders/Label/LabelStateUpdate.metal` (label-specific fade/duplicate)

## Guidelines for new UI elements
- Use pixel-space screen positions in `ScreenPointOutput.position`.
- Pick shape type:
  - Rect: set `halfSize`, `radius = 0`, `shapeType = .rect`.
  - Circle: set `radius`, `halfSize = 0`, `shapeType = .circle`.
- Input order is priority: earlier items remain visible when collisions occur.
- If you need priority sorting, do it before filling the buffers.

## Common pitfalls
- Forgetting to set `ScreenPointOutput.visible` to 0 for off-screen elements will cause
  them to participate in collisions. Handle clipping upstream.
- Mixing NDC and pixel coordinates: the collision kernel assumes pixels.
- Not resizing output buffer: call `ensureOutputCapacity` when the count changes.

## Files to look at
- `ImmersiveMapFramework/Shaders/Screen/ScreenCollision.metal`
- `ImmersiveMapFramework/Shaders/Screen/ScreenCollisionCommon.h`
- `ImmersiveMapFramework/Map/ScreenCollisionCalculator.swift`
- `ImmersiveMapFramework/Map/ScreenCollisionPipeline.swift`
- `ImmersiveMapFramework/Map/ScreenCollisionTypes.swift`
