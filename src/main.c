#include "mongoose.h"
#include <windows.h>
#include <shellapi.h>
#include <winsvc.h>
#include <stdio.h>
#include <string.h>
#include <wchar.h>

#ifndef HTTP_PORT
#define HTTP_PORT 8000
#endif
#define APP_VERSION L"V0.0.3"

#define WM_TRAY (WM_APP + 1)
#define ID_QUIT 100
#define ID_SETTINGS 101
#define ID_INSTALL_SERVICE 102
#define ID_REMOVE_SERVICE 103
#define ID_CONNECT 104
#define ID_PORT 200
#define ID_ROOT 201
#define ID_LISTING 202
#define ID_SAVE 203
#define ID_RESET 204
#define ID_GROUP 205
#define IDD_SETTINGS 300
#define SERVICE_NAME L"Mongoose"

typedef struct {
  UINT port;
  BOOL listing;
} Settings;

static Settings s_settings = {HTTP_PORT, TRUE};
static WCHAR s_root_w[MAX_PATH], s_config_path[MAX_PATH];
static char s_root[MAX_PATH * 4];
static HWND s_window;
static UINT s_taskbar_created;
static NOTIFYICONDATAW s_icon;
static volatile LONG s_stop;
static BOOL s_restart;
static SERVICE_STATUS_HANDLE s_service_handle;
static SERVICE_STATUS s_service_status;

static char *append_uint(char *p, UINT value) {
  char digits[10];
  unsigned n = 0;
  do { digits[n++] = (char) ('0' + value % 10); value /= 10; } while (value);
  while (n) *p++ = digits[--n];
  return p;
}

static WCHAR *append_uint_w(WCHAR *p, UINT value) {
  WCHAR digits[10];
  unsigned n = 0;
  do { digits[n++] = (WCHAR) (L'0' + value % 10); value /= 10; } while (value);
  while (n) *p++ = digits[--n];
  *p = L'\0';
  return p;
}

static BOOL resolve_paths(void) {
  WCHAR path[MAX_PATH];
  DWORD n = GetModuleFileNameW(NULL, path, MAX_PATH);
  WCHAR *slash;
  if (!n || n >= MAX_PATH || (slash = wcsrchr(path, L'\\')) == NULL) return FALSE;
  slash[1] = L'\0';
  lstrcpynW(s_root_w, path, MAX_PATH);
  if (lstrlenW(path) + lstrlenW(L"mongoose.conf") >= MAX_PATH) return FALSE;
  lstrcpyW(s_config_path, path);
  lstrcatW(s_config_path, L"mongoose.conf");
  return WideCharToMultiByte(CP_UTF8, 0, s_root_w, -1, s_root, sizeof(s_root), NULL, NULL) != 0;
}

static void load_settings(void) {
  char data[256] = {0}, *line, *next;
  DWORD read;
  HANDLE file = CreateFileW(s_config_path, GENERIC_READ, FILE_SHARE_READ, NULL, OPEN_EXISTING,
                            FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) return;
  ReadFile(file, data, sizeof(data) - 1, &read, NULL);
  CloseHandle(file);
  for (line = data; line && *line; line = next) {
    unsigned port = 0;
    next = strchr(line, '\n');
    if (next) *next++ = '\0';
    if (strncmp(line, "port=", 5) == 0) {
      char *p = line + 5;
      while (*p >= '0' && *p <= '9') port = port * 10 + (unsigned) (*p++ - '0');
      if (*p == '\r') p++;
      if (*p == '\0' && port > 0 && port <= 65535) s_settings.port = port;
    } else if (strncmp(line, "directory_listing=no", 20) == 0) s_settings.listing = FALSE;
    else if (strncmp(line, "directory_listing=yes", 21) == 0) s_settings.listing = TRUE;
  }
}

static BOOL save_settings(void) {
  char data[80];
  char *p = data;
  DWORD written;
  const char prefix[] = "port=";
  for (unsigned i = 0; i < sizeof(prefix) - 1; i++) *p++ = prefix[i];
  p = append_uint(p, s_settings.port);
  const char suffix[] = "\ndirectory_listing=";
  for (unsigned i = 0; i < sizeof(suffix) - 1; i++) *p++ = suffix[i];
  const char *value = s_settings.listing ? "yes\n" : "no\n";
  while (*value) *p++ = *value++;
  DWORD size = (DWORD) (p - data);
  HANDLE file = CreateFileW(s_config_path, GENERIC_WRITE, 0, NULL, CREATE_ALWAYS,
                            FILE_ATTRIBUTE_NORMAL, NULL);
  if (file == INVALID_HANDLE_VALUE) return FALSE;
  BOOL ok = WriteFile(file, data, size, &written, NULL) && written == size;
  CloseHandle(file);
  return ok;
}

#if defined(MG_CRINKLER)
extern const unsigned char mg_systray_ico[];
extern const unsigned int mg_systray_ico_size;

static HICON load_embedded_icon(void) {
  const unsigned char *p = mg_systray_ico;
  DWORD size, offset;
  if (mg_systray_ico_size < 22 || p[2] != 1 || p[3] != 0 || p[4] == 0) return NULL;
  size = (DWORD) p[14] | ((DWORD) p[15] << 8) | ((DWORD) p[16] << 16) | ((DWORD) p[17] << 24);
  offset = (DWORD) p[18] | ((DWORD) p[19] << 8) | ((DWORD) p[20] << 16) | ((DWORD) p[21] << 24);
  if (offset > mg_systray_ico_size || size > mg_systray_ico_size - offset) return NULL;
  return CreateIconFromResourceEx((PBYTE) p + offset, size, TRUE, 0x00030000,
                                  16, 16, LR_DEFAULTCOLOR);
}
#endif

static void http_handler(struct mg_connection *c, int ev, void *ev_data) {
  if (ev == MG_EV_HTTP_MSG) {
    struct mg_http_message *hm = (struct mg_http_message *) ev_data;
    const struct mg_http_serve_opts opts = {.root_dir = s_root, .enable_dir_listing = s_settings.listing};
    mg_http_serve_dir(c, hm, &opts);
  }
}

static BOOL listen_http(struct mg_mgr *mgr) {
  char url[64];
  const char prefix[] = "http://0.0.0.0:";
  char *p = url;
  for (unsigned i = 0; i < sizeof(prefix) - 1; i++) *p++ = prefix[i];
  *append_uint(p, s_settings.port) = '\0';
  return mg_http_listen(mgr, url, http_handler, NULL) != NULL;
}

static void show_system_error(void) {
  WCHAR text[256];
  FormatMessageW(FORMAT_MESSAGE_FROM_SYSTEM | FORMAT_MESSAGE_IGNORE_INSERTS, NULL,
                 GetLastError(), 0, text, sizeof(text) / sizeof(text[0]), NULL);
  MessageBoxW(NULL, text, L"Mongoose", MB_OK | MB_ICONERROR);
}

static BOOL service_installed(void) {
  SC_HANDLE scm = OpenSCManagerW(NULL, NULL, SC_MANAGER_CONNECT);
  SC_HANDLE service;
  BOOL found;
  if (!scm) return FALSE;
  service = OpenServiceW(scm, SERVICE_NAME, SERVICE_QUERY_STATUS);
  found = service != NULL;
  if (service) CloseServiceHandle(service);
  CloseServiceHandle(scm);
  return found;
}

static void manage_service(UINT command) {
  SC_HANDLE scm, service = NULL;
  DWORD access = command == ID_INSTALL_SERVICE ? SC_MANAGER_CREATE_SERVICE : SC_MANAGER_CONNECT;
  scm = OpenSCManagerW(NULL, NULL, access);
  if (!scm) return show_system_error();
  if (command == ID_INSTALL_SERVICE) {
    WCHAR path[MAX_PATH], binary[MAX_PATH + 32];
    if (!GetModuleFileNameW(NULL, path, MAX_PATH)) { CloseServiceHandle(scm); return show_system_error(); }
    WCHAR *p = binary;
    *p++ = L'"';
    for (const WCHAR *q = path; *q; q++) *p++ = *q;
    const WCHAR suffix[] = L"\" --service";
    for (unsigned i = 0; suffix[i]; i++) *p++ = suffix[i];
    *p = L'\0';
    service = CreateServiceW(scm, SERVICE_NAME, SERVICE_NAME, SERVICE_ALL_ACCESS,
                             SERVICE_WIN32_OWN_PROCESS, SERVICE_AUTO_START,
                             SERVICE_ERROR_NORMAL, binary, NULL, NULL, NULL, NULL, NULL);
  } else {
    service = OpenServiceW(scm, SERVICE_NAME, DELETE);
    if (service && !DeleteService(service)) { CloseServiceHandle(service); service = NULL; }
  }
  if (!service) show_system_error();
  else CloseServiceHandle(service);
  CloseServiceHandle(scm);
}

static INT_PTR CALLBACK settings_proc(HWND dlg, UINT msg, WPARAM wp, LPARAM lp) {
  (void) lp;
  if (msg == WM_CLOSE) { EndDialog(dlg, IDCANCEL); return TRUE; }
  if (msg == WM_INITDIALOG) {
    SetDlgItemInt(dlg, ID_PORT, s_settings.port, FALSE);
    SetDlgItemTextW(dlg, ID_ROOT, s_root_w);
    CheckDlgButton(dlg, ID_LISTING, s_settings.listing ? BST_CHECKED : BST_UNCHECKED);
    return TRUE;
  }
  if (msg == WM_COMMAND) {
    switch (LOWORD(wp)) {
      case ID_RESET:
        SetDlgItemInt(dlg, ID_PORT, HTTP_PORT, FALSE);
        CheckDlgButton(dlg, ID_LISTING, BST_CHECKED);
        return TRUE;
      case ID_SAVE: {
        BOOL valid;
        UINT port = GetDlgItemInt(dlg, ID_PORT, &valid, FALSE);
        if (!valid || port == 0 || port > 65535) {
          MessageBoxW(dlg, L"端口号必须在 1 到 65535 之间。", L"Mongoose settings", MB_OK | MB_ICONWARNING);
          return TRUE;
        }
        s_settings.port = port;
        s_settings.listing = IsDlgButtonChecked(dlg, ID_LISTING) == BST_CHECKED;
        if (!save_settings()) { show_system_error(); return TRUE; }
        s_restart = TRUE;
        EndDialog(dlg, ID_SAVE);
        return TRUE;
      }
    }
  }
  return FALSE;
}

static void show_settings(void) {
  if (DialogBoxParamW(GetModuleHandleW(NULL), MAKEINTRESOURCEW(IDD_SETTINGS),
                     s_window, settings_proc, 0) == -1)
    show_system_error();
}

static void show_tray_menu(void) {
  HMENU menu = CreatePopupMenu();
  POINT point;
  WCHAR title[80], status[80];
  BOOL installed = service_installed();
  if (!menu) return;
  lstrcpyW(title, L"Mongoose web server " APP_VERSION);
  lstrcpyW(status, installed ? L"NT service: installed" : L"NT service: not installed");
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 1, title);
  AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
  AppendMenuW(menu, MF_STRING | MF_GRAYED, 2, status);
  AppendMenuW(menu, MF_STRING | (installed ? MF_GRAYED : 0), ID_INSTALL_SERVICE, L"Install service");
  AppendMenuW(menu, MF_STRING | (!installed ? MF_GRAYED : 0), ID_REMOVE_SERVICE, L"Deinstall service");
  AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
  AppendMenuW(menu, MF_STRING, ID_CONNECT, L"Start browser");
  AppendMenuW(menu, MF_STRING, ID_SETTINGS, L"Edit Settings");
  AppendMenuW(menu, MF_SEPARATOR, 0, NULL);
  AppendMenuW(menu, MF_STRING, ID_QUIT, L"Exit");
  GetCursorPos(&point);
  SetForegroundWindow(s_window);
  UINT command = TrackPopupMenu(menu, TPM_RETURNCMD | TPM_NONOTIFY, point.x, point.y, 0, s_window, NULL);
  PostMessageW(s_window, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (command == ID_CONNECT) {
    WCHAR url[64];
    const WCHAR prefix[] = L"http://127.0.0.1:";
    WCHAR *p = url;
    for (unsigned i = 0; prefix[i]; i++) *p++ = prefix[i];
    p = append_uint_w(p, s_settings.port);
    *p++ = L'/'; *p = L'\0';
    ShellExecuteW(NULL, L"open", url, NULL, NULL, SW_SHOWNORMAL);
  } else if (command == ID_SETTINGS) show_settings();
  else if (command == ID_INSTALL_SERVICE || command == ID_REMOVE_SERVICE) manage_service(command);
  else if (command == ID_QUIT) DestroyWindow(s_window);
}

static LRESULT CALLBACK tray_proc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
  if (msg == WM_TRAY) {
    if (lp == WM_RBUTTONUP || lp == WM_LBUTTONUP || lp == WM_LBUTTONDBLCLK) show_tray_menu();
    return 0;
  }
  if (msg == WM_CLOSE) { DestroyWindow(hwnd); return 0; }
  if (msg == WM_DESTROY) { PostQuitMessage(0); return 0; }
  if (s_taskbar_created && msg == s_taskbar_created) Shell_NotifyIconW(NIM_ADD, &s_icon);
  return DefWindowProcW(hwnd, msg, wp, lp);
}

static BOOL create_tray(void) {
  WNDCLASSW wc = {0};
  wc.lpfnWndProc = tray_proc;
  wc.hInstance = GetModuleHandleW(NULL);
#if defined(MG_CRINKLER)
  wc.hIcon = load_embedded_icon();
#else
  wc.hIcon = (HICON) LoadImageW(GetModuleHandleW(NULL), MAKEINTRESOURCEW(100), IMAGE_ICON,
                               16, 16, LR_DEFAULTCOLOR);
#endif
  if (!wc.hIcon) return FALSE;
  wc.lpszClassName = L"MongooseWebServer";
  s_taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
  if (!RegisterClassW(&wc) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) return FALSE;
  s_window = CreateWindowW(wc.lpszClassName, L"Mongoose", WS_OVERLAPPEDWINDOW,
                           0, 0, 0, 0, NULL, NULL, wc.hInstance, NULL);
  if (!s_window) return FALSE;
  s_icon.cbSize = sizeof(s_icon);
  s_icon.hWnd = s_window;
  s_icon.uID = 100;
  s_icon.uFlags = NIF_ICON | NIF_MESSAGE | NIF_TIP;
  s_icon.hIcon = wc.hIcon;
  s_icon.uCallbackMessage = WM_TRAY;
  lstrcpynW(s_icon.szTip, L"Mongoose web server", sizeof(s_icon.szTip) / sizeof(s_icon.szTip[0]));
  if (!Shell_NotifyIconW(NIM_ADD, &s_icon)) {
    DestroyWindow(s_window); s_window = NULL;
    DestroyIcon(wc.hIcon);
    return FALSE;
  }
  return TRUE;
}

static int run_server(BOOL tray) {
  struct mg_mgr mgr;
  if (!resolve_paths()) {
    if (tray) MessageBoxW(NULL, L"Cannot find the executable directory.", L"Mongoose", MB_OK | MB_ICONERROR);
    return 1;
  }
  load_settings();
  mg_mgr_init(&mgr);
  if (!listen_http(&mgr)) { mg_mgr_free(&mgr); if (tray) MessageBoxW(NULL, L"Failed to start HTTP server.", L"Mongoose", MB_OK | MB_ICONERROR); return 1; }
  if (tray && !create_tray()) { mg_mgr_free(&mgr); return 1; }
  while (!InterlockedCompareExchange(&s_stop, 0, 0)) {
    if (tray) {
      MSG msg;
      while (PeekMessageW(&msg, NULL, 0, 0, PM_REMOVE)) {
        if (msg.message == WM_QUIT) InterlockedExchange(&s_stop, 1);
        else { TranslateMessage(&msg); DispatchMessageW(&msg); }
      }
      if (s_restart) {
        s_restart = FALSE;
        mg_mgr_free(&mgr);
        mg_mgr_init(&mgr);
        if (!listen_http(&mgr)) {
          MessageBoxW(NULL, L"Failed to restart HTTP server with the new settings.", L"Mongoose", MB_OK | MB_ICONERROR);
          InterlockedExchange(&s_stop, 1);
        }
      }
    }
    if (!InterlockedCompareExchange(&s_stop, 0, 0)) mg_mgr_poll(&mgr, 100);
  }
  if (tray) {
    Shell_NotifyIconW(NIM_DELETE, &s_icon);
    DestroyWindow(s_window); s_window = NULL;
    DestroyIcon(s_icon.hIcon);
  }
  mg_mgr_free(&mgr);
  return 0;
}

static void WINAPI service_control(DWORD code) {
  if (code == SERVICE_CONTROL_STOP || code == SERVICE_CONTROL_SHUTDOWN) {
    s_service_status.dwCurrentState = SERVICE_STOP_PENDING;
    SetServiceStatus(s_service_handle, &s_service_status);
    InterlockedExchange(&s_stop, 1);
  }
}

static void WINAPI service_main(DWORD argc, LPWSTR *argv) {
  (void) argc; (void) argv;
  s_service_handle = RegisterServiceCtrlHandlerW(SERVICE_NAME, service_control);
  if (!s_service_handle) return;
  s_service_status.dwServiceType = SERVICE_WIN32_OWN_PROCESS;
  s_service_status.dwControlsAccepted = SERVICE_ACCEPT_STOP | SERVICE_ACCEPT_SHUTDOWN;
  s_service_status.dwCurrentState = SERVICE_START_PENDING;
  SetServiceStatus(s_service_handle, &s_service_status);
  DWORD result = (DWORD) run_server(FALSE);
  s_service_status.dwCurrentState = SERVICE_STOPPED;
  s_service_status.dwWin32ExitCode = result ? ERROR_SERVICE_SPECIFIC_ERROR : NO_ERROR;
  SetServiceStatus(s_service_handle, &s_service_status);
}

static BOOL service_argument(void) {
  const WCHAR *p = GetCommandLineW();
  if (*p == L'"') {
    for (p++; *p && *p != L'"'; p++) {}
    if (*p) p++;
  } else {
    while (*p && *p != L' ' && *p != L'\t') p++;
  }
  while (*p == L' ' || *p == L'\t') p++;
  const WCHAR option[] = L"--service";
  unsigned i = 0;
  while (option[i] && p[i] == option[i]) i++;
  return !option[i] && (p[i] == L'\0' || p[i] == L' ' || p[i] == L'\t');
}

static int app_entry(void) {
  BOOL service = service_argument();
  InterlockedExchange(&s_stop, 0);
  if (service) {
    SERVICE_TABLE_ENTRYW table[] = {{(LPWSTR) SERVICE_NAME, service_main}, {NULL, NULL}};
    return StartServiceCtrlDispatcherW(table) ? 0 : 1;
  }
  return run_server(TRUE);
}

int WINAPI WinMain(HINSTANCE instance, HINSTANCE previous, LPSTR command_line, int show) {
  (void) instance; (void) previous; (void) command_line; (void) show;
  return app_entry();
}

#if defined(MG_CRINKLER)
void CrinklerEntry(void) {
  ExitProcess((UINT) app_entry());
}
#endif
