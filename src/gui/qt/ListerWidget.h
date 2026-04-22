#pragma once

#include <QWidget>
#include <QString>
#include <QStringList>
#include <QList>
#include <QUrl>

class QTreeView;
class QLineEdit;
class QPushButton;
class QLabel;
class QModelIndex;
class QEvent;
class QObject;
class QFileSystemWatcher;
class QTimer;
class DirBufferModel;
class FileTypeActions;

class ListerWidget : public QWidget {
    Q_OBJECT
public:
    explicit ListerWidget(const QString &initialPath, QWidget *parent = nullptr);

    QString currentPath() const { return m_path; }
    QStringList selectedPaths() const;
    QString currentShowPattern() const { return m_showPattern; }
    bool    hideDotfiles() const       { return m_hideDotfiles; }

    /* MainWindow passes in the shared registry so double-click + context
     * menu can honour user-defined file type actions. May be nullptr. */
    void setFileTypeActions(FileTypeActions *a) { m_fileTypeActions = a; }

public slots:
    void setPath(const QString &path);
    void goParent();
    void goHome();
    void goRoot();
    void goBack();
    void goForward();
    void refresh();
    bool canGoBack() const    { return m_historyIndex > 0; }
    bool canGoForward() const { return m_historyIndex + 1 < m_history.size(); }
    void selectAll();
    void selectNone();
    void selectByPattern(const QString &pattern);
    void setActive(bool active);
    void setShowPattern(const QString &pattern);
    void setHideDotfiles(bool hide);
    void toggleHideDotfiles();

signals:
    void pathChanged(const QString &newPath);
    void historyChanged();  /* emitted when back/forward availability might have changed */
    void copyRequested(ListerWidget *source);
    void moveRequested(ListerWidget *source);
    void deleteRequested(ListerWidget *source);
    void renameRequested(ListerWidget *source);
    void makeDirRequested(ListerWidget *source);
    void infoRequested(ListerWidget *source);
    void filterRequested(ListerWidget *source);
    void dropReceived(ListerWidget *dest, const QList<QUrl> &urls,
                      Qt::DropAction action);

protected:
    bool eventFilter(QObject *obj, QEvent *event) override;

private slots:
    void onDoubleClicked(const QModelIndex &index);
    void onPathEdited();
    void onHeaderClicked(int section);
    void onContextMenu(const QPoint &pos);
    void updateStatus();
    void onWatchedDirChanged(const QString &path);
    void fireDebouncedRefresh();

private:
    QPushButton *makeButton(const QString &text, bool enabled);
    void setPathInternal(const QString &path, bool recordHistory);
    void updateNavButtons();
    void rewatch(const QString &path);

    QTreeView      *m_view       = nullptr;
    DirBufferModel *m_model      = nullptr;
    QLineEdit      *m_pathField  = nullptr;
    QPushButton    *m_backBtn    = nullptr;
    QPushButton    *m_fwdBtn     = nullptr;
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
    QLabel         *m_stateBadge  = nullptr;
    QLabel         *m_statusLabel = nullptr;
    QFileSystemWatcher *m_watcher       = nullptr;
    QTimer             *m_refreshTimer  = nullptr;
    FileTypeActions    *m_fileTypeActions = nullptr;
    bool            m_active      = false;
    QString         m_path;
    QString         m_showPattern;
    bool            m_hideDotfiles = false;
    QStringList     m_history;
    int             m_historyIndex = -1;

    void reapplyFilter();
};
