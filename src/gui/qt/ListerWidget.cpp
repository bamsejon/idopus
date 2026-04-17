#include "ListerWidget.h"
#include "DirBufferModel.h"

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
    m_view->setSortingEnabled(false);
    m_view->header()->setStretchLastSection(true);

    m_model = new DirBufferModel(this);
    m_view->setModel(m_model);

    connect(m_view->selectionModel(), &QItemSelectionModel::selectionChanged,
            this, [this](const QItemSelection&, const QItemSelection&) { updateStatus(); });

    /* --- Path row: Parent ↑, Refresh ↻, path QLineEdit --- */
    m_parentBtn  = makeButton(QStringLiteral("↑"), true);
    m_refreshBtn = makeButton(QStringLiteral("↻"), true);
    m_parentBtn->setFixedWidth(32);
    m_refreshBtn->setFixedWidth(32);
    connect(m_parentBtn,  &QPushButton::clicked, this, &ListerWidget::goParent);
    connect(m_refreshBtn, &QPushButton::clicked, this, &ListerWidget::refresh);

    m_pathField = new QLineEdit(this);
    m_pathField->setClearButtonEnabled(true);
    connect(m_pathField, &QLineEdit::returnPressed, this, &ListerWidget::onPathEdited);

    auto *pathRow = new QHBoxLayout;
    pathRow->setContentsMargins(0, 0, 0, 0);
    pathRow->setSpacing(4);
    pathRow->addWidget(m_parentBtn);
    pathRow->addWidget(m_refreshBtn);
    pathRow->addWidget(m_pathField, 1);

    /* --- Action row: Copy · Move · Delete · Rename · MakeDir · Info · Filter
                       | Parent · Root | All · None --- */
    m_copyBtn    = makeButton(QStringLiteral("Copy"),    false);
    m_moveBtn    = makeButton(QStringLiteral("Move"),    false);
    m_deleteBtn  = makeButton(QStringLiteral("Delete"),  false);
    m_renameBtn  = makeButton(QStringLiteral("Rename"),  false);
    m_makeDirBtn = makeButton(QStringLiteral("MakeDir"), false);
    m_infoBtn    = makeButton(QStringLiteral("Info"),    false);
    m_filterBtn  = makeButton(QStringLiteral("Filter"),  false);

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

    /* --- Main layout: pathRow / actionRow / tree / statusRow --- */
    auto *main = new QVBoxLayout(this);
    main->setContentsMargins(2, 2, 2, 2);
    main->setSpacing(4);
    main->addLayout(pathRow);
    main->addLayout(actionRow);
    main->addWidget(m_view, 1);
    main->addLayout(statusRow);

    connect(m_view, &QAbstractItemView::doubleClicked,
            this,   &ListerWidget::onDoubleClicked);

    /* Keyboard: Alt+Up still triggers goParent on the focused pane */
    auto *sc = new QShortcut(QKeySequence(Qt::ALT | Qt::Key_Up), this);
    sc->setContext(Qt::WidgetWithChildrenShortcut);
    connect(sc, &QShortcut::activated, this, &ListerWidget::goParent);

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
    m_path = path;
    m_model->setPath(path);
    if (m_pathField) m_pathField->setText(path);
    m_view->resizeColumnToContents(DirBufferModel::ColName);
    m_view->resizeColumnToContents(DirBufferModel::ColSize);
    emit pathChanged(m_path);
    updateStatus();
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
    setPath(QStringLiteral("/"));
}

void ListerWidget::refresh() {
    setPath(m_path);
}

void ListerWidget::selectAll()  { m_view->selectAll(); }
void ListerWidget::selectNone() { m_view->clearSelection(); }

void ListerWidget::onDoubleClicked(const QModelIndex &index) {
    if (!index.isValid()) return;
    const dir_entry_t *e = m_model->entryAt(index.row());
    if (!e || !dir_entry_is_dir(e)) return;

    char child[4096];
    pal_path_join(m_path.toUtf8().constData(), e->name, child, sizeof child);
    setPath(QString::fromUtf8(child));
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
