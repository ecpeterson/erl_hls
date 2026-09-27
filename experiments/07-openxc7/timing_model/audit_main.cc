// Audit every IR node with the installed estimator; never stop at the first gap.
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>
#include "xls/common/init_xls.h"
#include "xls/estimators/delay_model/delay_estimator.h"
#include "xls/ir/ir_parser.h"
#include "xls/ir/package.h"
#include "xls/ir/function_base.h"

// Emit tab-separated scope, node, status/delay and canonical IR; fail on any gap.
int main(int argc, char** argv) {
  auto args = xls::InitXls("Audit XC7 timing coverage: audit_main FILE", argc, argv);
  if (args.size() != 1) return 2;
  std::ifstream input{std::string(args[0])};
  if (!input) return 2;
  std::string source{std::istreambuf_iterator<char>(input), {}};
  auto package = xls::Parser::ParsePackage(source);
  if (!package.ok()) { std::cerr << package.status() << "\n"; return 2; }
  auto model = xls::GetDelayEstimatorManagerSingleton().GetDelayEstimator("xc7_7030");
  if (!model.ok()) { std::cerr << model.status() << "\n"; return 2; }
  int missing = 0;
  for (auto* function : (*package)->GetFunctionBases()) {
    for (auto* node : function->nodes()) {
      auto delay = (*model)->GetOperationDelayInPs(node);
      std::cout << function->name() << "\t" << node->GetName() << "\t";
      if (delay.ok()) std::cout << *delay;
      else {
        std::string message(delay.status().message());
        message = message.substr(0, message.find('\n'));
        std::cout << "MISSING: " << message; ++missing;
      }
      std::cout << "\t" << node->ToString() << "\t";
      for (auto* operand : node->operands())
        std::cout << operand->GetName() << ":" << operand->GetType()->ToString() << "|";
      std::cout << "\n";
    }
  }
  std::cerr << "Unsupported nodes: " << missing << "\n";
  return missing ? 1 : 0;
}
