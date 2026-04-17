#pragma once

#include <QWidget>
#include <QString>

class QTreeView;
class QLineEdit;
class QPushButton;
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
    void goRoot();
    void refresh();
    void selectAll();
    void selectNone();
    void setActive(bool active);

signals:
    void pathChanged(const QString &newPath);

private slots:
    void onDoubleClicked(const QModelIndex &index);
    void onPathEdited();

private:
    QPushButton *makeButton(const QString &text, bool enabled);

    QTreeView      *m_view       = nullptr;
    DirBufferModel *m_model      = nullptr;
    QLineEdit      *m_pathField  = nullptr;
    QPushButton    *m_parentBtn  = nullptr;
    QPushButton    *m_refreshBtn = nullptr;
    QPushButton    *m_parent2Btn = nullptr;
    QPushButton    *m_rootBtn    = nullptr;
    QPushButton    *m_allBtn     = nullptr;
    QPushButton    *m_noneBtn    = nullptr;
    QPushButton    *m_copyBtn    = nullptr;
    QPushButton    *m_moveBtn    = nullptr;
    QPushButton    *m_deleteBtn  = nullptr;
    QPushButton    *m_renameBtn  = nullptr;
    QPushButton    *m_makeDirBtn = nullptr;
    QPushButton    *m_infoBtn    = nullptr;
    QPushButton    *m_filterBtn  = nullptr;
    QString         m_path;
};
