#pragma once

#include <cstddef>
#include <string>

// On-device interpreter that turns a short English request ("photos from the last 3 days") into a
// grammar-constrained JSON period. The output is untrusted: ArkTS validates it (model/TextRange.ts)
// and the owner approves the resulting period before anything changes.
namespace range_model {

constexpr size_t kMaxRequestBytes = 512;
constexpr size_t kMaxGrammarBytes = 4096;

// Returns the model's JSON, or an empty string with `error` set. `grammar` (GBNF, root rule "root")
// is built per request from what the request text can justify (TextRange.ts buildGrammar).
std::string Run(const std::string &model_path, const std::string &request, const std::string &grammar,
                std::string &error);

// Frees the cached model (e.g. before a guest session).
void Release();

} // namespace range_model
