#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdio.h>
#include <wchar.h>

#define PATH_BUFFER_CHARS 32768
#define COMMAND_BUFFER_CHARS 32768

static int file_exists(const wchar_t *path) {
    DWORD attributes = GetFileAttributesW(path);
    return attributes != INVALID_FILE_ATTRIBUTES &&
           (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

static int directory_from_path(wchar_t *path) {
    wchar_t *separator = wcsrchr(path, L'\\');
    if (separator == NULL) {
        return 0;
    }
    *separator = L'\0';
    return 1;
}

static int make_candidate(wchar_t *output, size_t output_count,
                          const wchar_t *base, const wchar_t *relative) {
    int written = _snwprintf_s(output, output_count, _TRUNCATE,
                               L"%ls\\%ls", base, relative);
    return written >= 0 && file_exists(output);
}

static int find_gui_script(const wchar_t *launcher_directory,
                           wchar_t *script_path, size_t script_path_count) {
    static const wchar_t *relative_paths[] = {
        L"QQ-Silk-Converter-GUI.ps1",
        L"scripts\\QQ-Silk-Converter-GUI.ps1",
        L"..\\scripts\\QQ-Silk-Converter-GUI.ps1",
        L"..\\..\\scripts\\QQ-Silk-Converter-GUI.ps1"
    };
    size_t index;

    for (index = 0; index < sizeof(relative_paths) / sizeof(relative_paths[0]); ++index) {
        wchar_t candidate[PATH_BUFFER_CHARS];
        wchar_t canonical[PATH_BUFFER_CHARS];
        DWORD canonical_length;
        if (!make_candidate(candidate, PATH_BUFFER_CHARS,
                            launcher_directory, relative_paths[index])) {
            continue;
        }
        canonical_length = GetFullPathNameW(candidate, PATH_BUFFER_CHARS,
                                            canonical, NULL);
        if (canonical_length == 0 || canonical_length >= PATH_BUFFER_CHARS) {
            continue;
        }
        if (wcsncpy_s(script_path, script_path_count, canonical, _TRUNCATE) == 0) {
            return 1;
        }
    }
    return 0;
}

static void show_error(const wchar_t *message) {
    MessageBoxW(NULL, message, L"QQ / WeChat SILK Voice Converter",
                MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous_instance,
                    PWSTR command_line, int show_command) {
    wchar_t launcher_path[PATH_BUFFER_CHARS];
    wchar_t launcher_directory[PATH_BUFFER_CHARS];
    wchar_t gui_script[PATH_BUFFER_CHARS];
    wchar_t windows_directory[PATH_BUFFER_CHARS];
    wchar_t powershell_path[PATH_BUFFER_CHARS];
    wchar_t child_command[COMMAND_BUFFER_CHARS];
    STARTUPINFOW startup_info;
    PROCESS_INFORMATION process_info;
    DWORD wait_result;
    DWORD exit_code = 0;
    DWORD path_length;
    int self_test;
    int written;

    (void)instance;
    (void)previous_instance;
    (void)show_command;

    path_length = GetModuleFileNameW(NULL, launcher_path, PATH_BUFFER_CHARS);
    if (path_length == 0 || path_length >= PATH_BUFFER_CHARS ||
        wcsncpy_s(launcher_directory, PATH_BUFFER_CHARS,
                  launcher_path, _TRUNCATE) != 0 ||
        !directory_from_path(launcher_directory)) {
        show_error(L"无法确定启动器目录。\nCould not determine the launcher directory.");
        return 2;
    }
    if (!find_gui_script(launcher_directory, gui_script, PATH_BUFFER_CHARS)) {
        show_error(L"未找到 QQ-Silk-Converter-GUI.ps1。\n"
                   L"请完整解压 Release ZIP 后再启动。\n\n"
                   L"QQ-Silk-Converter-GUI.ps1 was not found.\n"
                   L"Please extract the complete Release ZIP.");
        return 2;
    }
    path_length = GetWindowsDirectoryW(windows_directory, PATH_BUFFER_CHARS);
    if (path_length == 0 || path_length >= PATH_BUFFER_CHARS) {
        show_error(L"无法确定 Windows 目录。\nCould not determine the Windows directory.");
        return 2;
    }
    written = _snwprintf_s(powershell_path, PATH_BUFFER_CHARS, _TRUNCATE,
                           L"%ls\\System32\\WindowsPowerShell\\v1.0\\powershell.exe",
                           windows_directory);
    if (written < 0 || !file_exists(powershell_path)) {
        show_error(L"未找到 Windows PowerShell。\nWindows PowerShell was not found.");
        return 2;
    }

    self_test = command_line != NULL && wcscmp(command_line, L"--self-test") == 0;
    written = _snwprintf_s(
        child_command, COMMAND_BUFFER_CHARS, _TRUNCATE,
        L"\"%ls\" -NoLogo -NoProfile -ExecutionPolicy Bypass -STA -File \"%ls\"%ls",
        powershell_path, gui_script, self_test ? L" -SelfTest" : L"");
    if (written < 0) {
        show_error(L"启动命令过长。\nThe launch command is too long.");
        return 2;
    }

    ZeroMemory(&startup_info, sizeof(startup_info));
    startup_info.cb = sizeof(startup_info);
    ZeroMemory(&process_info, sizeof(process_info));
    if (!CreateProcessW(powershell_path, child_command, NULL, NULL, FALSE,
                        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
                        NULL, launcher_directory, &startup_info, &process_info)) {
        wchar_t error_message[512];
        DWORD error_code = GetLastError();
        _snwprintf_s(error_message, 512, _TRUNCATE,
                     L"无法启动转换器（Windows 错误 %lu）。\n"
                     L"Could not start the converter (Windows error %lu).",
                     error_code, error_code);
        show_error(error_message);
        return 2;
    }

    wait_result = WaitForSingleObject(process_info.hProcess,
                                      self_test ? INFINITE : 2000);
    if (wait_result == WAIT_OBJECT_0) {
        if (!GetExitCodeProcess(process_info.hProcess, &exit_code)) {
            exit_code = 1;
        }
        if (exit_code != 0 && !self_test) {
            wchar_t error_message[512];
            _snwprintf_s(error_message, 512, _TRUNCATE,
                         L"转换器启动失败（退出代码 %lu）。\n"
                         L"The converter failed to start (exit code %lu).",
                         exit_code, exit_code);
            show_error(error_message);
        }
    }

    CloseHandle(process_info.hThread);
    CloseHandle(process_info.hProcess);
    return wait_result == WAIT_OBJECT_0 ? (int)exit_code : 0;
}
