#pragma once

#include <QString>
#include <QStringList>

/*
 * Archiver — static helpers that resolve a platform-appropriate archive
 * toolchain and build argv for compress / extract operations.
 *
 * Supported formats:
 *   .zip       via `zip` (Linux/macOS) or PowerShell Compress-Archive
 *              (Windows built-in)
 *   .tar       via `tar`  (Win10 1803+ ships bsdtar, Linux/macOS tar)
 *   .tar.gz/.tgz, .tar.bz2, .tar.xz via `tar` (gzip/bzip2/xz streamed)
 *
 * Extract supports the same list plus `unzip` fallback when available.
 *
 * The helpers return a complete (program, args) pair suitable for
 * QProcess::start. Run on a worker thread — compress/extract of large
 * archives takes seconds to minutes.
 */
class Archiver {
public:
    enum Format {
        FormatUnknown,
        FormatZip,
        FormatTar,
        FormatTarGz,
        FormatTarBz2,
        FormatTarXz,
        FormatSevenZ
    };

    /* Match a path's suffix to a Format. ".tar.gz" / ".tar.bz2" / ".tar.xz"
     * take precedence over their single-suffix counterparts. */
    static Format formatForPath(const QString &path);

    /* Returns (program, args) for creating `archive` from `inputs`.
     * workingDir should be the directory inputs live in — the archive
     * will store paths relative to it. Empty program = unsupported format. */
    static bool buildCompressArgv(const QString &archive,
                                   const QStringList &inputs,
                                   const QString &workingDir,
                                   QString &program,
                                   QStringList &args);

    /* Returns (program, args) for extracting `archive` into `destDir`. */
    static bool buildExtractArgv(const QString &archive,
                                  const QString &destDir,
                                  QString &program,
                                  QStringList &args);

    /* Available archive extensions in a reasonable default order, for use
     * in file-filter dropdowns and menu labels. */
    static QStringList supportedCompressFormats();

    /* True if any known archive extension matches. */
    static bool isArchive(const QString &path);
};
