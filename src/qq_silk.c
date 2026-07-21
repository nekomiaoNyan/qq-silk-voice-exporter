#if !defined(_WIN32)
#define _POSIX_C_SOURCE 200809L
#endif

/***********************************************************************
Copyright (c) 2026 nekomiaoNyan

Permission is hereby granted, free of charge, to any person obtaining a
copy of this software and associated documentation files (the "Software"),
to deal in the Software without restriction, including without limitation
the rights to use, copy, modify, merge, publish, distribute, sublicense,
and/or sell copies of the Software, and to permit persons to whom the
Software is furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
DEALINGS IN THE SOFTWARE.
***********************************************************************/

#include <errno.h>
#include <limits.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "SKP_Silk_SDK_API.h"

#ifdef _WIN32
#include <io.h>
#include <windows.h>
#include <wchar.h>
typedef wchar_t path_char;
#define PATH_LITERAL(value) L##value
#define QQ_MAIN wmain
#define path_compare _wcsicmp

static FILE *path_open(const path_char *path, const path_char *mode) {
    return _wfopen(path, mode);
}

static int path_remove(const path_char *path) {
    return _wremove(path);
}

static long parse_long(const path_char *text, path_char **end, int base) {
    return wcstol(text, end, base);
}

static int open_files_are_same(FILE *left, FILE *right) {
    BY_HANDLE_FILE_INFORMATION left_info;
    BY_HANDLE_FILE_INFORMATION right_info;
    const intptr_t left_handle = _get_osfhandle(_fileno(left));
    const intptr_t right_handle = _get_osfhandle(_fileno(right));

    if (left_handle == -1 || right_handle == -1
        || !GetFileInformationByHandle((HANDLE)left_handle, &left_info)
        || !GetFileInformationByHandle((HANDLE)right_handle, &right_info)) {
        return -1;
    }

    return left_info.dwVolumeSerialNumber == right_info.dwVolumeSerialNumber
        && left_info.nFileIndexHigh == right_info.nFileIndexHigh
        && left_info.nFileIndexLow == right_info.nFileIndexLow;
}
#else
#include <sys/stat.h>
#include <unistd.h>
typedef char path_char;
#define PATH_LITERAL(value) value
#define QQ_MAIN main
#define path_compare strcmp

static FILE *path_open(const path_char *path, const path_char *mode) {
    return fopen(path, mode);
}

static int path_remove(const path_char *path) {
    return remove(path);
}

static long parse_long(const path_char *text, path_char **end, int base) {
    return strtol(text, end, base);
}

static int open_files_are_same(FILE *left, FILE *right) {
    struct stat left_info;
    struct stat right_info;

    if (fstat(fileno(left), &left_info) != 0 || fstat(fileno(right), &right_info) != 0) {
        return -1;
    }

    return left_info.st_dev == right_info.st_dev && left_info.st_ino == right_info.st_ino;
}
#endif

enum {
    DEFAULT_SAMPLE_RATE = 24000,
    MAX_PACKET_BYTES = 1024,
    MAX_SAMPLES_PER_FRAME = 960,
    MAX_FRAMES_PER_PACKET = 5,
    WAVE_HEADER_BYTES = 44
};

static void print_usage(void) {
    fputs(
        "qq-silk - auditable SILK V3 to WAV decoder\n"
        "Usage: qq-silk <input.amr|slk|silk> <output.wav> [--sample-rate 8000..48000]\n",
        stderr
    );
}

static int write_bytes(FILE *file, const uint8_t *bytes, size_t count) {
    return fwrite(bytes, 1, count, file) == count;
}

static int write_u16_le(FILE *file, uint16_t value) {
    const uint8_t bytes[2] = {
        (uint8_t)(value & 0xffu),
        (uint8_t)((value >> 8) & 0xffu)
    };
    return write_bytes(file, bytes, sizeof(bytes));
}

static int write_u32_le(FILE *file, uint32_t value) {
    const uint8_t bytes[4] = {
        (uint8_t)(value & 0xffu),
        (uint8_t)((value >> 8) & 0xffu),
        (uint8_t)((value >> 16) & 0xffu),
        (uint8_t)((value >> 24) & 0xffu)
    };
    return write_bytes(file, bytes, sizeof(bytes));
}

static int write_wave_header(FILE *file, uint32_t sample_rate, uint32_t data_bytes) {
    const uint32_t byte_rate = sample_rate * 2u;

    if (fseek(file, 0, SEEK_SET) != 0) {
        return 0;
    }

    return write_bytes(file, (const uint8_t *)"RIFF", 4)
        && write_u32_le(file, 36u + data_bytes)
        && write_bytes(file, (const uint8_t *)"WAVE", 4)
        && write_bytes(file, (const uint8_t *)"fmt ", 4)
        && write_u32_le(file, 16u)
        && write_u16_le(file, 1u)
        && write_u16_le(file, 1u)
        && write_u32_le(file, sample_rate)
        && write_u32_le(file, byte_rate)
        && write_u16_le(file, 2u)
        && write_u16_le(file, 16u)
        && write_bytes(file, (const uint8_t *)"data", 4)
        && write_u32_le(file, data_bytes);
}

static int reserve_wave_header(FILE *file) {
    const uint8_t empty[WAVE_HEADER_BYTES] = {0};
    return write_bytes(file, empty, sizeof(empty));
}

static int read_silk_header(FILE *input) {
    static const uint8_t signature[] = "#!SILK_V3";
    uint8_t first;
    uint8_t rest[sizeof(signature) - 1u];

    if (fread(&first, 1, 1, input) != 1) {
        return 0;
    }

    if (first == 0x02u) {
        return fread(rest, 1, sizeof(rest), input) == sizeof(rest)
            && memcmp(rest, signature, sizeof(rest)) == 0;
    }

    if (first != signature[0]) {
        return 0;
    }

    return fread(rest, 1, sizeof(rest) - 1u, input) == sizeof(rest) - 1u
        && memcmp(rest, signature + 1, sizeof(rest) - 1u) == 0;
}

static int read_packet_length(FILE *input, uint16_t *packet_bytes) {
    uint8_t bytes[2];
    const size_t count = fread(bytes, 1, sizeof(bytes), input);

    if (count == 0 && feof(input)) {
        return 0;
    }
    if (count != sizeof(bytes)) {
        return -1;
    }

    *packet_bytes = (uint16_t)((uint16_t)bytes[0] | ((uint16_t)bytes[1] << 8));
    return 1;
}

static int parse_sample_rate(int argc, path_char *argv[], int *sample_rate) {
    long parsed;
    path_char *end = NULL;

    *sample_rate = DEFAULT_SAMPLE_RATE;
    if (argc == 3) {
        return 1;
    }
    if (argc != 5 || path_compare(argv[3], PATH_LITERAL("--sample-rate")) != 0) {
        return 0;
    }

    errno = 0;
    parsed = parse_long(argv[4], &end, 10);
    if (errno != 0 || end == argv[4] || *end != 0 || parsed < 8000 || parsed > 48000) {
        return 0;
    }

    *sample_rate = (int)parsed;
    return 1;
}

static int output_alias_status(FILE *input, const path_char *output_path) {
    FILE *existing_output;
    int same;

    errno = 0;
    existing_output = path_open(output_path, PATH_LITERAL("rb"));
    if (existing_output == NULL) {
        return errno == ENOENT ? 0 : -1;
    }

    same = open_files_are_same(input, existing_output);
    fclose(existing_output);
    return same;
}

static int decode_file(const path_char *input_path, const path_char *output_path, int sample_rate) {
    FILE *input = NULL;
    FILE *output = NULL;
    void *decoder = NULL;
    SKP_int32 decoder_size = 0;
    SKP_SILK_SDK_DecControlStruct control;
    SKP_uint8 packet[MAX_PACKET_BYTES];
    SKP_int16 samples[MAX_SAMPLES_PER_FRAME];
    uint64_t total_data_bytes = 0;
    uint32_t packet_count = 0;
    int status = 1;
    int output_created = 0;

    input = path_open(input_path, PATH_LITERAL("rb"));
    if (input == NULL) {
        fputs("Error: cannot open input file.\n", stderr);
        goto cleanup;
    }

    if (!read_silk_header(input)) {
        fputs("Error: input is not a supported SILK V3 file.\n", stderr);
        goto cleanup;
    }

    {
        const int alias_status = output_alias_status(input, output_path);
        if (alias_status > 0) {
            fputs("Error: input and output refer to the same file.\n", stderr);
            goto cleanup;
        }
        if (alias_status < 0) {
            fputs("Error: cannot safely inspect the existing output path.\n", stderr);
            goto cleanup;
        }
    }

    output = path_open(output_path, PATH_LITERAL("wb"));
    if (output == NULL) {
        fputs("Error: cannot create output file.\n", stderr);
        goto cleanup;
    }
    output_created = 1;

    if (!reserve_wave_header(output)) {
        fputs("Error: cannot reserve the WAV header.\n", stderr);
        goto cleanup;
    }

    if (SKP_Silk_SDK_Get_Decoder_Size(&decoder_size) != 0
        || decoder_size <= 0
        || decoder_size > 1024 * 1024) {
        fputs("Error: SILK decoder reported an invalid state size.\n", stderr);
        goto cleanup;
    }

    decoder = calloc(1u, (size_t)decoder_size);
    if (decoder == NULL) {
        fputs("Error: cannot allocate decoder state.\n", stderr);
        goto cleanup;
    }
    if (SKP_Silk_SDK_InitDecoder(decoder) != 0) {
        fputs("Error: cannot initialize the SILK decoder.\n", stderr);
        goto cleanup;
    }

    memset(&control, 0, sizeof(control));
    control.API_sampleRate = sample_rate;
    control.framesPerPacket = 1;

    for (;;) {
        uint16_t packet_bytes = 0;
        const int length_status = read_packet_length(input, &packet_bytes);
        int frame_count = 0;

        if (length_status == 0 || packet_bytes == UINT16_MAX) {
            break;
        }
        if (length_status < 0) {
            fputs("Error: truncated SILK packet length.\n", stderr);
            goto cleanup;
        }
        if (packet_bytes == 0 || packet_bytes > MAX_PACKET_BYTES) {
            fputs("Error: invalid or oversized SILK packet.\n", stderr);
            goto cleanup;
        }
        if (fread(packet, 1, packet_bytes, input) != packet_bytes) {
            fputs("Error: truncated SILK packet.\n", stderr);
            goto cleanup;
        }

        do {
            SKP_int16 sample_count = MAX_SAMPLES_PER_FRAME;
            const SKP_int result = SKP_Silk_SDK_Decode(
                decoder,
                &control,
                0,
                packet,
                (SKP_int)packet_bytes,
                samples,
                &sample_count
            );
            uint64_t frame_bytes;

            if (result != 0) {
                fprintf(stderr, "Error: SILK decoder rejected a packet (%d).\n", (int)result);
                goto cleanup;
            }
            if (sample_count <= 0 || sample_count > MAX_SAMPLES_PER_FRAME) {
                fputs("Error: SILK decoder returned an invalid sample count.\n", stderr);
                goto cleanup;
            }
            if (++frame_count > MAX_FRAMES_PER_PACKET) {
                fputs("Error: SILK packet contains too many frames.\n", stderr);
                goto cleanup;
            }

            frame_bytes = (uint64_t)(uint16_t)sample_count * sizeof(SKP_int16);
            if (total_data_bytes + frame_bytes > UINT32_MAX - 36u) {
                fputs("Error: decoded audio exceeds the WAV size limit.\n", stderr);
                goto cleanup;
            }
            if (fwrite(samples, sizeof(SKP_int16), (size_t)sample_count, output)
                != (size_t)sample_count) {
                fputs("Error: cannot write decoded samples.\n", stderr);
                goto cleanup;
            }
            total_data_bytes += frame_bytes;
        } while (control.moreInternalDecoderFrames != 0);

        ++packet_count;
    }

    if (ferror(input)) {
        fputs("Error: failed while reading the input file.\n", stderr);
        goto cleanup;
    }
    if (packet_count == 0 || total_data_bytes == 0) {
        fputs("Error: SILK file contains no decodable audio packets.\n", stderr);
        goto cleanup;
    }
    if (!write_wave_header(output, (uint32_t)sample_rate, (uint32_t)total_data_bytes)
        || fflush(output) != 0) {
        fputs("Error: cannot finalize the WAV file.\n", stderr);
        goto cleanup;
    }

    fprintf(
        stdout,
        "Decoded %u packet(s), %.2f seconds, %d Hz mono WAV.\n",
        packet_count,
        (double)total_data_bytes / (double)(sample_rate * 2),
        sample_rate
    );
    status = 0;

cleanup:
    free(decoder);
    if (output != NULL) {
        fclose(output);
    }
    if (input != NULL) {
        fclose(input);
    }
    if (status != 0 && output_created) {
        (void)path_remove(output_path);
    }
    return status;
}

int QQ_MAIN(int argc, path_char *argv[]) {
    int sample_rate;

    if (!parse_sample_rate(argc, argv, &sample_rate)) {
        print_usage();
        return 2;
    }
    if (path_compare(argv[1], argv[2]) == 0) {
        fputs("Error: input and output paths must be different.\n", stderr);
        return 2;
    }

    return decode_file(argv[1], argv[2], sample_rate);
}
