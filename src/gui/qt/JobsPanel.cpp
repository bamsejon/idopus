#include "JobsPanel.h"
#include "FileJob.h"
#include "ConflictDialog.h"

#include <QFrame>
#include <QHBoxLayout>
#include <QLabel>
#include <QLocale>
#include <QProgressBar>
#include <QPushButton>
#include <QScrollArea>
#include <QThread>
#include <QTimer>
#include <QVBoxLayout>

JobsPanel::JobsPanel(QWidget *parent)
    : QDockWidget(tr("Jobs"), parent) {
    setObjectName(QStringLiteral("JobsPanel"));
    setAllowedAreas(Qt::BottomDockWidgetArea | Qt::TopDockWidgetArea);

    auto *scroll = new QScrollArea(this);
    scroll->setWidgetResizable(true);

    m_container = new QWidget;
    m_layout    = new QVBoxLayout(m_container);
    m_layout->setContentsMargins(8, 8, 8, 8);
    m_layout->setSpacing(6);

    m_emptyLbl = new QLabel(tr("No active jobs."), m_container);
    m_emptyLbl->setStyleSheet(QStringLiteral("QLabel { color: palette(mid); }"));
    m_layout->addWidget(m_emptyLbl);
    m_layout->addStretch(1);

    scroll->setWidget(m_container);
    setWidget(scroll);
}

JobsPanel::~JobsPanel() {
    /* Stop any in-flight jobs so we don't crash on app shutdown. */
    for (auto it = m_rows.constBegin(); it != m_rows.constEnd(); ++it) {
        FileJob *job = it.key();
        if (job) job->cancel();
        if (it.value().thread) {
            it.value().thread->quit();
            it.value().thread->wait(2000);
        }
    }
}

FileJob *JobsPanel::takeJob(FileJob *job) {
    if (!job) return nullptr;

    JobRow row;
    row.job    = job;
    row.thread = new QThread(this);
    job->moveToThread(row.thread);

    /* UI — one card per job. */
    auto *card = new QFrame(m_container);
    card->setFrameShape(QFrame::StyledPanel);
    card->setFrameShadow(QFrame::Raised);
    auto *cardLayout = new QVBoxLayout(card);
    cardLayout->setContentsMargins(8, 6, 8, 6);
    cardLayout->setSpacing(4);

    row.title  = new QLabel(job->label(), card);
    QFont titleFont = row.title->font();
    titleFont.setBold(true);
    row.title->setFont(titleFont);

    row.bar    = new QProgressBar(card);
    row.bar->setRange(0, 100);
    row.bar->setValue(0);

    row.status = new QLabel(tr("Preparing…"), card);
    row.status->setStyleSheet(QStringLiteral("QLabel { color: palette(mid); }"));
    QFont sf = row.status->font();
    sf.setPointSizeF(sf.pointSizeF() * 0.9);
    row.status->setFont(sf);

    row.cancel = new QPushButton(tr("Cancel"), card);
    row.cancel->setAutoDefault(false);

    auto *topRow = new QHBoxLayout;
    topRow->addWidget(row.title, 1);
    topRow->addWidget(row.cancel);

    cardLayout->addLayout(topRow);
    cardLayout->addWidget(row.bar);
    cardLayout->addWidget(row.status);

    row.widget = card;
    /* Insert before the trailing stretch. */
    m_layout->insertWidget(m_layout->count() - 1, card);
    m_emptyLbl->hide();

    m_rows.insert(job, row);

    /* Wire signals. */
    connect(row.cancel, &QPushButton::clicked, this, [job]{ job->cancel(); });

    connect(job, &FileJob::progress, this,
            [this, job](qint64 done, qint64 total, int i, int n, const QString &cur) {
                onProgress(job, done, total, i, n, cur);
            });
    connect(job, &FileJob::logMessage, this,
            [this, job](const QString &line) { onLog(job, line); });
    connect(job, &FileJob::conflict, this,
            [this, job](const QString &src, const QString &dst, bool isDir) {
                onConflict(job, src, dst, isDir);
            });
    connect(job, &FileJob::finished, this,
            [this, job](bool ok, int o, int s, int f, const QString &summary) {
                onFinished(job, ok, o, s, f, summary);
            });

    connect(row.thread, &QThread::started,  job, &FileJob::run);
    connect(job, &FileJob::finished, row.thread, &QThread::quit);
    connect(row.thread, &QThread::finished, row.thread, &QObject::deleteLater);

    /* Show the dock if the user had closed it. */
    show();
    raise();

    row.thread->start();
    return job;
}

void JobsPanel::onProgress(FileJob *job, qint64 done, qint64 total,
                            int itemsDone, int itemsTotal, const QString &current) {
    auto it = m_rows.find(job);
    if (it == m_rows.end()) return;
    int pct = (total > 0) ? int((done * 100) / total) : 0;
    it->bar->setValue(pct);

    QLocale loc;
    QString s;
    if (!current.isEmpty()) {
        s = tr("%1 of %2 · %3 — %4")
             .arg(itemsDone).arg(itemsTotal)
             .arg(loc.formattedDataSize(done))
             .arg(current);
    } else {
        s = tr("%1 of %2 · %3 of %4")
             .arg(itemsDone).arg(itemsTotal)
             .arg(loc.formattedDataSize(done))
             .arg(loc.formattedDataSize(total));
    }
    it->status->setText(s);
}

void JobsPanel::onLog(FileJob *job, const QString &line) {
    auto it = m_rows.find(job);
    if (it == m_rows.end()) return;
    it->status->setText(line);
}

void JobsPanel::onConflict(FileJob *job, const QString &src, const QString &dst,
                            bool isDir) {
    ConflictDialog dlg(src, dst, isDir, this);
    dlg.exec();
    job->resolveConflict(dlg.chosenAction(), dlg.applyToAll());
}

void JobsPanel::onFinished(FileJob *job, bool success, int ok, int skipped,
                            int failed, const QString &summary) {
    Q_UNUSED(ok); Q_UNUSED(skipped); Q_UNUSED(failed);
    auto it = m_rows.find(job);
    if (it != m_rows.end()) {
        it->cancel->setEnabled(false);
        it->cancel->setText(tr("Close"));
        it->status->setText(summary);
        it->bar->setValue(100);
        it->bar->setStyleSheet(success
            ? QStringLiteral("QProgressBar::chunk { background-color: #2a9; }")
            : QStringLiteral("QProgressBar::chunk { background-color: #c52; }"));
        /* Turn Cancel into a "remove from list" button now that the job is done. */
        disconnect(it->cancel, nullptr, this, nullptr);
        connect(it->cancel, &QPushButton::clicked, this, [this, job]{ removeRow(job); });
    }
    emit jobFinished(job);

    /* Auto-remove successful jobs after 6s so the list doesn't pile up. */
    if (success) QTimer::singleShot(6000, this, [this, job]{ removeRow(job); });
}

void JobsPanel::removeRow(FileJob *job) {
    auto it = m_rows.find(job);
    if (it == m_rows.end()) return;
    if (it->widget) it->widget->deleteLater();
    /* The QThread handles its own deletion via deleteLater on finished(). */
    job->deleteLater();
    m_rows.erase(it);
    if (m_rows.isEmpty()) m_emptyLbl->show();
}
