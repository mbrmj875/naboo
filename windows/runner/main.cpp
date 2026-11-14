#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <string>

#include "app_links/app_links_plugin_c_api.h"
#include "flutter_window.h"
#include "utils.h"

namespace {

// يُسجّل رابط الرجوع لحساب Google على ويندوز في حساب المستخدم الحالي.
void RegisterOAuthProtocol() {
  wchar_t exe_path[MAX_PATH];
  const DWORD length = ::GetModuleFileNameW(nullptr, exe_path, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return;
  }

  HKEY scheme_key = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, L"Software\\Classes\\io.supabase.naboo",
                        0, nullptr, 0, KEY_SET_VALUE, nullptr, &scheme_key,
                        nullptr) != ERROR_SUCCESS) {
    return;
  }
  const wchar_t* url_label = L"URL:NABOO";
  ::RegSetValueExW(scheme_key, nullptr, 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(url_label),
                   static_cast<DWORD>((wcslen(url_label) + 1) * sizeof(wchar_t)));
  const wchar_t empty[] = L"";
  ::RegSetValueExW(scheme_key, L"URL Protocol", 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(empty), sizeof(empty));
  ::RegCloseKey(scheme_key);

  HKEY command_key = nullptr;
  if (::RegCreateKeyExW(
          HKEY_CURRENT_USER,
          L"Software\\Classes\\io.supabase.naboo\\shell\\open\\command", 0,
          nullptr, 0, KEY_SET_VALUE, nullptr, &command_key,
          nullptr) != ERROR_SUCCESS) {
    return;
  }
  const std::wstring command =
      L"\"" + std::wstring(exe_path) + L"\" \"%1\"";
  ::RegSetValueExW(command_key, nullptr, 0, REG_SZ,
                   reinterpret_cast<const BYTE*>(command.c_str()),
                   static_cast<DWORD>((command.size() + 1) * sizeof(wchar_t)));
  ::RegCloseKey(command_key);
}

bool SendAppLinkToInstance(const std::wstring& title) {
  HWND hwnd = ::FindWindow(L"NABOO_ERP_WIN32_WINDOW", title.c_str());
  if (hwnd == nullptr) {
    hwnd = ::FindWindow(L"NABOO_ERP_WIN32_WINDOW", nullptr);
  }
  if (hwnd == nullptr) {
    return false;
  }

  SendAppLink(hwnd);

  WINDOWPLACEMENT place = {sizeof(WINDOWPLACEMENT)};
  ::GetWindowPlacement(hwnd, &place);
  switch (place.showCmd) {
    case SW_SHOWMAXIMIZED:
      ::ShowWindow(hwnd, SW_SHOWMAXIMIZED);
      break;
    case SW_SHOWMINIMIZED:
      ::ShowWindow(hwnd, SW_RESTORE);
      break;
    default:
      ::ShowWindow(hwnd, SW_NORMAL);
      break;
  }
  ::SetForegroundWindow(hwnd);
  return true;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  RegisterOAuthProtocol();
  if (SendAppLinkToInstance(L"naboo")) {
    return EXIT_SUCCESS;
  }

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"naboo", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
