#include "DirBufferModel.h"

#include <QFileInfo>
#include <cstring>

extern "C" {
#include "core/dir_buffer.h"
#include "core/dir_entry.h"
#include "pal/pal_file.h"
#include "pal/pal_strings.h"
}

DirBufferModel::DirBufferModel(QObject *parent)
    : QAbstractTableModel(parent) {}

DirBufferModel::~DirBufferModel() {
    if (m_buf) dir_buffer_free(m_buf);
}

int DirBufferModel::rowCount(const QModelIndex &parent) const {
    if (parent.isValid() || !m_buf) return 0;
    return m_buf->stats.total_entries;
}

int DirBufferModel::columnCount(const QModelIndex &parent) const {
    if (parent.isValid()) return 0;
    return ColCount;
}

QVariant DirBufferModel::data(const QModelIndex &index, int role) const {
    if (!index.isValid() || !m_buf) return {};

    if (role == Qt::TextAlignmentRole && index.column() == ColSize) {
        return int(Qt::AlignRight | Qt::AlignVCenter);
    }

    if (role == Qt::DecorationRole && index.column() == ColName) {
        dir_entry_t *e = dir_buffer_get_entry(m_buf, index.row());
        if (!e) return {};
        if (dir_entry_is_dir(e)) {
            if (m_folderIcon.isNull())
                m_folderIcon = m_iconProvider.icon(QFileIconProvider::Folder);
            return m_folderIcon;
        }
        const char *dot = std::strrchr(e->name, '.');
        QString key = dot ? QString::fromUtf8(dot).toLower()
                          : QStringLiteral("<none>");
        auto it = m_iconCache.constFind(key);
        if (it != m_iconCache.constEnd()) return it.value();
        char full[4096];
        pal_path_join(m_buf->path, e->name, full, sizeof full);
        QIcon icon = m_iconProvider.icon(QFileInfo(QString::fromUtf8(full)));
        if (icon.isNull()) {
            if (m_fileIcon.isNull())
                m_fileIcon = m_iconProvider.icon(QFileIconProvider::File);
            icon = m_fileIcon;
        }
        m_iconCache.insert(key, icon);
        return icon;
    }

    if (role != Qt::DisplayRole) return {};

    dir_entry_t *e = dir_buffer_get_entry(m_buf, index.row());
    if (!e) return {};

    switch (index.column()) {
    case ColName:
        return QString::fromUtf8(e->name);
    case ColSize: {
        if (dir_entry_is_dir(e)) return QStringLiteral("<DIR>");
        char buf[64];
        pal_format_size(e->size, buf, sizeof buf);
        return QString::fromUtf8(buf);
    }
    case ColDate: {
        char buf[64];
        pal_format_date(static_cast<long>(e->date_modified), buf, sizeof buf);
        return QString::fromUtf8(buf);
    }
    }
    return {};
}

QVariant DirBufferModel::headerData(int section, Qt::Orientation orientation,
                                    int role) const {
    if (role != Qt::DisplayRole || orientation != Qt::Horizontal) return {};
    switch (section) {
    case ColName: return QStringLiteral("Name");
    case ColSize: return QStringLiteral("Size");
    case ColDate: return QStringLiteral("Modified");
    }
    return {};
}

void DirBufferModel::setPath(const QString &path) {
    beginResetModel();
    if (m_buf) { dir_buffer_free(m_buf); m_buf = nullptr; }
    m_buf = dir_buffer_create();
    if (m_buf) {
        QByteArray utf = path.toUtf8();
        dir_buffer_read(m_buf, utf.constData());
        dir_buffer_set_sort(m_buf, SORT_NAME, false, SEPARATE_DIRS_FIRST);
        dir_buffer_sort(m_buf);
    }
    endResetModel();
}

const dir_entry *DirBufferModel::entryAt(int row) const {
    if (!m_buf) return nullptr;
    return dir_buffer_get_entry(m_buf, row);
}

void DirBufferModel::setFilter(const QString &showPattern,
                                const QString &hidePattern,
                                bool rejectHidden) {
    if (!m_buf) return;
    beginResetModel();
    QByteArray s = showPattern.toUtf8();
    QByteArray h = hidePattern.toUtf8();
    dir_buffer_set_filter(m_buf,
        showPattern.isEmpty() ? nullptr : s.constData(),
        hidePattern.isEmpty() ? nullptr : h.constData(),
        rejectHidden);
    dir_buffer_apply_filter(m_buf);
    endResetModel();
}

DirBufferModel::Stats DirBufferModel::stats() const {
    Stats s;
    if (m_buf) {
        s.total_files = m_buf->stats.total_files;
        s.total_dirs  = m_buf->stats.total_dirs;
        s.total_bytes = m_buf->stats.total_bytes;
    }
    return s;
}
