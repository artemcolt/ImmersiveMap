//
//  LabelRuntimeMeta.h
//  ImmersiveMapFramework
//

#include <metal_stdlib>
using namespace metal;

#ifndef LABEL_RUNTIME_META
#define LABEL_RUNTIME_META

struct LabelRuntimeMeta {
    uchar duplicate;
    uchar isRetained;
    ushort _padding;
    uint visibleTileIndex;
    float fadeAlpha;
    float _padding1;
    float2 labelSizePx;
};

#endif
