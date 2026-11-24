// Icarus observer for settled mapped-primitive outputs at successive falling
// edges.
#include <algorithm>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <set>
#include <string>
#include <vector>
#include <vpi_user.h>

namespace {
// Preserve the four-state value of every lane across consecutive sampled edges.
struct Port {
  vpiHandle signal;
  unsigned width;
  std::vector<s_vpi_vecval> previous;
};
// A synthesized primitive and its output ports in the functional library.
struct Cell {
  std::string name, kind;
  std::vector<Port> outputs;
};
std::vector<Cell> cells;
FILE *transitions;
unsigned samples;

// Abort the producer before an incomplete file can be accepted as a full trace.
void fail(const char *reason) {
  std::fprintf(stderr, "transition observer: %s\n", reason);
  std::exit(1);
}

// Only descend through design hierarchy. Library internals model one mapped
// primitive.
void discover(vpiHandle scope, const std::string &parent,
              const std::set<std::string> &kinds) {
  auto children = vpi_iterate(vpiModule, scope);
  while (children) {
    auto child = vpi_scan(children);
    if (!child)
      break;
    std::string local = vpi_get_str(vpiName, child);
    std::string kind = vpi_get_str(vpiDefName, child);
    std::string name = parent.empty() ? local : parent + "/" + local;
    if (!kinds.count(kind)) {
      auto nested = vpi_iterate(vpiModule, child);
      if (!nested)
        fail(("unclassified leaf " + name + " " + kind).c_str());
      vpi_free_object(nested);
      discover(child, name, kinds);
      continue;
    }
    Cell cell{name, kind, {}};
    auto ports = vpi_iterate(vpiPort, child);
    while (ports) {
      auto port = vpi_scan(ports);
      if (!port)
        break;
      if (vpi_get(vpiDirection, port) != vpiOutput)
        continue;
      auto signal = vpi_handle_by_name(vpi_get_str(vpiName, port), child);
      if (!signal)
        fail("missing primitive output");
      unsigned width = vpi_get(vpiSize, signal);
      if (width == 0 || width > 512)
        fail("primitive output width");
      cell.outputs.push_back(
          {signal, width, std::vector<s_vpi_vecval>((width + 31) / 32)});
    }
    if (cell.outputs.empty())
      fail(("no outputs on " + name).c_str());
    cells.push_back(std::move(cell));
    if (cells.size() > 150000)
      fail("cell count limit");
  }
}

// Keep a known-to-known transition and unknown comparisons as independent
// masks. The first settled sample initializes history and has no preceding
// observation.
PLI_INT32 edge(p_cb_data callback) {
  if (callback->value->value.scalar != vpi0)
    return 0;
  s_vpi_time now{};
  now.type = vpiSimTime;
  vpi_get_time(nullptr, &now);
  if (now.high == 0 && now.low == 0)
    return 0;
  const size_t words = (cells.size() + 7) / 8;
  std::vector<unsigned char> masks(2 * words);
  std::string baseline;
  if (samples == 0)
    baseline.assign(cells.size(), '-');
  for (size_t i = 0; i < cells.size(); ++i) {
    bool changed = false, unknown = false;
    for (auto &p : cells[i].outputs) {
      s_vpi_value value{};
      value.format = vpiVectorVal;
      vpi_get_value(p.signal, &value);
      if (samples == 0 && cells[i].kind == "FDRE") {
        if (cells[i].outputs.size() != 1 || p.width != 1)
          fail("FDRE output shape");
        const auto q = value.value.vector[0];
        baseline[i] = (q.bval & 1) ? 'x' : (q.aval & 1) ? '1' : '0';
      }
      for (size_t j = 0; j < p.previous.size(); ++j) {
        auto v = value.value.vector[j], old = p.previous[j];
        uint32_t mask = ~uint32_t(0);
        if (j + 1 == p.previous.size() && p.width % 32)
          mask = (uint32_t(1) << (p.width % 32)) - 1;
        auto x = uint32_t(v.bval | old.bval) & mask;
        changed |=
            samples > 0 && ((uint32_t(v.aval ^ old.aval) & mask & ~x) != 0);
        unknown |= samples == 0 || x != 0;
        p.previous[j] = v;
      }
    }
    if (changed)
      masks[i / 8] |= 1u << (i % 8);
    if (unknown)
      masks[words + i / 8] |= 1u << (i % 8);
  }
  if (std::fwrite(masks.data(), 1, masks.size(), transitions) != masks.size())
    fail("trace write");
  if (samples == 0) {
    FILE *out = std::fopen("initial-q.txt", "wx");
    if (!out ||
        std::fwrite(baseline.data(), 1, baseline.size(), out) !=
            baseline.size() ||
        std::fclose(out))
      fail("initial register values");
  }
  ++samples;
  return 0;
}

// Register against the two-pin harness and record the cell ordering of the bit
// masks.
PLI_INT32 start(p_cb_data) {
  std::ifstream input("primitive-types.txt");
  std::set<std::string> kinds;
  for (std::string line; std::getline(input, line);)
    kinds.insert(line);
  auto root = vpi_handle_by_name("functional_tb.dut", nullptr);
  auto clk = vpi_handle_by_name("functional_tb.clock", nullptr);
  if (kinds.empty() || !root || !clk)
    fail("top or primitive catalogue");
  discover(root, "", kinds);
  std::sort(cells.begin(), cells.end(),
            [](const Cell &a, const Cell &b) { return a.name < b.name; });
  FILE *names = std::fopen("cells.tsv", "wx");
  transitions = std::fopen("changes.bin", "wbx");
  if (!names || !transitions || cells.empty())
    fail("fresh output directory required");
  for (const auto &c : cells)
    std::fprintf(names, "%s\t%s\n", c.name.c_str(), c.kind.c_str());
  if (std::fclose(names))
    fail("catalogue write");
  static s_vpi_value v{};
  v.format = vpiScalarVal;
  s_cb_data cb{};
  cb.reason = cbValueChange;
  cb.obj = clk;
  cb.cb_rtn = edge;
  cb.value = &v;
  vpi_register_cb(&cb);
  return 0;
}

// A clean simulation footer is separately checked against the expected number
// of samples.
PLI_INT32 finish(p_cb_data) {
  if (!transitions || std::fclose(transitions))
    fail("trace close");
  vpi_printf("OBSERVED %u %zu\n", samples, cells.size());
  return 0;
}
// Install VPI lifecycle callbacks before the harness starts.
void install() {
  s_cb_data cb{};
  cb.reason = cbStartOfSimulation;
  cb.cb_rtn = start;
  vpi_register_cb(&cb);
  cb.reason = cbEndOfSimulation;
  cb.cb_rtn = finish;
  vpi_register_cb(&cb);
}
} // namespace
extern "C" {
void (*vlog_startup_routines[])() = {install, nullptr};
}
