// Exhaust the direct/cascade bus dependencies independently of nextpnr.
#include <cassert>
#include <string>
#include "xc7_dsp_cascade.inc"

int main()
{
    for (const auto &a : {"DIRECT", "CASCADE"}) {
        for (const auto &b : {"DIRECT", "CASCADE"}) {
            for (int bit = 0; bit < 30; ++bit) {
                const auto output = "ACOUT" + std::to_string(bit);
                for (int input = 0; input < 30; ++input) {
                    assert(xc7DspCascadeArcPossible("A" + std::to_string(input), output, a, b) ==
                           (std::string(a) == "DIRECT" && input == bit));
                    assert(xc7DspCascadeArcPossible("ACIN" + std::to_string(input), output, a, b) ==
                           (std::string(a) == "CASCADE" && input == bit));
                }
                for (const auto &port : {"B14", "BCIN7", "INMODE0", "C0", "D0", "OPMODE0"})
                    assert(!xc7DspCascadeArcPossible(port, output, a, b));
            }
            for (int bit = 0; bit < 18; ++bit) {
                const auto output = "BCOUT" + std::to_string(bit);
                for (int input = 0; input < 18; ++input) {
                    assert(xc7DspCascadeArcPossible("B" + std::to_string(input), output, a, b) ==
                           (std::string(b) == "DIRECT" && input == bit));
                    assert(xc7DspCascadeArcPossible("BCIN" + std::to_string(input), output, a, b) ==
                           (std::string(b) == "CASCADE" && input == bit));
                }
                for (const auto &port : {"A14", "ACIN7", "INMODE0", "C0", "D0", "OPMODE0"})
                    assert(!xc7DspCascadeArcPossible(port, output, a, b));
            }
        }
    }
    assert(xc7DspCascadeArcPossible("A7", "ACOUT7", "unknown", "unknown"));
    assert(xc7DspCascadeArcPossible("ACIN7", "ACOUT7", "unknown", "unknown"));
    assert(xc7DspCascadeArcPossible("B7", "BCOUT7", "unknown", "unknown"));
    assert(xc7DspCascadeArcPossible("BCIN7", "BCOUT7", "unknown", "unknown"));
    assert(!xc7DspCascadeArcPossible("B14", "ACOUT7", "unknown", "unknown"));
    for (const auto &port : {"P0", "PCOUT47", "CARRYOUT0", "MULTSIGNOUT", "PATTERNDETECT"})
        assert(xc7DspCascadeArcPossible("B14", port, "DIRECT", "DIRECT"));
}
