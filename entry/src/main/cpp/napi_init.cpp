#include "napi/native_api.h"
#include "range_model.h"

#include <algorithm>
#include <cerrno>
#include <cstdio>
#include <fcntl.h>
#include <string>
#include <unistd.h>
#include <vector>

namespace {

bool ReadString(napi_env env, napi_value value, size_t max_bytes, std::string &out) {
    size_t length = 0;
    if (napi_get_value_string_utf8(env, value, nullptr, 0, &length) != napi_ok || length > max_bytes) {
        return false;
    }
    std::vector<char> buffer(length + 1);
    if (napi_get_value_string_utf8(env, value, buffer.data(), buffer.size(), &length) != napi_ok) {
        return false;
    }
    out.assign(buffer.data(), length);
    return true;
}

bool ReadInt64(napi_env env, napi_value value, int64_t &out) {
    return napi_get_value_int64(env, value, &out) == napi_ok;
}

struct Work {
    napi_async_work work = nullptr;
    napi_deferred deferred = nullptr;
    std::string model_path;
    std::string request;
    std::string grammar;
    int fd = -1;
    int64_t offset = 0;
    int64_t length = 0;
    std::string output;
    std::string error;
};

void Complete(napi_env env, napi_status, void *data) {
    auto *work = static_cast<Work *>(data);
    if (work->error.empty()) {
        napi_value value;
        napi_create_string_utf8(env, work->output.c_str(), work->output.size(), &value);
        napi_resolve_deferred(env, work->deferred, value);
    } else {
        napi_value message;
        napi_value error;
        napi_create_string_utf8(env, work->error.c_str(), work->error.size(), &message);
        napi_create_error(env, nullptr, message, &error);
        napi_reject_deferred(env, work->deferred, error);
    }
    napi_delete_async_work(env, work->work);
    delete work;
}

napi_value Queue(napi_env env, Work *work, napi_async_execute_callback execute) {
    napi_value promise;
    napi_value name;
    napi_create_promise(env, &work->deferred, &promise);
    napi_create_string_utf8(env, "SafeShareRange", NAPI_AUTO_LENGTH, &name);
    napi_create_async_work(env, nullptr, name, execute, Complete, work, &work->work);
    napi_queue_async_work(env, work->work);
    return promise;
}

void ExecuteParse(napi_env, void *data) {
    auto *work = static_cast<Work *>(data);
    if (work->error.empty()) {
        work->output = range_model::Run(work->model_path, work->request, work->grammar, work->error);
    }
}

// parseRange(modelPath, request, grammar): Promise<string>
napi_value ParseRange(napi_env env, napi_callback_info info) {
    size_t argc = 3;
    napi_value args[3] = {nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto *work = new Work();
    if (argc != 3 || !ReadString(env, args[0], 4096, work->model_path) ||
        !ReadString(env, args[1], range_model::kMaxRequestBytes, work->request) ||
        !ReadString(env, args[2], range_model::kMaxGrammarBytes, work->grammar)) {
        work->error = "invalid arguments";
    }
    return Queue(env, work, ExecuteParse);
}

// Copies the model out of the HAP's raw-file region into the app sandbox, atomically.
void ExecuteInstall(napi_env, void *data) {
    auto *work = static_cast<Work *>(data);
    if (!work->error.empty()) {
        return;
    }
    const std::string partial = work->model_path + ".part";
    const int out = open(partial.c_str(), O_WRONLY | O_CREAT | O_TRUNC, 0600);
    if (out < 0) {
        work->error = "open destination";
        return;
    }
    std::vector<char> buffer(1 << 20);
    int64_t copied = 0;
    while (copied < work->length && work->error.empty()) {
        const size_t chunk = static_cast<size_t>(std::min<int64_t>(buffer.size(), work->length - copied));
        const ssize_t read_bytes = pread(work->fd, buffer.data(), chunk, work->offset + copied);
        if (read_bytes <= 0) {
            work->error = "read model";
            break;
        }
        for (ssize_t written = 0; written < read_bytes;) {
            const ssize_t result = write(out, buffer.data() + written, read_bytes - written);
            if (result < 0 && errno != EINTR) {
                work->error = "write model";
                break;
            }
            written += result > 0 ? result : 0;
        }
        copied += read_bytes;
    }
    if (fsync(out) != 0 && work->error.empty()) {
        work->error = "sync model";
    }
    close(out);
    if (work->error.empty() && rename(partial.c_str(), work->model_path.c_str()) != 0) {
        work->error = "rename model";
    }
    if (!work->error.empty()) {
        unlink(partial.c_str());
    }
}

// installModel(fd, offset, length, destPath): Promise<string>
napi_value InstallModel(napi_env env, napi_callback_info info) {
    size_t argc = 4;
    napi_value args[4] = {nullptr, nullptr, nullptr, nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    auto *work = new Work();
    int64_t fd = -1;
    if (argc != 4 || !ReadInt64(env, args[0], fd) || !ReadInt64(env, args[1], work->offset) ||
        !ReadInt64(env, args[2], work->length) || !ReadString(env, args[3], 4096, work->model_path) || fd < 0 ||
        work->offset < 0 || work->length <= 0) {
        work->error = "invalid arguments";
    }
    work->fd = static_cast<int>(fd);
    return Queue(env, work, ExecuteInstall);
}

// releaseModel(): frees the model's memory; the next parseRange loads it again.
napi_value ReleaseModel(napi_env env, napi_callback_info) {
    range_model::Release();
    return nullptr;
}

} // namespace

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor descriptors[] = {
        {"parseRange", nullptr, ParseRange, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"installModel", nullptr, InstallModel, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"releaseModel", nullptr, ReleaseModel, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(descriptors) / sizeof(descriptors[0]), descriptors);
    return exports;
}
EXTERN_C_END

static napi_module g_module = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "entry",
    .nm_priv = nullptr,
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterEntryModule() {
    napi_module_register(&g_module);
}
