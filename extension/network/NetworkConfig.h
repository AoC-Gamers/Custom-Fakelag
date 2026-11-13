#pragma once

enum class CFakeLagPacketLossMode : int {
    BernoulliUniform = 0,
    GilbertElliott = 1
};
CFakeLagPacketLossMode CFakeLag_GetPacketLossMode();
