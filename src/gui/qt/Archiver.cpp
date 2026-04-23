#include "Archiver.h"

#include <QDir>
#include <QFileInfo>
#include <QStandardPaths>

/* Helper: true if `name` refers to something runnable in the current PATH. */
static bool hasProgram(const QString &name) {
    return !QStandardPaths::findExecutable(name).isEmpty();
}

Archiver::Format Archiver::formatForPath(const QString &path) {
    const QString lower = path.toLower();
    if (lower.endsWith(QStringLiteral(".tar.gz")))  return FormatTarGz;
    if (lower.endsWith(QStringLiteral(".tgz")))     return FormatTarGz;
    if (lower.endsWith(QStringLiteral(".tar.bz2"))) return FormatTarBz2;
    if (lower.endsWith(QStringLiteral(".tbz2")))    return FormatTarBz2;
    if (lower.endsWith(QStringLiteral(".tar.xz")))  return FormatTarXz;
    if (lower.endsWith(QStringLiteral(".txz")))     return FormatTarXz;
    if (lower.endsWith(QStringLiteral(".tar")))     return FormatTar;
    if (lower.endsWith(QStringLiteral(".zip")))     return FormatZip;
    if (lower.endsWith(QStringLiteral(".7z")))      return FormatSevenZ;
    return FormatUnknown;
}

bool Archiver::isArchive(const QString &path) {
    return formatForPath(path) != FormatUnknown;
}

QStringList Archiver::supportedCompressFormats() {
    QStringList formats;
    /* Always list zip (Windows has it built in, POSIX typically too). */
    formats << QStringLiteral("zip");
    /* tar & variants need a tar binary. */
    if (hasProgram(QStringLiteral("tar"))) {
        formats << QStringLiteral("tar")
                << QStringLiteral("tar.gz")
                << QStringLiteral("tar.bz2")
                << QStringLiteral("tar.xz");
    }
    /* 7z optional. */
    if (hasProgram(QStringLiteral("7z"))) formats << QStringLiteral("7z");
    return formats;
}

bool Archiver::buildCompressArgv(const QString &archive,
                                  const QStringList &inputs,
                                  const QString &workingDir,
                                  QString &program,
                                  QStringList &args) {
    program.clear();
    args.clear();
    if (inputs.isEmpty()) return false;

    const Format fmt = formatForPath(archive);

    /* Convert absolute input paths to names relative to workingDir so
     * archives don't end up containing "/home/user/foo" etc. */
    QStringList names;
    QDir wd(workingDir);
    names.reserve(inputs.size());
    for (const QString &p : inputs) {
        QString rel = wd.relativeFilePath(p);
        if (rel.isEmpty()) rel = QFileInfo(p).fileName();
        names << rel;
    }

    switch (fmt) {
    case FormatZip: {
        if (hasProgram(QStringLiteral("zip"))) {
            program = QStringLiteral("zip");
            args << QStringLiteral("-r") << archive << names;
            return true;
        }
#ifdef Q_OS_WIN
        /* Windows: PowerShell's Compress-Archive. No per-file recursion
         * control for dirs here — PS handles it automatically. */
        program = QStringLiteral("powershell.exe");
        QStringList quoted;
        for (const QString &n : names) quoted << QStringLiteral("\"%1\"").arg(n);
        QString psPaths = quoted.join(QStringLiteral(", "));
        args << QStringLiteral("-NoProfile")
             << QStringLiteral("-Command")
             << QStringLiteral("Compress-Archive -Force -Path %1 -DestinationPath \"%2\"")
                    .arg(psPaths, archive);
        return true;
#else
        return false;
#endif
    }

    case FormatTar:
    case FormatTarGz:
    case FormatTarBz2:
    case FormatTarXz: {
        if (!hasProgram(QStringLiteral("tar"))) return false;
        program = QStringLiteral("tar");
        QString flags = QStringLiteral("-cf");
        if (fmt == FormatTarGz)  flags = QStringLiteral("-czf");
        if (fmt == FormatTarBz2) flags = QStringLiteral("-cjf");
        if (fmt == FormatTarXz)  flags = QStringLiteral("-cJf");
        args << flags << archive;
        args << names;
        return true;
    }

    case FormatSevenZ: {
        if (!hasProgram(QStringLiteral("7z"))) return false;
        program = QStringLiteral("7z");
        args << QStringLiteral("a") << QStringLiteral("-y") << archive << names;
        return true;
    }

    case FormatUnknown:
    default:
        return false;
    }
}

bool Archiver::buildExtractArgv(const QString &archive,
                                 const QString &destDir,
                                 QString &program,
                                 QStringList &args) {
    program.clear();
    args.clear();
    const Format fmt = formatForPath(archive);

    switch (fmt) {
    case FormatZip: {
        if (hasProgram(QStringLiteral("unzip"))) {
            program = QStringLiteral("unzip");
            args << QStringLiteral("-o") /* overwrite */
                 << archive
                 << QStringLiteral("-d") << destDir;
            return true;
        }
#ifdef Q_OS_WIN
        program = QStringLiteral("powershell.exe");
        args << QStringLiteral("-NoProfile")
             << QStringLiteral("-Command")
             << QStringLiteral(
                   "Expand-Archive -Force -LiteralPath \"%1\" -DestinationPath \"%2\"")
                    .arg(archive, destDir);
        return true;
#else
        if (hasProgram(QStringLiteral("tar"))) {
            /* bsdtar handles .zip natively on many systems. */
            program = QStringLiteral("tar");
            args << QStringLiteral("-xf") << archive
                 << QStringLiteral("-C") << destDir;
            return true;
        }
        return false;
#endif
    }

    case FormatTar:
    case FormatTarGz:
    case FormatTarBz2:
    case FormatTarXz: {
        if (!hasProgram(QStringLiteral("tar"))) return false;
        program = QStringLiteral("tar");
        /* tar auto-detects compression when given the right flag on modern
         * implementations; `-xf` alone is enough for bsdtar and GNU tar. */
        args << QStringLiteral("-xf") << archive
             << QStringLiteral("-C") << destDir;
        return true;
    }

    case FormatSevenZ: {
        if (!hasProgram(QStringLiteral("7z"))) return false;
        program = QStringLiteral("7z");
        args << QStringLiteral("x") << QStringLiteral("-y")
             << archive
             << QStringLiteral("-o") + destDir;  /* -oDEST syntax */
        return true;
    }

    case FormatUnknown:
    default:
        return false;
    }
}
