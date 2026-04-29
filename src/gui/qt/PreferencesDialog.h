#pragma once

#include <QDialog>

class QCheckBox;
class QComboBox;
class QSpinBox;

/*
 * PreferencesDialog — QDialog backed by QSettings. Stores:
 *   general/hideDotfilesByDefault   (bool)
 *   general/confirmDelete           (bool)
 *   general/permanentDelete         (bool, else move to Trash)
 *   general/restorePathsOnLaunch    (bool)
 *   general/showButtonBank          (bool)
 *   general/historySize             (int, 16..512)
 *   general/previewSize             (int, 0=Small 1=Medium 2=Large)
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
    static constexpr const char *KEY_PREVIEW_SIZE  = "general/previewSize";

    /* Defaults matching the macOS build's behaviour. */
    static bool hideDotfilesDefault();
    static bool confirmDelete();
    static bool permanentDelete();
    static bool restorePaths();
    static bool showButtonBank();
    static int  historySize();
    static int  previewSize();   /* 0=Small, 1=Medium, 2=Large */

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
    QComboBox *m_previewSize = nullptr;
};
