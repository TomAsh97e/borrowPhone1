// Host driver for run_eval.mjs. Input: per case, the request on one line, then the grammar lines,
// then a line "%%". Output: one line per case with the model's JSON or "ERROR: ...".
#include "range_model.h"

#include <iostream>
#include <string>

int main(int argc, char **argv) {
    if (argc != 2) {
        std::cerr << "usage: range_eval <model.gguf>\n";
        return 2;
    }
    std::string request;
    while (std::getline(std::cin, request)) {
        std::string grammar;
        std::string line;
        while (std::getline(std::cin, line) && line != "%%") {
            grammar += line + "\n";
        }
        std::string error;
        const std::string output = range_model::Run(argv[1], request, grammar, error);
        std::cout << (error.empty() ? output : "ERROR: " + error) << std::endl;
    }
    range_model::Release();
    return 0;
}
