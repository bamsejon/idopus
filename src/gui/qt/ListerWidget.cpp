#include "ListerWidget.h"
#include "DirBufferModel.h"

#include <QTreeView>
#include <QVBoxLayout>
#include <QHeaderView>
#include <QStandardPaths>

extern "C" {
#include "core/dir_entry.h"
#include "pal/pal_file.h"
}

ListerWidget::ListerWidget(const QString &initialPath, QWidget *parent)
    : QWidget(parent) {
    m_view = new QTreeView(this);
    m_view->setRootIsDecorated(false);
    m_view->setAlternatingRowColors(true);
    m_view->setSelectionBehavior(QAbstractItemView::SelectRows);
    m_view->setUniformRowHeights(true);
    m_view->setSortingEnabled(false);
    m_view->header()->setStretchLastSection(true);

    m_model = new DirBufferModel(this);
    m_view->setModel(m_model);

    auto *lay = new QVBoxLayout(this);
    lay->setContentsMargins(0, 0, 0, 0);
    lay->addWidget(m_view);

    connect(m_view, &QAbstractItemView::doubleClicked,
            this,   &ListerWidget::onDoubleClicked);

    setPath(initialPath);
}

void ListerWidget::setPath(const QString &path) {
    m_path = path;
    m_model->setPath(path);
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

void ListerWidget::refresh() {
    setPath(m_path);
}

void ListerWidget::onDoubleClicked(const QModelIndex &index) {
    if (!index.isValid()) return;
    const dir_entry_t *e = m_model->entryAt(index.row());
    if (!e || !dir_entry_is_dir(e)) return;

    char child[4096];
    pal_path_join(m_path.toUtf8().constData(), e->name, child, sizeof child);
    setPath(QString::fromUtf8(child));
}
