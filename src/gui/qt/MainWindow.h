#pragma once

#include <QMainWindow>

class ListerWidget;

class MainWindow : public QMainWindow {
    Q_OBJECT
public:
    explicit MainWindow(const QString &leftPath, const QString &rightPath,
                        QWidget *parent = nullptr);

private slots:
    void onFocusChanged(QWidget *old, QWidget *now);

private:
    void setActive(ListerWidget *lister);
    void updateTitle();

    ListerWidget *m_left   = nullptr;
    ListerWidget *m_right  = nullptr;
    ListerWidget *m_active = nullptr;
};
