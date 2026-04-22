#pragma once

#include <QList>
#include <QObject>
#include <QString>

/*
 * iDOpus — File Type Actions registry (Qt build).
 *
 * Stores a list of (extension, title, command, isDefault) records. "ext" is
 * matched case-insensitively and can be empty to mean "any file". Commands use
 * {FILE} as a placeholder for the target path; if no placeholder is present
 * the path is appended as an argument.
 *
 * Persisted via QSettings under the existing iDOpus app/org scope so Linux
 * and Windows installs carry their definitions forward. Mirrors the macOS
 * `addFileTypeAction:` model from AppDelegate.m.
 */

class QMenu;
class QWidget;

class FileTypeActions : public QObject {
    Q_OBJECT
public:
    struct Action {
        QString ext;       /* e.g. "txt" or "" for any file */
        QString title;     /* user-visible menu label */
        QString command;   /* shell command; {FILE} = absolute path */
        bool    isDefault = false;  /* used on double-click for this ext */
    };

    explicit FileTypeActions(QObject *parent = nullptr);

    const QList<Action> &actions() const { return m_actions; }
    QList<Action>       actionsFor(const QString &path) const;
    /* Returns the default action for this path, or nullptr if none. */
    const Action *defaultFor(const QString &path) const;

    void   addAction(const Action &a);
    void   removeAt(int index);
    void   replace(int index, const Action &a);
    void   setDefault(int index, bool on);

    /* Build a Qt menu of applicable actions for `path` (with target already
     * captured in each QAction's data, so callers can just connect and go). */
    void   populateMenu(QMenu *menu, const QString &path, QWidget *parentForErrors) const;

    /* Convenience: run a command against a single path. */
    static bool run(const QString &command, const QString &path,
                    QWidget *parentForErrors = nullptr);

signals:
    void changed();

private:
    void load();
    void save();

    QList<Action> m_actions;
};
