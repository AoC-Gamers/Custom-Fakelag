#pragma once

inline bool CFakeLag_LanPolicyBlocks(bool lan, bool allowLan) { return lan && !allowLan; }
bool CFakeLag_IsLanBlocked();
