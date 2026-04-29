#pragma once

#include <QDockWidget>
#include <QPixmap>
#include <QString>

class QLabel;
class QPlainTextEdit;
class QScrollArea;
class QStackedWidget;
class QTimer;

/*
 * PreviewPane — right-side dockable preview of the active lister's
 * current selection. Renders images (via QImageReader) and text files
 * (first 128 KB). Everything else falls back to a short metadata card.
 *
 * Three width presets (Small/Medium/Large) are supported. The active
 * preset is persisted in QSettings. ⌘+/⌘- step through presets.
 * Hovering over an image preview shows a larger floating popup when
 * the pane is not already at the largest preset.
 */
class PreviewPane : public QDockWidget {
    Q_OBJECT
public:
    explicit PreviewPane(QWidget *parent = nullptr);

    /* Width (pixels) for each size preset index (0=Small, 1=Medium, 2=Large). */
    static int presetWidth(int preset);
    static constexpr int NUM_PRESETS = 3;

    int  sizePreset() const { return m_sizePreset; }
    void setSizePreset(int preset);
    void stepPreset(int delta);   /* +1 = larger, -1 = smaller */

signals:
    /* Emitted whenever the preset changes; width is the target dock width. */
    void sizePresetChanged(int preset, int width);

public slots:
    void showPath(const QString &path);
    void clear();

protected:
    bool eventFilter(QObject *obj, QEvent *event) override;

private:
    void showImage(const QString &path);
    void showText(const QString &path);
    void showMetadata(const QString &path);
    void showHoverPopup();
    void hideHoverPopup();

    static bool isImage(const QString &path);
    static bool isText(const QString &path);

    QStackedWidget *m_stack      = nullptr;
    QScrollArea    *m_imgScroll  = nullptr;
    QLabel         *m_imgLabel   = nullptr;
    QPlainTextEdit *m_text       = nullptr;
    QLabel         *m_meta       = nullptr;
    QLabel         *m_empty      = nullptr;
    QString         m_current;

    /* Full-resolution pixmap stored for hover popup. */
    QPixmap         m_fullPixmap;

    /* Hover popup — a borderless top-level label. */
    QLabel         *m_hoverPopup = nullptr;
    QTimer         *m_hoverTimer = nullptr;

    int             m_sizePreset = 0;
};
