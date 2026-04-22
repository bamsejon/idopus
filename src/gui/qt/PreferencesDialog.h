#pragma once

#include <QDialog>

class QCheckBox;
class QSpinBox;

/*
 * PreferencesDialog — QDialog backed by QSettings. Stores:
 *   general/hideDotfilesByDefault   (bool)
 *   general/confirmDelete           (bool)
 *   general/permanentDelete         (bool, else move to Trash)
 *   general/restorePathsOnLaunch    (bool)
 *   general/showButtonBank          (bool)
 *   general/historySize             (int, 16..512)
 */
class PreferencesDialog : public QDialog {
    Q_OBJECT
public:
    explicit PreferencesDialog(QWidget *parent = nullptr);

    /* Keys — exposed so MainWindow / ListerWidget can read the same setting
     * names without copy-pasting strings. */
    static constexpr const char *KEY_HIDE_DOT      = "general/hideDotfilesByDefault";
    static constexpr const char *KEY_CONFIRM_DEL   = "general/confirmDelete";
    static constexpr const char *KEY_PERMA_DEL     = "general/permanentDelete";
    static constexpr const char *KEY_RESTORE_PATHS = "general/restorePathsOnLaunch";
    static constexpr const char *KEY_SHOW_BANK     = "general/showButtonBank";
    static constexpr const char *KEY_HISTORY_SIZE  = "general/historySize";

    /* Defaults matching the macOS build's behaviour. */
    static bool hideDotfilesDefault();
    static bool confirmDelete();
    static bool permanentDelete();
    static bool restorePaths();
    static bool showButtonBank();
    static int  historySize();

signals:
    void settingsChanged();

private slots:
    void resetToDefaults();

private:
    void load();
    void save();

    QCheckBox *m_hideDot = nullptr;
    QCheckBox *m_confirmDel = nullptr;
    QCheckBox *m_permaDel = nullptr;
    QCheckBox *m_restore = nullptr;
    QCheckBox *m_showBank = nullptr;
    QSpinBox  *m_history = nullptr;
};
