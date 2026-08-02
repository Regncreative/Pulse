// PulseMCP.exe — thin launcher for the bundled private Node runtime.
// End users never need a system Node.js install.
// Child (node) is assigned to a job so it dies when this process is killed (MCP clients).

#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <cstdio>
#include <string>
#include <vector>

namespace {

std::wstring DirName(const std::wstring& path) {
  const auto pos = path.find_last_of(L"\\/");
  if (pos == std::wstring::npos) {
    return L".";
  }
  return path.substr(0, pos);
}

std::wstring QuoteArg(const std::wstring& arg) {
  if (arg.empty()) {
    return L"\"\"";
  }
  const bool need =
      arg.find_first_of(L" \t\"") != std::wstring::npos;
  if (!need) {
    return arg;
  }
  std::wstring out = L"\"";
  for (wchar_t ch : arg) {
    if (ch == L'"') {
      out += L"\\\"";
    } else {
      out += ch;
    }
  }
  out += L'"';
  return out;
}

}  // namespace

int wmain(int argc, wchar_t** argv) {
  wchar_t module_path[MAX_PATH] = {};
  const DWORD n = GetModuleFileNameW(nullptr, module_path, MAX_PATH);
  if (n == 0 || n >= MAX_PATH) {
    fwprintf(stderr, L"PulseMCP: cannot resolve own path\n");
    return 1;
  }

  const std::wstring dir = DirName(module_path);
  const std::wstring node = dir + L"\\runtime\\node.exe";
  const std::wstring main_js = dir + L"\\mcp\\main.js";

  if (GetFileAttributesW(node.c_str()) == INVALID_FILE_ATTRIBUTES) {
    fwprintf(
        stderr,
        L"PulseMCP: bundled runtime missing:\n  %s\n"
        L"Reinstall Pulse. A system Node.js install is not required.\n",
        node.c_str());
    return 1;
  }
  if (GetFileAttributesW(main_js.c_str()) == INVALID_FILE_ATTRIBUTES) {
    fwprintf(stderr, L"PulseMCP: mcp\\main.js missing:\n  %s\n", main_js.c_str());
    return 1;
  }

  std::wstring cmd = QuoteArg(node) + L" " + QuoteArg(main_js);
  for (int i = 1; i < argc; ++i) {
    cmd.push_back(L' ');
    cmd += QuoteArg(argv[i]);
  }

  HANDLE job = CreateJobObjectW(nullptr, nullptr);
  if (!job) {
    fwprintf(stderr, L"PulseMCP: CreateJobObject failed (%lu)\n", GetLastError());
    return 1;
  }

  JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
  limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
  if (!SetInformationJobObject(
          job, JobObjectExtendedLimitInformation, &limits, sizeof(limits))) {
    fwprintf(stderr, L"PulseMCP: SetInformationJobObject failed (%lu)\n", GetLastError());
    CloseHandle(job);
    return 1;
  }

  STARTUPINFOW si = {sizeof(si)};
  PROCESS_INFORMATION pi = {};
  std::vector<wchar_t> cmd_buf(cmd.begin(), cmd.end());
  cmd_buf.push_back(L'\0');

  // Inherit std handles so MCP stdio (and status-daemon) works through this EXE.
  const BOOL ok = CreateProcessW(
      node.c_str(),
      cmd_buf.data(),
      nullptr,
      nullptr,
      TRUE,
      CREATE_SUSPENDED,
      nullptr,
      nullptr,
      &si,
      &pi);
  if (!ok) {
    fwprintf(stderr, L"PulseMCP: failed to start runtime (%lu)\n", GetLastError());
    CloseHandle(job);
    return 1;
  }

  if (!AssignProcessToJobObject(job, pi.hProcess)) {
    fwprintf(stderr, L"PulseMCP: AssignProcessToJobObject failed (%lu)\n", GetLastError());
    TerminateProcess(pi.hProcess, 1);
    CloseHandle(pi.hThread);
    CloseHandle(pi.hProcess);
    CloseHandle(job);
    return 1;
  }

  ResumeThread(pi.hThread);
  CloseHandle(pi.hThread);

  WaitForSingleObject(pi.hProcess, INFINITE);
  DWORD code = 1;
  GetExitCodeProcess(pi.hProcess, &code);
  CloseHandle(pi.hProcess);
  CloseHandle(job);
  return static_cast<int>(code);
}
