#pragma once

#include <QAtomicInt>
#include <QList>
#include <QMutex>
#include <QObject>
#include <QString>
#include <QStringList>
#include <QWaitCondition>

/*
 * FileJob — a single queued batch of file operations (copy / move / delete).
 *
 * Runs in a worker QThread. Emits progress, conflict, log and finished
 * signals back to the main thread. Conflict resolution is a handshake:
 * the worker emits `conflict(src, dst, isDir)` and blocks on a wait
 * condition until the UI calls `resolveConflict(action, applyToAll)`.
 *
 * Copy / move recurse into directories; merge for dir-on-dir is supported
 * (non-destructive — only missing entries are filled in).
 */

class FileJob : public QObject {
    Q_OBJECT
public:
    enum Op { Copy, Move, Delete };
    Q_ENUM(Op)

    enum ConflictAction {
        Replace,
        Skip,
        KeepBoth,
        Merge,       /* dir-on-dir only */
        CancelAll
    };
    Q_ENUM(ConflictAction)

    struct Item {
        QString src;   /* source path; empty for Delete ops on dst */
        QString dst;   /* destination path; for Delete = path to remove */
    };

    /* `label` is a short human description shown in the jobs panel. */
    FileJob(Op op, QList<Item> items, QString label, QObject *parent = nullptr);

    Op                  operation() const { return m_op; }
    const QString      &label() const     { return m_label; }
    bool                isRunning() const { return m_running.loadAcquire() != 0; }
    bool                isFinished() const { return m_finished.loadAcquire() != 0; }

public slots:
    /* Worker entry point — connect QThread::started to this. */
    void run();
    /* Request cancel. Safe to call from any thread. */
    void cancel();
    /* Called by UI when conflict dialog closes. */
    void resolveConflict(int action, bool applyToAll);

signals:
    void progress(qint64 bytesDone, qint64 bytesTotal,
                  int itemsDone, int itemsTotal,
                  const QString &currentFile);
    void logMessage(const QString &line);
    /* Emitted when an existing destination blocks the copy/move. The worker
     * thread is blocked until resolveConflict() is called. `isDir` is true
     * only when both src and dst are directories (Merge valid). */
    void conflict(const QString &src, const QString &dst, bool isDir);
    void finished(bool success, int okCount, int skippedCount,
                  int failedCount, const QString &summary);

private:
    bool   cancelled() const { return m_cancelRequested.loadAcquire() != 0; }

    /* Walks `src` to sum byte totals. Used for progress sizing. */
    qint64 measureTree(const QString &src) const;

    /* One copy/move/delete item; may recurse. `total` is the whole batch
     * size so progress % is global. Updates m_bytesDone. */
    bool processItem(const Op op, const Item &item, qint64 batchTotal);

    bool doCopyTree(const QString &src, const QString &dst, qint64 batchTotal);
    bool doCopyFile(const QString &src, const QString &dst, qint64 batchTotal);
    bool doDeleteTree(const QString &path);

    ConflictAction askConflict(const QString &src, const QString &dst, bool isDir);
    QString uniqueTarget(const QString &dst) const;

    Op           m_op;
    QList<Item>  m_items;
    QString      m_label;

    QAtomicInt   m_running       { 0 };
    QAtomicInt   m_finished      { 0 };
    QAtomicInt   m_cancelRequested { 0 };

    /* Conflict handshake */
    QMutex          m_conflictMutex;
    QWaitCondition  m_conflictCond;
    int             m_conflictAnswer { -1 };  /* ConflictAction, -1 = unset */
    bool            m_conflictApplyAll { false };
    int             m_dirStickyAction  { -1 }; /* for "apply to all" on files */
    int             m_dirStickyDirAction { -1 }; /* for dirs */

    /* Progress */
    qint64 m_bytesDone    { 0 };
    int    m_itemIndex    { 0 };
    int    m_okCount      { 0 };
    int    m_skippedCount { 0 };
    int    m_failedCount  { 0 };
};
