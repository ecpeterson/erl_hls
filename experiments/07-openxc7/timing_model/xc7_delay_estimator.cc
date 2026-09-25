// Bounded XLS delay estimates for a measured native XC7 mapping.
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <fstream>
#include <map>
#include <memory>
#include <sstream>
#include <string>
#include <vector>
#include "absl/flags/flag.h"
#include "absl/status/status.h"
#include "absl/status/statusor.h"
#include "xls/estimators/delay_model/delay_estimator.h"
#include "xls/ir/node.h"
#include "xls/ir/nodes.h"
#include "xls/ir/op.h"

ABSL_FLAG(std::string, xc7_delay_table, "", "Measured rows: op width cases cell_ps routed_ps.");
ABSL_FLAG(bool, xc7_routed_delays, true, "Include measured local routing in operation costs.");

namespace xls {
namespace {
// Delays exclude the launch flip-flop's clock-to-Q and capture setup time.
struct Sample { int64_t width; int64_t cell; int64_t routed; };
using Table = std::map<std::pair<std::string, int64_t>, std::vector<Sample>>;

// Read and validate one calibration table; malformed input never becomes a zero delay.
absl::StatusOr<Table> LoadTable() {
  std::ifstream input(absl::GetFlag(FLAGS_xc7_delay_table));
  if (!input) return absl::InvalidArgumentError("--xc7_delay_table must name a readable calibration table");
  Table table;
  std::string line;
  while (std::getline(input, line)) {
    if (line.empty() || line[0] == '#') continue;
    std::istringstream fields(line);
    std::string op, extra;
    int64_t count;
    Sample sample;
    if (!(fields >> op >> sample.width >> count >> sample.cell >> sample.routed) ||
        (fields >> extra) || sample.width <= 0 || count <= 0 || sample.cell < 0 ||
        sample.routed < sample.cell)
      return absl::InvalidArgumentError("invalid XC7 calibration row: " + line);
    table[{op, count}].push_back(sample);
  }
  if (table.empty()) return absl::InvalidArgumentError("empty XC7 calibration table");
  for (auto& [key, samples] : table) {
    std::sort(samples.begin(), samples.end(), [](auto a, auto b) { return a.width < b.width; });
    for (size_t i = 1; i < samples.size(); ++i)
      if (samples[i].width == samples[i - 1].width)
        return absl::InvalidArgumentError("duplicate XC7 calibration width");
  }
  return table;
}

// Wiring has zero intrinsic cell delay; its physical fan-out remains a placement cost.
bool IsWiring(Op op) {
  switch (op) {
    case Op::kParam: case Op::kLiteral: case Op::kIdentity: case Op::kConcat:
    case Op::kBitSlice: case Op::kSignExt: case Op::kZeroExt: case Op::kReverse:
    case Op::kTuple: case Op::kTupleIndex: case Op::kArray: case Op::kAfterAll:
    case Op::kStateRead: case Op::kNext: case Op::kInputPort: case Op::kOutputPort:
    case Op::kRegisterRead: case Op::kRegisterWrite:
      return true;
    default: return false;
  }
}

// Interpolate a monotone envelope inside measured widths; reject extrapolation.
class Xc7DelayEstimator final : public DelayEstimator {
 public:
  // Register an explicitly selected model; it never replaces a default.
  Xc7DelayEstimator() : DelayEstimator("xc7_7030") {}
  // Return a measured-shape estimate or an error; unknown shapes have no fallback.
  absl::StatusOr<int64_t> GetOperationDelayInPs(Node* node) const override {
    if (IsWiring(node->op())) return 0;
    static const auto table = LoadTable();
    if (!table.ok()) return table.status();
    std::string op(OpToString(node->op()));
    int64_t width = node->GetType()->GetFlatBitCount();
    int64_t count = 2;
    switch (node->op()) {
      case Op::kEq: case Op::kNe: case Op::kULt: case Op::kULe: case Op::kUGt:
      case Op::kUGe: case Op::kSLt: case Op::kSLe: case Op::kSGt: case Op::kSGe:
      case Op::kAndReduce: case Op::kOrReduce: case Op::kXorReduce:
        width = node->operand(0)->GetType()->GetFlatBitCount(); break;
      case Op::kSel: {
        count = node->As<Select>()->cases().size();
        // Wider selectors add default-arm decoding absent from the measured muxes.
        const int64_t selector_width = node->As<Select>()->selector()->BitCountOrDie();
        if ((count != 2 && count != 4 && count != 8) ||
            selector_width != (count == 2 ? 1 : count == 4 ? 2 : 3))
          return absl::UnimplementedError("XC7 select shape exceeds calibration: " + node->ToString());
        break;
      }
      case Op::kOneHotSel: count = node->As<OneHotSelect>()->cases().size(); break;
      case Op::kPrioritySel: count = node->As<PrioritySelect>()->cases().size(); break;
      case Op::kAnd: case Op::kOr: case Op::kXor: count = node->operand_count(); break;
      default: break;
    }
    // A measured constant multiply is valid only for its exact operand/result shape.
    if (node->op() == Op::kSMul && node->operand(1)->Is<Literal>()) {
      auto bits = node->operand(1)->As<Literal>()->value().bits();
      auto value = bits.ToUint64();
      if (value.ok()) {
        const std::string key = "smul_const_" +
            std::to_string(node->operand(0)->GetType()->GetFlatBitCount()) + "_" +
            std::to_string(bits.bit_count()) + "_" + std::to_string(width) + "_" +
            std::to_string(*value);
        if (table->find({key, count}) != table->end()) op = key;
      }
    }
    auto it = table->find({op, count});
    if (it == table->end()) return absl::UnimplementedError("XC7 model has no calibration for " + node->ToString());
    for (Node* operand : node->operands())
      if (operand->GetType()->GetFlatBitCount() > std::max<int64_t>(width, count))
        return absl::UnimplementedError("XC7 operand exceeds calibrated shape: " + node->ToString());
    const auto& samples = it->second;
    if (width > samples.back().width)
      return absl::UnimplementedError("XC7 width exceeds calibration: " + node->ToString());
    const bool routed = absl::GetFlag(FLAGS_xc7_routed_delays);
    int64_t previous_width = 0, previous_delay = 0;
    for (const Sample& sample : samples) {
      const int64_t delay = std::max(previous_delay, routed ? sample.routed : sample.cell);
      if (width <= sample.width) {
        if (previous_width == 0) return delay;
        return static_cast<int64_t>(std::ceil(previous_delay +
            double(delay - previous_delay) * (width - previous_width) / (sample.width - previous_width)));
      }
      previous_width = sample.width;
      previous_delay = delay;
    }
    return absl::InternalError("unreachable XC7 width interval");
  }
};

// Explicit selection is required; existing default model selection is unchanged.
const bool registered = [] {
  return GetDelayEstimatorManagerSingleton().RegisterDelayEstimator(
      std::make_unique<Xc7DelayEstimator>(), DelayEstimatorPrecedence::kLow).ok();
}();
}  // namespace
}  // namespace xls
