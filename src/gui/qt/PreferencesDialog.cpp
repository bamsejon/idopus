#include "PreferencesDialog.h"

#include <QCheckBox>
#include <QDialogButtonBox>
#include <QFormLayout>
#include <QGroupBox>
#include <QPushButton>
#include <QSettings>
#include <QSpinBox>
#include <QVBoxLayout>

static bool readBool(const char *key, bool def) {
    return QSettings().value(QString::fromLatin1(key), def).toBool();
}
static int readInt(const char *key, int def) {
    return QSettings().value(QString::fromLatin1(key), def).toInt();
}

bool PreferencesDialog::hideDotfilesDefault() { return readBool(KEY_HIDE_DOT,      false); }
bool PreferencesDialog::confirmDelete()       { return readBool(KEY_CONFIRM_DEL,   true);  }
bool PreferencesDialog::permanentDelete()     { return readBool(KEY_PERMA_DEL,     false); }
bool PreferencesDialog::restorePaths()        { return readBool(KEY_RESTORE_PATHS, true);  }
bool PreferencesDialog::showButtonBank()      { return readBool(KEY_SHOW_BANK,     true);  }
int  PreferencesDialog::historySize()         { return readInt (KEY_HISTORY_SIZE,  128);   }

PreferencesDialog::PreferencesDialog(QWidget *parent) : QDialog(parent) {
    setWindowTitle(tr("Preferences"));
    resize(460, 360);

    auto *displayGroup = new QGroupBox(tr("Display"), this);
    m_hideDot  = new QCheckBox(tr("Hide dotfiles in new listers"), displayGroup);
    m_showBank = new QCheckBox(tr("Show Button Bank"),              displayGroup);
    auto *dLay = new QVBoxLayout(displayGroup);
    dLay->addWidget(m_hideDot);
    dLay->addWidget(m_showBank);

    auto *deleteGroup = new QGroupBox(tr("Deletion"), this);
    m_confirmDel = new QCheckBox(tr("Ask before deleting"),      deleteGroup);
    m_permaDel   = new QCheckBox(tr("Permanently delete (skip Trash)"), deleteGroup);
    auto *delLay = new QVBoxLayout(deleteGroup);
    delLay->addWidget(m_confirmDel);
    delLay->addWidget(m_permaDel);

    auto *sessionGroup = new QGroupBox(tr("Session"), this);
    m_restore = new QCheckBox(tr("Restore last paths on launch"), sessionGroup);
    m_history = new QSpinBox(sessionGroup);
    m_history->setRange(16, 512);
    m_history->setSuffix(tr("  entries"));

    auto *histForm = new QFormLayout;
    histForm->addRow(tr("History stack size:"), m_history);

    auto *sLay = new QVBoxLayout(sessionGroup);
    sLay->addWidget(m_restore);
    sLay->addLayout(histForm);

    auto *buttons = new QDialogButtonBox(
        QDialogButtonBox::Ok | QDialogButtonBox::Cancel |
        QDialogButtonBox::Apply | QDialogButtonBox::RestoreDefaults, this);
    auto *applyBtn = buttons->button(QDialogButtonBox::Apply);
    auto *resetBtn = buttons->button(QDialogButtonBox::RestoreDefaults);

    connect(buttons, &QDialogButtonBox::accepted, this, [this]{ save(); emit settingsChanged(); accept(); });
    connect(buttons, &QDialogButtonBox::rejected, this, &QDialog::reject);
    connect(applyBtn, &QPushButton::clicked, this, [this]{ save(); emit settingsChanged(); });
    connect(resetBtn, &QPushButton::clicked, this, &PreferencesDialog::resetToDefaults);

    auto *main = new QVBoxLayout(this);
    main->addWidget(displayGroup);
    main->addWidget(deleteGroup);
    main->addWidget(sessionGroup);
    main->addStretch(1);
    main->addWidget(buttons);

    load();
}

void PreferencesDialog::load() {
    m_hideDot->setChecked(hideDotfilesDefault());
    m_showBank->setChecked(showButtonBank());
    m_confirmDel->setChecked(confirmDelete());
    m_permaDel->setChecked(permanentDelete());
    m_restore->setChecked(restorePaths());
    m_history->setValue(historySize());
}

void PreferencesDialog::save() {
    QSettings s;
    s.setValue(QString::fromLatin1(KEY_HIDE_DOT),       m_hideDot->isChecked());
    s.setValue(QString::fromLatin1(KEY_SHOW_BANK),      m_showBank->isChecked());
    s.setValue(QString::fromLatin1(KEY_CONFIRM_DEL),    m_confirmDel->isChecked());
    s.setValue(QString::fromLatin1(KEY_PERMA_DEL),      m_permaDel->isChecked());
    s.setValue(QString::fromLatin1(KEY_RESTORE_PATHS),  m_restore->isChecked());
    s.setValue(QString::fromLatin1(KEY_HISTORY_SIZE),   m_history->value());
}

void PreferencesDialog::resetToDefaults() {
    m_hideDot->setChecked(false);
    m_showBank->setChecked(true);
    m_confirmDel->setChecked(true);
    m_permaDel->setChecked(false);
    m_restore->setChecked(true);
    m_history->setValue(128);
}
