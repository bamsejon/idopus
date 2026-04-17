#include "ListerWidget.h"
#include "DirBufferModel.h"

#include <QTreeView>
#include <QLineEdit>
#include <QPushButton>
#include <QHBoxLayout>
#include <QVBoxLayout>
#include <QHeaderView>
#include <QShortcut>
#include <QStandardPaths>

extern "C" {
#include "core/dir_entry.h"
#include "pal/pal_file.h"
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

    /* --- Main layout: pathRow / actionRow / tree --- */
    auto *main = new QVBoxLayout(this);
    main->setContentsMargins(2, 2, 2, 2);
    main->setSpacing(4);
    main->addLayout(pathRow);
    main->addLayout(actionRow);
    main->addWidget(m_view, 1);

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
    return b;
}

void ListerWidget::setActive(bool active) {
    setStyleSheet(active
        ? QStringLiteral("ListerWidget { border: 2px solid palette(highlight); }")
        : QStringLiteral("ListerWidget { border: 2px solid transparent; }"));
}

void ListerWidget::setPath(const QString &path) {
    m_path = path;
    m_model->setPath(path);
    if (m_pathField) m_pathField->setText(path);
    m_view->resizeColumnToContents(DirBufferModel::ColName);
    m_view->resizeColumnToContents(DirBufferModel::ColSize);
    emit pathChanged(m_path);
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
