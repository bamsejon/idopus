#pragma once

#include <QWidget>
#include <QString>

class QTreeView;
class QModelIndex;
class DirBufferModel;

class ListerWidget : public QWidget {
    Q_OBJECT
public:
    explicit ListerWidget(const QString &initialPath, QWidget *parent = nullptr);

    QString currentPath() const { return m_path; }

public slots:
    void setPath(const QString &path);
    void goParent();
    void goHome();
    void refresh();

signals:
    void pathChanged(const QString &newPath);

private slots:
    void onDoubleClicked(const QModelIndex &index);

private:
    QTreeView      *m_view  = nullptr;
    DirBufferModel *m_model = nullptr;
    QString         m_path;
};
