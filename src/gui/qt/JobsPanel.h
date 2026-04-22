#pragma once

#include <QDockWidget>
#include <QHash>

class FileJob;
class QVBoxLayout;
class QWidget;
class QLabel;
class QProgressBar;
class QPushButton;
class QThread;

/*
 * JobsPanel — dockable pane that lists active + recently-finished file
 * operations with progress bars and cancel buttons. MainWindow hands each
 * new FileJob off to takeJob(); the panel owns the QThread, the FileJob,
 * and the per-job widget row.
 */
class JobsPanel : public QDockWidget {
    Q_OBJECT
public:
    explicit JobsPanel(QWidget *parent = nullptr);
    ~JobsPanel() override;

    /* Hand a freshly-constructed job off. Returns the job pointer so the
     * caller can connect additional signals if desired. */
    FileJob *takeJob(FileJob *job);

signals:
    /* Re-emitted so MainWindow can refresh listers after the job completes. */
    void jobFinished(FileJob *job);

private:
    struct JobRow {
        FileJob      *job      = nullptr;
        QThread      *thread   = nullptr;
        QWidget      *widget   = nullptr;
        QLabel       *title    = nullptr;
        QLabel       *status   = nullptr;
        QProgressBar *bar      = nullptr;
        QPushButton  *cancel   = nullptr;
    };

    void onProgress(FileJob *job, qint64 done, qint64 total, int itemsDone,
                    int itemsTotal, const QString &current);
    void onLog(FileJob *job, const QString &line);
    void onConflict(FileJob *job, const QString &src, const QString &dst, bool isDir);
    void onFinished(FileJob *job, bool success, int ok, int skipped, int failed,
                    const QString &summary);
    void removeRow(FileJob *job);

    QWidget     *m_container = nullptr;
    QVBoxLayout *m_layout    = nullptr;
    QLabel      *m_emptyLbl  = nullptr;
    QHash<FileJob *, JobRow> m_rows;
};
