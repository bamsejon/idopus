#include "BreadcrumbBar.h"

#include <QHBoxLayout>
#include <QLabel>
#include <QStringList>
#include <QToolButton>

BreadcrumbBar::BreadcrumbBar(QWidget *parent) : QWidget(parent) {
    m_layout = new QHBoxLayout(this);
    m_layout->setContentsMargins(2, 1, 2, 1);
    m_layout->setSpacing(1);
    m_layout->addStretch(1);
}

void BreadcrumbBar::clearButtons() {
    while (m_layout->count() > 0) {
        auto *it = m_layout->takeAt(0);
        if (auto *w = it->widget()) w->deleteLater();
        delete it;
    }
}

QToolButton *BreadcrumbBar::makeSegment(const QString &label, const QString &path) {
    auto *b = new QToolButton(this);
    b->setText(label);
    b->setAutoRaise(true);
    b->setFocusPolicy(Qt::NoFocus);
    b->setStyleSheet(QStringLiteral(
        "QToolButton { padding: 2px 6px; border-radius: 3px; }"
        "QToolButton:hover { background-color: palette(highlight); color: palette(highlighted-text); }"));
    connect(b, &QToolButton::clicked, this, [this, path]{ emit pathPicked(path); });
    return b;
}

void BreadcrumbBar::setPath(const QString &path) {
    clearButtons();

    /* Normalize separators to forward slash for splitting. Windows paths
     * come in as C:\Foo\Bar or C:/Foo/Bar; both work. */
    QString norm = path;
    norm.replace(QLatin1Char('\\'), QLatin1Char('/'));

#ifdef Q_OS_WIN
    /* Drive root: "C:" + path after "C:/" */
    QString rootLabel, rootPath;
    if (norm.size() >= 2 && norm[1] == QLatin1Char(':')) {
        rootLabel = norm.left(2);                    /* "C:"  */
        rootPath  = rootLabel + QLatin1Char('/');    /* "C:/" */
        norm = norm.mid(rootPath.size() - 1);        /* strip "C:" */
    } else {
        rootLabel = QStringLiteral("/");
        rootPath  = QStringLiteral("/");
    }
#else
    const QString rootLabel = QStringLiteral("/");
    const QString rootPath  = QStringLiteral("/");
#endif

    m_layout->addWidget(makeSegment(rootLabel, rootPath));

    /* Split the remaining path on '/', dropping empties. */
    const QStringList parts = norm.split(QLatin1Char('/'), Qt::SkipEmptyParts);
    QString accum = rootPath;
    for (int i = 0; i < parts.size(); ++i) {
        auto *sep = new QLabel(QStringLiteral(" › "), this);
        sep->setStyleSheet(QStringLiteral("QLabel { color: palette(mid); }"));
        m_layout->addWidget(sep);
        if (accum.endsWith(QLatin1Char('/'))) accum += parts[i];
        else                                  accum += QLatin1Char('/') + parts[i];
        m_layout->addWidget(makeSegment(parts[i], accum));
    }
    m_layout->addStretch(1);
}
