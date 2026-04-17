#pragma once

#include <QMainWindow>

class ListerWidget;
class ButtonBank;

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

private:
    void setActive(ListerWidget *lister);
    void updateTitle();
    void wireLister(ListerWidget *lister);
    ListerWidget *peerOf(ListerWidget *lister) const;

    ListerWidget *m_left   = nullptr;
    ListerWidget *m_right  = nullptr;
    ListerWidget *m_active = nullptr;
    ButtonBank   *m_bank   = nullptr;
};
