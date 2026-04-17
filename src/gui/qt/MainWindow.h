#pragma once

#include <QMainWindow>

class ListerWidget;
class QAction;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(const QString &initialPath, QWidget *parent = nullptr);

private slots:
    void onParent();
    void onRefresh();
    void onHome();

private:
    ListerWidget *m_lister     = nullptr;
    QAction      *m_actParent  = nullptr;
    QAction      *m_actRefresh = nullptr;
    QAction      *m_actHome    = nullptr;
};
