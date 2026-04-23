#include "ListerWidget.h"
#include "BreadcrumbBar.h"
#include "DirBufferModel.h"
#include "FileTypeActions.h"

#include <QKeyEvent>

#include <QTreeView>
#include <QLineEdit>
#include <QPushButton>
#include <QLabel>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QHeaderView>
#include <QShortcut>
#include <QStandardPaths>
#include <QStorageInfo>
#include <QItemSelectionModel>
#include <QMenu>
#include <QDesktopServices>
#include <QUrl>
#include <QFileInfo>
#include <QGuiApplication>
#include <QClipboard>
#include <QProcess>
#include <QInputDialog>
#include <QDragEnterEvent>
#include <QDragMoveEvent>
#include <QDropEvent>
#include <QMimeData>
#include <QGuiApplication>
#include <QFileSystemWatcher>
#include <QTimer>

extern "C" {
#include "core/dir_entry.h"
#include "pal/pal_file.h"
#include "pal/pal_strings.h"
}

ListerWidget::ListerWidget(const QString &initialPath, QWidget *parent)
    : QWidget(parent) {
    /* --- Tree view + model --- */
    m_view = new QTreeView(this);
    m_view->setRootIsDecorated(false);
    m_view->setAlternatingRowColors(true);
    m_view->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_view->setSelectionMode(QAbstractItemView::ExtendedSelection);
    m_view->setUniformRowHeights(true);
    m_view->setSortingEnabled(false);   /* ordering driven by dir_buffer */
    m_view->header()->setStretchLastSection(true);
    m_view->header()->setSectionsClickable(true);
    m_view->header()->setSortIndicatorShown(true);
    m_view->header()->setSortIndicator(DirBufferModel::ColName, Qt::AscendingOrder);
    connect(m_view->header(), &QHeaderView::sectionClicked,
            this, &ListerWidget::onHeaderClicked);

    m_model = new DirBufferModel(this);
    m_view->setModel(m_model);

    connect(m_view->selectionModel(), &QItemSelectionModel::selectionChanged,
            this, [this](const QItemSelection&, const QItemSelection&) { updateStatus(); });

    /* --- Path row: Back ←, Fwd →, Parent ↑, Refresh ↻, path QLineEdit --- */
    m_backBtn    = makeButton(QStringLiteral("←"), false);
    m_fwdBtn     = makeButton(QStringLiteral("→"), false);
    m_parentBtn  = makeButton(QStringLiteral("↑"), true);
    m_refreshBtn = makeButton(QStringLiteral("↻"), true);
    m_backBtn->setFixedWidth(32);    m_backBtn->setToolTip(tr("Back (Alt+Left)"));
    m_fwdBtn->setFixedWidth(32);     m_fwdBtn->setToolTip(tr("Forward (Alt+Right)"));
    m_parentBtn->setFixedWidth(32);  m_parentBtn->setToolTip(tr("Parent (Alt+Up)"));
    m_refreshBtn->setFixedWidth(32); m_refreshBtn->setToolTip(tr("Refresh"));
    connect(m_backBtn,    &QPushButton::clicked, this, &ListerWidget::goBack);
    connect(m_fwdBtn,     &QPushButton::clicked, this, &ListerWidget::goForward);
    connect(m_parentBtn,  &QPushButton::clicked, this, &ListerWidget::goParent);
    connect(m_refreshBtn, &QPushButton::clicked, this, &ListerWidget::refresh);

    m_pathField = new QLineEdit(this);
    m_pathField->setClearButtonEnabled(true);
    connect(m_pathField, &QLineEdit::returnPressed, this, &ListerWidget::onPathEdited);

    auto *pathRow = new QHBoxLayout;
    pathRow->setContentsMargins(0, 0, 0, 0);
    pathRow->setSpacing(4);
    pathRow->addWidget(m_backBtn);
    pathRow->addWidget(m_fwdBtn);
    pathRow->addWidget(m_parentBtn);
    pathRow->addWidget(m_refreshBtn);
    pathRow->addWidget(m_pathField, 1);

    /* Clickable breadcrumb row above the text path field. */
    m_breadcrumb = new BreadcrumbBar(this);
    connect(m_breadcrumb, &BreadcrumbBar::pathPicked,
            this, &ListerWidget::setPath);

    /* --- Action row: Copy · Move · Delete · Rename · MakeDir · Info · Filter
                       | Parent · Root | All · None --- */
    m_copyBtn    = makeButton(QStringLiteral("Copy"),    true);
    m_moveBtn    = makeButton(QStringLiteral("Move"),    true);
    m_deleteBtn  = makeButton(QStringLiteral("Delete"),  true);
    m_renameBtn  = makeButton(QStringLiteral("Rename"),  true);
    m_makeDirBtn = makeButton(QStringLiteral("MakeDir"), true);
    m_infoBtn    = makeButton(QStringLiteral("Info"),    true);
    m_filterBtn  = makeButton(QStringLiteral("Filter"),  true);

    connect(m_copyBtn,    &QPushButton::clicked, this, [this]{ emit copyRequested(this);    });
    connect(m_moveBtn,    &QPushButton::clicked, this, [this]{ emit moveRequested(this);    });
    connect(m_deleteBtn,  &QPushButton::clicked, this, [this]{ emit deleteRequested(this);  });
    connect(m_renameBtn,  &QPushButton::clicked, this, [this]{ emit renameRequested(this);  });
    connect(m_makeDirBtn, &QPushButton::clicked, this, [this]{ emit makeDirRequested(this); });
    connect(m_infoBtn,    &QPushButton::clicked, this, [this]{ emit infoRequested(this);    });
    connect(m_filterBtn,  &QPushButton::clicked, this, [this]{ emit filterRequested(this);  });

    m_parent2Btn = makeButton(QStringLiteral("Parent"), true);
    m_rootBtn    = makeButton(QStringLiteral("Root"),   true);
    m_allBtn     = makeButton(QStringLiteral("All"),    true);
    m_noneBtn    = makeButton(QStringLiteral("None"),   true);
    connect(m_parent2Btn, &QPushButton::clicked, this, &ListerWidget::goParent);
    connect(m_rootBtn,    &QPushButton::clicked, this, &ListerWidget::goRoot);
    connect(m_allBtn,     &QPushButton::clicked, this, &ListerWidget::selectAll);
    connect(m_noneBtn,    &QPushButton::clicked, this, &ListerWidget::selectNone);

    auto *actionRow = new QHBoxLayout;
    actionRow->setContentsMargins(0, 0, 0, 0);
    actionRow->setSpacing(4);
    actionRow->addWidget(m_copyBtn);
    actionRow->addWidget(m_moveBtn);
    actionRow->addWidget(m_deleteBtn);
    actionRow->addWidget(m_renameBtn);
    actionRow->addWidget(m_makeDirBtn);
    actionRow->addWidget(m_infoBtn);
    actionRow->addWidget(m_filterBtn);
    actionRow->addSpacing(8);
    actionRow->addWidget(m_parent2Btn);
    actionRow->addWidget(m_rootBtn);
    actionRow->addSpacing(8);
    actionRow->addWidget(m_allBtn);
    actionRow->addWidget(m_noneBtn);
    actionRow->addStretch(1);

    /* --- Status row: SOURCE/DEST badge + counts --- */
    m_stateBadge = new QLabel(this);
    m_stateBadge->setAlignment(Qt::AlignCenter);
    m_stateBadge->setFixedSize(64, 20);
    QFont badgeFont = m_stateBadge->font();
    badgeFont.setBold(true);
    badgeFont.setStyleHint(QFont::Monospace);
    badgeFont.setPointSizeF(badgeFont.pointSizeF() * 0.9);
    m_stateBadge->setFont(badgeFont);

    m_statusLabel = new QLabel(this);
    QFont statusFont = m_statusLabel->font();
    statusFont.setStyleHint(QFont::Monospace);
    statusFont.setPointSizeF(statusFont.pointSizeF() * 0.9);
    m_statusLabel->setFont(statusFont);
    m_statusLabel->setTextInteractionFlags(Qt::TextSelectableByMouse);

    auto *statusRow = new QHBoxLayout;
    statusRow->setContentsMargins(0, 0, 0, 0);
    statusRow->setSpacing(8);
    statusRow->addWidget(m_stateBadge);
    statusRow->addWidget(m_statusLabel, 1);

    /* --- Main layout: breadcrumb / pathRow / actionRow / tree / statusRow --- */
    auto *main = new QVBoxLayout(this);
    main->setContentsMargins(2, 2, 2, 2);
    main->setSpacing(4);
    main->addWidget(m_breadcrumb);
    main->addLayout(pathRow);
    main->addLayout(actionRow);
    main->addWidget(m_view, 1);
    main->addLayout(statusRow);

    connect(m_view, &QAbstractItemView::doubleClicked,
            this,   &ListerWidget::onDoubleClicked);

    m_view->setContextMenuPolicy(Qt::CustomContextMenu);
    connect(m_view, &QWidget::customContextMenuRequested,
            this,   &ListerWidget::onContextMenu);

    m_view->setDragEnabled(true);
    m_view->setAcceptDrops(true);
    m_view->setDropIndicatorShown(true);
    m_view->setDragDropMode(QAbstractItemView::DragDrop);
    m_view->setDefaultDropAction(Qt::CopyAction);
    m_view->viewport()->installEventFilter(this);

    /* Keyboard navigation: Alt+Up/Left/Right */
    auto addSC = [this](const QKeySequence &seq, void (ListerWidget::*handler)()) {
        auto *sc = new QShortcut(seq, this);
        sc->setContext(Qt::WidgetWithChildrenShortcut);
        connect(sc, &QShortcut::activated, this, handler);
    };
    addSC(QKeySequence(Qt::ALT | Qt::Key_Up),    &ListerWidget::goParent);
    addSC(QKeySequence(Qt::ALT | Qt::Key_Left),  &ListerWidget::goBack);
    addSC(QKeySequence(Qt::ALT | Qt::Key_Right), &ListerWidget::goForward);

    /* Live refresh: QFileSystemWatcher + debounced 250ms timer so rapid
     * bursts of change events collapse into a single refresh(). */
    m_watcher = new QFileSystemWatcher(this);
    connect(m_watcher, &QFileSystemWatcher::directoryChanged,
            this,      &ListerWidget::onWatchedDirChanged);
    m_refreshTimer = new QTimer(this);
    m_refreshTimer->setSingleShot(true);
    m_refreshTimer->setInterval(250);
    connect(m_refreshTimer, &QTimer::timeout,
            this,           &ListerWidget::fireDebouncedRefresh);

    /* Type-to-find — accumulate letters, jump on each change, clear after 700 ms. */
    m_typeTimer = new QTimer(this);
    m_typeTimer->setSingleShot(true);
    m_typeTimer->setInterval(700);
    connect(m_typeTimer, &QTimer::timeout,
            this, &ListerWidget::clearTypeToFindBuffer);

    connect(m_view->selectionModel(), &QItemSelectionModel::currentRowChanged,
            this, [this](const QModelIndex&, const QModelIndex&) { onCurrentRowChanged(); });

    setActive(false);
    setPath(initialPath);
}

QPushButton *ListerWidget::makeButton(const QString &text, bool enabled) {
    auto *b = new QPushButton(text, this);
    b->setAutoDefault(false);
    b->setDefault(false);
    b->setEnabled(enabled);
    b->setStyleSheet(QStringLiteral("QPushButton { padding: 2px 6px; }"));
    QFont f = b->font();
    f.setPointSizeF(f.pointSizeF() * 0.9);
    b->setFont(f);
    b->setSizePolicy(QSizePolicy::Minimum, QSizePolicy::Fixed);
    return b;
}

void ListerWidget::setActive(bool active) {
    m_active = active;
    setStyleSheet(active
        ? QStringLiteral("ListerWidget { border: 2px solid palette(highlight); }")
        : QStringLiteral("ListerWidget { border: 2px solid transparent; }"));
    if (m_stateBadge) {
        if (active) {
            m_stateBadge->setText(QStringLiteral("SOURCE"));
            m_stateBadge->setStyleSheet(QStringLiteral(
                "QLabel { background-color: #0A84FF; color: white; border-radius: 3px; }"));
        } else {
            m_stateBadge->setText(QStringLiteral("DEST"));
            m_stateBadge->setStyleSheet(QStringLiteral(
                "QLabel { background-color: #FF9F0A; color: white; border-radius: 3px; }"));
        }
    }
}

void ListerWidget::setPath(const QString &path) {
    setPathInternal(path, /* recordHistory = */ true);
}

void ListerWidget::setPathInternal(const QString &path, bool recordHistory) {
    if (recordHistory && path != m_path) {
        /* Chop any forward history past the current position, then push. */
        if (m_historyIndex >= 0 && m_historyIndex + 1 < m_history.size())
            m_history.erase(m_history.begin() + m_historyIndex + 1, m_history.end());
        m_history.append(path);
        m_historyIndex = m_history.size() - 1;
        /* Keep the stack bounded so it doesn't grow forever. */
        const int kMaxHistory = 128;
        if (m_history.size() > kMaxHistory) {
            m_history.removeFirst();
            --m_historyIndex;
        }
    }
    m_path = path;
    m_model->setPath(path);
    if (m_pathField)  m_pathField->setText(path);
    if (m_breadcrumb) m_breadcrumb->setPath(path);
    m_view->resizeColumnToContents(DirBufferModel::ColName);
    m_view->resizeColumnToContents(DirBufferModel::ColSize);
    rewatch(path);
    updateNavButtons();
    emit pathChanged(m_path);
    emit historyChanged();
    updateStatus();
    /* New directory usually means no selection — clear the preview. */
    emit currentFileChanged(QString());
}

void ListerWidget::goParent() {
    char buf[4096];
    pal_path_parent(m_path.toUtf8().constData(), buf, sizeof buf);
    QString parent = QString::fromUtf8(buf);
    if (parent == m_path) return;
    setPath(parent);
}

void ListerWidget::goHome() {
    setPath(QStandardPaths::writableLocation(QStandardPaths::HomeLocation));
}

void ListerWidget::goRoot() {
#ifdef Q_OS_WIN
    /* "Root" on Windows is ambiguous — take the current drive's root. */
    if (!m_path.isEmpty() && m_path.size() >= 2 && m_path[1] == QChar(':')) {
        setPath(m_path.left(2) + QLatin1Char('/'));
        return;
    }
    setPath(QStringLiteral("C:/"));
#else
    setPath(QStringLiteral("/"));
#endif
}

void ListerWidget::goBack() {
    if (!canGoBack()) return;
    --m_historyIndex;
    setPathInternal(m_history[m_historyIndex], /* recordHistory = */ false);
}

void ListerWidget::goForward() {
    if (!canGoForward()) return;
    ++m_historyIndex;
    setPathInternal(m_history[m_historyIndex], /* recordHistory = */ false);
}

void ListerWidget::refresh() {
    /* Just reload the model; don't churn history. */
    setPathInternal(m_path, /* recordHistory = */ false);
}

void ListerWidget::updateNavButtons() {
    if (m_backBtn) m_backBtn->setEnabled(canGoBack());
    if (m_fwdBtn)  m_fwdBtn->setEnabled(canGoForward());
}

void ListerWidget::rewatch(const QString &path) {
    if (!m_watcher) return;
    const QStringList watching = m_watcher->directories();
    if (!watching.isEmpty()) m_watcher->removePaths(watching);
    if (!path.isEmpty()) m_watcher->addPath(path);
}

void ListerWidget::onWatchedDirChanged(const QString &path) {
    Q_UNUSED(path);
    if (m_refreshTimer) m_refreshTimer->start();
}

void ListerWidget::fireDebouncedRefresh() {
    /* Only refresh if the watched dir still matches the current path. */
    const QStringList watching = m_watcher ? m_watcher->directories() : QStringList{};
    if (watching.contains(m_path)) {
        refresh();
    } else if (!m_path.isEmpty()) {
        rewatch(m_path);
    }
}

void ListerWidget::selectAll()  { m_view->selectAll(); }
void ListerWidget::selectNone() { m_view->clearSelection(); }

void ListerWidget::selectByPattern(const QString &pattern) {
    if (!m_model || !m_view || !m_view->selectionModel()) return;
    if (pattern.isEmpty()) return;
    QByteArray pat = pattern.toUtf8();

    QItemSelection sel;
    QModelIndex firstHit;
    const int rows = m_model->rowCount();
    const int cols = m_model->columnCount();
    for (int row = 0; row < rows; ++row) {
        const dir_entry_t *e = m_model->entryAt(row);
        if (!e) continue;
        if (!pal_path_match(pat.constData(), e->name)) continue;
        QModelIndex left  = m_model->index(row, 0);
        QModelIndex right = m_model->index(row, cols - 1);
        sel.select(left, right);
        if (!firstHit.isValid()) firstHit = left;
    }
    m_view->selectionModel()->select(sel,
        QItemSelectionModel::ClearAndSelect | QItemSelectionModel::Rows);
    if (firstHit.isValid()) {
        m_view->setCurrentIndex(firstHit);
        m_view->scrollTo(firstHit, QAbstractItemView::PositionAtCenter);
    }
    updateStatus();
}

QStringList ListerWidget::selectedPaths() const {
    QStringList out;
    if (!m_view || !m_view->selectionModel() || !m_model) return out;
    QByteArray base = m_path.toUtf8();
    for (const QModelIndex &idx : m_view->selectionModel()->selectedRows()) {
        const dir_entry_t *e = m_model->entryAt(idx.row());
        if (!e) continue;
        char full[4096];
        pal_path_join(base.constData(), e->name, full, sizeof full);
        out << QString::fromUtf8(full);
    }
    return out;
}

void ListerWidget::setShowPattern(const QString &pattern) {
    m_showPattern = pattern;
    reapplyFilter();
}

void ListerWidget::setHideDotfiles(bool hide) {
    if (m_hideDotfiles == hide) return;
    m_hideDotfiles = hide;
    reapplyFilter();
}

void ListerWidget::toggleHideDotfiles() {
    setHideDotfiles(!m_hideDotfiles);
}

void ListerWidget::reapplyFilter() {
    m_model->setFilter(m_showPattern, QString(), m_hideDotfiles);
    updateStatus();
}

void ListerWidget::onDoubleClicked(const QModelIndex &index) {
    if (!index.isValid()) return;
    const dir_entry_t *e = m_model->entryAt(index.row());
    if (!e) return;

    char child[4096];
    pal_path_join(m_path.toUtf8().constData(), e->name, child, sizeof child);
    const QString full = QString::fromUtf8(child);

    if (dir_entry_is_dir(e)) {
        setPath(full);
        return;
    }

    /* File: run the default file-type action if one matches, otherwise let the
     * OS pick (macOS open, Explorer, xdg-open). */
    if (m_fileTypeActions) {
        if (const auto *def = m_fileTypeActions->defaultFor(full)) {
            FileTypeActions::run(def->command, full, this);
            return;
        }
    }
    QDesktopServices::openUrl(QUrl::fromLocalFile(full));
}

void ListerWidget::onHeaderClicked(int section) {
    if (!m_model) return;
    sort_field_t field;
    switch (section) {
    case DirBufferModel::ColName: field = SORT_NAME; break;
    case DirBufferModel::ColSize: field = SORT_SIZE; break;
    case DirBufferModel::ColDate: field = SORT_DATE; break;
    default: return;
    }
    bool reverse = (field == m_model->sortField()) ? !m_model->sortReverse() : false;
    m_model->setSort(field, reverse);
    m_view->header()->setSortIndicator(
        section, reverse ? Qt::DescendingOrder : Qt::AscendingOrder);
    updateStatus();
}

void ListerWidget::onContextMenu(const QPoint &pos) {
    if (!m_view || !m_model) return;
    QModelIndex idx = m_view->indexAt(pos);
    if (!idx.isValid()) return;

    if (!m_view->selectionModel()->isRowSelected(idx.row(), QModelIndex())) {
        m_view->selectionModel()->select(idx,
            QItemSelectionModel::ClearAndSelect | QItemSelectionModel::Rows);
        m_view->setCurrentIndex(idx);
    }

    const QStringList paths = selectedPaths();
    if (paths.isEmpty()) return;
    const bool single = (paths.size() == 1);
    const QString first = paths.first();

    QMenu menu(this);
    QAction *aOpen     = menu.addAction(tr("Open"));

    /* Open With submenu populated from the FileTypeActions registry if
     * available. Falls back to the old ad-hoc dialog if not. */
    QMenu   *openWith  = nullptr;
    QAction *aOpenWithRaw = nullptr;
    if (single && m_fileTypeActions) {
        const auto apps = m_fileTypeActions->actionsFor(first);
        if (!apps.isEmpty()) {
            openWith = menu.addMenu(tr("Open With"));
            m_fileTypeActions->populateMenu(openWith, first, this);
            openWith->addSeparator();
        }
    }
    if (!openWith) {
        aOpenWithRaw = menu.addAction(tr("Open With…"));
        aOpenWithRaw->setEnabled(single);
    }

    QAction *aReveal  = menu.addAction(tr("Reveal in Files"));
    QAction *aCopy    = menu.addAction(tr("Copy Path"));
    menu.addSeparator();
    QAction *aInfo    = menu.addAction(tr("Info"));
    QAction *aRename  = menu.addAction(tr("Rename"));
    menu.addSeparator();
    QAction *aTrash   = menu.addAction(tr("Move to Trash"));

    aRename->setEnabled(single);

    QAction *chosen = menu.exec(m_view->viewport()->mapToGlobal(pos));
    if (!chosen) return;

    if (chosen == aOpen) {
        if (single) {
            QFileInfo fi(first);
            if (fi.isDir()) setPath(first);
            else QDesktopServices::openUrl(QUrl::fromLocalFile(first));
        } else {
            for (const QString &p : paths)
                QDesktopServices::openUrl(QUrl::fromLocalFile(p));
        }
    } else if (aOpenWithRaw && chosen == aOpenWithRaw) {
        bool ok;
        QString cmd = QInputDialog::getText(this, tr("Open With"),
            tr("Command:"), QLineEdit::Normal, QString(), &ok);
        if (ok && !cmd.isEmpty())
            QProcess::startDetached(cmd, QStringList{first});
    } else if (chosen == aReveal) {
        QDesktopServices::openUrl(QUrl::fromLocalFile(QFileInfo(first).absolutePath()));
    } else if (chosen == aCopy) {
        QGuiApplication::clipboard()->setText(single ? first : paths.join(QLatin1Char('\n')));
    } else if (chosen == aInfo) {
        emit infoRequested(this);
    } else if (chosen == aRename) {
        emit renameRequested(this);
    } else if (chosen == aTrash) {
        emit deleteRequested(this);
    }
}

void ListerWidget::onPathEdited() {
    const QString typed = m_pathField->text();
    QByteArray utf = typed.toUtf8();
    if (!pal_file_is_dir(utf.constData())) {
        /* Not a directory — revert the field to current path */
        m_pathField->setText(m_path);
        return;
    }
    setPath(typed);
}

void ListerWidget::updateStatus() {
    if (!m_statusLabel || !m_model) return;

    DirBufferModel::Stats s = m_model->stats();

    QModelIndexList selected;
    if (m_view && m_view->selectionModel())
        selected = m_view->selectionModel()->selectedRows();

    int selCount = selected.size();
    quint64 selBytes = 0;
    for (const QModelIndex &idx : selected) {
        const dir_entry_t *e = m_model->entryAt(idx.row());
        if (e && !dir_entry_is_dir(e)) selBytes += e->size;
    }

    quint64 freeBytes = 0;
    if (!m_path.isEmpty()) {
        QStorageInfo si(m_path);
        if (si.isValid() && si.isReady()) freeBytes = si.bytesAvailable();
    }

    char total_buf[64], free_buf[64];
    pal_format_size(s.total_bytes, total_buf, sizeof total_buf);
    pal_format_size(freeBytes,     free_buf,  sizeof free_buf);

    QString text;
    if (selCount > 0) {
        char sel_buf[64];
        pal_format_size(selBytes, sel_buf, sizeof sel_buf);
        text = QStringLiteral("%1 selected (%2) | %3 files, %4 dirs (%5) — %6 free")
                .arg(selCount)
                .arg(QString::fromUtf8(sel_buf))
                .arg(s.total_files)
                .arg(s.total_dirs)
                .arg(QString::fromUtf8(total_buf))
                .arg(QString::fromUtf8(free_buf));
    } else {
        text = QStringLiteral("%1 files, %2 dirs (%3) — %4 free")
                .arg(s.total_files)
                .arg(s.total_dirs)
                .arg(QString::fromUtf8(total_buf))
                .arg(QString::fromUtf8(free_buf));
    }
    m_statusLabel->setText(text);
}

static bool mimeHasLocalFiles(const QMimeData *md) {
    if (!md || !md->hasUrls()) return false;
    const auto urls = md->urls();
    for (const QUrl &u : urls) {
        if (!u.isLocalFile()) return false;
    }
    return !urls.isEmpty();
}

static Qt::DropAction chooseAction(Qt::KeyboardModifiers mods) {
    return (mods & Qt::ControlModifier) ? Qt::MoveAction : Qt::CopyAction;
}

bool ListerWidget::eventFilter(QObject *obj, QEvent *event) {
    if (!m_view || obj != m_view->viewport())
        return QWidget::eventFilter(obj, event);

    switch (event->type()) {
    case QEvent::DragEnter: {
        auto *e = static_cast<QDragEnterEvent *>(event);
        if (!mimeHasLocalFiles(e->mimeData())) return false;
        e->setDropAction(chooseAction(e->modifiers()));
        e->accept();
        return true;
    }
    case QEvent::DragMove: {
        auto *e = static_cast<QDragMoveEvent *>(event);
        if (!mimeHasLocalFiles(e->mimeData())) return false;
        e->setDropAction(chooseAction(e->modifiers()));
        e->accept();
        return true;
    }
    case QEvent::Drop: {
        auto *e = static_cast<QDropEvent *>(event);
        if (!mimeHasLocalFiles(e->mimeData())) return false;
        Qt::DropAction act = chooseAction(e->modifiers());
        QList<QUrl> urls = e->mimeData()->urls();
        e->setDropAction(act);
        e->accept();
        emit dropReceived(this, urls, act);
        return true;
    }
    default:
        break;
    }
    return QWidget::eventFilter(obj, event);
}

/* --- Type-to-find --- */

void ListerWidget::keyPressEvent(QKeyEvent *event) {
    /* Only react when the tree view (or its children) holds the focus.
     * We don't want typing to hijack the path field / other widgets. */
    QWidget *fw = focusWidget();
    bool treeFocused = false;
    for (QWidget *w = fw; w; w = w->parentWidget()) {
        if (w == m_view) { treeFocused = true; break; }
    }
    if (!treeFocused) { QWidget::keyPressEvent(event); return; }

    /* Backspace trims the buffer. */
    if (event->key() == Qt::Key_Backspace) {
        if (!m_typeBuffer.isEmpty()) {
            m_typeBuffer.chop(1);
            if (!m_typeBuffer.isEmpty()) jumpToPrefix(m_typeBuffer);
            m_typeTimer->start();
        }
        event->accept();
        return;
    }

    if (event->key() == Qt::Key_Escape) {
        clearTypeToFindBuffer();
        event->accept();
        return;
    }

    const QString text = event->text();
    if (text.isEmpty() || !text.at(0).isPrint()) {
        QWidget::keyPressEvent(event);
        return;
    }
    /* Printable character — grow buffer, match. */
    m_typeBuffer += text;
    jumpToPrefix(m_typeBuffer);
    m_typeTimer->start();
    if (m_statusLabel) {
        m_statusLabel->setText(tr("Find: %1").arg(m_typeBuffer));
    }
    event->accept();
}

void ListerWidget::clearTypeToFindBuffer() {
    m_typeBuffer.clear();
    updateStatus();
}

void ListerWidget::jumpToPrefix(const QString &prefix) {
    if (!m_model || !m_view) return;
    const int rows = m_model->rowCount();
    if (rows == 0) return;
    /* Start from the row after the current one so repeated typing of the
     * same prefix cycles through matches. */
    int start = m_view->currentIndex().row();
    if (start < 0) start = -1;

    auto matches = [](const QString &name, const QString &pfx) {
        return name.startsWith(pfx, Qt::CaseInsensitive);
    };

    for (int step = 1; step <= rows; ++step) {
        int r = (start + step) % rows;
        const dir_entry_t *e = m_model->entryAt(r);
        if (!e) continue;
        if (matches(QString::fromUtf8(e->name), prefix)) {
            QModelIndex idx = m_model->index(r, 0);
            m_view->setCurrentIndex(idx);
            m_view->scrollTo(idx, QAbstractItemView::PositionAtCenter);
            return;
        }
    }
}

void ListerWidget::onCurrentRowChanged() {
    const QModelIndex idx = m_view->currentIndex();
    if (!idx.isValid()) { emit currentFileChanged(QString()); return; }
    const dir_entry_t *e = m_model->entryAt(idx.row());
    if (!e) { emit currentFileChanged(QString()); return; }
    char full[4096];
    pal_path_join(m_path.toUtf8().constData(), e->name, full, sizeof full);
    emit currentFileChanged(QString::fromUtf8(full));
}
