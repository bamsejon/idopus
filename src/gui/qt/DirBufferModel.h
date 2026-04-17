#pragma once

#include <QAbstractTableModel>
#include <QString>

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

    void setPath(const QString &path);
    const struct dir_entry *entryAt(int row) const;

    struct Stats {
        int     total_files = 0;
        int     total_dirs  = 0;
        quint64 total_bytes = 0;
    };
    Stats stats() const;

private:
    struct dir_buffer *m_buf = nullptr;
};
