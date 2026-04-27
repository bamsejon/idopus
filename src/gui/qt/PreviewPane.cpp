#include "PreviewPane.h"

#include <QApplication>
#include <QCursor>
#include <QDateTime>
#include <QEvent>
#include <QFile>
#include <QFileInfo>
#include <QGuiApplication>
#include <QImageReader>
#include <QLabel>
#include <QLocale>
#include <QPixmap>
#include <QPlainTextEdit>
#include <QRect>
#include <QScreen>
#include <QScrollArea>
#include <QSet>
#include <QStackedWidget>
#include <QTimer>

static const int PRESET_WIDTHS[] = { 260, 420, 600 };

int PreviewPane::presetWidth(int preset)
{
    preset = qBound(0, preset, NUM_PRESETS - 1);
    return PRESET_WIDTHS[preset];
}

PreviewPane::PreviewPane(QWidget *parent)
    : QDockWidget(tr("Preview"), parent) {
    setObjectName(QStringLiteral("PreviewPane"));
    setAllowedAreas(Qt::LeftDockWidgetArea | Qt::RightDockWidgetArea);

    m_stack = new QStackedWidget(this);

    /* Image view with scroll area. */
    m_imgScroll = new QScrollArea(m_stack);
    m_imgScroll->setAlignment(Qt::AlignCenter);
    m_imgScroll->setWidgetResizable(true);
    m_imgLabel = new QLabel(m_imgScroll);
    m_imgLabel->setAlignment(Qt::AlignCenter);
    m_imgLabel->setMinimumSize(200, 200);
    m_imgScroll->setWidget(m_imgLabel);

    /* Text view. */
    m_text = new QPlainTextEdit(m_stack);
    m_text->setReadOnly(true);
    QFont mono = m_text->font();
    mono.setStyleHint(QFont::Monospace);
    mono.setFamily(QStringLiteral("Menlo, Consolas, monospace"));
    m_text->setFont(mono);

    /* Metadata / fallback view. */
    m_meta = new QLabel(m_stack);
    m_meta->setAlignment(Qt::AlignCenter);
    m_meta->setWordWrap(true);
    m_meta->setTextInteractionFlags(Qt::TextSelectableByMouse);

    /* Empty placeholder. */
    m_empty = new QLabel(tr("(nothing selected)"), m_stack);
    m_empty->setAlignment(Qt::AlignCenter);
    m_empty->setStyleSheet(QStringLiteral("QLabel { color: palette(mid); }"));

    m_stack->addWidget(m_empty);      /* index 0 */
    m_stack->addWidget(m_imgScroll);  /* index 1 */
    m_stack->addWidget(m_text);       /* index 2 */
    m_stack->addWidget(m_meta);       /* index 3 */
    m_stack->setCurrentWidget(m_empty);

    setWidget(m_stack);
    setMinimumWidth(PRESET_WIDTHS[0]);

    /* Hover popup — frameless top-level label that floats over the UI. */
    m_hoverPopup = new QLabel(nullptr,
        Qt::Window | Qt::FramelessWindowHint |
        Qt::WindowStaysOnTopHint | Qt::WindowDoesNotAcceptFocus);
    m_hoverPopup->setAlignment(Qt::AlignCenter);
    m_hoverPopup->setStyleSheet(
        QStringLiteral("QLabel { background: #1a1a1a; border: 1px solid #606060; padding: 4px; }"));
    m_hoverPopup->hide();

    /* Timer that delays showing the popup after the cursor enters the image. */
    m_hoverTimer = new QTimer(this);
    m_hoverTimer->setSingleShot(true);
    connect(m_hoverTimer, &QTimer::timeout, this, &PreviewPane::showHoverPopup);

    m_imgLabel->installEventFilter(this);
}

/* ------------------------------------------------------------------ */
/* Size presets                                                         */
/* ------------------------------------------------------------------ */

void PreviewPane::setSizePreset(int preset)
{
    preset = qBound(0, preset, NUM_PRESETS - 1);
    if (preset == m_sizePreset) return;
    m_sizePreset = preset;
    setMinimumWidth(PRESET_WIDTHS[preset]);
    emit sizePresetChanged(preset, PRESET_WIDTHS[preset]);
}

void PreviewPane::stepPreset(int delta)
{
    setSizePreset(m_sizePreset + delta);
}

/* ------------------------------------------------------------------ */
/* Content display                                                      */
/* ------------------------------------------------------------------ */

void PreviewPane::clear() {
    m_current.clear();
    m_fullPixmap = QPixmap();
    m_imgLabel->clear();
    m_text->clear();
    m_meta->clear();
    m_stack->setCurrentWidget(m_empty);
    hideHoverPopup();
}

bool PreviewPane::isImage(const QString &path) {
    static const QSet<QString> exts = {
        "png","jpg","jpeg","gif","bmp","webp","tif","tiff","svg","ico"
    };
    return exts.contains(QFileInfo(path).suffix().toLower());
}

bool PreviewPane::isText(const QString &path) {
    static const QSet<QString> exts = {
        "txt","md","markdown","log","ini","cfg","conf","json","yaml","yml","toml",
        "xml","html","htm","csv","tsv","py","c","cpp","cc","h","hpp","hxx","m","mm",
        "cs","java","js","ts","tsx","jsx","go","rs","rb","php","sh","bash","zsh",
        "ps1","bat","cmd","sql","pro","cmake","qml","make"
    };
    return exts.contains(QFileInfo(path).suffix().toLower());
}

void PreviewPane::showPath(const QString &path) {
    if (path == m_current) return;
    m_current = path;
    hideHoverPopup();
    if (path.isEmpty()) { clear(); return; }

    QFileInfo fi(path);
    if (!fi.exists() || fi.isDir()) { showMetadata(path); return; }

    if (isImage(path))      showImage(path);
    else if (isText(path))  showText(path);
    else                    showMetadata(path);
}

void PreviewPane::showImage(const QString &path) {
    QImageReader r(path);
    r.setAutoTransform(true);
    const QImage img = r.read();
    if (img.isNull()) { showMetadata(path); return; }

    m_fullPixmap = QPixmap::fromImage(img);

    const QSize viewSize = m_imgScroll->viewport()->size();
    QPixmap pix = m_fullPixmap;
    if (pix.width() > viewSize.width() || pix.height() > viewSize.height()) {
        pix = pix.scaled(viewSize, Qt::KeepAspectRatio, Qt::SmoothTransformation);
    }
    m_imgLabel->setPixmap(pix);
    m_imgLabel->resize(pix.size());
    m_stack->setCurrentWidget(m_imgScroll);
}

void PreviewPane::showText(const QString &path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) { showMetadata(path); return; }

    const qint64 MAX_BYTES = 128 * 1024; /* 128 KiB */
    const QByteArray bytes = f.read(MAX_BYTES);
    /* Bail out if it's binary — rough heuristic: if >10 % of first 2 KiB
     * is control/NUL bytes, treat as binary and fall back. */
    int bad = 0;
    const int sample = qMin<int>(bytes.size(), 2048);
    for (int i = 0; i < sample; ++i) {
        unsigned char c = static_cast<unsigned char>(bytes[i]);
        if (c == 0 || (c < 0x20 && c != '\t' && c != '\n' && c != '\r')) ++bad;
    }
    if (sample > 0 && bad * 10 > sample) { showMetadata(path); return; }

    QString text = QString::fromUtf8(bytes);
    if (f.size() > MAX_BYTES) {
        text += QStringLiteral("\n\n— truncated — showing first %1 KiB of %2 KiB —\n")
                    .arg(MAX_BYTES / 1024).arg(f.size() / 1024);
    }
    m_text->setPlainText(text);
    m_stack->setCurrentWidget(m_text);
}

void PreviewPane::showMetadata(const QString &path) {
    QFileInfo fi(path);
    QLocale loc;
    QString kind;
    if (!fi.exists())       kind = tr("(missing)");
    else if (fi.isSymLink())kind = tr("Symlink → %1").arg(fi.symLinkTarget());
    else if (fi.isDir())    kind = tr("Directory");
    else                    kind = tr("File");

    QString size = fi.isDir() ? QString() : loc.formattedDataSize(fi.size());

    QString html = tr(
        "<div style='text-align:left; padding:16px;'>"
        "<h3>%1</h3>"
        "<p><b>Path:</b> %2</p>"
        "<p><b>Type:</b> %3</p>"
        "%4"
        "<p><b>Modified:</b> %5</p>"
        "<p style='color:gray; font-size:smaller;'>No inline preview for this file type.</p>"
        "</div>")
        .arg(fi.fileName().toHtmlEscaped())
        .arg(fi.absoluteFilePath().toHtmlEscaped())
        .arg(kind.toHtmlEscaped())
        .arg(size.isEmpty() ? QString()
                            : tr("<p><b>Size:</b> %1</p>").arg(size))
        .arg(loc.toString(fi.lastModified(), QLocale::ShortFormat));
    m_meta->setText(html);
    m_meta->setTextFormat(Qt::RichText);
    m_stack->setCurrentWidget(m_meta);
}

/* ------------------------------------------------------------------ */
/* Hover popup                                                          */
/* ------------------------------------------------------------------ */

bool PreviewPane::eventFilter(QObject *obj, QEvent *event)
{
    if (obj == m_imgLabel) {
        if (event->type() == QEvent::Enter) {
            m_hoverTimer->start(400);
        } else if (event->type() == QEvent::Leave) {
            m_hoverTimer->stop();
            hideHoverPopup();
        }
    }
    return QDockWidget::eventFilter(obj, event);
}

void PreviewPane::showHoverPopup()
{
    /* Only show when not already at the largest preset and image is loaded. */
    if (m_sizePreset >= NUM_PRESETS - 1 || m_fullPixmap.isNull()) return;

    const QScreen *screen = QGuiApplication::screenAt(QCursor::pos());
    if (!screen) return;
    const QSize avail = screen->availableSize();

    /* Cap at 80 % of the screen in each dimension. */
    const int maxW = static_cast<int>(avail.width()  * 0.80);
    const int maxH = static_cast<int>(avail.height() * 0.80);

    QPixmap scaled = m_fullPixmap;
    if (scaled.width() > maxW || scaled.height() > maxH)
        scaled = m_fullPixmap.scaled(maxW, maxH, Qt::KeepAspectRatio, Qt::SmoothTransformation);

    m_hoverPopup->setPixmap(scaled);
    /* +10 px padding on each side from the style sheet (4 px padding + 1 px border × 2). */
    m_hoverPopup->resize(scaled.width() + 10, scaled.height() + 10);

    /* Position near cursor, nudged so it stays on screen. */
    QPoint pos = QCursor::pos() + QPoint(20, 20);
    const QRect popupRect(pos, m_hoverPopup->size());
    const QRect screenRect(screen->availableGeometry());
    if (popupRect.right()  > screenRect.right())
        pos.setX(QCursor::pos().x() - m_hoverPopup->width() - 20);
    if (popupRect.bottom() > screenRect.bottom())
        pos.setY(QCursor::pos().y() - m_hoverPopup->height() - 20);
    m_hoverPopup->move(pos);
    m_hoverPopup->show();
}

void PreviewPane::hideHoverPopup()
{
    m_hoverPopup->hide();
}
