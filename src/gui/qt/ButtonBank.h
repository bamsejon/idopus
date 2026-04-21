#pragma once

#include <QWidget>

class QPushButton;

class ButtonBank : public QWidget {
    Q_OBJECT
public:
    explicit ButtonBank(QWidget *parent = nullptr);

signals:
    /* File ops — stubbed (buttons disabled) for now */
    void copyClicked();
    void moveClicked();
    void deleteClicked();
    void renameClicked();
    void makeDirClicked();
    void infoClicked();
    void filterClicked();

    /* Wired to the active pane */
    void parentClicked();
    void rootClicked();
    void refreshClicked();
    void allClicked();
    void noneClicked();

private:
    QPushButton *makeButton(const QString &text, bool enabled);
};
