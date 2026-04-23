#pragma once

#include <QDockWidget>
#include <QString>

class QLabel;
class QPlainTextEdit;
class QScrollArea;
class QStackedWidget;

/*
 * PreviewPane — right-side dockable preview of the active lister's
 * current selection. Renders images (via QImageReader) and text files
 * (first 128 KB). Everything else falls back to a short metadata card.
 */
class PreviewPane : public QDockWidget {
    Q_OBJECT
public:
    explicit PreviewPane(QWidget *parent = nullptr);

public slots:
    void showPath(const QString &path);
    void clear();

private:
    void showImage(const QString &path);
    void showText(const QString &path);
    void showMetadata(const QString &path);

    static bool isImage(const QString &path);
    static bool isText(const QString &path);

    QStackedWidget *m_stack   = nullptr;
    QScrollArea    *m_imgScroll = nullptr;
    QLabel         *m_imgLabel  = nullptr;
    QPlainTextEdit *m_text      = nullptr;
    QLabel         *m_meta      = nullptr;
    QLabel         *m_empty     = nullptr;
    QString         m_current;
};
