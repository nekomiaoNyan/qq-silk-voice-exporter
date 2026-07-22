#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <audioclient.h>
#include <conio.h>
#include <mmdeviceapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

#if defined(__has_include)
#if __has_include(<audioclientactivationparams.h>)
#include <audioclientactivationparams.h>
#define QQ_HAS_AUDIOCLIENT_ACTIVATION_PARAMS 1
#endif
#endif

#ifndef QQ_HAS_AUDIOCLIENT_ACTIVATION_PARAMS
typedef enum AUDIOCLIENT_ACTIVATION_TYPE {
    AUDIOCLIENT_ACTIVATION_TYPE_DEFAULT = 0,
    AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK = 1
} AUDIOCLIENT_ACTIVATION_TYPE;

typedef enum PROCESS_LOOPBACK_MODE {
    PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE = 0,
    PROCESS_LOOPBACK_MODE_EXCLUDE_TARGET_PROCESS_TREE = 1
} PROCESS_LOOPBACK_MODE;

typedef struct AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS {
    DWORD TargetProcessId;
    PROCESS_LOOPBACK_MODE ProcessLoopbackMode;
} AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS;

typedef struct AUDIOCLIENT_ACTIVATION_PARAMS {
    AUDIOCLIENT_ACTIVATION_TYPE ActivationType;
    union {
        AUDIOCLIENT_PROCESS_LOOPBACK_PARAMS ProcessLoopbackParams;
    } DUMMYUNIONNAME;
} AUDIOCLIENT_ACTIVATION_PARAMS;
#endif

#ifndef VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK
#define VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK L"VAD\\Process_Loopback"
#endif

static const GUID g_iid_unknown = {
    0x00000000, 0x0000, 0x0000, {0xc0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46}
};
static const GUID g_iid_audio_client = {
    0x1cb9ad4c, 0xdbfa, 0x4c32, {0xb1, 0x78, 0xc2, 0xf5, 0x68, 0xa7, 0x03, 0xb2}
};
static const GUID g_iid_audio_capture_client = {
    0xc8adbd64, 0xe71e, 0x48a0, {0xa4, 0xde, 0x18, 0x5c, 0x39, 0x5c, 0xd3, 0x17}
};
static const GUID g_iid_device_enumerator = {
    0xa95664d2, 0x9614, 0x4f35, {0xa7, 0x46, 0xde, 0x8d, 0xb6, 0x36, 0x17, 0xe6}
};
static const GUID g_iid_activation_completion_handler = {
    0x41d949ab, 0x9862, 0x444a, {0x80, 0xf6, 0xc2, 0x61, 0x33, 0x4d, 0xa5, 0xeb}
};
static const GUID g_clsid_device_enumerator = {
    0xbcde0395, 0xe52f, 0x467c, {0x8e, 0x3d, 0xc4, 0x57, 0x92, 0x91, 0x69, 0x2e}
};

static volatile LONG g_stop_requested = 0;

typedef struct WavWriter {
    FILE *file;
    __int64 riff_size_offset;
    __int64 data_size_offset;
    uint64_t data_bytes;
} WavWriter;

static BOOL WINAPI console_handler(DWORD signal_type) {
    if (signal_type == CTRL_C_EVENT || signal_type == CTRL_BREAK_EVENT ||
        signal_type == CTRL_CLOSE_EVENT || signal_type == CTRL_SHUTDOWN_EVENT) {
        InterlockedExchange(&g_stop_requested, 1);
        return TRUE;
    }
    return FALSE;
}

static int write_bytes(FILE *file, const void *data, size_t size) {
    return size == 0 || fwrite(data, 1, size, file) == size;
}

static int write_u32(FILE *file, uint32_t value) {
    unsigned char bytes[4] = {
        (unsigned char)(value & 0xffu),
        (unsigned char)((value >> 8) & 0xffu),
        (unsigned char)((value >> 16) & 0xffu),
        (unsigned char)((value >> 24) & 0xffu)
    };
    return write_bytes(file, bytes, sizeof(bytes));
}

static int wav_open(WavWriter *writer, const wchar_t *path, const WAVEFORMATEX *format) {
    uint32_t format_size;

    ZeroMemory(writer, sizeof(*writer));
    if (_wfopen_s(&writer->file, path, L"w+b") != 0 || writer->file == NULL) {
        fwprintf(stderr, L"Could not create output file: %ls\n", path);
        return 0;
    }

    format_size = 18u + (uint32_t)format->cbSize;
    if (!write_bytes(writer->file, "RIFF", 4)) {
        goto fail;
    }
    writer->riff_size_offset = _ftelli64(writer->file);
    if (!write_u32(writer->file, 0) ||
        !write_bytes(writer->file, "WAVEfmt ", 8) ||
        !write_u32(writer->file, format_size) ||
        !write_bytes(writer->file, format, format_size)) {
        goto fail;
    }
    if ((format_size & 1u) != 0u && fputc(0, writer->file) == EOF) {
        goto fail;
    }
    if (!write_bytes(writer->file, "data", 4)) {
        goto fail;
    }
    writer->data_size_offset = _ftelli64(writer->file);
    if (!write_u32(writer->file, 0)) {
        goto fail;
    }
    return 1;

fail:
    (void)fclose(writer->file);
    writer->file = NULL;
    (void)_wremove(path);
    return 0;
}

static int wav_write(WavWriter *writer, const BYTE *data, size_t size, int silent) {
    static const unsigned char zeros[4096] = {0};
    size_t remaining = size;

    if (writer->data_bytes + (uint64_t)size > UINT32_MAX) {
        fputs("Recording is too large for a standard WAV file (4 GiB limit).\n", stderr);
        return 0;
    }
    if (!silent) {
        if (!write_bytes(writer->file, data, size)) {
            return 0;
        }
    } else {
        while (remaining > 0) {
            size_t chunk = remaining < sizeof(zeros) ? remaining : sizeof(zeros);
            if (!write_bytes(writer->file, zeros, chunk)) {
                return 0;
            }
            remaining -= chunk;
        }
    }
    writer->data_bytes += (uint64_t)size;
    return 1;
}

static int wav_close(WavWriter *writer) {
    uint32_t data_size;
    uint32_t riff_size;
    __int64 end_position;
    int ok = 1;

    if (writer->file == NULL) {
        return 1;
    }

    data_size = (uint32_t)writer->data_bytes;
    if ((data_size & 1u) != 0u && fputc(0, writer->file) == EOF) {
        ok = 0;
    }
    end_position = _ftelli64(writer->file);
    if (end_position < 8 || (uint64_t)(end_position - 8) > UINT32_MAX) {
        ok = 0;
    }
    riff_size = ok ? (uint32_t)(end_position - 8) : 0;

    if (ok && (_fseeki64(writer->file, writer->data_size_offset, SEEK_SET) != 0 ||
               !write_u32(writer->file, data_size) ||
               _fseeki64(writer->file, writer->riff_size_offset, SEEK_SET) != 0 ||
               !write_u32(writer->file, riff_size))) {
        ok = 0;
    }
    if (fclose(writer->file) != 0) {
        ok = 0;
    }
    writer->file = NULL;
    return ok;
}

static int stdin_requests_stop(void) {
    HANDLE input = GetStdHandle(STD_INPUT_HANDLE);
    DWORD type;

    if (input == NULL || input == INVALID_HANDLE_VALUE) {
        return 0;
    }
    type = GetFileType(input);
    if (type == FILE_TYPE_PIPE) {
        DWORD available = 0;
        unsigned char byte;
        DWORD read_count = 0;
        if (!PeekNamedPipe(input, NULL, 0, NULL, &available, NULL)) {
            return GetLastError() == ERROR_BROKEN_PIPE;
        }
        if (available > 0 && ReadFile(input, &byte, 1, &read_count, NULL)) {
            return read_count > 0;
        }
    } else if (type == FILE_TYPE_CHAR && _kbhit()) {
        (void)_getch();
        return 1;
    }
    return 0;
}

static void print_hresult(const char *operation, HRESULT result) {
    fprintf(stderr, "%s failed (HRESULT 0x%08lx).\n", operation, (unsigned long)result);
}

typedef struct ActivationHandler {
    IActivateAudioInterfaceCompletionHandler interface_value;
    LONG reference_count;
    HANDLE completed_event;
    HRESULT activation_result;
    IAudioClient *audio_client;
    IUnknown *free_threaded_marshaler;
} ActivationHandler;

static ActivationHandler *activation_handler_from_interface(
    IActivateAudioInterfaceCompletionHandler *interface_value) {
    return CONTAINING_RECORD(interface_value, ActivationHandler, interface_value);
}

static HRESULT STDMETHODCALLTYPE activation_handler_query_interface(
    IActivateAudioInterfaceCompletionHandler *interface_value,
    REFIID interface_id,
    void **object) {
    ActivationHandler *handler = activation_handler_from_interface(interface_value);

    if (object == NULL) {
        return E_POINTER;
    }
    *object = NULL;
    if (IsEqualIID(interface_id, &g_iid_unknown) ||
        IsEqualIID(interface_id, &g_iid_activation_completion_handler)) {
        *object = interface_value;
        (void)IActivateAudioInterfaceCompletionHandler_AddRef(interface_value);
        return S_OK;
    }
    if (handler->free_threaded_marshaler != NULL) {
        return IUnknown_QueryInterface(handler->free_threaded_marshaler,
                                       interface_id, object);
    }
    return E_NOINTERFACE;
}

static ULONG STDMETHODCALLTYPE activation_handler_add_ref(
    IActivateAudioInterfaceCompletionHandler *interface_value) {
    ActivationHandler *handler = activation_handler_from_interface(interface_value);
    return (ULONG)InterlockedIncrement(&handler->reference_count);
}

static ULONG STDMETHODCALLTYPE activation_handler_release(
    IActivateAudioInterfaceCompletionHandler *interface_value) {
    ActivationHandler *handler = activation_handler_from_interface(interface_value);
    LONG remaining = InterlockedDecrement(&handler->reference_count);

    if (remaining == 0) {
        if (handler->audio_client != NULL) {
            IAudioClient_Release(handler->audio_client);
        }
        if (handler->free_threaded_marshaler != NULL) {
            IUnknown_Release(handler->free_threaded_marshaler);
        }
        if (handler->completed_event != NULL) {
            CloseHandle(handler->completed_event);
        }
        HeapFree(GetProcessHeap(), 0, handler);
    }
    return (ULONG)remaining;
}

static HRESULT STDMETHODCALLTYPE activation_handler_completed(
    IActivateAudioInterfaceCompletionHandler *interface_value,
    IActivateAudioInterfaceAsyncOperation *operation) {
    ActivationHandler *handler = activation_handler_from_interface(interface_value);
    IUnknown *activated_interface = NULL;
    HRESULT operation_result = E_UNEXPECTED;
    HRESULT result;

    result = IActivateAudioInterfaceAsyncOperation_GetActivateResult(
        operation, &operation_result, &activated_interface);
    if (SUCCEEDED(result)) {
        result = operation_result;
    }
    if (SUCCEEDED(result)) {
        result = IUnknown_QueryInterface(activated_interface, &g_iid_audio_client,
                                         (void **)&handler->audio_client);
    }
    if (activated_interface != NULL) {
        IUnknown_Release(activated_interface);
    }
    handler->activation_result = result;
    SetEvent(handler->completed_event);
    return S_OK;
}

static IActivateAudioInterfaceCompletionHandlerVtbl g_activation_handler_vtable = {
    activation_handler_query_interface,
    activation_handler_add_ref,
    activation_handler_release,
    activation_handler_completed
};

static ActivationHandler *activation_handler_create(void) {
    ActivationHandler *handler = (ActivationHandler *)HeapAlloc(
        GetProcessHeap(), HEAP_ZERO_MEMORY, sizeof(*handler));
    HRESULT result;

    if (handler == NULL) {
        return NULL;
    }
    handler->interface_value.lpVtbl = &g_activation_handler_vtable;
    handler->reference_count = 1;
    handler->activation_result = E_PENDING;
    handler->completed_event = CreateEventW(NULL, TRUE, FALSE, NULL);
    if (handler->completed_event == NULL) {
        HeapFree(GetProcessHeap(), 0, handler);
        return NULL;
    }
    result = CoCreateFreeThreadedMarshaler(
        (IUnknown *)&handler->interface_value, &handler->free_threaded_marshaler);
    if (FAILED(result)) {
        CloseHandle(handler->completed_event);
        HeapFree(GetProcessHeap(), 0, handler);
        return NULL;
    }
    return handler;
}

static HRESULT activate_process_audio_client(DWORD process_id,
                                               IAudioClient **audio_client) {
    AUDIOCLIENT_ACTIVATION_PARAMS activation_parameters;
    PROPVARIANT activation_variant;
    ActivationHandler *handler = NULL;
    IActivateAudioInterfaceAsyncOperation *operation = NULL;
    HRESULT result;

    *audio_client = NULL;
    handler = activation_handler_create();
    if (handler == NULL) {
        return E_OUTOFMEMORY;
    }

    ZeroMemory(&activation_parameters, sizeof(activation_parameters));
    activation_parameters.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
    activation_parameters.ProcessLoopbackParams.TargetProcessId = process_id;
    activation_parameters.ProcessLoopbackParams.ProcessLoopbackMode =
        PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;

    ZeroMemory(&activation_variant, sizeof(activation_variant));
    activation_variant.vt = VT_BLOB;
    activation_variant.blob.cbSize = sizeof(activation_parameters);
    activation_variant.blob.pBlobData = (BYTE *)&activation_parameters;

    result = ActivateAudioInterfaceAsync(
        VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
        &g_iid_audio_client,
        &activation_variant,
        &handler->interface_value,
        &operation);
    if (SUCCEEDED(result)) {
        DWORD wait_result = WaitForSingleObject(handler->completed_event, INFINITE);
        if (wait_result != WAIT_OBJECT_0) {
            result = HRESULT_FROM_WIN32(GetLastError());
        } else {
            result = handler->activation_result;
        }
    }
    if (operation != NULL) {
        IActivateAudioInterfaceAsyncOperation_Release(operation);
    }
    if (SUCCEEDED(result) && handler->audio_client != NULL) {
        *audio_client = handler->audio_client;
        handler->audio_client = NULL;
    } else if (SUCCEEDED(result)) {
        result = E_UNEXPECTED;
    }
    IActivateAudioInterfaceCompletionHandler_Release(&handler->interface_value);
    return result;
}

static int record_loopback(const wchar_t *output_path, DWORD maximum_seconds,
                           DWORD process_id) {
    HRESULT result;
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDevice *device = NULL;
    IAudioClient *audio_client = NULL;
    IAudioCaptureClient *capture_client = NULL;
    WAVEFORMATEX *mix_format = NULL;
    WAVEFORMATEX process_format;
    WavWriter writer;
    ULONGLONG start_tick;
    int free_mix_format = 0;
    int writer_open = 0;
    int started = 0;
    int ok = 0;

    ZeroMemory(&writer, sizeof(writer));
    result = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(result)) {
        print_hresult("CoInitializeEx", result);
        return 1;
    }

    if (process_id != 0) {
        result = activate_process_audio_client(process_id, &audio_client);
        if (FAILED(result)) {
            print_hresult("Activate process-only loopback recording", result);
            fputs("Process-only recording requires Windows build 20348 or later and a running target process.\n"
                  "Select the system-audio compatibility mode if this Windows version does not support it.\n",
                  stderr);
            goto cleanup;
        }
        ZeroMemory(&process_format, sizeof(process_format));
        process_format.wFormatTag = WAVE_FORMAT_PCM;
        process_format.nChannels = 2;
        process_format.nSamplesPerSec = 44100;
        process_format.wBitsPerSample = 16;
        process_format.nBlockAlign = 4;
        process_format.nAvgBytesPerSec = 176400;
        mix_format = &process_format;
        result = IAudioClient_Initialize(
            audio_client, AUDCLNT_SHAREMODE_SHARED,
            AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
            0, 0, mix_format, NULL);
    } else {
        result = CoCreateInstance(&g_clsid_device_enumerator, NULL, CLSCTX_ALL,
                                  &g_iid_device_enumerator, (void **)&enumerator);
        if (FAILED(result)) {
            print_hresult("Create audio device enumerator", result);
            goto cleanup;
        }
        result = IMMDeviceEnumerator_GetDefaultAudioEndpoint(enumerator, eRender, eConsole, &device);
        if (FAILED(result)) {
            print_hresult("Open default playback device", result);
            goto cleanup;
        }
        result = IMMDevice_Activate(device, &g_iid_audio_client, CLSCTX_ALL, NULL,
                                   (void **)&audio_client);
        if (FAILED(result)) {
            print_hresult("Activate Windows audio client", result);
            goto cleanup;
        }
        result = IAudioClient_GetMixFormat(audio_client, &mix_format);
        if (FAILED(result)) {
            print_hresult("Read playback mix format", result);
            goto cleanup;
        }
        free_mix_format = 1;
        result = IAudioClient_Initialize(audio_client, AUDCLNT_SHAREMODE_SHARED,
                                         AUDCLNT_STREAMFLAGS_LOOPBACK,
                                         10000000, 0, mix_format, NULL);
    }
    if (FAILED(result)) {
        print_hresult("Initialize loopback recording", result);
        goto cleanup;
    }
    result = IAudioClient_GetService(audio_client, &g_iid_audio_capture_client,
                                     (void **)&capture_client);
    if (FAILED(result)) {
        print_hresult("Open loopback capture service", result);
        goto cleanup;
    }
    if (!wav_open(&writer, output_path, mix_format)) {
        goto cleanup;
    }
    writer_open = 1;

    result = IAudioClient_Start(audio_client);
    if (FAILED(result)) {
        print_hresult("Start loopback recording", result);
        goto cleanup;
    }
    started = 1;
    start_tick = GetTickCount64();
    SetConsoleCtrlHandler(console_handler, TRUE);
    fputs("READY\n", stdout);
    fflush(stdout);

    while (InterlockedCompareExchange(&g_stop_requested, 0, 0) == 0) {
        UINT32 packet_frames = 0;

        if (stdin_requests_stop()) {
            break;
        }
        if (maximum_seconds > 0 &&
            GetTickCount64() - start_tick >= (ULONGLONG)maximum_seconds * 1000u) {
            break;
        }

        result = IAudioCaptureClient_GetNextPacketSize(capture_client, &packet_frames);
        if (FAILED(result)) {
            print_hresult("Read loopback packet size", result);
            goto cleanup;
        }
        while (packet_frames > 0) {
            BYTE *data = NULL;
            UINT32 frames = 0;
            DWORD flags = 0;
            size_t byte_count;

            result = IAudioCaptureClient_GetBuffer(capture_client, &data, &frames,
                                                    &flags, NULL, NULL);
            if (FAILED(result)) {
                print_hresult("Read loopback packet", result);
                goto cleanup;
            }
            byte_count = (size_t)frames * mix_format->nBlockAlign;
            if (!wav_write(&writer, data, byte_count,
                           (flags & AUDCLNT_BUFFERFLAGS_SILENT) != 0)) {
                (void)IAudioCaptureClient_ReleaseBuffer(capture_client, frames);
                fputs("Could not write recorded audio.\n", stderr);
                goto cleanup;
            }
            result = IAudioCaptureClient_ReleaseBuffer(capture_client, frames);
            if (FAILED(result)) {
                print_hresult("Release loopback packet", result);
                goto cleanup;
            }
            result = IAudioCaptureClient_GetNextPacketSize(capture_client, &packet_frames);
            if (FAILED(result)) {
                print_hresult("Read loopback packet size", result);
                goto cleanup;
            }
        }
        Sleep(10);
    }
    ok = 1;

cleanup:
    if (started) {
        (void)IAudioClient_Stop(audio_client);
    }
    if (writer_open && !wav_close(&writer)) {
        fputs("Could not finalize the WAV file.\n", stderr);
        ok = 0;
    }
    if (!ok && writer_open) {
        (void)_wremove(output_path);
    }
    if (capture_client != NULL) {
        IAudioCaptureClient_Release(capture_client);
    }
    if (free_mix_format && mix_format != NULL) {
        CoTaskMemFree(mix_format);
    }
    if (audio_client != NULL) {
        IAudioClient_Release(audio_client);
    }
    if (device != NULL) {
        IMMDevice_Release(device);
    }
    if (enumerator != NULL) {
        IMMDeviceEnumerator_Release(enumerator);
    }
    CoUninitialize();

    if (ok) {
        wprintf(L"SAVED %ls\n", output_path);
        return 0;
    }
    return 1;
}

static int self_test(const wchar_t *output_path) {
    WAVEFORMATEX format;
    WavWriter writer;
    unsigned char silence[160] = {0};

    ZeroMemory(&format, sizeof(format));
    format.wFormatTag = WAVE_FORMAT_PCM;
    format.nChannels = 1;
    format.nSamplesPerSec = 8000;
    format.wBitsPerSample = 16;
    format.nBlockAlign = 2;
    format.nAvgBytesPerSec = 16000;
    format.cbSize = 0;
    if (!wav_open(&writer, output_path, &format) ||
        !wav_write(&writer, silence, sizeof(silence), 0) ||
        !wav_close(&writer)) {
        if (writer.file != NULL) {
            (void)fclose(writer.file);
        }
        (void)_wremove(output_path);
        return 1;
    }
    return 0;
}

static void usage(void) {
    fputws(L"WeChat playback recorder (local WASAPI loopback)\n\n"
           L"Usage:\n"
           L"  wechat-record.exe record <output.wav> [--seconds N]\n"
           L"  wechat-record.exe record-process <pid> <output.wav> [--seconds N]\n"
           L"  wechat-record.exe self-test <output.wav>\n\n"
           L"record-process captures only the target process and its child processes on\n"
           L"Windows build 20348 or later. record captures the complete system audio mix.\n"
           L"Start recording, play a voice message in WeChat, then press Enter to stop.\n"
           L"It does not read WeChat files, databases, process memory, or encryption keys.\n",
           stderr);
}

int wmain(int argc, wchar_t **argv) {
    DWORD seconds = 0;
    DWORD process_id = 0;
    const wchar_t *output_path;
    int option_index;

    if (argc < 2) {
        usage();
        return 2;
    }
    if (argc == 3 && wcscmp(argv[1], L"self-test") == 0) {
        return self_test(argv[2]);
    }
    if (wcscmp(argv[1], L"record") == 0 && (argc == 3 || argc == 5)) {
        output_path = argv[2];
        option_index = 3;
    } else if (wcscmp(argv[1], L"record-process") == 0 &&
               (argc == 4 || argc == 6)) {
        wchar_t *end = NULL;
        unsigned long parsed = wcstoul(argv[2], &end, 10);
        if (end == argv[2] || *end != L'\0' || parsed == 0 || parsed > UINT32_MAX) {
            fputs("pid must be a positive 32-bit process ID.\n", stderr);
            return 2;
        }
        process_id = (DWORD)parsed;
        output_path = argv[3];
        option_index = 4;
    } else {
        usage();
        return 2;
    }
    if (argc > option_index) {
        wchar_t *end = NULL;
        unsigned long parsed;
        if (wcscmp(argv[option_index], L"--seconds") != 0) {
            usage();
            return 2;
        }
        parsed = wcstoul(argv[option_index + 1], &end, 10);
        if (end == argv[option_index + 1] || *end != L'\0' ||
            parsed == 0 || parsed > 3600) {
            fputs("--seconds must be between 1 and 3600.\n", stderr);
            return 2;
        }
        seconds = (DWORD)parsed;
    }
    return record_loopback(output_path, seconds, process_id);
}
