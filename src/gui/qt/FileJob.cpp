#include "FileJob.h"

#include <QDir>
#include <QDirIterator>
#include <QFile>
#include <QFileInfo>
#include <QMutexLocker>
#include <QThread>

FileJob::FileJob(Op op, QList<Item> items, QString label, QObject *parent)
    : QObject(parent), m_op(op), m_items(std::move(items)), m_label(std::move(label)) {}

void FileJob::cancel() {
    m_cancelRequested.storeRelease(1);
    /* Unblock anyone waiting on a conflict answer. */
    QMutexLocker lock(&m_conflictMutex);
    m_conflictAnswer = CancelAll;
    m_conflictCond.wakeAll();
}

void FileJob::resolveConflict(int action, bool applyToAll) {
    QMutexLocker lock(&m_conflictMutex);
    m_conflictAnswer   = action;
    m_conflictApplyAll = applyToAll;
    m_conflictCond.wakeAll();
}

FileJob::ConflictAction FileJob::askConflict(const QString &src, const QString &dst,
                                              bool isDir) {
    /* Fast path: a sticky answer from "apply to all" on previous conflict. */
    if (isDir && m_dirStickyDirAction >= 0)
        return static_cast<ConflictAction>(m_dirStickyDirAction);
    if (!isDir && m_dirStickyAction >= 0)
        return static_cast<ConflictAction>(m_dirStickyAction);

    QMutexLocker lock(&m_conflictMutex);
    m_conflictAnswer = -1;
    m_conflictApplyAll = false;
    /* Emit from worker; UI slot is on main thread — signal crosses threads
     * via Qt::AutoConnection = QueuedConnection. */
    emit conflict(src, dst, isDir);
    while (m_conflictAnswer < 0 && !cancelled())
        m_conflictCond.wait(&m_conflictMutex);
    const int ans = m_conflictAnswer;
    if (m_conflictApplyAll) {
        if (isDir) m_dirStickyDirAction = ans;
        else       m_dirStickyAction    = ans;
    }
    return static_cast<ConflictAction>(ans);
}

QString FileJob::uniqueTarget(const QString &dst) const {
    /* Inserts a numeric suffix before the extension: foo.txt → foo (2).txt. */
    QFileInfo fi(dst);
    QString base = fi.completeBaseName();
    QString ext  = fi.suffix();
    QString dir  = fi.absolutePath();
    for (int i = 2; i < 10000; ++i) {
        QString candidate = dir + QLatin1Char('/') + base
            + QStringLiteral(" (") + QString::number(i) + QLatin1Char(')');
        if (!ext.isEmpty()) candidate += QLatin1Char('.') + ext;
        if (!QFileInfo::exists(candidate)) return candidate;
    }
    return dst + QStringLiteral(".new");
}

qint64 FileJob::measureTree(const QString &src) const {
    QFileInfo fi(src);
    if (fi.isSymLink()) return 0;
    if (!fi.isDir())    return fi.size();

    qint64 total = 0;
    QDirIterator it(src, QDir::AllEntries | QDir::NoDotAndDotDot | QDir::Hidden
                          | QDir::System, QDirIterator::Subdirectories);
    while (it.hasNext()) {
        if (cancelled()) return total;
        it.next();
        QFileInfo f = it.fileInfo();
        if (f.isSymLink()) continue;
        if (f.isFile()) total += f.size();
    }
    return total;
}

bool FileJob::doCopyFile(const QString &src, const QString &dst, qint64 batchTotal) {
    if (cancelled()) return false;

    emit progress(m_bytesDone, batchTotal, m_itemIndex, m_items.size(),
                  QFileInfo(src).fileName());

    QFile in(src);
    if (!in.open(QIODevice::ReadOnly)) {
        emit logMessage(tr("Cannot read %1").arg(src));
        return false;
    }
    QFile out(dst);
    if (!out.open(QIODevice::WriteOnly | QIODevice::Truncate)) {
        emit logMessage(tr("Cannot write %1").arg(dst));
        return false;
    }

    const qint64 CHUNK = 1 << 16;  /* 64 KiB */
    QByteArray buf;
    buf.resize(CHUNK);

    while (!in.atEnd()) {
        if (cancelled()) {
            in.close();
            out.close();
            QFile::remove(dst);
            return false;
        }
        const qint64 n = in.read(buf.data(), CHUNK);
        if (n < 0) { emit logMessage(tr("Read error on %1").arg(src)); return false; }
        if (n == 0) break;
        if (out.write(buf.constData(), n) != n) {
            emit logMessage(tr("Write error on %1").arg(dst));
            return false;
        }
        m_bytesDone += n;
        if ((m_bytesDone & ((1 << 20) - 1)) == 0 /* ~every MiB */) {
            emit progress(m_bytesDone, batchTotal, m_itemIndex, m_items.size(),
                          QFileInfo(src).fileName());
        }
    }
    /* Preserve mtime where we can. */
    QFile::setPermissions(dst, in.permissions());
    return true;
}

bool FileJob::doCopyTree(const QString &src, const QString &dst, qint64 batchTotal) {
    QFileInfo si(src);
    if (!si.exists()) { emit logMessage(tr("Source gone: %1").arg(src)); return false; }

    if (si.isSymLink()) {
        /* Preserve symlink — no recursion. */
        const QString target = si.symLinkTarget();
        if (QFileInfo::exists(dst)) QFile::remove(dst);
        return QFile::link(target, dst);
    }

    if (!si.isDir()) {
        if (QFileInfo::exists(dst)) {
            ConflictAction a = askConflict(src, dst, /*isDir=*/false);
            switch (a) {
            case Skip:      ++m_skippedCount; return true;
            case CancelAll: cancel(); return false;
            case KeepBoth:  return doCopyFile(src, uniqueTarget(dst), batchTotal);
            case Replace:   QFile::remove(dst); break;
            case Merge:     /* not valid for files; treat as Replace */
                            QFile::remove(dst); break;
            }
        }
        return doCopyFile(src, dst, batchTotal);
    }

    /* Source is a directory. */
    QFileInfo di(dst);
    if (di.exists()) {
        ConflictAction a = askConflict(src, dst, /*isDir=*/true);
        switch (a) {
        case Skip:      ++m_skippedCount; return true;
        case CancelAll: cancel(); return false;
        case KeepBoth:  {
            /* Copy into a renamed sibling dir. */
            const QString alt = uniqueTarget(dst);
            if (!QDir().mkpath(alt)) { emit logMessage(tr("mkdir failed: %1").arg(alt)); return false; }
            QDir d(src);
            const auto names = d.entryList(QDir::NoDotAndDotDot | QDir::AllEntries
                                            | QDir::Hidden | QDir::System);
            for (const QString &n : names) {
                if (cancelled()) return false;
                if (!doCopyTree(src + QLatin1Char('/') + n,
                                alt + QLatin1Char('/') + n, batchTotal))
                    return false;
            }
            return true;
        }
        case Replace:
            if (!doDeleteTree(dst)) { emit logMessage(tr("cannot replace %1").arg(dst)); return false; }
            if (!QDir().mkpath(dst)) return false;
            break;
        case Merge:
            /* Non-destructive: existing files stay untouched unless the
             * recursive call asks for them. Fall through to the per-entry
             * loop below. */
            break;
        }
    } else {
        if (!QDir().mkpath(dst)) { emit logMessage(tr("mkdir failed: %1").arg(dst)); return false; }
    }

    QDir d(src);
    const auto names = d.entryList(QDir::NoDotAndDotDot | QDir::AllEntries
                                    | QDir::Hidden | QDir::System);
    for (const QString &n : names) {
        if (cancelled()) return false;
        if (!doCopyTree(src + QLatin1Char('/') + n,
                        dst + QLatin1Char('/') + n, batchTotal))
            return false;
    }
    return true;
}

bool FileJob::doDeleteTree(const QString &path) {
    if (cancelled()) return false;
    QFileInfo fi(path);
    if (fi.isDir() && !fi.isSymLink()) {
        return QDir(path).removeRecursively();
    }
    return QFile::remove(path);
}

bool FileJob::processItem(const Op op, const Item &item, qint64 batchTotal) {
    if (op == Delete) {
        if (doDeleteTree(item.dst)) { ++m_okCount; return true; }
        ++m_failedCount;
        return false;
    }

    /* Move: try rename fast path first (atomic on same volume, no I/O). */
    if (op == Move) {
        if (!QFileInfo::exists(item.dst)) {
            /* mkdir parent if needed */
            QDir().mkpath(QFileInfo(item.dst).absolutePath());
            if (QFile::rename(item.src, item.dst)) {
                ++m_okCount;
                m_bytesDone += measureTree(item.src);  /* approx for progress */
                return true;
            }
        }
        /* Fall back to copy-then-delete. */
        if (!doCopyTree(item.src, item.dst, batchTotal)) {
            ++m_failedCount;
            return false;
        }
        if (!doDeleteTree(item.src)) {
            emit logMessage(tr("Warning: copied but couldn't remove %1").arg(item.src));
        }
        ++m_okCount;
        return true;
    }

    /* Copy */
    if (doCopyTree(item.src, item.dst, batchTotal)) {
        ++m_okCount;
        return true;
    }
    ++m_failedCount;
    return false;
}

void FileJob::run() {
    m_running.storeRelease(1);
    m_bytesDone = 0;
    m_okCount = m_skippedCount = m_failedCount = 0;
    m_itemIndex = 0;

    /* Pre-compute total bytes for a meaningful progress percentage. */
    qint64 batchTotal = 0;
    if (m_op == Copy || m_op == Move) {
        for (const Item &it : m_items) {
            if (cancelled()) break;
            batchTotal += measureTree(it.src);
        }
    }
    emit progress(0, batchTotal, 0, m_items.size(), QString());

    for (; m_itemIndex < m_items.size(); ++m_itemIndex) {
        if (cancelled()) break;
        const Item &it = m_items[m_itemIndex];
        processItem(m_op, it, batchTotal);
    }

    const QString summary = tr("%1 ok · %2 skipped · %3 failed")
                                .arg(m_okCount).arg(m_skippedCount).arg(m_failedCount);
    m_running.storeRelease(0);
    m_finished.storeRelease(1);
    emit progress(batchTotal, batchTotal, m_items.size(), m_items.size(), QString());
    emit finished(m_failedCount == 0 && !cancelled(),
                  m_okCount, m_skippedCount, m_failedCount, summary);
}
