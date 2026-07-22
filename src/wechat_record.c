#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <initguid.h>
#include <audioclient.h>
#include <conio.h>
#include <mmdeviceapi.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <wchar.h>

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

static int record_loopback(const wchar_t *output_path, DWORD maximum_seconds) {
    HRESULT result;
    IMMDeviceEnumerator *enumerator = NULL;
    IMMDevice *device = NULL;
    IAudioClient *audio_client = NULL;
    IAudioCaptureClient *capture_client = NULL;
    WAVEFORMATEX *mix_format = NULL;
    WavWriter writer;
    ULONGLONG start_tick;
    int writer_open = 0;
    int started = 0;
    int ok = 0;

    ZeroMemory(&writer, sizeof(writer));
    result = CoInitializeEx(NULL, COINIT_MULTITHREADED);
    if (FAILED(result)) {
        print_hresult("CoInitializeEx", result);
        return 1;
    }

    result = CoCreateInstance(&CLSID_MMDeviceEnumerator, NULL, CLSCTX_ALL,
                              &IID_IMMDeviceEnumerator, (void **)&enumerator);
    if (FAILED(result)) {
        print_hresult("Create audio device enumerator", result);
        goto cleanup;
    }
    result = IMMDeviceEnumerator_GetDefaultAudioEndpoint(enumerator, eRender, eConsole, &device);
    if (FAILED(result)) {
        print_hresult("Open default playback device", result);
        goto cleanup;
    }
    result = IMMDevice_Activate(device, &IID_IAudioClient, CLSCTX_ALL, NULL,
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
    result = IAudioClient_Initialize(audio_client, AUDCLNT_SHAREMODE_SHARED,
                                     AUDCLNT_STREAMFLAGS_LOOPBACK,
                                     10000000, 0, mix_format, NULL);
    if (FAILED(result)) {
        print_hresult("Initialize loopback recording", result);
        goto cleanup;
    }
    result = IAudioClient_GetService(audio_client, &IID_IAudioCaptureClient,
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
    if (mix_format != NULL) {
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
           L"  wechat-record.exe self-test <output.wav>\n\n"
           L"The recorder captures the system audio mix. Close other audio apps, start\n"
           L"recording, play a voice message in WeChat, then press Enter to stop.\n"
           L"It does not read WeChat files, databases, process memory, or encryption keys.\n",
           stderr);
}

int wmain(int argc, wchar_t **argv) {
    DWORD seconds = 0;

    if (argc == 3 && wcscmp(argv[1], L"self-test") == 0) {
        return self_test(argv[2]);
    }
    if (argc != 3 && argc != 5) {
        usage();
        return 2;
    }
    if (wcscmp(argv[1], L"record") != 0) {
        usage();
        return 2;
    }
    if (argc == 5) {
        wchar_t *end = NULL;
        unsigned long parsed;
        if (wcscmp(argv[3], L"--seconds") != 0) {
            usage();
            return 2;
        }
        parsed = wcstoul(argv[4], &end, 10);
        if (end == argv[4] || *end != L'\0' || parsed == 0 || parsed > 3600) {
            fputs("--seconds must be between 1 and 3600.\n", stderr);
            return 2;
        }
        seconds = (DWORD)parsed;
    }
    return record_loopback(argv[2], seconds);
}
