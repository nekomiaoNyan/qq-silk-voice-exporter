#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <errno.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;

enum {
    SQLITE_OK = 0,
    SQLITE_ROW = 100,
    SQLITE_DONE = 101,
    SQLITE_OPEN_READONLY = 0x00000001,
    SQLITE_OPEN_READWRITE = 0x00000002,
    SQLITE_OPEN_CREATE = 0x00000004,
    SQLITE_OPEN_NOMUTEX = 0x00008000,
    SQLITE_TRANSIENT_VALUE = -1
};

typedef int(__cdecl *sqlite3_open_v2_fn)(const char *, sqlite3 **, int, const char *);
typedef int(__cdecl *sqlite3_close_fn)(sqlite3 *);
typedef const char *(__cdecl *sqlite3_errmsg_fn)(sqlite3 *);
typedef int(__cdecl *sqlite3_prepare_v2_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
typedef int(__cdecl *sqlite3_step_fn)(sqlite3_stmt *);
typedef int(__cdecl *sqlite3_finalize_fn)(sqlite3_stmt *);
typedef int(__cdecl *sqlite3_bind_int64_fn)(sqlite3_stmt *, int, int64_t);
typedef int(__cdecl *sqlite3_bind_int_fn)(sqlite3_stmt *, int, int);
typedef int(__cdecl *sqlite3_bind_blob_fn)(sqlite3_stmt *, int, const void *, int, void(__cdecl *)(void *));
typedef int64_t(__cdecl *sqlite3_column_int64_fn)(sqlite3_stmt *, int);
typedef const void *(__cdecl *sqlite3_column_blob_fn)(sqlite3_stmt *, int);
typedef int(__cdecl *sqlite3_column_bytes_fn)(sqlite3_stmt *, int);
typedef int(__cdecl *sqlite3_exec_fn)(sqlite3 *, const char *, int(__cdecl *)(void *, int, char **, char **), void *, char **);
typedef void(__cdecl *sqlite3_free_fn)(void *);

typedef struct sqlite_api {
    HMODULE module;
    sqlite3_open_v2_fn open_v2;
    sqlite3_close_fn close;
    sqlite3_errmsg_fn errmsg;
    sqlite3_prepare_v2_fn prepare_v2;
    sqlite3_step_fn step;
    sqlite3_finalize_fn finalize;
    sqlite3_bind_int64_fn bind_int64;
    sqlite3_bind_int_fn bind_int;
    sqlite3_bind_blob_fn bind_blob;
    sqlite3_column_int64_fn column_int64;
    sqlite3_column_blob_fn column_blob;
    sqlite3_column_bytes_fn column_bytes;
    sqlite3_exec_fn exec;
    sqlite3_free_fn free_mem;
} sqlite_api;

typedef struct export_options {
    int64_t since;
    int64_t until;
    int limit;
    int force;
} export_options;

typedef struct export_stats {
    int exported;
    int skipped;
    int invalid;
    int failed;
} export_stats;

static void print_usage(void) {
    fwprintf(stderr,
             L"WeChat voice database extractor (read-only)\n"
             L"\n"
             L"Usage:\n"
             L"  wechat-voice.exe check <decrypted-media.db>\n"
             L"  wechat-voice.exe export <decrypted-media.db> <output-dir> [options]\n"
             L"  wechat-voice.exe self-test <temporary-dir>\n"
             L"\n"
             L"Options:\n"
             L"  --since <unix-seconds>   Include records at or after this time\n"
             L"  --until <unix-seconds>   Include records at or before this time\n"
             L"  --limit <count>          Maximum records (default: 10000)\n"
             L"  --force                  Replace existing exported .silk files\n"
             L"\n"
             L"The input must be a decrypted SQLite copy of WeChat 4.x media_*.db.\n"
             L"This program never reads Weixin.exe memory and never modifies the database.\n");
}

static FARPROC load_symbol(HMODULE module, const char *name) {
    FARPROC symbol = GetProcAddress(module, name);
    if (symbol == NULL) {
        fprintf(stderr, "winsqlite3.dll is missing required symbol: %s\n", name);
    }
    return symbol;
}

static int assign_symbol(HMODULE module, const char *name, void *target, size_t target_size) {
    FARPROC symbol = load_symbol(module, name);
    if (symbol == NULL) {
        return 0;
    }
    if (target_size != sizeof(symbol)) {
        fprintf(stderr, "Unexpected function pointer size for: %s\n", name);
        return 0;
    }
    memcpy(target, &symbol, target_size);
    return 1;
}

static int load_sqlite(sqlite_api *api) {
    wchar_t system_path[MAX_PATH];
    size_t path_length;
    memset(api, 0, sizeof(*api));
    if (GetSystemDirectoryW(system_path, _countof(system_path)) == 0) {
        fwprintf(stderr, L"Could not locate the Windows system directory.\n");
        return 0;
    }
    path_length = wcslen(system_path);
    if (path_length + wcslen(L"\\winsqlite3.dll") + 1 > _countof(system_path)) {
        fwprintf(stderr, L"Windows system directory path is too long.\n");
        return 0;
    }
    wcscat_s(system_path, _countof(system_path), L"\\winsqlite3.dll");
    api->module = LoadLibraryW(system_path);
    if (api->module == NULL) {
        fwprintf(stderr, L"Could not load the Windows system SQLite library (winsqlite3.dll).\n");
        return 0;
    }

#define LOAD_API(field, name)                                                  \
    do {                                                                        \
        if (!assign_symbol(api->module, name, &api->field, sizeof(api->field))) { \
            FreeLibrary(api->module);                                          \
            memset(api, 0, sizeof(*api));                                       \
            return 0;                                                           \
        }                                                                       \
    } while (0)

    LOAD_API(open_v2, "sqlite3_open_v2");
    LOAD_API(close, "sqlite3_close");
    LOAD_API(errmsg, "sqlite3_errmsg");
    LOAD_API(prepare_v2, "sqlite3_prepare_v2");
    LOAD_API(step, "sqlite3_step");
    LOAD_API(finalize, "sqlite3_finalize");
    LOAD_API(bind_int64, "sqlite3_bind_int64");
    LOAD_API(bind_int, "sqlite3_bind_int");
    LOAD_API(bind_blob, "sqlite3_bind_blob");
    LOAD_API(column_int64, "sqlite3_column_int64");
    LOAD_API(column_blob, "sqlite3_column_blob");
    LOAD_API(column_bytes, "sqlite3_column_bytes");
    LOAD_API(exec, "sqlite3_exec");
    LOAD_API(free_mem, "sqlite3_free");
#undef LOAD_API
    return 1;
}

static void unload_sqlite(sqlite_api *api) {
    if (api->module != NULL) {
        FreeLibrary(api->module);
    }
    memset(api, 0, sizeof(*api));
}

static char *wide_to_utf8(const wchar_t *value) {
    int size;
    char *result;
    if (value == NULL) {
        return NULL;
    }
    size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, NULL, 0, NULL, NULL);
    if (size <= 0) {
        return NULL;
    }
    result = (char *)malloc((size_t)size);
    if (result == NULL) {
        return NULL;
    }
    if (WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, value, -1, result, size, NULL, NULL) <= 0) {
        free(result);
        return NULL;
    }
    return result;
}

static int parse_int64(const wchar_t *value, int64_t *result) {
    wchar_t *end = NULL;
    long long parsed;
    errno = 0;
    parsed = wcstoll(value, &end, 10);
    if (errno != 0 || end == value || *end != L'\0') {
        return 0;
    }
    *result = (int64_t)parsed;
    return 1;
}

static int parse_positive_int(const wchar_t *value, int *result) {
    int64_t parsed;
    if (!parse_int64(value, &parsed) || parsed <= 0 || parsed > 1000000) {
        return 0;
    }
    *result = (int)parsed;
    return 1;
}

static int open_database(const sqlite_api *api, const wchar_t *path, int flags, sqlite3 **database) {
    char *utf8_path = wide_to_utf8(path);
    int rc;
    if (utf8_path == NULL) {
        fwprintf(stderr, L"Could not encode database path as UTF-8.\n");
        return 0;
    }
    *database = NULL;
    rc = api->open_v2(utf8_path, database, flags, NULL);
    free(utf8_path);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "Could not open database: %s\n", *database ? api->errmsg(*database) : "unknown error");
        if (*database != NULL) {
            api->close(*database);
            *database = NULL;
        }
        return 0;
    }
    return 1;
}

static int prepare_voice_query(const sqlite_api *api, sqlite3 *database, sqlite3_stmt **statement) {
    static const char query[] =
        "SELECT create_time, local_id, voice_data "
        "FROM VoiceInfo "
        "WHERE voice_data IS NOT NULL AND length(voice_data) >= 10 "
        "AND (?1 = 0 OR create_time >= ?1) "
        "AND (?2 = 0 OR create_time <= ?2) "
        "ORDER BY create_time DESC LIMIT ?3";
    int rc = api->prepare_v2(database, query, -1, statement, NULL);
    if (rc != SQLITE_OK) {
        fprintf(stderr,
                "Could not read VoiceInfo. The database may still be encrypted, locked, or incompatible: %s\n",
                api->errmsg(database));
        return 0;
    }
    return 1;
}

static int has_silk_header(const unsigned char *data, int size) {
    static const unsigned char header[] = {'#', '!', 'S', 'I', 'L', 'K', '_', 'V', '3'};
    if (data == NULL || size < (int)sizeof(header)) {
        return 0;
    }
    if (memcmp(data, header, sizeof(header)) == 0) {
        return 1;
    }
    return size >= (int)sizeof(header) + 1 && data[0] == 0x02 && memcmp(data + 1, header, sizeof(header)) == 0;
}

static int directory_exists(const wchar_t *path) {
    DWORD attributes = GetFileAttributesW(path);
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) != 0;
}

static int file_exists(const wchar_t *path) {
    DWORD attributes = GetFileAttributesW(path);
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

static int join_output_path(wchar_t *buffer,
                            size_t buffer_count,
                            const wchar_t *directory,
                            int64_t create_time,
                            int64_t local_id) {
    int written;
    const wchar_t *separator = L"";
    size_t length = wcslen(directory);
    if (length > 0 && directory[length - 1] != L'\\' && directory[length - 1] != L'/') {
        separator = L"\\";
    }
    written = swprintf_s(buffer,
                         buffer_count,
                         L"%ls%ls%lld_%lld.silk",
                         directory,
                         separator,
                         (long long)create_time,
                         (long long)local_id);
    return written > 0 && (size_t)written < buffer_count;
}

static int write_blob(const wchar_t *path, const void *data, int size) {
    FILE *output = NULL;
    size_t written;
    if (_wfopen_s(&output, path, L"wb") != 0 || output == NULL) {
        fwprintf(stderr, L"Could not create output file: %ls\n", path);
        return 0;
    }
    written = fwrite(data, 1, (size_t)size, output);
    if (fclose(output) != 0 || written != (size_t)size) {
        _wremove(path);
        fwprintf(stderr, L"Could not finish output file: %ls\n", path);
        return 0;
    }
    return 1;
}

static int check_database(const sqlite_api *api, const wchar_t *database_path) {
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    int rows = 0;
    int rc;
    if (!open_database(api, database_path, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, &database)) {
        return 0;
    }
    if (!prepare_voice_query(api, database, &statement)) {
        api->close(database);
        return 0;
    }
    api->bind_int64(statement, 1, 0);
    api->bind_int64(statement, 2, 0);
    /* Preparing and stepping this query validates the expected schema. One
       row is enough; a full count would make the GUI pause on large stores. */
    api->bind_int(statement, 3, 1);
    while ((rc = api->step(statement)) == SQLITE_ROW) {
        rows++;
    }
    if (rc != SQLITE_DONE) {
        fprintf(stderr, "Could not enumerate VoiceInfo: %s\n", api->errmsg(database));
        api->finalize(statement);
        api->close(database);
        return 0;
    }
    api->finalize(statement);
    api->close(database);
    printf("database=compatible\nvoice_records_sampled=%d\n", rows);
    return 1;
}

static int export_database(const sqlite_api *api,
                           const wchar_t *database_path,
                           const wchar_t *output_directory,
                           const export_options *options,
                           export_stats *stats) {
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    int rc;
    memset(stats, 0, sizeof(*stats));

    if (!directory_exists(output_directory)) {
        fwprintf(stderr, L"Output directory does not exist: %ls\n", output_directory);
        return 0;
    }
    if (!open_database(api, database_path, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, &database)) {
        return 0;
    }
    if (!prepare_voice_query(api, database, &statement)) {
        api->close(database);
        return 0;
    }
    api->bind_int64(statement, 1, options->since);
    api->bind_int64(statement, 2, options->until);
    api->bind_int(statement, 3, options->limit);

    while ((rc = api->step(statement)) == SQLITE_ROW) {
        int64_t create_time = api->column_int64(statement, 0);
        int64_t local_id = api->column_int64(statement, 1);
        const unsigned char *voice_data = (const unsigned char *)api->column_blob(statement, 2);
        int voice_size = api->column_bytes(statement, 2);
        wchar_t output_path[32768];

        if (!has_silk_header(voice_data, voice_size)) {
            stats->invalid++;
            continue;
        }
        if (!join_output_path(output_path, _countof(output_path), output_directory, create_time, local_id)) {
            fprintf(stderr, "Output path is too long.\n");
            stats->failed++;
            continue;
        }
        if (file_exists(output_path) && !options->force) {
            stats->skipped++;
            continue;
        }
        if (write_blob(output_path, voice_data, voice_size)) {
            stats->exported++;
            printf("exported=%lld_%lld.silk\n", (long long)create_time, (long long)local_id);
        } else {
            stats->failed++;
        }
    }

    if (rc != SQLITE_DONE) {
        fprintf(stderr, "Could not enumerate VoiceInfo: %s\n", api->errmsg(database));
        api->finalize(statement);
        api->close(database);
        return 0;
    }
    api->finalize(statement);
    api->close(database);
    printf("summary_exported=%d\nsummary_skipped=%d\nsummary_invalid=%d\nsummary_failed=%d\n",
           stats->exported,
           stats->skipped,
           stats->invalid,
           stats->failed);
    return stats->failed == 0;
}

static int exec_sql(const sqlite_api *api, sqlite3 *database, const char *sql) {
    char *message = NULL;
    int rc = api->exec(database, sql, NULL, NULL, &message);
    if (rc != SQLITE_OK) {
        fprintf(stderr, "SQLite setup failed: %s\n", message ? message : api->errmsg(database));
        if (message != NULL) {
            api->free_mem(message);
        }
        return 0;
    }
    return 1;
}

static int self_test(const sqlite_api *api, const wchar_t *temporary_directory) {
    wchar_t database_path[32768];
    wchar_t output_directory[32768];
    wchar_t expected_file[32768];
    sqlite3 *database = NULL;
    sqlite3_stmt *statement = NULL;
    export_options options = {0, 0, 10, 0};
    export_stats stats;
    static const unsigned char voice_data[] = {0x02, '#', '!', 'S', 'I', 'L', 'K', '_', 'V', '3', 0x01, 0x00};
    static const char insert_sql[] =
        "INSERT INTO VoiceInfo(create_time, local_id, voice_data) VALUES(?1, ?2, ?3)";
    int ok = 0;

    if (!directory_exists(temporary_directory)) {
        fwprintf(stderr, L"Self-test directory does not exist: %ls\n", temporary_directory);
        return 0;
    }
    if (swprintf_s(database_path,
                   _countof(database_path),
                   L"%ls\\wechat-voice-self-test-%lu.db",
                   temporary_directory,
                   GetCurrentProcessId()) <= 0 ||
        swprintf_s(output_directory,
                   _countof(output_directory),
                   L"%ls\\wechat-voice-self-test-%lu",
                   temporary_directory,
                   GetCurrentProcessId()) <= 0) {
        return 0;
    }
    _wremove(database_path);
    RemoveDirectoryW(output_directory);
    if (!CreateDirectoryW(output_directory, NULL)) {
        fwprintf(stderr, L"Could not create self-test output directory.\n");
        return 0;
    }
    if (!open_database(api,
                       database_path,
                       SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX,
                       &database)) {
        goto cleanup;
    }
    if (!exec_sql(api,
                  database,
                  "CREATE TABLE VoiceInfo(create_time INTEGER, local_id INTEGER, voice_data BLOB)")) {
        goto cleanup;
    }
    if (api->prepare_v2(database, insert_sql, -1, &statement, NULL) != SQLITE_OK) {
        fprintf(stderr, "Could not prepare self-test insert: %s\n", api->errmsg(database));
        goto cleanup;
    }
    api->bind_int64(statement, 1, 1700000000);
    api->bind_int64(statement, 2, 42);
    api->bind_blob(statement,
                   3,
                   voice_data,
                   (int)sizeof(voice_data),
                   (void(__cdecl *)(void *))(intptr_t)SQLITE_TRANSIENT_VALUE);
    if (api->step(statement) != SQLITE_DONE) {
        fprintf(stderr, "Could not insert self-test voice: %s\n", api->errmsg(database));
        goto cleanup;
    }
    api->finalize(statement);
    statement = NULL;
    api->close(database);
    database = NULL;

    if (!export_database(api, database_path, output_directory, &options, &stats)) {
        goto cleanup;
    }
    if (!join_output_path(expected_file, _countof(expected_file), output_directory, 1700000000, 42) ||
        stats.exported != 1 || !file_exists(expected_file)) {
        fprintf(stderr, "Self-test did not export the expected SILK file.\n");
        goto cleanup;
    }
    printf("self_test=ok\n");
    ok = 1;

cleanup:
    if (statement != NULL) {
        api->finalize(statement);
    }
    if (database != NULL) {
        api->close(database);
    }
    if (join_output_path(expected_file, _countof(expected_file), output_directory, 1700000000, 42)) {
        _wremove(expected_file);
    }
    RemoveDirectoryW(output_directory);
    _wremove(database_path);
    return ok;
}

int wmain(int argc, wchar_t **argv) {
    sqlite_api api;
    int result = 1;
    if (argc < 2) {
        print_usage();
        return 2;
    }
    if (!load_sqlite(&api)) {
        return 1;
    }

    if (_wcsicmp(argv[1], L"check") == 0) {
        if (argc != 3) {
            print_usage();
            result = 2;
        } else {
            result = check_database(&api, argv[2]) ? 0 : 1;
        }
    } else if (_wcsicmp(argv[1], L"export") == 0) {
        export_options options = {0, 0, 10000, 0};
        export_stats stats;
        int index;
        int valid = argc >= 4;
        for (index = 4; valid && index < argc; index++) {
            if (_wcsicmp(argv[index], L"--force") == 0) {
                options.force = 1;
            } else if (_wcsicmp(argv[index], L"--since") == 0 && index + 1 < argc) {
                valid = parse_int64(argv[++index], &options.since) && options.since >= 0;
            } else if (_wcsicmp(argv[index], L"--until") == 0 && index + 1 < argc) {
                valid = parse_int64(argv[++index], &options.until) && options.until >= 0;
            } else if (_wcsicmp(argv[index], L"--limit") == 0 && index + 1 < argc) {
                valid = parse_positive_int(argv[++index], &options.limit);
            } else {
                valid = 0;
            }
        }
        if (!valid || (options.until != 0 && options.since > options.until)) {
            print_usage();
            result = 2;
        } else {
            result = export_database(&api, argv[2], argv[3], &options, &stats) ? 0 : 1;
        }
    } else if (_wcsicmp(argv[1], L"self-test") == 0) {
        if (argc != 3) {
            print_usage();
            result = 2;
        } else {
            result = self_test(&api, argv[2]) ? 0 : 1;
        }
    } else {
        print_usage();
        result = 2;
    }

    unload_sqlite(&api);
    return result;
}
