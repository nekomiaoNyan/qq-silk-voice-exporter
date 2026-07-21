# Security policy

This project intentionally performs no network access, telemetry, persistence, privilege elevation, process-memory scanning, key extraction, or source-file deletion. It decodes user-selected local files into a separate output directory. WeChat support opens only a user-selected, decrypted SQLite copy in read-only mode; encrypted official databases are rejected.

Please report memory-safety issues, malformed-file crashes, unexpected file writes, dependency provenance problems, and reproducibility issues through a private GitHub security advisory when available. Do not attach private QQ/WeChat voice files, databases, account folders, database keys, screenshots with contact names, or exported chat data to a public issue. Provide a minimized synthetic reproducer instead.

An antivirus or SmartScreen warning is useful diagnostic information but is not, by itself, proof of either maliciousness or safety. Include the exact product, engine/signature version, detection name, SHA-256, and download source in a report.
