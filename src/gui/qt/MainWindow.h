#pragma once

#include <QMainWindow>
#include <QList>
#include <QUrl>
#include <QString>
#include <QPair>

class ListerWidget;
class ButtonBank;
class QMenu;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(const QString &leftPath, const QString &rightPath,
                        QWidget *parent = nullptr);

private slots:
    void onFocusChanged(QWidget *old, QWidget *now);
    void doCopy(ListerWidget *src);
    void doMove(ListerWidget *src);
    void doDelete(ListerWidget *src);
    void doRename(ListerWidget *src);
    void doMakeDir(ListerWidget *src);
    void doInfo(ListerWidget *src);
    void doFilter(ListerWidget *src);
    void onDrop(ListerWidget *dest, const QList<QUrl> &urls, Qt::DropAction action);
    void addBookmarkForActive();
    void manageBookmarks();

private:
    void setActive(ListerWidget *lister);
    void updateTitle();
    void wireLister(ListerWidget *lister);
    ListerWidget *peerOf(ListerWidget *lister) const;
    void buildMenuBar();
    void rebuildBookmarksMenu();
    void loadBookmarks();
    void saveBookmarks();

    ListerWidget *m_left   = nullptr;
    ListerWidget *m_right  = nullptr;
    ListerWidget *m_active = nullptr;
    ButtonBank   *m_bank   = nullptr;
    QMenu        *m_bookmarksMenu = nullptr;

    /* Bookmark entries as (title, path) pairs. Empty title → show the path. */
    QList<QPair<QString, QString>> m_bookmarks;
};
