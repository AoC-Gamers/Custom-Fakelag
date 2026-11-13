#pragma once

// Transition first, then emit: a bad state drops exactly this packet.
// a=P(G->B)=p/2, q=P(B->G)=(1-p)/2. Stationary loss a/(a+q)=p,
// E[bad run]=1/q=2/(1-p), lag-one correlation=1-a-q=1/2.
// A fixed two-packet burst is incompatible with high p and bounded a.
inline bool GilbertElliottDrop(bool& bad, int percent, double uniform)
{
    if (percent <= 0) { bad = false; return false; }
    if (percent >= 100) { bad = true; return true; }
    const double p = percent / 100.0;
    if (bad) { if (uniform < (1.0 - p) / 2.0) bad = false; }
    else if (uniform < p / 2.0) bad = true;
    return bad;
}
