#include "FileTypeActions.h"

#include <QAction>
#include <QFileInfo>
#include <QMenu>
#include <QMessageBox>
#include <QProcess>
#include <QSettings>
#include <QStringList>

FileTypeActions::FileTypeActions(QObject *parent) : QObject(parent) {
    load();
}

QList<FileTypeActions::Action>
FileTypeActions::actionsFor(const QString &path) const {
    QList<Action> out;
    const QString ext = QFileInfo(path).suffix().toLower();
    for (const auto &a : m_actions) {
        if (a.ext.isEmpty() || a.ext.compare(ext, Qt::CaseInsensitive) == 0)
            out.append(a);
    }
    return out;
}

const FileTypeActions::Action *
FileTypeActions::defaultFor(const QString &path) const {
    const QString ext = QFileInfo(path).suffix().toLower();
    const Action *fallback = nullptr;
    for (const auto &a : m_actions) {
        if (!a.isDefault) continue;
        if (a.ext.compare(ext, Qt::CaseInsensitive) == 0) return &a;
        if (a.ext.isEmpty() && !fallback) fallback = &a;
    }
    return fallback;
}

void FileTypeActions::addAction(const Action &a) {
    m_actions.append(a);
    save();
    emit changed();
}

void FileTypeActions::removeAt(int index) {
    if (index < 0 || index >= m_actions.size()) return;
    m_actions.removeAt(index);
    save();
    emit changed();
}

void FileTypeActions::replace(int index, const Action &a) {
    if (index < 0 || index >= m_actions.size()) return;
    m_actions[index] = a;
    save();
    emit changed();
}

void FileTypeActions::setDefault(int index, bool on) {
    if (index < 0 || index >= m_actions.size()) return;
    if (on) {
        /* Only one default per (ext) */
        const QString ext = m_actions[index].ext;
        for (int i = 0; i < m_actions.size(); ++i)
            if (i != index && m_actions[i].ext.compare(ext, Qt::CaseInsensitive) == 0)
                m_actions[i].isDefault = false;
    }
    m_actions[index].isDefault = on;
    save();
    emit changed();
}

void FileTypeActions::populateMenu(QMenu *menu, const QString &path,
                                    QWidget *parentForErrors) const {
    if (!menu) return;
    const QList<Action> apps = actionsFor(path);
    if (apps.isEmpty()) return;

    for (const Action &a : apps) {
        QString label = a.title.isEmpty() ? a.command : a.title;
        if (a.isDefault) label += QStringLiteral("  (default)");
        QAction *act = menu->addAction(label);
        const QString cmd = a.command;
        QObject::connect(act, &QAction::triggered, menu, [cmd, path, parentForErrors]{
            FileTypeActions::run(cmd, path, parentForErrors);
        });
    }
}

bool FileTypeActions::run(const QString &command, const QString &path,
                           QWidget *parentForErrors) {
    if (command.isEmpty()) return false;

    /* Substitute {FILE} if present, otherwise append path as the last arg. */
    QStringList tokens = QProcess::splitCommand(command);
    bool substituted = false;
    for (QString &t : tokens) {
        if (t.contains(QStringLiteral("{FILE}"))) {
            t.replace(QStringLiteral("{FILE}"), path);
            substituted = true;
        }
    }
    if (tokens.isEmpty()) return false;
    if (!substituted) tokens.append(path);

    const QString program = tokens.takeFirst();
    bool ok = QProcess::startDetached(program, tokens);
    if (!ok && parentForErrors) {
        QMessageBox::warning(parentForErrors, QObject::tr("Open With"),
            QObject::tr("Could not launch:\n%1").arg(command));
    }
    return ok;
}

void FileTypeActions::load() {
    m_actions.clear();
    QSettings s;
    const int n = s.beginReadArray(QStringLiteral("filetypes"));
    m_actions.reserve(n);
    for (int i = 0; i < n; ++i) {
        s.setArrayIndex(i);
        Action a;
        a.ext       = s.value(QStringLiteral("ext")).toString();
        a.title     = s.value(QStringLiteral("title")).toString();
        a.command   = s.value(QStringLiteral("command")).toString();
        a.isDefault = s.value(QStringLiteral("default"), false).toBool();
        if (!a.command.isEmpty()) m_actions.append(a);
    }
    s.endArray();
}

void FileTypeActions::save() {
    QSettings s;
    s.beginWriteArray(QStringLiteral("filetypes"), m_actions.size());
    for (int i = 0; i < m_actions.size(); ++i) {
        s.setArrayIndex(i);
        const Action &a = m_actions[i];
        s.setValue(QStringLiteral("ext"),     a.ext);
        s.setValue(QStringLiteral("title"),   a.title);
        s.setValue(QStringLiteral("command"), a.command);
        s.setValue(QStringLiteral("default"), a.isDefault);
    }
    s.endArray();
}
