// Bounded XLS delay estimates for a measured native XC7 mapping.
#include <algorithm>
#include <charconv>
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
// Calibration rows are grouped by operation family and fan-in.
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

// Interpolate measured widths after taking a monotone envelope; never extrapolate.
absl::StatusOr<int64_t> WidthDelay(const std::vector<Sample>& samples,
                                  int64_t width, bool routed) {
  if (width > samples.back().width)
    return absl::UnimplementedError("XC7 width exceeds calibration");
  int64_t previous_width = 0, previous_delay = 0;
  for (const Sample& sample : samples) {
    int64_t delay = std::max(previous_delay, routed ? sample.routed : sample.cell);
    if (width <= sample.width) {
      if (previous_width == 0) return delay;
      return static_cast<int64_t>(std::ceil(previous_delay + double(delay - previous_delay) *
          (width - previous_width) / (sample.width - previous_width)));
    }
    previous_width = sample.width; previous_delay = delay;
  }
  return absl::InternalError("unreachable XC7 width interval");
}

// Fan-in interpolation is checked against held-out non-power-of-two circuits.
absl::StatusOr<int64_t> ShapeDelay(const Table& table, const std::string& op,
                                  int64_t width, int64_t count, bool routed) {
  int64_t previous_count = 0, previous_delay = 0;
  bool found = false;
  for (const auto& [key, samples] : table) {
    if (key.first != op) continue;
    found = true;
    auto value = WidthDelay(samples, width, routed);
    if (!value.ok()) return value.status();
    int64_t delay = std::max(previous_delay, *value);
    if (count <= key.second) {
      if (previous_count == 0) return delay;
      return static_cast<int64_t>(std::ceil(previous_delay + double(delay - previous_delay) *
          (count - previous_count) / (key.second - previous_count)));
    }
    previous_count = key.second; previous_delay = delay;
  }
  return absl::UnimplementedError(found ? "XC7 fan-in exceeds calibration" :
                                          "XC7 model has no calibration for " + op);
}

// Wider sampled indices retain the overflow/default decoder; record this approximation.
std::string IndexFamily(const Table& table, const std::string& prefix, int64_t bits) {
  int64_t selected = INT64_MAX;
  for (const auto& [key, samples] : table) {
    if (key.first.rfind(prefix, 0) != 0) continue;
    std::string suffix = key.first.substr(prefix.size());
    if (suffix.empty() || suffix.find_first_not_of("0123456789") != std::string::npos) continue;
    int64_t candidate;
    const auto parsed = std::from_chars(suffix.data(), suffix.data() + suffix.size(), candidate);
    if (parsed.ec != std::errc{} || parsed.ptr != suffix.data() + suffix.size()) continue;
    if (candidate >= bits) selected = std::min(selected, candidate);
  }
  return prefix + std::to_string(selected == INT64_MAX ? bits : selected);
}

// Return a measured-shape estimate or an error; unsupported shapes have no fallback.
class Xc7DelayEstimator final : public DelayEstimator {
 public:
  // Register an explicitly selected model without replacing existing defaults.
  Xc7DelayEstimator() : DelayEstimator("xc7_7030") {}

  // Costs describe proc-local operations, not stitched FIFO ready/valid paths.
  absl::StatusOr<int64_t> GetOperationDelayInPs(Node* node) const override {
    if (IsWiring(node->op())) return 0;
    // Proc I/O is a scheduling boundary, as in the standard technology estimators.
    // Its generated valid/data gating and FIFO/RAM adapters need mapped STA.
    if (node->op() == Op::kSend || node->op() == Op::kReceive) return 0;
    if (node->GetType()->GetFlatBitCount() == 0) return 0;
    static const auto table = LoadTable();
    if (!table.ok()) return table.status();
    std::string op(OpToString(node->op()));
    int64_t width = node->GetType()->GetFlatBitCount(), count = 2;
    bool aggregate = false;
    switch (node->op()) {
      case Op::kEq: case Op::kNe: case Op::kULt: case Op::kULe: case Op::kUGt:
      case Op::kUGe: case Op::kSLt: case Op::kSLe: case Op::kSGt: case Op::kSGe:
      case Op::kAndReduce: case Op::kOrReduce: case Op::kXorReduce:
        width = node->operand(0)->GetType()->GetFlatBitCount(); break;
      case Op::kSel: {
        auto* select = node->As<Select>();
        count = select->cases().size();
        int64_t bits = select->selector()->BitCountOrDie();
        // A full binary selector needs no default-arm decoding.
        if (bits >= 63 || count != (int64_t{1} << bits))
          op = IndexFamily(*table, "sel_d", bits);
        break;
      }
      case Op::kOneHotSel: count = node->As<OneHotSelect>()->cases().size(); break;
      case Op::kPrioritySel: count = node->As<PrioritySelect>()->cases().size(); break;
      case Op::kAnd: case Op::kOr: case Op::kXor: case Op::kNand: case Op::kNor:
        count = node->operand_count(); break;
      case Op::kOneHot:
        op = node->As<OneHot>()->priority() == LsbOrMsb::kLsb ? "one_hot_lsb" : "one_hot_msb";
        width = node->operand(0)->BitCountOrDie(); break;
      case Op::kShll: case Op::kShrl: case Op::kShra:
        if (node->operand(1)->Is<Literal>()) return 0;
        if (node->operand(1)->BitCountOrDie() != width)
          op = IndexFamily(*table, op + "_s", node->operand(1)->BitCountOrDie());
        aggregate = true; break;
      case Op::kArrayIndex: case Op::kArrayUpdate: {
        auto indices = node->op() == Op::kArrayIndex ? node->As<ArrayIndex>()->indices() :
                                                      node->As<ArrayUpdate>()->indices();
        bool constant = std::all_of(indices.begin(), indices.end(), [](Node* n) { return n->Is<Literal>(); });
        if (constant) return 0;  // Fixed slicing/reassembly, including known out-of-range cases.
        if (indices.size() > 1) {
          // Constant dimensions select fixed wires. Dynamic dimensions compose mux
          // layers; summing their measured costs is checked on nested-array probes.
          if (node->op() == Op::kArrayUpdate)
            return absl::UnimplementedError("XC7 multidimensional dynamic update: " + node->ToString());
          std::vector<int64_t> sizes;
          Type* type = node->operand(0)->GetType();
          for (auto* index : indices) {
            auto* array = type->AsArrayOrDie();
            sizes.push_back(array->size()); type = array->element_type();
          }
          int64_t selected_width = type->GetFlatBitCount(), delay = 0;
          for (int64_t i = indices.size() - 1; i >= 0; --i) {
            if (indices[i]->Is<Literal>()) continue;
            int64_t bits = indices[i]->BitCountOrDie();
            int64_t cases = bits < 63 ? std::min(sizes[i], int64_t{1} << bits) : sizes[i];
            auto part = ShapeDelay(*table, IndexFamily(*table, "array_index_s", bits),
                                  selected_width, cases, absl::GetFlag(FLAGS_xc7_routed_delays));
            if (!part.ok()) return part.status();
            delay += *part; selected_width *= cases;
          }
          return delay;
        }
        auto* type = node->operand(0)->GetType()->AsArrayOrDie();
        int64_t bits = indices.front()->BitCountOrDie();
        count = bits < 63 ? std::min(type->size(), int64_t{1} << bits) : type->size();
        width = type->element_type()->GetFlatBitCount();
        op = IndexFamily(*table, node->op() == Op::kArrayIndex ? "array_index_s" : "array_update_s", bits);
        aggregate = true; break;
      }
      default: break;
    }
    // Constant multiplies qualify only at their exact measured operand/result shape.
    if (node->op() == Op::kSMul && node->operand(1)->Is<Literal>()) {
      auto bits = node->operand(1)->As<Literal>()->value().bits();
      auto value = bits.ToUint64();
      if (value.ok()) {
        std::string key = "smul_const_" + std::to_string(node->operand(0)->GetType()->GetFlatBitCount()) +
            "_" + std::to_string(bits.bit_count()) + "_" + std::to_string(width) + "_" + std::to_string(*value);
        if (table->find({key, count}) != table->end()) op = key;
      }
    }
    // Selectors and array indices are separate measured dimensions, not payload widths.
    if (!aggregate) {
      for (int64_t i = 0; i < node->operand_count(); ++i) {
        if (i == 0 && (node->Is<Select>() || node->Is<OneHotSelect>() || node->Is<PrioritySelect>())) continue;
        if (node->operand(i)->GetType()->GetFlatBitCount() > std::max<int64_t>(width, count))
          return absl::UnimplementedError("XC7 operand exceeds calibrated shape: " + node->ToString());
      }
    }
    return ShapeDelay(*table, op, width, count, absl::GetFlag(FLAGS_xc7_routed_delays));
  }
};

// Only explicit model selection enables the experimental table.
const bool registered = [] {
  return GetDelayEstimatorManagerSingleton().RegisterDelayEstimator(
      std::make_unique<Xc7DelayEstimator>(), DelayEstimatorPrecedence::kLow).ok();
}();
}  // namespace
}  // namespace xls
