#pragma once

#include <QDialog>

class QCheckBox;
class QLabel;

/*
 * ConflictDialog — shown when a copy / move target already exists.
 *
 * Offers Replace / Skip / Keep Both / Cancel All. Merge is available only
 * for dir-on-dir conflicts. "Apply to all similar conflicts" remembers
 * the answer for the rest of the batch (separately per file-vs-dir kind).
 */
class ConflictDialog : public QDialog {
    Q_OBJECT
public:
    enum Action { Replace = 0, Skip = 1, KeepBoth = 2, Merge = 3, CancelAll = 4 };

    ConflictDialog(const QString &src, const QString &dst, bool isDir,
                   QWidget *parent = nullptr);

    int  chosenAction() const { return m_action; }
    bool applyToAll()   const;

private:
    void setAction(int a);

    QCheckBox *m_applyAll = nullptr;
    int        m_action   = Skip;
};
