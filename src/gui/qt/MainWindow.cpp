#include "MainWindow.h"
#include "ListerWidget.h"
#include "ButtonBank.h"

#include <QAction>
#include <QApplication>
#include <QBoxLayout>
#include <QDateTime>
#include <QDialog>
#include <QDialogButtonBox>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QInputDialog>
#include <QKeySequence>
#include <QLabel>
#include <QListWidget>
#include <QMenu>
#include <QMenuBar>
#include <QMessageBox>
#include <QPushButton>
#include <QSettings>
#include <QShortcut>
#include <QSplitter>
#include <QStandardPaths>

static bool copyRecursive(const QString &src, const QString &dst) {
    QFileInfo si(src);
    if (si.isSymLink()) {
        QFile::link(si.symLinkTarget(), dst);
        return true;
    }
    if (si.isDir()) {
        if (!QDir().mkpath(dst)) return false;
        QDir d(src);
        const auto entries = d.entryList(QDir::NoDotAndDotDot | QDir::AllEntries
                                          | QDir::Hidden | QDir::System);
        for (const QString &name : entries) {
            if (!copyRecursive(src + '/' + name, dst + '/' + name)) return false;
        }
        return true;
    }
    return QFile::copy(src, dst);
}

static bool removeAny(const QString &path) {
    QFileInfo fi(path);
    if (fi.isDir() && !fi.isSymLink()) return QDir(path).removeRecursively();
    return QFile::remove(path);
}

static bool moveItem(const QString &src, const QString &dst) {
    if (QFile::rename(src, dst)) return true;
    if (!copyRecursive(src, dst)) return false;
    return removeAny(src);
}

MainWindow::MainWindow(const QString &leftPath, const QString &rightPath,
                       QWidget *parent)
    : QMainWindow(parent) {
    m_left  = new ListerWidget(leftPath,  this);
    m_right = new ListerWidget(rightPath, this);
    m_bank  = new ButtonBank(this);

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

/* --- File operations --- */

void MainWindow::doCopy(ListerWidget *src) {
    if (!src) return;
    ListerWidget *dst = peerOf(src);
    if (!dst) return;
    const QStringList items = src->selectedPaths();
    if (items.isEmpty()) {
        QMessageBox::information(this, tr("Copy"), tr("Nothing selected."));
        return;
    }
    const QString dstDir = dst->currentPath();
    int ok = 0, fail = 0, skipped = 0;
    for (const QString &path : items) {
        QFileInfo si(path);
        QString target = dstDir + '/' + si.fileName();
        if (QFileInfo::exists(target)) { ++skipped; continue; }
        if (copyRecursive(path, target)) ++ok;
        else ++fail;
    }
    dst->refresh();
    if (fail || skipped) {
        QMessageBox::warning(this, tr("Copy"),
            tr("%1 copied, %2 skipped (already exists), %3 failed")
              .arg(ok).arg(skipped).arg(fail));
    }
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
    const QString dstDir = dst->currentPath();
    int ok = 0, fail = 0, skipped = 0;
    for (const QString &path : items) {
        QFileInfo si(path);
        QString target = dstDir + '/' + si.fileName();
        if (QFileInfo::exists(target)) { ++skipped; continue; }
        if (moveItem(path, target)) ++ok;
        else ++fail;
    }
    src->refresh();
    dst->refresh();
    if (fail || skipped) {
        QMessageBox::warning(this, tr("Move"),
            tr("%1 moved, %2 skipped (already exists), %3 failed")
              .arg(ok).arg(skipped).arg(fail));
    }
}

void MainWindow::doDelete(ListerWidget *src) {
    if (!src) return;
    const QStringList items = src->selectedPaths();
    if (items.isEmpty()) {
        QMessageBox::information(this, tr("Delete"), tr("Nothing selected."));
        return;
    }
    auto ret = QMessageBox::question(this, tr("Delete"),
        tr("Move %n item(s) to Trash?", "", items.size()),
        QMessageBox::Yes | QMessageBox::No, QMessageBox::Yes);
    if (ret != QMessageBox::Yes) return;
    int ok = 0, fail = 0;
    for (const QString &p : items) {
        if (QFile::moveToTrash(p)) ++ok;
        else ++fail;
    }
    src->refresh();
    if (fail) {
        QMessageBox::warning(this, tr("Delete"),
            tr("%1 moved to Trash, %2 failed").arg(ok).arg(fail));
    }
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
    bool ok;
    QString pattern = QInputDialog::getText(this, tr("Filter"),
        tr("Show pattern (glob, e.g. *.txt — empty clears filter):"),
        QLineEdit::Normal, QString(), &ok);
    if (!ok) return;
    src->setShowPattern(pattern);
}

void MainWindow::onDrop(ListerWidget *dest, const QList<QUrl> &urls,
                        Qt::DropAction action) {
    if (!dest || urls.isEmpty()) return;
    const QString destDir = dest->currentPath();
    const QDir destQDir(destDir);

    int ok = 0, fail = 0, skipped = 0;
    for (const QUrl &u : urls) {
        if (!u.isLocalFile()) { ++skipped; continue; }
        const QString src = u.toLocalFile();
        QFileInfo si(src);
        if (!si.exists()) { ++skipped; continue; }
        if (QFileInfo(si.absolutePath()) == QFileInfo(destDir)) {
            /* same-dir drop: nothing to do */
            ++skipped;
            continue;
        }
        const QString target = destQDir.filePath(si.fileName());
        if (QFileInfo::exists(target)) { ++skipped; continue; }
        const bool success = (action == Qt::MoveAction)
                                ? moveItem(src, target)
                                : copyRecursive(src, target);
        if (success) ++ok; else ++fail;
    }
    if (m_left)  m_left->refresh();
    if (m_right) m_right->refresh();
    if (fail || skipped) {
        QMessageBox::warning(this, tr("Drop"),
            tr("%1 %2, %3 skipped, %4 failed")
              .arg(ok)
              .arg(action == Qt::MoveAction ? tr("moved") : tr("copied"))
              .arg(skipped).arg(fail));
    }
}
