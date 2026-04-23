#include "MainWindow.h"
#include "ListerWidget.h"
#include "ButtonBank.h"
#include "FileTypeActions.h"
#include "FileJob.h"
#include "JobsPanel.h"
#include "PreferencesDialog.h"
#include "PreviewPane.h"

#include <QAction>
#include <QApplication>
#include <QBoxLayout>
#include <QCheckBox>
#include <QDateTime>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFile>
#include <QFileDialog>
#include <QFileInfo>
#include <QFormLayout>
#include <QInputDialog>
#include <QKeySequence>
#include <QLabel>
#include <QLineEdit>
#include <QListWidget>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QProcess>
#include <QPushButton>
#include <QSettings>
#include <QShortcut>
#include <QSplitter>
#include <QStandardPaths>
#include <QUrl>

MainWindow::MainWindow(const QString &leftPath, const QString &rightPath,
                       QWidget *parent)
    : QMainWindow(parent) {
    m_ftypes = new FileTypeActions(this);
    m_left   = new ListerWidget(leftPath,  this);
    m_right  = new ListerWidget(rightPath, this);
    m_left->setFileTypeActions(m_ftypes);
    m_right->setFileTypeActions(m_ftypes);
    m_bank   = new ButtonBank(this);
    m_jobs   = new JobsPanel(this);
    addDockWidget(Qt::BottomDockWidgetArea, m_jobs);
    m_jobs->hide();   /* appears automatically when a job is queued */

    m_preview = new PreviewPane(this);
    addDockWidget(Qt::RightDockWidgetArea, m_preview);
    m_preview->hide();   /* opt-in via View menu or the active lister's selection */

    /* Show the current selection of whichever lister is active in the
     * preview pane. The pane keeps its last content until a new selection
     * arrives, so switching panes doesn't make it flicker empty. */
    auto wireSelectionToPreview = [this](ListerWidget *l) {
        connect(l, &ListerWidget::currentFileChanged,
                m_preview, &PreviewPane::showPath);
    };
    wireSelectionToPreview(m_left);
    wireSelectionToPreview(m_right);

    connect(m_jobs, &JobsPanel::jobFinished, this, [this](FileJob *) {
        if (m_left)  m_left->refresh();
        if (m_right) m_right->refresh();
    });

    auto *splitter = new QSplitter(Qt::Horizontal, this);
    splitter->addWidget(m_left);
    splitter->addWidget(m_bank);
    splitter->addWidget(m_right);
    splitter->setChildrenCollapsible(false);
    splitter->setStretchFactor(0, 1);
    splitter->setStretchFactor(1, 0);
    splitter->setStretchFactor(2, 1);
    setCentralWidget(splitter);

    connect(m_left,  &ListerWidget::pathChanged, this, [this](const QString&) { updateTitle(); });
    connect(m_right, &ListerWidget::pathChanged, this, [this](const QString&) { updateTitle(); });

    wireLister(m_left);
    wireLister(m_right);

    connect(m_bank, &ButtonBank::parentClicked,  this, [this]{ if (m_active) m_active->goParent();   });
    connect(m_bank, &ButtonBank::rootClicked,    this, [this]{ if (m_active) m_active->goRoot();     });
    connect(m_bank, &ButtonBank::refreshClicked, this, [this]{ if (m_active) m_active->refresh();    });
    connect(m_bank, &ButtonBank::allClicked,     this, [this]{ if (m_active) m_active->selectAll();  });
    connect(m_bank, &ButtonBank::noneClicked,    this, [this]{ if (m_active) m_active->selectNone(); });

    connect(m_bank, &ButtonBank::copyClicked,    this, [this]{ if (m_active) doCopy(m_active);    });
    connect(m_bank, &ButtonBank::moveClicked,    this, [this]{ if (m_active) doMove(m_active);    });
    connect(m_bank, &ButtonBank::deleteClicked,  this, [this]{ if (m_active) doDelete(m_active);  });
    connect(m_bank, &ButtonBank::renameClicked,  this, [this]{ if (m_active) doRename(m_active);  });
    connect(m_bank, &ButtonBank::makeDirClicked, this, [this]{ if (m_active) doMakeDir(m_active); });
    connect(m_bank, &ButtonBank::infoClicked,    this, [this]{ if (m_active) doInfo(m_active);    });
    connect(m_bank, &ButtonBank::filterClicked,  this, [this]{ if (m_active) doFilter(m_active);  });
    connect(m_bank, &ButtonBank::customTriggered, this, &MainWindow::runCustomCommand);
    connect(m_bank, &ButtonBank::manageCustomRequested,
            this, &MainWindow::manageCustomButtons);

    connect(qApp, &QApplication::focusChanged,
            this, &MainWindow::onFocusChanged);

    /* Keyboard shortcuts — target the active pane */
    auto addSC = [this](const QKeySequence &seq, auto handler) {
        auto *sc = new QShortcut(seq, this);
        sc->setContext(Qt::WindowShortcut);
        connect(sc, &QShortcut::activated, this, handler);
    };
    addSC(QKeySequence(Qt::Key_F3), [this]{ if (m_active) doRename(m_active);  });
    addSC(QKeySequence(Qt::Key_F5), [this]{ if (m_active) doCopy(m_active);    });
    addSC(QKeySequence(Qt::Key_F6), [this]{ if (m_active) doMove(m_active);    });
    addSC(QKeySequence(Qt::Key_F7), [this]{ if (m_active) doMakeDir(m_active); });
    addSC(QKeySequence(Qt::Key_F8), [this]{ if (m_active) doDelete(m_active);  });
    addSC(QKeySequence(Qt::Key_F9), [this]{ if (m_active) doInfo(m_active);    });
    addSC(QKeySequence(QStringLiteral("Ctrl+.")),
          [this]{ if (m_active) m_active->toggleHideDotfiles(); });
    addSC(QKeySequence(QStringLiteral("Ctrl+H")),
          [this]{ if (m_active) m_active->toggleHideDotfiles(); });
    addSC(QKeySequence(QStringLiteral("Ctrl+Shift+A")), [this]{
        if (!m_active) return;
        bool ok;
        QString p = QInputDialog::getText(this, tr("Select By Pattern"),
            tr("Pattern (glob, e.g. *.txt):"), QLineEdit::Normal, QString(), &ok);
        if (ok && !p.isEmpty()) m_active->selectByPattern(p);
    });

    loadBookmarks();
    buildMenuBar();
    applyPreferences();   /* pull stored Preferences into the UI at startup */

    setActive(m_left);
}

/* --- Menu bar + bookmarks --- */

void MainWindow::buildMenuBar() {
    auto *bar = menuBar();

    auto *viewMenu = bar->addMenu(tr("&Go"));
    auto *actBack = viewMenu->addAction(tr("&Back"));
    actBack->setShortcut(QKeySequence(Qt::ALT | Qt::Key_Left));
    connect(actBack, &QAction::triggered, this,
            [this]{ if (m_active) m_active->goBack(); });

    auto *actFwd = viewMenu->addAction(tr("&Forward"));
    actFwd->setShortcut(QKeySequence(Qt::ALT | Qt::Key_Right));
    connect(actFwd, &QAction::triggered, this,
            [this]{ if (m_active) m_active->goForward(); });

    auto *actUp = viewMenu->addAction(tr("&Parent"));
    actUp->setShortcut(QKeySequence(Qt::ALT | Qt::Key_Up));
    connect(actUp, &QAction::triggered, this,
            [this]{ if (m_active) m_active->goParent(); });

    viewMenu->addSeparator();
    auto *actHome = viewMenu->addAction(tr("&Home"));
    actHome->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+H")));
    connect(actHome, &QAction::triggered, this,
            [this]{ if (m_active) m_active->goHome(); });

    auto *actRoot = viewMenu->addAction(tr("&Root"));
    connect(actRoot, &QAction::triggered, this,
            [this]{ if (m_active) m_active->goRoot(); });

    auto *actRefresh = viewMenu->addAction(tr("Re&fresh"));
    actRefresh->setShortcut(QKeySequence(QStringLiteral("Ctrl+R")));
    connect(actRefresh, &QAction::triggered, this,
            [this]{ if (m_active) m_active->refresh(); });

    m_bookmarksMenu = bar->addMenu(tr("&Bookmarks"));
    rebuildBookmarksMenu();

    auto *toolsMenu = bar->addMenu(tr("&Tools"));
    auto *actFilter = toolsMenu->addAction(tr("&Filter…"));
    actFilter->setShortcut(QKeySequence(QStringLiteral("Ctrl+Shift+F")));
    connect(actFilter, &QAction::triggered, this,
            [this]{ if (m_active) doFilter(m_active); });

    toolsMenu->addSeparator();
    auto *actBtns = toolsMenu->addAction(tr("Manage Custom &Buttons…"));
    connect(actBtns, &QAction::triggered, this, &MainWindow::manageCustomButtons);
    auto *actFT   = toolsMenu->addAction(tr("Manage File Type &Actions…"));
    connect(actFT, &QAction::triggered, this, &MainWindow::manageFileTypeActions);

    auto *viewMenu2 = bar->addMenu(tr("&View"));
    if (m_jobs) {
        auto *toggleJobs = m_jobs->toggleViewAction();
        toggleJobs->setText(tr("&Jobs panel"));
        viewMenu2->addAction(toggleJobs);
    }
    if (m_preview) {
        auto *togglePrev = m_preview->toggleViewAction();
        togglePrev->setText(tr("&Preview pane"));
        togglePrev->setShortcut(QKeySequence(Qt::Key_Space));
        viewMenu2->addAction(togglePrev);
    }

    auto *prefsMenu = bar->addMenu(tr("&Preferences"));
    auto *actPrefs = prefsMenu->addAction(tr("&Preferences…"));
    actPrefs->setShortcut(QKeySequence(QKeySequence::Preferences));
    actPrefs->setMenuRole(QAction::PreferencesRole);
    connect(actPrefs, &QAction::triggered, this, &MainWindow::showPreferences);
}

void MainWindow::rebuildBookmarksMenu() {
    if (!m_bookmarksMenu) return;
    m_bookmarksMenu->clear();

    auto *addAct = m_bookmarksMenu->addAction(tr("Add &Current Path"));
    addAct->setShortcut(QKeySequence(QStringLiteral("Ctrl+D")));
    connect(addAct, &QAction::triggered, this, &MainWindow::addBookmarkForActive);

    auto *manageAct = m_bookmarksMenu->addAction(tr("&Manage Bookmarks…"));
    connect(manageAct, &QAction::triggered, this, &MainWindow::manageBookmarks);

    if (!m_bookmarks.isEmpty()) m_bookmarksMenu->addSeparator();

    for (const auto &b : m_bookmarks) {
        const QString label = b.first.isEmpty() ? b.second : b.first;
        const QString path  = b.second;
        auto *act = m_bookmarksMenu->addAction(label);
        act->setToolTip(path);
        connect(act, &QAction::triggered, this,
                [this, path]{ if (m_active) m_active->setPath(path); });
    }
}

void MainWindow::addBookmarkForActive() {
    if (!m_active) return;
    const QString path = m_active->currentPath();
    if (path.isEmpty()) return;
    /* Dedupe by path. */
    for (const auto &b : m_bookmarks)
        if (b.second == path) return;

    bool ok;
    QString title = QInputDialog::getText(this, tr("Add Bookmark"),
        tr("Title (optional):"), QLineEdit::Normal,
        QFileInfo(path).fileName(), &ok);
    if (!ok) return;
    m_bookmarks.append(qMakePair(title.trimmed(), path));
    saveBookmarks();
    rebuildBookmarksMenu();
}

void MainWindow::manageBookmarks() {
    QDialog dlg(this);
    dlg.setWindowTitle(tr("Manage Bookmarks"));
    dlg.resize(480, 320);

    auto *list = new QListWidget(&dlg);
    for (const auto &b : m_bookmarks) {
        const QString label = b.first.isEmpty() ? b.second : b.first;
        list->addItem(QStringLiteral("%1  —  %2").arg(label, b.second));
    }

    auto *btnRemove = new QPushButton(tr("Remove"), &dlg);
    auto *btnUp     = new QPushButton(tr("Up"),     &dlg);
    auto *btnDown   = new QPushButton(tr("Down"),   &dlg);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Close, &dlg);
    connect(buttons, &QDialogButtonBox::rejected, &dlg, &QDialog::accept);

    auto *sideCol = new QVBoxLayout;
    sideCol->addWidget(btnRemove);
    sideCol->addWidget(btnUp);
    sideCol->addWidget(btnDown);
    sideCol->addStretch(1);

    auto *row = new QHBoxLayout;
    row->addWidget(list, 1);
    row->addLayout(sideCol);

    auto *main = new QVBoxLayout(&dlg);
    main->addWidget(new QLabel(tr("Select a bookmark:"), &dlg));
    main->addLayout(row);
    main->addWidget(buttons);

    auto refreshList = [&]{
        list->clear();
        for (const auto &b : m_bookmarks) {
            const QString label = b.first.isEmpty() ? b.second : b.first;
            list->addItem(QStringLiteral("%1  —  %2").arg(label, b.second));
        }
    };

    connect(btnRemove, &QPushButton::clicked, this, [&]{
        int r = list->currentRow();
        if (r < 0 || r >= m_bookmarks.size()) return;
        m_bookmarks.removeAt(r);
        refreshList();
    });
    connect(btnUp, &QPushButton::clicked, this, [&]{
        int r = list->currentRow();
        if (r <= 0) return;
        m_bookmarks.swapItemsAt(r, r - 1);
        refreshList();
        list->setCurrentRow(r - 1);
    });
    connect(btnDown, &QPushButton::clicked, this, [&]{
        int r = list->currentRow();
        if (r < 0 || r + 1 >= m_bookmarks.size()) return;
        m_bookmarks.swapItemsAt(r, r + 1);
        refreshList();
        list->setCurrentRow(r + 1);
    });

    dlg.exec();
    saveBookmarks();
    rebuildBookmarksMenu();
}

void MainWindow::loadBookmarks() {
    QSettings s;
    int n = s.beginReadArray(QStringLiteral("bookmarks"));
    m_bookmarks.clear();
    m_bookmarks.reserve(n);
    for (int i = 0; i < n; ++i) {
        s.setArrayIndex(i);
        const QString title = s.value(QStringLiteral("title")).toString();
        const QString path  = s.value(QStringLiteral("path")).toString();
        if (!path.isEmpty()) m_bookmarks.append(qMakePair(title, path));
    }
    s.endArray();

    if (m_bookmarks.isEmpty()) {
        /* Seed with sensible defaults so the menu isn't empty on first run. */
        const QString home = QStandardPaths::writableLocation(QStandardPaths::HomeLocation);
        const QString docs = QStandardPaths::writableLocation(QStandardPaths::DocumentsLocation);
        const QString dl   = QStandardPaths::writableLocation(QStandardPaths::DownloadLocation);
        if (!home.isEmpty()) m_bookmarks.append(qMakePair(tr("Home"),     home));
        if (!docs.isEmpty()) m_bookmarks.append(qMakePair(tr("Documents"), docs));
        if (!dl.isEmpty())   m_bookmarks.append(qMakePair(tr("Downloads"), dl));
    }
}

void MainWindow::saveBookmarks() {
    QSettings s;
    s.beginWriteArray(QStringLiteral("bookmarks"), m_bookmarks.size());
    for (int i = 0; i < m_bookmarks.size(); ++i) {
        s.setArrayIndex(i);
        s.setValue(QStringLiteral("title"), m_bookmarks[i].first);
        s.setValue(QStringLiteral("path"),  m_bookmarks[i].second);
    }
    s.endArray();
}

void MainWindow::wireLister(ListerWidget *l) {
    connect(l, &ListerWidget::copyRequested,    this, &MainWindow::doCopy);
    connect(l, &ListerWidget::moveRequested,    this, &MainWindow::doMove);
    connect(l, &ListerWidget::deleteRequested,  this, &MainWindow::doDelete);
    connect(l, &ListerWidget::renameRequested,  this, &MainWindow::doRename);
    connect(l, &ListerWidget::makeDirRequested, this, &MainWindow::doMakeDir);
    connect(l, &ListerWidget::infoRequested,    this, &MainWindow::doInfo);
    connect(l, &ListerWidget::filterRequested,  this, &MainWindow::doFilter);
    connect(l, &ListerWidget::dropReceived,     this, &MainWindow::onDrop);
}

ListerWidget *MainWindow::peerOf(ListerWidget *lister) const {
    if (lister == m_left)  return m_right;
    if (lister == m_right) return m_left;
    return nullptr;
}

void MainWindow::setActive(ListerWidget *lister) {
    if (lister == m_active) return;
    if (m_active) m_active->setActive(false);
    m_active = lister;
    if (m_active) m_active->setActive(true);
    updateTitle();
}

void MainWindow::updateTitle() {
    if (!m_active) { setWindowTitle(QStringLiteral("iDOpus")); return; }
    setWindowTitle(QStringLiteral("iDOpus — ") + m_active->currentPath());
}

void MainWindow::onFocusChanged(QWidget * /*old*/, QWidget *now) {
    for (QWidget *w = now; w; w = w->parentWidget()) {
        if (w == m_left)  { setActive(m_left);  return; }
        if (w == m_right) { setActive(m_right); return; }
    }
}

/* --- File operations (async via FileJob + JobsPanel) --- */

static QList<FileJob::Item> buildItems(const QStringList &srcs, const QString &dstDir) {
    QList<FileJob::Item> out;
    out.reserve(srcs.size());
    for (const QString &s : srcs) {
        FileJob::Item it;
        it.src = s;
        it.dst = dstDir + QLatin1Char('/') + QFileInfo(s).fileName();
        out.append(it);
    }
    return out;
}

void MainWindow::doCopy(ListerWidget *src) {
    if (!src) return;
    ListerWidget *dst = peerOf(src);
    if (!dst) return;
    const QStringList items = src->selectedPaths();
    if (items.isEmpty()) {
        QMessageBox::information(this, tr("Copy"), tr("Nothing selected."));
        return;
    }
    const QString label = tr("Copy %n item(s) → %1", "", items.size())
                              .arg(dst->currentPath());
    m_jobs->takeJob(new FileJob(FileJob::Copy, buildItems(items, dst->currentPath()), label));
}

void MainWindow::doMove(ListerWidget *src) {
    if (!src) return;
    ListerWidget *dst = peerOf(src);
    if (!dst) return;
    const QStringList items = src->selectedPaths();
    if (items.isEmpty()) {
        QMessageBox::information(this, tr("Move"), tr("Nothing selected."));
        return;
    }
    const QString label = tr("Move %n item(s) → %1", "", items.size())
                              .arg(dst->currentPath());
    m_jobs->takeJob(new FileJob(FileJob::Move, buildItems(items, dst->currentPath()), label));
}

void MainWindow::doDelete(ListerWidget *src) {
    if (!src) return;
    const QStringList items = src->selectedPaths();
    if (items.isEmpty()) {
        QMessageBox::information(this, tr("Delete"), tr("Nothing selected."));
        return;
    }
    const bool permanent = PreferencesDialog::permanentDelete();
    if (PreferencesDialog::confirmDelete()) {
        auto ret = QMessageBox::question(this, tr("Delete"),
            permanent
                ? tr("Permanently delete %n item(s)? This cannot be undone.", "", items.size())
                : tr("Move %n item(s) to Trash?", "", items.size()),
            QMessageBox::Yes | QMessageBox::No, QMessageBox::No);
        if (ret != QMessageBox::Yes) return;
    }

    if (!permanent) {
        /* Fast path: let Qt/the OS move things to Trash synchronously. */
        int ok = 0, fail = 0;
        for (const QString &p : items) {
            if (QFile::moveToTrash(p)) ++ok; else ++fail;
        }
        src->refresh();
        if (fail) {
            QMessageBox::warning(this, tr("Delete"),
                tr("%1 moved to Trash, %2 failed").arg(ok).arg(fail));
        }
        return;
    }

    /* Permanent delete: queue a FileJob so it's cancellable + reported. */
    QList<FileJob::Item> toDelete;
    toDelete.reserve(items.size());
    for (const QString &p : items) {
        FileJob::Item it;
        it.dst = p;
        toDelete.append(it);
    }
    const QString label = tr("Delete %n item(s)", "", items.size());
    m_jobs->takeJob(new FileJob(FileJob::Delete, toDelete, label));
}

void MainWindow::doRename(ListerWidget *src) {
    if (!src) return;
    const QStringList items = src->selectedPaths();
    if (items.size() != 1) {
        QMessageBox::information(this, tr("Rename"),
            tr("Select exactly one item to rename."));
        return;
    }
    QFileInfo fi(items.first());
    bool ok;
    QString newName = QInputDialog::getText(this, tr("Rename"),
        tr("New name:"), QLineEdit::Normal, fi.fileName(), &ok);
    if (!ok || newName.isEmpty() || newName == fi.fileName()) return;
    if (newName.contains('/')) {
        QMessageBox::warning(this, tr("Rename"), tr("Name may not contain '/'."));
        return;
    }
    QString newPath = fi.absolutePath() + '/' + newName;
    if (QFile::rename(items.first(), newPath)) {
        src->refresh();
    } else {
        QMessageBox::warning(this, tr("Rename"), tr("Rename failed."));
    }
}

void MainWindow::doMakeDir(ListerWidget *src) {
    if (!src) return;
    bool ok;
    QString name = QInputDialog::getText(this, tr("New Folder"),
        tr("Folder name:"), QLineEdit::Normal, tr("New Folder"), &ok);
    if (!ok || name.isEmpty()) return;
    if (name.contains('/')) {
        QMessageBox::warning(this, tr("New Folder"), tr("Name may not contain '/'."));
        return;
    }
    QDir dir(src->currentPath());
    if (dir.mkdir(name)) {
        src->refresh();
    } else {
        QMessageBox::warning(this, tr("New Folder"), tr("Could not create folder."));
    }
}

void MainWindow::doInfo(ListerWidget *src) {
    if (!src) return;
    const QStringList items = src->selectedPaths();
    if (items.isEmpty()) {
        QMessageBox::information(this, tr("Info"), tr("Nothing selected."));
        return;
    }
    QString text;
    if (items.size() == 1) {
        QFileInfo fi(items.first());
        text = tr("<b>%1</b><br>"
                  "Path: %2<br>"
                  "Size: %3 bytes<br>"
                  "Modified: %4<br>"
                  "Type: %5<br>"
                  "Permissions: %6")
            .arg(fi.fileName())
            .arg(fi.absolutePath())
            .arg(fi.size())
            .arg(fi.lastModified().toString(Qt::ISODate))
            .arg(fi.isSymLink() ? tr("Symlink")
                 : fi.isDir()   ? tr("Directory")
                                : tr("File"))
            .arg(QString::number(fi.permissions() & 0777, 8));
    } else {
        qint64 total = 0;
        int files = 0, dirs = 0;
        for (const QString &p : items) {
            QFileInfo fi(p);
            if (fi.isDir()) ++dirs;
            else { ++files; total += fi.size(); }
        }
        text = tr("<b>%1 items</b><br>%2 files · %3 directories<br>Total: %4 bytes")
                 .arg(items.size()).arg(files).arg(dirs).arg(total);
    }
    QMessageBox::information(this, tr("Info"), text);
}

void MainWindow::doFilter(ListerWidget *src) {
    if (!src) return;

    QDialog dlg(this);
    dlg.setWindowTitle(tr("Filter"));
    dlg.resize(400, 160);

    auto *showEdit  = new QLineEdit(&dlg);
    showEdit->setPlaceholderText(tr("glob, e.g. *.txt — empty = no show filter"));
    showEdit->setText(src->currentShowPattern());

    auto *hideDot = new QCheckBox(tr("Hide dotfiles (leading '.')"), &dlg);
    hideDot->setChecked(src->hideDotfiles());

    auto *form = new QFormLayout;
    form->addRow(tr("&Show pattern:"), showEdit);
    form->addRow(QString(), hideDot);

    auto *buttons = new QDialogButtonBox(
        QDialogButtonBox::Ok | QDialogButtonBox::Cancel |
        QDialogButtonBox::Reset, &dlg);
    connect(buttons, &QDialogButtonBox::accepted, &dlg, &QDialog::accept);
    connect(buttons, &QDialogButtonBox::rejected, &dlg, &QDialog::reject);
    connect(buttons->button(QDialogButtonBox::Reset), &QPushButton::clicked, &dlg, [&]{
        showEdit->clear();
        hideDot->setChecked(false);
    });

    auto *main = new QVBoxLayout(&dlg);
    main->addLayout(form);
    main->addStretch(1);
    main->addWidget(buttons);

    if (dlg.exec() == QDialog::Accepted) {
        src->setShowPattern(showEdit->text().trimmed());
        src->setHideDotfiles(hideDot->isChecked());
    }
}

/* --- Custom-command execution for user buttons --- */

void MainWindow::runCustomCommand(const QString &command) {
    if (command.isEmpty() || !m_active) return;
    const QString path  = m_active->currentPath();
    const QStringList sel = m_active->selectedPaths();

    auto quoteAll = [](const QStringList &ps) {
        QStringList out;
        out.reserve(ps.size());
        for (const QString &p : ps) {
            if (p.contains(QLatin1Char(' ')) || p.contains(QLatin1Char('"')))
                out << QLatin1Char('"') + QString(p).replace(QLatin1Char('"'),
                                                              QStringLiteral("\\\""))
                      + QLatin1Char('"');
            else
                out << p;
        }
        return out.join(QLatin1Char(' '));
    };

    QString rendered = command;
    rendered.replace(QStringLiteral("{FILES}"), quoteAll(sel));
    rendered.replace(QStringLiteral("{PATH}"),  path);

    QStringList tokens = QProcess::splitCommand(rendered);
    if (tokens.isEmpty()) return;
    const QString program = tokens.takeFirst();
    if (!QProcess::startDetached(program, tokens)) {
        QMessageBox::warning(this, tr("Custom button"),
            tr("Could not launch:\n%1").arg(command));
    }
}

/* --- Custom buttons manager --- */

void MainWindow::manageCustomButtons() {
    if (!m_bank) return;

    QDialog dlg(this);
    dlg.setWindowTitle(tr("Custom Buttons"));
    dlg.resize(560, 360);

    auto *list = new QListWidget(&dlg);
    auto refresh = [&]{
        list->clear();
        for (const auto &b : m_bank->customButtons()) {
            const QString label = b.label.isEmpty() ? tr("(untitled)") : b.label;
            list->addItem(QStringLiteral("%1  —  %2").arg(label, b.command));
        }
    };
    refresh();

    auto *addBtn    = new QPushButton(tr("Add…"),    &dlg);
    auto *editBtn   = new QPushButton(tr("Edit…"),   &dlg);
    auto *removeBtn = new QPushButton(tr("Remove"),  &dlg);

    auto *sideCol = new QVBoxLayout;
    sideCol->addWidget(addBtn);
    sideCol->addWidget(editBtn);
    sideCol->addWidget(removeBtn);
    sideCol->addStretch(1);

    auto *row = new QHBoxLayout;
    row->addWidget(list, 1);
    row->addLayout(sideCol);

    auto *help = new QLabel(tr(
        "Placeholders: <b>{FILES}</b> = quoted selection, <b>{PATH}</b> = active "
        "lister's current directory."), &dlg);
    help->setWordWrap(true);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Close, &dlg);
    connect(buttons, &QDialogButtonBox::rejected, &dlg, &QDialog::accept);

    auto *main = new QVBoxLayout(&dlg);
    main->addWidget(new QLabel(tr("User buttons (saved across sessions):"), &dlg));
    main->addLayout(row);
    main->addWidget(help);
    main->addWidget(buttons);

    auto editDialog = [&](ButtonBank::CustomButton *inout) -> bool {
        QDialog d(&dlg);
        d.setWindowTitle(tr("Button"));
        auto *label = new QLineEdit(inout->label, &d);
        auto *cmd   = new QLineEdit(inout->command, &d);
        cmd->setPlaceholderText(QStringLiteral("e.g. notepad.exe {FILES}"));

        auto *form = new QFormLayout;
        form->addRow(tr("&Label:"),   label);
        form->addRow(tr("&Command:"), cmd);

        auto *ok = new QDialogButtonBox(
            QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &d);
        connect(ok, &QDialogButtonBox::accepted, &d, &QDialog::accept);
        connect(ok, &QDialogButtonBox::rejected, &d, &QDialog::reject);

        auto *v = new QVBoxLayout(&d);
        v->addLayout(form);
        v->addWidget(ok);

        if (d.exec() != QDialog::Accepted) return false;
        inout->label   = label->text().trimmed();
        inout->command = cmd->text().trimmed();
        return !inout->command.isEmpty();
    };

    connect(addBtn, &QPushButton::clicked, this, [&]{
        ButtonBank::CustomButton b;
        if (editDialog(&b)) {
            m_bank->addCustomButton(b);
            refresh();
        }
    });
    connect(editBtn, &QPushButton::clicked, this, [&]{
        int r = list->currentRow();
        if (r < 0 || r >= m_bank->customButtons().size()) return;
        ButtonBank::CustomButton b = m_bank->customButtons().at(r);
        if (editDialog(&b)) {
            m_bank->replaceCustom(r, b);
            refresh();
        }
    });
    connect(removeBtn, &QPushButton::clicked, this, [&]{
        int r = list->currentRow();
        if (r < 0) return;
        m_bank->removeCustomAt(r);
        refresh();
    });

    dlg.exec();
}

/* --- File Type Actions manager --- */

void MainWindow::manageFileTypeActions() {
    if (!m_ftypes) return;

    QDialog dlg(this);
    dlg.setWindowTitle(tr("File Type Actions"));
    dlg.resize(640, 400);

    auto *list = new QListWidget(&dlg);
    auto refresh = [&]{
        list->clear();
        for (const auto &a : m_ftypes->actions()) {
            const QString ext = a.ext.isEmpty() ? tr("*") : a.ext;
            const QString def = a.isDefault ? QStringLiteral(" ★") : QString();
            list->addItem(QStringLiteral(".%1%2  —  %3  (%4)")
                .arg(ext, def, a.title.isEmpty() ? a.command : a.title, a.command));
        }
    };
    refresh();

    auto *addBtn     = new QPushButton(tr("Add…"),      &dlg);
    auto *editBtn    = new QPushButton(tr("Edit…"),     &dlg);
    auto *removeBtn  = new QPushButton(tr("Remove"),    &dlg);
    auto *defaultBtn = new QPushButton(tr("Make default"), &dlg);
    defaultBtn->setCheckable(true);

    auto *sideCol = new QVBoxLayout;
    sideCol->addWidget(addBtn);
    sideCol->addWidget(editBtn);
    sideCol->addWidget(removeBtn);
    sideCol->addWidget(defaultBtn);
    sideCol->addStretch(1);

    auto *row = new QHBoxLayout;
    row->addWidget(list, 1);
    row->addLayout(sideCol);

    auto *help = new QLabel(tr(
        "Extensions match case-insensitively. Leave extension empty for \"any file\". "
        "Use <b>{FILE}</b> in the command as the file's path placeholder "
        "(appended automatically if omitted). ★ marks the default action used "
        "when double-clicking a file of that type."), &dlg);
    help->setWordWrap(true);

    auto *buttons = new QDialogButtonBox(QDialogButtonBox::Close, &dlg);
    connect(buttons, &QDialogButtonBox::rejected, &dlg, &QDialog::accept);

    auto *main = new QVBoxLayout(&dlg);
    main->addLayout(row);
    main->addWidget(help);
    main->addWidget(buttons);

    auto editOne = [&](FileTypeActions::Action *a) -> bool {
        QDialog d(&dlg);
        d.setWindowTitle(tr("File type action"));

        auto *ext    = new QLineEdit(a->ext,     &d);
        auto *title  = new QLineEdit(a->title,   &d);
        auto *cmd    = new QLineEdit(a->command, &d);
        auto *isDef  = new QCheckBox(tr("Default action for this extension"), &d);
        isDef->setChecked(a->isDefault);
        auto *pick   = new QPushButton(tr("Pick program…"), &d);

        connect(pick, &QPushButton::clicked, &d, [&]{
            const QString exe = QFileDialog::getOpenFileName(&d, tr("Pick program"));
            if (exe.isEmpty()) return;
            QString q = exe.contains(QLatin1Char(' '))
                ? QLatin1Char('"') + exe + QLatin1Char('"') : exe;
            if (cmd->text().isEmpty())
                cmd->setText(q + QStringLiteral(" {FILE}"));
            else
                cmd->setText(q + QStringLiteral(" ") + cmd->text());
        });

        auto *form = new QFormLayout;
        form->addRow(tr("&Extension:"),  ext);
        form->addRow(tr("&Title:"),      title);
        form->addRow(tr("&Command:"),    cmd);
        form->addRow(QString(),          pick);
        form->addRow(QString(),          isDef);

        auto *ok = new QDialogButtonBox(
            QDialogButtonBox::Ok | QDialogButtonBox::Cancel, &d);
        connect(ok, &QDialogButtonBox::accepted, &d, &QDialog::accept);
        connect(ok, &QDialogButtonBox::rejected, &d, &QDialog::reject);

        auto *v = new QVBoxLayout(&d);
        v->addLayout(form);
        v->addWidget(ok);
        d.resize(460, 280);

        if (d.exec() != QDialog::Accepted) return false;
        a->ext       = ext->text().trimmed();
        if (a->ext.startsWith(QLatin1Char('.'))) a->ext.remove(0, 1);
        a->title     = title->text().trimmed();
        a->command   = cmd->text().trimmed();
        a->isDefault = isDef->isChecked();
        return !a->command.isEmpty();
    };

    connect(addBtn, &QPushButton::clicked, this, [&]{
        FileTypeActions::Action a;
        if (editOne(&a)) { m_ftypes->addAction(a); refresh(); }
    });
    connect(editBtn, &QPushButton::clicked, this, [&]{
        int r = list->currentRow();
        if (r < 0) return;
        FileTypeActions::Action a = m_ftypes->actions().at(r);
        if (editOne(&a)) { m_ftypes->replace(r, a); refresh(); }
    });
    connect(removeBtn, &QPushButton::clicked, this, [&]{
        int r = list->currentRow();
        if (r < 0) return;
        m_ftypes->removeAt(r);
        refresh();
    });
    connect(defaultBtn, &QPushButton::clicked, this, [&]{
        int r = list->currentRow();
        if (r < 0) return;
        m_ftypes->setDefault(r, !m_ftypes->actions().at(r).isDefault);
        refresh();
    });

    dlg.exec();
}

void MainWindow::onDrop(ListerWidget *dest, const QList<QUrl> &urls,
                        Qt::DropAction action) {
    if (!dest || urls.isEmpty()) return;
    const QString destDir = dest->currentPath();

    QStringList sources;
    sources.reserve(urls.size());
    for (const QUrl &u : urls) {
        if (!u.isLocalFile()) continue;
        const QString src = u.toLocalFile();
        if (!QFileInfo::exists(src)) continue;
        /* Don't queue same-directory drops. */
        if (QFileInfo(src).absolutePath() == QFileInfo(destDir).absoluteFilePath())
            continue;
        sources.append(src);
    }
    if (sources.isEmpty()) return;

    const bool isMove = (action == Qt::MoveAction);
    const QString label = isMove
        ? tr("Drop: move %n item(s) → %1", "", sources.size()).arg(destDir)
        : tr("Drop: copy %n item(s) → %1", "", sources.size()).arg(destDir);
    m_jobs->takeJob(new FileJob(isMove ? FileJob::Move : FileJob::Copy,
                                 buildItems(sources, destDir), label));
}

/* --- Preferences --- */

void MainWindow::showPreferences() {
    PreferencesDialog dlg(this);
    connect(&dlg, &PreferencesDialog::settingsChanged,
            this, &MainWindow::applyPreferences);
    dlg.exec();
}

void MainWindow::applyPreferences() {
    const bool showBank = PreferencesDialog::showButtonBank();
    if (m_bank) m_bank->setVisible(showBank);
    const bool hideDot = PreferencesDialog::hideDotfilesDefault();
    if (m_left)  m_left->setHideDotfiles(hideDot);
    if (m_right) m_right->setHideDotfiles(hideDot);
}
