#pragma once

#include <QList>
#include <QString>
#include <QWidget>

class QPushButton;
class QVBoxLayout;

/*
 * Button Bank — Magellan-style button column that sits between the two
 * Listers. Built-in buttons are always present; user-defined buttons are
 * appended below them and persisted via QSettings.
 *
 * User buttons use {FILES} (space-separated selected paths) and {PATH}
 * (active lister's current directory) placeholders, matching the
 * conventions in macOS AppDelegate.m.
 */
class ButtonBank : public QWidget {
    Q_OBJECT
public:
    struct CustomButton {
        QString label;
        QString command;
    };

    explicit ButtonBank(QWidget *parent = nullptr);

    const QList<CustomButton> &customButtons() const { return m_custom; }
    void addCustomButton(const CustomButton &b);
    void removeCustomAt(int index);
    void replaceCustom(int index, const CustomButton &b);

signals:
    void copyClicked();
    void moveClicked();
    void deleteClicked();
    void renameClicked();
    void makeDirClicked();
    void infoClicked();
    void filterClicked();

    void parentClicked();
    void rootClicked();
    void refreshClicked();
    void allClicked();
    void noneClicked();

    /* Emitted when a user-defined button is pressed. Caller substitutes
     * {FILES} / {PATH} and runs. */
    void customTriggered(const QString &command);

    /* Emitted when the user wants to add/edit/remove custom buttons. The
     * MainWindow owns the dialog so it can show proper file pickers etc. */
    void manageCustomRequested();

private:
    QPushButton *makeButton(const QString &text, bool enabled);
    void rebuildCustomRows();
    void load();
    void save();

    QVBoxLayout         *m_layout       = nullptr;
    QList<QPushButton *> m_customButtons;
    QList<CustomButton>  m_custom;
};
