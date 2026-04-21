#pragma once

#include <QAbstractTableModel>
#include <QFileIconProvider>
#include <QHash>
#include <QIcon>
#include <QString>

extern "C" {
#include "core/dir_entry.h"
}

struct dir_buffer;
struct dir_entry;

class DirBufferModel : public QAbstractTableModel {
    Q_OBJECT
public:
    enum Column { ColName = 0, ColSize = 1, ColDate = 2, ColCount = 3 };

    explicit DirBufferModel(QObject *parent = nullptr);
    ~DirBufferModel() override;

    int rowCount(const QModelIndex &parent = QModelIndex()) const override;
    int columnCount(const QModelIndex &parent = QModelIndex()) const override;
    QVariant data(const QModelIndex &index, int role) const override;
    QVariant headerData(int section, Qt::Orientation orientation,
                        int role = Qt::DisplayRole) const override;
    Qt::ItemFlags  flags(const QModelIndex &index) const override;
    QStringList    mimeTypes() const override;
    QMimeData     *mimeData(const QModelIndexList &indexes) const override;
    Qt::DropActions supportedDragActions() const override
        { return Qt::CopyAction | Qt::MoveAction; }

    void setPath(const QString &path);
    void setFilter(const QString &showPattern,
                   const QString &hidePattern,
                   bool rejectHidden);
    const struct dir_entry *entryAt(int row) const;

    void setSort(sort_field_t field, bool reverse,
                 separation_t sep = SEPARATE_DIRS_FIRST);
    sort_field_t sortField()   const { return m_sortField; }
    bool         sortReverse() const { return m_sortReverse; }

    struct Stats {
        int     total_files = 0;
        int     total_dirs  = 0;
        quint64 total_bytes = 0;
    };
    Stats stats() const;

private:
    struct dir_buffer *m_buf = nullptr;
    QFileIconProvider m_iconProvider;
    mutable QHash<QString, QIcon> m_iconCache;
    mutable QIcon m_folderIcon;
    mutable QIcon m_fileIcon;

    sort_field_t m_sortField   = SORT_NAME;
    bool         m_sortReverse = false;
    separation_t m_sortSep     = SEPARATE_DIRS_FIRST;
};
