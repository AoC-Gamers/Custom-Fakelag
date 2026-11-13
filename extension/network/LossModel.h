#pragma once

class LossPercentage {
    int m_Value = 0;
public:
    static bool TryFrom(int value, LossPercentage& result) {
        if (value < 0 || value > 100) return false;
        result.m_Value = value;
        return true;
    }
    double Fraction() const { return m_Value / 100.0; }
};

// Transition first, then emit: a bad state drops exactly this packet.
// a=P(G->B)=p/2, q=P(B->G)=(1-p)/2. Stationary loss a/(a+q)=p,
// E[bad run]=1/q=2/(1-p), lag-one correlation=1-a-q=1/2.
// A fixed two-packet burst is incompatible with high p and bounded a.
inline bool GilbertElliottDrop(bool& bad, int percent, double uniform)
{
    LossPercentage validated;
    if (!LossPercentage::TryFrom(percent, validated)) { bad = false; return false; }
    const double p = validated.Fraction();
    if (p == 0) { bad = false; return false; }
    if (p == 1) { bad = true; return true; }
    if (bad) { if (uniform < (1.0 - p) / 2.0) bad = false; }
    else if (uniform < p / 2.0) bad = true;
    return bad;
}
